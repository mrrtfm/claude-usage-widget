import SwiftUI

// inline settings tray (kept in-panel so we don't juggle a separate window).
struct SettingsPane: View {
    @Environment(UsageStore.self) private var store

    var body: some View {
        @Bindable var store = store
        VStack(alignment: .leading, spacing: 10) {
            Text("Settings").font(.caption.weight(.semibold)).foregroundStyle(.secondary)

            HStack {
                Text("Refresh every").font(.caption)
                Spacer()
                Stepper(value: $store.refreshMinutes, in: 1...60) {
                    Text("\(store.refreshMinutes) min").font(.caption.monospacedDigit())
                }
                .controlSize(.mini)
            }

            Toggle(isOn: $store.showPercentInMenuBar) {
                Text("Show usage % in menu bar").font(.caption)
            }
            .toggleStyle(.switch)
            .controlSize(.mini)

            Toggle(isOn: $store.launchAtLogin) {
                Text("Launch at login").font(.caption)
            }
            .toggleStyle(.switch)
            .controlSize(.mini)

            HStack {
                Text("Menu bar tracks").font(.caption)
                Spacer()
                Picker("", selection: $store.menuBarMetric) {
                    ForEach(MenuMetric.allCases) { m in Text(m.label).tag(m) }
                }
                .labelsHidden()
                .controlSize(.mini)
                .fixedSize()
            }

            Text("Usage is read from claude.ai's web API using each account's signed-in session. Sessions are stored in your login keychain.")
                .font(.caption2).foregroundStyle(.tertiary)
        }
        .padding(12)
    }
}
