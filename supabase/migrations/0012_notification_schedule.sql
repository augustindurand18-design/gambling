-- 0012 — File de notifications planifiees
--
-- L'instant de declenchement est calcule COTE SERVEUR et n'est jamais expose
-- au client : c'est ce qui rend la fenetre de preuve imprevisible en mode
-- random_window, donc la photo impossible a preparer a l'avance.

create table public.notification_schedule (
  id uuid primary key default gen_random_uuid(),
  goal_id uuid references public.goals(id) on delete cascade,
  user_id uuid not null references public.profiles(user_id) on delete cascade,

  kind text not null check (kind in (
    'proof_window_open',   -- ouvre la fenetre : c'est LA notification surprise
    'proof_reminder',      -- rappel avant expiration
    'verdict',             -- resultat de la verification
    'dispute_deadline',    -- rappel de fin de fenetre de contestation
    'card_incident'        -- carte a mettre a jour
  )),

  fire_at timestamptz not null,
  sent_at timestamptz,
  attempts int not null default 0,
  last_error text,
  payload jsonb,

  created_at timestamptz not null default now()
);

-- Index de balayage du cron : les non-envoyees, par echeance
create index notification_pending_idx on public.notification_schedule (fire_at)
  where sent_at is null;
create index notification_goal_idx on public.notification_schedule (goal_id, kind);

-- Une seule notification d'ouverture de fenetre par objectif
create unique index notification_window_open_uniq
  on public.notification_schedule (goal_id)
  where kind = 'proof_window_open';
