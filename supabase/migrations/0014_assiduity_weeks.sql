-- 0014 — Assiduite hebdomadaire (pilote la remise d'abonnement)
--
-- Rappel du modele : 25 EUR/mois tarif de reference, ramene a 5 EUR/mois
-- en REMISE D'ASSIDUITE si l'utilisateur pose >= 3 objectifs par semaine et
-- les tient. Ce n'est pas une penalite (formulation juridique voulue).
--
-- Une semaine 'frozen' (incident carte) n'est pas comptee contre l'utilisateur.

create table public.assiduity_weeks (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(user_id) on delete cascade,

  -- Semaine ISO au format '2026-W36'
  iso_week text not null check (iso_week ~ '^\d{4}-W\d{2}$'),
  week_start_date date not null,

  goals_committed int not null default 0,
  goals_kept int not null default 0,

  status assiduity_status not null default 'normal',
  freeze_reason text,
  discount_earned boolean not null default false,

  computed_at timestamptz not null default now(),
  created_at timestamptz not null default now(),

  unique (user_id, iso_week)
);

create index assiduity_user_idx on public.assiduity_weeks (user_id, week_start_date desc);

-- Seuil d'objectifs tenus donnant droit a la remise
create or replace function app.assiduity_threshold()
returns int
language sql
immutable
as $$ select 3; $$;
