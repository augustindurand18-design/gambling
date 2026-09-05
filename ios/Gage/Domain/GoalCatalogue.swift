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

/// Declinaison d'une famille : ce que l'utilisateur va reellement faire.
struct GoalVariant: Identifiable, Hashable, Sendable {
    let id: String
    /// Libelle de la carte du sous-menu.
    let title: String
    /// Fragment infinitif insere dans « Je me promets … », elision comprise
    /// (« d'aller » et non « de aller »).
    let promise: String
    let proofs: [ProofOption]

    /// La meme action, sans la preposition et en tete de phrase :
    /// « d'aller a la salle » donne « Aller a la salle ».
    ///
    /// Derive plutot que saisi une seconde fois : deux champs a maintenir
    /// finiraient par se contredire, et c'est le libelle que l'utilisateur
    /// lit sur son accueil.
    var action: String {
        let stripped = if promise.hasPrefix("d'") {
            String(promise.dropFirst(2))
        } else if promise.hasPrefix("de ") {
            String(promise.dropFirst(3))
        } else {
            promise
        }
        return stripped.prefix(1).uppercased() + stripped.dropFirst()
    }
}

/// Famille d'objectifs, telle qu'elle apparait dans la liste generique.
struct GoalCategory: Identifiable, Hashable, Sendable {
    let id: String
    let title: String
    /// Question posee en tete du sous-menu.
    let question: String
    let variants: [GoalVariant]
}

/// Jour de la semaine, lundi en premier comme dans un calendrier francais.
enum Weekday: Int, CaseIterable, Identifiable, Hashable, Sendable, Comparable {
    case monday = 1, tuesday, wednesday, thursday, friday, saturday, sunday

    var id: Int { rawValue }

    /// Initiale affichee dans le calendrier. Mardi et mercredi partagent la
    /// leur : c'est l'usage, et le nom complet reste lisible aux lecteurs
    /// d'ecran.
    var initial: String {
        switch self {
        case .monday: "L"
        case .tuesday, .wednesday: "M"
        case .thursday: "J"
        case .friday: "V"
        case .saturday: "S"
        case .sunday: "D"
        }
    }

    var name: String {
        switch self {
        case .monday: "Lundi"
        case .tuesday: "Mardi"
        case .wednesday: "Mercredi"
        case .thursday: "Jeudi"
        case .friday: "Vendredi"
        case .saturday: "Samedi"
        case .sunday: "Dimanche"
        }
    }

    /// Numerotation de `Calendar`, ou la semaine commence le dimanche.
    var calendarWeekday: Int { self == .sunday ? 1 : rawValue + 1 }

    static func < (lhs: Weekday, rhs: Weekday) -> Bool { lhs.rawValue < rhs.rawValue }
}

/// Moment de la journee retenu pour un jour donne.
enum DayTime: Hashable, Sendable {
    /// L'heure sera donnee le matin meme. Utile quand l'utilisateur ne sait
    /// pas encore a quelle heure il ira ; le creneau ne peut plus etre fixe
    /// une fois la journee entamee.
    case onTheDay
    /// Heure connue des maintenant.
    case fixed(hour: Int, minute: Int)

    var isFixed: Bool {
        if case .fixed = self { return true }
        return false
    }

    var hour: Int {
        if case let .fixed(hour, _) = self { return hour }
        return GoalCatalogue.defaultHour
    }

    var minute: Int {
        if case let .fixed(_, minute) = self { return minute }
        return 0
    }

    /// « 7 h 00 », a la francaise.
    var text: String {
        switch self {
        case .onTheDay: "À renseigner le matin même"
        case let .fixed(hour, minute): "\(hour) h \(String(format: "%02d", minute))"
        }
    }

    /// Version compacte, pour le recapitulatif de la semaine.
    var shortText: String {
        switch self {
        case .onTheDay: "heure le matin"
        case .fixed: text
        }
    }
}

/// Catalogue des objectifs proposes.
///
/// Embarque pour l'instant. Il passera cote serveur le jour ou la liste devra
/// evoluer sans mise a jour de l'app — les identifiants sont deja stables
/// pour que les objectifs deja engages restent lisibles apres un changement
/// de libelle.
enum GoalCatalogue {

    static let defaultHour = 7
    static let hours: [Int] = Array(0..<24)
    /// Minutes par pas de cinq : assez fin pour un reveil, assez grossier
    /// pour que la roue reste parcourable d'un geste.
    static let minutes: [Int] = Array(stride(from: 0, to: 60, by: 5))
    /// Une semaine entiere au maximum : au-dela, la promesse ne serait plus
    /// hebdomadaire.
    static let frequencies: [Int] = Array(1...7)

    static let categories: [GoalCategory] = [
        GoalCategory(id: "wake-up", title: "Me réveiller", question: "Tu te lèves pour quoi ?", variants: [
            GoalVariant(id: "plain", title: "Juste me lever", promise: "de me lever", proofs: [
                ProofOption(id: "selfie", title: "Selfie du matin",
                            subtitle: "Ton visage, à l'heure dite", symbol: "face.smiling"),
                ProofOption(id: "bed", title: "Photo du lit fait",
                            subtitle: "Prouve que tu as quitté le lit", symbol: "bed.double"),
                ProofOption(id: "outside", title: "Photo de l'extérieur",
                            subtitle: "Prouve que tu es sorti de chez toi", symbol: "mappin.and.ellipse")
            ]),
            GoalVariant(id: "breakfast", title: "Me lever et petit-déjeuner",
                        promise: "de me lever et de prendre un petit-déjeuner", proofs: [
                ProofOption(id: "table", title: "Photo du petit-déjeuner",
                            subtitle: "Montre le repas servi", symbol: "fork.knife"),
                ProofOption(id: "kitchen", title: "Photo de la cuisine",
                            subtitle: "Situe le repas chez toi", symbol: "photo"),
                ProofOption(id: "selfie", title: "Selfie à table",
                            subtitle: "Ton visage, devant l'assiette", symbol: "face.smiling")
            ]),
            GoalVariant(id: "out", title: "Me lever et sortir",
                        promise: "de me lever et de sortir de chez moi", proofs: [
                ProofOption(id: "street", title: "Photo de la rue",
                            subtitle: "Prouve que tu es dehors", symbol: "mappin.and.ellipse"),
                ProofOption(id: "shoes", title: "Photo de tes chaussures aux pieds",
                            subtitle: "Montre que tu es habillé", symbol: "bag"),
                ProofOption(id: "selfie", title: "Selfie dehors",
                            subtitle: "Ton visage, à l'air libre", symbol: "face.smiling")
            ])
        ]),

        GoalCategory(id: "sport", title: "Faire du sport", question: "Quel sport ?", variants: [
            GoalVariant(id: "gym", title: "La salle", promise: "d'aller à la salle", proofs: [
                ProofOption(id: "onsite", title: "Photo sur place",
                            subtitle: "Confirme que tu es bien à la salle", symbol: "mappin.and.ellipse"),
                ProofOption(id: "machine", title: "Photo de la machine utilisée",
                            subtitle: "Prouve que la séance a eu lieu", symbol: "photo"),
                ProofOption(id: "bag", title: "Photo de ton sac ouvert",
                            subtitle: "Montre que tu as pris ta tenue", symbol: "bag")
            ]),
            GoalVariant(id: "football", title: "Le foot", promise: "d'aller au foot", proofs: [
                ProofOption(id: "pitch", title: "Photo du terrain",
                            subtitle: "Situe le match ou l'entraînement", symbol: "mappin.and.ellipse"),
                ProofOption(id: "boots", title: "Photo de tes crampons aux pieds",
                            subtitle: "Montre que tu es en tenue", symbol: "bag"),
                ProofOption(id: "selfie", title: "Selfie après le match",
                            subtitle: "Ton visage, au coup de sifflet final", symbol: "face.smiling")
            ]),
            GoalVariant(id: "run", title: "La course", promise: "d'aller courir", proofs: [
                ProofOption(id: "route", title: "Photo de ton parcours",
                            subtitle: "Situe la course en extérieur", symbol: "mappin.and.ellipse"),
                ProofOption(id: "shoes", title: "Photo de tes chaussures aux pieds",
                            subtitle: "Montre que tu es en tenue", symbol: "bag"),
                ProofOption(id: "selfie", title: "Selfie après l'effort",
                            subtitle: "Ton visage, à l'arrivée", symbol: "face.smiling")
            ]),
            GoalVariant(id: "pool", title: "La piscine", promise: "d'aller à la piscine", proofs: [
                ProofOption(id: "basin", title: "Photo du bassin",
                            subtitle: "Confirme que tu es sur place", symbol: "mappin.and.ellipse"),
                ProofOption(id: "gear", title: "Photo du bonnet et des lunettes",
                            subtitle: "Montre que tu es équipé", symbol: "bag"),
                ProofOption(id: "selfie", title: "Selfie cheveux mouillés",
                            subtitle: "Prouve que tu es entré dans l'eau", symbol: "face.smiling")
            ]),
            GoalVariant(id: "bike", title: "Le vélo", promise: "de faire du vélo", proofs: [
                ProofOption(id: "bike", title: "Photo du vélo sorti",
                            subtitle: "Montre la machine prête ou revenue", symbol: "photo"),
                ProofOption(id: "road", title: "Photo de la route",
                            subtitle: "Situe la sortie en extérieur", symbol: "mappin.and.ellipse"),
                ProofOption(id: "selfie", title: "Selfie casque sur la tête",
                            subtitle: "Ton visage, en tenue", symbol: "face.smiling")
            ])
        ]),

        GoalCategory(id: "tidy", title: "Ranger chez moi", question: "Tu ranges quoi ?", variants: [
            GoalVariant(id: "bed", title: "Mon lit", promise: "de faire mon lit", proofs: [
                ProofOption(id: "made", title: "Photo du lit fait",
                            subtitle: "Montre le résultat, draps tirés", symbol: "bed.double"),
                ProofOption(id: "room", title: "Photo de la chambre entière",
                            subtitle: "Situe le lit dans la pièce", symbol: "photo"),
                ProofOption(id: "pillows", title: "Photo des oreillers en place",
                            subtitle: "Confirme le détail fini", symbol: "bag")
            ]),
            GoalVariant(id: "desk", title: "Mon bureau", promise: "de ranger mon bureau", proofs: [
                ProofOption(id: "surface", title: "Photo du plan de travail",
                            subtitle: "Montre la surface dégagée", symbol: "photo"),
                ProofOption(id: "tidy", title: "Photo des affaires rangées",
                            subtitle: "Confirme que rien ne traîne", symbol: "bag"),
                ProofOption(id: "doorway", title: "Photo de la pièce depuis la porte",
                            subtitle: "Situe le bureau rangé", symbol: "mappin.and.ellipse")
            ]),
            GoalVariant(id: "cleaning", title: "Le ménage", promise: "de faire le ménage", proofs: [
                ProofOption(id: "room", title: "Photo de la pièce rangée",
                            subtitle: "Montre le résultat d'ensemble", symbol: "photo"),
                ProofOption(id: "floor", title: "Photo du sol et de l'aspirateur",
                            subtitle: "Confirme le passage effectué", symbol: "bag"),
                ProofOption(id: "bins", title: "Photo des poubelles sorties",
                            subtitle: "Prouve la dernière étape", symbol: "mappin.and.ellipse")
            ])
        ]),

        GoalCategory(id: "work", title: "M'y mettre", question: "T'y mettre à quoi ?", variants: [
            GoalVariant(id: "office", title: "Aller au travail", promise: "d'aller au travail", proofs: [
                ProofOption(id: "desk", title: "Photo de ton poste",
                            subtitle: "Prouve que tu es installé", symbol: "photo"),
                ProofOption(id: "entrance", title: "Photo de l'entrée du bâtiment",
                            subtitle: "Situe ton arrivée sur place", symbol: "mappin.and.ellipse"),
                ProofOption(id: "badge", title: "Photo de ton badge en main",
                            subtitle: "Montre l'accès validé", symbol: "bag")
            ]),
            GoalVariant(id: "homework", title: "Mes devoirs", promise: "de faire mes devoirs", proofs: [
                ProofOption(id: "pages", title: "Photo du travail terminé",
                            subtitle: "Montre les pages remplies", symbol: "photo"),
                ProofOption(id: "closed", title: "Photo du cahier fermé sur la table",
                            subtitle: "Confirme la séance finie", symbol: "bag"),
                ProofOption(id: "selfie", title: "Selfie au bureau",
                            subtitle: "Ton visage, au poste de travail", symbol: "face.smiling")
            ]),
            GoalVariant(id: "study", title: "Réviser", promise: "de réviser", proofs: [
                ProofOption(id: "notes", title: "Photo de tes fiches",
                            subtitle: "Montre le travail produit", symbol: "photo"),
                ProofOption(id: "desk", title: "Photo du bureau en séance",
                            subtitle: "Situe la session de révision", symbol: "mappin.and.ellipse"),
                ProofOption(id: "selfie", title: "Selfie en révision",
                            subtitle: "Ton visage, au travail", symbol: "face.smiling")
            ])
        ])
    ]

    static func category(id: String?) -> GoalCategory? {
        guard let id else { return nil }
        return categories.first { $0.id == id }
    }
}
