-- 0003 — Profils utilisateur (1:1 avec auth.users)

create table public.profiles (
  user_id uuid primary key references auth.users(id) on delete cascade,

  display_name text,
  email text,

  -- Stripe
  stripe_customer_id text unique,
  default_payment_method_id text,
  pm_last4 text,
  pm_brand text,
  pm_exp_month int,
  pm_exp_year int,

  -- Plafonds acceptes a l'onboarding (voir consents.onboarding_caps)
  per_goal_cap_cents int not null default 3000,      -- 30 EUR
  monthly_cap_cents int not null default 15000,      -- 150 EUR

  -- Blocage suite a un echec d'encaissement
  stake_block_active boolean not null default false,
  stake_block_reason text,
  stake_block_since timestamptz,
  outstanding_balance_cents int not null default 0
    check (outstanding_balance_cents >= 0),

  -- Abonnement (reporte apres la beta ; on stocke deja l'etat calcule)
  subscription_tier text not null default 'none',
  assiduity_discount_active boolean not null default false,

  onboarding_completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on column public.profiles.outstanding_balance_cents is
  'Somme des mises dues suite a un echec de debit. Doit revenir a 0 pour lever stake_block_active.';

-- Cree automatiquement le profil a l'inscription
create or replace function app.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
begin
  insert into public.profiles (user_id, email, display_name)
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data ->> 'full_name', new.raw_user_meta_data ->> 'name')
  )
  on conflict (user_id) do nothing;
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function app.handle_new_user();

-- Maintient updated_at
create or replace function app.touch_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

create trigger profiles_touch_updated_at
  before update on public.profiles
  for each row execute function app.touch_updated_at();
