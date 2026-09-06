-- Sortie pour les objectifs qu'aucun humain ne vient examiner.
--
-- `human_review` n'avait aucune issue automatique : le tableau de revue
-- n'existe pas, rien dans le battement ne touchait ces objectifs, et ils
-- restaient sur l'accueil indefiniment, mise immobilisee sur le plafond de
-- leur proprietaire. Quelqu'un pouvait avoir tenu sa promesse, l'avoir
-- prouvee, et n'obtenir jamais de reponse.
--
-- Le sens de la cloture n'est pas un choix de confort : l'invariant 2 dit
-- qu'on ne debite jamais sur un doute. Un doute que personne ne leve dans le
-- delai imparti se resout donc EN FAVEUR DE L'UTILISATEUR — objectif tenu,
-- mise liberee par le declencheur de 0035, rien de preleve.
--
-- Ce que cela coute, et qui doit rester ecrit : la relecture aleatoire
-- anti-fraude (5 % des validations) se solde desormais par une validation
-- automatique si personne ne regarde. Elle ne dissuade donc plus rien tant
-- qu'aucun humain ne tient ce poste. Le jour ou le tableau de revue existera,
-- ce delai sera le temps laisse aux relecteurs, pas une porte de sortie.

create or replace function app.review_window_hours()
returns int
language sql
immutable
set search_path = public, app
as $$
  select 24;
$$;

comment on function app.review_window_hours is
  'Delai laisse a une revue humaine avant cloture automatique en faveur de l''utilisateur.';


create or replace function app.close_stale_reviews()
returns int
language plpgsql
security definer
set search_path = public, app
as $$
declare
  v_goal record;
  v_count int := 0;
begin
  for v_goal in
    -- L'anciennete se lit dans le journal, pas dans `goals.updated_at` : un
    -- declencheur remet celui-ci a `now()` a chaque ecriture, si bien qu'une
    -- revue oubliee depuis deux jours paraissait fraiche des qu'un champ
    -- avait bouge. Le journal, lui, date l'entree en revue et ne ment pas.
    select g.id
    from public.goals g
    where g.state = 'human_review'
      and (
        select max(t.created_at) from public.goal_state_transitions t
        where t.goal_id = g.id and t.to_state = 'human_review'
      ) < now() - make_interval(hours => app.review_window_hours())
    for update of g skip locked
  loop
    -- Un objectif malforme ne doit pas empecher les autres d'etre clos.
    begin
      perform public.transition_goal(
        v_goal.id,
        'closed_kept',
        'cron:close_stale_reviews',
        'revue humaine non tranchee dans le delai : au benefice de l''utilisateur'
      );
      v_count := v_count + 1;
    exception when others then
      null;
    end;
  end loop;

  return v_count;
end;
$$;

comment on function app.close_stale_reviews is
  'Clot au benefice de l''utilisateur les revues qu''aucun humain n''a tranchees.';


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
  perform app.close_stale_reviews();

  -- Hors du chemin de l'argent : chacun de ces reveils peut echouer sans
  -- annuler ce qui precede.
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
  'Battement du cron : planifie, ouvre, clot, arbitre, livre, verifie, debite.';
