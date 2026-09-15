import SwiftUI

// the dropdown panel: header, one card per account, footer actions.
struct PanelView: View {
    @Environment(UsageStore.self) private var store
    @State private var showSettings = false

    // height of the scroll viewport once there are >2 cards (≈ two cards)
    private let scrollCap: CGFloat = 470

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            if showSettings {
                SettingsPane()
            } else if store.states.isEmpty {
                emptyState
            } else {
                cardList
            }
            Divider()
            footer
        }
        .frame(width: 360)
    }

    // ≤2 accounts render inline (window sizes to fit, no scroll). beyond that we cap the
    // viewport so it scrolls after roughly two cards.
    @ViewBuilder private var cardList: some View {
        if store.states.count <= 2 {
            cardStack
        } else {
            ScrollView { cardStack }.frame(height: scrollCap)
        }
    }

    private var cardStack: some View {
        VStack(spacing: 10) {
            ForEach(store.states) { state in AccountCardView(state: state) }
        }
        .padding(12)
    }

    private var header: some View {
        HStack(spacing: 8) {
            if showSettings {
                Text("Settings").font(.headline)
                Spacer()
                Button("Done") { withAnimation { showSettings = false } }
                    .buttonStyle(.borderless)
            } else {
                Image(systemName: "gauge.with.dots.needle.67percent")
                    .foregroundStyle(.tint)
                Text("Claude Usage").font(.headline)
                Spacer()
                if let last = store.lastRefresh {
                    Text(last, format: .relative(presentation: .numeric))
                        .font(.caption2).foregroundStyle(.secondary)
                }
                Button {
                    Task { await store.refreshAll() }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .rotationEffect(.degrees(store.isRefreshing ? 360 : 0))
                        .animation(store.isRefreshing ? .linear(duration: 1).repeatForever(autoreverses: false) : .default, value: store.isRefreshing)
                }
                .buttonStyle(.borderless)
                .disabled(store.isRefreshing)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "person.crop.circle.badge.plus")
                .font(.system(size: 34)).foregroundStyle(.secondary)
            Text("No accounts yet").font(.headline)
            Text("Add a Claude account to track its session and weekly limits.")
                .font(.caption).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Add account") { store.addAccount() }
                .buttonStyle(.borderedProminent)
        }
        .padding(24)
        .frame(maxWidth: .infinity)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Button {
                store.addAccount()
            } label: { Label("Add account", systemImage: "plus") }
                .buttonStyle(.borderless)
            Spacer()
            Button {
                withAnimation { showSettings.toggle() }
            } label: { Image(systemName: "gearshape") }
                .buttonStyle(.borderless)
            Button {
                NSApplication.shared.terminate(nil)
            } label: { Image(systemName: "power") }
                .buttonStyle(.borderless)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }
}

// MARK: - account card

struct AccountCardView: View {
    @Environment(UsageStore.self) private var store
    let state: AccountState

    private var account: Account { state.account }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                avatar
                VStack(alignment: .leading, spacing: 1) {
                    Text(account.name.isEmpty ? account.email : account.name)
                        .font(.subheadline.weight(.semibold)).lineLimit(1)
                    Text(account.email).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                planBadge
            }

            if let err = state.error {
                errorRow(err)
            } else if let snap = state.snapshot {
                usageRows(snap)
            } else {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Loading…").font(.caption).foregroundStyle(.secondary)
                }.padding(.vertical, 4)
            }
        }
        .padding(12)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Color(nsColor: .separatorColor).opacity(0.6)))
        .contextMenu {
            Button("Refresh") { Task { await store.refresh(account.id) } }
            Button("Sign in again") { store.addAccount() }
            Divider()
            Button("Remove account", role: .destructive) { store.remove(account.id) }
        }
    }

    private var avatar: some View {
        Text(account.initial)
            .font(.headline).foregroundStyle(.white)
            .frame(width: 34, height: 34)
            .background(account.displayPlan.tint.gradient, in: Circle())
    }

    private var planBadge: some View {
        Text(account.displayPlan.label)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(account.displayPlan.tint.opacity(0.15), in: Capsule())
            .foregroundStyle(account.displayPlan.tint)
    }

    @ViewBuilder
    private func usageRows(_ snap: UsageSnapshot) -> some View {
        VStack(spacing: 8) {
            if let w = snap.session { UsageBarView(title: "Session", subtitle: "5-hour window", window: w) }
            if let w = snap.weeklyAll { UsageBarView(title: "Weekly", subtitle: "all models · 7-day", window: w) }
            if let w = snap.weeklyOpus { UsageBarView(title: "Weekly Opus", subtitle: "opus · 7-day", window: w) }
            if snap.session == nil && snap.weeklyAll == nil {
                Text("No usage windows reported.")
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }
    }

    private func errorRow(_ msg: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text(msg).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            Spacer()
            Button("Sign in") { store.addAccount() }.font(.caption).buttonStyle(.borderless)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - usage bar

struct UsageBarView: View {
    let title: String
    let subtitle: String
    let window: UsageWindow

    private var used: Double { window.used }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.caption.weight(.medium))
                Text(subtitle).font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(window.remaining.rounded()))% left")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(barColor)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary).frame(height: 6)
                    Capsule().fill(barColor.gradient)
                        .frame(width: max(4, geo.size.width * used / 100), height: 6)
                }
            }
            .frame(height: 6)
            HStack {
                Text("\(Int(used.rounded()))% used").font(.caption2).foregroundStyle(.secondary)
                Spacer()
                if let reset = window.resetsAt {
                    Text(resetText(reset)).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }

    private var barColor: Color {
        switch used {
        case ..<50: return .green
        case ..<75: return .yellow
        case ..<90: return .orange
        default: return .red
        }
    }

    private func resetText(_ date: Date) -> String {
        let now = Date()
        if date <= now { return "resets now" }
        let secs = Int(date.timeIntervalSince(now))
        let d = secs / 86400, h = (secs % 86400) / 3600, m = (secs % 3600) / 60
        if d > 0 { return "resets in \(d)d \(h)h" }
        if h > 0 { return "resets in \(h)h \(m)m" }
        return "resets in \(m)m"
    }
}
