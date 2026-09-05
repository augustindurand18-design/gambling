-- Tests pgTAP : l'instant du controle surprise reste un secret serveur.
--
-- Invariant 4 de docs/architecture.md. Ce test existe parce que la fuite
-- etait invisible a la lecture : `notification_schedule` etait bien protegee,
-- et personne n'avait remarque que `goals` portait le meme instant dans une
-- colonne rendue visible par une policy qui donne toute la ligne.
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
   window_start_local, window_end_local)
values
  ('bbbb2222-0000-0000-0000-000000000001',
   'aaaa1111-0000-0000-0000-000000000001',
   'Controle surprise', 'random_window', current_date + 1,
   '07:00', '10:00');

insert into public.notification_schedule (goal_id, user_id, kind, fire_at)
values ('bbbb2222-0000-0000-0000-000000000001',
        'aaaa1111-0000-0000-0000-000000000001',
        'proof_window_open', now() + interval '3 hours');

-- ------------------------------------ un seul domicile pour cet instant
select hasnt_column(
  'public', 'goals', 'window_fire_at',
  'goals ne porte plus l''instant du controle : il vivait a deux endroits, dont un mal garde'
);

select has_column(
  'public', 'notification_schedule', 'fire_at',
  'L''instant vit dans la file de notifications, concue pour lui'
);

-- ------------------------------------------------------ verification reelle
set local role authenticated;
set local request.jwt.claims = '{"sub": "aaaa1111-0000-0000-0000-000000000001", "role": "authenticated"}';

select is(
  (select count(*)::int from public.notification_schedule),
  0,
  'La file de notifications reste invisible au client'
);

-- L'objectif, lui, doit rester lisible : c'est la promesse de l'utilisateur.
-- Un `select *` doit passer, sinon l'application ne peut plus rien afficher
-- (c'est ce qui avait casse la lecture avec la premiere correction).
select is(
  (select count(*)::int from public.goals),
  1,
  'L''utilisateur lit toujours son propre objectif'
);

select lives_ok(
  'select * from public.goals',
  'Un select * sur goals fonctionne : PostgREST en emet un sous le capot'
);

reset role;

select * from finish();
rollback;
