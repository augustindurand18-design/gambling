import SwiftUI

/// Zone de signature manuscrite.
///
/// Le trace n'est pas un ornement : c'est le geste qui materialise le
/// consentement au debit. Il est demande a chaque engagement, jamais
/// pre-rempli et jamais rejoue depuis un engagement precedent.
struct SignaturePad: View {
    @Binding var strokes: [[CGPoint]]

    /// Vrai pendant un trace, pour distinguer le premier point d'un geste de
    /// la suite : sans ce drapeau, tous les points finiraient dans un seul
    /// trait et la levee du doigt relierait les lettres entre elles.
    @State private var isDrawing = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Theme.Colors.surface.opacity(0.55))

            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(
                    Theme.Colors.placeholderBorder,
                    style: StrokeStyle(lineWidth: 1.5, dash: [6, 5])
                )

            if strokes.isEmpty {
                Text("Signe ici pour t'engager")
                    .font(Theme.Fonts.body)
                    .foregroundStyle(Theme.Colors.inkFaded)
            }

            Canvas { context, _ in
                for stroke in strokes {
                    var path = Path()
                    path.addLines(stroke)
                    context.stroke(
                        path,
                        with: .color(Theme.Colors.signature),
                        style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round)
                    )
                }
            }
        }
        .frame(height: Theme.Metrics.signatureHeight)
        .contentShape(.rect)
        // Le trace est fait de dizaines de sous-vues sans interet : la zone
        // se presente comme un seul element, sinon elle n'est annoncee nulle
        // part et reste introuvable pour qui n'y voit pas le pointille.
        .accessibilityElement()
        .accessibilityIdentifier("signature-pad")
        .accessibilityLabel("Zone de signature")
        .accessibilityValue(strokes.isEmpty ? "vide" : "signée")
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in
                    if isDrawing, !strokes.isEmpty {
                        strokes[strokes.count - 1].append(value.location)
                    } else {
                        isDrawing = true
                        // Deux fois le meme point : un simple appui laisse
                        // ainsi une marque ronde au lieu de rien du tout.
                        strokes.append([value.location, value.location])
                    }
                }
                .onEnded { _ in isDrawing = false }
        )
        .overlay(alignment: .bottomTrailing) {
            if !strokes.isEmpty {
                Button("Effacer") { strokes.removeAll() }
                    .font(Theme.Fonts.footnote)
                    .foregroundStyle(Theme.Colors.inkMuted)
                    .padding(10)
            }
        }
    }
}

#Preview {
    @Previewable @State var strokes: [[CGPoint]] = []
    ScreenBackground(glow: .topTrailing) {
        SignaturePad(strokes: $strokes)
            .padding(.horizontal, Theme.Spacing.screenHorizontal)
    }
}
