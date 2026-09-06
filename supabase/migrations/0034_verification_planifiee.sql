-- La verification des preuves part toute seule.
--
-- `verify-proof` etait la derniere fonction a lancer a la main. Une preuve
-- envoyee restait donc en `proof_submitted` indefiniment : l'utilisateur a
-- tenu sa promesse, l'a prouvee, et n'apprend rien. Il n'y perd pas d'argent
-- — c'est l'echeance de soumission qui compte, et elle est deja passee — mais
-- il reste sans reponse, ce qui est notre defaillance.
--
-- Meme mecanique que `send-push` (0033) : jeton court dans un en-tete a nous,
-- controle par la fonction. Un JWT ne survit pas au passage par pg_net.

create or replace function app.trigger_pending_verifications()
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

  -- Rien a verifier : on evite un appel HTTP par minute, toute la journee.
  select count(*) into v_due
  from goals
  where state = 'proof_submitted';

  if v_due = 0 then
    return;
  end if;

  perform net.http_post(
    url     := v_url || '/functions/v1/verify-proof',
    headers := jsonb_build_object(
      'Content-Type',   'application/json',
      'x-gage-trigger', v_secret
    ),
    body    := '{}'::jsonb
  );
end;
$$;

comment on function app.trigger_pending_verifications is
  'Reveille verify-proof s''il y a des preuves a examiner. Sans effet sur l''etat.';


-- ------------------------------------------------------------ le battement

-- Cinquieme temps. La verification vient apres la livraison : une preuve
-- envoyee a l'instant peut ainsi etre examinee dans le meme tour.
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

  -- Hors du chemin de l'argent : livraison et verification echouent sans
  -- annuler ce qui precede. Un objectif ne peut pas etre perdu parce qu'une
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
end;
$$;

comment on function app.tick_notifications is
  'Battement du cron : planifie, ouvre, clot, livre, verifie. Point d''entree unique, verrouille.';
