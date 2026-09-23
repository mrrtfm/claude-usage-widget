import Foundation
import Observation
import SwiftUI
import WidgetKit
import ClaudeUsageKit

// which usage window the widget's compact readout tracks.
enum PrimaryMetric: String, CaseIterable, Identifiable {
    case session, weekly
    var id: String { rawValue }
    var label: String { self == .session ? "Session (5h)" : "Weekly (7d)" }
}

// single source of truth for the app: the account list, their latest usage, polling, and
// the handoff to the widget. mirrors the macOS UsageStore minus the menu-bar bits.
@MainActor
@Observable
final class UsageStore {
    var states: [AccountState] = []
    var lastRefresh: Date?
    var isRefreshing = false
    var showingLogin = false

    // settings (persisted)
    var refreshMinutes: Int {
        didSet { UserDefaults.standard.set(refreshMinutes, forKey: "refreshMinutes"); restartTimer() }
    }
    var primaryMetric: PrimaryMetric {
        didSet { UserDefaults.standard.set(primaryMetric.rawValue, forKey: "primaryMetric"); pushToWidget() }
    }

    private var timerTask: Task<Void, Never>?

    init() {
        let d = UserDefaults.standard
        refreshMinutes = (d.object(forKey: "refreshMinutes") as? Int) ?? 5
        primaryMetric = PrimaryMetric(rawValue: d.string(forKey: "primaryMetric") ?? "") ?? .session
        states = KeychainStore.load().map { AccountState(account: $0) }
    }

    // MARK: derived

    private func metricUsed(_ s: AccountState) -> Double? {
        (primaryMetric == .session ? s.snapshot?.session : s.snapshot?.weeklyAll)?.used
    }

    // tightest usage across accounts — the one number worth glancing at
    var worstUsed: Double? { states.compactMap(metricUsed).max() }

    // MARK: accounts

    func addAccount() { showingLogin = true }

    func finishLogin(_ result: Result<Account, Error>) {
        showingLogin = false
        if case .success(let account) = result { upsert(account) }
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
        pushToWidget()
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
        pushToWidget()
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

    // MARK: widget handoff

    // leave a secret-free snapshot in the app group and nudge the timelines. no-ops when no
    // app group is configured (free apple id) — the app just works without a widget.
    private func pushToWidget() {
        guard SharedStore.isConfigured else { return }
        SharedStore.save(WidgetPayload(states: states))
        WidgetCenter.shared.reloadAllTimelines()
    }

    // MARK: polling

    func start() {
        restartTimer()
        Task { await refreshAll() }
    }

    // foreground-only poll: iOS suspends us in the background, so this timer is really
    // "keep the open app fresh". the widget does its own fetching on its own budget.
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
