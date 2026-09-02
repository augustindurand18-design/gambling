import Foundation

enum StakeStatus: String, Codable, Sendable {
    case active, released, charged
}

/// Somme engagee sur un objectif.
///
/// `charityBps` est fige a l'engagement : une evolution ulterieure du ratio
/// reverse ne modifie pas les mises deja consenties.
struct Stake: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let goalID: UUID
    let userID: UUID

    let amountCents: Int
    let currency: String
    let charityBps: Int
    let charityID: UUID?
    var status: StakeStatus
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id
        case goalID = "goal_id"
        case userID = "user_id"
        case amountCents = "amount_cents"
        case currency
        case charityBps = "charity_bps"
        case charityID = "charity_id"
        case status
        case createdAt = "created_at"
    }
}

extension Stake {
    var charityAmountCents: Int { Self.charityShare(of: amountCents, bps: charityBps) }
    var companyAmountCents: Int { amountCents - charityAmountCents }

    /// Part reversee a l'association.
    ///
    /// Arrondi a l'entier inferieur, le reliquat revient a la societe : aucun
    /// centime ne disparait. Doit rester strictement identique a
    /// `app.split_stake` en base.
    static func charityShare(of amountCents: Int, bps: Int) -> Int {
        (amountCents * bps) / 10_000
    }
}

/// Association beneficiaire.
struct Charity: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let slug: String
    let name: String
    let description: String?
    let logoURL: String?
    let websiteURL: String?
    let active: Bool
    let sortOrder: Int

    enum CodingKeys: String, CodingKey {
        case id, slug, name, description, active
        case logoURL = "logo_url"
        case websiteURL = "website_url"
        case sortOrder = "sort_order"
    }
}
