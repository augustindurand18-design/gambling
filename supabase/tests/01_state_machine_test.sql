-- Tests pgTAP : machine a etats + immutabilite des consentements.
-- Execution : supabase test db

begin;
select plan(14);

create extension if not exists pgtap with schema extensions;

-- ------------------------------------------------------------- fixtures
insert into auth.users (id, email, raw_user_meta_data)
values
  ('11111111-1111-1111-1111-111111111111', 'alice@test.local', '{}'::jsonb),
  ('22222222-2222-2222-2222-222222222222', 'bob@test.local',   '{}'::jsonb);

insert into public.charities (id, slug, name)
values ('33333333-3333-3333-3333-333333333333', 'test-asso', 'Association de test')
on conflict (slug) do nothing;

insert into public.goals
  (id, user_id, title, window_mode, target_date, fixed_time_local, proof_instruction)
values
  ('44444444-4444-4444-4444-444444444444',
   '11111111-1111-1111-1111-111111111111',
   'Se lever a 7h',
   'fixed_time',
   current_date + 1,
   '07:00',
   'Photo du tableau de bord de ma voiture');

-- ------------------------------------------- table de verite des transitions
select ok(
  app.goal_state_allowed('draft', 'committed'),
  'draft -> committed est autorise'
);

select ok(
  app.goal_state_allowed('ai_verifying', 'human_review'),
  'ai_verifying -> human_review est autorise (fail-safe)'
);

select ok(
  app.goal_state_allowed('charge_failed', 'charge_pending'),
  'charge_failed -> charge_pending est autorise (relance apres mise a jour de carte)'
);

select ok(
  not app.goal_state_allowed('draft', 'charge_ok'),
  'draft -> charge_ok est interdit : on ne debite jamais sans passer par la verification'
);

select ok(
  not app.goal_state_allowed('committed', 'closed_kept'),
  'committed -> closed_kept est interdit : pas de succes sans preuve'
);

select ok(
  not app.goal_state_allowed('rejected', 'validated'),
  'rejected -> validated est interdit : seule une revue humaine peut sauver un rejet'
);

select ok(
  app.goal_state_is_terminal('charge_ok'),
  'charge_ok est terminal'
);

-- ------------------------------------------------- application par le trigger
select lives_ok(
  $$ update public.goals set state = 'committed', committed_at = now()
     where id = '44444444-4444-4444-4444-444444444444' $$,
  'Une transition legale passe'
);

select throws_ok(
  $$ update public.goals set state = 'charge_ok'
     where id = '44444444-4444-4444-4444-444444444444' $$,
  'check_violation',
  null,
  'Une transition illegale est rejetee par la base, meme en service role'
);

-- ------------------------------------------------- gel d'un objectif engage
select throws_ok(
  $$ update public.goals set title = 'Titre modifie apres coup'
     where id = '44444444-4444-4444-4444-444444444444' $$,
  'check_violation',
  null,
  'Le contenu d''un objectif engage ne peut plus etre modifie'
);

-- --------------------------------------------------------- journal d'audit
select is(
  (select count(*)::int from public.goal_state_transitions
   where goal_id = '44444444-4444-4444-4444-444444444444'),
  2,
  'Creation + engagement sont journalises'
);

-- ------------------------------------------------ immutabilite des consents
insert into public.consents
  (id, user_id, consent_type, terms_version, terms_hash, payload)
values
  ('55555555-5555-5555-5555-555555555555',
   '11111111-1111-1111-1111-111111111111',
   'onboarding_caps',
   'v1',
   repeat('a', 64),
   '{"per_goal_cap_cents": 3000}'::jsonb);

select throws_ok(
  $$ update public.consents set payload = '{"per_goal_cap_cents": 999999}'::jsonb
     where id = '55555555-5555-5555-5555-555555555555' $$,
  'P0001',
  null,
  'Un consentement ne peut pas etre modifie'
);

select throws_ok(
  $$ delete from public.consents
     where id = '55555555-5555-5555-5555-555555555555' $$,
  'P0001',
  null,
  'Un consentement ne peut pas etre supprime'
);

select isnt(
  (select row_hash from public.consents
   where id = '55555555-5555-5555-5555-555555555555'),
  null,
  'Le hash de chainage est calcule a l''insertion'
);

select * from finish();
rollback;
