import Foundation
import Observation
import SwiftUI

// which usage window the menu-bar readout tracks.
enum MenuMetric: String, CaseIterable, Identifiable {
    case session, weekly
    var id: String { rawValue }
    var label: String { self == .session ? "Session (5h)" : "Weekly (7d)" }
    var short: String { self == .session ? "session" : "weekly" }
}

// single source of truth for the whole app: the account list, their latest usage,
// polling, and the little settings the menu bar reads.
@MainActor
@Observable
final class UsageStore {
    var states: [AccountState] = []
    var lastRefresh: Date?
    var isRefreshing = false

    // settings (persisted)
    var refreshMinutes: Int {
        didSet { UserDefaults.standard.set(refreshMinutes, forKey: "refreshMinutes"); restartTimer() }
    }
    var showPercentInMenuBar: Bool {
        didSet { UserDefaults.standard.set(showPercentInMenuBar, forKey: "showPercent") }
    }
    var menuBarMetric: MenuMetric {
        didSet { UserDefaults.standard.set(menuBarMetric.rawValue, forKey: "menuBarMetric") }
    }

    private var login: LoginController?
    private var timerTask: Task<Void, Never>?

    init() {
        let d = UserDefaults.standard
        refreshMinutes = (d.object(forKey: "refreshMinutes") as? Int) ?? 5
        showPercentInMenuBar = (d.object(forKey: "showPercent") as? Bool) ?? true
        menuBarMetric = MenuMetric(rawValue: d.string(forKey: "menuBarMetric") ?? "") ?? .session
        states = KeychainStore.load().map { AccountState(account: $0) }
    }

    // MARK: derived menu-bar signal

    // used-% for the selected metric (session by default), for one account.
    private func metricUsed(_ s: AccountState) -> Double? {
        let w = menuBarMetric == .session ? s.snapshot?.session : s.snapshot?.weeklyAll
        return w?.used
    }

    // per-account readout for the stacked 2-account menu-bar view.
    var menuBarItems: [(initial: String, used: Double?)] {
        states.map { ($0.account.initial, metricUsed($0)) }
    }

    // tightest usage across accounts drives the single-line icon (worst case first).
    var worstUsed: Double? { states.compactMap(metricUsed).max() }

    // MARK: accounts

    func addAccount() {
        let controller = LoginController { [weak self] result in
            Task { @MainActor in
                self?.login = nil
                if case .success(let account) = result { self?.upsert(account) }
            }
        }
        login = controller
        controller.present()
    }

    private func upsert(_ account: Account) {
        if let i = states.firstIndex(where: { $0.account.id == account.id }) {
            states[i].account = account
            states[i].error = nil
        } else {
            states.append(AccountState(account: account))
        }
        persist()
        Task { await refresh(account.id) }
    }

    func remove(_ id: String) {
        states.removeAll { $0.account.id == id }
        persist()
    }

    private func persist() {
        KeychainStore.save(states.map { $0.account })
    }

    // MARK: refresh

    func refreshAll() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        await withTaskGroup(of: Void.self) { group in
            for s in states { group.addTask { await self.refresh(s.account.id) } }
        }
        lastRefresh = Date()
        isRefreshing = false
    }

    func refresh(_ id: String) async {
        guard let i = states.firstIndex(where: { $0.account.id == id }) else { return }
        states[i].loading = true
        let account = states[i].account
        do {
            let snap = try await ClaudeAPI.fetchUsage(orgUuid: account.orgUuid, cookies: account.cookies, userAgent: account.userAgent)
            guard let j = states.firstIndex(where: { $0.account.id == id }) else { return }
            states[j].snapshot = snap
            states[j].error = nil
            states[j].loading = false

            // self-heal the plan label for accounts stored before tier detection improved
            // (incl. generic "raven" → try to pin the specific Max tier)
            if states[j].account.displayPlan == .unknown || states[j].account.name.isEmpty || states[j].account.planTier == "raven",
               let ident = try? await ClaudeAPI.fetchIdentity(cookies: account.cookies, userAgent: account.userAgent),
               let k = states.firstIndex(where: { $0.account.id == id }) {
                states[k].account.planTier = ident.planTier
                if states[k].account.name.isEmpty { states[k].account.name = ident.name }
                persist()
            }
        } catch {
            guard let j = states.firstIndex(where: { $0.account.id == id }) else { return }
            states[j].error = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            states[j].loading = false
        }
    }

    // MARK: polling

    func start() {
        restartTimer()
        Task { await refreshAll() }
    }

    private func restartTimer() {
        timerTask?.cancel()
        let interval = UInt64(max(1, refreshMinutes)) * 60 * 1_000_000_000
        timerTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: interval)
                if Task.isCancelled { break }
                await self?.refreshAll()
            }
        }
    }
}
