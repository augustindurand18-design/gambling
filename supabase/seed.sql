-- Donnees de reference pour le developpement local.
--
-- Associations : liste provisoire d'associations francaises reconnues.
-- A valider juridiquement (accord de l'association, mention de son nom dans
-- l'app, modalites de reversement) avant toute mise en production.

insert into public.charities (slug, name, description, website_url, sort_order) values
  ('restos-du-coeur',   'Les Restos du Cœur',
   'Aide alimentaire et accompagnement des personnes en difficulte.',
   'https://www.restosducoeur.org', 10),

  ('secours-populaire', 'Secours populaire français',
   'Solidarite de proximite en France et dans le monde.',
   'https://www.secourspopulaire.fr', 20),

  ('institut-curie',    'Institut Curie',
   'Recherche et soins contre le cancer.',
   'https://curie.fr', 30),

  ('spa',               'La SPA',
   'Protection des animaux domestiques.',
   'https://www.la-spa.fr', 40),

  ('handicap-intl',     'Humanité & Inclusion',
   'Aide aux personnes handicapees et vulnerables.',
   'https://www.handicap-international.fr', 50)
on conflict (slug) do nothing;
