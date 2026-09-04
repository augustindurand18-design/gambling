import SwiftUI

/// Jetons de design partages par tous les ecrans : couleurs, degrades,
/// typographie et rythme d'espacement, releves sur les maquettes.
///
/// Regle : aucune vue n'ecrit une valeur brute (couleur, taille, marge).
/// Tout passe par `Theme` pour qu'un changement de maquette se repercute
/// en un seul endroit.
enum Theme {

    // MARK: - Couleurs

    enum Colors {
        /// Texte principal, bleu nuit des titres.
        static let ink = Color(hex: 0x141B3C)
        /// Texte secondaire, gris des mentions sous les boutons.
        static let inkMuted = Color(hex: 0x9AA0A6)
        /// Gris clair des valeurs non selectionnees (roue de montants).
        static let inkFaded = Color(hex: 0xB6BCC3)
        /// Violet de marque : pastille du logo et liens.
        static let brand = Color(hex: 0x4630D8)
        /// Bleu de fin du degrade des boutons.
        static let brandAccent = Color(hex: 0x3E7BD6)
        /// Surfaces posees sur le fond degrade (carte du logo, cartes d'ecran).
        static let surface = Color(hex: 0xFBFCFE)
        /// Fond des cartes de choix.
        static let card = Color.white
        /// Contour pointille des emplacements vides.
        static let placeholderBorder = Color(hex: 0xC3CBD2)
        /// Texte pose sur une surface de marque.
        static let onBrand = Color.white
        /// Contour des elements selectionnes.
        static let selectionBorder = Color(hex: 0xAFC2EE)
        /// Points de progression inactifs.
        static let dotInactive = Color(hex: 0xCBD2D9)
        /// Halo cyan decoratif du fond.
        static let glow = Color(hex: 0x56B4E8)
    }

    // MARK: - Degrades

    enum Gradients {
        /// Fond d'ecran des pages d'accueil et d'onboarding :
        /// lavande en haut, menthe au milieu, creme en bas.
        static let background = LinearGradient(
            stops: [
                .init(color: Color(hex: 0xEFF1FD), location: 0.00),
                .init(color: Color(hex: 0xE9F5EE), location: 0.45),
                .init(color: Color(hex: 0xFCFAE9), location: 1.00)
            ],
            startPoint: .top,
            endPoint: .bottom
        )

        /// Remplissage des boutons principaux : violet vers bleu.
        static let brand = LinearGradient(
            colors: [Color(hex: 0x3A2BC9), Colors.brandAccent],
            startPoint: .leading,
            endPoint: .trailing
        )
    }

    // MARK: - Typographie

    /// La maquette utilise une grotesque geometrique arrondie ; `.rounded`
    /// est l'equivalent systeme, sans embarquer de fonte tierce.
    enum Fonts {
        static let display = Font.system(size: 34, weight: .bold, design: .rounded)
        static let title = Font.system(size: 28, weight: .bold, design: .rounded)
        static let body = Font.system(size: 15, weight: .regular, design: .rounded)
        static let cardTitle = Font.system(size: 16, weight: .semibold, design: .rounded)
        /// Montant selectionne dans la roue de mise.
        static let amount = Font.system(size: 48, weight: .bold, design: .rounded)
        /// Montants voisins, non selectionnes.
        static let amountMuted = Font.system(size: 36, weight: .bold, design: .rounded)
        static let button = Font.system(size: 19, weight: .semibold, design: .rounded)
        static let footnote = Font.system(size: 15, weight: .medium, design: .rounded)
        static let footnoteEmphasis = Font.system(size: 15, weight: .bold, design: .rounded)
    }

    // MARK: - Mesures

    enum Metrics {
        static let cardHeight: CGFloat = 58
        static let cardRadius: CGFloat = 16
    }

    // MARK: - Espacement

    enum Spacing {
        /// Marge laterale de tous les ecrans.
        static let screenHorizontal: CGFloat = 24
        static let small: CGFloat = 8
        static let medium: CGFloat = 20
        static let large: CGFloat = 36
        /// Marge haute des ecrans d'onboarding, sous les points de progression.
        static let screenTop: CGFloat = 28
        /// Remontee du contenu centre pour retrouver le centre optique
        /// (le vide sous le bloc est plus grand que celui du dessus).
        static let opticalLift: CGFloat = 88
    }
}

extension Color {
    /// Construit une couleur depuis un litteral hexadecimal `0xRRGGBB`,
    /// pour coller aux valeurs relevees dans Figma.
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}
