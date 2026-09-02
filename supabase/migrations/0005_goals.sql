-- 0005 — Objectifs (entite centrale du domaine)

create table public.goals (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(user_id) on delete cascade,

  title text not null check (char_length(trim(title)) between 3 and 120),
  goal_type goal_type not null default 'object_scene',
  state goal_state not null default 'draft',

  -- Ce que la preuve doit montrer : sert a construire le prompt de verification.
  proof_instruction text check (char_length(proof_instruction) <= 500),

  charity_id uuid references public.charities(id),

  -- Planification de la fenetre de preuve
  window_mode window_mode not null,
  timezone text not null default 'Europe/Paris',
  target_date date not null,
  fixed_time_local time,          -- si window_mode = fixed_time
  window_start_local time,        -- si window_mode = random_window
  window_end_local time,          -- si window_mode = random_window

  -- Instants calcules (UTC)
  window_fire_at timestamptz,     -- pose par schedule-notifications
  window_opened_at timestamptz,   -- pose par send-push au moment reel de la notif
  proof_deadline_at timestamptz,
  dispute_deadline_at timestamptz,
  review_deadline_at timestamptz,

  committed_at timestamptz,
  closed_at timestamptz,

  human_review_reason text,

  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  -- Coherence du mode de fenetre
  constraint goals_window_mode_fields check (
    (window_mode = 'fixed_time'
      and fixed_time_local is not null
      and window_start_local is null
      and window_end_local is null)
    or
    (window_mode = 'random_window'
      and fixed_time_local is null
      and window_start_local is not null
      and window_end_local is not null
      and window_end_local > window_start_local)
  )
);

create index goals_user_state_idx on public.goals (user_id, state);
create index goals_state_fire_idx on public.goals (state, window_fire_at)
  where state = 'committed';
create index goals_state_proof_deadline_idx on public.goals (state, proof_deadline_at)
  where state = 'proof_window_open';
create index goals_state_dispute_deadline_idx on public.goals (state, dispute_deadline_at)
  where state = 'rejected';
create index goals_state_review_deadline_idx on public.goals (state, review_deadline_at)
  where state = 'human_review';

create trigger goals_touch_updated_at
  before update on public.goals
  for each row execute function app.touch_updated_at();
