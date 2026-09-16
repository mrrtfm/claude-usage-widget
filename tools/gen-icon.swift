// draws the ClaudeUsage app icon at a given pixel size -> png. pure CoreGraphics, no deps.
// a coral squircle + cream usage-gauge arc (~68% filled, gap at bottom).
// usage: swift gen-icon.swift <size> <out.png> [dot]
//
// regen ../AppIcon.icns:
//   set -e; mkdir -p AppIcon.iconset
//   for pair in 16:16x16 32:16x16@2x 32:32x32 64:32x32@2x 128:128x128 \
//               256:128x128@2x 256:256x256 512:256x256@2x 512:512x512 1024:512x512@2x; do
//     swift gen-icon.swift "${pair%%:*}" "AppIcon.iconset/icon_${pair##*:}.png"; done
//   iconutil -c icns AppIcon.iconset -o ../AppIcon.icns && rm -rf AppIcon.iconset
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

let size = CGFloat(Int(CommandLine.arguments[1]) ?? 1024)
let outPath = CommandLine.arguments[2]

let cs = CGColorSpaceCreateDeviceRGB()
guard let ctx = CGContext(data: nil, width: Int(size), height: Int(size),
                          bitsPerComponent: 8, bytesPerRow: 0, space: cs,
                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    fatalError("no ctx")
}
ctx.setAllowsAntialiasing(true)
ctx.interpolationQuality = .high

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: cs, components: [r/255, g/255, b/255, a])!
}

let s = size

// --- squircle background (apple-ish grid: ~824/1024 shape, corner ~0.2246 of shape) ---
let margin = s * (100.0/1024.0)
let rectSize = s - margin*2
let corner = rectSize * 0.2246
let bgRect = CGRect(x: margin, y: margin, width: rectSize, height: rectSize)
let bgPath = CGPath(roundedRect: bgRect, cornerWidth: corner, cornerHeight: corner, transform: nil)

// coral gradient, top -> bottom (y-up: top is high y)
ctx.saveGState()
ctx.addPath(bgPath)
ctx.clip()
let grad = CGGradient(colorsSpace: cs,
    colors: [rgb(228,140,104), rgb(190,90,56)] as CFArray,
    locations: [0, 1])!
ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: s), end: CGPoint(x: 0, y: 0), options: [])

// soft top highlight for depth
let hl = CGGradient(colorsSpace: cs,
    colors: [rgb(255,255,255,0.16), rgb(255,255,255,0)] as CFArray,
    locations: [0, 1])!
ctx.drawLinearGradient(hl, start: CGPoint(x: 0, y: s), end: CGPoint(x: 0, y: s*0.45), options: [])
ctx.restoreGState()

// hairline inner stroke for crisp edge definition
ctx.saveGState()
ctx.addPath(bgPath)
ctx.setStrokeColor(rgb(0,0,0,0.10))
ctx.setLineWidth(max(1, s*0.004))
ctx.strokePath()
ctx.restoreGState()

// --- usage gauge ---
let center = CGPoint(x: s/2, y: s/2)
let R = s * 0.285
let lw = s * 0.10
let cream = rgb(251,238,226)

func deg(_ d: CGFloat) -> CGFloat { d * .pi / 180 }

// track: 280° arc, 80° gap centered at bottom. y-up, clockwise the long way.
ctx.setLineCap(.round)
ctx.setLineWidth(lw)
ctx.beginPath()
ctx.addArc(center: center, radius: R, startAngle: deg(230), endAngle: deg(310), clockwise: true)
ctx.setStrokeColor(rgb(255,255,255,0.28))
ctx.strokePath()

// progress: 68% of the 280° sweep, fills from bottom-left clockwise
let fill: CGFloat = 0.68
let endAngle = 230 - fill*280
ctx.beginPath()
ctx.addArc(center: center, radius: R, startAngle: deg(230), endAngle: deg(endAngle), clockwise: true)
ctx.setStrokeColor(cream)
ctx.strokePath()

// tick mark at the progress head (little dot) — subtle, only at larger sizes
let showDot = CommandLine.arguments.count > 3 && CommandLine.arguments[3] == "dot"
if showDot && s >= 64 {
    let a = deg(endAngle)
    let hx = center.x + cos(a)*R
    let hy = center.y + sin(a)*R
    ctx.setFillColor(rgb(190,90,56))
    ctx.fillEllipse(in: CGRect(x: hx - lw*0.16, y: hy - lw*0.16, width: lw*0.32, height: lw*0.32))
}

guard let img = ctx.makeImage() else { fatalError("no img") }
let url = URL(fileURLWithPath: outPath)
guard let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil) else {
    fatalError("no dest")
}
CGImageDestinationAddImage(dest, img, nil)
CGImageDestinationFinalize(dest)
