-- 0011 — Appareils enregistres pour les notifications APNs

create table public.devices (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(user_id) on delete cascade,

  apns_token text not null,
  env text not null default 'sandbox' check (env in ('sandbox', 'production')),
  bundle_id text,
  app_version text,
  os_version text,
  model text,

  revoked boolean not null default false,
  last_seen_at timestamptz not null default now(),
  created_at timestamptz not null default now(),

  unique (user_id, apns_token)
);

create index devices_active_idx on public.devices (user_id) where revoked = false;
