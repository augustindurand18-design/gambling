-- Tests pgTAP : isolation entre utilisateurs et regles d'ecriture.
-- Execution : supabase test db

begin;
select plan(9);

create extension if not exists pgtap with schema extensions;

-- ------------------------------------------------------------- fixtures
insert into auth.users (id, email, raw_user_meta_data)
values
  ('aaaaaaaa-0000-0000-0000-000000000001', 'alice@test.local', '{}'::jsonb),
  ('bbbbbbbb-0000-0000-0000-000000000002', 'bob@test.local',   '{}'::jsonb);

insert into public.goals
  (id, user_id, title, window_mode, target_date, fixed_time_local)
values
  ('cccccccc-0000-0000-0000-000000000001',
   'aaaaaaaa-0000-0000-0000-000000000001',
   'Objectif d''Alice', 'fixed_time', current_date + 1, '07:00'),
  ('cccccccc-0000-0000-0000-000000000002',
   'bbbbbbbb-0000-0000-0000-000000000002',
   'Objectif de Bob', 'fixed_time', current_date + 1, '08:00');

-- ----------------------------------------------------- Alice est connectee
set local role authenticated;
set local request.jwt.claims = '{"sub": "aaaaaaaa-0000-0000-0000-000000000001", "role": "authenticated"}';

select is(
  (select count(*)::int from public.goals),
  1,
  'Alice ne voit que son propre objectif'
);

select is(
  (select title from public.goals),
  'Objectif d''Alice',
  'Et c''est bien le sien'
);

select is(
  (select count(*)::int from public.goals
   where id = 'cccccccc-0000-0000-0000-000000000002'),
  0,
  'L''objectif de Bob est invisible pour Alice'
);

select throws_ok(
  $$ update public.goals set title = 'Pirate'
     where id = 'cccccccc-0000-0000-0000-000000000002' $$,
  null, null,
  'Alice ne peut pas modifier l''objectif de Bob'
);

-- La file de notifications ne doit jamais fuiter : l'instant de declenchement
-- doit rester imprevisible.
select is(
  (select count(*)::int from public.notification_schedule),
  0,
  'La file de notifications est invisible du client (fenetre surprise preservee)'
);

-- Un utilisateur ne peut pas s'auto-debloquer ni relever ses plafonds.
select throws_ok(
  $$ update public.profiles
     set stake_block_active = false, outstanding_balance_cents = 0
     where user_id = 'aaaaaaaa-0000-0000-0000-000000000001' $$,
  'insufficient_privilege',
  null,
  'Un utilisateur ne peut pas lever son propre blocage de paiement'
);

select throws_ok(
  $$ update public.profiles set per_goal_cap_cents = 1000000
     where user_id = 'aaaaaaaa-0000-0000-0000-000000000001' $$,
  'insufficient_privilege',
  null,
  'Un utilisateur ne peut pas relever ses propres plafonds'
);

-- Une preuve ne peut etre deposee que si la fenetre est ouverte.
select throws_ok(
  $$ insert into public.proofs (goal_id, user_id, image_sha256)
     values ('cccccccc-0000-0000-0000-000000000001',
             'aaaaaaaa-0000-0000-0000-000000000001',
             repeat('b', 64)) $$,
  null, null,
  'Pas de preuve tant que la fenetre n''est pas ouverte'
);

-- Le passage a committed ne peut pas se faire par un UPDATE direct :
-- il faut passer par la RPC commit_goal (mise + consentement atomiques).
select throws_ok(
  $$ update public.goals set state = 'committed'
     where id = 'cccccccc-0000-0000-0000-000000000001' $$,
  null, null,
  'L''engagement ne peut pas court-circuiter la RPC commit_goal'
);

select * from finish();
rollback;
