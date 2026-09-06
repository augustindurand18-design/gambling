-- Tests pgTAP : cloture des echeances passees.
--
-- C'est la seule fonction du cron qui decide qu'un objectif est perdu : tout
-- ce qu'elle fait finit en argent. Les tests qui comptent le plus sont donc
-- ceux qui verifient ce qu'elle NE fait PAS — ne pas clore une contestation
-- encore ouverte, ne pas rejeter un objectif dont la fenetre n'a jamais ete
-- ouverte. Ce second cas est notre panne, pas un manquement de l'utilisateur :
-- le debiter pour ca serait exactement ce que l'invariant 2 interdit.
--
-- Execution : supabase test db

begin;
select plan(9);

create extension if not exists pgtap with schema extensions;

-- ------------------------------------------------------------- fixtures
insert into auth.users (id, email, raw_user_meta_data)
values ('aaaa1111-0000-0000-0000-000000000001', 'alice@test.local', '{}'::jsonb);

insert into public.goals
  (id, user_id, title, state, window_mode, timezone, target_date,
   window_start_local, window_end_local, committed_at,
   window_opened_at, proof_deadline_at, dispute_deadline_at)
values
  -- (a) fenetre ouverte, delai ecoule, aucune preuve
  ('bbbb2222-0000-0000-0000-000000000001',
   'aaaa1111-0000-0000-0000-000000000001',
   'Aller a la salle', 'proof_window_open', 'random_window', 'Europe/Paris',
   current_date, '07:00', '10:00', now(),
   now() - interval '1 hour', now() - interval '45 minutes', null),

  -- (a bis) fenetre ouverte, delai tout juste depasse mais dans la grace
  ('bbbb2222-0000-0000-0000-000000000002',
   'aaaa1111-0000-0000-0000-000000000001',
   'Ranger le bureau', 'proof_window_open', 'random_window', 'Europe/Paris',
   current_date, '18:00', '21:00', now(),
   now() - interval '15 minutes', now() - interval '30 seconds', null),

  -- (b) rejet dont la contestation est expiree
  ('bbbb2222-0000-0000-0000-000000000003',
   'aaaa1111-0000-0000-0000-000000000001',
   'Reviser', 'rejected', 'random_window', 'Europe/Paris',
   current_date - 3, '07:00', '10:00', now(),
   null, null, now() - interval '1 hour'),

  -- (b bis) rejet encore contestable
  ('bbbb2222-0000-0000-0000-000000000004',
   'aaaa1111-0000-0000-0000-000000000001',
   'Courir', 'rejected', 'random_window', 'Europe/Paris',
   current_date, '07:00', '10:00', now(),
   null, null, now() + interval '24 hours'),

  -- (c) engage, jour passe, fenetre jamais ouverte
  ('bbbb2222-0000-0000-0000-000000000005',
   'aaaa1111-0000-0000-0000-000000000001',
   'Nager', 'committed', 'random_window', 'Europe/Paris',
   current_date - 3, '07:00', '10:00', now(),
   null, null, null);

insert into public.notification_schedule (goal_id, user_id, kind, fire_at)
values ('bbbb2222-0000-0000-0000-000000000005',
        'aaaa1111-0000-0000-0000-000000000001',
        'proof_window_open', now() - interval '3 days');

-- --------------------------------------------------------- la cloture

select is(
  app.close_expired_goals(), 2,
  'Deux echeances tombent : la preuve manquante et la contestation expiree'
);

-- (a) l'echec nominal
select is(
  (select state::text from public.goals where id = 'bbbb2222-0000-0000-0000-000000000001'),
  'rejected',
  'Fenetre ouverte, delai ecoule, aucune preuve : l''objectif est rejete'
);

-- La fenetre de contestation a ete retiree (2026-09-06) : l'echeance est
-- posee a `now()`, et le battement suivant clot l'objectif. Elle reste NON
-- NULLE — `close_expired_goals` l'exige, et un rejet sans echeance ne serait
-- jamais clos ni debite.
select ok(
  (select dispute_deadline_at is not null
     and dispute_deadline_at <= now() + interval '1 minute'
   from public.goals where id = 'bbbb2222-0000-0000-0000-000000000001'),
  'Le rejet pose une echeance immediate, sans fenetre de contestation'
);

-- (a bis) la grace d'horloge
select is(
  (select state::text from public.goals where id = 'bbbb2222-0000-0000-0000-000000000002'),
  'proof_window_open',
  'Trente secondes apres l''echeance, la fenetre reste ouverte : on ne tranche pas contre l''utilisateur sur un doute d''horloge'
);

-- (b) la contestation
select is(
  (select state::text from public.goals where id = 'bbbb2222-0000-0000-0000-000000000003'),
  'closed_failed',
  'Un rejet non conteste dans les temps devient un echec confirme'
);

select ok(
  (select closed_at is not null
   from public.goals where id = 'bbbb2222-0000-0000-0000-000000000003'),
  'La cloture est horodatee'
);

-- (b bis) ce qu'elle ne doit surtout pas faire
select is(
  (select state::text from public.goals where id = 'bbbb2222-0000-0000-0000-000000000004'),
  'rejected',
  'Une contestation encore ouverte n''est jamais close d''office'
);

-- (c) notre panne n'est pas sa faute
select is(
  (select state::text from public.goals where id = 'bbbb2222-0000-0000-0000-000000000005'),
  'committed',
  'Un objectif dont la fenetre ne s''est jamais ouverte n''est pas rejete : la panne est la notre'
);

select is(
  (select last_error from public.notification_schedule
   where goal_id = 'bbbb2222-0000-0000-0000-000000000005'),
  'fenetre jamais ouverte : a examiner',
  'Il est signale pour examen plutot que laisse invisible'
);

select * from finish();
rollback;
