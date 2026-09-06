-- Livraison des notifications sans intervention humaine.
--
-- `send-push` etait la derniere piece a lancer a la main : le cron ouvrait la
-- fenetre de preuve (0027), mais personne n'annoncait rien a l'utilisateur
-- tant qu'un developpeur n'avait pas appele la fonction. Un objectif pouvait
-- donc arriver a echeance sans que son proprietaire ait jamais ete prevenu.
--
-- Ce qui bloquait n'etait pas technique mais editorial : appeler une Edge
-- Function depuis Postgres demande une cle, et le depot est public. La cle est
-- donc lue dans Vault, jamais ecrite ici. Tant qu'elle n'y est pas, cette
-- migration s'applique et le battement continue sans livrer — le comportement
-- d'avant, pas une panne.
--
-- On lit la cle *anon* et non le service role : `send-push` porte deja ses
-- propres droits par son environnement, elle n'attend de l'appelant qu'un
-- jeton valide. Cette cle voyage deja dans l'application iOS, la poser ici
-- n'ouvre rien de neuf.


-- --------------------------------------------------------------- 1. la cle

-- Rend l'un des deux reglages, ou null s'il n'a pas ete pose. Le nom est fixe
-- pour que `supabase secrets` et Vault ne divergent pas silencieusement.
create or replace function app.edge_setting(p_name text)
returns text
language sql
stable
security definer
set search_path = vault, public
as $$
  select decrypted_secret
  from vault.decrypted_secrets
  where name = p_name
  limit 1;
$$;

comment on function app.edge_setting is
  'Reglage d''appel des Edge Functions, lu dans Vault. Null si absent.';

revoke all on function app.edge_setting(text) from public, anon, authenticated;


-- ---------------------------------------------------- 2. l'appel a send-push

-- Sans effet sur l'etat d'un objectif, et c'est voulu : la fenetre est deja
-- ouverte et l'echeance court. Une panne d'Apple, de Vault ou du reseau ne
-- peut donc pas faire perdre d'argent a quelqu'un — meme raison qu'en 0027.
create or replace function app.deliver_pending_pushes()
returns void
language plpgsql
security definer
set search_path = public, app, extensions
as $$
declare
  v_url text := app.edge_setting('edge_project_url');
  v_key text := app.edge_setting('edge_anon_key');
  v_due int;
begin
  if v_url is null or v_key is null then
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

  -- `net.http_post` rend un identifiant de requete et ne bloque pas : la
  -- reponse est collectee plus tard par pg_net. On ne l'attend pas, et on n'en
  -- fait rien — c'est `send-push` qui inscrit succes et erreur dans
  -- `notification_schedule`, la seule trace qui compte.
  perform net.http_post(
    url     := v_url || '/functions/v1/send-push',
    headers := jsonb_build_object(
      'Content-Type',  'application/json',
      'Authorization', 'Bearer ' || v_key
    ),
    body    := '{}'::jsonb
  );
end;
$$;

comment on function app.deliver_pending_pushes is
  'Reveille send-push s''il y a quelque chose a livrer. Sans effet sur l''etat.';


-- ------------------------------------------------------ 3. le battement

-- Quatrieme temps, en dernier : planifier, ouvrir, clore, puis livrer. La
-- livraison vient apres l'ouverture pour que la fenetre du tour courant parte
-- dans la foulee, sans attendre la minute suivante.
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

  -- Hors du chemin de l'argent : si la livraison echoue, le reste du tour a
  -- deja eu lieu et rien n'est annule.
  begin
    perform app.deliver_pending_pushes();
  exception when others then
    null;
  end;
end;
$$;

comment on function app.tick_notifications is
  'Battement du cron : planifie, ouvre, clot, livre. Point d''entree unique, verrouille.';
