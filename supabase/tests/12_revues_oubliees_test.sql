-- Tests pgTAP : cloture des revues qu'aucun humain n'a tranchees.
--
-- Cette fonction decide seule qu'un objectif est tenu. Ce qui compte le plus
-- est donc ce qu'elle NE fait PAS : ne pas clore une revue encore fraiche, a
-- qui un relecteur pourrait repondre, et ne toucher a rien d'autre que
-- `human_review`.
--
-- Execution : supabase test db

begin;
select plan(6);

create extension if not exists pgtap with schema extensions;

insert into auth.users (id, email, raw_user_meta_data)
values ('aaaa1111-0000-0000-0000-000000000030', 'revue@test.local', '{}'::jsonb);

insert into public.charities (id, name, slug, active)
values ('dddd4444-0000-0000-0000-000000000002', 'Test', 'test-revue', true)
on conflict do nothing;

-- (a) revue oubliee depuis longtemps, (b) revue d'il y a une heure,
-- (c) objectif rejete, qui n'a rien a faire ici
insert into public.goals
  (id, user_id, title, state, window_mode, fixed_time_local, timezone,
   target_date, committed_at, window_opened_at, proof_deadline_at)
values
  ('bbbb2222-0000-0000-0000-000000000030',
   'aaaa1111-0000-0000-0000-000000000030', 'Oubliee', 'human_review',
   'fixed_time', '07:00', 'Europe/Paris', current_date, now(), now(),
   now() - interval '2 days'),
  ('bbbb2222-0000-0000-0000-000000000031',
   'aaaa1111-0000-0000-0000-000000000030', 'Fraiche', 'human_review',
   'fixed_time', '07:00', 'Europe/Paris', current_date, now(), now(),
   now() - interval '1 hour'),
  ('bbbb2222-0000-0000-0000-000000000032',
   'aaaa1111-0000-0000-0000-000000000030', 'Rejete', 'rejected',
   'fixed_time', '07:00', 'Europe/Paris', current_date, now(), now(),
   now() - interval '2 days');

insert into public.stakes (goal_id, user_id, amount_cents, charity_bps, charity_id, status)
values
  ('bbbb2222-0000-0000-0000-000000000030',
   'aaaa1111-0000-0000-0000-000000000030', 2000, 2500,
   'dddd4444-0000-0000-0000-000000000002', 'active');

-- L'anciennete se lit dans le journal : `goals.updated_at` est remis a
-- `now()` par un declencheur des qu'un champ bouge, et ne dit donc pas depuis
-- quand la revue attend.
-- L'insertion d'un objectif journalise deja son entree en revue, a `now()`.
-- On recule cette ligne plutot que d'en ajouter une : c'est la plus recente
-- qui compte, et une seconde entree a l'ancienne date ne changerait rien.
update public.goal_state_transitions set created_at = now() - interval '2 days'
 where goal_id = 'bbbb2222-0000-0000-0000-000000000030' and to_state = 'human_review';
update public.goal_state_transitions set created_at = now() - interval '1 hour'
 where goal_id = 'bbbb2222-0000-0000-0000-000000000031' and to_state = 'human_review';

select is(
  app.close_stale_reviews(), 1,
  'une seule revue est close : celle que le delai a depassee'
);

-- ------------------------------------- au benefice de l'utilisateur
select is(
  (select state::text from public.goals
   where id = 'bbbb2222-0000-0000-0000-000000000030'),
  'closed_kept',
  'un doute que personne ne leve se resout en faveur de l''utilisateur'
);

-- ------------------------------------- et la mise ne coute rien
select is(
  (select status::text from public.stakes
   where goal_id = 'bbbb2222-0000-0000-0000-000000000030'),
  'released',
  'la mise est liberee, rien n''est preleve'
);

-- ------------------------------------- une revue fraiche est laissee
-- C'est le test qui protege le relecteur : cloturer avant le delai lui
-- retirerait la decision sans qu'il ait rien pu faire.
select is(
  (select state::text from public.goals
   where id = 'bbbb2222-0000-0000-0000-000000000031'),
  'human_review',
  'une revue encore dans le delai n''est pas tranchee d''office'
);

-- ------------------------------------- rien d'autre n'est touche
select is(
  (select state::text from public.goals
   where id = 'bbbb2222-0000-0000-0000-000000000032'),
  'rejected',
  'un objectif rejete n''est pas requalifie en objectif tenu'
);

-- ------------------------------------- la decision laisse une trace
-- Un objectif clos sans humain doit pouvoir s'expliquer plus tard : c'est le
-- journal qui dit que la machine a tranche, et pourquoi.
select ok(
  exists (
    select 1 from public.goal_state_transitions
    where goal_id = 'bbbb2222-0000-0000-0000-000000000030'
      and to_state = 'closed_kept'
      and actor = 'cron:close_stale_reviews'
  ),
  'la cloture automatique est inscrite au journal, avec son auteur'
);

select * from finish();
rollback;
