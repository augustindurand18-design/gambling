import SwiftUI

/// Les sept jours de la semaine, a cocher.
///
/// Un jour deja coche reste toujours decochable ; les autres se ferment des
/// que le quota de seances promises est atteint, plutot que d'accepter un
/// huitieme jour qui contredirait la promesse.
struct WeekCalendar: View {
    let selected: Set<Weekday>
    let canSelectMore: Bool
    let onToggle: (Weekday) -> Void

    var body: some View {
        HStack(spacing: 7) {
            ForEach(Weekday.allCases) { day in
                dayButton(day)
            }
        }
    }

    private func dayButton(_ day: Weekday) -> some View {
        let isOn = selected.contains(day)
        let isOpen = isOn || canSelectMore

        return Button {
            onToggle(day)
        } label: {
            Text(day.initial)
                .font(Theme.Fonts.cardTitle)
                .foregroundStyle(foreground(isOn: isOn, isOpen: isOpen))
                .frame(maxWidth: .infinity)
                .frame(height: 46)
                .background {
                    if isOn {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Theme.Gradients.brand)
                    } else {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(Theme.Colors.card.opacity(isOpen ? 1 : 0.5))
                    }
                }
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .disabled(!isOpen)
        .animation(.easeOut(duration: 0.2), value: isOn)
        .accessibilityIdentifier("day-\(day.rawValue)")
        .accessibilityLabel(day.name)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }

    private func foreground(isOn: Bool, isOpen: Bool) -> Color {
        if isOn { return Theme.Colors.onBrand }
        return isOpen ? Theme.Colors.ink : Theme.Colors.inkFaded
    }
}

#Preview {
    ScreenBackground(glow: .topTrailing) {
        WeekCalendar(selected: [.monday, .thursday], canSelectMore: true) { _ in }
            .padding(.horizontal, Theme.Spacing.screenHorizontal)
    }
}
