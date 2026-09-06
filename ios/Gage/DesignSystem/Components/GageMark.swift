import SwiftUI

/// Le trace de la marque : un G ouvert a droite dont la longue branche de la
/// coche s'aplatit en barre, d'un seul geste.
///
/// Le trace vit ici et dans l'icone de l'application
/// (`Resources/Assets.xcassets/AppIcon.appiconset`), qui est un PNG et ne peut
/// donc pas partager ce code. Toute retouche du dessin doit etre reportee des
/// deux cotes ; rien ne detecte une divergence.
///
/// Dessine sur une grille de 100, centre en (50, 52), rayon 38. La forme est
/// centree dans le rectangle qu'on lui donne et reste carree : elle ne
/// s'etire jamais.
struct GageMark: Shape {

    /// Epaisseur du trait, en fraction du cote. En dessous de 9 %, la coche se
    /// referme sur elle-meme des que l'icone descend a 60 points.
    static let strokeRatio: CGFloat = 0.09

    func path(in rect: CGRect) -> Path {
        let side = min(rect.width, rect.height)
        let unit = side / 100
        let originX = rect.minX + (rect.width - side) / 2
        let originY = rect.minY + (rect.height - side) / 2
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: originX + x * unit, y: originY + y * unit)
        }

        var path = Path()
        // L'anneau du G, ouvert entre les deux terminaux de droite.
        path.addArc(
            center: point(50, 52),
            radius: 38 * unit,
            startAngle: .degrees(42.88),
            endAngle: .degrees(317.12),
            clockwise: false
        )
        // La coche, logee dans le contre-poincon, qui finit en barre du G.
        path.move(to: point(44, 58))
        path.addLine(to: point(57, 71))
        path.addLine(to: point(76, 52))
        path.addLine(to: point(88, 52))
        return path
    }

    /// Style de trait a appliquer pour un cote donne.
    static func stroke(for side: CGFloat) -> StrokeStyle {
        StrokeStyle(lineWidth: side * strokeRatio, lineCap: .round, lineJoin: .round)
    }
}

#Preview {
    ScreenBackground {
        VStack(spacing: 32) {
            GageMark()
                .stroke(Theme.Gradients.brand, style: GageMark.stroke(for: 160))
                .frame(width: 160, height: 160)
            HStack(spacing: 24) {
                AppMark(size: 88)
                AppMark(size: 64)
                AppMark(size: 44)
            }
        }
    }
}
