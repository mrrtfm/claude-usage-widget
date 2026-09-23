import Foundation
import os

private let log = Logger(subsystem: "com.laszlo.ClaudeUsage", category: "api")

// thin client over claude.ai's web api. auth is the browser session cookie jar
// (sessionKey + cloudflare's cf_clearance), captured at login and replayed here.
// war story: cf_clearance is bound to the user-agent, so the UA below MUST match
// the one set on the login WKWebView or cloudflare 403s the replayed request.
public enum ClaudeAPI {
    static let base = "https://claude.ai"
    // fallback only — real requests use the UA captured from the login webview so it
    // matches the cf_clearance cookie cloudflare issued.
    static let fallbackUA = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15"

    public struct APIError: LocalizedError {
        public let message: String
        public var errorDescription: String? { message }
    }

    // MARK: request plumbing

    private static func get(_ path: String, cookies: [String: String], userAgent: String?) async throws -> Data {
        guard let url = URL(string: base + path) else { throw APIError(message: "bad url") }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        req.setValue(cookieHeader(cookies), forHTTPHeaderField: "Cookie")
        req.setValue(userAgent ?? fallbackUA, forHTTPHeaderField: "User-Agent")
        req.setValue("application/json", forHTTPHeaderField: "Accept")
        req.setValue(base + "/", forHTTPHeaderField: "Referer")
        req.setValue(base, forHTTPHeaderField: "Origin")
        req.setValue("empty", forHTTPHeaderField: "Sec-Fetch-Dest")
        req.setValue("cors", forHTTPHeaderField: "Sec-Fetch-Mode")
        req.setValue("same-origin", forHTTPHeaderField: "Sec-Fetch-Site")

        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse else { throw APIError(message: "no response") }
        switch http.statusCode {
        case 200: return data
        case 401, 403:
            // could be an expired session or a cloudflare challenge (html body)
            throw APIError(message: "session expired — sign in again")
        default:
            throw APIError(message: "http \(http.statusCode)")
        }
    }

    private static func cookieHeader(_ cookies: [String: String]) -> String {
        cookies.map { "\($0.key)=\($0.value)" }.joined(separator: "; ")
    }

    // MARK: identity + org discovery

    public struct Identity {
        public var name: String
        public var email: String
        public var orgUuid: String
        public var planTier: String
    }

    // pulls account name/email + the primary org (uuid + plan tier).
    // decoded loosely with JSONSerialization since the bootstrap payload is large and shifts.
    public static func fetchIdentity(cookies: [String: String], userAgent: String?) async throws -> Identity {
        let data = try await get("/api/bootstrap", cookies: cookies, userAgent: userAgent)
        let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]

        let account = root["account"] as? [String: Any] ?? [:]
        let name = (account["full_name"] as? String)
            ?? (account["display_name"] as? String) ?? ""
        let email = (account["email_address"] as? String)
            ?? (account["email"] as? String) ?? ""

        // organizations can live in bootstrap; if not, ask the dedicated endpoint
        var orgs = (root["organizations"] as? [[String: Any]])
            ?? ((account["memberships"] as? [[String: Any]])?.compactMap { $0["organization"] as? [String: Any] })
            ?? []
        if orgs.isEmpty {
            let od = try await get("/api/organizations", cookies: cookies, userAgent: userAgent)
            orgs = (try? JSONSerialization.jsonObject(with: od)) as? [[String: Any]] ?? []
        }
        guard let org = pickOrg(orgs) else { throw APIError(message: "no organization found") }

        // plan-field diagnostics (verbose org-key dump only under --debug)
        log.debug("org keys: \(org.keys.sorted().joined(separator: ","), privacy: .public)")
        log.debug("plan fields — analytics_subscription_plan=\(String(describing: org["analytics_subscription_plan"]), privacy: .public) capabilities=[\((org["capabilities"] as? [String])?.joined(separator: ",") ?? "nil", privacy: .public)] rate_limit_tier=\(org["rate_limit_tier"] as? String ?? "nil", privacy: .public) raven_type=\(String(describing: org["raven_type"]), privacy: .public)")

        let uuid = (org["uuid"] as? String) ?? (org["id"] as? String) ?? ""
        let tier = planTier(from: org)
        log.info("resolved planTier=\(tier, privacy: .public)")
        return Identity(name: name, email: email, orgUuid: uuid, planTier: tier)
    }

    // prefer a real chat org over api-only / stale ones.
    private static func pickOrg(_ orgs: [[String: Any]]) -> [String: Any]? {
        func caps(_ o: [String: Any]) -> [String] { (o["capabilities"] as? [String]) ?? [] }
        if let chat = orgs.first(where: { caps($0).contains("chat") }) { return chat }
        return orgs.first { !caps($0).contains("api") } ?? orgs.first
    }

    private static func planTier(from org: [String: Any]) -> String {
        // analytics_subscription_plan is the authoritative human plan name (pro/team/max_*/…)
        if let p = org["analytics_subscription_plan"] as? String, !p.isEmpty, p.lowercased() != "unknown" {
            return p
        }
        // explicit capability hints (raven excluded — it's shared by Team and Max)
        let caps = (org["capabilities"] as? [String]) ?? []
        for hint in ["claude_max_20x", "claude_max_5x", "claude_max", "claude_pro",
                     "claude_enterprise", "enterprise", "claude_team", "team"] where caps.contains(hint) {
            return hint
        }
        // raven_type sometimes names the tier explicitly
        if let rt = org["raven_type"] as? String, !rt.isEmpty, rt.lowercased() != "unknown" { return rt }
        if let t = org["rate_limit_tier"] as? String, !t.isEmpty, t != "default",
           !t.contains("claude_ai"), !t.contains("raven") { return t }
        // last resort: scan settings values for a plan-ish string
        if let settings = org["settings"] as? [String: Any] {
            for v in settings.values {
                if let s = v as? String, ["pro", "max", "team", "enterprise"].contains(where: s.lowercased().contains) {
                    return s
                }
            }
        }
        return caps.joined(separator: ",")
    }

    // MARK: usage

    public static func fetchUsage(orgUuid: String, cookies: [String: String], userAgent: String?) async throws -> UsageSnapshot {
        let data = try await get("/api/organizations/\(orgUuid)/usage", cookies: cookies, userAgent: userAgent)
        let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        // some builds nest the windows under a wrapper key; unwrap if so
        let map = (root["rate_limits"] as? [String: Any])
            ?? (root["usage"] as? [String: Any]) ?? root

        var windows: [String: UsageWindow] = [:]
        for (key, value) in map {
            guard let obj = value as? [String: Any] else { continue }  // skip nulls / scalars
            let util = (obj["utilization"] as? Double)
                ?? (obj["percent"] as? Double)
                ?? (obj["utilization"] as? NSNumber)?.doubleValue
            var resets: Date?
            if let s = obj["resets_at"] as? String { resets = UsageWindow.parse(s) }
            windows[key] = UsageWindow(utilization: util, resetsAt: resets)
        }
        return UsageSnapshot(windows: windows, fetchedAt: Date())
    }
}
