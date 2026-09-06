-- Deux bouts manquants du cycle de l'argent.
--
-- 1. Aucune mise n'etait jamais liberee. `stake_status` prevoit `released`,
--    mais rien ne le posait : un objectif TENU gardait sa mise `active` a
--    vie, et elle continuait de consommer le plafond mensuel. Quelqu'un de
--    parfaitement assidu finissait donc bloque par ses propres reussites.
--
-- 2. Personne n'appelait le debit. Le cycle (`0029`) et `stripe-charge-stake`
--    sont ecrits et testes, mais aucun declencheur ne les invoquait : une
--    mise perdue restait due indefiniment. Ce n'etait pas une clemence utile
--    — l'objectif restait `closed_failed`, l'utilisateur restait avec une
--    dette sans echeance, et rien ne le lui disait.


-- --------------------------------------------- 1. liberer les mises tenues

create or replace function app.release_stake_on_kept()
returns trigger
language plpgsql
security definer
set search_path = public, app
as $$
begin
  -- `charged` n'est jamais retouche : une mise deja debitee ne redevient pas
  -- libre parce qu'un etat a bouge.
  update public.stakes
  set status = 'released'
  where goal_id = new.id
    and status = 'active';

  return new;
end;
$$;

comment on function app.release_stake_on_kept is
  'Libere la mise d''un objectif tenu : elle ne doit plus peser sur le plafond.';

drop trigger if exists goals_release_stake on public.goals;

create trigger goals_release_stake
  after update of state on public.goals
  for each row
  when (new.state = 'closed_kept' and old.state is distinct from 'closed_kept')
  execute function app.release_stake_on_kept();

-- Rattrapage de l'existant : les objectifs deja tenus tiennent encore le
-- plafond de leur proprietaire, et aucun evenement ne repassera sur eux.
update public.stakes s
set status = 'released'
where s.status = 'active'
  and exists (
    select 1 from public.goals g
    where g.id = s.goal_id and g.state = 'closed_kept'
  );


-- ------------------------------------------------ 2. declencher les debits

-- `stripe-charge-stake` prend toute la file `closed_failed` / `charge_failed`
-- et appelle `begin_stake_charge` elle-meme : il n'y a qu'a la reveiller.
create or replace function app.trigger_pending_charges()
returns void
language plpgsql
security definer
set search_path = public, app, extensions
as $$
declare
  v_url text := app.edge_setting('edge_project_url');
  v_secret text := app.edge_setting('edge_trigger_secret');
  v_due int;
begin
  if v_url is null or v_secret is null then
    return;
  end if;

  select count(*) into v_due
  from goals
  where state in ('closed_failed', 'charge_failed');

  if v_due = 0 then
    return;
  end if;

  perform net.http_post(
    url     := v_url || '/functions/v1/stripe-charge-stake',
    headers := jsonb_build_object(
      'Content-Type',   'application/json',
      'x-gage-trigger', v_secret
    ),
    body    := '{}'::jsonb
  );
end;
$$;

comment on function app.trigger_pending_charges is
  'Reveille stripe-charge-stake s''il y a des mises perdues a debiter.';


-- ------------------------------------------------------------ le battement

create or replace function app.tick_notifications()
returns void
language plpgsql
security definer
set search_path = public, app
as $$
begin
  if not pg_try_advisory_xact_lock(hashtext('gage.tick')::bigint) then
    return;
  end if;

  perform app.schedule_proof_windows();
  perform app.open_due_proof_windows();
  perform app.close_expired_goals();

  -- Hors du chemin de l'argent : chacun de ces reveils peut echouer sans
  -- annuler ce qui precede. Un objectif ne doit pas etre perdu parce qu'une
  -- Edge Function etait indisponible.
  begin
    perform app.deliver_pending_pushes();
  exception when others then
    null;
  end;

  begin
    perform app.trigger_pending_verifications();
  exception when others then
    null;
  end;

  begin
    perform app.trigger_pending_charges();
  exception when others then
    null;
  end;
end;
$$;

comment on function app.tick_notifications is
  'Battement du cron : planifie, ouvre, clot, livre, verifie, debite. Point d''entree unique, verrouille.';
