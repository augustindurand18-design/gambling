-- Tests pgTAP : annonce du verdict.
--
-- Sans cette notification, quelqu'un qui a ferme l'application n'apprend
-- jamais qu'une mise a ete prelevee. Ce qui compte donc autant que l'envoi,
-- c'est qu'il n'y en ait qu'UN : deux annonces pour une meme decision, ou une
-- annonce a chaque etape intermediaire, feraient douter de ce qui a ete
-- decide.
--
-- Execution : supabase test db

begin;
select plan(6);

create extension if not exists pgtap with schema extensions;

insert into auth.users (id, email, raw_user_meta_data)
values ('aaaa1111-0000-0000-0000-000000000040', 'verdict@test.local', '{}'::jsonb);

insert into public.goals
  (id, user_id, title, state, window_mode, fixed_time_local, timezone,
   target_date, committed_at, window_opened_at, proof_deadline_at)
values
  ('bbbb2222-0000-0000-0000-000000000040',
   'aaaa1111-0000-0000-0000-000000000040', 'Tenu', 'validated', 'fixed_time',
   '07:00', 'Europe/Paris', current_date, now(), now(), now() + interval '5 min'),
  ('bbbb2222-0000-0000-0000-000000000041',
   'aaaa1111-0000-0000-0000-000000000040', 'Perdu', 'rejected', 'fixed_time',
   '07:00', 'Europe/Paris', current_date, now(), now(), now() - interval '1 min');

-- ------------------------------------- 1. un etat intermediaire ne dit rien
-- `validated` precede `closed_kept`, `rejected` precede `closed_failed` :
-- annoncer les deux ferait deux notifications pour une seule decision, et la
-- premiere serait dementie par la seconde en cas de debit.
select is(
  (select count(*)::int from public.notification_schedule
   where goal_id = 'bbbb2222-0000-0000-0000-000000000040' and kind = 'verdict'),
  0,
  'un objectif seulement valide n''annonce rien : la decision n''est pas close'
);

-- ------------------------------------- 2. un objectif tenu s'annonce
update public.goals set state = 'closed_kept'
 where id = 'bbbb2222-0000-0000-0000-000000000040';

select is(
  (select payload->>'outcome' from public.notification_schedule
   where goal_id = 'bbbb2222-0000-0000-0000-000000000040' and kind = 'verdict'),
  'kept',
  'un objectif tenu depose une annonce favorable'
);

-- ------------------------------------- 3. un objectif perdu s'annonce
update public.goals set state = 'closed_failed'
 where id = 'bbbb2222-0000-0000-0000-000000000041';

select is(
  (select payload->>'outcome' from public.notification_schedule
   where goal_id = 'bbbb2222-0000-0000-0000-000000000041' and kind = 'verdict'),
  'failed',
  'un objectif perdu depose une annonce defavorable'
);

-- ------------------------------------- 4. l'annonce est immediate
select ok(
  (select fire_at <= now() from public.notification_schedule
   where goal_id = 'bbbb2222-0000-0000-0000-000000000041' and kind = 'verdict'),
  'l''annonce part tout de suite, pas a une echeance future'
);

-- ------------------------------------- 5. une seule annonce par objectif
-- Le debit fait encore bouger l'etat apres la cloture. Chacun de ces
-- mouvements ne doit pas re-annoncer une decision deja dite.
update public.goals set state = 'charge_pending'
 where id = 'bbbb2222-0000-0000-0000-000000000041';
update public.goals set state = 'charge_ok'
 where id = 'bbbb2222-0000-0000-0000-000000000041';

select is(
  (select count(*)::int from public.notification_schedule
   where goal_id = 'bbbb2222-0000-0000-0000-000000000041' and kind = 'verdict'),
  1,
  'le cycle de debit ne re-annonce pas un verdict deja dit'
);

-- ------------------------------------- 6. la demande de preuve reste intacte
-- Les deux natures cohabitent dans la meme file : la nouvelle ne doit pas
-- avoir marche sur l'ancienne.
select is(
  (select count(*)::int from public.notification_schedule
   where kind = 'proof_window_open'),
  0,
  'aucune demande de preuve n''a ete creee par erreur'
);

select * from finish();
rollback;
