-- 0001 — Extensions
-- pgcrypto : gen_random_uuid(), digest() pour les hash de consentement
-- pg_cron   : planification des jobs (schedule-notifications, send-push, close-expired...)
-- pg_net    : appels HTTP sortants depuis Postgres vers les Edge Functions

create extension if not exists pgcrypto with schema extensions;
create extension if not exists pg_cron;
create extension if not exists pg_net with schema extensions;

-- Schema applicatif pour les fonctions internes (garde public propre)
create schema if not exists app;
