-- 0004 — Associations beneficiaires
-- Une part de chaque mise perdue leur est reversee (charity_bps sur stakes).

create table public.charities (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique,
  name text not null,
  description text,
  logo_url text,
  website_url text,
  -- Reference de versement (pour plus tard : virement, Stripe Connect...).
  -- MVP : la societe collecte et reverse manuellement, avec reporting.
  payout_ref text,
  active boolean not null default true,
  sort_order int not null default 0,
  created_at timestamptz not null default now()
);

create index charities_active_idx on public.charities (active, sort_order);
