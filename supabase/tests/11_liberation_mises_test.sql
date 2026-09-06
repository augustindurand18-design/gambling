-- Tests pgTAP : liberation des mises tenues.
--
-- C'est de l'argent qui cesse de peser sur un plafond, donc ce qui compte
-- autant que la liberation elle-meme, c'est ce qui NE doit PAS bouger : une
-- mise deja debitee ne redevient pas libre, et une mise dont l'objectif est
-- perdu reste active jusqu'au debit.
--
-- Execution : supabase test db

begin;
select plan(5);

create extension if not exists pgtap with schema extensions;

insert into auth.users (id, email, raw_user_meta_data)
values ('aaaa1111-0000-0000-0000-000000000020', 'liberation@test.local', '{}'::jsonb);

insert into public.charities (id, name, slug, active)
values ('dddd4444-0000-0000-0000-000000000001', 'Test', 'test-liberation', true)
on conflict do nothing;

-- (a) objectif qui sera tenu, (b) objectif qui sera perdu
insert into public.goals
  (id, user_id, title, state, window_mode, fixed_time_local, timezone,
   target_date, committed_at, window_opened_at, proof_deadline_at)
values
  ('bbbb2222-0000-0000-0000-000000000020',
   'aaaa1111-0000-0000-0000-000000000020', 'Tenu', 'validated', 'fixed_time',
   '07:00', 'Europe/Paris', current_date, now(), now(), now() + interval '5 min'),
  ('bbbb2222-0000-0000-0000-000000000021',
   'aaaa1111-0000-0000-0000-000000000020', 'Perdu', 'rejected', 'fixed_time',
   '07:00', 'Europe/Paris', current_date, now(), now(), now() - interval '1 min');

insert into public.stakes (goal_id, user_id, amount_cents, charity_bps, charity_id, status)
values
  ('bbbb2222-0000-0000-0000-000000000020',
   'aaaa1111-0000-0000-0000-000000000020', 2000, 2500,
   'dddd4444-0000-0000-0000-000000000001', 'active'),
  ('bbbb2222-0000-0000-0000-000000000021',
   'aaaa1111-0000-0000-0000-000000000020', 3000, 2500,
   'dddd4444-0000-0000-0000-000000000001', 'active');

-- ------------------------------------- 1. un objectif tenu libere sa mise
update public.goals set state = 'closed_kept'
 where id = 'bbbb2222-0000-0000-0000-000000000020';

select is(
  (select status::text from public.stakes
   where goal_id = 'bbbb2222-0000-0000-0000-000000000020'),
  'released',
  'un objectif tenu libere sa mise'
);

-- ------------------------------------- 2. la mise perdue ne bouge pas
select is(
  (select status::text from public.stakes
   where goal_id = 'bbbb2222-0000-0000-0000-000000000021'),
  'active',
  'la mise d''un objectif perdu reste active jusqu''au debit'
);

-- ------------------------------------- 3. elle ne pese plus sur le plafond
-- Le calcul de `commit_goal` ne compte que les mises actives : c'est tout
-- l'interet de la liberation, et la raison pour laquelle un utilisateur
-- assidu se retrouvait bloque par ses propres reussites.
select is(
  (select coalesce(sum(amount_cents), 0)::int from public.stakes
   where user_id = 'aaaa1111-0000-0000-0000-000000000020' and status = 'active'),
  3000,
  'seule la mise encore en jeu compte dans le plafond'
);

-- ------------------------------------- 4. une mise debitee ne revient pas
update public.stakes set status = 'charged'
 where goal_id = 'bbbb2222-0000-0000-0000-000000000021';

update public.goals set state = 'human_review'
 where id = 'bbbb2222-0000-0000-0000-000000000021';
update public.goals set state = 'closed_kept'
 where id = 'bbbb2222-0000-0000-0000-000000000021';

select is(
  (select status::text from public.stakes
   where goal_id = 'bbbb2222-0000-0000-0000-000000000021'),
  'charged',
  'une mise deja debitee ne redevient jamais libre'
);

-- ------------------------------------- 5. sans reglage, aucun debit declenche
-- Meme prudence que pour la livraison : sans Vault renseigne, le reveil ne
-- part pas et ne leve pas. Ici l'enjeu est plus grand — un appel declenche
-- de vrais debits.
select lives_ok(
  'select app.trigger_pending_charges()',
  'sans reglage Vault, le reveil des debits passe sans lever'
);

select * from finish();
rollback;
