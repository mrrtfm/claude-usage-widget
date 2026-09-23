import SwiftUI
import ClaudeUsageKit

// one account: identity row, plan badge, one bar per limit window.
struct AccountCardView: View {
    @Environment(UsageStore.self) private var store
    let state: AccountState

    private var account: Account { state.account }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
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
                }
            }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 16))
        .contextMenu {
            Button("Refresh", systemImage: "arrow.clockwise") { Task { await store.refresh(account.id) } }
            Button("Sign in again", systemImage: "person.badge.key") { store.addAccount() }
            Divider()
            Button("Remove account", systemImage: "trash", role: .destructive) { store.remove(account.id) }
        }
    }

    private var avatar: some View {
        Text(account.initial)
            .font(.headline).foregroundStyle(.white)
            .frame(width: 36, height: 36)
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
        VStack(spacing: 10) {
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
            Button("Sign in") { store.addAccount() }.font(.caption.weight(.semibold))
        }
    }
}

// MARK: - usage bar

struct UsageBarView: View {
    let title: String
    let subtitle: String
    let window: UsageWindow

    private var used: Double { window.used }
    private var tint: Color { usageTint(used: used) }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .firstTextBaseline) {
                Text(title).font(.caption.weight(.medium))
                Text(subtitle).font(.caption2).foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(window.remaining.rounded()))% left")
                    .font(.caption.weight(.semibold).monospacedDigit())
                    .foregroundStyle(tint)
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary).frame(height: 7)
                    Capsule().fill(tint.gradient)
                        .frame(width: max(5, geo.size.width * used / 100), height: 7)
                }
            }
            .frame(height: 7)
            HStack {
                Text("\(Int(used.rounded()))% used").font(.caption2).foregroundStyle(.secondary)
                Spacer()
                if let reset = window.resetsAt {
                    Text(resetText(reset)).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
    }
}
