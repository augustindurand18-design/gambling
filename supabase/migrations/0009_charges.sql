-- 0009 — Debits des mises perdues (Stripe)

create table public.charges (
  id uuid primary key default gen_random_uuid(),
  goal_id uuid not null references public.goals(id) on delete cascade,
  stake_id uuid not null references public.stakes(id) on delete cascade,
  user_id uuid not null references public.profiles(user_id) on delete cascade,

  amount_cents int not null check (amount_cents > 0),
  currency text not null default 'eur',

  -- Repartition figee au moment du debit
  charity_bps int not null,
  charity_id uuid references public.charities(id),
  charity_amount_cents int not null check (charity_amount_cents >= 0),
  company_amount_cents int not null check (company_amount_cents >= 0),

  stripe_payment_intent_id text unique,
  status charge_status not null default 'pending',

  failure_code text,
  failure_message text,
  attempt_count int not null default 0,
  last_attempt_at timestamptz,
  succeeded_at timestamptz,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  constraint charges_split_sums check (
    charity_amount_cents + company_amount_cents = amount_cents
  )
);

-- Un seul debit par objectif
create unique index charges_goal_uniq on public.charges (goal_id);
create index charges_user_idx on public.charges (user_id, created_at desc);
create index charges_status_idx on public.charges (status)
  where status in ('pending', 'processing', 'requires_action');

create trigger charges_touch_updated_at
  before update on public.charges
  for each row execute function app.touch_updated_at();

-- Journal des evenements Stripe deja traites : garantit l'idempotence des webhooks.
create table public.stripe_events (
  id text primary key,                  -- Stripe event id (evt_...)
  type text not null,
  processed_at timestamptz not null default now(),
  payload jsonb
);
