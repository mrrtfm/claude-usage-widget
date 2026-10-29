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
// rasterise the layout with ImageRenderer and hand it over as a template image. the raster
// is pinned to the bar's thickness and whole points, and carries a 1x and a 2x rep — see
// render() for why each of those matters.
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

    // three traps, all of which read as "blurry numbers":
    //   • NSScreen.main is whichever screen has focus, so rendering at its scale puts a 1x
    //     bitmap on the retina bar whenever an external 1x monitor was active. ship a 1x and
    //     a 2x rep in one NSImage instead and let AppKit pick per screen.
    //   • the bar is NSStatusBar.thickness tall (22pt). anything taller — the two-line
    //     readout was 24pt — gets resampled to fit. pin the height.
    //   • text widths are fractional (43.5pt), which lands glyphs half a pixel off the grid
    //     on 1x screens. measure first, then re-render at the width rounded up.
    @MainActor private func render(items: [(initial: String, used: Double?)], worst: Double?, show: Bool) -> NSImage {
        let fallback = NSImage(systemSymbolName: "speedometer", accessibilityDescription: "usage") ?? NSImage()
        let height = NSStatusBar.system.thickness
        let content = MenuBarContent(items: items, worst: worst, show: show)

        // pass 1 — measure. cgImage at scale 1 is already ceil'd to whole px == whole points.
        let probe = ImageRenderer(content: content.frame(height: height))
        probe.scale = 1
        guard let measured = probe.cgImage else { return fallback }
        let size = NSSize(width: CGFloat(measured.width), height: height)

        // pass 2 — rasterise at the rounded size, once per scale the screens may ask for.
        let renderer = ImageRenderer(content: content.frame(width: size.width, height: size.height))
        let img = NSImage(size: size)
        for scale in [1.0, 2.0] as [CGFloat] {
            renderer.scale = scale
            guard let cg = renderer.cgImage else { continue }
            let rep = NSBitmapImageRep(cgImage: cg)
            rep.size = size   // same point size for both reps — that's what makes them 1x/2x of one image
            img.addRepresentation(rep)
        }
        guard !img.representations.isEmpty else { return fallback }
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
        // no vertical padding: two 9pt lines are exactly the bar's 22pt, padding would push
        // the raster past it and get the whole thing resampled
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
