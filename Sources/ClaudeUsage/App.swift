import SwiftUI
import AppKit
import ClaudeUsageKit

// opening the repo folder in Xcode opens THIS package (via .swiftpm/xcode), and picking an
// iPhone destination then tries to build the menu-bar app for iOS — which surfaces as
// "No such module 'AppKit'" or a deployment-target mismatch on ClaudeUsageKit. say so.
#if !os(macOS)
#error("This is the macOS menu-bar app. For iPhone open ios/ClaudeUsage.xcodeproj instead.")
#endif

@main
struct ClaudeUsageApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @State private var store = UsageStore()

    var body: some Scene {
        MenuBarExtra {
            PanelView()
                .environment(store)
                .onAppear { delegate.attach(store) }
        } label: {
            MenuBarLabel(store: store)
        }
        .menuBarExtraStyle(.window)
    }
}

// menu bar label. MenuBarExtra clips a live multi-line View to one text line, so we
// rasterise the layout with ImageRenderer and hand it over as a template image — which it
// scales to fit the bar height, so both lines of a two-account readout survive.
struct MenuBarLabel: View {
    var store: UsageStore

    var body: some View {
        // read the observable state HERE (not inside ImageRenderer) so the label re-renders
        // when usage loads — reads buried in the renderer don't register as dependencies.
        let items = store.menuBarItems
        let worst = store.worstUsed
        let show = store.showPercentInMenuBar
        return Image(nsImage: render(items: items, worst: worst, show: show))
    }

    @MainActor private func render(items: [(initial: String, used: Double?)], worst: Double?, show: Bool) -> NSImage {
        let content = MenuBarContent(items: items, worst: worst, show: show)
        let renderer = ImageRenderer(content: content)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        let img = renderer.nsImage ?? NSImage(systemSymbolName: "speedometer", accessibilityDescription: "usage") ?? NSImage()
        img.isTemplate = true   // let the menu bar tint it for light/dark
        return img
    }
}

// the actual layout that gets rasterised. plain values in, no store access — that lives in
// MenuBarLabel.body so dependency tracking works.
private struct MenuBarContent: View {
    let items: [(initial: String, used: Double?)]
    let worst: Double?
    let show: Bool

    private func pct(_ used: Double?) -> String {
        used.map { "\(Int($0.rounded()))%" } ?? "—"
    }

    var body: some View {
        HStack(spacing: 3) {
            Image(nsImage: gaugeGlyph).interpolation(.high)   // matches the app icon's gauge
            if show {
                if items.count == 2 {
                    // two accounts → stack both, one per line, tagged by initial
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                            Text("\(item.initial) \(pct(item.used))")
                                .font(.system(size: 9, weight: .semibold).monospacedDigit())
                        }
                    }
                } else if let worst {
                    Text(pct(worst))
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                }
            }
        }
        .foregroundStyle(.black)   // template image tints by alpha; colour is irrelevant
        .padding(.vertical, 1)
    }
}

// menu-bar gauge glyph — same silhouette as the app icon (280° arc, gap at the bottom),
// drawn monochrome so the bar can tint it. NSImage(flipped:) is resolution-independent, so
// this stays crisp when ImageRenderer rasterises the label at 2x. coords are y-up here.
@MainActor private let gaugeGlyph: NSImage = {
    let side: CGFloat = 15
    let img = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
        guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
        let s = rect.width
        let center = CGPoint(x: s / 2, y: s / 2)
        let lw = s * 0.14
        let r = s / 2 - lw / 2 - s * 0.03
        func deg(_ d: CGFloat) -> CGFloat { d * .pi / 180 }
        ctx.setStrokeColor(NSColor.black.cgColor)   // template tints by alpha; colour irrelevant
        ctx.setLineCap(.round)
        ctx.setLineWidth(lw)
        ctx.addArc(center: center, radius: r, startAngle: deg(230), endAngle: deg(310), clockwise: true)
        ctx.strokePath()
        return true
    }
    img.isTemplate = true
    return img
}()

final class AppDelegate: NSObject, NSApplicationDelegate {
    private weak var store: UsageStore?
    private var started = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)  // menu-bar only, no dock icon
    }

    // kick off polling once the scene wires up the store
    @MainActor func attach(_ store: UsageStore) {
        self.store = store
        guard !started else { return }
        started = true
        store.start()
    }
}
