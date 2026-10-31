import AppKit
import XprinterKit

/// `XprinterSetup --screenshots <dir>`: shows sample data (no USB, no network), saves PNGs of its own windows and quits.
/// Used for README screenshots without exposing anyone's real network.
enum Demo {
    static let isOn = CommandLine.arguments.contains("--screenshots")
    static var outputDir: URL {
        let args = CommandLine.arguments
        let i = args.firstIndex(of: "--screenshots").map { $0 + 1 }
        return URL(fileURLWithPath: i.flatMap { $0 < args.count ? args[$0] : nil } ?? ".")
    }

    static let config = PrinterConfig(report: """
        XP-420B Version: 1.040.3552 CEZD
        Wifi : YES
        Wifi Name: XP-420B
        Wifi Sta Ip: 192.168.1.50
        Wifi Versions: X4_V95.0.9
        Density: 8.0
        Speed: 4 Inch
        Direction: 0
        Mirror: OFF
        Reprint: ON
        Offset: 0
        Shift X: 0
        Shift Y: 0
        Reference X: 0
        Reference Y: 0
        """)
    static let networks = ["Home", "Office", "Shop Wi-Fi"]

    @MainActor
    static func capture(_ model: PrinterModel) async {
        let lang = Locale.preferredLanguages.first?.hasPrefix("ru") == true ? "ru" : "en"
        try? await Task.sleep(nanoseconds: 2_500_000_000)
        await save(window: loc("Printer Settings"), as: "settings-\(lang)")
        await save(window: loc("Xprinter Setup"), as: "setup-\(lang)")
        model.phase = .done(queue: "Xprinter XP-420B (Wi-Fi)", ip: "192.168.1.50")
        try? await Task.sleep(nanoseconds: 1_000_000_000)
        await save(window: loc("Xprinter Setup"), as: "done-\(lang)")
        NSApp.terminate(nil)
    }

    @MainActor
    static func save(window title: String, as name: String) async {
        // the theme frame includes the title bar; an app may always snapshot its own windows
        guard let w = NSApp.windows.first(where: { $0.title == title }), let view = w.contentView?.superview else {
            print("no window titled \(title); have \(NSApp.windows.map(\.title))"); return
        }
        NSApp.activate(ignoringOtherApps: true)
        w.makeKeyAndOrderFront(nil)
        w.makeFirstResponder(nil)  // no focus ring in the picture
        try? await Task.sleep(nanoseconds: 600_000_000)  // let it redraw as the active window
        view.layoutSubtreeIfNeeded(); view.display()
        // render the layer tree: cacheDisplay skips layer-backed scroll views (grouped Form)
        let scale = w.backingScaleFactor
        guard let layer = view.layer,
              let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(view.bounds.width * scale),
                                         pixelsHigh: Int(view.bounds.height * scale), bitsPerSample: 8, samplesPerPixel: 4,
                                         hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let ctx = NSGraphicsContext(bitmapImageRep: rep) else { return }
        ctx.cgContext.scaleBy(x: scale, y: scale)
        layer.render(in: ctx.cgContext)
        try? rep.representation(using: .png, properties: [:])?.write(to: outputDir.appendingPathComponent("\(name).png"))
    }
}
