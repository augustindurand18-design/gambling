-- 0001 — Extensions
-- pgcrypto : gen_random_uuid(), digest() pour les hash de consentement
-- pg_cron   : planification des jobs (schedule-notifications, send-push, close-expired...)
-- pg_net    : appels HTTP sortants depuis Postgres vers les Edge Functions

create extension if not exists pgcrypto with schema extensions;
create extension if not exists pg_cron;
create extension if not exists pg_net with schema extensions;

-- Schema applicatif pour les fonctions internes (garde public propre)
create schema if not exists app;

-- Les triggers du schema app s'executent avec les droits de l'appelant. Sans
-- ces droits, une simple ecriture cliente echouerait sur une erreur de
-- permission au lieu d'etre evaluee par la machine a etats.
-- Ces fonctions sont soit pures (tables de verite), soit des gardes : les
-- exposer ne donne acces a aucune donnee.
grant usage on schema app to authenticated, anon, service_role;

alter default privileges in schema app
  grant execute on functions to authenticated, anon, service_role;
