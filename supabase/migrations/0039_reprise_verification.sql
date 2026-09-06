-- Reprendre une verification que le modele n'a pas pu faire.
--
-- Un quota depasse, une panne reseau, une erreur serveur : le modele n'a pas
-- regarde l'image, et il pourrait y arriver dans une minute. Jusqu'ici cette
-- indisponibilite produisait un verdict definitif — `uncertain`, donc valide
-- au benefice du doute. C'est arrive le 2026-09-06 : une photo d'ordinateur
-- validee pour une seance de sport, parce que Gemini repondait `429`.
--
-- Le trou est plus large qu'une erreur d'affichage : n'importe qui pouvait
-- obtenir une validation en soumettant pendant une saturation.
--
-- La preuve retourne donc en `proof_submitted` et le battement la reprend.
-- On ne renonce qu'apres plusieurs essais, pour ne pas la laisser en suspens
-- si le quota reste ferme — et ce renoncement-la valide, parce qu'une panne
-- de notre cote ne doit couter d'argent a personne (invariant 2).


-- ------------------------------------------------- 1. compter les essais

alter table public.proofs
  add column if not exists verify_attempts int not null default 0;

comment on column public.proofs.verify_attempts is
  'Nombre de fois ou le modele a ete sollicite sans pouvoir repondre.';


-- ------------------------------------------- 2. autoriser le retour en file
--
-- La liste vit dans une fonction, pas dans une table : elle est reprise en
-- entier. Toute modification doit etre faite des DEUX cotes, ici et dans
-- `GoalStateMachine.swift` — aucune verification automatique ne detecte une
-- divergence.

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
    -- Reprise : le modele n'a pas pu repondre (quota, panne). Seule
    -- transition en arriere de la machine — elle ne revient pas sur une
    -- decision, elle dit qu'aucune n'a encore pu etre prise.
    ('ai_verifying',      'proof_submitted'),

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
