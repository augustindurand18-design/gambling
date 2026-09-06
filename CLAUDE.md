# Gage — Contexte projet

> **Nouveau sur ce dépôt ?** Lisez [`CONTRIBUTING.md`](CONTRIBUTING.md) pour
> l'installation, puis [`docs/architecture.md`](docs/architecture.md) pour les
> garanties du système. Ce fichier-ci porte le contexte produit et les
> décisions ; l'architecture explique le code.

## Équipe

Augustin (produit, design, code) et un développeur. Les deux travaillent avec
Claude Code. Le dépôt est public : ne jamais y committer de secret, de donnée
personnelle ou de contenu de consentement réel.

## Règles de travail pour Claude Code

**Avant de toucher au paiement ou à la vérification**, lire
`docs/architecture.md` — les invariants n'y sont pas devinables depuis le code.

**Cinq choses à ne jamais casser** (détail dans `docs/architecture.md`) :
1. la base fait autorité sur les transitions d'état, service role compris ;
2. on ne débite jamais sur un doute — toute ambiguïté part en revue humaine ;
3. les consentements sont immuables, y compris pour le service role ;
4. l'instant du contrôle surprise n'est jamais lisible par le client ;
5. la caméra est le seul accès aux médias, aucune photothèque.

**Machine à états** : toute modification doit être faite des **deux côtés**,
`supabase/migrations/0015_state_machine_trigger.sql` et
`ios/Gage/Domain/GoalStateMachine.swift`. Aucune vérification automatique ne
détecte une divergence.

**Toujours exécuter les tests, jamais se contenter de les lire.** Trois failles
réelles (RLS, triggers, permissions de schéma) n'étaient pas visibles à la
lecture et n'ont été trouvées qu'en lançant le schéma contre une vraie base.

```bash
supabase test db                                      # 115 tests
deno test supabase/functions --allow-env --no-check   # 60 tests
./scripts/ios-test.sh                                 # 68 tests
```

Pour observer la boucle de notification en local, il faut d'abord un moyen de
paiement et un appareil factices — sans quoi aucun objectif n'atteint
`committed` et aucune fenêtre ne s'ouvre :

```bash
./scripts/dev-moyen-paiement.sh
```

**Langue** : documentation, commentaires et commits en français ; code et
schéma en anglais ; textes destinés à l'utilisateur en français.

## Objectif
Concevoir et lancer un **SaaS B2C** rentable, à destination du marché **français / francophone**.

## Contraintes cadrées (non négociables)
- **B2C uniquement** — le B2B est écarté (cycle de vente, support, complexité).
- **Abonnement récurrent (MRR)** — pas de one-shot, pas de pur freemium sans conversion.
- **Marché prioritaire : France / francophone** — accepte un TAM plus petit contre une concurrence anglo-saxonne moindre et un avantage "local".
- **Solo + bootstrapé** — Augustin code (avec Claude), pas de levée, coûts d'infra faibles, time-to-market court (< 3 mois pour un MVP).
- Corollaires : éviter le contenu user-generated à modérer lourdement ; éviter les marketplaces (poule/œuf) ; privilégier une valeur délivrée dès la 1re session (churn semaine 1 = 35 % des annulations annuelles).

### Deux filtres ajoutés (2026-09-01) — l'idée DOIT combiner :
1. **Pulsion primaire** — être au plus près d'au moins une des trois : **statut**, **reproduction** (séduction / vie de couple / attractivité), **sécurité / appartenance**. Idéalement plusieurs à la fois.
2. **Boucle virale intégrée** — la distribution organique (réseaux sociaux, bouche-à-oreille) doit être *dans le produit*, pas un canal marketing à côté. Deux mécanismes recherchés :
   - **Virale structurelle** : le produit ne fonctionne pas sans inviter quelqu'un (app de couple, cercle familial, défi entre amis) → coefficient viral quasi garanti chez les utilisateurs activés.
   - **Virale de contenu** : le produit génère un artefact partageable natif TikTok/Insta/Story (avant/après, score, carte de résultat, recap).
   Le must : les deux à la fois.
→ voir `docs/brainstorm-pulsions-viralite.md`

### Anti-pattern explicite : ne PAS construire une plateforme d'attention
Pas de réseau social, pas de feed, pas de marketplace, pas de produit dont la valeur = la présence des autres et qui exige une masse critique + de la modération. La valeur doit être délivrée à **un utilisateur seul dès la 1re session**. La viralité vient de l'utilité de l'artefact partagé ou de l'invitation, pas d'une économie de l'attention à amorcer.

### Méthode : problème d'abord, pas solution d'abord (2026-09-01)
On identifie d'abord des **problèmes que quasiment tout client peut avoir** et qu'un SaaS mono-utilisateur peut résoudre. On ne dessine des formes de produit qu'ensuite.
→ voir `docs/problemes.md`

## IDÉE VERROUILLÉE (2026-09-02)

### Nom de travail
**Gage** (provisoire) — *un gage* = la somme mise en garantie + la preuve d'engagement + le gage à accomplir du jeu d'enfance. Alternatives : Enjeu, Tenu. Nom définitif à trancher après check dispo marque INPI + domaine + App Store.

### Pitch
Une app iOS où l'utilisateur fixe chaque semaine (ou chaque matin) des objectifs précis, engage une somme d'argent sur chacun, et **doit prouver leur réalisation via une photo (ou donnée d'usage) vérifiée par IA**. Objectif tenu → il ne perd rien. Objectif raté et non contesté → la somme engagée est débitée.
Promesse : "on ne laisse plus jamais rien tomber".

### Pulsions visées
Statut (image de soi, discipline, ne pas être le maillon faible) + appartenance (si témoins/amis ajoutés plus tard).

### Boucle virale
Contenu : "j'ai perdu 10 € parce que je me suis pas levé" est très partageable. Structurelle possible en v2 via témoins/groupes d'amis (honte sociale = meilleur anti-triche).

### Modèle économique — 3 flux (arrêté avec l'utilisateur)
1. **Abonnement** : **25 €/mois tarif de référence, ramené à 5 €/mois** (remise d'assiduité, PAS une pénalité) si l'utilisateur pose ≥ 3 objectifs/semaine et les tient. Passage 25 → 5 automatique et affiché en temps réel.
2. **Mises perdues** : débitées via la carte enregistrée. **Une partie (ratio à fixer, ~20-30 %) reversée à une association choisie par l'utilisateur** (désamorce l'angle "s'enrichit de vos échecs"), le reste pour la société. Ratio affiché en clair.
3. (implicite) Volume d'engagement = volume de flux.

### Points juridiques / conformité — CRITIQUES
- **Pas un jeu d'argent** (pas de hasard, pas de gain espéré) — mais faire confirmer par un juriste.
- **Formuler le prix comme une remise, jamais comme une pénalité** (risque clause pénale / clause abusive B2C).
- **Consentement au débit "sur échec"** : consentement horodaté explicite à chaque mise, montant plafonné (ex. 50 € max) et affiché avant validation, e-mail de confirmation, historique consultable. Table de consentement versionnée + audit log = éléments à construire.
- **Détention/mouvement de fonds** : passer par un PSP (Stripe). Ne PAS redistribuer l'argent entre utilisateurs (sinon agrément établissement de paiement).
- **App Store (Apple)** : DÉCIDÉ (2026-09-02) — app 100 % native, tout in-app, on accepte la commission Apple. Abonnement via **IAP StoreKit 2** (Small Business Program = 15 %) ; mises via **Stripe** (l'IAP interdit le "real money gaming" et ne sait pas débiter en différé). Question écrite à poser à Apple avant de coder : la mécanique de mise est-elle du "real money gaming" (→ classement 17+, restrictions) ?
- **TVA** : sur l'abo, Apple est merchant of record et reverse la TVA. Sur la part des mises conservée par la société → à qualifier avec l'expert-comptable/juriste (fee de service ? don ?).
- **RGPD** : photos quotidiennes (voiture, domicile, visage), analyse IA, géoloc, Screen Time → base légale, minimisation, hébergement UE, durée de conservation courte des photos.

### Vérification — architecture à 3 niveaux
1. **IA automatique** (instantané) — doit absorber 85 %+ des preuves.
2. **Revue humaine** — cas incertains + tous les litiges + échantillon aléatoire anti-fraude. Coût ~0,20-0,50 €/contrôle → ne se déclenche qu'au-delà d'un seuil de mise ou sur litige.
3. **Contestation** — sous 24-48 h, décision humaine finale sous 72 h, non susceptible d'appel. Contestations abusives répétées facturées.

### Périmètre des objectifs : uniquement le vérifiable
Familles retenues : (a) **présence dans un lieu** (géofence + photo horodatée) ★★★ ; (b) **objet/scène à un instant donné** (photo in-app, fenêtre horaire imposée) ★★ ; (c) **données d'usage téléphone** (API Screen Time iOS) ★★★ iOS ; (d) **preuve d'action produite** (export Strava/Kindle, capture) ★★.
**Exclus au lancement** : "ne pas fumer", "appeler ma mère", "être gentil" — invérifiables.

### Parcours de mise / consentement (décidé 2026-09-02)
- Carte saisie **une seule fois à l'onboarding** : Stripe `SetupIntent` + 3DS + `usage: off_session` → PaymentMethod réutilisable (MIT).
- **Plafonds acceptés à l'onboarding** : mise max par objectif + total max par mois.
- À chaque objectif : affichage conditions + mode de vérif + montant → **confirmation explicite d'un tap** (« Engager X € »), jamais pré-coché, **pas de re-saisie de carte**.
- Enregistrement horodaté + versionné du consentement (montant, conditions, deadline, 4 derniers chiffres, part asso).
- Débit sur échec non contesté = `PaymentIntent` off-session, silencieux.
- Plafond par mise à 100 € (2026-09-03). Plus le montant monte, plus la banque risque d'exiger une SCA sur un débit off-session : à surveiller en bêta.
- **À spécifier dans le cahier des charges** : parcours de secours si SCA exigée par la banque.

### Échec d'encaissement d'une mise (décidé 2026-09-02)
- **Règle principale** : tant qu'un débit de mise n'est pas encaissé → **création de nouvel objectif bloquée**. Bannière + e-mail « mets à jour ta carte », Stripe Smart Retries en fond.
- L'objectif raté **reste raté** ; le montant devient un **solde dû**. Blocage levé quand : solde réglé **ET** carte valide en place. _(OK par défaut, à reconfirmer)_
- Les objectifs **déjà en cours continuent** (consentement déjà donné) ; seule la création est gelée. _(OK par défaut, à reconfirmer)_
- Pendant un blocage pour **incident carte**, le **compteur d'assiduité est neutralisé** (semaines gelées non comptées) → l'utilisateur conserve le tarif 5 € ; ce n'est pas un manque de volonté. Anti-abus : à surveiller si un utilisateur laisse volontairement sa carte KO pour ne plus rien risquer tout en gardant le tarif bas (ex. limite de durée du gel, ou après X jours l'abo repasse à 25 €).
- Paiement de l'abo lui-même (IAP) : géré par Apple (grâce + relance) ; si lapse, RevenueCat coupe l'accès. Rien à coder.

### Anti-triche (dès le MVP)
Capture **uniquement via caméra intégrée à l'app** (pas d'upload galerie) ; **fenêtre horaire aléatoire** (notif surprise dans le créneau choisi) ; horodatage + GPS **côté serveur** ; détection "photo d'écran" par l'IA ; échantillon aléatoire de revues humaines même sur preuves validées.

## Où en est-on

### Fait
- [x] Cadrage produit, recherche d'idées, analyse concurrentielle
- [x] Idée verrouillée (2026-09-02)
- [x] Stack technique arrêtée
- [x] **Schéma complet** : 18 migrations, RLS, machine à états en trigger, RPC `commit_goal` — 24 tests pgTAP
- [x] **Pipeline de vérification** : anti-triche serveur, prompts, routage conservateur — 21 tests Deno
- [x] **Squelette iOS** : modèles, machine à états client, config, APNs — 19 tests, compile sur simulateur

### En cours / à faire — code
- [x] RPC `transition_goal` (`0020`, réécrite par `0023`) et `submit_proof` (`0026`)
- [x] **Planification et ouverture des fenêtres** (`0027`) : `app.tick_notifications()` sur pg_cron, toutes les minutes
- [x] **`send-push`** — livraison seule, avec transport de repli. Jamais exécutée contre Apple (voir ci-dessous)
- [x] **Caméra AVFoundation + pré-filtre Vision + envoi** (`Features/ProofCapture/`, `ProofsAPI`)
- [x] **Edge Function `verify-proof`** — anti-triche, modèle, routage, verdict. Claude en production (Haiku → escalade Sonnet), Gemini comme fournisseur de test
- [x] **Edge Functions Stripe** : `stripe-setup-intent`, `stripe-webhook`, `stripe-charge-stake`, plus le cycle de debit en base (`0029`, `0031`). Verifiees contre le vrai Stripe en mode test
- [ ] `dispute-intake`, `weekly-assiduity`, `purge-proofs`
- [ ] Le reste de l'interface iOS (dépend du design Figma)
- [ ] Abonnement IAP + RevenueCat (reporté après la bêta)

### Dettes ouvertes par le chantier des notifications
- **Aucune sortie pour un objectif jamais notifié.** Si la fenêtre ne s'ouvre
  pas (cron arrêté, aucun appareil enregistré), l'objectif reste `committed` et
  sa mise reste `active` indéfiniment. On refuse délibérément de le rejeter :
  ce serait débiter quelqu'un pour notre panne. La sortie honnête serait
  `committed → human_review`, à ajouter **des deux côtés** (`0015` et
  `GoalStateMachine.swift`).
- **Objets orphelins dans le bucket.** Envoi du fichier réussi puis
  `submit_proof` refusée : l'objet reste, sans ligne qui le désigne et sans
  droit de suppression client. À traiter dans `purge-proofs`.
- ~~**`send-push` n'est pas planifiée.**~~ Réglé par `0032` : le battement
  appelle la fonction via `net.http_post`, avec l'URL et la **clé anon** lues
  dans Vault (`edge_project_url`, `edge_anon_key`). Rien dans le dépôt. Tant
  que les secrets ne sont pas posés, la livraison ne part pas — silencieusement
  et sans erreur, c'est-à-dire exactement le comportement d'avant.

### À faire — hors code (bloquant à terme)
- [ ] **Compte Stripe** (mode test) — bloque tout le paiement
- [ ] **Compte Apple Developer** — type **Individual** (voir décision 2026-09-06). Titulaire : Augustin, Apple ID pro dédié + 2FA. Bloque TestFlight, push réels, Sign in with Apple sur appareil
- [ ] Question écrite à Apple : la mécanique de mise est-elle du « real money gaming » ?
- [ ] Consultation juridique (jeu d'argent / clause pénale / consentement débit / RGPD)
- [ ] Design iOS (onboarding + écrans de consentement en priorité)
- [x] Projet Supabase distant (voir « La base distante » ci-dessous)

## La base distante — on ne travaille plus en local (2026-09-06)

**Le développement se fait désormais contre le projet Supabase distant.** La
pile locale n'est plus la référence : elle peut servir à essayer une migration
avant de la pousser, jamais à valider que l'app marche.

| | |
|---|---|
| Projet | **Objectify**, ref `gdqzpjlexyvtamrtergk` |
| Organisation | celle du collaborateur (Jules) |
| Région | **eu-west-1 (Irlande)** — pas Francfort, contrairement à la décision du 2026-09-02 |
| URL | `https://gdqzpjlexyvtamrtergk.supabase.co` |

`ios/Config/Secrets.xcconfig` pointe dessus. Ce fichier est **gitignoré** :
chacun renseigne le sien, la clé anon n'entre jamais dans le dépôt public.

**La base est partagée avec un collaborateur.** Trois conséquences :

1. **Prévenir avant de pousser.** Deux `db push` simultanés se marchent dessus,
   et l'ordre d'application n'est plus garanti.
2. **Vérifier l'historique avant d'écrire** : `supabase migration list --linked`.
   Une migration distante sans fichier local signale que quelqu'un a poussé
   autrement — c'est arrivé le 2026-09-05, où `0025` avait été appliquée sous
   un numéro horodaté et faisait croire à une divergence de schéma.
3. **Ne jamais modifier une migration déjà poussée**, la règle vaut d'autant
   plus qu'un autre l'a peut-être déjà appliquée.

**Le seed ne suit pas les migrations.** `supabase/seed.sql` n'est joué qu'en
local, à chaque `supabase start` et `db reset`. `db push` n'applique que les
migrations : sur un projet distant, le schéma arrive complet et **les données
de départ manquent**. C'est ce qui a bloqué l'engagement le 2026-09-06 — la
table `charities` était vide, donc la liste d'associations aussi, donc
`profiles.default_charity_id` restait nul, et `commit_goal` se faisait refuser
par la clé étrangère de `stakes.charity_id`. L'écran n'affichait que « Ton
engagement n'a pas pu être enregistré ». Après tout changement de projet
distant, **rejouer le seed à la main** (éditeur SQL du Dashboard, `psql` étant
absent de la machine).

**Corollaire, et c'est le piège** : un `migration list` tout vert ne prouve
pas que la base est utilisable. Les 31 migrations étaient identiques des deux
côtés au moment de la panne. Le contrôle qui rassure le plus est justement
celui qui ne voit rien ici — vérifier les **données** (`charities` non vide,
profil créé) autant que le schéma.

**État des Edge Functions sur le distant** (2026-09-06) : `stripe-setup-intent`
et `stripe-webhook` déployées et vérifiées de bout en bout — carte enregistrée,
`setup_intent.succeeded` reçu, `default_payment_method_id` écrit. Restent à
déployer `stripe-charge-stake`, `verify-proof` et `send-push` ; tout ce qui en
dépend échoue côté app avec un message générique.

**Une panne peut en cacher une autre.** Le parcours de paiement en a empilé
quatre, chacune ne se révélant qu'une fois la précédente levée : fonction non
déployée, puis clé publiable vide côté app, puis webhook absent, puis seed
manquant. Ne pas conclure qu'une correction a échoué parce qu'un nouveau
message apparaît — lire le nouveau message, il a changé.

**Les secrets ne se déduisent pas de `supabase/.env`**, qui ne vaut que pour le
local. Sur le distant, `SUPABASE_URL`, `SUPABASE_ANON_KEY` et
`SUPABASE_SERVICE_ROLE_KEY` sont injectées automatiquement — Supabase refuse
qu'on les pose. Restent à définir : `STRIPE_SECRET_KEY`,
`STRIPE_PUBLISHABLE_KEY`, `STRIPE_WEBHOOK_SECRET` et la clé du fournisseur de
vision pour `verify-proof`.
Le secret de webhook du `.env` vient de `stripe listen` et **ne vaut rien pour
un endpoint distant** : il faut celui de l'endpoint déclaré dans Stripe.

**La clé publiable Stripe vient du serveur** (2026-09-06). `stripe-setup-intent`
la renvoie à côté du client secret, et l'application la pose sur le SDK juste
avant d'ouvrir le formulaire ; `STRIPE_PUBLISHABLE_KEY` dans
`ios/Config/Secrets.xcconfig` n'est plus qu'un secours. La raison n'est pas la
confidentialité — cette clé est publique par conception — mais l'appariement :
elle doit venir du **même compte** que la clé secrète qui a créé le SetupIntent.
Une clé dépareillée, ou vide sur le poste d'un développeur, ne se voyait qu'au
dernier écran, sur « There was an unexpected error » en anglais, au moment
précis où l'on demande une carte. C'est arrivé le 2026-09-06 sur le poste du
collaborateur.

**`stripe-webhook` se déploie avec `--no-verify-jwt`.** Stripe l'appelle sans
jeton Supabase ; sans ce drapeau, chaque notification part en 401. Aucune
section `[functions]` dans `config.toml` ne le fait à notre place.

**L'auth par e-mail dépend de réglages qui ne sont pas dans le dépôt.**
`config.toml` (SMTP Resend, `otp_length = 6`, gabarits `{{ .Token }}`) ne
configure que le local ; le distant se règle par `supabase config push` ou à la
main dans le Dashboard. Un projet hébergé ne lit pas les `content_path`
locaux : si le code à six chiffres est remplacé par un lien, c'est là qu'il
faut regarder. Et un envoi vers une adresse inexistante met celle-ci sur la
**liste de suppression de Resend** — tout envoi ultérieur vers elle est
abandonné en silence, même après correction.

## Décisions
_(date + décision + raison)_
- 2026-09-06 : **le montant d'une mise ne déclenche plus de revue humaine.**
  Le seuil était à 20 €, il passe à `null` : `humanReviewStakeThresholdCents`
  reste dans `RoutingConfig` et le mécanisme reste testé, pour qu'un seuil
  puisse être remis sans réécrire le routage. Restent l'anti-triche, la
  confiance sous 0,8 et l'échantillon aléatoire de 5 %. À réexaminer avant la
  bêta : c'est la garde qui empêchait l'IA de trancher seule jusqu'au plafond
  de 100 €.
- 2026-09-06 : **la fenêtre de contestation est retirée** (`0036`). Un refus
  clôt l'objectif et lance le prélèvement immédiatement. C'était le dernier
  recours humain avant un débit, donc la traduction concrète de l'invariant 2 :
  un faux négatif du modèle débite désormais sans que personne ne puisse s'y
  opposer. **Les deux gardes sont tombées le même jour** — celle-ci et le seuil
  de revue humaine sur le montant. À réexaminer ensemble avant la bêta.
  Le texte de consentement a été réécrit et `termsVersion` passe à
  `2026-09-v2` : il promettait 48 heures de recours, et faire signer un texte
  faux sur le point qui autorise un prélèvement est le risque juridique le
  plus direct du produit.
- 2026-09-06 : **les mises des objectifs tenus sont libérées** (`0035`).
  `stake_status` prévoyait `released` mais rien ne le posait : un objectif
  **tenu** gardait sa mise `active` à vie et continuait de peser sur le
  plafond mensuel. Quelqu'un de parfaitement assidu finissait bloqué par ses
  propres réussites. La migration rattrape aussi l'existant.
- 2026-09-06 : **le débit des mises perdues est déclenché** (`0035`), au même
  battement. Le cycle (`0029`) et `stripe-charge-stake` étaient écrits et
  testés, mais personne ne les appelait : une mise perdue restait due sans
  échéance, et rien ne le disait à l'utilisateur.
- 2026-09-06 : **`verify-proof` est planifiée** (`0034`), sur le même battement
  et le même jeton court que `send-push`. Une preuve envoyée restait sinon en
  `proof_submitted` indéfiniment — sans coût pour l'utilisateur, l'échéance
  étant déjà passée, mais sans réponse non plus.
- 2026-09-06 : **Apple Pay proposé à l'enregistrement de la carte, mais
  conditionné**. Apple Pay n'enregistre pas un numéro de carte, il enregistre un
  jeton propre à l'appareil, et tout le modèle repose sur un débit `off_session`
  déclenché des jours plus tard. Apple veut que cette intention soit annoncée à
  l'enregistrement (`PKDeferredPaymentRequest`), ce qui exige une **page de
  gestion des débits à venir** — qui n'existe pas encore. Tant que
  `PAYMENT_MANAGEMENT_URL` est vide, Apple Pay n'est **pas** proposé et seule la
  saisie de carte reste : un refus de débit sur jeton non déclaré serait
  invisible à l'enregistrement et n'apparaîtrait qu'au moment où quelqu'un rate
  son objectif. Reste à faire, dans cet ordre : la page de gestion, puis
  l'identifiant marchand `merchant.com.augustindurand.gage` sur
  developer.apple.com, son association au compte Stripe, l'activation des
  entitlements dans `project.yml` — et **un débit off-session réellement exécuté
  en mode test** sur un moyen de paiement enregistré via Apple Pay avant de
  considérer que ça marche.
- 2026-09-06 : **on développe contre la base distante**, plus en local. Le
  projet est `gdqzpjlexyvtamrtergk` (Objectify), en **eu-west-1 (Irlande)** et
  non à Francfort comme décidé le 2026-09-02 : la région effective contredit la
  décision écrite, à trancher avant la bêta. La base est **partagée avec le
  collaborateur** — voir « La base distante » pour ce que ça impose.
- 2026-09-01 : contraintes projet + 2 filtres (pulsion primaire, boucle virale) + anti-pattern "plateforme d'attention".
- 2026-09-02 : **idée verrouillée** (commitment device avec preuve IA + argent en jeu).
- 2026-09-02 : abonnement 25 €→5 € formulé en **remise d'assiduité**, pas en pénalité.
- 2026-09-02 : une **part des mises perdues ira à une association** choisie par l'utilisateur.
- 2026-09-02 : **plateforme cible = iOS natif d'abord**. Design soigné, focus consentement.
- 2026-09-02 : objectifs limités au **strictement vérifiable** (photo, géofence, Screen Time, exports d'apps).
- 2026-09-02 : **app 100 % native, tout in-app, commission Apple acceptée. Abo = IAP StoreKit 2 (15 % SBP). Mises = Stripe. Paddle abandonné. Cible = France.**
- 2026-09-02 : prix variable 25 €→5 € géré via **2 produits StoreKit dans un même groupe d'abonnement** (bascule au renouvellement) + offres promo. Revoir la voie DMA UE seulement si trop rigide.
- 2026-09-05 : **audit des preuves du catalogue** (42 → 19). Retrait de toutes
  les preuves de « matériel » et de « décor » — un sac, des chaussures, un badge
  se photographient sans avoir fait l'objectif — et de **tous les selfies**. Un
  objectif de lieu se prouve par une seule photo sur place. La famille « Me
  réveiller » fusionne en un objectif unique : ses déclinaisons n'étaient que
  des façons de prouver la même promesse. Nombre de preuves désormais variable,
  jamais un quota. → `docs/objectifs-verification.md` §7.
- 2026-09-06 : **l'ouverture de la fenêtre de preuve passe en SQL** (`0027`,
  pg_cron), et non plus dans `send-push` comme `docs/architecture.md` le
  prévoyait. Faire porter la transition `committed → proof_window_open` par la
  livraison APNs mettait une panne d'Apple sur le chemin critique de l'argent :
  fenêtre jamais ouverte → soumission impossible → échéance dépassée → débit.
  `send-push` ne fait plus que livrer, et son échec est sans effet sur l'état.
  Corollaire utile : toute la chaîne devient vérifiable en local sans compte
  Apple Developer.
- 2026-09-06 : **délai de soumission fixé à 15 min**, tolérance d'horloge de
  120 s accordée par `submit_proof` — refuser à la seconde près une preuve que
  l'anti-triche juge légitime serait l'invariant 2 à l'envers.
- 2026-09-06 : **compte Apple Developer = Individual**, pas Organization. Raison :
  l'Organization exige un numéro D-U-N-S (délai 1-2 semaines) qui ferait sauter
  la cible bêta. Une seule cotisation 99 €/an couvre les 2 devs — le second est
  ajouté dans App Store Connect (Users and Access) pour TestFlight ; le partage
  de signature se fait via fastlane match, pas d'échange de `.p12`. Migration
  vers Organization possible plus tard sans perdre l'app.
- 2026-09-03 : **plafond par objectif porté de 30 € à 100 €** (roue de mise de 5 € à 100 €, pas de 5 €). S'applique aux nouveaux profils uniquement — migration `0019`. Le plafond mensuel reste à 150 €, à revoir : il n'autorise plus qu'une mise maximale par mois.

## Stack pressentie (en cours de décision — 2026-09-02)
- **iOS** : Swift + SwiftUI (iOS 17+). Natif obligatoire à cause de FamilyControls/DeviceActivity (Screen Time), CoreLocation (géofence), AVFoundation (caméra in-app anti-triche), StoreKit 2.
- **Backend** : Supabase (Postgres + Auth + Storage + Edge Functions TS/Deno), pg_cron pour les jobs hebdo. Région décidée : Francfort ; **région réellement en service : eu-west-1 (Irlande)** — voir « La base distante ».
- **IA vérification** : Claude vision (Haiku 1er passage → Sonnet en escalade) via Edge Function (clé API côté serveur) ; Apple Vision on-device en pré-filtre gratuit.
- **Paiement** : **abo = Apple IAP via StoreKit 2 + RevenueCat** (reçus/entitlements). **Mises = Stripe** (PaymentSheet native + Apple Pay, SetupIntent pour stocker la carte, PaymentIntent off-session au moment de l'échec).
- **Notifications** : APNs planifiées **côté serveur** (heure aléatoire non prédictible).
- **Dashboard revue humaine** : Next.js sur Vercel (ou vues Supabase au début).
- **Analytics / crash** : TelemetryDeck (UE, privacy) + Sentry.
- **Design** : Figma.

## Roadmap MVP (2026-09-02) — objectif : bêta TestFlight en 2 semaines

**Cible réaliste des 2 semaines** : bêta fermée TestFlight, France, périmètre réduit. PAS une sortie App Store publique (revue Apple sur mécaniques d'argent + juridique + entitlement Screen Time = délais calendaires hors dev).

### Comptes / outils à ouvrir (Augustin) — par ordre d'urgence
- 🔴 Apple Developer Program (99 €/an) — 24-48 h, bloquant
- 🔴 Stripe France + KYC — 1-2 j
- 🔴 Projet Supabase région Francfort — immédiat
- 🔴 Clé API Anthropic (Claude) — immédiat
- 🟠 Resend + Sentry + TelemetryDeck — immédiat
- 🟠 Juriste conso/paiement — prise de RDV en parallèle
- 🟠 Question écrite à Apple (real money gaming / classement d'âge) — en parallèle
- 🟢 Demande entitlement FamilyControls (Screen Time, pour plus tard) — lancer maintenant, délai long
- 🟢 RevenueCat — après la bêta (quand on fait l'abo)

### Périmètre bêta
IN : vérif **photo uniquement** ; création objectif ; mise + consentement ; notif aléatoire ; capture in-app ; vérif IA ; débit Stripe sur échec ; contestation basique ; historique.
REPORTÉ : abonnement IAP/RevenueCat, Screen Time, géofence, dashboard revue humaine soigné, sortie App Store publique, Android.

### Déroulé
Semaine 1 : J1 repo + schéma Supabase (users, goals, stakes, proofs, consents, charges, disputes) + RLS + Sign in with Apple · J2 onboarding + carte Stripe (SetupIntent+3DS) + plafonds + consentement · J3 flow création objectif · J4 notif APNs planifiée serveur (pg_cron, minute aléatoire) · J5 caméra in-app + upload Storage.
Semaine 2 : J6 Edge Function vérif Claude vision + détection photo d'écran · J7 machine à états objectif + PaymentIntent off-session + gestion SCA/échec → blocage création · J8 contestation + revue minimale + split asso · J9 historique + reçus + e-mails Resend · J10 passe design · J11 tests E2E · J12 build TestFlight + 5-10 bêta-testeurs · J13-14 buffer + itération faux positifs IA.

### Hors compteur 2 semaines
Revue App Store publique (prévoir ≥ 1 rejet, allers-retours 1-2 sem) · feu vert juriste · entitlement FamilyControls · affinage qualité vérif IA (semaines).

## Valeurs de configuration en vigueur

Toutes provisoires, isolées en constantes. À arbitrer (voir `docs/architecture.md` §8).

| Paramètre | Valeur | Où |
|---|---|---|
| Part reversée à l'association | 25 % (2500 bps) | `AppConfig.swift`, `stakes.charity_bps` |
| Plafond par objectif | 100 € | `profiles.per_goal_cap_cents` |
| Plafond mensuel | 150 € | `profiles.monthly_cap_cents` |
| Seuil de revue humaine | **désactivé** | `routing.ts` |
| Relecture aléatoire | 5 % des validations | `routing.ts` |
| Seuil de confiance du modèle | 0,8 | `routing.ts` |
| Objectifs/semaine pour la remise | 3 | `app.assiduity_threshold()` |
| Rétention des photos | 60 j | `purge-proofs` (à écrire) |
| Délai de soumission d'une preuve | 15 min | `app.proof_window_seconds()`, `MAX_CAPTURE_DELAY_SEC`, `ProofWindow.duration` |
| Tolérance d'horloge | 120 s | `app.proof_clock_grace_seconds()`, `CLOCK_SKEW_TOLERANCE_SEC` |
| Fenêtre de contestation | **0 h (retirée)** | `app.dispute_window_hours()` |

**Le délai de soumission vit à trois endroits** (base, vérification, iOS) et
aucune vérification automatique ne détecte une divergence — chaque côté a un
test qui assène le littéral 900. Même remarque pour la tolérance d'horloge.

## Conventions de travail
- Documentation, commentaires et commits en **français** ; code et schéma en **anglais** ; textes utilisateur en français.
- Migrations numérotées, **en avant seulement** — on ne modifie jamais une migration poussée.
- Le projet Xcode est **généré** par XcodeGen depuis `ios/project.yml` : modifier le YAML, jamais le projet dans Xcode.
- Docs de recherche dans `docs/`.
- Ne jamais télécharger un runtime de simulateur depuis l'interface Xcode — utiliser `xcodebuild -downloadPlatform iOS`. Les deux en parallèle créent des doublons qui cassent le montage.

## Historique des incidents (pour ne pas les refaire)
- **2026-09-02** — Le trigger de la machine à états échouait sur une erreur de permission pour tout appel client : le rôle `authenticated` n'avait pas accès au schéma `app`. La garde qui protège l'argent ne s'exécutait donc jamais dans le cas qui compte. Trouvé en exécutant, invisible à la lecture.
- **2026-09-02** — Le journal d'audit se faisait refuser par sa propre RLS dès qu'une transition venait d'un client. Corrigé en passant les triggers en `security definer`.
- **2026-09-06** — Le cron n'a jamais reussi a declencher `send-push`. Il
  passait la cle anon dans un en-tete `Authorization` via `net.http_post`, et
  le portail repondait invariablement 401 `UNAUTHORIZED_INVALID_JWT_FORMAT` —
  **y compris avec la cle ecrite en dur dans la requete**, ce qui innocente
  Vault : `pg_net` ne transporte pas sans dommage une valeur d'en-tete de 215
  caracteres. La meme cle envoyee par `curl` passe. Corrige par `0033` : jeton
  court dans un en-tete a nous, controle par la fonction elle-meme, deployee
  en `--no-verify-jwt`. **Le piege du diagnostic** : chaque `curl` de secours
  vidait la file, si bien que l'essai suivant n'avait plus rien a livrer et
  sortait sans erreur — on a cru trois fois que c'etait repare. `pg_net` est
  asynchrone : les codes HTTP se lisent dans `net._http_response`, et les
  appels du cron s'y reconnaissent a leur horodatage sur la minute pleine.
- **2026-09-06** — Aucune preuve n'atteignait le bucket. `UUID.uuidString`
  rend l'identifiant en **majuscules**, `auth.uid()::text` en **minuscules**,
  et la policy de stockage compare les deux chaînes telles quelles : tout
  envoi était refusé. L'écran affichait « Ta photo n'a pas pu être envoyée »
  sans dire pourquoi, et `submit_proof` aurait refusé une seconde fois, elle
  revérifie le même préfixe. Le test comparait le chemin à `user.uuidString`,
  donc il validait n'importe quelle casse. Trouvé en envoyant une vraie photo
  depuis un vrai appareil. **La règle générale** : dès qu'un UUID est comparé
  à du **texte** côté base — un préfixe de chemin, un `like`, une policy — il
  se met en minuscules côté client. Passé comme valeur typée dans une requête
  PostgREST, il est casté en `uuid` et la casse n'a aucune importance ; c'est
  la comparaison textuelle, et elle seule, qui est piégeuse.
- **2026-09-06** — Aucune notification ne partait, et rien ne le signalait.
  `entitlements` avec un `path` mais sans `properties` ne rattache pas un
  fichier écrit à la main : **XcodeGen le génère**, vide, et écrase le
  contenu à chaque `xcodegen generate`. L'app partait signée sans
  `aps-environment` alors que la capability était cochée sur l'App ID et que
  le profil de provisioning portait le droit. La compilation réussissait.
  Le seul contrôle qui fasse foi est le binaire signé :
  `codesign -d --entitlements - <app>.app`. Au passage, `DEVELOPMENT_TEAM:
  $(DEVELOPMENT_TEAM)` dans les réglages d'une cible est une auto-référence
  que Xcode résout en chaîne vide, tout en écrasant la valeur du xcconfig.
- **2026-09-02** — Runtime de simulateur iOS téléchargé simultanément par Xcode et en ligne de commande → trois images en double, toutes invalidées, asset purgé. 8 Go à retélécharger.
