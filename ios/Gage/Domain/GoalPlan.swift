import Foundation

/// Objectif en cours de definition : ce qu'on promet, a quel rythme, quels
/// jours, a quelle heure, et ce qu'on montrera.
///
/// Cascade stricte : changer de famille vide la declinaison et la preuve,
/// changer de declinaison vide la preuve. Sans cela l'utilisateur garderait
/// une preuve choisie pour un objectif qu'il vient de remplacer.
///
/// La promesse porte sur la semaine entiere : une seule mise couvre tous les
/// jours choisis. Le schema actuel ne sait pas encore representer ca — un
/// objectif y vaut pour un seul jour — c'est le travail de branchement qui
/// tranchera comment un plan hebdomadaire s'y projette.
struct GoalPlan: Equatable, Sendable {
    var categoryID: String?
    var variantID: String?
    var timesPerWeek: Int = 3
    var days: Set<Weekday> = []
    /// Heure retenue pour chaque jour choisi. Un jour selectionne y entre
    /// aussitot, en « le matin meme » tant que l'utilisateur n'a rien fixe.
    var times: [Weekday: DayTime] = [:]
    var proofID: String?

    // MARK: - Lecture

    var category: GoalCategory? { GoalCatalogue.category(id: categoryID) }

    var variants: [GoalVariant] { category?.variants ?? [] }

    var variant: GoalVariant? {
        guard let variantID else { return nil }
        return variants.first { $0.id == variantID }
    }

    var proofs: [ProofOption] { variant?.proofs ?? [] }

    /// Le parcours saute l'ecran de declinaison quand la famille n'en propose
    /// qu'une : elle est retenue d'office par `selectCategory`. Se lit sur le
    /// plan et non sur une valeur passee aux ecrans — une copie resterait
    /// figee sur l'etat d'avant le choix de la famille.
    var skipsVariantStep: Bool { variants.count == 1 }

    var selectedProof: ProofOption? {
        guard let proofID else { return nil }
        return proofs.first { $0.id == proofID }
    }

    /// Jours retenus, dans l'ordre de la semaine.
    var selectedDays: [Weekday] { days.sorted() }

    /// L'heure doit-elle etre arretee des maintenant ? Un reveil ne peut pas
    /// se renseigner le matin meme : l'heure y est la promesse.
    var requiresFixedTime: Bool { category?.requiresFixedTime ?? false }

    /// Moment retenu par defaut a l'ajout d'un jour : « le matin meme », sauf
    /// quand l'objectif exige une heure ferme.
    var defaultDayTime: DayTime {
        requiresFixedTime ? .fixed(hour: GoalCatalogue.defaultHour, minute: 0) : .onTheDay
    }

    func time(for day: Weekday) -> DayTime { times[day] ?? defaultDayTime }

    /// « 3 fois cette semaine ».
    var frequencyText: String { "\(timesPerWeek) fois cette semaine" }

    /// Debut de la phrase, sans le rythme : la roue le complete a l'ecran.
    var promiseText: String {
        guard let variant else { return "Je me promets" }
        return "Je me promets \(variant.promise)"
    }

    /// Promesse complete, rappelee aux ecrans suivants et a la signature.
    var sentence: String {
        guard variant != nil else { return "Objectif non défini" }
        return "\(promiseText) \(frequencyText)."
    }

    /// Libelle du defi tel qu'il apparait sur l'accueil :
    /// « Aller a la salle 5 fois cette semaine ».
    ///
    /// La promesse porte sur la semaine ; c'est elle que l'utilisateur doit
    /// lire, pas les seances qui la composent.
    var weeklyTitle: String {
        guard let variant else { return "Objectif non défini" }
        return "\(variant.action) \(timesPerWeek) fois cette semaine"
    }

    /// Rappel court, en tete des ecrans suivants.
    var shortTitle: String {
        guard let variant else { return "Objectif non défini" }
        return "\(variant.title) · \(frequencyText)"
    }

    /// Recapitulatif des jours et de leur heure, relu avant la signature.
    var scheduleText: String {
        selectedDays
            .map { "\($0.name), \(time(for: $0).shortText)" }
            .joined(separator: " · ")
    }

    /// Le plan tient-il la promesse annoncee ? On exige autant de jours que
    /// de seances promises : engager de l'argent sur « 3 fois cette semaine »
    /// en n'ayant coche que deux jours rendrait l'echec certain d'avance.
    var isScheduleComplete: Bool { days.count == timesPerWeek }

    /// Reste-t-il de la place pour cocher un jour de plus ?
    var canSelectMoreDays: Bool { days.count < timesPerWeek }

    /// Date de chaque seance promise, dans l'ordre de la semaine.
    ///
    /// Un jour qui tombe aujourd'hui compte pour aujourd'hui : quelqu'un qui
    /// s'engage lundi matin a aller a la salle le lundi parle bien de ce
    /// jour-la, pas de la semaine suivante.
    func sessions(from reference: Date = .now, calendar: Calendar = .gage) -> [(day: Weekday, date: Date)] {
        let today = calendar.startOfDay(for: reference)
        let todayWeekday = calendar.component(.weekday, from: today)

        return selectedDays.compactMap { day in
            var offset = day.calendarWeekday - todayWeekday
            if offset < 0 { offset += 7 }
            guard let date = calendar.date(byAdding: .day, value: offset, to: today) else { return nil }
            return (day, date)
        }
    }

    // MARK: - Ecriture

    /// Une famille qui n'a qu'une declinaison la retient d'office : le parcours
    /// saute alors l'ecran de declinaison, qui n'offrirait aucun choix.
    mutating func selectCategory(_ id: String) {
        guard id != categoryID else { return }
        categoryID = id
        variantID = nil
        proofID = nil
        if variants.count == 1 { variantID = variants[0].id }
    }

    mutating func selectVariant(_ id: String) {
        guard id != variantID else { return }
        variantID = id
        proofID = nil
    }

    /// Baisser le rythme retire les derniers jours de la semaine plutot que
    /// de laisser un plan qui promet moins de seances qu'il n'en programme.
    ///
    /// Promettre autant de seances qu'il y a de jours ne laisse rien a
    /// choisir : la semaine se coche alors d'elle-meme, plutot que d'exiger
    /// sept gestes dont aucun n'est une decision.
    mutating func setTimesPerWeek(_ count: Int) {
        timesPerWeek = count
        while days.count > count, let last = days.max() {
            days.remove(last)
            times[last] = nil
        }
        guard count == Weekday.allCases.count else { return }
        for day in Weekday.allCases where !days.contains(day) {
            days.insert(day)
            times[day] = defaultDayTime
        }
    }

    mutating func toggleDay(_ day: Weekday) {
        if days.contains(day) {
            days.remove(day)
            times[day] = nil
        } else if canSelectMoreDays {
            days.insert(day)
            times[day] = defaultDayTime
        }
    }

    /// « Le matin meme » est refuse quand l'objectif exige une heure ferme :
    /// la garde est ici et pas seulement dans l'ecran, pour qu'aucun chemin ne
    /// puisse enregistrer un reveil sans heure.
    mutating func setTime(_ time: DayTime, for day: Weekday) {
        guard days.contains(day) else { return }
        guard time.isFixed || !requiresFixedTime else { return }
        times[day] = time
    }
}
