# Recherche d'idées — SaaS B2C francophone, solo/bootstrapé, abonnement

_Dernière mise à jour : 2026-09-01_

## 1. Grille de filtrage

Une idée est retenue si elle coche :
1. **Douleur récurrente** → justifie un abonnement (pas un achat unique).
2. **Valeur dès la 1re session** → limite le churn semaine 1.
3. **Constructible en solo en < 3 mois** (pas de hardware, pas de conformité bancaire lourde, pas de marketplace).
4. **Angle "France/FR" défendable** → langue, réglementation, culture, ou concurrence anglo-saxonne absente/faible.
5. **Canal d'acquisition accessible sans budget** → SEO, communautés, bouche-à-oreille, réseaux.
6. **Willingness to pay prouvée** → des gens paient déjà pour résoudre ça (autre app, humain, bricolage).

## 2. Contexte marché (sources en bas)

- Marché micro-SaaS : ~15,7 Md$ → ~59,6 Md$ d'ici 2030 (~30 %/an). Coût avant 1er revenu généralement < 1 000 $.
- 2025 = meilleure année des indie hackers : l'assistance IA au code multiplie ~×5 ce qu'un solo peut livrer → plus de one-person SaaS à 10–200 k$ MRR.
- **Attention IA** : les apps "IA" à abonnement mensuel retiennent **36 % moins bien sur 12 mois** que les apps classiques (rétention payeur 12 mois ~9–11 %). L'IA doit être un moyen, pas la promesse.
- Tarification : le tiered pricing reste dominant ; 85 % des SaaS ajoutent une composante usage.
- France : l'État prépare **AMI**, super-app interministérielle (démarches, impôts, carte grise), test depuis janv. 2026, grand public possible ~oct. 2026 → **risque de dépréciation** pour tout ce qui touche aux démarches administratives génériques.

## 3. Shortlist d'idées

### Idée A — Coach budget/finances perso "à la française"
- **Problème** : les apps de budget (Bankin', Linxo…) s'arrêtent au graphique ; peu de conseil actionnable, peu adaptées aux spécificités FR (livrets, PEA/AV, prélèvements, impôt à la source, RAV).
- **Cible** : 25–40 ans, revenus moyens, veulent "reprendre le contrôle" sans payer un CGP.
- **Récurrence** : forte (suivi mensuel, alertes, objectifs).
- **Monétisation** : 4–8 €/mois. Palier sup. avec projections épargne/fiscalité.
- **Concurrents** : Bankin' (freemium, gros), Linxo, Finary (patrimoine, plutôt CSP+), YNAB (US, payant, pas FR-natif), Mon Petit Placement. Agrégation bancaire = **DSP2 via un agrégateur** (Bridge, Powens) → coût récurrent + conformité → **frein solo n°1**.
- **Angle FR** : conseil fiscal/produits d'épargne FR, ton pédagogique, pas de vente de produits.
- **Risque #1** : dépendance à un agrégateur bancaire (coût, contrat, conformité) ; concurrents installés.
- **Test** : landing "coach budget FR" + 20 interviews ; tester saisie manuelle/CSV d'abord (sans agrégateur) pour valider la valeur du *conseil*.
- **Verdict** : intéressant mais l'agrégation bancaire casse la contrainte "solo léger". À ne garder que si on démarre sans connexion bancaire.

### Idée B — Assistant déclaration & optimisation d'impôt sur le revenu (particuliers)
- **Problème** : la déclaration IR stresse ; les gens ratent des crédits/réductions (dons, emploi à domicile, garde d'enfants, travaux, frais réels vs forfait). Les experts-comptables ne prennent pas les particuliers simples.
- **Cible** : foyers avec un peu de complexité (frais réels, immobilier locatif nu/LMNP débutant, freelances au réel simplifié, parents séparés).
- **Récurrence** : **faible en apparence** (1×/an) → **risque abonnement**. Contrer par : suivi toute l'année (simulateur de reste à vivre après impôt, aide au taux de PAS, acomptes, alertes échéances, LMNP : amortissements/recettes).
- **Monétisation** : 6–12 €/mois annualisé, ou 39–79 €/campagne. Abonnement "sérénité fiscale" à l'année.
- **Concurrents** : impots.gouv (gratuit, officiel), Tacotax/Jestimo (défunt/pivots), LeLynx-like, experts-comptables en ligne (Indy, Dougs → orientés pro/BNC), Paperasse.ai & AdminLanding (plutôt expats/paperasse, pas optimisation IR). **Peu d'acteur grand public purement "optimisation IR + suivi annuel".**
- **Angle FR** : 100 % spécifique — non attaquable par un acteur US.
- **Risque #1** : saisonnalité (avril–juin) ; responsabilité perçue sur le conseil fiscal ; AMI côté démarches (mais AMI ≠ optimisation).
- **Test** : landing avant campagne 2026, simulateur gratuit d'"impôt potentiellement récupéré", mesurer email→attente de la version suivi annuel.
- **Verdict** : **fort angle FR, faible concurrence grand public**. Le défi = transformer un acte annuel en abonnement. Creuser l'angle **LMNP débutant** (vraie récurrence : loyers, charges, liasse 2031) — sous-segment qui paie (Decla.fr, JeDeclareMonMeuble existent → concurrence réelle mais marché en croissance).

### Idée C — LMNP / loueur meublé non pro : compta + liasse fiscale
- **Problème** : ~800 k foyers LMNP, obligation de comptabilité (amortissements) au régime réel ; l'expert-comptable coûte 300–600 €/an ; peu s'y retrouvent seuls.
- **Cible** : particulier avec 1–3 biens meublés, régime réel.
- **Récurrence** : **native** (saisie loyers/charges toute l'année, clôture annuelle, télétransmission liasse).
- **Monétisation** : 10–20 €/mois ou 150–250 €/an (vs 400 € comptable) → willingness to pay **prouvée**.
- **Concurrents** : **JeDeclareMonMeuble, Decla.fr, Nopli, Indy (ajout LMNP), Amarris** → marché déjà servi. Différenciation possible : UX, onboarding, prix, accompagnement AVA/OGA, multi-biens, SCI à l'IS.
- **Angle FR** : total.
- **Risque #1** : concurrence frontale établie + besoin d'un partenariat AVA (association de gestion agréée) ou d'un expert-comptable pour le visa → **casse le "solo"** (au moins un partenariat).
- **Verdict** : marché validé mais **déjà concurrentiel et semi-réglementé**. Passe seulement si on trouve un sous-segment mal servi (ex. LMNP + résidence services, ou expats propriétaires en France).

### Idée D — Gestion des abonnements & résiliation (subscription manager FR)
- **Problème** : abonnements oubliés, essais gratuits non résiliés, hausses silencieuses.
- **Récurrence** : moyenne (l'utilisateur peut "nettoyer" puis partir → churn).
- **Monétisation** : 3–5 €/mois.
- **Concurrents** : Origin, Rocket Money (US), Bankin' Coach, **Lydia/banques** intègrent la détection ; **fort risque de commoditisation** (déjà une feature des néobanques). Nécessite agrégation bancaire (idem idée A).
- **Verdict** : **écarté** — feature, pas produit ; commoditisé ; churn structurel.

### Idée E — Suivi santé/nutrition : rééquilibrage alimentaire coaché (FR, non-régime)
- **Problème** : les gens veulent manger mieux/perdre du poids sans app US à la Noom (chère, en anglais, culpabilisante) ni diététicien à 50 €/séance.
- **Cible** : 30–50 ans, francophones, veulent des repas concrets adaptés aux produits/habitudes FR.
- **Récurrence** : forte si programme + menus hebdo + suivi.
- **Monétisation** : 8–15 €/mois.
- **Concurrents** : Yazio, MyFitnessPal, Foodvisor (FR !), Noom, Weight Watchers, Jow (courses, gratuit/affilié). **Marché saturé**, churn meal/nutrition élevé (9–15 %/mois).
- **Verdict** : **écarté** sauf niche très précise (ex. nutrition périménopause FR, diabète gestationnel, sportifs d'endurance amateurs) — sinon rouge sang.

### Idée F — Assistant "vie administrative de la famille" (post-naissance, séparation, décès, déménagement)
- **Problème** : événements de vie = avalanche de démarches (CAF, Sécu, employeur, mutuelle, école, impôts, banque, notaire). Stress, oublis, délais.
- **Cible** : jeunes parents, personnes en séparation, aidants après un décès.
- **Récurrence** : **faible par événement** → abonnement difficile, sauf à couvrir toute la trajectoire familiale (naissance → garde → école → ados → …) = "copilote administratif familial".
- **Monétisation** : 5–8 €/mois "tranquillité".
- **Concurrents** : mesdemarches, service-public.fr (gratuit), **AMI (État, 2026) = menace directe**, startups paperasse (expats).
- **Verdict** : **risque AMI trop élevé** sur le générique. Ne garder qu'un segment émotionnel fort et mal servi par l'État : **succession / après-décès** (démarches lourdes, 6–12 mois, gens vulnérables, notaires débordés) — mais récurrence faible → plutôt one-shot que SaaS.

### Idée G — Coach de préparation aux examens / concours FR (niche)
- **Problème** : concours (infirmier, AS, fonction publique cat. B/C, code, permis bateau, Toeic…), révisions BAC/Brevet, avec planning adaptatif + quiz espacés.
- **Récurrence** : bonne pendant la période de prépa (3–9 mois) → churn "naturel" à la réussite mais LTV correcte + flux constant de nouveaux entrants.
- **Monétisation** : 10–20 €/mois.
- **Concurrents** : Nomad Education (gratuit/pub), PrepMyFuture, Anki (gratuit), Digischool, SchoolMouv (collège/lycée). Selon niche : concurrence faible sur certains concours pro.
- **Angle FR** : programmes officiels FR.
- **Risque #1** : acquisition (SEO très concurrentiel sur "révisions BAC") → viser une niche concours pro précise où le SEO est faisable.
- **Verdict** : **candidat sérieux** si on choisit UNE niche concours à faible concurrence et forte douleur (ex. concours interne fonction publique, examens pro réglementés).

## 4. Classement provisoire

| # | Idée | Angle FR | Concurrence | Faisable solo | Récurrence | Note |
|---|------|----------|-------------|---------------|-----------|------|
| B | Assistant impôt IR + suivi annuel (angle LMNP à creuser) | ★★★ | ★★☆ (faible grand public) | ★★☆ | ★★☆ | **À creuser #1** |
| G | Coach concours/examen FR (niche pro) | ★★★ | ★★☆ (selon niche) | ★★★ | ★★☆ | **À creuser #2** |
| A | Coach budget FR sans agrégation bancaire au départ | ★★☆ | ★☆☆ | ★★☆ | ★★★ | **À creuser #3** |
| C | LMNP compta/liasse | ★★★ | ★☆☆ (saturé) | ★☆☆ | ★★★ | En réserve |
| E | Nutrition niche FR | ★★☆ | ★☆☆ | ★★★ | ★★☆ | En réserve |
| F | Copilote admin familial | ★★☆ | ★☆☆ (AMI) | ★★☆ | ★☆☆ | Écarté (AMI) |
| D | Subscription manager | ★☆☆ | ★☆☆ | ★☆☆ | ★☆☆ | Écarté |

## 5. Prochaines étapes proposées

1. **Choisir 2 idées** parmi B / G / A pour une analyse concurrentielle approfondie (screenshots, pricing réel, avis Trustpilot/stores, volumes de recherche).
2. Pour chacune : estimer le **TAM FR** (nb de foyers/candidats concernés × prix annuel × taux de capture réaliste 0,1–1 %).
3. Monter **1 landing page de test** par idée finaliste avec un mini-outil gratuit (simulateur / quiz) et mesurer le taux d'inscription email sur 2–3 semaines + 30 € d'ads pour du trafic qualifié.
4. 10–15 **interviews** utilisateurs par idée.
5. Décision Go/No-Go → MVP.

## Sources
- [15 Best Bootstrapped SaaS Niches for Solo Founders 2026 — entrepreneurloop](https://entrepreneurloop.com/bootstrapped-saas-niches-solo-founders/)
- [Best Micro SaaS Ideas for Solopreneurs 2026 — Superframeworks](https://superframeworks.com/articles/best-micro-saas-ideas-solopreneurs)
- [12 B2C Micro-SaaS Ideas Solo 2026 — GenAI Labs](https://www.genailabs.agency/blog/b2c-micro-saas-ideas-solo-founders-2026)
- [Micro-SaaS et SaaS Vertical en 2026 — Polara Studio](https://www.polarastudio.fr/blog/micro-saas-et-saas-vertical-en-2026-lancer-un-logiciel-de-niche-rentable)
- [Les meilleures idées de SaaS à lancer en 2026 — Hostinger](https://www.hostinger.com/tutorials/saas-ideas/)
- [State of Subscription Apps 2026 — RevenueCat](https://www.revenuecat.com/state-of-subscription-apps)
- [Average Subscription Churn Rate by Category 2026 — Eightx](https://eightx.co/blog/average-subscription-churn-rate-by-category)
- [From $0 to $1K MRR in 8 Months (Habit Pixel) — Indie Hackers](https://www.indiehackers.com/post/from-0-to-1k-mrr-in-8-months-bootstrapping-habit-pixel-as-a-solo-dev-684b6c056d)
- [Super-app AMI : l'État veut centraliser vos démarches — LearnUp](https://www.learnup.fr/etat-super-app-administrative-ami-demarches)
- [Paperasse AI](https://www.paperasse.ai/) · [AdminLanding](https://www.adminlanding.com/)
- [AI-driven Meal Planning Apps Market — market.us](https://market.us/report/ai-driven-meal-planning-apps-market/)
