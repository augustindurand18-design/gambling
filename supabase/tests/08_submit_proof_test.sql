-- Tests pgTAP : depot d'une preuve.
--
-- `submit_proof` est la seule voie cliente vers `proof_submitted` : la RLS
-- interdit l'UPDATE direct, et `transition_goal` est reservee au service role.
-- Une fonction `security definer` accessible a `authenticated` est une porte
-- ouverte dans le mur — ces tests verifient qu'elle ne laisse passer que ce
-- qu'elle doit.
--
-- Le test qui compte le plus est celui de l'atomicite : un refus hors delai
-- ne doit laisser AUCUNE ligne dans `proofs`. Une preuve orpheline sur un
-- objectif rejete serait ingerable en cas de litige.
--
-- Execution : supabase test db

begin;
select plan(11);

create extension if not exists pgtap with schema extensions;

-- ------------------------------------------------------------- fixtures
insert into auth.users (id, email, raw_user_meta_data)
values
  ('aaaa1111-0000-0000-0000-000000000001', 'alice@test.local', '{}'::jsonb),
  ('aaaa1111-0000-0000-0000-000000000002', 'bob@test.local',   '{}'::jsonb);

insert into public.goals
  (id, user_id, title, state, window_mode, timezone, target_date,
   window_start_local, window_end_local, committed_at,
   window_opened_at, proof_deadline_at)
values
  -- fenetre ouverte, dans les temps
  ('bbbb2222-0000-0000-0000-000000000001',
   'aaaa1111-0000-0000-0000-000000000001',
   'Aller a la salle', 'proof_window_open', 'random_window', 'Europe/Paris',
   current_date, '07:00', '10:00', now(),
   now() - interval '2 minutes', now() + interval '13 minutes'),

  -- pas encore ouverte
  ('bbbb2222-0000-0000-0000-000000000002',
   'aaaa1111-0000-0000-0000-000000000001',
   'Ranger le bureau', 'committed', 'random_window', 'Europe/Paris',
   current_date, '18:00', '21:00', now(), null, null),

  -- ouverte mais largement echue
  ('bbbb2222-0000-0000-0000-000000000003',
   'aaaa1111-0000-0000-0000-000000000001',
   'Reviser', 'proof_window_open', 'random_window', 'Europe/Paris',
   current_date, '07:00', '10:00', now(),
   now() - interval '20 minutes', now() - interval '5 minutes'),

  -- ouverte, echue de 60 s seulement : dans la grace d'horloge
  ('bbbb2222-0000-0000-0000-000000000004',
   'aaaa1111-0000-0000-0000-000000000001',
   'Courir', 'proof_window_open', 'random_window', 'Europe/Paris',
   current_date, '07:00', '10:00', now(),
   now() - interval '16 minutes', now() - interval '60 seconds'),

  -- celle de quelqu'un d'autre
  ('bbbb2222-0000-0000-0000-000000000005',
   'aaaa1111-0000-0000-0000-000000000002',
   'Nager', 'proof_window_open', 'random_window', 'Europe/Paris',
   current_date, '07:00', '10:00', now(),
   now() - interval '2 minutes', now() + interval '13 minutes');

set local role authenticated;
set local request.jwt.claims = '{"sub": "aaaa1111-0000-0000-0000-000000000001", "role": "authenticated"}';

-- --------------------------------------------------------- chemin nominal

select lives_ok(
  $$select public.submit_proof(
      'bbbb2222-0000-0000-0000-000000000001',
      'aaaa1111-0000-0000-0000-000000000001/bbbb2222-0000-0000-0000-000000000001/photo.jpg',
      repeat('a', 64), 120000, now(), null, null, '{"passed": true}'::jsonb)$$,
  'Une preuve deposee dans les temps est acceptee'
);

select is(
  (select state::text from public.goals where id = 'bbbb2222-0000-0000-0000-000000000001'),
  'proof_submitted',
  'L''objectif passe en proof_submitted dans la meme transaction'
);

select is(
  (select actor from public.goal_state_transitions
   where goal_id = 'bbbb2222-0000-0000-0000-000000000001' and to_state = 'proof_submitted'),
  'user',
  'Le journal d''audit attribue la transition a l''utilisateur'
);

-- Rejeu : une coupure reseau apres l'insertion ne doit pas bloquer l'app.
select is(
  (select public.submit_proof(
     'bbbb2222-0000-0000-0000-000000000001',
     'aaaa1111-0000-0000-0000-000000000001/bbbb2222-0000-0000-0000-000000000001/photo.jpg',
     repeat('a', 64), 120000, now(), null, null, '{}'::jsonb)),
  (select id from public.proofs where goal_id = 'bbbb2222-0000-0000-0000-000000000001'),
  'Un rejeu avec la meme image rend la preuve deja enregistree'
);

select is(
  (select count(*)::int from public.proofs
   where goal_id = 'bbbb2222-0000-0000-0000-000000000001'),
  1,
  'Le rejeu ne cree pas de seconde ligne'
);

-- ----------------------------------------------------- la grace d'horloge

select lives_ok(
  $$select public.submit_proof(
      'bbbb2222-0000-0000-0000-000000000004',
      'aaaa1111-0000-0000-0000-000000000001/bbbb2222-0000-0000-0000-000000000004/photo.jpg',
      repeat('d', 64), 120000, now(), null, null, '{}'::jsonb)$$,
  'Soixante secondes apres l''echeance, la preuve passe : l''anti-triche la juge legitime, la base ne la refuse pas'
);

-- ------------------------------------------------------------- les refus

select throws_ok(
  $$select public.submit_proof(
      'bbbb2222-0000-0000-0000-000000000002',
      'aaaa1111-0000-0000-0000-000000000001/bbbb2222-0000-0000-0000-000000000002/photo.jpg',
      repeat('b', 64), 120000, now(), null, null, '{}'::jsonb)$$,
  '23514', null,
  'Une preuve deposee avant l''ouverture de la fenetre est refusee'
);

select throws_ok(
  $$select public.submit_proof(
      'bbbb2222-0000-0000-0000-000000000003',
      'aaaa1111-0000-0000-0000-000000000001/bbbb2222-0000-0000-0000-000000000003/photo.jpg',
      repeat('c', 64), 120000, now(), null, null, '{}'::jsonb)$$,
  '23514', null,
  'Une preuve deposee bien apres l''echeance est refusee'
);

-- L'atomicite : le refus ci-dessus ne doit avoir rien laisse derriere lui.
select is(
  (select count(*)::int from public.proofs
   where goal_id = 'bbbb2222-0000-0000-0000-000000000003'),
  0,
  'Un refus hors delai ne laisse aucune preuve orpheline'
);

select throws_ok(
  $$select public.submit_proof(
      'bbbb2222-0000-0000-0000-000000000005',
      'aaaa1111-0000-0000-0000-000000000001/bbbb2222-0000-0000-0000-000000000005/photo.jpg',
      repeat('e', 64), 120000, now(), null, null, '{}'::jsonb)$$,
  'P0002', null,
  'L''objectif d''un autre est introuvable, pas « interdit » : on ne confirme meme pas son existence'
);

-- Le chemin est verifie ici aussi, et pas seulement par la policy de storage :
-- une ligne de `proofs` ne doit jamais designer le fichier de quelqu'un d'autre.
select throws_ok(
  $$select public.submit_proof(
      'bbbb2222-0000-0000-0000-000000000001',
      'aaaa1111-0000-0000-0000-000000000002/bbbb2222-0000-0000-0000-000000000001/photo.jpg',
      repeat('f', 64), 120000, now(), null, null, '{}'::jsonb)$$,
  '23514', null,
  'Un chemin de stockage hors du dossier de l''utilisateur est refuse'
);

reset role;

select * from finish();
rollback;
