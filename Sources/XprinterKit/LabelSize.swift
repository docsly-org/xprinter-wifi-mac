import Foundation

/// The default label size of a macOS printer, stored in its PPD as an extra page size ("XPSetupLabel").
/// macOS has no UI for a per-printer custom default size, and apps start from the PPD default.
public enum LabelSize {
    static let key = "XPSetupLabel"
    public static let widthRange = 10.0...108.0   // XP-420B print width: 108 mm
    public static let heightRange = 10.0...1000.0

    static func points(_ mm: Double) -> String { String(format: "%.2f", mm * 72 / 25.4) }
    static func mm(_ points: Double) -> Double { (points * 25.4 / 72 * 10).rounded() / 10 }
    static func label(_ mm: Double) -> String { mm == mm.rounded() ? String(Int(mm)) : String(format: "%.1f", mm) }

    /// Default size in mm, read from the PPD's default page size and its PaperDimension.
    public static func read(ppd: String) -> (width: Double, height: Double)? {
        let lines = ppd.components(separatedBy: "\n")
        guard let name = lines.first(where: { $0.hasPrefix("*DefaultPageSize:") })?
                .dropFirst("*DefaultPageSize:".count).trimmingCharacters(in: .whitespacesAndNewlines),
              let dim = lines.first(where: { $0.hasPrefix("*PaperDimension \(name)/") || $0.hasPrefix("*PaperDimension \(name):") }),
              let quoted = dim.split(separator: "\"").dropFirst().first else { return nil }
        let n = quoted.split(separator: " ").compactMap { Double($0) }
        guard n.count == 2 else { return nil }
        return (mm(n[0]), mm(n[1]))
    }

    /// The PPD with our size added (replacing an earlier one) and made the default.
    public static func apply(ppd: String, width: Double, height: Double) -> String {
        let w = points(width), h = points(height)
        let title = "\(key)/\(label(width)) x \(label(height)) mm"
        let device = "\"<</PageSize[\(w) \(h)]/ImagingBBox null>>setpagedevice\""
        var out: [String] = []
        var addedArea = false, addedDim = false
        let ours = ["PageSize", "PageRegion", "ImageableArea", "PaperDimension"].map { "*\($0) \(key)" }
        for line in ppd.components(separatedBy: "\n") where !ours.contains(where: line.hasPrefix) {
            if line.hasPrefix("*DefaultPageSize:") {
                out += ["*DefaultPageSize: \(key)", "*PageSize \(title): \(device)"]
            } else if line.hasPrefix("*DefaultPageRegion:") {
                out += ["*DefaultPageRegion: \(key)", "*PageRegion \(title): \(device)"]
            } else if line.hasPrefix("*DefaultImageableArea:") {
                out.append("*DefaultImageableArea: \(key)")
            } else if line.hasPrefix("*DefaultPaperDimension:") {
                out.append("*DefaultPaperDimension: \(key)")
            } else {
                if line.hasPrefix("*ImageableArea "), !addedArea { out.append("*ImageableArea \(title): \"0 0 \(w) \(h)\""); addedArea = true }
                if line.hasPrefix("*PaperDimension "), !addedDim { out.append("*PaperDimension \(title): \"\(w) \(h)\""); addedDim = true }
                out.append(line)
            }
        }
        return out.joined(separator: "\n")
    }
}

extension CUPS {
    /// Xprinter printers in macOS (USB and Wi-Fi): they share the roll, so they share the label size.
    public static func xprinterQueues() -> [PrinterQueue] {
        queues().filter { $0.name.hasPrefix("Xprinter") || $0.uri.localizedCaseInsensitiveContains("xprinter") }
    }

    public static func labelSize(queue: String) -> (width: Double, height: Double)? {
        (try? String(contentsOfFile: "/etc/cups/ppd/\(queue).ppd", encoding: .isoLatin1)).flatMap(LabelSize.read)
    }

    /// Makes `width` x `height` mm the default paper of every Xprinter printer in macOS.
    public static func setLabelSize(width: Double, height: Double) throws {
        for q in xprinterQueues() {
            let path = "/etc/cups/ppd/\(q.name).ppd"
            guard let ppd = try? String(contentsOfFile: path, encoding: .isoLatin1) else { continue }
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("\(q.name)-\(UUID().uuidString).ppd")
            try LabelSize.apply(ppd: ppd, width: width, height: height).write(to: tmp, atomically: true, encoding: .isoLatin1)
            defer { try? FileManager.default.removeItem(at: tmp) }
            try run("/usr/sbin/lpadmin", ["-p", q.name, "-P", tmp.path])
        }
    }
}
