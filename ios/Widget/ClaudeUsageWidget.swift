import WidgetKit
import SwiftUI
import ClaudeUsageKit

// MARK: - timeline

struct UsageEntry: TimelineEntry {
    var date: Date
    var payload: WidgetPayload
    var stale: Bool          // drawn from the app's last handoff rather than a live fetch
    var unconfigured: Bool   // no app group / keychain group — nothing to show, ever
}

struct Provider: TimelineProvider {
    // how long between refreshes. widgets get a limited daily budget, so 20 min is about as
    // tight as it's worth asking for.
    private let cadence: TimeInterval = 20 * 60

    func placeholder(in context: Context) -> UsageEntry {
        UsageEntry(date: Date(), payload: .preview, stale: false, unconfigured: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (UsageEntry) -> Void) {
        if context.isPreview {
            completion(UsageEntry(date: Date(), payload: .preview, stale: false, unconfigured: false))
        } else {
            Task { completion(await entry()) }
        }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<UsageEntry>) -> Void) {
        Task {
            let e = await entry()
            completion(Timeline(entries: [e], policy: .after(Date().addingTimeInterval(cadence))))
        }
    }

    // prefer a live fetch with the shared-keychain sessions; fall back to whatever the app
    // last left in the app group. both need a paid-team capability, hence `unconfigured`.
    private func entry() async -> UsageEntry {
        AppConfig.bootstrap()
        let accounts = KeychainStore.load()

        if !accounts.isEmpty {
            var rows: [WidgetPayload.Row] = []
            for a in accounts {
                let snap = try? await ClaudeAPI.fetchUsage(orgUuid: a.orgUuid, cookies: a.cookies, userAgent: a.userAgent)
                rows.append(WidgetPayload.Row(
                    id: a.id, initial: a.initial,
                    name: a.name.isEmpty ? a.email : a.name,
                    planLabel: a.displayPlan.label,
                    sessionUsed: snap?.session?.used, sessionResets: snap?.session?.resetsAt,
                    weeklyUsed: snap?.weeklyAll?.used, weeklyResets: snap?.weeklyAll?.resetsAt,
                    extra: snap?.extra))
            }
            return UsageEntry(date: Date(), payload: WidgetPayload(rows: rows), stale: false, unconfigured: false)
        }

        if let cached = SharedStore.load() {
            return UsageEntry(date: Date(), payload: cached, stale: true, unconfigured: false)
        }
        let nothingWired = !SharedStore.isConfigured && KeychainStore.accessGroup == nil
        return UsageEntry(date: Date(), payload: WidgetPayload(rows: []), stale: false, unconfigured: nothingWired)
    }
}

// MARK: - views

struct ClaudeUsageWidgetView: View {
    @Environment(\.widgetFamily) private var family
    var entry: UsageEntry

    // worst-case account drives every compact family — the tightest limit is the one that
    // actually bites.
    private var worst: WidgetPayload.Row? {
        entry.payload.rows.max { ($0.sessionUsed ?? -1) < ($1.sessionUsed ?? -1) }
    }

    var body: some View {
        content.containerBackground(.fill.tertiary, for: .widget)
    }

    @ViewBuilder private var content: some View {
        if entry.unconfigured {
            unconfiguredView
        } else if entry.payload.rows.isEmpty {
            Text("Open Claude Usage to sign in")
                .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
        } else {
            switch family {
            case .accessoryCircular:    circular
            case .accessoryRectangular: rectangular
            case .systemMedium, .systemLarge: medium
            default:                    small
            }
        }
    }

    private var unconfiguredView: some View {
        VStack(spacing: 4) {
            Image(systemName: "lock.badge.exclamationmark").foregroundStyle(.secondary)
            Text("Needs an app group").font(.caption2.weight(.semibold))
            Text("paid dev account").font(.caption2).foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
    }

    // MARK: families

    private var small: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Claude").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
            if let r = worst {
                Text(pctLeft(r.sessionUsed))
                    .font(.system(size: 34, weight: .semibold).monospacedDigit())
                    .foregroundStyle(usageTint(used: r.sessionUsed ?? 0))
                Text("session left").font(.caption2).foregroundStyle(.secondary)
                Spacer(minLength: 0)
                if let reset = r.sessionResets {
                    Text(resetText(reset)).font(.caption2).foregroundStyle(.tertiary).lineLimit(1)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var medium: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(entry.payload.rows.prefix(3)) { r in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(r.initial)
                            .font(.caption2.weight(.bold)).foregroundStyle(.white)
                            .frame(width: 18, height: 18)
                            .background(.tint, in: Circle())
                        Text(r.name).font(.caption.weight(.medium)).lineLimit(1)
                        Spacer()
                        Text(pctLeft(r.sessionUsed))
                            .font(.caption.weight(.semibold).monospacedDigit())
                            .foregroundStyle(usageTint(used: r.sessionUsed ?? 0))
                    }
                    bar(r.sessionUsed)
                }
            }
            Spacer(minLength: 0)
        }
    }

    private var circular: some View {
        Gauge(value: (worst?.sessionUsed ?? 0) / 100) {
            Image(systemName: "gauge.with.dots.needle.67percent")
        } currentValueLabel: {
            Text("\(Int((worst?.sessionUsed.map { 100 - $0 } ?? 0).rounded()))")
                .monospacedDigit()
        }
        .gaugeStyle(.accessoryCircular)
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("Claude usage").font(.caption2.weight(.semibold))
            if let r = worst {
                Text("\(pctLeft(r.sessionUsed)) session").font(.caption.monospacedDigit())
                if let reset = r.sessionResets {
                    Text(resetText(reset)).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
    }

    // MARK: bits

    private func bar(_ used: Double?) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary).frame(height: 5)
                Capsule().fill(usageTint(used: used ?? 0))
                    .frame(width: max(4, geo.size.width * (used ?? 0) / 100), height: 5)
            }
        }
        .frame(height: 5)
    }

    private func pctLeft(_ used: Double?) -> String {
        used.map { "\(Int((100 - $0).rounded()))%" } ?? "—"
    }
}

// MARK: - widget

struct ClaudeUsageWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "ClaudeUsageWidget", provider: Provider()) { entry in
            ClaudeUsageWidgetView(entry: entry)
        }
        .configurationDisplayName("Claude Usage")
        .description("Session and weekly limits left, per account.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryCircular, .accessoryRectangular])
    }
}

@main
struct ClaudeUsageWidgetBundle: WidgetBundle {
    var body: some Widget { ClaudeUsageWidget() }
}

private extension WidgetPayload {
    // gallery/placeholder sample — never shown once real data lands
    static var preview: WidgetPayload {
        WidgetPayload(rows: [
            .init(id: "1", initial: "A", name: "Alex", planLabel: "Max 20×",
                  sessionUsed: 34, sessionResets: Date().addingTimeInterval(3 * 3600),
                  weeklyUsed: 61, weeklyResets: Date().addingTimeInterval(4 * 86400))
        ])
    }
}
