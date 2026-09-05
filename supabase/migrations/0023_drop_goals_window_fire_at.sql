-- 0023 — L'instant du controle n'a plus qu'un seul domicile
--
-- La migration 0022 cachait `goals.window_fire_at` au client en retirant le
-- droit de lecture au niveau de la table pour le rendre colonne par colonne.
-- Correct en SQL, inutilisable en pratique : PostgREST emet un `select *`
-- sous le capot meme quand la requete nomme ses colonnes, et toute lecture
-- de `goals` par l'application echouait avec « permission denied ».
--
-- Le detour n'avait de toute facon pas lieu d'etre. L'instant du controle
-- vit deja dans `notification_schedule.fire_at`, table concue pour lui et
-- correctement protegee (aucune policy de lecture, cf. 0012). La colonne de
-- `goals` en etait un double, jamais ecrit par personne — et c'est ce double
-- qui fuyait.
--
-- Un fait, un endroit. Supprimer la colonne fait disparaitre la fuite au
-- lieu de la masquer, et epargne au prochain qui ajoutera une colonne a
-- `goals` d'avoir a se demander s'il vient de rouvrir la porte.

-- L'index de balayage disparait avec elle : le cron parcourt la file de
-- notifications, qui a le sien (notification_pending_idx).
drop index if exists public.goals_state_fire_idx;

alter table public.goals drop column if exists window_fire_at;

-- Les droits de table retires par 0022 sont rendus : il n'y a plus de
-- colonne sensible dans `goals`, et la RLS suffit a filtrer les lignes.
grant select, insert, update on public.goals to authenticated;

-- `anon` reste sans droits sur les objectifs. La RLS le bloquait deja, mais
-- une permission qui dit la meme chose que la policy vaut mieux qu'une
-- permission large corrigee plus loin.

comment on table public.goals is
  'Objectifs. L''instant du controle surprise n''est pas ici : il vit dans notification_schedule.fire_at, hors de portee du client (invariant 4).';

-- `transition_goal` (0020) nommait la colonne disparue dans sa liste blanche
-- et dans son UPDATE : sans cette reecriture, toute transition echouerait.
-- Les deux changements sont solidaires et doivent voyager ensemble.
create or replace function public.transition_goal(
  p_goal_id uuid,
  p_to_state goal_state,
  p_actor text,
  p_reason text,
  p_fields jsonb default '{}'::jsonb
)
returns void
language plpgsql
security definer
set search_path = public, app
as $$
declare
  c_writable constant text[] := array[
    'window_opened_at',
    'proof_deadline_at',
    'dispute_deadline_at',
    'review_deadline_at',
    'closed_at',
    'human_review_reason'
  ];
  v_goal public.goals%rowtype;
  v_unknown text[];
begin
  if p_actor is null or btrim(p_actor) = '' then
    raise exception 'Un acteur est requis : le journal d''audit doit dire qui a decide'
      using errcode = 'check_violation';
  end if;

  if p_reason is null or btrim(p_reason) = '' then
    raise exception 'Une raison est requise pour tracer la transition'
      using errcode = 'check_violation';
  end if;

  select array_agg(k) into v_unknown
  from jsonb_object_keys(coalesce(p_fields, '{}'::jsonb)) as k
  where k <> all (c_writable);

  if v_unknown is not null then
    raise exception 'Champs non modifiables par une transition : %',
      array_to_string(v_unknown, ', ')
      using errcode = 'check_violation';
  end if;

  select * into v_goal from public.goals where id = p_goal_id for update;

  if not found then
    raise exception 'Objectif % introuvable', p_goal_id using errcode = 'no_data_found';
  end if;

  if v_goal.state = p_to_state then
    return;
  end if;

  perform set_config('app.actor', p_actor, true);
  perform set_config('app.transition_reason', p_reason, true);

  update public.goals
  set state               = p_to_state,
      window_opened_at    = coalesce((p_fields->>'window_opened_at')::timestamptz, window_opened_at),
      proof_deadline_at   = coalesce((p_fields->>'proof_deadline_at')::timestamptz, proof_deadline_at),
      dispute_deadline_at = coalesce((p_fields->>'dispute_deadline_at')::timestamptz, dispute_deadline_at),
      review_deadline_at  = coalesce((p_fields->>'review_deadline_at')::timestamptz, review_deadline_at),
      closed_at           = coalesce((p_fields->>'closed_at')::timestamptz, closed_at),
      human_review_reason = coalesce(p_fields->>'human_review_reason', human_review_reason)
  where id = p_goal_id;
end;
$$;

revoke all on function public.transition_goal from public;
revoke all on function public.transition_goal from anon;
revoke all on function public.transition_goal from authenticated;
grant execute on function public.transition_goal to service_role;
