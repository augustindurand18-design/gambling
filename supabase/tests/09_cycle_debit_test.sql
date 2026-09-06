-- Tests pgTAP : cycle de vie d'un debit.
--
-- Ces fonctions sont les seules du depot qui deplacent de l'argent. Les tests
-- qui comptent le plus sont ceux qui verifient qu'elles refusent : on
-- n'encaisse pas un objectif que la machine a etats n'a pas declare perdu, et
-- on ne debite pas deux fois la meme mise parce qu'un webhook a rejoue.
--
-- Execution : supabase test db

begin;
select plan(17);

create extension if not exists pgtap with schema extensions;

-- ------------------------------------------------------------- fixtures
insert into auth.users (id, email, raw_user_meta_data)
values ('aaaa1111-0000-0000-0000-000000000001', 'alice@test.local', '{}'::jsonb);

update public.profiles
set stripe_customer_id = 'cus_test', default_payment_method_id = 'pm_test'
where user_id = 'aaaa1111-0000-0000-0000-000000000001';

insert into public.charities (id, slug, name)
values ('cccc0000-0000-0000-0000-000000000001', 'asso-test', 'Association de test');

-- Un objectif perdu, pret a etre encaisse.
insert into public.goals
  (id, user_id, title, state, window_mode, timezone, target_date,
   window_start_local, window_end_local, committed_at, charity_id, closed_at)
values
  ('bbbb2222-0000-0000-0000-000000000001',
   'aaaa1111-0000-0000-0000-000000000001',
   'Aller a la salle', 'closed_failed', 'random_window', 'Europe/Paris',
   current_date, '07:00', '10:00', now(),
   'cccc0000-0000-0000-0000-000000000001', now()),

  -- Un objectif encore contestable : intouchable.
  ('bbbb2222-0000-0000-0000-000000000002',
   'aaaa1111-0000-0000-0000-000000000001',
   'Reviser', 'rejected', 'random_window', 'Europe/Paris',
   current_date, '07:00', '10:00', now(),
   'cccc0000-0000-0000-0000-000000000001', null);

insert into public.stakes (goal_id, user_id, amount_cents, charity_bps, charity_id)
values
  ('bbbb2222-0000-0000-0000-000000000001',
   'aaaa1111-0000-0000-0000-000000000001', 1000, 2500,
   'cccc0000-0000-0000-0000-000000000001'),
  ('bbbb2222-0000-0000-0000-000000000002',
   'aaaa1111-0000-0000-0000-000000000001', 2000, 2500,
   'cccc0000-0000-0000-0000-000000000001');

-- ------------------------------------------------- ce qu'on refuse d'encaisser

select throws_ok(
  $$select * from public.begin_stake_charge('bbbb2222-0000-0000-0000-000000000002')$$,
  '23514', null,
  'Un objectif encore contestable n''est pas encaissable : la contestation existe pour servir'
);

select is(
  (select count(*)::int from public.charges
   where goal_id = 'bbbb2222-0000-0000-0000-000000000002'),
  0,
  'Le refus ne laisse aucune ligne de debit derriere lui'
);

-- ------------------------------------------------------ ouverture du debit

select lives_ok(
  $$select * from public.begin_stake_charge('bbbb2222-0000-0000-0000-000000000001')$$,
  'Un objectif perdu ouvre son debit'
);

select is(
  (select state::text from public.goals where id = 'bbbb2222-0000-0000-0000-000000000001'),
  'charge_pending',
  'L''objectif passe en charge_pending'
);

-- Le partage est fige au moment du debit : le bareme peut changer, la ligne
-- de comptabilite non.
select is(
  (select charity_amount_cents from public.charges
   where goal_id = 'bbbb2222-0000-0000-0000-000000000001'),
  250,
  'La part de l''association est figee a 25 % de la mise'
);

select is(
  (select charity_amount_cents + company_amount_cents from public.charges
   where goal_id = 'bbbb2222-0000-0000-0000-000000000001'),
  1000,
  'Le partage ne perd aucun centime'
);

-- Rejouable : une reprise apres coupure retrouve la ligne au lieu d'en creer
-- une seconde.
select lives_ok(
  $$select * from public.begin_stake_charge('bbbb2222-0000-0000-0000-000000000001')$$,
  'Une reprise ne casse pas sur un debit deja ouvert'
);

select is(
  (select count(*)::int from public.charges
   where goal_id = 'bbbb2222-0000-0000-0000-000000000001'),
  1,
  'Une reprise ne cree pas un second debit'
);

select is(
  (select attempt_count from public.charges
   where goal_id = 'bbbb2222-0000-0000-0000-000000000001'),
  2,
  'Chaque tentative est comptee'
);

-- ------------------------------------------------------------- l'echec

select lives_ok(
  $$select public.attach_charge_intent(
      (select id from public.charges where goal_id = 'bbbb2222-0000-0000-0000-000000000001'),
      'pi_test_1')$$,
  'Le PaymentIntent se rattache au debit'
);

select lives_ok(
  $$select public.settle_charge_failed('pi_test_1', 'card_declined', 'Carte refusee', false)$$,
  'Un refus de carte est enregistre'
);

select is(
  (select outstanding_balance_cents from public.profiles
   where user_id = 'aaaa1111-0000-0000-0000-000000000001'),
  1000,
  'La mise non encaissee devient un solde du'
);

select is(
  (select stake_block_active from public.profiles
   where user_id = 'aaaa1111-0000-0000-0000-000000000001'),
  true,
  'Un debit en echec gele la creation de nouveaux objectifs'
);

-- Rejeu du meme webhook : Stripe rejoue, parfois des heures apres.
select public.settle_charge_failed('pi_test_1', 'card_declined', 'Carte refusee', false);

select is(
  (select outstanding_balance_cents from public.profiles
   where user_id = 'aaaa1111-0000-0000-0000-000000000001'),
  1000,
  'Un webhook rejoue ne double pas le solde du'
);

-- ----------------------------------------------- une carte neuve ne solde rien

select public.set_default_payment_method(
  'aaaa1111-0000-0000-0000-000000000001', 'cus_test', 'pm_neuf',
  '4242', 'visa', 12, 2030
);

select is(
  (select stake_block_active from public.profiles
   where user_id = 'aaaa1111-0000-0000-0000-000000000001'),
  true,
  'Enregistrer une carte neuve ne leve pas le blocage tant qu''une mise est due'
);

-- ------------------------------------------------------------ le denouement

-- Nouvelle tentative apres mise a jour de la carte : c'est la sortie du
-- blocage, et elle doit exister sans quoi le gel serait definitif.
select public.begin_stake_charge('bbbb2222-0000-0000-0000-000000000001');
select public.attach_charge_intent(
  (select id from public.charges where goal_id = 'bbbb2222-0000-0000-0000-000000000001'),
  'pi_test_2'
);
select public.settle_charge_succeeded('pi_test_2');

select is(
  (select state::text from public.goals where id = 'bbbb2222-0000-0000-0000-000000000001'),
  'charge_ok',
  'Une relance aboutie encaisse la mise'
);

select is(
  (select outstanding_balance_cents = 0 and stake_block_active = false
   from public.profiles where user_id = 'aaaa1111-0000-0000-0000-000000000001'),
  true,
  'Le solde regle et une carte valide levent le blocage'
);

reset role;

select * from finish();
rollback;
