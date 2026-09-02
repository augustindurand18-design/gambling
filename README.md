# Gage

Application iOS d'engagement : on fixe un objectif, on engage une somme, on
prouve par photo vérifiée. Objectif tenu, rien n'est débité. Objectif non tenu
et non contesté, la mise est prélevée — une part est reversée à une association
choisie par l'utilisateur.

Le cadrage produit complet (modèle économique, contraintes juridiques,
périmètre) est dans [`CLAUDE.md`](CLAUDE.md).

## Structure

| Dossier | Contenu |
|---|---|
| `ios/` | Application SwiftUI (projet Xcode généré par XcodeGen) |
| `supabase/` | Migrations Postgres, Edge Functions, tests pgTAP |
| `web/` | Interface de revue humaine (à venir) |
| `docs/` | Recherche marché et documents de cadrage |
| `scripts/` | Build, tests, reset de base |

## Prérequis

```bash
sudo xcodebuild -license accept     # une fois, demande le mot de passe
brew install xcodegen supabase/tap/supabase
brew install stripe/stripe-cli/stripe   # pour tester les paiements
```

Xcode 26+ et Deno sont également requis.

## Démarrer

```bash
# Base de données locale
supabase start
supabase db reset          # applique migrations + seed

# Application iOS
cp ios/Config/Secrets.example.xcconfig ios/Config/Secrets.xcconfig
# renseigner SUPABASE_ANON_KEY (affichée par `supabase start`)
cd ios && xcodegen generate
./scripts/ios-build.sh
```

## Tests

```bash
supabase test db           # pgTAP : machine à états, RLS, immutabilité
deno test supabase/functions --allow-env
./scripts/ios-test.sh      # tests unitaires et UI
```

## Points d'architecture

**La base de données est l'autorité.** Les transitions d'état d'un objectif
sont validées par un trigger Postgres
([`0015_state_machine_trigger.sql`](supabase/migrations/0015_state_machine_trigger.sql))
qui s'applique même au service role. Aucun bug applicatif ne peut faire passer
un objectif de « engagé » à « débité » sans vérification.

**Les consentements sont immuables.** La table `consents` est append-only,
protégée par trigger, avec chaînage de hash. Elle enregistre le texte légal
exact affiché à l'utilisateur au moment où il engage son argent.

**L'instant du contrôle est un secret serveur.** En mode « contrôle surprise »,
la table `notification_schedule` n'a volontairement aucune policy de lecture :
si le client pouvait connaître l'heure à l'avance, la preuve serait
préparable.

**On ne débite jamais sur un doute.** Toute erreur de vérification (timeout,
réponse illisible, incertitude du modèle) route vers la revue humaine, jamais
vers un rejet automatique.

**La caméra est le seul accès aux médias.** Aucun accès à la photothèque n'est
demandé nulle part dans l'application, par conception.
