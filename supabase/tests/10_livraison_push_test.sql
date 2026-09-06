-- Tests pgTAP : reveil de send-push depuis le cron.
--
-- Cette fonction ne touche a aucun etat : elle ne peut donc pas faire perdre
-- d'argent, et ce n'est pas ce qu'on lui demande. Ce qu'on verifie, c'est
-- qu'elle se taise quand il faut — sans reglage, ou sans rien a livrer — et
-- qu'elle parle quand une demande est reellement due. Un appel HTTP par
-- minute et par journee vide serait une facture, pas une panne, et personne
-- ne le remarquerait.
--
-- Execution : supabase test db

begin;
select plan(6);

create extension if not exists pgtap with schema extensions;

-- ------------------------------------------------------------- fixtures
insert into auth.users (id, email, raw_user_meta_data)
values ('aaaa1111-0000-0000-0000-000000000010', 'push@test.local', '{}'::jsonb);

insert into public.goals
  (id, user_id, title, state, window_mode, fixed_time_local, timezone,
   target_date, committed_at, window_opened_at, proof_deadline_at)
values
  ('bbbb2222-0000-0000-0000-000000000010',
   'aaaa1111-0000-0000-0000-000000000010',
   'Me reveiller', 'proof_window_open', 'fixed_time', '07:00', 'Europe/Paris',
   current_date, now(), now(), now() + interval '10 minutes');

-- ------------------------------------- 1. sans reglage, aucun appel
-- Le cas de toute base ou le secret n'a pas ete pose : le battement doit
-- continuer comme avant, pas tomber.
insert into public.notification_schedule (goal_id, user_id, kind, fire_at)
values ('bbbb2222-0000-0000-0000-000000000010',
        'aaaa1111-0000-0000-0000-000000000010', 'proof_window_open', now());

select lives_ok(
  'select app.deliver_pending_pushes()',
  'sans reglage Vault, la livraison passe sans lever'
);

select is(
  (select count(*) from net.http_request_queue)::int, 0,
  'sans reglage Vault, aucun appel ne part'
);

-- ------------------------------------- 2. reglages poses
select vault.create_secret('https://exemple.test', 'edge_project_url');
select vault.create_secret('cle-de-test', 'edge_anon_key');

select is(
  app.edge_setting('edge_project_url'), 'https://exemple.test',
  'le reglage est relu depuis Vault'
);

-- ------------------------------------- 3. une demande due : un appel
select app.deliver_pending_pushes();

select is(
  (select count(*) from net.http_request_queue)::int, 1,
  'une demande due declenche un appel'
);

select is(
  (select url from net.http_request_queue order by id desc limit 1),
  'https://exemple.test/functions/v1/send-push',
  'l''appel vise bien send-push'
);

-- ------------------------------------- 4. file vide : silence
-- Une demande deja livree ne doit plus reveiller personne.
update public.notification_schedule set sent_at = now()
 where goal_id = 'bbbb2222-0000-0000-0000-000000000010';

select app.deliver_pending_pushes();

select is(
  (select count(*) from net.http_request_queue)::int, 1,
  'rien a livrer : aucun appel supplementaire'
);

select * from finish();
rollback;
