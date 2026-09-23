import SwiftUI
import ClaudeUsageKit

@main
struct ClaudeUsageApp: App {
    @State private var store: UsageStore
    @Environment(\.scenePhase) private var phase

    init() {
        // must run before the store touches the keychain — it decides which access group
        // (if any) the accounts live in.
        AppConfig.bootstrap()
        _store = State(initialValue: UsageStore())
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(store)
                .task { store.start() }
        }
        // no background execution on iOS, so "coming back to the app" is the real refresh
        // trigger — the poll timer only ticks while we're on screen.
        .onChange(of: phase) { _, new in
            if new == .active { Task { await store.refreshAll() } }
        }
    }
}
