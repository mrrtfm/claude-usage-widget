import SwiftUI
import ClaudeUsageKit

struct SettingsView: View {
    @Environment(UsageStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var store = store
        NavigationStack {
            Form {
                Section("Refresh") {
                    Stepper(value: $store.refreshMinutes, in: 1...60) {
                        HStack {
                            Text("Every")
                            Spacer()
                            Text("\(store.refreshMinutes) min").foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                    Text("Only ticks while the app is open — iOS suspends background work. Pull down to refresh any time.")
                        .font(.caption).foregroundStyle(.secondary)
                }

                Section("Widget") {
                    Picker("Tracks", selection: $store.primaryMetric) {
                        ForEach(PrimaryMetric.allCases) { m in Text(m.label).tag(m) }
                    }
                    if !SharedStore.isConfigured {
                        Label("No app group configured — the home-screen widget stays empty. See docs/ios-deploy.md.",
                              systemImage: "exclamationmark.triangle")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                Section("Accounts") {
                    ForEach(store.states) { s in
                        HStack {
                            Text(s.account.name.isEmpty ? s.account.email : s.account.name)
                            Spacer()
                            Text(s.account.displayPlan.label).foregroundStyle(.secondary).font(.caption)
                        }
                    }
                    .onDelete { idx in idx.map { store.states[$0].account.id }.forEach(store.remove) }
                    Button("Add account", systemImage: "plus") {
                        dismiss()
                        store.addAccount()
                    }
                }

                Section {
                    Text("Usage is read from claude.ai's web API using each account's signed-in session. Sessions are stored in the device keychain and never leave it except to claude.ai.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } }
            }
        }
    }
}
