-- Tests pgTAP : RPC transition_goal (0020).
--
-- Ce que ces tests protegent : la RPC ne doit jamais devenir un moyen de
-- contourner la table de verite des transitions, ni d'ecrire dans une colonne
-- que le gel d'un objectif engage protege.
--
-- Execution : supabase test db

begin;
select plan(15);

create extension if not exists pgtap with schema extensions;

-- ------------------------------------------------------------- fixtures
insert into auth.users (id, email, raw_user_meta_data)
values ('11111111-1111-1111-1111-111111111111', 'alice@test.local', '{}'::jsonb);

insert into public.goals
  (id, user_id, title, window_mode, target_date, fixed_time_local, proof_instruction)
values
  ('44444444-4444-4444-4444-444444444444',
   '11111111-1111-1111-1111-111111111111',
   'Se lever a 7h',
   'fixed_time',
   current_date + 1,
   '07:00',
   'Photo du lit fait');

-- ------------------------------------------------- transition legale simple
select lives_ok(
  $$ select public.transition_goal(
       '44444444-4444-4444-4444-444444444444', 'committed',
       'system', 'engagement') $$,
  'Une transition legale est acceptee'
);

select is(
  (select state from public.goals where id = '44444444-4444-4444-4444-444444444444'),
  'committed'::goal_state,
  'L''etat de l''objectif a bien change'
);

-- ---------------------------------------------------- journal d'audit nourri
select is(
  (select actor from public.goal_state_transitions
   where goal_id = '44444444-4444-4444-4444-444444444444'
     and to_state = 'committed'),
  'system',
  'L''acteur de la transition est journalise'
);

select is(
  (select reason from public.goal_state_transitions
   where goal_id = '44444444-4444-4444-4444-444444444444'
     and to_state = 'committed'),
  'engagement',
  'La raison de la transition est journalisee'
);

-- ------------------------------------------- instants calcules par le serveur
select lives_ok(
  $$ select public.transition_goal(
       '44444444-4444-4444-4444-444444444444', 'proof_window_open',
       'send-push', 'ouverture de la fenetre',
       jsonb_build_object(
         'window_opened_at', '2026-09-10T05:00:00Z',
         'proof_deadline_at', '2026-09-10T07:00:00Z')) $$,
  'Une transition peut poser les echeances calculees par le serveur'
);

select is(
  (select proof_deadline_at from public.goals
   where id = '44444444-4444-4444-4444-444444444444'),
  '2026-09-10T07:00:00Z'::timestamptz,
  'L''echeance de preuve a ete ecrite'
);

-- ------------------------------------------------------- la garde tient bon
-- Le trigger de 0015 reste seul juge : la RPC ne doit pas lui permettre de
-- sauter des etapes, sinon on debiterait sans avoir verifie quoi que ce soit.
select throws_ok(
  $$ select public.transition_goal(
       '44444444-4444-4444-4444-444444444444', 'charge_ok',
       'system', 'tentative de raccourci') $$,
  '23514',
  null,
  'Une transition illegale reste refusee par le trigger'
);

-- Une cle inconnue est refusee, pas ignoree : une faute de frappe dans une
-- Edge Function laisserait sinon un objectif sans echeance.
select throws_ok(
  $$ select public.transition_goal(
       '44444444-4444-4444-4444-444444444444', 'proof_submitted',
       'app', 'preuve deposee',
       '{"proof_dealine_at": "2026-09-10T07:00:00Z"}'::jsonb) $$,
  '23514',
  null,
  'Un champ mal orthographie est refuse et non ignore'
);

-- Le contenu de la promesse n'est pas modifiable par cette voie.
select throws_ok(
  $$ select public.transition_goal(
       '44444444-4444-4444-4444-444444444444', 'proof_submitted',
       'app', 'preuve deposee',
       '{"title": "Un autre objectif"}'::jsonb) $$,
  '23514',
  null,
  'La promesse elle-meme ne peut pas etre reecrite par une transition'
);

-- --------------------------------------------------------- tracabilite exigee
select throws_ok(
  $$ select public.transition_goal(
       '44444444-4444-4444-4444-444444444444', 'proof_submitted',
       '', 'preuve deposee') $$,
  '23514',
  null,
  'Une transition sans acteur est refusee'
);

-- ------------------------------------------------------------- rejeu d'un cron
select lives_ok(
  $$ select public.transition_goal(
       '44444444-4444-4444-4444-444444444444', 'proof_window_open',
       'send-push', 'rejeu') $$,
  'Rejouer une transition deja faite ne casse pas : les crons et webhooks rejouent'
);

-- ------------------------------------------------- hors de portee du client
-- Le point le plus sensible de cette RPC : accordee au role authenticated,
-- elle laisserait un utilisateur passer son propre objectif de 'rejected' a
-- 'closed_kept' et effacer sa propre mise. Le grant se verifie en l'appelant,
-- pas en le relisant.
set local role authenticated;
set local request.jwt.claims = '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}';

select throws_ok(
  $$ select public.transition_goal(
       '44444444-4444-4444-4444-444444444444', 'closed_kept',
       'user', 'tentative depuis le telephone') $$,
  '42501',
  null,
  'Un utilisateur connecte ne peut pas appeler transition_goal'
);

reset role;

-- Les permissions se lisent dans la base, pas dans les migrations : le revoke
-- sur `public` de 0017 laissait `anon` executer commit_goal (corrige en 0021).
select ok(
  not has_function_privilege('anon', 'public.transition_goal(uuid, goal_state, text, text, jsonb)', 'execute'),
  'anon ne peut pas appeler transition_goal'
);

select ok(
  not has_function_privilege(
    'anon',
    'public.commit_goal(uuid, int, uuid, int, text, text, jsonb, text, text)',
    'execute'),
  'anon ne peut pas engager un objectif'
);

select ok(
  has_function_privilege(
    'authenticated',
    'public.commit_goal(uuid, int, uuid, int, text, text, jsonb, text, text)',
    'execute'),
  'un utilisateur connecte, lui, peut toujours engager un objectif'
);

select * from finish();
rollback;
