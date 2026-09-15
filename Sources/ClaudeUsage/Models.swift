import Foundation
import SwiftUI

// one claude usage window (5h session, 7d all-models, 7d opus, …).
// utilization is a percent 0–100; resets_at is when the window rolls over.
struct UsageWindow: Codable, Hashable {
    var utilization: Double?
    var resetsAt: Date?

    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }

    // api hands utilization as either a number or occasionally null; resets_at is ISO8601
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        utilization = try? c.decodeIfPresent(Double.self, forKey: .utilization)
        if let s = try? c.decodeIfPresent(String.self, forKey: .resetsAt), let d = UsageWindow.parse(s) {
            resetsAt = d
        }
    }

    init(utilization: Double?, resetsAt: Date?) {
        self.utilization = utilization
        self.resetsAt = resetsAt
    }

    static func parse(_ s: String) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: s) { return d }
        iso.formatOptions = [.withInternetDateTime]
        return iso.date(from: s)
    }

    var used: Double { max(0, min(100, utilization ?? 0)) }
    var remaining: Double { max(0, 100 - used) }
}

// snapshot of every window for one account at one point in time.
struct UsageSnapshot: Equatable {
    var windows: [String: UsageWindow] = [:]
    var fetchedAt: Date = .init()

    var session: UsageWindow? { windows["five_hour"] }
    var weeklyAll: UsageWindow? { windows["seven_day"] }
    var weeklyOpus: UsageWindow? { windows["seven_day_opus"] }
}

// a signed-in claude account. cookies are the replayable session (sessionKey + friends).
struct Account: Codable, Identifiable, Equatable {
    var id: String            // org uuid — stable per account
    var name: String
    var email: String
    var orgUuid: String
    var planTier: String      // raw rate_limit_tier / capability hint
    var cookies: [String: String]
    var userAgent: String?    // the webview's real UA — cf_clearance is bound to it

    var displayPlan: Plan { Plan(tier: planTier) }
    var initial: String {
        let base = name.isEmpty ? email : name
        return String(base.first.map(String.init)?.uppercased() ?? "?")
    }
}

// friendly plan label derived from the raw tier string.
enum Plan: String {
    case free, pro, max, max5, max20, team, enterprise, unknown

    init(tier: String) {
        let t = tier.lowercased()
        if t.contains("max_20") || t.contains("20x") { self = .max20 }
        else if t.contains("max_5") || t.contains("5x") { self = .max5 }
        else if t.contains("enterprise") { self = .enterprise }
        else if t.contains("team") { self = .team }
        else if t.contains("max") { self = .max }
        else if t.contains("pro") { self = .pro }
        else if t.contains("free") { self = .free }
        // note: "raven" is infra plumbing shared by Team AND Max — never a plan hint on its own
        else { self = .unknown }
    }

    var label: String {
        switch self {
        case .free: return "Free"
        case .pro: return "Pro"
        case .max: return "Max"
        case .max5: return "Max 5×"
        case .max20: return "Max 20×"
        case .team: return "Team"
        case .enterprise: return "Enterprise"
        case .unknown: return "Plan"
        }
    }

    var tint: Color {
        switch self {
        case .max20, .max: return .purple
        case .max5: return .indigo
        case .pro: return .orange
        case .team, .enterprise: return .teal
        default: return .secondary
        }
    }
}

// per-account load state shown in the UI.
struct AccountState: Identifiable {
    var account: Account
    var snapshot: UsageSnapshot?
    var error: String?
    var loading: Bool = false
    var id: String { account.id }
}
