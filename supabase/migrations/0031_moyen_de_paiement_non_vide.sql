-- 0031 — Un moyen de paiement vide n'est pas un moyen de paiement
--
-- `begin_stake_charge` (0029) refusait un `default_payment_method_id` nul,
-- mais laissait passer une chaine vide. Le debit partait alors vers Stripe
-- avec `payment_method=""`, qui repond « You passed an empty string for
-- 'payment_method' » — un message qui ne dit rien de ce qui s'est reellement
-- passe, et l'objectif restait bloque en `charge_pending`.
--
-- Constate en montant un essai contre le vrai Stripe, ou une chaine vide
-- s'est glissee dans le profil. En production, seul le webhook ecrit cette
-- colonne et il y met toujours un identifiant valide : le cas ne devrait pas
-- se produire. Mais sur un chemin qui deplace de l'argent, une garde qui
-- transforme une erreur incomprehensible en refus clair coute deux lignes.

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

  -- La chaine vide est aussi peu utilisable qu'un nul : la refuser ici plutot
  -- que de laisser Stripe s'en plaindre.
  if v_profile.default_payment_method_id is null
     or btrim(v_profile.default_payment_method_id) = '' then
    raise exception 'Aucun moyen de paiement enregistre' using errcode = 'check_violation';
  end if;

  if v_profile.stripe_customer_id is null
     or btrim(v_profile.stripe_customer_id) = '' then
    raise exception 'Aucun client Stripe rattache' using errcode = 'check_violation';
  end if;

  -- Rejouable : une reprise apres coupure retrouve la ligne deja creee plutot
  -- que d'en fabriquer une seconde.
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

revoke all on function public.begin_stake_charge(uuid) from public;
revoke all on function public.begin_stake_charge(uuid) from anon;
revoke all on function public.begin_stake_charge(uuid) from authenticated;
grant execute on function public.begin_stake_charge(uuid) to service_role;
