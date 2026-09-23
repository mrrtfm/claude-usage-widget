import Foundation
import SwiftUI

// one claude usage window (5h session, 7d all-models, 7d opus, …).
// utilization is a percent 0–100; resets_at is when the window rolls over.
public struct UsageWindow: Codable, Hashable, Sendable {
    public var utilization: Double?
    public var resetsAt: Date?

    enum CodingKeys: String, CodingKey {
        case utilization
        case resetsAt = "resets_at"
    }

    // api hands utilization as either a number or occasionally null; resets_at is ISO8601
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        utilization = try? c.decodeIfPresent(Double.self, forKey: .utilization)
        if let s = try? c.decodeIfPresent(String.self, forKey: .resetsAt), let d = UsageWindow.parse(s) {
            resetsAt = d
        }
    }

    public init(utilization: Double?, resetsAt: Date?) {
        self.utilization = utilization
        self.resetsAt = resetsAt
    }

    public static func parse(_ s: String) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = iso.date(from: s) { return d }
        iso.formatOptions = [.withInternetDateTime]
        return iso.date(from: s)
    }

    public var used: Double { max(0, min(100, utilization ?? 0)) }
    public var remaining: Double { max(0, 100 - used) }
}

// snapshot of every window for one account at one point in time.
// Codable so the iOS app can hand it to the widget through the app group.
public struct UsageSnapshot: Codable, Equatable, Sendable {
    public var windows: [String: UsageWindow] = [:]
    public var fetchedAt: Date = .init()

    public init(windows: [String: UsageWindow] = [:], fetchedAt: Date = .init()) {
        self.windows = windows
        self.fetchedAt = fetchedAt
    }

    public var session: UsageWindow? { windows["five_hour"] }
    public var weeklyAll: UsageWindow? { windows["seven_day"] }
    public var weeklyOpus: UsageWindow? { windows["seven_day_opus"] }
}

// a signed-in claude account. cookies are the replayable session (sessionKey + friends).
public struct Account: Codable, Identifiable, Equatable, Sendable {
    public var id: String            // org uuid — stable per account
    public var name: String
    public var email: String
    public var orgUuid: String
    public var planTier: String      // raw rate_limit_tier / capability hint
    public var cookies: [String: String]
    public var userAgent: String?    // the webview's real UA — cf_clearance is bound to it

    public init(id: String, name: String, email: String, orgUuid: String,
                planTier: String, cookies: [String: String], userAgent: String?) {
        self.id = id
        self.name = name
        self.email = email
        self.orgUuid = orgUuid
        self.planTier = planTier
        self.cookies = cookies
        self.userAgent = userAgent
    }

    public var displayPlan: Plan { Plan(tier: planTier) }
    public var initial: String {
        let base = name.isEmpty ? email : name
        return String(base.first.map(String.init)?.uppercased() ?? "?")
    }
}

// friendly plan label derived from the raw tier string.
public enum Plan: String, Sendable {
    case free, pro, max, max5, max20, team, enterprise, unknown

    public init(tier: String) {
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

    public var label: String {
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

    public var tint: Color {
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
public struct AccountState: Identifiable {
    public var account: Account
    public var snapshot: UsageSnapshot?
    public var error: String?
    public var loading: Bool = false
    public var id: String { account.id }

    public init(account: Account, snapshot: UsageSnapshot? = nil, error: String? = nil, loading: Bool = false) {
        self.account = account
        self.snapshot = snapshot
        self.error = error
        self.loading = loading
    }
}

// colour ramp shared by every usage bar — green until half, red past 90% used.
public func usageTint(used: Double) -> Color {
    switch used {
    case ..<50: return .green
    case ..<75: return .yellow
    case ..<90: return .orange
    default: return .red
    }
}

// "resets in 3h 12m" / "resets in 2d 4h". nil date -> nil string.
public func resetText(_ date: Date, now: Date = Date()) -> String {
    if date <= now { return "resets now" }
    let secs = Int(date.timeIntervalSince(now))
    let d = secs / 86400, h = (secs % 86400) / 3600, m = (secs % 3600) / 60
    if d > 0 { return "resets in \(d)d \(h)h" }
    if h > 0 { return "resets in \(h)h \(m)m" }
    return "resets in \(m)m"
}
