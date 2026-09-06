-- Le declenchement de send-push ne passe plus par un JWT.
--
-- `0032` appelait la fonction avec la cle anon dans un en-tete
-- `Authorization`. Le portail repondait invariablement 401
-- `UNAUTHORIZED_INVALID_JWT_FORMAT` — y compris avec la cle ecrite en dur
-- dans la requete, ce qui innocente Vault : pg_net ne transporte pas sans
-- dommage une valeur d'en-tete de 215 caracteres. La meme cle envoyee par
-- `curl` passe sans probleme.
--
-- On envoie donc un jeton court, dans un en-tete a nous, et c'est
-- `send-push` qui le controle (elle est deployee avec `--no-verify-jwt`).
-- Ce que ce jeton protege est mince : declencher la livraison de
-- notifications deja dues. Aucune donnee lue, aucun etat change.
--
-- Le secret se pose dans Vault sous le nom `edge_trigger_secret`, jamais
-- ici : le depot est public.

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

  -- Rien a annoncer : on evite un appel HTTP par minute, toute la journee.
  select count(*) into v_due
  from notification_schedule n
  join goals g on g.id = n.goal_id
  where n.kind = 'proof_window_open'
    and n.sent_at is null
    and n.attempts < 5
    and g.state = 'proof_window_open';

  if v_due = 0 then
    return;
  end if;

  -- `net.http_post` rend un identifiant de requete et ne bloque pas. On
  -- n'attend pas la reponse et on n'en fait rien : c'est `send-push` qui
  -- inscrit succes et erreur dans `notification_schedule`, la seule trace qui
  -- compte. En cas de doute, `net._http_response` garde le code HTTP.
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
