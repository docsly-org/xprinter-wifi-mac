// Draws the app icon and writes AppIcon.icns.  Usage: swift tools/make-icon.swift <out-dir>
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : ".")

func draw(_ px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = CGFloat(px) / 1024  // design on a 1024 grid
    func r(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat) -> NSRect { NSRect(x: x * s, y: y * s, width: w * s, height: h * s) }

    // macOS icon grid: 824x824 rounded square centred, with a soft shadow
    let tile = NSBezierPath(roundedRect: r(100, 100, 824, 824), xRadius: 185 * s, yRadius: 185 * s)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.3)
    shadow.shadowBlurRadius = 28 * s
    shadow.shadowOffset = NSSize(width: 0, height: -12 * s)
    shadow.set()
    NSColor.white.setFill(); tile.fill()
    NSGraphicsContext.restoreGraphicsState()
    NSGradient(starting: NSColor(srgbRed: 0.30, green: 0.66, blue: 1.00, alpha: 1),
               ending: NSColor(srgbRed: 0.04, green: 0.37, blue: 0.93, alpha: 1))!.draw(in: tile, angle: -90)

    // Wi-Fi arcs above the printer
    let c = NSPoint(x: 512 * s, y: 560 * s)
    NSColor.white.setStroke()
    for (radius, alpha) in [(110.0, 1.0), (185.0, 0.85), (260.0, 0.7)] as [(CGFloat, CGFloat)] {
        let arc = NSBezierPath()
        arc.appendArc(withCenter: c, radius: radius * s, startAngle: 50, endAngle: 130)
        arc.lineWidth = 44 * s; arc.lineCapStyle = .round
        NSColor.white.withAlphaComponent(alpha).setStroke(); arc.stroke()
    }
    NSColor.white.setFill()
    NSBezierPath(ovalIn: r(512 - 34, 560 - 34 + 30, 68, 68)).fill()

    // Label printer body
    NSColor.white.setFill()
    NSBezierPath(roundedRect: r(262, 250, 500, 230), xRadius: 56 * s, yRadius: 56 * s).fill()
    // paper slot and label coming out
    NSColor(srgbRed: 0.08, green: 0.42, blue: 0.95, alpha: 1).setFill()
    NSBezierPath(roundedRect: r(342, 330, 340, 22), xRadius: 11 * s, yRadius: 11 * s).fill()
    NSColor.white.setFill()
    NSBezierPath(roundedRect: r(372, 170, 280, 170), xRadius: 22 * s, yRadius: 22 * s).fill()
    // barcode on the label
    NSColor(srgbRed: 0.08, green: 0.42, blue: 0.95, alpha: 0.85).setFill()
    var x: CGFloat = 410
    for w in [10, 6, 14, 6, 8, 16, 6, 10, 6, 14, 8, 6, 12] as [CGFloat] {
        NSBezierPath(rect: r(x, 200, w, 80)).fill()
        x += w + 8
    }
    // status light
    NSColor(srgbRed: 0.20, green: 0.80, blue: 0.45, alpha: 1).setFill()
    NSBezierPath(ovalIn: r(690, 400, 36, 36)).fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let iconset = out.appendingPathComponent("AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    try! draw(size).write(to: iconset.appendingPathComponent("icon_\(size)x\(size).png"))
    try! draw(size * 2).write(to: iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
let p = Process()
p.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
p.arguments = ["-c", "icns", iconset.path, "-o", out.appendingPathComponent("AppIcon.icns").path]
try! p.run(); p.waitUntilExit()
try! FileManager.default.removeItem(at: iconset)
try! draw(1024).write(to: out.appendingPathComponent("AppIcon.png"))  // preview for README
