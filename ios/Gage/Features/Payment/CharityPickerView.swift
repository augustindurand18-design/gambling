import SwiftUI

/// Choix de l'association vers laquelle part la part reversée.
///
/// Ce choix n'est pas décoratif : le texte de consentement affirme qu'une part
/// ira « à l'association que j'ai choisie ». Tant que personne ne choisit, ce
/// texte décrit une répartition qui n'existe pas — et c'est exactement ce
/// qu'un médiateur relèverait en premier.
///
/// Le choix vaut pour les engagements **à venir**. Ceux déjà pris gardent
/// l'association qui figurait dans leur consentement : `commit_goal` la
/// recopie sur l'objectif au moment de l'engagement, où elle se fige.
struct CharityPickerView: View {
    var onChosen: (UUID) -> Void

    @State private var phase: Phase = .loading
    @State private var chosen: UUID?
    @Environment(\.dismiss) private var dismiss

    private enum Phase {
        case loading
        case loaded([Charity])
        case failed(String)
    }

    var body: some View {
        NavigationStack {
            ScreenBackground {
                switch phase {
                case .loading:
                    ProgressView().controlSize(.large).tint(Theme.Colors.brand)

                case .failed(let message):
                    VStack(spacing: Theme.Spacing.medium) {
                        Text(message)
                            .font(Theme.Fonts.body)
                            .foregroundStyle(Theme.Colors.inkMuted)
                            .multilineTextAlignment(.center)
                        PrimaryButton(title: "Réessayer", showsChevron: false) {
                            Task { await load() }
                        }
                    }
                    .padding(.horizontal, Theme.Spacing.screenHorizontal)

                case .loaded(let charities):
                    ScrollView {
                        VStack(alignment: .leading, spacing: Theme.Spacing.small) {
                            Text(
                                "\(BusinessRules.charityBps / 100) % de chaque mise perdue lui sera reversé. "
                                    + "Tu peux en changer quand tu veux : les engagements déjà pris gardent la leur."
                            )
                            .font(Theme.Fonts.body)
                            .foregroundStyle(Theme.Colors.inkMuted)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.bottom, Theme.Spacing.small)

                            ForEach(charities) { charity in
                                row(charity)
                            }
                        }
                        .padding(.horizontal, Theme.Spacing.screenHorizontal)
                        .padding(.vertical, Theme.Spacing.medium)
                    }
                    .scrollIndicators(.hidden)
                }
            }
            .navigationTitle("Association")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fermer") { dismiss() }
                        .font(Theme.Fonts.footnote)
                        .foregroundStyle(Theme.Colors.brand)
                }
            }
        }
        .task { await load() }
    }

    private func row(_ charity: Charity) -> some View {
        Button {
            Task { await choose(charity) }
        } label: {
            HStack(alignment: .top, spacing: Theme.Spacing.small) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(charity.name)
                        .font(Theme.Fonts.cardTitle)
                        .foregroundStyle(Theme.Colors.ink)
                    if let description = charity.description {
                        Text(description)
                            .font(Theme.Fonts.cardSubtitle)
                            .foregroundStyle(Theme.Colors.inkMuted)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: Theme.Spacing.small)
                Image(systemName: chosen == charity.id ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 20))
                    .foregroundStyle(chosen == charity.id ? Theme.Colors.brand : Theme.Colors.dotInactive)
            }
            .multilineTextAlignment(.leading)
            .padding(Theme.Spacing.medium - 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                chosen == charity.id ? Theme.Colors.cardSelected : Theme.Colors.card,
                in: .rect(cornerRadius: Theme.Metrics.cardRadius, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Metrics.cardRadius, style: .continuous)
                    .strokeBorder(
                        chosen == charity.id ? Theme.Colors.selectionBorder : .clear,
                        lineWidth: 1.5
                    )
            }
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("charity-\(charity.slug)")
    }

    private func load() async {
        phase = .loading
        do {
            let charities = try await ProfileAPI.shared.charities()
            chosen = try? await ProfileAPI.shared.load().defaultCharityID
            phase = .loaded(charities)
        } catch {
            phase = .failed(
                (error as? AppError)?.errorDescription ?? "Impossible de charger les associations."
            )
        }
    }

    private func choose(_ charity: Charity) async {
        // Le choix s'affiche tout de suite : l'aller-retour serveur ne doit pas
        // donner l'impression que le tap n'a pas été pris.
        let previous = chosen
        chosen = charity.id

        do {
            try await ProfileAPI.shared.chooseCharity(charity.id)
            onChosen(charity.id)
        } catch {
            chosen = previous
            phase = .failed(
                (error as? AppError)?.errorDescription ?? "Ton choix n'a pas pu être enregistré."
            )
        }
    }
}
