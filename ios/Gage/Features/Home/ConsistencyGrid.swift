import SwiftUI

/// Grille de regularite : une colonne par semaine, une ligne par jour.
///
/// La lecture visee est celle d'un coup d'oeil sur plusieurs semaines, pas
/// celle d'une date precise — c'est pourquoi les cases n'ont pas de numero.
struct ConsistencyGrid: View {
    let calendar: ConsistencyCalendar

    private let cell: CGFloat = 20
    private let spacing: CGFloat = 4
    private static let weekdayInitials = ["L", "M", "M", "J", "V", "S", "D"]

    var body: some View {
        HStack(alignment: .top, spacing: spacing) {
            VStack(spacing: spacing) {
                ForEach(Array(Self.weekdayInitials.enumerated()), id: \.offset) { _, initial in
                    Text(initial)
                        .font(Theme.Fonts.calendarLegend)
                        .foregroundStyle(Theme.Colors.inkMuted)
                        .frame(width: 12, height: cell)
                }
            }

            // Les semaines defilent : douze colonnes ne tiennent pas toujours
            // dans la largeur, et rogner la grille cacherait le passe recent
            // plutot que l'ancien.
            ScrollView(.horizontal) {
                HStack(spacing: spacing) {
                    ForEach(Array(calendar.weeks.enumerated()), id: \.offset) { _, week in
                        VStack(spacing: spacing) {
                            ForEach(week) { day in
                                cellView(day)
                            }
                        }
                    }
                }
                .padding(.trailing, 2)
            }
            .scrollIndicators(.hidden)
            .defaultScrollAnchor(.trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Régularité des douze dernières semaines")
        .accessibilityValue("\(calendar.keptCount) jours tenus, \(calendar.failedCount) non tenus")
    }

    private func cellView(_ day: ConsistencyDay) -> some View {
        RoundedRectangle(cornerRadius: 5, style: .continuous)
            .fill(fill(for: day))
            .frame(width: cell, height: cell)
    }

    private func fill(for day: ConsistencyDay) -> Color {
        if day.isFuture { return Theme.Colors.calendarEmpty.opacity(0.4) }
        switch day.outcome {
        case .kept: return Theme.Colors.kept
        case .failed: return Theme.Colors.failed
        case .pending: return Theme.Colors.attention.opacity(0.45)
        case .none: return Theme.Colors.calendarEmpty
        }
    }
}

/// Legende de la grille : sans elle, les couleurs ne veulent rien dire.
struct ConsistencyLegend: View {
    var body: some View {
        HStack(spacing: Theme.Spacing.medium - 6) {
            item(Theme.Colors.kept, "Tenu")
            item(Theme.Colors.failed, "Manqué")
            item(Theme.Colors.calendarEmpty, "Rien")
        }
        .font(Theme.Fonts.calendarLegend)
        .foregroundStyle(Theme.Colors.inkMuted)
    }

    private func item(_ color: Color, _ label: String) -> some View {
        HStack(spacing: 5) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(color)
                .frame(width: 10, height: 10)
            Text(label)
        }
    }
}

#Preview {
    ScreenBackground(glow: .topTrailing) {
        VStack(alignment: .leading, spacing: Theme.Spacing.medium) {
            ConsistencyGrid(calendar: HomeSnapshot.sample.calendar)
            ConsistencyLegend()
        }
        .padding(.horizontal, Theme.Spacing.screenHorizontal)
    }
}
