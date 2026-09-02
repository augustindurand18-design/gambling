# Démarrer sur le projet

Ce guide part du principe que vous n'avez jamais ouvert ce dépôt. Comptez
30 à 45 minutes, dont l'essentiel en téléchargements.

Lisez ensuite [`docs/architecture.md`](docs/architecture.md) — il explique les
garanties du système, et plusieurs d'entre elles sont faciles à casser sans
s'en apercevoir.

---

## 1. Prérequis

### Xcode

Xcode 26 ou plus récent. Après installation :

```bash
sudo xcodebuild -license accept
```

Sans cette étape, Homebrew refuse d'installer quoi que ce soit.

### Runtime de simulateur iOS

Xcode 26 n'embarque plus de simulateur. Installez-le **en ligne de commande** :

```bash
xcodebuild -downloadPlatform iOS
```

⚠️ **Ne le téléchargez jamais depuis l'interface d'Xcode en parallèle.** Les
deux téléchargeurs créent des images en double qui s'invalident mutuellement,
et le runtime devient inutilisable. C'est arrivé, la réparation coûte un
re-téléchargement de 8 Go.

Vérification :

```bash
xcrun simctl list runtimes    # doit afficher iOS 26.x
```

### Outils

```bash
brew install xcodegen supabase/tap/supabase
brew install colima docker          # runtime de conteneurs pour Supabase
brew install stripe/stripe-cli/stripe
```

Colima remplace Docker Desktop : pas d'interface, pas de licence, plus léger.

```bash
colima start --cpu 4 --memory 6 --disk 40
```

À relancer après chaque redémarrage du Mac.

### Deno

Nécessaire pour les Edge Functions.

```bash
brew install deno
```

---

## 2. Installation

```bash
git clone https://github.com/augustindurand18-design/gambling.git
cd gambling
```

### Base de données locale

```bash
supabase start
```

Le premier lancement télécharge plusieurs images Docker. La commande affiche à
la fin un bloc JSON contenant `ANON_KEY` — gardez-le sous la main.

```bash
supabase db reset     # applique les 18 migrations + le seed
supabase test db      # 24 tests pgTAP, doivent tous passer
```

Interface d'administration : http://127.0.0.1:54323

### Application iOS

```bash
cp ios/Config/Secrets.example.xcconfig ios/Config/Secrets.xcconfig
```

Ouvrez `ios/Config/Secrets.xcconfig` et renseignez `SUPABASE_ANON_KEY` avec la
valeur affichée par `supabase start`.

⚠️ Ce fichier est ignoré par git. **Ne le committez jamais**, même vidé de ses
valeurs — `Secrets.example.xcconfig` existe pour ça.

Note sur la syntaxe `xcconfig` : `//` démarre un commentaire. D'où
l'astuce `SLASHES = //` en tête de fichier, utilisée pour écrire les URL. Ne
la supprimez pas.

```bash
cd ios && xcodegen generate && cd ..
./scripts/ios-build.sh
./scripts/ios-test.sh
```

Le premier build compile tous les SDK (Stripe est volumineux) — comptez
10 à 15 minutes. Les suivants sont rapides.

---

## 3. Le projet Xcode est généré, pas versionné

`Gage.xcodeproj` **n'est pas dans git**. Il est produit par XcodeGen à partir
de [`ios/project.yml`](ios/project.yml).

Conséquences :

- pour ajouter une dépendance, un target ou un réglage de build, **modifiez
  `project.yml`**, pas le projet dans Xcode ;
- après un `git pull` qui touche `project.yml`, relancez `xcodegen generate` ;
- toute modification faite dans l'interface d'Xcode sera perdue à la prochaine
  génération.

Ça évite les conflits git illisibles sur le `.pbxproj` et rend les
changements de configuration relisibles en revue.

---

## 4. Tests

```bash
supabase test db                                      # base : 24 tests
deno test supabase/functions --allow-env --no-check   # fonctions : 21 tests
./scripts/ios-test.sh                                 # iOS : 19 tests
```

`./scripts/db-reset.sh` enchaîne reset + tests.

### Ce que les tests protègent

Ils ne vérifient pas seulement que le code marche : ils verrouillent les
garanties décrites dans `docs/architecture.md`. Par exemple, un test affirme
qu'aucun chemin de la machine à états ne mène à un débit sans être passé par
la vérification.

**Un test qui échoue après votre changement est probablement en train de vous
dire quelque chose.** Avant de l'ajuster, vérifiez que la garantie qu'il
protège tient toujours.

### Un piège connu

pgTAP attend des **codes SQLSTATE** (`'23514'`), pas des noms
(`'check_violation'`). Un nom passé à `throws_ok` produit un échec dont le
message ressemble à une vraie régression alors qu'il n'en est pas une.

---

## 5. Conventions

**Langue.** Documentation, commentaires et messages de commit en français.
Le code — identifiants, noms de fonctions, de tables et de colonnes — en
anglais. Les chaînes destinées à l'utilisateur sont en français.

**Commentaires.** Expliquez le *pourquoi*, pas le *quoi*. Ce dépôt contient
beaucoup de décisions contre-intuitives (ne jamais rejeter sur un doute,
masquer volontairement une table au client) : sans le motif écrit à côté,
elles seront « corrigées » par erreur.

**Migrations.** Numérotées, en avant seulement. On ne modifie jamais une
migration déjà poussée : on en ajoute une. Après toute migration, lancez
`supabase db reset` — ça rejoue tout à froid et révèle les problèmes d'ordre
qu'une base déjà montée masquerait.

**Machine à états.** Toute modification doit être faite **des deux côtés** :
[`0015_state_machine_trigger.sql`](supabase/migrations/0015_state_machine_trigger.sql)
et [`GoalStateMachine.swift`](ios/Gage/Domain/GoalStateMachine.swift). Rien ne
détecte automatiquement une divergence.

**Secrets.** Aucune clé dans le dépôt. Côté iOS, seules des clés publiques
(anon Supabase, publishable Stripe) — protégées par les RLS et par Stripe
lui-même. Côté serveur, `supabase secrets set`.

---

## 6. Travailler avec Claude Code

[`CLAUDE.md`](CLAUDE.md) est chargé automatiquement au démarrage d'une session
et contient tout le contexte produit, le modèle économique, les contraintes
juridiques et l'état d'avancement.

Deux recommandations tirées de l'expérience sur ce dépôt :

- **Faites-lui lire `docs/architecture.md` avant toute modification du
  paiement ou de la vérification.** Les invariants n'y sont pas devinables
  depuis le code seul.
- **Faites tourner les tests, ne les lisez pas.** Trois failles réelles dans
  les RLS et les triggers n'étaient pas détectables à la lecture ; seule
  l'exécution contre une vraie base les a révélées.

---

## 7. Comptes externes

Certains chantiers demandent un accès que le dépôt ne fournit pas :

| Service | Nécessaire pour | État |
|---|---|---|
| Apple Developer (99 €/an) | TestFlight, notifications push, Sign in with Apple sur appareil réel | ❌ pas encore pris |
| Stripe (mode test) | tout le paiement | ❌ pas encore créé |
| Anthropic API | vérification par IA | à configurer |
| Supabase cloud (Francfort) | déploiement | local uniquement pour l'instant |

En attendant le compte Apple, les entitlements sont désactivés dans
`project.yml` — sans quoi rien ne compile. Le simulateur n'exige aucune
signature, donc tout le développement reste possible.

Le fichier `ios/Gage/Gage.entitlements` est prêt : il suffira de rétablir le
bloc `entitlements:` dans `project.yml` le jour de l'inscription.
