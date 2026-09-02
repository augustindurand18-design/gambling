-- 0002 — Types enumeres du domaine

-- Etats d'un objectif. L'ordre est celui du cycle de vie nominal.
create type goal_state as enum (
  'draft',              -- en cours de composition, aucun engagement
  'committed',          -- mise + consentement enregistres, fenetre planifiee
  'proof_window_open',  -- notification envoyee, l'utilisateur peut soumettre
  'proof_submitted',    -- photo uploadee, metadonnees serveur posees
  'ai_verifying',       -- verify-proof en cours
  'validated',          -- verdict favorable (IA ou humain)
  'rejected',           -- verdict defavorable, contestable pendant dispute_deadline_at
  'human_review',       -- file de revue manuelle (incertain, litige, echantillon)
  'closed_kept',        -- TERMINAL : objectif tenu, rien debite
  'closed_failed',      -- echec confirme et non contestable, debit a declencher
  'charge_pending',     -- PaymentIntent cree, en attente
  'charge_ok',          -- TERMINAL : mise encaissee
  'charge_failed'       -- TERMINAL bloquant : debit echoue, solde du, creation bloquee
);

-- Familles de preuve. La beta n'utilise que object_scene.
create type goal_type as enum (
  'object_scene',   -- photo d'un objet/scene a un instant donne
  'presence',       -- geofence + photo horodatee sur place
  'usage_data',     -- donnees d'usage telephone (Screen Time)
  'action_export'   -- export d'une app tierce (Strava, Kindle...)
);

-- Mode de declenchement de la fenetre de preuve.
create type window_mode as enum (
  'fixed_time',     -- heure precise choisie par l'utilisateur
  'random_window'   -- instant aleatoire tire dans une plage choisie
);

create type verdict as enum ('pass', 'fail', 'uncertain');

create type charge_status as enum (
  'pending', 'processing', 'succeeded', 'failed', 'canceled', 'requires_action'
);

create type dispute_status as enum ('open', 'under_review', 'upheld', 'denied');

create type consent_type as enum ('onboarding_caps', 'stake_commitment');

create type assiduity_status as enum ('normal', 'frozen');

create type stake_status as enum ('active', 'released', 'charged');
