-- 0029 — Cycle de vie d'un debit
--
-- Le webhook Stripe et la fonction d'encaissement pourraient ecrire
-- directement dans `charges` et `profiles` : le service role traverse la RLS
-- et le trigger `protect_profile_columns` ne vise que `authenticated`/`anon`.
-- On passe quand meme par des RPC, pour trois raisons.
--
--   1. Un debit touche trois tables — `charges`, `stakes`, `profiles` — plus
--      l'etat de l'objectif. Fait a la main, l'ensemble peut se retrouver a
--      moitie applique si la fonction meurt entre deux requetes.
--   2. Le partage avec l'association doit etre fige au moment du debit, avec
--      `app.split_stake()`, et jamais recalcule ensuite : le bareme peut
--      changer, la ligne de comptabilite non.
--   3. Les webhooks rejouent. Chaque fonction est donc idempotente, comme
--      `transition_goal` (0020).
--
-- Rien ici ne decide QUE debiter : la decision appartient a la machine a
-- etats, qui a deja fait passer l'objectif en `closed_failed`. Ces fonctions
-- executent, elles ne jugent pas.


-- ------------------------------------------------------- ouverture du debit

-- Prepare le debit d'une mise perdue et rend de quoi appeler Stripe.
--
-- Cree la ligne de `charges` avec le partage fige, et fait passer l'objectif
-- en `charge_pending`. L'appelant cree ensuite le PaymentIntent et rappelle
-- `attach_charge_intent`.
create or replace function public.begin_stake_charge(p_goal_id uuid)
returns table (
  charge_id uuid,
  user_id uuid,
  stripe_customer_id text,
  payment_method_id text,
  amount_cents int,
  attempt_count int
)
language plpgsql
security definer
set search_path = public, app
as $$
declare
  v_goal public.goals%rowtype;
  v_stake public.stakes%rowtype;
  v_profile public.profiles%rowtype;
  v_charge public.charges%rowtype;
  v_split record;
begin
  select * into v_goal from public.goals where id = p_goal_id for update;
  if not found then
    raise exception 'Objectif % introuvable', p_goal_id using errcode = 'no_data_found';
  end if;

  -- On n'encaisse que ce que la machine a etats a declare perdu. Un objectif
  -- encore contestable, ou deja encaisse, n'a rien a faire ici.
  --
  -- `charge_pending` est accepte : c'est l'etat que laisse une coupure reseau
  -- au milieu d'un appel a Stripe, et la reprise doit pouvoir repartir de la.
  -- `charge_failed` aussi : c'est la sortie du blocage, apres mise a jour du
  -- moyen de paiement.
  if v_goal.state not in ('closed_failed', 'charge_failed', 'charge_pending') then
    raise exception 'L''objectif % n''est pas encaissable (etat : %)', p_goal_id, v_goal.state
      using errcode = 'check_violation';
  end if;

  select * into v_stake from public.stakes where goal_id = p_goal_id for update;
  if not found then
    raise exception 'Aucune mise sur l''objectif %', p_goal_id using errcode = 'no_data_found';
  end if;

  select * into v_profile from public.profiles where profiles.user_id = v_goal.user_id for update;

  if v_profile.default_payment_method_id is null then
    raise exception 'Aucun moyen de paiement enregistre' using errcode = 'check_violation';
  end if;

  -- Rejouable : une reprise apres coupure retrouve la ligne deja creee plutot
  -- que d'en fabriquer une seconde. L'index unique sur goal_id l'interdirait
  -- de toute facon, mais echouer serait inutilement brutal.
  select * into v_charge from public.charges where goal_id = p_goal_id for update;

  if not found then
    select * into v_split from app.split_stake(v_stake.amount_cents, v_stake.charity_bps);

    insert into public.charges
      (goal_id, stake_id, user_id, amount_cents, currency,
       charity_bps, charity_id, charity_amount_cents, company_amount_cents,
       status)
    values
      (p_goal_id, v_stake.id, v_goal.user_id, v_stake.amount_cents, v_stake.currency,
       v_stake.charity_bps, v_goal.charity_id,
       v_split.charity_amount_cents, v_split.company_amount_cents,
       'pending')
    returning * into v_charge;
  end if;

  update public.charges
  set attempt_count = charges.attempt_count + 1,
      last_attempt_at = now(),
      status = 'processing'
  where id = v_charge.id
  returning * into v_charge;

  perform public.transition_goal(
    p_goal_id, 'charge_pending', 'stripe',
    'encaissement de la mise perdue'
  );

  return query select
    v_charge.id, v_goal.user_id, v_profile.stripe_customer_id,
    v_profile.default_payment_method_id, v_charge.amount_cents, v_charge.attempt_count;
end;
$$;

comment on function public.begin_stake_charge is
  'Prepare le debit d''une mise perdue : fige le partage, cree la charge, passe l''objectif en charge_pending. Idempotente.';


-- Rattache le PaymentIntent cree cote Stripe.
--
-- Ecrase toujours l'identifiant precedent, et c'est essentiel. Une relance
-- apres echec cree un NOUVEAU PaymentIntent : garder l'ancien laisserait la
-- charge pointee sur une tentative morte, et le webhook du paiement reussi ne
-- trouverait aucune ligne a solder. L'argent serait preleve chez
-- l'utilisateur sans que rien ne l'enregistre — ni la mise marquee, ni le
-- solde du diminue, ni le blocage leve.
--
-- Trouve en executant le test 09, pas en relisant : chaque garde semblait
-- prudente isolement.
--
-- Consequence assumee : un webhook tardif portant sur une tentative
-- precedente ne trouve plus sa charge et devient sans effet. C'est le
-- comportement voulu — cette tentative-la est superseded.
create or replace function public.attach_charge_intent(
  p_charge_id uuid,
  p_payment_intent_id text
)
returns void
language plpgsql
security definer
set search_path = public, app
as $$
begin
  update public.charges
  set stripe_payment_intent_id = p_payment_intent_id
  where id = p_charge_id;
end;
$$;


-- ------------------------------------------------------------ denouement

-- Le debit a abouti.
create or replace function public.settle_charge_succeeded(
  p_payment_intent_id text
)
returns void
language plpgsql
security definer
set search_path = public, app
as $$
declare
  v_charge public.charges%rowtype;
  v_profile public.profiles%rowtype;
begin
  select * into v_charge from public.charges
  where stripe_payment_intent_id = p_payment_intent_id for update;

  if not found then
    raise warning 'Aucune charge pour le PaymentIntent %', p_payment_intent_id;
    return;
  end if;

  -- Rejeu d'un webhook deja traite : on sort sans rien changer.
  if v_charge.status = 'succeeded' then
    return;
  end if;

  update public.charges
  set status = 'succeeded', succeeded_at = now(),
      failure_code = null, failure_message = null
  where id = v_charge.id;

  update public.stakes set status = 'charged' where id = v_charge.stake_id;

  select * into v_profile from public.profiles
  where profiles.user_id = v_charge.user_id for update;

  -- Le solde du diminue de ce qui vient d'etre encaisse. Le blocage ne se
  -- leve que si plus rien n'est du ET qu'une carte valide est en place :
  -- c'est la regle decidee le 2026-09-02.
  update public.profiles
  set outstanding_balance_cents = greatest(
        0, profiles.outstanding_balance_cents - v_charge.amount_cents),
      stake_block_active = case
        when greatest(0, profiles.outstanding_balance_cents - v_charge.amount_cents) = 0
             and profiles.default_payment_method_id is not null
        then false else profiles.stake_block_active end,
      stake_block_reason = case
        when greatest(0, profiles.outstanding_balance_cents - v_charge.amount_cents) = 0
             and profiles.default_payment_method_id is not null
        then null else profiles.stake_block_reason end,
      stake_block_since = case
        when greatest(0, profiles.outstanding_balance_cents - v_charge.amount_cents) = 0
             and profiles.default_payment_method_id is not null
        then null else profiles.stake_block_since end
  where profiles.user_id = v_charge.user_id;

  perform public.transition_goal(
    v_charge.goal_id, 'charge_ok', 'stripe', 'mise encaissee'
  );
end;
$$;

comment on function public.settle_charge_succeeded is
  'Encaissement abouti : charge soldee, mise marquee, solde du diminue, blocage leve si plus rien n''est du. Idempotente.';


-- Le debit a echoue, ou la banque exige une authentification.
--
-- Decision du 2026-09-06 : une SCA exigee est traitee comme un echec de
-- carte. Le montant devient un solde du et la creation d'objectifs est gelee,
-- exactement comme pour une carte refusee. La distinction reste visible dans
-- `charges.status` ('requires_action' contre 'failed') pour le diagnostic et
-- pour le message affiche a l'utilisateur, qui n'est pas le meme : dans un
-- cas il doit changer de carte, dans l'autre il doit confirmer aupres de sa
-- banque.
--
-- Le blocage doit rester levable : la sortie passe par une nouvelle tentative
-- en session (`stripe-charge-stake` rappelee apres mise a jour du moyen de
-- paiement), qui aboutira a `settle_charge_succeeded`.
create or replace function public.settle_charge_failed(
  p_payment_intent_id text,
  p_failure_code text default null,
  p_failure_message text default null,
  p_requires_action boolean default false
)
returns void
language plpgsql
security definer
set search_path = public, app
as $$
declare
  v_charge public.charges%rowtype;
begin
  select * into v_charge from public.charges
  where stripe_payment_intent_id = p_payment_intent_id for update;

  if not found then
    raise warning 'Aucune charge pour le PaymentIntent %', p_payment_intent_id;
    return;
  end if;

  if v_charge.status in ('failed', 'requires_action', 'succeeded') then
    return;
  end if;

  update public.charges
  set status = case when p_requires_action then 'requires_action' else 'failed' end::charge_status,
      failure_code = p_failure_code,
      failure_message = left(p_failure_message, 500)
  where id = v_charge.id;

  update public.profiles
  set outstanding_balance_cents = profiles.outstanding_balance_cents + v_charge.amount_cents,
      stake_block_active = true,
      stake_block_reason = case
        when p_requires_action then 'authentification bancaire requise'
        else coalesce(p_failure_code, 'debit refuse') end,
      stake_block_since = coalesce(profiles.stake_block_since, now())
  where profiles.user_id = v_charge.user_id;

  perform public.transition_goal(
    v_charge.goal_id, 'charge_failed', 'stripe',
    coalesce(p_failure_code, 'debit refuse')
  );
end;
$$;

comment on function public.settle_charge_failed is
  'Echec d''encaissement, SCA comprise : solde du augmente, creation d''objectifs gelee. Idempotente.';


-- --------------------------------------------- enregistrement du moyen de paiement

-- Pose le moyen de paiement par defaut apres un SetupIntent abouti.
--
-- Passe par une RPC plutot qu'un UPDATE direct parce que l'operation peut
-- lever le blocage : quelqu'un dont la carte avait expire et qui en enregistre
-- une neuve doit pouvoir reprendre, si son solde est a zero.
create or replace function public.set_default_payment_method(
  p_user_id uuid,
  p_customer_id text,
  p_payment_method_id text,
  p_last4 text default null,
  p_brand text default null,
  p_exp_month int default null,
  p_exp_year int default null
)
returns void
language plpgsql
security definer
set search_path = public, app
as $$
begin
  update public.profiles
  set stripe_customer_id = coalesce(profiles.stripe_customer_id, p_customer_id),
      default_payment_method_id = p_payment_method_id,
      pm_last4 = p_last4,
      pm_brand = p_brand,
      pm_exp_month = p_exp_month,
      pm_exp_year = p_exp_year,
      -- Une carte neuve ne solde pas ce qui est du. Le blocage ne tombe que
      -- si le solde est deja a zero — sinon il faut d'abord payer.
      stake_block_active = case
        when profiles.outstanding_balance_cents = 0 then false
        else profiles.stake_block_active end,
      stake_block_reason = case
        when profiles.outstanding_balance_cents = 0 then null
        else profiles.stake_block_reason end,
      stake_block_since = case
        when profiles.outstanding_balance_cents = 0 then null
        else profiles.stake_block_since end
  where profiles.user_id = p_user_id;
end;
$$;

comment on function public.set_default_payment_method is
  'Enregistre le moyen de paiement par defaut. Leve le blocage si plus rien n''est du.';


-- Rattache l'identifiant client Stripe, sans toucher au reste.
create or replace function public.set_stripe_customer(
  p_user_id uuid,
  p_customer_id text
)
returns void
language plpgsql
security definer
set search_path = public, app
as $$
begin
  update public.profiles
  set stripe_customer_id = p_customer_id
  where profiles.user_id = p_user_id
    and profiles.stripe_customer_id is null;
end;
$$;


-- ----------------------------------------------------------------- droits
--
-- Aucune de ces fonctions n'est appelable par un client : elles deplacent de
-- l'argent. Revocation nominative, lecon de 0020 — les privileges par defaut
-- de Supabase sont accordes nommement a `anon` et `authenticated`, et un
-- revoke sur `public` ne les entame pas.

do $$
declare
  v_signature text;
begin
  foreach v_signature in array array[
    'public.begin_stake_charge(uuid)',
    'public.attach_charge_intent(uuid, text)',
    'public.settle_charge_succeeded(text)',
    'public.settle_charge_failed(text, text, text, boolean)',
    'public.set_default_payment_method(uuid, text, text, text, text, int, int)',
    'public.set_stripe_customer(uuid, text)'
  ]
  loop
    execute format('revoke all on function %s from public', v_signature);
    execute format('revoke all on function %s from anon', v_signature);
    execute format('revoke all on function %s from authenticated', v_signature);
    execute format('grant execute on function %s to service_role', v_signature);
  end loop;
end;
$$;
