-- 0013 — Journal d'audit des transitions d'etat
--
-- Toute transition est tracee, avec son declencheur. Sert a la fois au debug,
-- au support client et a la preuve en cas de litige.

create table public.goal_state_transitions (
  id bigint generated always as identity primary key,
  goal_id uuid not null references public.goals(id) on delete cascade,
  user_id uuid not null,

  from_state goal_state,
  to_state goal_state not null,

  -- 'system' | 'user' | 'reviewer:<uuid>' | 'stripe' | 'cron:<job>'
  actor text not null default 'system',
  reason text,
  metadata jsonb,

  created_at timestamptz not null default now()
);

create index goal_transitions_goal_idx
  on public.goal_state_transitions (goal_id, created_at);

-- Variable de session utilisee pour attribuer une transition a un acteur precis.
-- Les Edge Functions posent `set local app.actor = 'stripe'` avant leur UPDATE.
create or replace function app.current_actor()
returns text
language plpgsql
stable
as $$
begin
  return coalesce(nullif(current_setting('app.actor', true), ''), 'system');
end;
$$;

create or replace function app.current_transition_reason()
returns text
language plpgsql
stable
as $$
begin
  return nullif(current_setting('app.transition_reason', true), '');
end;
$$;
