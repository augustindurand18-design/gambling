-- Tests pgTAP : ouverture de la fenetre de preuve.
--
-- C'est ici que demarre le compte a rebours qui met une mise en jeu. Deux
-- garanties comptent plus que les autres :
--
--   - l'ouverture est idempotente, parce que le cron repasse toutes les
--     minutes et qu'une reprise ne doit pas echouer sur un travail deja fait ;
--   - on n'ouvre pas une fenetre qu'on est incapable d'annoncer. Sans appareil
--     joignable, le compte a rebours partirait dans le vide et l'utilisateur
--     perdrait sa mise sans avoir rien su : ce serait lui faire payer notre
--     incapacite a le prevenir (invariant 2).
--
-- Execution : supabase test db

begin;
select plan(9);

create extension if not exists pgtap with schema extensions;

-- ------------------------------------------------------------- fixtures
insert into auth.users (id, email, raw_user_meta_data)
values
  ('aaaa1111-0000-0000-0000-000000000001', 'alice@test.local', '{}'::jsonb),
  ('aaaa1111-0000-0000-0000-000000000002', 'sansappareil@test.local', '{}'::jsonb);

-- Alice a un iPhone enregistre ; l'autre utilisateur n'en a aucun.
insert into public.devices (user_id, apns_token, env)
values ('aaaa1111-0000-0000-0000-000000000001', 'aa00bb11cc22', 'sandbox');

insert into public.goals
  (id, user_id, title, state, window_mode, timezone, target_date,
   window_start_local, window_end_local, committed_at)
values
  -- du, joignable
  ('bbbb2222-0000-0000-0000-000000000001',
   'aaaa1111-0000-0000-0000-000000000001',
   'Aller a la salle', 'committed', 'random_window', 'Europe/Paris',
   current_date, '07:00', '10:00', now()),
  -- pas encore du
  ('bbbb2222-0000-0000-0000-000000000002',
   'aaaa1111-0000-0000-0000-000000000001',
   'Ranger le bureau', 'committed', 'random_window', 'Europe/Paris',
   current_date, '18:00', '21:00', now()),
  -- du, mais personne a qui l'annoncer
  ('bbbb2222-0000-0000-0000-000000000003',
   'aaaa1111-0000-0000-0000-000000000002',
   'Reviser', 'committed', 'random_window', 'Europe/Paris',
   current_date, '07:00', '10:00', now());

insert into public.notification_schedule (goal_id, user_id, kind, fire_at)
values
  ('bbbb2222-0000-0000-0000-000000000001',
   'aaaa1111-0000-0000-0000-000000000001', 'proof_window_open', now() - interval '1 minute'),
  ('bbbb2222-0000-0000-0000-000000000002',
   'aaaa1111-0000-0000-0000-000000000001', 'proof_window_open', now() + interval '6 hours'),
  ('bbbb2222-0000-0000-0000-000000000003',
   'aaaa1111-0000-0000-0000-000000000002', 'proof_window_open', now() - interval '1 minute');

-- ----------------------------------------------------------- l'ouverture

select is(
  app.open_due_proof_windows(), 1,
  'Seul l''objectif du et joignable est ouvert'
);

select is(
  (select state::text from public.goals where id = 'bbbb2222-0000-0000-0000-000000000001'),
  'proof_window_open',
  'L''objectif du passe en proof_window_open'
);

select ok(
  (select window_opened_at is not null and proof_deadline_at is not null
   from public.goals where id = 'bbbb2222-0000-0000-0000-000000000001'),
  'Les deux instants dont depend l''anti-triche sont poses'
);

select is(
  (select proof_deadline_at - window_opened_at
   from public.goals where id = 'bbbb2222-0000-0000-0000-000000000001'),
  make_interval(secs => app.proof_window_seconds()),
  'L''echeance est posee a exactement un delai de soumission'
);

select is(
  (select actor from public.goal_state_transitions
   where goal_id = 'bbbb2222-0000-0000-0000-000000000001'
     and to_state = 'proof_window_open'),
  'cron:open_due_proof_windows',
  'Le journal d''audit nomme le cron, pas « system »'
);

-- ------------------------------------------------------ le non-joignable

select is(
  (select state::text from public.goals where id = 'bbbb2222-0000-0000-0000-000000000003'),
  'committed',
  'Sans appareil actif, la fenetre ne s''ouvre pas : on ne lance pas un compte a rebours muet'
);

select is(
  (select last_error from public.notification_schedule
   where goal_id = 'bbbb2222-0000-0000-0000-000000000003'),
  'aucun appareil actif : fenetre non ouverte',
  'Le cas est journalise plutot que passe sous silence'
);

-- ------------------------------------------------------------- pas encore

select is(
  (select state::text from public.goals where id = 'bbbb2222-0000-0000-0000-000000000002'),
  'committed',
  'Un controle a venir n''est pas ouvert d''avance'
);

-- ------------------------------------------------------------ idempotence

select is(
  app.open_due_proof_windows(), 0,
  'Un second passage du cron ne rouvre rien et n''echoue pas'
);

select * from finish();
rollback;
