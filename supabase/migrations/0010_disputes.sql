-- 0010 — Contestations d'un verdict defavorable

create table public.disputes (
  id uuid primary key default gen_random_uuid(),
  goal_id uuid not null references public.goals(id) on delete cascade,
  proof_id uuid references public.proofs(id) on delete set null,
  user_id uuid not null references public.profiles(user_id) on delete cascade,

  reason text not null check (char_length(trim(reason)) between 5 and 1000),
  status dispute_status not null default 'open',

  filed_at timestamptz not null default now(),
  resolved_at timestamptz,
  reviewer_id text,
  resolution_note text,

  -- Marque les contestations manifestement infondees (compteur anti-abus)
  is_abusive boolean not null default false,

  created_at timestamptz not null default now()
);

-- Une seule contestation par objectif
create unique index disputes_goal_uniq on public.disputes (goal_id);
create index disputes_status_idx on public.disputes (status) where status in ('open', 'under_review');
create index disputes_user_idx on public.disputes (user_id, filed_at desc);
