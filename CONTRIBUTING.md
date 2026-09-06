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
supabase db reset     # applique les 28 migrations + le seed
supabase test db      # 87 tests pgTAP, doivent tous passer
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
supabase test db                                      # base : 87 tests
deno test supabase/functions --allow-env --no-check   # fonctions : 52 tests
./scripts/ios-test.sh                                 # iOS : 56 tests
```

`./scripts/db-reset.sh` enchaîne reset + tests.

### Exercer la boucle de notification en local

Un `db reset` laisse une base sans compte. Une fois connecté depuis
l'application :

```bash
./scripts/dev-moyen-paiement.sh
```

`commit_goal` refuse d'engager un objectif sans moyen de paiement — Stripe
n'est pas branché — et `app.open_due_proof_windows()` refuse d'ouvrir une
fenêtre pour quelqu'un sans appareil joignable. Ce script pose les deux, en
local uniquement.

Le cron `gage-tick` tourne ensuite toutes les minutes : planification,
ouverture, clôture. Pour voir où en est un objectif :

```bash
docker exec -i supabase_db_nouveau_SaaS psql -U postgres -c "select g.title, g.state, n.fire_at, n.sent_at, n.last_error from goals g left join notification_schedule n on n.goal_id = g.id order by g.created_at desc limit 10;"
```

`send-push` n'est pas planifiée : l'appeler depuis Postgres demanderait une clé
de service dans une migration, et le dépôt est public. On l'invoque à la main.

```bash
supabase functions serve send-push --env-file supabase/.env
```

Sans identifiants APNs — le cas aujourd'hui, faute de compte Apple Developer —
elle journalise une commande `xcrun simctl push` prête à coller, qui exerce le
routage dans l'application. Cela ne teste pas la livraison, seulement ce que
l'app fait du message.

### Vérifier une preuve

`verify-proof` n'est pas planifiée non plus. Sans argument elle traite toute la
file des preuves en attente ; avec `{"proof_id": "..."}` elle n'en traite qu'une.

```bash
supabase functions serve verify-proof --env-file supabase/.env
```

Le fournisseur se choisit sur les variables présentes, dans cet ordre :

| Variable | Fournisseur | Usage |
|---|---|---|
| `ANTHROPIC_API_KEY` | Claude — Haiku, escalade Sonnet sur le doute | production |
| `GEMINI_API_KEY` | Gemini | test uniquement |
| aucune | — | chaque preuve part en revue humaine |

L'ordre n'est pas négociable : une clé de test ne doit jamais détourner la
production de Claude. Et sans aucune clé, **on n'invente pas de verdict** —
tout va en revue humaine. C'est coûteux et c'est voulu.

⚠️ Le prompt système est écrit et réglé pour Claude. Gemini sert à exercer la
chaîne, pas à mesurer la qualité de vérification.

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
