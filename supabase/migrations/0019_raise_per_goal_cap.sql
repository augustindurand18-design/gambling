-- 0019 — Plafond par objectif porte a 100 EUR

-- Seule la valeur par defaut change : elle s'applique aux profils crees a
-- partir de maintenant. Les profils existants conservent le plafond qu'ils
-- ont accepte a l'onboarding — relever l'exposition financiere de quelqu'un
-- sans nouveau consentement irait contre l'immuabilite des consentements.
alter table public.profiles
  alter column per_goal_cap_cents set default 10000;   -- 100 EUR

comment on column public.profiles.per_goal_cap_cents is
  'Plafond par mise accepte a l''onboarding. Le defaut vaut pour les nouveaux profils ; un profil existant ne change de plafond qu''avec un nouveau consentement.';
