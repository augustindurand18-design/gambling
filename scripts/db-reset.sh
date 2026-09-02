#!/usr/bin/env bash
# Rejoue toutes les migrations a froid puis les tests. Detecte les problemes
# d'ordre entre migrations, qu'un schema deja monte masquerait.
set -euo pipefail
cd "$(dirname "$0")/.."
supabase db reset
supabase test db
