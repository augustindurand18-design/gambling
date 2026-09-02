-- 0015 — Machine a etats : legalite des transitions imposee par la base
--
-- Cette contrainte s'applique a TOUT LE MONDE, service role compris. Un bug
-- dans une Edge Function ne peut pas faire sauter un objectif de 'committed'
-- directement a 'charge_ok'. La base est la derniere ligne de defense avant
-- de toucher a l'argent de l'utilisateur.
--
-- Cycle nominal :
--   draft -> committed -> proof_window_open -> proof_submitted -> ai_verifying
--         -> validated | rejected
--         -> (contestation) human_review
--         -> closed_kept | closed_failed
--         -> charge_pending -> charge_ok | charge_failed

create or replace function app.goal_state_allowed(
  p_from goal_state,
  p_to goal_state
)
returns boolean
language sql
immutable
as $$
  select (p_from, p_to) in (
    -- Engagement
    ('draft',             'committed'),

    -- Ouverture de la fenetre de preuve (send-push)
    ('committed',         'proof_window_open'),
    -- Filet de securite : fenetre jamais ouverte et echeance depassee
    ('committed',         'rejected'),

    -- Soumission de la preuve
    ('proof_window_open', 'proof_submitted'),
    -- Echeance depassee sans preuve (close-expired)
    ('proof_window_open', 'rejected'),

    -- Verification
    ('proof_submitted',   'ai_verifying'),
    -- Rejet immediat : preuve soumise hors fenetre, image deja vue, etc.
    ('proof_submitted',   'rejected'),

    ('ai_verifying',      'validated'),
    ('ai_verifying',      'rejected'),
    ('ai_verifying',      'human_review'),

    -- Echantillon aleatoire anti-fraude sur un verdict favorable
    ('validated',         'human_review'),
    ('validated',         'closed_kept'),

    -- Contestation ouverte par l'utilisateur
    ('rejected',          'human_review'),
    -- Fenetre de contestation expiree sans contestation
    ('rejected',          'closed_failed'),

    -- Decision du reviewer humain, definitive
    ('human_review',      'closed_kept'),
    ('human_review',      'closed_failed'),

    -- Encaissement
    ('closed_failed',     'charge_pending'),
    ('charge_pending',    'charge_ok'),
    ('charge_pending',    'charge_failed'),
    -- Nouvelle tentative apres mise a jour de la carte (Smart Retries)
    ('charge_failed',     'charge_pending'),
    -- Une relance Stripe peut aboutir directement
    ('charge_failed',     'charge_ok')
  );
$$;

comment on function app.goal_state_allowed is
  'Table de verite des transitions legales. Toute evolution du cycle de vie passe par ici.';

-- Etats terminaux : plus aucune transition sortante.
create or replace function app.goal_state_is_terminal(p_state goal_state)
returns boolean
language sql
immutable
as $$
  select p_state in ('closed_kept', 'charge_ok');
$$;

-- Garde + journalisation automatique de chaque changement d'etat.
create or replace function app.enforce_goal_transition()
returns trigger
language plpgsql
as $$
begin
  if new.state is distinct from old.state then

    if not app.goal_state_allowed(old.state, new.state) then
      raise exception
        'Transition d''etat illegale : % -> % (objectif %)',
        old.state, new.state, old.id
        using errcode = 'check_violation';
    end if;

    -- Horodatage automatique de la cloture
    if new.state in ('closed_kept', 'closed_failed') and new.closed_at is null then
      new.closed_at := now();
    end if;

    insert into public.goal_state_transitions
      (goal_id, user_id, from_state, to_state, actor, reason)
    values
      (old.id, old.user_id, old.state, new.state,
       app.current_actor(), app.current_transition_reason());
  end if;

  return new;
end;
$$;

create trigger goals_enforce_transition
  before update of state on public.goals
  for each row execute function app.enforce_goal_transition();

-- Journalise egalement la creation (transition initiale vers 'draft').
create or replace function app.log_goal_creation()
returns trigger
language plpgsql
as $$
begin
  insert into public.goal_state_transitions
    (goal_id, user_id, from_state, to_state, actor, reason)
  values
    (new.id, new.user_id, null, new.state, app.current_actor(), 'creation');
  return new;
end;
$$;

create trigger goals_log_creation
  after insert on public.goals
  for each row execute function app.log_goal_creation();

-- Un objectif ne peut plus etre modifie une fois engage, hormis son etat et
-- les instants calcules par le serveur. Protege le contenu de la promesse.
create or replace function app.freeze_committed_goal()
returns trigger
language plpgsql
as $$
begin
  if old.state <> 'draft' then
    if new.title is distinct from old.title
       or new.goal_type is distinct from old.goal_type
       or new.proof_instruction is distinct from old.proof_instruction
       or new.charity_id is distinct from old.charity_id
       or new.window_mode is distinct from old.window_mode
       or new.target_date is distinct from old.target_date
       or new.fixed_time_local is distinct from old.fixed_time_local
       or new.window_start_local is distinct from old.window_start_local
       or new.window_end_local is distinct from old.window_end_local
       or new.timezone is distinct from old.timezone
    then
      raise exception
        'Un objectif engage est fige : seuls son etat et ses echeances peuvent evoluer (objectif %)',
        old.id
        using errcode = 'check_violation';
    end if;
  end if;
  return new;
end;
$$;

create trigger goals_freeze_committed
  before update on public.goals
  for each row execute function app.freeze_committed_goal();
