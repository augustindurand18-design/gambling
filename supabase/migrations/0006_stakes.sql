-- 0006 — Mises engagees sur un objectif

create table public.stakes (
  id uuid primary key default gen_random_uuid(),
  goal_id uuid not null unique references public.goals(id) on delete cascade,
  user_id uuid not null references public.profiles(user_id) on delete cascade,

  amount_cents int not null check (amount_cents > 0),
  currency text not null default 'eur' check (currency = 'eur'),

  -- Part reversee a l'association, en points de base (2500 = 25 %).
  -- Fige au moment de l'engagement : une evolution du ratio ne modifie pas
  -- les mises deja consenties.
  charity_bps int not null check (charity_bps between 0 and 10000),
  charity_id uuid references public.charities(id),

  status stake_status not null default 'active',

  created_at timestamptz not null default now()
);

create index stakes_user_idx on public.stakes (user_id, created_at desc);

-- Repartition d'un montant : la part association est arrondie a l'entier
-- inferieur, le reliquat va a la societe (jamais de centime perdu).
create or replace function app.split_stake(p_amount_cents int, p_charity_bps int)
returns table (charity_amount_cents int, company_amount_cents int)
language sql
immutable
as $$
  select
    (p_amount_cents * p_charity_bps) / 10000 as charity_amount_cents,
    p_amount_cents - ((p_amount_cents * p_charity_bps) / 10000) as company_amount_cents;
$$;
