-- 0022 — L'instant du controle surprise redevient un secret serveur
--
-- Invariant 4 (docs/architecture.md) : l'instant de declenchement ne doit
-- jamais etre lisible par le client. `notification_schedule` le respecte —
-- elle n'a volontairement aucune policy de lecture. Mais `goals` porte le
-- meme instant dans `window_fire_at`, et la policy `goals_select_own` rend
-- toute la ligne visible a son proprietaire : la RLS filtre des lignes,
-- jamais des colonnes.
--
-- La porte etait donc fermee d'un cote et ouverte de l'autre. Un utilisateur
-- pouvait lire l'heure exacte de son propre controle et preparer la photo,
-- ce qui vide de son sens la fenetre aleatoire — la seule chose qui empeche
-- une preuve d'etre fabriquee a l'avance.
--
-- Constate en interrogeant la base sous le role authenticated, pas en
-- relisant les policies : la fuite ne se voit pas dans le texte d'une policy.
--
-- Un `revoke select (window_fire_at)` seul ne suffit pas : `authenticated`
-- detient un droit au niveau de la table, qui couvre toutes les colonnes et
-- qu'un revoke de colonne n'entame pas. Il faut retirer le droit table, puis
-- le rendre colonne par colonne — ce qui a l'avantage de rendre la liste des
-- champs lisibles explicite, et de faire echouer bruyamment tout ajout futur
-- de colonne sensible.
--
-- La colonne reste en place : elle est ecrite par schedule-notifications et
-- balayee par le cron via goals_state_fire_idx. Seuls sa lecture et son
-- ecriture par le client disparaissent.

revoke select, insert, update on public.goals from authenticated;
revoke select, insert, update on public.goals from anon;

-- Lecture : tout sauf l'instant du controle.
grant select (
  id, user_id, title, goal_type, state, proof_instruction, charity_id,
  window_mode, timezone, target_date,
  fixed_time_local, window_start_local, window_end_local,
  window_opened_at, proof_deadline_at, dispute_deadline_at, review_deadline_at,
  committed_at, closed_at, human_review_reason,
  created_at, updated_at
) on public.goals to authenticated;

-- Ecriture : ce que l'utilisateur compose lui-meme. Ni l'etat — le passage
-- draft -> committed appartient a commit_goal — ni aucun instant calcule par
-- le serveur.
grant insert (
  id, user_id, title, goal_type, proof_instruction, charity_id,
  window_mode, timezone, target_date,
  fixed_time_local, window_start_local, window_end_local
) on public.goals to authenticated;

grant update (
  title, goal_type, proof_instruction, charity_id,
  window_mode, timezone, target_date,
  fixed_time_local, window_start_local, window_end_local
) on public.goals to authenticated;

comment on column public.goals.window_fire_at is
  'Instant du controle surprise. Ecrit et lu cote serveur uniquement : lecture et ecriture retirees aux roles anon et authenticated (0022). Une requete client doit nommer ses colonnes ; un select * sur goals echoue, et c''est voulu.';
