import SwiftUI

/// Etape 3 : le rythme de la semaine, les jours, et l'heure de chaque jour.
///
/// L'heure n'est pas obligatoire ici. Quelqu'un qui ne sait pas encore a
/// quelle heure il ira peut la renseigner le matin meme ; le forcer a
/// inventer un horaire produirait un objectif rate pour une mauvaise raison.
struct PlanWeekView: View {
    @Binding var plan: GoalPlan
    let onContinue: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScreenBackground(glow: .topTrailing) {
            VStack(alignment: .leading, spacing: 0) {
                StepHeader(
                    count: NewGoalStep.total,
                    index: NewGoalStep.plan.index,
                    onBack: { dismiss() }
                )

                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        promise
                        daysSection
                        schedules
                    }
                    .padding(.bottom, Theme.Spacing.medium)
                }
                .scrollIndicators(.hidden)
                .padding(.top, Theme.Spacing.medium)

                PrimaryButton(
                    title: "Continuer",
                    isEnabled: plan.isScheduleComplete,
                    action: onContinue
                )
                .accessibilityIdentifier("plan-continue")
                .padding(.top, Theme.Spacing.small + 4)
            }
            .padding(.horizontal, Theme.Spacing.screenHorizontal)
            .padding(.top, Theme.Spacing.screenTop)
            .padding(.bottom, Theme.Spacing.medium)
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    /// La phrase se complete a la roue : le rythme se lit dans la promesse
    /// plutot que dans un reglage pose a cote.
    private var promise: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
            Text(plan.promiseText)
                .font(Theme.Fonts.sentence)
                .foregroundStyle(Theme.Colors.ink)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                Wheel(
                    values: GoalCatalogue.frequencies,
                    selection: Binding(
                        get: { plan.timesPerWeek },
                        set: { plan.setTimesPerWeek($0) }
                    ),
                    label: { "\($0)" },
                    selectedFont: Theme.Fonts.sentence
                )
                .frame(width: 78)
                .accessibilityLabel("Séances par semaine")

                Text("fois par semaine")
                    .font(Theme.Fonts.sentence)
                    .foregroundStyle(Theme.Colors.ink)
            }
        }
    }

    private var daysSection: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small + 4) {
            Divider().overlay(Theme.Colors.divider)

            Text("Quels jours ?")
                .font(Theme.Fonts.sectionTitle)
                .foregroundStyle(Theme.Colors.ink)

            Text(hint)
                .font(Theme.Fonts.body)
                .foregroundStyle(Theme.Colors.inkMuted)

            WeekCalendar(
                selected: plan.days,
                canSelectMore: plan.canSelectMoreDays,
                onToggle: { plan.toggleDay($0) }
            )
        }
        .padding(.top, Theme.Spacing.medium)
    }

    private var schedules: some View {
        VStack(spacing: Theme.Spacing.small + 4) {
            ForEach(plan.selectedDays) { day in
                DayScheduleCard(
                    day: day,
                    time: plan.time(for: day),
                    onChange: { plan.setTime($0, for: day) }
                )
            }
        }
        .padding(.top, Theme.Spacing.medium)
        .animation(.easeOut(duration: 0.2), value: plan.selectedDays)
    }

    private var hint: String {
        let remaining = plan.timesPerWeek - plan.days.count
        switch remaining {
        case ..<0: return "Retire un jour pour tenir la promesse."
        case 0: return "Ta semaine est complète."
        case 1: return "Encore un jour à choisir."
        default: return "Encore \(remaining) jours à choisir."
        }
    }
}

/// Un jour retenu : sait-on deja a quelle heure, ou le dira-t-on le matin ?
private struct DayScheduleCard: View {
    let day: Weekday
    let time: DayTime
    let onChange: (DayTime) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.small + 4) {
            HStack {
                Text(day.name)
                    .font(Theme.Fonts.cardTitle)
                    .foregroundStyle(Theme.Colors.ink)

                Spacer(minLength: Theme.Spacing.small)

                Text(time.text)
                    .font(Theme.Fonts.cardSubtitle)
                    .foregroundStyle(Theme.Colors.inkMuted)
            }

            HStack(spacing: 8) {
                choice(title: "Je sais l'heure", isOn: time.isFixed) {
                    onChange(.fixed(hour: time.hour, minute: time.minute))
                }
                choice(title: "Le matin même", isOn: !time.isFixed) {
                    onChange(.onTheDay)
                }
            }

            if time.isFixed {
                TimeWheels(
                    hour: Binding(
                        get: { time.hour },
                        set: { onChange(.fixed(hour: $0, minute: time.minute)) }
                    ),
                    minute: Binding(
                        get: { time.minute },
                        set: { onChange(.fixed(hour: time.hour, minute: $0)) }
                    )
                )
            }
        }
        .padding(Theme.Spacing.medium - 4)
        .background(Theme.Colors.card, in: .rect(cornerRadius: Theme.Metrics.cardRadius, style: .continuous))
        .shadow(color: Theme.Colors.ink.opacity(0.05), radius: 10, y: 4)
        .animation(.easeOut(duration: 0.2), value: time)
    }

    private func choice(title: String, isOn: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(Theme.Fonts.badge)
                .foregroundStyle(isOn ? Theme.Colors.brand : Theme.Colors.inkMuted)
                .padding(.horizontal, 14)
                .frame(height: 34)
                .background {
                    Capsule()
                        .fill(isOn ? Theme.Colors.cardSelected : Theme.Colors.disabledFill.opacity(0.6))
                        .overlay {
                            Capsule().strokeBorder(
                                isOn ? Theme.Colors.brand.opacity(0.35) : .clear,
                                lineWidth: 1.5
                            )
                        }
                }
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? [.isSelected] : [])
    }
}

#Preview {
    @Previewable @State var plan = GoalPlan(categoryID: "sport", variantID: "gym")
    PlanWeekView(plan: $plan, onContinue: {})
}
