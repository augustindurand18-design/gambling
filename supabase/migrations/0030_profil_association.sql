-- 0030 — L'association choisie une fois, pour toutes les mises
--
-- Le modele economique prevoit qu'une part des mises perdues aille « a une
-- association choisie par l'utilisateur » (decision du 2026-09-02), et le
-- texte de consentement le lui dit mot pour mot. Or rien dans le parcours ne
-- lui faisait choisir : `goals.charity_id` restait nul, et le consentement
-- affirmait donc quelque chose de faux.
--
-- Un consentement qui decrit une repartition qui n'existe pas est exactement
-- ce qu'un mediateur ou une banque relevera en premier.
--
-- Le choix vit sur le profil et non sur l'objectif : on ne va pas demander a
-- quelqu'un de choisir une association a chaque fois qu'il promet d'aller a
-- la salle. `commit_goal` recopie la valeur sur l'objectif au moment de
-- l'engagement, ou elle se fige — changer d'association plus tard ne doit pas
-- reecrire les engagements deja pris.

alter table public.profiles
  add column default_charity_id uuid references public.charities(id);

comment on column public.profiles.default_charity_id is
  'Association vers laquelle part la part reversee des mises perdues. Recopiee sur l''objectif a l''engagement, ou elle se fige.';

-- L'utilisateur choisit lui-meme : la colonne n'est donc pas protegee par
-- `app.protect_profile_columns()`, contrairement a tout ce qui touche a
-- Stripe et aux plafonds. Le seul garde-fou utile est la cle etrangere, plus
-- la policy de `charities` qui ne montre que les associations actives.
