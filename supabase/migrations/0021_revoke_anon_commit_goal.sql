-- 0021 — Retire a `anon` le droit d'appeler commit_goal
--
-- La migration 0017 revoquait sur `public` puis accordait a `authenticated`,
-- en pensant avoir ferme la porte. Elle etait restee ouverte : Supabase
-- accorde execute sur toute nouvelle fonction du schema public a `anon` et
-- `authenticated` par privileges par defaut, et ces droits nominatifs
-- survivent a un revoke sur `public`. Constate en interrogeant
-- has_function_privilege sur une vraie base, pas en relisant le SQL.
--
-- L'exposition n'etait pas exploitable — le corps de commit_goal leve une
-- exception quand auth.uid() est nul — mais la seule chose qui protegeait
-- l'engagement d'un appel non authentifie etait cette garde applicative.
-- Sur le chemin de l'argent, la permission doit dire la meme chose que le
-- code.

revoke all on function public.commit_goal(
  uuid, int, uuid, int, text, text, jsonb, text, text
) from anon;

comment on function public.commit_goal is
  'Engage un objectif : cree la mise, enregistre le consentement horodate et passe l''objectif en committed. Atomique. Reservee au role authenticated.';
