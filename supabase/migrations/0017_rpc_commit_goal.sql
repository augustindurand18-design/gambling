-- 0017 — RPC d'engagement d'un objectif
--
-- Le passage draft -> committed est le moment ou l'utilisateur met son argent
-- en jeu. Il doit etre atomique : mise + consentement + transition, ou rien.
-- Les policies RLS interdisent volontairement l'UPDATE direct vers 'committed'.

create or replace function public.commit_goal(
  p_goal_id uuid,
  p_amount_cents int,
  p_charity_id uuid,
  p_charity_bps int,
  p_terms_version text,
  p_terms_hash text,
  p_consent_payload jsonb,
  p_app_version text default null,
  p_platform text default 'ios'
)
returns uuid
language plpgsql
security definer
set search_path = public, app, extensions
as $$
declare
  v_user_id uuid := auth.uid();
  v_goal public.goals%rowtype;
  v_profile public.profiles%rowtype;
  v_month_total int;
  v_stake_id uuid;
begin
  if v_user_id is null then
    raise exception 'Authentification requise' using errcode = 'insufficient_privilege';
  end if;

  select * into v_profile from public.profiles where user_id = v_user_id for update;
  if not found then
    raise exception 'Profil introuvable' using errcode = 'no_data_found';
  end if;

  -- Regle metier : un incident de paiement non regle gele la creation de
  -- nouveaux engagements (les objectifs deja en cours, eux, continuent).
  if v_profile.stake_block_active then
    raise exception
      'Impossible d''engager un nouvel objectif : une mise reste a regler. Mets ta carte a jour.'
      using errcode = 'check_violation';
  end if;

  if v_profile.default_payment_method_id is null then
    raise exception 'Aucun moyen de paiement enregistre'
      using errcode = 'check_violation';
  end if;

  select * into v_goal
  from public.goals
  where id = p_goal_id and user_id = v_user_id
  for update;

  if not found then
    raise exception 'Objectif introuvable' using errcode = 'no_data_found';
  end if;

  if v_goal.state <> 'draft' then
    raise exception 'Cet objectif est deja engage' using errcode = 'check_violation';
  end if;

  -- Plafonds acceptes a l'onboarding
  if p_amount_cents <= 0 then
    raise exception 'Le montant doit etre positif' using errcode = 'check_violation';
  end if;

  if p_amount_cents > v_profile.per_goal_cap_cents then
    raise exception
      'Mise superieure au plafond par objectif (% centimes)', v_profile.per_goal_cap_cents
      using errcode = 'check_violation';
  end if;

  select coalesce(sum(s.amount_cents), 0) into v_month_total
  from public.stakes s
  where s.user_id = v_user_id
    and s.status = 'active'
    and s.created_at >= date_trunc('month', now());

  if v_month_total + p_amount_cents > v_profile.monthly_cap_cents then
    raise exception
      'Plafond mensuel atteint (% centimes engages sur % autorises)',
      v_month_total, v_profile.monthly_cap_cents
      using errcode = 'check_violation';
  end if;

  -- La fenetre de preuve doit encore etre a venir
  if v_goal.target_date < (now() at time zone v_goal.timezone)::date then
    raise exception 'La date de l''objectif est deja passee' using errcode = 'check_violation';
  end if;

  insert into public.stakes
    (goal_id, user_id, amount_cents, charity_bps, charity_id, status)
  values
    (p_goal_id, v_user_id, p_amount_cents, p_charity_bps, p_charity_id, 'active')
  returning id into v_stake_id;

  -- Trace juridique : ce que l'utilisateur a vu et accepte, a la seconde pres.
  insert into public.consents
    (user_id, consent_type, goal_id, stake_id, terms_version, terms_hash,
     payload, app_version, platform)
  values
    (v_user_id, 'stake_commitment', p_goal_id, v_stake_id, p_terms_version, p_terms_hash,
     p_consent_payload, p_app_version, p_platform);

  perform set_config('app.actor', 'user', true);
  perform set_config('app.transition_reason', 'engagement', true);

  update public.goals
  set state = 'committed',
      committed_at = now(),
      charity_id = p_charity_id
  where id = p_goal_id;

  return v_stake_id;
end;
$$;

revoke all on function public.commit_goal from public;
grant execute on function public.commit_goal to authenticated;

comment on function public.commit_goal is
  'Engage un objectif : cree la mise, enregistre le consentement horodate et passe l''objectif en committed. Atomique.';
