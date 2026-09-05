# Objectifs & vérification — catalogue

_2026-09-04. Quels objectifs l'app propose, et comment chacun est prouvé.
Base de travail pour le cahier des charges de la création d'objectif et du
pipeline `verify-proof`._

> Rappel invariant (voir `architecture.md` §2) : **on ne débite jamais sur un
> doute.** Tout objectif dont la preuve est ambiguë part en revue humaine, pas
> en échec automatique. Un objectif qui ne peut pas produire de preuve nette
> n'entre pas au catalogue.

> **Décision 2026-09-04 : pas de challenge dynamique.** On ne demande jamais à
> l'utilisateur, au moment de la notif, un élément surprise à intégrer à la
> photo. Risque : quelqu'un qui a fait son objectif panique sur la consigne,
> la rate, et perd sa mise à tort. **Ce qui doit figurer dans la preuve est
> défini à l'avance, à la création de l'objectif**, et affiché dans l'écran de
> capture. La seule chose imprévisible reste **le moment** (fenêtre surprise).

---

## 1. Les cinq mécanismes de vérification

| # | Mécanisme | Source du signal | Falsifiable par l'utilisateur ? | Dispo |
|---|---|---|---|---|
| M1 | **Photo caméra in-app** | `AVFoundation`, jamais la photothèque | Image non falsifiable ; reste la possibilité de rephotographier une scène préparée | ✅ Bêta |
| M2 | **Position** | `CoreLocation` + recoupée serveur | Difficile (spoofing GPS = jailbreak) | ✅ Bêta (géofence simple) |
| M3 | **Horodatage serveur** | horloge serveur à la réception | Non | ✅ Bêta |
| M4 | **Trace d'effort** | `CoreLocation` en continu / `HealthKit` workout | Oui (voiture pour une « course ») → contrôle vitesse/cadence | ⚠️ v2 |
| M5a | **Pas** — `CMPedometer` (Core Motion), lu directement | capteur de mouvement de l'iPhone, aucune écriture tierce possible | seulement par mouvement physique du téléphone | ✅ **Bêta** |
| M5b | **Temps d'écran** — `DeviceActivity` | l'OS | non (sans jailbreak) | ⚠️ v2 (entitlement `FamilyControls`) |
| M5c | **Sommeil** — `HealthKit` `sleepAnalysis` | agrégat + saisie manuelle | oui (saisie manuelle) | ⚠️ v2, à réévaluer |

Un objectif = **une combinaison** de ces mécanismes. Plus il y a de signaux
indépendants qui doivent concorder, plus la triche coûte cher. Le pilier
anti-triche de la bêta est **M1 (caméra only) + M3 (fenêtre surprise étroite)**
complété par **M2** quand un lieu est en jeu et par la **détection de doublon
visuel** pour les objectifs récurrents.

---

## 2. Catalogue des objectifs

Colonnes : **Fiab.** = fiabilité de la preuve (★ faible → ★★★ solide).
**Dispo** = Bêta / v2. **Point faible** = la façon de tricher qui reste
possible et ce qui l'atténue.

### 2.1 Présence dans un lieu — le lieu EST l'objectif

| Objectif | Vérification | Point faible & parade | Fiab. | Dispo |
|---|---|---|---|---|
| Aller à la salle de sport | M2 géofence sur le POI + M1 photo (rack, machines) + M3 dans la fenêtre surprise | Rentrer, badger, photographier, repartir = objectif atteint de fait | ★★★ | Bêta |
| Piscine | idem, IA reconnaît bassin / vestiaire humide | idem | ★★★ | Bêta |
| Salle d'escalade | idem, IA reconnaît mur / prises | idem | ★★★ | Bêta |
| Entraînement club (foot, rugby, combat) | M2 géofence club + M1 photo terrain/tatami + M3 à l'heure de l'entraînement | Ne prouve **pas** la pratique → objectif formulé « être au club à l'heure », pas « j'ai joué » | ★★ | Bêta |
| Café / bar / restaurant | M2 géofence POI + M1 photo intérieur + M3 | Faible valeur anti-triche mais faible enjeu | ★★ | Bêta |
| Bibliothèque / musée / cinéma | M2 géofence POI + M1 photo (rayonnages, salle, écran) + M3 | idem | ★★ | Bêta |

**Règle** : uniquement des lieux **publics avec une adresse POI**. Pas de
« jardin », « domicile », « chez un ami » dans cette catégorie — ils vont en 2.2.

### 2.2 Scène à un instant donné — le lieu n'est qu'un décor

On ne prouve pas *où*, on prouve *que l'utilisateur est debout et actif dans
la fenêtre surprise*. La géofence ne sert à rien ; ce sont **M1 + M3 + le
descriptif de preuve défini à la création** qui portent tout.

| Objectif | Vérification | Point faible & parade | Fiab. | Dispo |
|---|---|---|---|---|
| Se lever avant 7 h (photo dehors : jardin, rue, voiture) | M1 photo extérieur + M3 fenêtre surprise 6 h–8 h + IA (lumière du matin, scène plausible) | Photo depuis le lit par la fenêtre puis rendormi. Accepté : la personne s'est réveillée à l'heure, c'était le deal. Photo de la veille impossible (caméra only) | ★★ | Bêta |
| Petit-déjeuner fait | M1 photo table + M3 créneau matinal | Photo d'un petit-déj recyclé → M3 étroit + doublon visuel | ★★ | Bêta |
| Lit fait | M1 photo chambre + M3 fenêtre surprise le matin | Très nette pour l'IA, peu de triche possible | ★★★ | Bêta |
| Évier vide / vaisselle faite | M1 photo cuisine + M3 créneau du soir | idem | ★★★ | Bêta |
| Bureau rangé avant de commencer | M1 photo poste + M3 | idem | ★★ | Bêta |
| Routine soin du soir | M1 photo miroir salle de bain + M3 21 h–23 h | Prouve la présence dans la salle de bain, pas le soin lui-même → enjeu perso, acceptable | ★★ | Bêta |
| Tenue soignée / rasé avant 9 h (jours ouvrés) | M1 photo miroir + M3 | Subjectif pour l'IA → seuil de confiance bas → revue humaine fréquente au début | ★ | Bêta (prudence) |

### 2.3 Alimentation

| Objectif | Vérification | Point faible & parade | Fiab. | Dispo |
|---|---|---|---|---|
| Repas fait maison (substitut à « pas de livraison ») | M1 photo assiette + M3 à chaque repas | Photographier un plat resto comme « fait maison » → IA (dressage, contenant) + doublon visuel | ★★ | Bêta |
| Boire de l'eau (gourde) | M1 photo gourde + M3 à des heures surprises | Faible enjeu, faible triche | ★ | Bêta |
| Prendre médicaments / compléments | M1 photo pilulier du jour vidé + M3 | Ne prouve pas l'ingestion → acceptable, enjeu perso | ★★ | Bêta |

### 2.4 Création / pratique

| Objectif | Vérification | Point faible & parade | Fiab. | Dispo |
|---|---|---|---|---|
| Pages écrites (journal, manuscrit, révisions) | M1 photo du cahier/écran + M3 ; à la création l'utilisateur déclare « photo de la page manuscrite du jour » | Rephotographier une page déjà écrite → l'IA compare aux preuves précédentes (le texte doit avoir changé/progressé) | ★★ | Bêta |
| Session instrument | M1 photo instrument + pupitre + partition + M3 | Ne prouve pas la pratique effective → présence du matériel installé, acceptable | ★ | Bêta (prudence) |

### 2.5 Extérieur / air

| Objectif | Vérification | Point faible & parade | Fiab. | Dispo |
|---|---|---|---|---|
| Marche quotidienne | M1 photo dehors + M2 position ≠ domicile + M3 ; **lieu différent chaque jour** (l'IA compare aux preuves précédentes) | Même endroit tous les jours → doublon visuel + M2 | ★★ | Bêta |
| Sortir le chien | M1 photo extérieur avec le chien + M3 | idem | ★★ | Bêta |
| Pause déjeuner dehors | M1 photo + M2 position ≠ bureau + M3 créneau midi | idem | ★★ | Bêta |

### 2.6 Corps / apparence (pulsion reproduction — artefact partageable)

| Objectif | Vérification | Point faible & parade | Fiab. | Dispo |
|---|---|---|---|---|
| Photo de progression physique (1×/sem, même pose) | M1 photo + M3 ; pose et cadrage fixés à la création | L'artefact avant/après est le contenu viral natif Insta. Photo ancienne → caméra only + doublon visuel | ★★ | Bêta |
| Pesée hebdo | M1 photo du chiffre sur la balance + M3 fenêtre surprise le matin | Photographier un vieux relevé → M3 étroit ; à la création, « balance + pieds visibles » fait partie du descriptif de preuve (défini à l'avance, pas surprise) | ★★ | Bêta |

### 2.7 Social (pulsion appartenance)

| Objectif | Vérification | Point faible & parade | Fiab. | Dispo |
|---|---|---|---|---|
| Voir quelqu'un en vrai | M1 photo à deux (café, resto, marche) + M2 + M3 | Pas de vérif d'identité → faible. Se renforce avec les **témoins/groupes v2** (la personne confirme) | ★ | v2 |
| Défi entre amis (témoins) | témoin humain valide/invalide la preuve dans l'app | Collusion entre amis → échantillon de revue humaine | ★★ | v2 |

### 2.8 Trace d'effort — GPS chronométré (M4)

| Objectif | Vérification | Point faible & parade | Fiab. | Dispo |
|---|---|---|---|---|
| Course à pied X km | M4 tracé `CoreLocation` continu pendant l'activité + M3 | Voiture/vélo pour une « course » → **contrôle de vitesse et d'accélération** (allure > 20 km/h = rejet), cadence si dispo | ★★ | **v2** |
| Sortie vélo X km | M4 tracé + profil de vitesse cohérent | Scooter → contrôle vitesse/plage plausible | ★★ | **v2** |
| Séance de sport (workout) | M5 `HealthKit` workout (source = Watch/iPhone uniquement) + M1 photo fin de séance | Écriture `HealthKit` tierce → filtrer sur `HKSource`, croiser avec M1 | ★★ | **v2** |

> **Décision à trancher pour la v2** : autoriser un **connecteur Strava / Apple
> Santé en lecture seule** (donnée vérifiée à la source) plutôt que de
> reconstruire la détection de fraude sur trace brute. Plus simple, plus fiable.
> La capture d'écran d'une app tierce reste **interdite** (règle « caméra
> uniquement »).

### 2.10 Pas — `CMPedometer` (M5a) — ✅ BÊTA

| Objectif | Vérification | Point faible & parade | Fiab. | Dispo |
|---|---|---|---|---|
| X pas dans la journée (ex. 8 000) | M5a **`CMPedometer` (Core Motion) lu directement**. **Ne jamais passer par `HealthKit`** (agrégat + saisie manuelle). Requête quotidienne (historique limité à ~7 j). Comptage sur la journée calendaire, fuseau de l'appareil | Plus d'injection de données possible. Reste le **spoofing physique** (secouer, accrocher au chien, poser sur un objet qui oscille) → plafonner l'enjeu + détecter les profils non humains (cadence irrégulière, pas en rafale, tout en fin de journée) → revue humaine. **Faux négatif** si téléphone laissé à la maison alors que la personne a marché → UX explicite « garde ton téléphone sur toi », enjeu perso assumé | ★★★ (donnée) / ★★ (spoofing physique) | ✅ **Bêta** — aucun entitlement, seulement l'autorisation *Mouvement et forme physique* |

> **Spécificité machine à états** : comme le temps d'écran, la vérification est
> **passive** — pas de photo à soumettre. À l'échéance de la journée, l'Edge
> Function lit le total `CMPedometer` remonté par le client et tranche
> `success` / `failed`. Le client doit envoyer la donnée ; s'il ne l'envoie pas
> (app jamais ouverte de la journée) → relance push, puis revue humaine, jamais
> échec direct. À modéliser des deux côtés (`GoalStateMachine.swift` + trigger
> SQL).

### 2.11 Sommeil & temps d'écran (M5b / M5c) — v2

| Objectif | Vérification | Point faible & parade | Fiab. | Dispo |
|---|---|---|---|---|
| < 30 min/j Instagram + TikTok, < 2 h/j écran total, pas de réseaux avant 9 h | M5b `DeviceActivityMonitor` : l'OS déclenche au dépassement | Donnée OS **non falsifiable** sans jailbreak. Désinstaller FamilyControls → l'app le détecte et invalide la semaine | ★★★ | **v2** — bloqué sur entitlement `FamilyControls` (délai calendaire long) |
| Heure de coucher avant minuit | M5c `HealthKit` `sleepAnalysis` | Saisie manuelle possible dans Santé → très faible. Données **très sensibles RGPD** | ★ | **v2, à réévaluer** |

> **Temps d'écran** : vérification **négative et passive**. `success` par défaut
> à l'échéance ; un événement de dépassement transmis par
> `DeviceActivityMonitor` fait basculer en `failed`. Chemin distinct de la
> preuve photo, à modéliser des deux côtés.
> **Sommeil** : candidat le plus faible du catalogue, manipulable et sensible.
> Ne pas l'ouvrir sans garde-fou fort (donnée Watch obligatoire).

---

## 3. Le descriptif de preuve (défini à la création)

Remplace le challenge dynamique. À la création de l'objectif, l'utilisateur
choisit un template et **voit exactement ce que sa photo devra montrer**. Ce
texte est :

- **stocké avec l'objectif** (immuable après le consentement, comme le reste) ;
- **réaffiché dans l'écran de capture** au moment de la notif surprise ;
- **passé au modèle** dans le prompt `verify-proof` comme critère d'acceptation.

Exemples de descriptifs :
- salle de sport → « photo à l'intérieur de la salle : machines ou poids
  visibles »
- lever → « photo prise dehors ou à une fenêtre : lumière du jour visible »
- pesée → « photo de l'écran de la balance avec le chiffre lisible et tes pieds
  dessus »
- pages écrites → « photo de la page manuscrite écrite aujourd'hui »
- marche → « photo en extérieur, à un endroit différent d'hier »

**Principe** : rien dans le descriptif n'est une surprise. Si l'utilisateur a
fait l'objectif, il sait d'avance quoi photographier et peut le faire sans
stress. La seule inconnue est l'heure.

**Si la photo ne colle pas au descriptif mais l'objectif semble atteint** →
revue humaine, jamais échec direct (invariant §2).

---

## 4. Règles transverses

1. **Objectif négatif → preuve positive de substitution.**
   « Pas de fast-food » n'est pas vérifiable ; « photo d'un repas maison à
   chaque repas » l'est. Le seul négatif vérifié directement est le temps
   d'écran (M5, v2), parce que la donnée vient de l'OS.

2. **Jamais de photothèque.** M1 = caméra in-app exclusivement. C'est la
   première barrière anti-triche et elle est non négociable (invariant §2).

3. **La fenêtre surprise porte l'anti-triche temporel.** Notif à une minute
   aléatoire dans le créneau choisi ; délai de réponse court (5–15 min selon
   la famille). L'instant exact n'est jamais lisible côté client (invariant §2).
   C'est la **seule** part imprévisible de la demande de preuve.

4. **Détection de doublon visuel** pour tous les objectifs récurrents :
   comparer la preuve du jour aux précédentes. Bloque le recyclage de photo
   sans avoir besoin d'une consigne surprise.

5. **Objectif subjectif → seuil de confiance bas → revue humaine.** « Tenue
   soignée », « bureau rangé » : au lancement on route large vers l'humain,
   on resserre quand on a des données de faux positifs.

6. **Plafond d'enjeu corrélé à la fiabilité.** Un objectif ★ (pesée, instrument,
   pas) ne devrait pas pouvoir porter la mise maximale tant que la vérif n'est
   pas éprouvée.

7. **Quand l'heure est l'objectif, elle se fixe à la création.** La plupart des
   objectifs tolèrent « je donnerai l'heure le jour même » : on promet d'aller à
   la salle, pas d'y aller à 18 h. Un réveil, non — l'heure *est* la promesse, et
   la renseigner le matin reviendrait à la choisir une fois levé, c'est-à-dire à
   ne rien promettre. La famille « Me réveiller » porte donc
   `requiresFixedTime`, qui retire l'option « le matin même » et impose la roue
   horaire. La garde est aussi dans le domaine (`GoalPlan.setTime`), pas
   seulement à l'écran.

---

## 5. Récapitulatif périmètre bêta

**IN (bêta TestFlight, France) :**
- Présence lieu public (2.1) : salle, piscine, escalade, café, bar, biblio,
  musée, ciné, club de sport.
- Scène à instant donné (2.2) : lever, petit-déj, lit fait, vaisselle, bureau,
  routine soin.
- Alimentation (2.3), création (2.4), extérieur (2.5), apparence (2.6).
- **Objectif « pas » via `CMPedometer` (2.10)** — décidé 2026-09-04.
- Mécanismes M1 + M2 (géofence simple) + M3 + M5a (pas) + descriptif de preuve
  défini à la création + doublon visuel.

**OUT (v2) :**
- Trace d'effort GPS chronométrée (2.8) — via connecteur Strava/Santé.
- Temps d'écran (2.11) — bloqué sur entitlement `FamilyControls`.
- Sommeil (2.11) — fiabilité insuffisante sans Watch.
- Social / témoins (2.7) — arrive avec la boucle virale structurelle.

---

## 6. À faire

- [ ] Rédiger le **descriptif de preuve** de chaque template d'objectif bêta
      (texte utilisateur, français).
- [ ] Implémenter la lecture `CMPedometer` côté iOS + envoi quotidien du total
      au backend ; détection de spoofing physique ; plafond d'enjeu dédié.
- [ ] Spécifier le chemin machine à états « vérification passive » (pas M5a en
      bêta, temps d'écran M5b plus tard) — les deux côtés : SQL + Swift.
- [ ] Décider connecteur Strava/Santé vs détection de fraude sur trace (v2).
- [ ] Table `goal_templates` : encoder par template les mécanismes requis, la
      fenêtre, le descriptif de preuve, le plafond d'enjeu autorisé, le seuil
      de confiance IA.
- [ ] Prompt `verify-proof` : intégrer le descriptif de preuve comme critère
      et la comparaison aux preuves précédentes (doublon visuel).

---

## 7. Audit du catalogue in-app — 2026-09-05

Le catalogue embarqué (`ios/Gage/Domain/GoalCatalogue.swift`) proposait
mécaniquement **3 preuves pour chacune de ses 14 déclinaisons, soit 42**. Le
quota était l'erreur : pour tenir trois options partout, il fallait inventer des
preuves qui n'en sont pas. Après audit, **42 → 19 preuves et 14 → 12
déclinaisons**.

### Les cinq critères

1. **Probante** — la photo atteste l'action accomplie ou son résultat, jamais du
   matériel, une préparation ou un décor. Un sac prêt, des chaussures aux pieds,
   un vélo sorti précèdent l'effort et ne l'attestent pas.
2. **Sans visage** — aucune preuve ne repose sur le fait de se photographier.
   C'est la donnée la plus sensible qu'on puisse réclamer tous les jours (§RGPD
   de `CLAUDE.md`), et aucun objectif ne doit en dépendre.
3. **Une seule preuve quand le lieu est l'objectif** (§2.1) — la photo sur place
   ferme la question. Plusieurs options ne se justifient que si le lieu prend des
   formes différentes selon les gens : « aller au travail » est la seule
   exception, un lieu de travail pouvant être un bureau, une entrée d'immeuble
   ou un atelier.
4. **Tranchable** — le modèle vision décide sans ambiguïté. « Confirme que rien
   ne traîne » est un jugement, pas un constat (règle §4.5).
5. **Non redondante** — pas deux cadrages de la même scène dans une même
   déclinaison, pas de doublon avec une autre déclinaison de la même famille.

### Preuves retirées

| Déclinaison | Preuve retirée | Motif |
|---|---|---|
| Me lever | `selfie` Selfie du matin | Visage |
| Me lever | `street` Photo de la rue | Doublon d'`outside` |
| Me lever et petit-déjeuner | `kitchen` Photo de la cuisine | Décor : une cuisine ne prouve aucun repas |
| Me lever et petit-déjeuner | `selfie` Selfie à table | Visage |
| Me lever et sortir | `shoes` Chaussures aux pieds | Matériel |
| Me lever et sortir | `selfie` Selfie dehors | Visage |
| La salle | `machine` Photo de la machine | Doublon du lieu |
| La salle | `bag` Photo du sac ouvert | Matériel |
| Le foot | `boots` Crampons aux pieds | Matériel |
| La course | `shoes` Chaussures aux pieds | Matériel |
| La piscine | `gear` Bonnet et lunettes | Matériel |
| Le vélo | `bike` Photo du vélo sorti | Matériel — « prête » désigne l'avant-effort |
| Foot, course, piscine, vélo | `selfie` (×4) | Visage |
| Mon lit | `pillows` Oreillers en place | Redondant avec `made` |
| Mon bureau | `tidy` Affaires rangées | Redondant, et « rien ne traîne » est indécidable |
| Le ménage | `bins` Poubelles sorties | Hors sujet : sortir les poubelles n'est pas le ménage |
| Aller au travail | `badge` Badge en main | Matériel : un badge se photographie n'importe où |
| Mes devoirs | `closed` Cahier fermé | N'atteste aucun travail |
| Mes devoirs, Réviser | `selfie` (×2) | Visage |
| Réviser | `desk` Bureau en séance | Décor, redondant avec les fiches |

### Deux conséquences de structure

**La famille « Me réveiller » fusionne en un seul objectif.** Ses trois
déclinaisons — « juste me lever », « me lever et petit-déjeuner », « me lever et
sortir » — n'étaient pas trois promesses mais une seule, « me lever », avec trois
façons de la prouver : lit fait, petit-déjeuner, extérieur. Une famille qui n'a
qu'une déclinaison la retient d'office et son écran de choix est sauté
(`GoalPlan.selectCategory`).

**Sept déclinaisons sur douze n'ont plus qu'une preuve** (salle, foot, course,
piscine, vélo, devoirs, réviser). L'écran de preuve reste affiché malgré tout :
il n'y fait plus choisir mais annonce ce qu'il faudra photographier, ce que la
doctrine du descriptif de preuve (§3) exige. La preuve unique y est
pré-sélectionnée.

> **Règle** : le nombre de preuves d'un objectif est **variable**. On n'en invente
> pas pour tenir un quota — c'est exactement ce qui avait produit « photo de ton
> sac ouvert ». `GoalPlanTests` n'exige donc qu'**au moins une** preuve par
> déclinaison, et interdit explicitement le retour des selfies.
