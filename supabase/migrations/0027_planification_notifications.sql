-- 0027 — Planification des controles surprises, en SQL
--
-- docs/architecture.md faisait porter la transition `committed ->
-- proof_window_open` par l'Edge Function `send-push`, « au moment ou elle
-- envoie la notification ». C'etait mettre la livraison APNs sur le chemin
-- critique de l'argent : une panne d'Apple, un jeton revoque, une variable
-- d'environnement absente, et la fenetre ne s'ouvre jamais — l'utilisateur ne
-- peut donc pas soumettre, l'echeance passe, et il est debite. Un incident
-- d'infrastructure deviendrait un debit, ce qui heurte de plein fouet
-- l'invariant 2.
--
-- L'ouverture revient donc a la base, qui fait deja autorite sur le cycle de
-- vie (invariant 1). `send-push` ne fait plus que livrer : son echec est sans
-- consequence sur l'etat. Effet de bord appreciable, toute la chaine devient
-- verifiable en local sans compte Apple Developer.
--
-- Toutes les fonctions posent leur `search_path` des leur creation : la lecon
-- de 0024, dont l'avertissement n'etait visible que sur le projet cloud.


-- ------------------------------------------------- garde-fous sur les goals

-- `goals.timezone` est ecrit par le client (0023 lui rend le droit d'insert)
-- et n'etait valide nulle part. Un nom IANA invalide leve
-- `invalid_parameter_value` a la premiere conversion — c'est-a-dire au milieu
-- de la boucle du cron, ce qui avorterait tout le lot : un seul objectif
-- malforme empecherait l'ouverture des fenetres de tout le monde.
create or replace function app.validate_goal_timezone()
returns trigger
language plpgsql
set search_path = public, app
as $$
begin
  begin
    perform now() at time zone new.timezone;
  exception when others then
    raise exception 'Fuseau horaire inconnu : %', new.timezone
      using errcode = 'check_violation';
  end;
  return new;
end;
$$;

create trigger goals_validate_timezone
  before insert or update of timezone on public.goals
  for each row execute function app.validate_goal_timezone();

comment on function app.validate_goal_timezone is
  'Refuse un fuseau inconnu a l''ecriture plutot qu''a l''ouverture de la fenetre, ou il ferait tomber tout le lot du cron.';

-- `goals_window_mode_fields` (0005) n'impose que `end > start`. Une fenetre de
-- dix minutes est plus courte que le delai de soumission : le tirage n'aurait
-- alors plus aucune place ou tomber.
--
-- Le litteral reprend app.proof_window_seconds(). Une contrainte de table ne
-- peut pas dependre d'une fonction qu'on voudrait pouvoir changer : les deux
-- doivent bouger ensemble, et le test 05 le verifie.
alter table public.goals
  add constraint goals_window_long_enough check (
    window_mode <> 'random_window'
    or window_end_local - window_start_local >= interval '15 minutes'
  );

-- `goals_state_fire_idx` a disparu avec sa colonne en 0023, et
-- `goals_user_state_idx` est prefixe par `user_id` : le balayage du cron,
-- qui cherche tous les `committed` sans distinction d'utilisateur, n'avait
-- plus d'index.
create index goals_committed_idx on public.goals (target_date)
  where state = 'committed';


-- ------------------------------------------------------------- constantes

-- Fenetre de contestation d'un verdict defavorable. La documentation dit
-- « 24-48 h » ; le code doit trancher une fois, ici.
create or replace function app.dispute_window_hours()
returns int
language sql
immutable
set search_path = public, app
as $$
  select 48;
$$;

comment on function app.dispute_window_hours is
  'Duree pendant laquelle un objectif rejete reste contestable.';


-- ------------------------------------------------------- tirage de l'instant

-- Instant du controle surprise, tire dans le creneau choisi.
--
-- La fonction est pure et son alea est un parametre : `random()` enfoui dans
-- une fonction n'est pas testable, et `setseed()` est un etat de session que
-- pgTAP ne controle pas proprement. La production laisse le defaut, les tests
-- passent 0, 0.5 et 1 et verifient les bornes.
--
-- Piege de fuseau assume : le 30 mars, 02:30 local n'existe pas, et Postgres
-- decale silencieusement ; le 26 octobre, 02:30 est ambigu et il retient la
-- premiere occurrence. Les objectifs a 2 h du matin sont marginaux, mais que
-- personne ne « corrige » cet offset dans six mois sans lire ceci — les tests
-- 05 figent le comportement en heure d'hiver et en heure d'ete.
create or replace function app.pick_window_fire_at(
  p_target_date date,
  p_tz text,
  p_start time,
  p_end time,
  p_span_sec int,
  p_random double precision default random()
)
returns timestamptz
language plpgsql
-- `stable` et non `immutable` : `at time zone <nom>` depend de la base de
-- fuseaux, qu'une mise a jour systeme peut changer. La declarer immuable
-- autoriserait le planificateur a figer un resultat qui ne l'est pas.
stable
set search_path = public, app
as $$
declare
  v_start timestamptz := (p_target_date + p_start) at time zone p_tz;
  v_end   timestamptz := (p_target_date + p_end)   at time zone p_tz;
  v_last  timestamptz;
  v_span  int;
begin
  -- Le dernier instant acceptable laisse au moins le delai de soumission
  -- avant la fin du creneau annonce. `greatest` est un filet : la contrainte
  -- goals_window_long_enough garantit deja que la fenetre est assez large,
  -- mais une donnee anterieure a cette migration pourrait ne pas l'etre.
  v_last := greatest(v_start, v_end - make_interval(secs => p_span_sec));
  v_span := extract(epoch from (v_last - v_start))::int;

  -- `random()` rend [0,1) ; un test peut passer 1 exactement. On borne pour
  -- que l'instant tire reste dans le creneau dans tous les cas.
  return v_start + make_interval(
    secs => least(floor(p_random * (v_span + 1))::int, v_span)
  );
end;
$$;

comment on function app.pick_window_fire_at is
  'Instant du controle surprise dans un creneau. Pure, alea injectable pour les tests.';


-- ---------------------------------------------------------- 1. planification

-- Met en file un controle pour chaque objectif engage qui n'en a pas encore.
--
-- Une promesse hebdomadaire arrive en plusieurs lignes de `goals` partageant
-- un `plan_id` (0025) : on planifie par objectif, pas par plan.
create or replace function app.schedule_proof_windows()
returns int
language plpgsql
security definer
set search_path = public, app
as $$
declare
  v_goal record;
  v_fire_at timestamptz;
  v_count int := 0;
begin
  for v_goal in
    select g.id, g.user_id, g.timezone, g.target_date, g.window_mode,
           g.fixed_time_local, g.window_start_local, g.window_end_local
    from public.goals g
    where g.state = 'committed'
      and not exists (
        select 1 from public.notification_schedule n
        where n.goal_id = g.id and n.kind = 'proof_window_open'
      )
  loop
    -- Un objectif malforme ne doit jamais empecher les autres d'etre
    -- planifies : chaque tour a son propre filet.
    begin
      if v_goal.window_mode = 'fixed_time' then
        -- L'heure EST la promesse (un reveil) : aucun alea a ajouter.
        v_fire_at := (v_goal.target_date + v_goal.fixed_time_local)
                     at time zone v_goal.timezone;
      else
        v_fire_at := app.pick_window_fire_at(
          v_goal.target_date,
          v_goal.timezone,
          v_goal.window_start_local,
          v_goal.window_end_local,
          app.proof_window_seconds()
        );
      end if;

      -- `on conflict` sans cible : l'inference sur l'index unique partiel
      -- notification_window_open_uniq (0012) exigerait d'en repeter le
      -- predicat, et se tromper la rendrait la planification non rejouable.
      insert into public.notification_schedule (goal_id, user_id, kind, fire_at)
      values (v_goal.id, v_goal.user_id, 'proof_window_open', v_fire_at)
      on conflict do nothing;

      v_count := v_count + 1;

    exception when others then
      raise warning 'Planification impossible pour l''objectif % : %',
        v_goal.id, sqlerrm;
    end;
  end loop;

  return v_count;
end;
$$;


-- ------------------------------------------------------------- 2. ouverture

-- Ouvre les fenetres dues. C'est ici, et nulle part ailleurs, que commence le
-- compte a rebours qui met une mise en jeu.
--
-- Ne marque pas `sent_at` : la livraison est le travail de `send-push`, et son
-- echec ne doit rien changer a l'etat de l'objectif.
create or replace function app.open_due_proof_windows()
returns int
language plpgsql
security definer
set search_path = public, app
as $$
declare
  v_row record;
  v_count int := 0;
begin
  for v_row in
    select n.id, n.goal_id, n.user_id
    from public.notification_schedule n
    join public.goals g on g.id = n.goal_id
    where n.kind = 'proof_window_open'
      and n.sent_at is null
      and n.fire_at <= now()
      and g.state = 'committed'
    -- `skip locked` : deux passages du cron peuvent se chevaucher, et le
    -- second n'a pas a attendre le premier pour traiter le reste de la file.
    for update of n skip locked
  loop
    begin
      -- On n'ouvre pas une fenetre qu'on est incapable d'annoncer. Sans
      -- appareil joignable, le compte a rebours de quinze minutes partirait
      -- dans le vide et l'utilisateur perdrait sa mise sans avoir rien su :
      -- ce serait lui faire payer notre incapacite a le prevenir.
      if not exists (
        select 1 from public.devices d
        where d.user_id = v_row.user_id and d.revoked = false
      ) then
        update public.notification_schedule
        set last_error = 'aucun appareil actif : fenetre non ouverte'
        where id = v_row.id;
        continue;
      end if;

      perform public.transition_goal(
        v_row.goal_id,
        'proof_window_open',
        'cron:open_due_proof_windows',
        'ouverture de la fenetre de preuve',
        jsonb_build_object(
          'window_opened_at', now(),
          'proof_deadline_at', now() + make_interval(secs => app.proof_window_seconds())
        )
      );

      update public.notification_schedule
      set last_error = null
      where id = v_row.id;

      v_count := v_count + 1;

    exception when others then
      update public.notification_schedule
      set last_error = left(sqlerrm, 500)
      where id = v_row.id;
      raise warning 'Ouverture impossible pour l''objectif % : %',
        v_row.goal_id, sqlerrm;
    end;
  end loop;

  return v_count;
end;
$$;


-- -------------------------------------------------------------- 3. cloture

-- Fait tomber les echeances passees.
--
-- Cette fonction est la seule de ce fichier qui decide qu'un objectif est
-- perdu : tout ce qu'elle fait finit en argent. Elle est donc deliberement
-- avare — un doute ne se tranche jamais en faveur du debit.
create or replace function app.close_expired_goals()
returns int
language plpgsql
security definer
set search_path = public, app
as $$
declare
  v_goal record;
  v_count int := 0;
begin
  -- (a) Fenetre ouverte, delai ecoule, aucune preuve. L'utilisateur a ete
  -- prevenu et n'a pas repondu : c'est le cas nominal de l'echec.
  for v_goal in
    select id from public.goals
    where state = 'proof_window_open'
      and proof_deadline_at is not null
      and now() > proof_deadline_at + make_interval(secs => app.proof_clock_grace_seconds())
    for update skip locked
  loop
    begin
      perform public.transition_goal(
        v_goal.id, 'rejected', 'cron:close_expired_goals',
        'aucune preuve avant l''echeance',
        jsonb_build_object(
          'dispute_deadline_at', now() + make_interval(hours => app.dispute_window_hours())
        )
      );
      v_count := v_count + 1;
    exception when others then
      raise warning 'Cloture impossible pour l''objectif % : %', v_goal.id, sqlerrm;
    end;
  end loop;

  -- (b) Rejet non conteste dans les temps. `is not null` est explicite a
  -- dessein : une echeance absente ne doit jamais etre lue comme echue, et
  -- personne ne doit etre tente de « simplifier » en coalesce(..., now()).
  for v_goal in
    select id from public.goals
    where state = 'rejected'
      and dispute_deadline_at is not null
      and now() > dispute_deadline_at
    for update skip locked
  loop
    begin
      perform public.transition_goal(
        v_goal.id, 'closed_failed', 'cron:close_expired_goals',
        'fenetre de contestation expiree'
      );
      v_count := v_count + 1;
    exception when others then
      raise warning 'Cloture impossible pour l''objectif % : %', v_goal.id, sqlerrm;
    end;
  end loop;

  -- (c) Objectif engage dont la fenetre n'a JAMAIS ete ouverte alors que son
  -- jour est passe.
  --
  -- 0015 autorise `committed -> rejected` comme filet de securite. On ne s'en
  -- sert pas, et c'est delibere : si la fenetre ne s'est pas ouverte, c'est
  -- notre faute — cron arrete, aucun appareil enregistre, migration en cours.
  -- Debiter quelqu'un pour une panne dont il n'a rien su serait exactement ce
  -- que l'invariant 2 interdit.
  --
  -- L'objectif reste donc `committed` et sa mise reste `active`. Il n'y a pas
  -- aujourd'hui de sortie honnete pour ce cas : il faudrait un
  -- `committed -> human_review`, qui n'existe ni dans 0015 ni dans
  -- GoalStateMachine.swift. En attendant, on le rend visible.
  update public.notification_schedule n
  set last_error = 'fenetre jamais ouverte : a examiner'
  from public.goals g
  where g.id = n.goal_id
    and n.kind = 'proof_window_open'
    and g.state = 'committed'
    and n.fire_at < now() - interval '1 day'
    and n.last_error is distinct from 'fenetre jamais ouverte : a examiner';

  return v_count;
end;
$$;


-- ------------------------------------------------------------ 4. le battement

-- Un seul job cron, pas trois.
--
-- pg_cron ne saute pas une execution si la precedente tourne encore : trois
-- jobs a la minute finiraient par se marcher dessus, dans un ordre non
-- garanti. Un seul point d'entree donne un ordre deterministe — planifier,
-- ouvrir, clore — un seul verrou, et un seul interrupteur en cas d'incident.
create or replace function app.tick_notifications()
returns void
language plpgsql
security definer
set search_path = public, app
as $$
begin
  -- Si un tour precedent tourne encore, celui-ci n'a rien a faire : la file
  -- sera traitee dans une minute.
  if not pg_try_advisory_xact_lock(hashtext('gage.tick')::bigint) then
    return;
  end if;

  perform app.schedule_proof_windows();
  perform app.open_due_proof_windows();
  perform app.close_expired_goals();
end;
$$;

comment on function app.tick_notifications is
  'Battement du cron : planifie, ouvre, clot. Point d''entree unique, verrouille.';


-- ------------------------------------------------------------- planification

-- `cron.unschedule` leve si le job n'existe pas, et une migration doit pouvoir
-- etre rejouee a froid comme sur une base ou elle est deja passee.
do $$
begin
  perform cron.unschedule('gage-tick');
exception when others then
  null;
end;
$$;

select cron.schedule('gage-tick', '* * * * *', 'select app.tick_notifications();');
