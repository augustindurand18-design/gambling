-- 0024 — Fige le search_path des fonctions du schema app
--
-- Une fonction dont le search_path n'est pas fige resout ses noms de tables
-- selon le chemin de l'appelant. Quelqu'un qui peut creer un schema en tete
-- de son propre chemin fait alors executer ses tables a la place des notres,
-- avec les droits de la fonction. Les triggers vises gardent l'argent et
-- l'immuabilite des consentements : ils ne doivent dependre d'aucun reglage
-- de session.
--
-- Les trois fonctions qui le posaient deja (handle_new_user,
-- enforce_goal_transition, log_goal_creation) ne sont pas reprises ici.
--
-- Signale par l'analyseur Supabase (`function_search_path_mutable`) sur la
-- base cloud, invisible en local.

alter function app.touch_updated_at()            set search_path = public, app;
alter function app.forbid_consent_mutation()     set search_path = public, app;
alter function app.chain_consent_hash()          set search_path = public, app, extensions;
alter function app.current_actor()               set search_path = public, app;
alter function app.current_transition_reason()   set search_path = public, app;
alter function app.freeze_committed_goal()       set search_path = public, app;
alter function app.protect_profile_columns()     set search_path = public, app;
alter function app.assiduity_threshold()         set search_path = public, app;
alter function app.split_stake(int, int)         set search_path = public, app;
alter function app.goal_state_allowed(goal_state, goal_state) set search_path = public, app;
alter function app.goal_state_is_terminal(goal_state)         set search_path = public, app;
