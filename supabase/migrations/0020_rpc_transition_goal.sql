-- 0020 — RPC de transition d'etat, appelee par les Edge Functions
--
-- `functions/_shared/db.ts` l'appelait deja sans qu'elle existe : toute Edge
-- Function ecrite l'aurait ete contre une fonction absente.
--
-- Cette RPC ne juge PAS de la legalite de la transition. C'est le trigger
-- `goals_enforce_transition` (0015) qui l'impose, et il doit rester la seule
-- table de verite : recopier ici les couples autorises creerait un second
-- jeu de regles qui divergerait tot ou tard, sur le chemin de l'argent.
--
-- Son role est plus etroit : attribuer la transition a un acteur pour le
-- journal d'audit, et poser dans le meme mouvement les instants calcules par
-- le serveur, sans jamais laisser une fonction ecrire ailleurs.

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
  -- Seules colonnes qu'une Edge Function peut ecrire au fil du cycle de vie.
  -- Tout le reste — la promesse, la mise, la planification — est fige des
  -- l'engagement (voir app.freeze_committed_goal).
  c_writable constant text[] := array[
    'window_fire_at',
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

  -- Liste blanche stricte plutot que du SQL dynamique. Une cle inconnue est
  -- refusee et non ignoree : une faute de frappe dans une Edge Function
  -- passerait sinon inapercue, et l'echeance qu'elle croit poser ne serait
  -- jamais ecrite — un objectif que l'utilisateur ne pourrait plus prouver.
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

  -- Deja dans l'etat vise : on ne fait rien et on ne remonte pas d'erreur.
  -- Les Edge Functions sont declenchees par des crons et des webhooks, qui
  -- rejouent. Une reprise ne doit pas echouer sur un travail deja fait.
  if v_goal.state = p_to_state then
    return;
  end if;

  perform set_config('app.actor', p_actor, true);
  perform set_config('app.transition_reason', p_reason, true);

  -- coalesce : un champ absent de p_fields garde sa valeur. Ces instants ne
  -- sont jamais remis a null une fois poses, donc l'impossibilite de les
  -- effacer par ici est voulue.
  update public.goals
  set state               = p_to_state,
      window_fire_at      = coalesce((p_fields->>'window_fire_at')::timestamptz, window_fire_at),
      window_opened_at    = coalesce((p_fields->>'window_opened_at')::timestamptz, window_opened_at),
      proof_deadline_at   = coalesce((p_fields->>'proof_deadline_at')::timestamptz, proof_deadline_at),
      dispute_deadline_at = coalesce((p_fields->>'dispute_deadline_at')::timestamptz, dispute_deadline_at),
      review_deadline_at  = coalesce((p_fields->>'review_deadline_at')::timestamptz, review_deadline_at),
      closed_at           = coalesce((p_fields->>'closed_at')::timestamptz, closed_at),
      human_review_reason = coalesce(p_fields->>'human_review_reason', human_review_reason)
  where id = p_goal_id;
end;
$$;

-- Jamais exposee au client : un utilisateur qui pourrait l'appeler passerait
-- son propre objectif de 'ai_verifying' a 'validated' — il validerait sa
-- propre preuve et annulerait sa mise. Les transitions venant du telephone
-- passent par commit_goal, seule RPC accordee au role authenticated.
--
-- Les trois revoke sont necessaires, et pas seulement celui sur `public` :
-- Supabase accorde execute sur toute nouvelle fonction du schema public a
-- `anon` et `authenticated` par privileges par defaut. Ces droits-la sont
-- nominatifs et survivent au revoke sur `public`. Verifie par le test 12 de
-- 03_transition_goal_test.sql, qui echouait avant cette correction.
revoke all on function public.transition_goal from public;
revoke all on function public.transition_goal from anon;
revoke all on function public.transition_goal from authenticated;
grant execute on function public.transition_goal to service_role;

comment on function public.transition_goal is
  'Change l''etat d''un objectif au nom d''un acteur, en posant au passage les instants calcules par le serveur. Reservee aux Edge Functions. La legalite de la transition reste imposee par le trigger de 0015.';
