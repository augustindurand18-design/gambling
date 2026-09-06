-- Annoncer le verdict a celui qui a mis de l'argent en jeu.
--
-- L'ecran de preuve attend le verdict quarante secondes puis renonce : il ne
-- peut pas faire mieux, une reprise apres indisponibilite du modele prend
-- plusieurs minutes, et personne ne reste devant une roue qui tourne. Passe
-- ce delai, l'utilisateur ne savait plus rien. C'est arrive le 2026-09-06.
--
-- Le trou depasse le confort : sans notification, quelqu'un qui a ferme
-- l'application n'apprend JAMAIS qu'une mise a ete prelevee. Or c'est
-- precisement l'instant ou l'on veut etre prevenu.
--
-- La notification est posee par la base, a la transition, et non par
-- `verify-proof` : c'est la base qui fait autorite sur les etats (invariant 1),
-- et une decision prise par le cron — cloture d'echeance, revue oubliee —
-- doit s'annoncer autant qu'une decision du modele.

create or replace function app.notify_verdict()
returns trigger
language plpgsql
security definer
set search_path = public, app
as $$
declare
  v_outcome text;
begin
  -- Seuls les etats qui closent l'affaire. `validated` et `rejected` sont des
  -- etapes : annoncer les deux ferait deux notifications pour une seule
  -- decision, et la premiere serait dementie par la seconde en cas de debit.
  if new.state = 'closed_kept' then
    v_outcome := 'kept';
  elsif new.state = 'closed_failed' then
    v_outcome := 'failed';
  else
    return new;
  end if;

  -- Une seule annonce par objectif, quoi qu'il arrive ensuite.
  if exists (
    select 1 from public.notification_schedule
    where goal_id = new.id and kind = 'verdict'
  ) then
    return new;
  end if;

  insert into public.notification_schedule (goal_id, user_id, kind, fire_at, payload)
  values (
    new.id, new.user_id, 'verdict', now(),
    jsonb_build_object('outcome', v_outcome)
  );

  return new;
end;
$$;

comment on function app.notify_verdict is
  'Depose l''annonce du verdict des qu''un objectif est clos.';

drop trigger if exists goals_notify_verdict on public.goals;

create trigger goals_notify_verdict
  after update of state on public.goals
  for each row
  when (new.state in ('closed_kept', 'closed_failed')
        and old.state is distinct from new.state)
  execute function app.notify_verdict();


-- ---------------------------------------------------- livraison immediate

-- `deliver_pending_pushes` n'annoncait que les fenetres ouvertes. Un verdict
-- attend d'etre dit tout de suite : l'utilisateur vient de fermer l'ecran de
-- capture, il a la reponse en tete.
create or replace function app.deliver_pending_pushes()
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
  from notification_schedule n
  join goals g on g.id = n.goal_id
  where n.sent_at is null
    and n.attempts < 5
    and (
      (n.kind = 'proof_window_open' and g.state = 'proof_window_open')
      or n.kind = 'verdict'
    );

  if v_due = 0 then
    return;
  end if;

  perform net.http_post(
    url     := v_url || '/functions/v1/send-push',
    headers := jsonb_build_object(
      'Content-Type',   'application/json',
      'x-gage-trigger', v_secret
    ),
    body    := '{}'::jsonb
  );
end;
$$;

comment on function app.deliver_pending_pushes is
  'Reveille send-push s''il y a quelque chose a livrer. Sans effet sur l''etat.';
