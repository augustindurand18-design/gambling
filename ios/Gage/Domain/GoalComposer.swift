import Foundation

/// Preuve photo acceptee pour un objectif donne.
///
/// L'utilisateur ne regle rien de technique : il choisit ce qu'il accepte de
/// montrer. Toutes les preuves proposees pour un objectif se valent aux yeux
/// de la verification.
struct ProofOption: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    let subtitle: String
    /// Symbole SF affiche a gauche de la carte.
    let symbol: String
}

/// Deuxieme segment de la phrase : ce que l'on va faire.
struct GoalComplement: Identifiable, Hashable, Sendable {
    let id: String
    /// Segment affiche dans la roue.
    let label: String
    /// Ce que le segment ajoute a la phrase. `nil` quand la roue n'affiche
    /// qu'un mot de liaison deja porte par le fragment horaire (« a 7 h 00 »).
    let phrase: String?
    let proofs: [ProofOption]
}

/// Premier segment de la phrase : le verbe.
struct GoalVerb: Identifiable, Hashable, Sendable {
    let id: String
    /// Segment affiche dans la roue.
    let label: String
    /// Fragment infinitif insere dans « Je me promets … », elision comprise
    /// (« d'aller » et non « de aller »). `nil` marque le cran neutre : tant
    /// que la roue n'a pas bouge, aucun objectif n'est compose.
    let promise: String?
    let complements: [GoalComplement]

    var isChosen: Bool { promise != nil }
}

/// Catalogue des objectifs composables.
///
/// Embarque pour l'instant. Il passera cote serveur le jour ou la liste devra
/// evoluer sans mise a jour de l'app — les identifiants sont deja stables
/// pour que les objectifs deja engages restent lisibles apres un changement
/// de libelle.
enum GoalCatalogue {

    static let hours: [Int] = Array(0..<24)
    /// Minutes par pas de cinq : assez fin pour un reveil, assez grossier
    /// pour que la roue reste parcourable d'un geste.
    static let minutes: [Int] = Array(stride(from: 0, to: 60, by: 5))

    static let verbs: [GoalVerb] = [
        GoalVerb(id: "none", label: "—", promise: nil, complements: [neutral]),

        GoalVerb(id: "wake-up", label: "Me lever", promise: "de me lever", complements: [
            GoalComplement(id: "plain", label: "à", phrase: nil, proofs: [
                ProofOption(id: "outside", title: "Photo de l'extérieur",
                            subtitle: "Prouve que tu es sorti de chez toi", symbol: "mappin.and.ellipse"),
                ProofOption(id: "breakfast", title: "Photo du petit-déjeuner",
                            subtitle: "Prouve que tu es debout et actif", symbol: "fork.knife"),
                ProofOption(id: "bed", title: "Photo du lit fait",
                            subtitle: "Prouve que tu as quitté le lit", symbol: "bed.double"),
                ProofOption(id: "selfie", title: "Selfie du matin",
                            subtitle: "Ton visage, à l'heure dite", symbol: "face.smiling")
            ])
        ]),

        GoalVerb(id: "go", label: "Aller", promise: "d'aller", complements: [
            GoalComplement(id: "gym", label: "à la salle", phrase: "à la salle", proofs: [
                ProofOption(id: "onsite", title: "Photo sur place",
                            subtitle: "Confirme que tu es bien à la salle", symbol: "mappin.and.ellipse"),
                ProofOption(id: "bag", title: "Photo de ton sac ouvert",
                            subtitle: "Montre que tu as pris ta tenue", symbol: "bag"),
                ProofOption(id: "machine", title: "Photo de la machine utilisée",
                            subtitle: "Prouve que la séance a eu lieu", symbol: "photo")
            ]),
            GoalComplement(id: "run", label: "courir dehors", phrase: "courir dehors", proofs: [
                ProofOption(id: "route", title: "Photo de ton parcours",
                            subtitle: "Situe la course en extérieur", symbol: "mappin.and.ellipse"),
                ProofOption(id: "shoes", title: "Photo de tes chaussures aux pieds",
                            subtitle: "Montre que tu es en tenue", symbol: "bag"),
                ProofOption(id: "selfie", title: "Selfie après l'effort",
                            subtitle: "Ton visage, à l'arrivée", symbol: "face.smiling")
            ]),
            GoalComplement(id: "work", label: "au travail", phrase: "au travail", proofs: [
                ProofOption(id: "desk", title: "Photo de ton poste",
                            subtitle: "Prouve que tu es installé", symbol: "photo"),
                ProofOption(id: "entrance", title: "Photo de l'entrée du bâtiment",
                            subtitle: "Situe ton arrivée sur place", symbol: "mappin.and.ellipse"),
                ProofOption(id: "badge", title: "Photo de ton badge en main",
                            subtitle: "Montre l'accès validé", symbol: "bag")
            ]),
            GoalComplement(id: "pool", label: "à la piscine", phrase: "à la piscine", proofs: [
                ProofOption(id: "basin", title: "Photo du bassin",
                            subtitle: "Confirme que tu es sur place", symbol: "mappin.and.ellipse"),
                ProofOption(id: "gear", title: "Photo du bonnet et des lunettes",
                            subtitle: "Montre que tu es équipé", symbol: "bag"),
                ProofOption(id: "selfie", title: "Selfie cheveux mouillés",
                            subtitle: "Prouve que tu es entré dans l'eau", symbol: "face.smiling")
            ]),
            GoalComplement(id: "physio", label: "chez le kiné", phrase: "chez le kiné", proofs: [
                ProofOption(id: "waiting", title: "Photo de la salle d'attente",
                            subtitle: "Situe ta présence au cabinet", symbol: "mappin.and.ellipse"),
                ProofOption(id: "sheet", title: "Photo de la feuille de séance",
                            subtitle: "Confirme le rendez-vous honoré", symbol: "photo"),
                ProofOption(id: "selfie", title: "Selfie sur place",
                            subtitle: "Ton visage, au cabinet", symbol: "face.smiling")
            ])
        ]),

        GoalVerb(id: "do", label: "Faire", promise: "de faire", complements: [
            GoalComplement(id: "bed", label: "mon lit", phrase: "mon lit", proofs: [
                ProofOption(id: "made", title: "Photo du lit fait",
                            subtitle: "Montre le résultat, draps tirés", symbol: "bed.double"),
                ProofOption(id: "room", title: "Photo de la chambre entière",
                            subtitle: "Situe le lit dans la pièce", symbol: "photo"),
                ProofOption(id: "pillows", title: "Photo des oreillers en place",
                            subtitle: "Confirme le détail fini", symbol: "bag")
            ]),
            GoalComplement(id: "desk", label: "mon bureau", phrase: "mon bureau", proofs: [
                ProofOption(id: "surface", title: "Photo du plan de travail",
                            subtitle: "Montre la surface dégagée", symbol: "photo"),
                ProofOption(id: "tidy", title: "Photo des affaires rangées",
                            subtitle: "Confirme que rien ne traîne", symbol: "bag"),
                ProofOption(id: "doorway", title: "Photo de la pièce depuis la porte",
                            subtitle: "Situe le bureau rangé", symbol: "mappin.and.ellipse")
            ]),
            GoalComplement(id: "homework", label: "mes devoirs", phrase: "mes devoirs", proofs: [
                ProofOption(id: "pages", title: "Photo du travail terminé",
                            subtitle: "Montre les pages remplies", symbol: "photo"),
                ProofOption(id: "closed", title: "Photo du cahier fermé sur la table",
                            subtitle: "Confirme la séance finie", symbol: "bag"),
                ProofOption(id: "selfie", title: "Selfie au bureau",
                            subtitle: "Ton visage, au poste de travail", symbol: "face.smiling")
            ]),
            GoalComplement(id: "sport", label: "du sport", phrase: "du sport", proofs: [
                ProofOption(id: "selfie", title: "Selfie en tenue",
                            subtitle: "Ton visage, après la séance", symbol: "face.smiling"),
                ProofOption(id: "gear", title: "Photo du matériel utilisé",
                            subtitle: "Montre l'effort réellement fait", symbol: "bag"),
                ProofOption(id: "place", title: "Photo du lieu d'entraînement",
                            subtitle: "Situe la séance", symbol: "mappin.and.ellipse")
            ]),
            GoalComplement(id: "cleaning", label: "le ménage", phrase: "le ménage", proofs: [
                ProofOption(id: "room", title: "Photo de la pièce rangée",
                            subtitle: "Montre le résultat d'ensemble", symbol: "photo"),
                ProofOption(id: "floor", title: "Photo du sol et de l'aspirateur",
                            subtitle: "Confirme le passage effectué", symbol: "bag"),
                ProofOption(id: "bins", title: "Photo des poubelles sorties",
                            subtitle: "Prouve la dernière étape", symbol: "mappin.and.ellipse")
            ])
        ])
    ]

    /// Complement du cran neutre : la roue du milieu doit rester peuplee tant
    /// qu'aucun verbe n'est choisi, sinon elle se vide et saute a l'ecran.
    private static let neutral = GoalComplement(id: "none", label: "—", phrase: nil, proofs: [])
}

/// Objectif en cours de composition.
///
/// Cascade stricte : changer le verbe vide le complement et la preuve,
/// changer le complement vide la preuve. Sans cela l'utilisateur garderait
/// une preuve choisie pour un objectif qu'il vient de remplacer.
struct GoalComposition: Equatable, Sendable {
    var verbIndex: Int = 0
    var complementIndex: Int = 0
    var hour: Int = 7
    var minute: Int = 0
    var proofID: String?

    // MARK: - Lecture

    var verb: GoalVerb {
        GoalCatalogue.verbs[min(max(verbIndex, 0), GoalCatalogue.verbs.count - 1)]
    }

    var complements: [GoalComplement] { verb.complements }

    var complement: GoalComplement {
        complements[min(max(complementIndex, 0), complements.count - 1)]
    }

    /// Un verbe a-t-il ete choisi ? Tant que non, rien n'est engageable.
    var isGoalChosen: Bool { verb.isChosen }

    var proofs: [ProofOption] { complement.proofs }

    var selectedProof: ProofOption? {
        guard let proofID else { return nil }
        return proofs.first { $0.id == proofID }
    }

    /// « 7 h 00 », a la francaise.
    var timeText: String { "\(hour) h \(String(format: "%02d", minute))" }

    /// Promesse affichee a l'ecran de composition et rappelee a l'engagement.
    var sentence: String {
        guard let promise = verb.promise else {
            return "Fais tourner pour composer ton objectif."
        }
        return "Je me promets \(promise)\(complementFragment) à \(timeText)."
    }

    /// Rappel court, en tete des ecrans suivants.
    var shortTitle: String {
        guard isGoalChosen else { return "Objectif non composé" }
        return "\(verb.label)\(complementFragment) à \(timeText)"
    }

    private var complementFragment: String {
        complement.phrase.map { " \($0)" } ?? ""
    }

    // MARK: - Ecriture

    mutating func selectVerb(_ index: Int) {
        guard index != verbIndex else { return }
        verbIndex = index
        complementIndex = 0
        proofID = nil
    }

    mutating func selectComplement(_ index: Int) {
        guard index != complementIndex else { return }
        complementIndex = index
        proofID = nil
    }
}
