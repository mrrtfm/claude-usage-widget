import Foundation

// what the iOS app leaves in the app-group container for the widget to draw.
// deliberately secret-free: names and percentages only, no cookies — the widget reads
// credentials from the shared keychain instead, and only if it's entitled to.
public struct WidgetPayload: Codable, Sendable {
    public struct Row: Codable, Sendable, Identifiable {
        public var id: String
        public var initial: String
        public var name: String
        public var planLabel: String
        public var sessionUsed: Double?
        public var sessionResets: Date?
        public var weeklyUsed: Double?
        public var weeklyResets: Date?

        public init(id: String, initial: String, name: String, planLabel: String,
                    sessionUsed: Double?, sessionResets: Date?,
                    weeklyUsed: Double?, weeklyResets: Date?) {
            self.id = id
            self.initial = initial
            self.name = name
            self.planLabel = planLabel
            self.sessionUsed = sessionUsed
            self.sessionResets = sessionResets
            self.weeklyUsed = weeklyUsed
            self.weeklyResets = weeklyResets
        }
    }

    public var rows: [Row]
    public var updatedAt: Date

    public init(rows: [Row], updatedAt: Date = Date()) {
        self.rows = rows
        self.updatedAt = updatedAt
    }

    // fold the app's live account states down to the widget's flat rows.
    public init(states: [AccountState]) {
        self.rows = states.map { s in
            Row(id: s.account.id,
                initial: s.account.initial,
                name: s.account.name.isEmpty ? s.account.email : s.account.name,
                planLabel: s.account.displayPlan.label,
                sessionUsed: s.snapshot?.session?.used,
                sessionResets: s.snapshot?.session?.resetsAt,
                weeklyUsed: s.snapshot?.weeklyAll?.used,
                weeklyResets: s.snapshot?.weeklyAll?.resetsAt)
        }
        self.updatedAt = Date()
    }
}

// app-group handoff. `appGroupID` stays nil until something calls AppConfig.bootstrap(),
// and nil means "no group configured" — every call below then no-ops instead of trapping,
// which is exactly the free-Apple-ID case (app groups need a paid team).
public enum SharedStore {
    public nonisolated(unsafe) static var appGroupID: String?

    private static var fileURL: URL? {
        guard let g = appGroupID, !g.isEmpty,
              let dir = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: g)
        else { return nil }
        return dir.appendingPathComponent("widget-payload.json")
    }

    public static var isConfigured: Bool { fileURL != nil }

    public static func save(_ payload: WidgetPayload) {
        guard let url = fileURL, let data = try? JSONEncoder().encode(payload) else { return }
        try? data.write(to: url, options: .atomic)
    }

    public static func load() -> WidgetPayload? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WidgetPayload.self, from: data)
    }
}

// wiring for the two capabilities that need a paid developer account. both are read from
// Info.plist so enabling them is a build-setting change, not a code change — see
// docs/ios-deploy.md. empty/placeholder values are treated as "not configured".
public enum AppConfig {
    public static func bootstrap(bundle: Bundle = .main) {
        SharedStore.appGroupID = value(bundle, "AppGroupIdentifier")
        KeychainStore.accessGroup = value(bundle, "KeychainAccessGroup")
    }

    // an unset xcconfig var expands to the literal "$(NAME)" — treat that as unset too
    private static func value(_ bundle: Bundle, _ key: String) -> String? {
        guard let s = bundle.object(forInfoDictionaryKey: key) as? String else { return nil }
        let t = s.trimmingCharacters(in: .whitespaces)
        return (t.isEmpty || t.hasPrefix("$(")) ? nil : t
    }
}
