# Architecture

Ce document explique **pourquoi** le code est fait ainsi. Le « comment »
s'apprend en lisant les fichiers ; le « pourquoi » se perd, et c'est lui qui
évite de casser des garanties sans s'en rendre compte.

À lire en entier avant la première contribution.

---

## 1. Ce que fait le produit, en une phrase technique

Un utilisateur crée un objectif, engage une somme d'argent dessus, reçoit à un
moment donné une demande de preuve photo, et selon que la preuve est acceptée
ou non, sa carte est débitée ou non.

Tout le reste découle de cette phrase. En particulier : **le logiciel prend
une décision qui coûte de l'argent réel à un utilisateur, sans intervention
humaine, sur la base d'une photo.** C'est une situation inhabituelle, et elle
justifie des choix qui paraîtraient excessifs ailleurs.

---

## 2. Les cinq invariants

Ce sont les règles qu'on ne casse pas. Si une évolution semble les
contredire, c'est le moment d'en discuter, pas de contourner.

### 2.1 La base de données fait autorité sur le cycle de vie

Le fichier
[`0015_state_machine_trigger.sql`](../supabase/migrations/0015_state_machine_trigger.sql)
contient une table de vérité des transitions légales, appliquée par un trigger
`BEFORE UPDATE`. **Ce trigger s'applique au service role**, donc aux Edge
Functions, donc à nous.

Concrètement : même avec une clé service role, un bug ne peut pas faire passer
un objectif de `committed` à `charge_ok`. La base refuse. C'est la dernière
barrière avant l'argent de quelqu'un.

Il existe un miroir Swift de cette table,
[`GoalStateMachine.swift`](../ios/Gage/Domain/GoalStateMachine.swift), utilisé
uniquement pour piloter l'interface. **Les deux doivent rester alignés.** Si
vous modifiez l'un, modifiez l'autre — les tests des deux côtés vérifient la
cohérence structurelle, mais rien ne détecte automatiquement une divergence
entre les deux fichiers. C'est le principal piège de ce dépôt.

### 2.2 On ne débite jamais sur un doute

Toute ambiguïté route vers la revue humaine, jamais vers un rejet :

- verdict `uncertain` du modèle,
- confiance sous le seuil,
- réponse du modèle illisible ou API en erreur,
- suspicion de falsification,
- signal anti-triche quelconque,
- mise élevée.

Voir [`routing.ts`](../supabase/functions/_shared/routing.ts). Une revue
humaine coûte 0,20 à 0,50 €. Un débit injustifié coûte un client, une note
1 étoile, et potentiellement un litige bancaire. Le calcul n'est pas serré.

**Corollaire pour le développement** : ne « corrigez » jamais un
comportement en faisant basculer un cas ambigu vers `rejected` pour réduire
le volume de revue humaine. Si le volume est trop élevé, la réponse est
d'améliorer le prompt ou de bouger un seuil de manière explicite, pas de
rendre le système plus tranchant.

### 2.3 Les consentements sont immuables

La table `consents` est append-only, avec deux triggers qui lèvent une
exception sur `UPDATE` et sur `DELETE`, **service role compris**. Chaque ligne
porte un `terms_hash` (SHA-256 du texte légal exactement tel qu'affiché) et un
`row_hash` chaîné à la ligne précédente du même utilisateur.

Raison : le jour où un utilisateur conteste un débit devant un médiateur ou sa
banque, la seule défense est de montrer ce qu'il a vu et accepté, à la seconde
près, sans possibilité d'avoir réécrit l'histoire. Une correction se fait en
ajoutant une ligne, jamais en modifiant.

Voir [`0007_consents.sql`](../supabase/migrations/0007_consents.sql).

### 2.4 L'instant du contrôle est un secret serveur

En mode `random_window`, le serveur tire un instant au hasard dans le créneau
choisi par l'utilisateur. Cet instant vit dans `notification_schedule`, table
qui **n'a volontairement aucune policy RLS de lecture**. Le client ne peut pas
la lire, même pour ses propres lignes.

Si l'utilisateur pouvait connaître l'heure à l'avance, il préparerait la photo,
et le produit ne vaudrait plus rien. C'est pour la même raison que les
notifications sont envoyées via APNs **depuis le serveur** et jamais
programmées en local sur l'appareil : une notification locale est inspectable.

Il y a un test pgTAP qui vérifie que cette table reste invisible. Ne le
supprimez pas pour faire passer une feature.

### 2.5 La caméra est le seul accès aux médias

L'app ne demande jamais l'accès à la photothèque. Aucun `PHPicker`, aucun
`UIImagePickerController` en mode bibliothèque. La capture passe par
`AVFoundation` dans l'app.

Ça élimine d'un coup la majorité des fraudes triviales : photo prise la
veille, photo trouvée sur internet, capture d'écran. Ajouter un accès galerie
« pour la commodité » reviendrait à supprimer l'anti-triche.

---

## 3. Le cycle de vie d'un objectif

```
draft ──► committed ──► proof_window_open ──► proof_submitted ──► ai_verifying
                │              │                     │                  │
                │              │                     │        ┌─────────┼─────────┐
                │              │                     │        ▼         ▼         ▼
                │              │                     │   validated  rejected  human_review
                │              │                     │        │         │         │
                └──────────────┴─────────────────────┘        │         │         │
                        (échéance dépassée)                   │         │         │
                                                              ▼         ▼         ▼
                                                        closed_kept   closed_failed
                                                                            │
                                                                            ▼
                                                                     charge_pending
                                                                       │        │
                                                                       ▼        ▼
                                                                  charge_ok  charge_failed
```

**Points d'entrée dans chaque état** :

| État | Qui le déclenche |
|---|---|
| `draft` | l'utilisateur, via un `INSERT` direct (RLS l'autorise) |
| `committed` | la RPC `commit_goal` — jamais un `UPDATE` direct |
| `proof_window_open` | `app.open_due_proof_windows()`, appelée par le cron — **pas** `send-push` |
| `proof_submitted` | la RPC `submit_proof`, après upload de la photo |
| `ai_verifying` | la fonction `verify-proof` |
| `validated` / `rejected` / `human_review` | `verify-proof`, selon le routage |
| `closed_kept` / `closed_failed` | `verify-proof`, `close-expired`, ou un reviewer humain |
| `charge_pending` | `stripe-charge-stake` |
| `charge_ok` / `charge_failed` | le webhook Stripe |

**Les deux états terminaux** sont `closed_kept` et `charge_ok`. Un objectif en
`charge_failed` n'est pas terminal : une relance Stripe peut le débloquer.

### Pourquoi la notification n'ouvre pas la fenêtre

Ce tableau disait, jusqu'à la migration `0027`, que `proof_window_open` était
déclenché par `send-push` « au moment où elle envoie la notification ». C'était
mettre la livraison APNs sur le chemin critique de l'argent : une panne d'Apple,
un jeton révoqué, une variable d'environnement absente, et la fenêtre ne
s'ouvrait jamais — donc l'utilisateur ne pouvait pas soumettre, donc l'échéance
passait, donc il était débité. Un incident d'infrastructure serait devenu un
débit, ce qu'interdit l'invariant §2.2.

L'ouverture appartient donc à la base, qui fait déjà autorité sur le cycle de
vie (§2.1). `pg_cron` appelle `app.tick_notifications()` chaque minute, qui
planifie, ouvre, puis clôt. `send-push` ne fait plus que livrer : **son échec
n'a aucun effet sur l'état d'un objectif**. Effet de bord appréciable, toute la
chaîne devient vérifiable en local sans compte Apple Developer.

Une conséquence à connaître : `app.open_due_proof_windows()` refuse d'ouvrir
une fenêtre pour un utilisateur qui n'a **aucun appareil non révoqué**. Sans
cela, le compte à rebours de quinze minutes partirait dans le vide et
l'utilisateur perdrait sa mise sans avoir rien su.

**Un manque assumé** : quand une fenêtre n'a jamais pu s'ouvrir alors que le
jour est passé, l'objectif reste `committed` et sa mise reste `active`.
`app.close_expired_goals()` se contente de le signaler dans
`notification_schedule.last_error`. `0015` autorise bien `committed → rejected`
comme filet de sécurité, mais s'en servir reviendrait à débiter quelqu'un pour
notre panne. La sortie honnête serait `committed → human_review`, qui n'existe
ni dans `0015` ni dans `GoalStateMachine.swift`.

---

## 4. Pourquoi l'engagement passe par une RPC

`commit_goal` fait quatre choses dans une seule transaction :

1. vérifie les plafonds et l'absence de blocage de paiement,
2. crée la mise,
3. enregistre le consentement horodaté,
4. fait passer l'objectif en `committed`.

Si on autorisait un `UPDATE` direct sur `goals.state`, il deviendrait possible
d'engager de l'argent sans trace de consentement — par un bug, ou par un
client modifié. Les policies RLS interdisent donc explicitement la transition
vers `committed` depuis le client, et un test pgTAP vérifie ce refus.

Voir [`0017_rpc_commit_goal.sql`](../supabase/migrations/0017_rpc_commit_goal.sql).

---

## 5. Le pipeline de vérification, étape par étape

### 5.1 Pré-filtre embarqué (Apple Vision)

Tourne sur l'appareil, gratuit. Cherche des indices de capture d'écran (moiré,
densité de texte, bordures) et une présence grossière de l'objet attendu.
Produit un objet `ondevice_precheck` transmis au serveur.

**Non autoritaire.** Il ne rejette rien. Un pré-filtre trop strict recalerait
des preuves légitimes — par exemple la photo d'un écran de tableau de bord de
voiture, qui est un cas d'usage valide.

### 5.2 Anti-triche serveur

[`anticheat.ts`](../supabase/functions/_shared/anticheat.ts). Principe : **tout
ce que déclare l'appareil est suspect.** `captured_at`, la position, l'EXIF
sont fournis par le client et falsifiables. Seuls `server_received_at` et
`window_opened_at` font foi.

Deux cas valent **rejet immédiat sans consulter le modèle**, parce que la
fraude y est établie par construction :

- **preuve reçue avant l'ouverture de la fenêtre** — impossible de bonne foi,
  puisque l'utilisateur ne peut pas connaître l'instant du contrôle ;
- **image déjà utilisée** (`image_sha256` déjà en base, toutes personnes
  confondues).

Tout le reste — EXIF absent, horodatage incohérent, écran détecté — remonte
comme **signal**, et un signal envoie vers la revue humaine, pas vers un rejet.

### 5.3 Appel au modèle

[`prompts.ts`](../supabase/functions/_shared/prompts.ts). Le prompt système
dit explicitement au modèle que répondre `uncertain` est le comportement
attendu et non un échec, et qu'une photo floue ou mal cadrée n'est pas une
fraude. C'est délibéré : un modèle qui cherche à trancher pour « bien faire »
produit des faux rejets, et un faux rejet coûte de l'argent à un utilisateur
innocent.

Routage des modèles : Haiku en premier passage (coût quasi nul), escalade vers
Sonnet si le verdict est incertain.

Le parsing est défensif : toute réponse illisible devient `uncertain`. On ne
débite jamais quelqu'un sur une réponse qu'on n'a pas su lire.

### 5.4 Décision

[`routing.ts`](../supabase/functions/_shared/routing.ts). Voir l'invariant 2.2.

Un point mérite attention : **une part des validations part en relecture
aléatoire** (5 % par défaut). Sans cela, quelqu'un qui découvre une faille du
modèle peut l'exploiter indéfiniment sans jamais être vu. C'est de la
dissuasion, pas du contrôle qualité.

---

## 6. Paiements

### 6.1 Deux flux distincts, deux prestataires

| Flux | Prestataire | Pourquoi |
|---|---|---|
| Abonnement | Apple IAP (StoreKit 2 + RevenueCat) | Apple l'exige pour un service numérique consommé dans l'app |
| Mises | Stripe | L'IAP **interdit** les mécaniques d'argent réel et ne sait pas débiter en différé |

Ce n'est pas un choix d'optimisation, c'est une contrainte. Ne tentez pas
d'unifier.

### 6.2 Le parcours de mise

La carte est saisie **une seule fois**, à l'onboarding, via un `SetupIntent`
Stripe avec 3DS et `usage: off_session`. Ensuite, chaque engagement se fait
d'un simple tap — pas de re-saisie.

Ce tap doit rester **explicite et jamais pré-coché**. C'est la protection
principale contre les litiges bancaires et contre une requalification en
clause abusive. Frictionless sur la carte, volontaire sur la mise.

### 6.3 Ce qui se passe quand un débit échoue

Le débit off-session peut échouer : carte expirée, provision insuffisante, ou
SCA exigée par la banque (fréquent en France). Dans ce cas :

- l'objectif reste **raté**, le montant devient un **solde dû** ;
- `profiles.stake_block_active` passe à `true` → **création de nouveaux
  objectifs bloquée** ;
- les objectifs **déjà engagés continuent** normalement, le consentement ayant
  déjà été donné ;
- les semaines concernées sont marquées `frozen` dans `assiduity_weeks`, pour
  que l'utilisateur **conserve son tarif réduit** — un incident de carte n'est
  pas un manque de volonté.

Le déblocage exige **solde à zéro ET carte valide**.

---

## 7. Ce qui n'est pas encore écrit

L'architecture ci-dessus est posée, mais toutes les Edge Functions ne sont pas
implémentées. État au dernier commit :

| Composant | État |
|---|---|
| Schéma complet + RLS + machine à états | ✅ écrit, 87 tests pgTAP |
| Anti-triche, prompts, routage | ✅ écrits, 52 tests Deno |
| Modèles Swift + machine à états client | ✅ écrits, 56 tests |
| RPC `transition_goal` (`0020`) et `submit_proof` (`0026`) | ✅ écrites |
| Planification et ouverture des fenêtres (`0027`, `pg_cron`) | ✅ écrites |
| `send-push` (livraison seule) | ⚠️ écrite, **jamais exécutée contre Apple** |
| Caméra `AVFoundation` + pré-filtre Vision + envoi | ✅ écrits |
| `verify-proof` (fonction assemblée) | ✅ écrite — Claude en production, Gemini pour les essais |
| `stripe-setup-intent`, `stripe-webhook`, `stripe-charge-stake` | ⬜ à écrire |
| `dispute-intake`, `weekly-assiduity`, `purge-proofs` | ⬜ à écrire |
| Le reste de l'interface iOS | ⬜ design Figma en cours |

Deux réserves sur ce qui est marqué écrit :

- **`send-push` n'a jamais tourné contre Apple.** Sans compte Apple Developer,
  ni clé `.p8` ni identifiants n'existent, et l'entitlement `aps-environment`
  n'est pas attaché à la cible (voir le commentaire dans `ios/project.yml`).
  La signature ES256, le cache du jeton et le traitement des codes d'erreur
  sont écrits d'après la documentation et testés unitairement. Un transport de
  repli journalise une commande `xcrun simctl push` prête à coller, ce qui
  exerce le routage dans l'application — pas la livraison.
- **Dette connue** : si l'envoi du fichier réussit mais que `submit_proof`
  refuse (délai écoulé), l'objet reste orphelin dans le bucket, et le client
  n'a pas le droit de le supprimer. `purge-proofs` devra les ramasser.

**Un défaut trouvé en exécutant, pas en relisant** (2026-09-06) : ni
`ProofsAPI` ni `submit_proof` ne transmettaient l'EXIF, donc `proofs.exif`
restait toujours nul. Or `runAntiCheat` lève `exif_missing` en son absence — à
raison — et `routeVerdict` envoie en revue humaine toute preuve portant le
moindre signal. **Cent pour cent des preuves partaient donc en revue humaine**,
à 0,20-0,50 € pièce, alors que §5 vise 85 % absorbés par l'IA : la vérification
automatique ne servait à rien. Chaque pièce était pourtant correcte isolément.
Réparé par la migration `0028` et `ProofExif.swift`, qui n'envoie qu'une liste
blanche de champs — l'EXIF brut porte les coordonnées GPS du lieu de prise de
vue, dont on n'a pas besoin — et normalise la date en UTC, faute de quoi le
décalage horaire français lèverait `exif_date_mismatch` sur chaque preuve
honnête.

---

## 8. Décisions ouvertes

Ces points sont tranchés provisoirement dans le code, mais méritent un
arbitrage réel :

1. **Seuil de revue humaine à 20 €.** Si beaucoup d'utilisateurs misent
   20–30 €, le coût de vérification grimpe et la marge sur l'abonnement à 5 €
   fond. Constante isolée dans `routing.ts`.
2. **Part reversée à l'association : 25 %.** Fixée arbitrairement, à valider
   juridiquement et économiquement.
3. **Rétention des photos : 60 jours.** À arbitrer entre besoin de preuve en
   cas de litige tardif et minimisation RGPD.
4. **Plafond de semaines gelées : 3.** Anti-abus contre quelqu'un qui
   laisserait sa carte invalide exprès pour ne plus rien risquer tout en
   gardant le tarif réduit. Enregistré mais pas encore appliqué.
5. **Délai de soumission après notification.** Pas encore fixé.
6. **Position d'Apple sur le « real money gaming ».** Question à poser par
   écrit avant de soumettre. Peut imposer un classement 17+ voire un refus.
   La couche mise/débit doit rester isolable pour permettre une bêta « sans
   argent » si nécessaire.
