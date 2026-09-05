import SwiftUI

/// Heure et minutes cote a cote, dans un seul cadre de selection.
///
/// Les deux roues partagent le cadre : separees, elles se liraient comme deux
/// reglages independants au lieu d'une heure.
struct TimeWheels: View {
    @Binding var hour: Int
    @Binding var minute: Int

    var body: some View {
        ZStack {
            WheelSelectionBand(height: Theme.Metrics.wheelRow - Theme.Metrics.wheelBandInset)

            HStack(spacing: 6) {
                Wheel(
                    values: GoalCatalogue.hours,
                    selection: $hour,
                    label: { String(format: "%02d", $0) },
                    alignment: .trailing,
                    showsBand: false
                )
                .frame(width: 92)
                .accessibilityLabel("Heure")

                Text(":")
                    .font(Theme.Fonts.option)
                    .foregroundStyle(Theme.Colors.ink)

                Wheel(
                    values: GoalCatalogue.minutes,
                    selection: $minute,
                    label: { String(format: "%02d", $0) },
                    alignment: .leading,
                    showsBand: false
                )
                .frame(width: 92)
                .accessibilityLabel("Minutes")
            }
            .frame(maxWidth: .infinity)
        }
    }
}

#Preview {
    @Previewable @State var hour = 7
    @Previewable @State var minute = 0
    ScreenBackground(glow: .topTrailing) {
        TimeWheels(hour: $hour, minute: $minute)
            .padding(.horizontal, Theme.Spacing.screenHorizontal)
    }
}
