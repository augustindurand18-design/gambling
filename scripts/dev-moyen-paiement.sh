#!/usr/bin/env bash
# Pose un moyen de paiement factice sur les profils de la base LOCALE.
#
# `commit_goal` (0017) refuse d'engager un objectif sans
# `default_payment_method_id` : c'est Stripe qui le pose, et Stripe n'est pas
# encore branche. Sans ce contournement, aucun objectif ne peut atteindre
# `committed`, donc rien n'est planifie, donc aucune fenetre ne s'ouvre — tout
# le chantier des notifications reste invisible.
#
# Enregistre aussi un appareil factice si le profil n'en a aucun :
# `app.open_due_proof_windows()` refuse deliberement d'ouvrir une fenetre
# qu'elle ne peut annoncer a personne.
#
# Volontairement PAS dans seed.sql : celui-ci s'execute juste apres les
# migrations, quand aucun compte n'existe encore (l'UPDATE ne toucherait rien),
# et il pourrait un jour tourner contre le projet cloud.
set -euo pipefail

cd "$(dirname "$0")/.."

CONTAINER="supabase_db_nouveau_SaaS"

if ! docker ps --format '{{.Names}}' | grep -qx "$CONTAINER"; then
  echo "La base locale ne tourne pas. Lance d'abord : supabase start" >&2
  exit 1
fi

docker exec -i "$CONTAINER" psql -U postgres -X -q <<'SQL'
-- Valeur ostensiblement fausse : personne ne doit croire une seconde qu'un
-- vrai moyen de paiement dort dans une base de developpement.
update public.profiles
set default_payment_method_id = 'pm_dev_factice',
    stripe_customer_id = coalesce(stripe_customer_id, 'cus_dev_' || left(user_id::text, 8)),
    pm_last4 = '4242',
    pm_brand = 'visa'
where default_payment_method_id is null;

insert into public.devices (user_id, apns_token, env, model)
select p.user_id,
       'dev-' || replace(p.user_id::text, '-', ''),
       'sandbox',
       'Simulator (dev)'
from public.profiles p
where not exists (
  select 1 from public.devices d where d.user_id = p.user_id and d.revoked = false
);

select count(*) || ' profil(s) equipes, '
       || (select count(*) from public.devices where revoked = false)
       || ' appareil(s) actif(s)' as etat
from public.profiles
where default_payment_method_id is not null;
SQL

echo
echo "Rappel : ces valeurs n'ont de sens qu'en local. Ne jamais lancer ce script"
echo "contre le projet cloud."
