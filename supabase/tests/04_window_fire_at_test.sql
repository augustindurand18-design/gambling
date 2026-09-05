-- Tests pgTAP : l'instant du controle surprise reste un secret serveur.
--
-- Invariant 4 de docs/architecture.md. Ce test existe parce que la fuite
-- etait invisible a la lecture : `notification_schedule` etait bien protegee,
-- et personne n'avait remarque que `goals.window_fire_at` portait le meme
-- instant sous une policy qui donne toute la ligne.
--
-- Execution : supabase test db

begin;
select plan(5);

create extension if not exists pgtap with schema extensions;

-- ------------------------------------------------------------- fixtures
insert into auth.users (id, email, raw_user_meta_data)
values ('aaaa1111-0000-0000-0000-000000000001', 'mallory@test.local', '{}'::jsonb);

insert into public.goals
  (id, user_id, title, window_mode, target_date,
   window_start_local, window_end_local, window_fire_at)
values
  ('bbbb2222-0000-0000-0000-000000000001',
   'aaaa1111-0000-0000-0000-000000000001',
   'Controle surprise', 'random_window', current_date + 1,
   '07:00', '10:00', now() + interval '3 hours');

insert into public.notification_schedule (goal_id, user_id, kind, fire_at)
values ('bbbb2222-0000-0000-0000-000000000001',
        'aaaa1111-0000-0000-0000-000000000001',
        'proof_window_open', now() + interval '3 hours');

-- --------------------------------------------------- permissions declarees
select ok(
  not has_column_privilege('authenticated', 'public.goals', 'window_fire_at', 'select'),
  'Un utilisateur connecte n''a pas le droit de lire window_fire_at'
);

select ok(
  not has_column_privilege('anon', 'public.goals', 'window_fire_at', 'select'),
  'Un visiteur anonyme non plus'
);

-- Les colonnes dont l'utilisateur a besoin restent lisibles : l'echeance de
-- preuve lui est due, sinon il ne saurait pas jusqu'a quand agir.
select ok(
  has_column_privilege('authenticated', 'public.goals', 'proof_deadline_at', 'select'),
  'L''echeance de preuve, elle, reste lisible'
);

-- ------------------------------------------------------ verification reelle
set local role authenticated;
set local request.jwt.claims = '{"sub": "aaaa1111-0000-0000-0000-000000000001", "role": "authenticated"}';

select throws_ok(
  'select window_fire_at from public.goals',
  '42501',
  null,
  'Lire la colonne echoue vraiment, et pas seulement sur le papier'
);

select is(
  (select count(*)::int from public.notification_schedule),
  0,
  'La file de notifications reste invisible au client'
);

reset role;

select * from finish();
rollback;
