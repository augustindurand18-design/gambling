-- Tests pgTAP : planification du controle surprise.
--
-- Deux choses se jouent ici. D'abord l'arithmetique de fuseau, qui est le
-- genre de code qu'on relit sans y voir d'erreur : le tirage est fige en
-- heure d'hiver ET en heure d'ete pour que personne ne « corrige » un offset
-- dans six mois. Ensuite l'invariant 4 — l'instant tire ne doit rester
-- lisible par personne d'autre que le serveur, y compris apres planification.
--
-- Execution : supabase test db

begin;
select plan(12);

create extension if not exists pgtap with schema extensions;

-- ------------------------------------------------------------- fixtures
insert into auth.users (id, email, raw_user_meta_data)
values
  ('aaaa1111-0000-0000-0000-000000000001', 'alice@test.local', '{}'::jsonb),
  ('aaaa1111-0000-0000-0000-000000000002', 'bob@test.local',   '{}'::jsonb);

-- Un objectif engage a creneau libre, un a heure fixe, un brouillon.
insert into public.goals
  (id, user_id, title, state, window_mode, timezone, target_date,
   window_start_local, window_end_local, committed_at)
values
  ('bbbb2222-0000-0000-0000-000000000001',
   'aaaa1111-0000-0000-0000-000000000001',
   'Aller a la salle', 'committed', 'random_window', 'Europe/Paris',
   date '2026-07-15', '07:00', '10:00', now());

insert into public.goals
  (id, user_id, title, state, window_mode, timezone, target_date,
   fixed_time_local, committed_at)
values
  ('bbbb2222-0000-0000-0000-000000000002',
   'aaaa1111-0000-0000-0000-000000000001',
   'Me reveiller', 'committed', 'fixed_time', 'Europe/Paris',
   date '2026-07-15', '07:00', now());

insert into public.goals
  (id, user_id, title, state, window_mode, timezone, target_date,
   window_start_local, window_end_local)
values
  ('bbbb2222-0000-0000-0000-000000000003',
   'aaaa1111-0000-0000-0000-000000000002',
   'Ranger le bureau', 'draft', 'random_window', 'Europe/Paris',
   date '2026-07-15', '18:00', '21:00');

-- ------------------------------------------- constantes et leur alignement

select is(
  app.proof_window_seconds(), 900,
  'Le delai de soumission vaut 900 s, comme MAX_CAPTURE_DELAY_SEC dans anticheat.ts'
);

select is(
  app.proof_clock_grace_seconds(), 120,
  'La grace d''horloge vaut 120 s, comme CLOCK_SKEW_TOLERANCE_SEC dans anticheat.ts'
);

-- La contrainte de largeur de fenetre reprend le meme nombre en dur : si le
-- delai de soumission change sans elle, un creneau redevient trop court pour
-- accueillir un tirage.
select throws_ok(
  $$insert into public.goals
      (user_id, title, window_mode, timezone, target_date,
       window_start_local, window_end_local)
    values ('aaaa1111-0000-0000-0000-000000000001', 'Creneau trop court',
            'random_window', 'Europe/Paris', date '2026-07-16', '07:00', '07:10')$$,
  '23514',
  null,
  'Un creneau plus court que le delai de soumission est refuse a l''ecriture'
);

-- ------------------------------------------------ arithmetique de fuseau

select is(
  app.pick_window_fire_at(date '2026-01-15', 'Europe/Paris', '07:00', '10:00', 900, 0)
    at time zone 'Europe/Paris',
  timestamp '2026-01-15 07:00:00',
  'Heure d''hiver, tirage au plus bas : l''instant tombe au debut du creneau'
);

select is(
  app.pick_window_fire_at(date '2026-07-15', 'Europe/Paris', '07:00', '10:00', 900, 0)
    at time zone 'Europe/Paris',
  timestamp '2026-07-15 07:00:00',
  'Heure d''ete, tirage au plus bas : meme heure locale, offset UTC different'
);

-- Le meme creneau local ne donne pas le meme instant absolu selon la saison :
-- c'est exactement ce que l'arithmetique de fuseau doit produire.
select isnt(
  app.pick_window_fire_at(date '2026-01-15', 'Europe/Paris', '07:00', '10:00', 900, 0)::time,
  app.pick_window_fire_at(date '2026-07-15', 'Europe/Paris', '07:00', '10:00', 900, 0)::time,
  'Hiver et ete n''ont pas le meme offset UTC pour la meme heure locale'
);

select is(
  app.pick_window_fire_at(date '2026-07-15', 'Europe/Paris', '07:00', '10:00', 900, 1)
    at time zone 'Europe/Paris',
  timestamp '2026-07-15 09:45:00',
  'Tirage au plus haut : il reste toujours le delai de soumission avant la fin du creneau'
);

-- Filet pour une donnee anterieure a la contrainte de largeur.
select is(
  app.pick_window_fire_at(date '2026-07-15', 'Europe/Paris', '07:00', '07:10', 900, 1)
    at time zone 'Europe/Paris',
  timestamp '2026-07-15 07:00:00',
  'Un creneau plus court que le delai se replie sur son debut plutot que de partir en arriere'
);

-- ---------------------------------------------------------- planification

select is(
  app.schedule_proof_windows(), 2,
  'Les deux objectifs engages sont planifies, le brouillon ne l''est pas'
);

select is(
  (select fire_at from public.notification_schedule
   where goal_id = 'bbbb2222-0000-0000-0000-000000000002')
    at time zone 'Europe/Paris',
  timestamp '2026-07-15 07:00:00',
  'A heure fixe, l''heure EST la promesse : aucun alea ne s''y ajoute'
);

-- Rejouable : le cron repasse toutes les minutes.
select app.schedule_proof_windows();

select is(
  (select count(*)::int from public.notification_schedule
   where kind = 'proof_window_open'),
  2,
  'Une seconde planification ne cree aucun doublon'
);

-- --------------------------------------------------- invariant 4 maintenu

set local role authenticated;
set local request.jwt.claims = '{"sub": "aaaa1111-0000-0000-0000-000000000001", "role": "authenticated"}';

select is(
  (select count(*)::int from public.notification_schedule),
  0,
  'Meme planifie, l''instant du controle reste invisible a son proprietaire'
);

reset role;

select * from finish();
rollback;
