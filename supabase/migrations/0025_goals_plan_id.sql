-- 0025 — Rattache les seances d'une meme promesse hebdomadaire
--
-- L'utilisateur promet « aller a la salle 5 fois cette semaine ». La base,
-- elle, ne sait representer qu'un objectif par jour : la promesse arrive donc
-- en cinq lignes. Sans lien entre elles, l'accueil ne peut que les afficher
-- separement, et l'utilisateur voit cinq defis la ou il n'en a pris qu'un.
--
-- `plan_id` est ce lien. Il est pose par le client au moment de la creation :
-- toutes les lignes d'une meme composition partagent le meme identifiant.
-- Nul est accepte — les objectifs crees avant cette migration n'en ont pas,
-- et chacun vaut alors pour lui-meme.
--
-- Ce n'est pas encore le modele definitif d'une promesse hebdomadaire : la
-- mise reste attachee a chaque objectif alors qu'elle vaut pour la semaine
-- entiere. Cette colonne rend l'affichage juste ; le modele suivra avec le
-- branchement du paiement.

alter table public.goals add column plan_id uuid;

create index goals_plan_idx on public.goals (user_id, plan_id)
  where plan_id is not null;

comment on column public.goals.plan_id is
  'Regroupe les seances d''une meme promesse hebdomadaire. Pose par le client a la creation, jamais modifie ensuite.';
