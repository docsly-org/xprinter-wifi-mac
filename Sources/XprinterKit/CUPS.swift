import Foundation

/// A printer queue configured in macOS (CUPS).
public struct PrinterQueue: Hashable {
    public let name: String
    public let uri: String
}

public enum CUPS {
    /// Parses `lpstat -v` output: "device for NAME: URI". The prefix is localized by macOS
    /// (e.g. "устройство для NAME: URI"), so only the last word before ": " is taken; queue names have no spaces.
    public static func parseQueues(_ output: String) -> [PrinterQueue] {
        output.split(separator: "\n").compactMap { line in
            guard let colon = line.range(of: ": "),
                  let name = line[..<colon.lowerBound].split(separator: " ").last else { return nil }
            return PrinterQueue(name: String(name), uri: String(line[colon.upperBound...]))
        }
    }

    public static func queues() -> [PrinterQueue] { parseQueues((try? run("/usr/bin/lpstat", ["-v"])) ?? "") }

    /// Addresses of Xprinter Wi-Fi printers added to macOS ("socket://a.b.c.d:9100").
    public static func xprinterNetworkHosts() -> [String] {
        queues().compactMap { q in
            guard q.name.hasPrefix("Xprinter"), q.uri.hasPrefix("socket://") else { return nil }
            return URL(string: q.uri)?.host
        }
    }

    /// Queue name for the Wi-Fi printer, e.g. "Xprinter_XP_420B_WiFi".
    public static func queueName(model: String) -> String {
        "Xprinter_" + model.map { $0.isLetter || $0.isNumber ? $0 : "_" } + "_WiFi"
    }

    /// Driver file for the model: from an existing USB queue, or from the installed Xprinter driver.
    public static func ppd(model: String) -> String? {
        let fm = FileManager.default
        for q in queues() where q.uri.hasPrefix("usb://") && q.uri.localizedCaseInsensitiveContains("xprinter") {
            let path = "/etc/cups/ppd/\(q.name).ppd"
            if fm.isReadableFile(atPath: path) { return path }
        }
        let dir = "/Library/Printers/PPDs/Contents/Resources"
        let needle = model.replacingOccurrences(of: "-", with: "").lowercased()
        let file = (try? fm.contentsOfDirectory(atPath: dir))?.first {
            $0.replacingOccurrences(of: "-", with: "").lowercased().contains(needle)
        }
        return file.map { "\(dir)/\($0)" }
    }

    /// Adds the Wi-Fi printer, or updates its address if it already exists. Returns the queue name.
    @discardableResult
    public static func addOrUpdateWiFiQueue(model: String, ip: String) throws -> String {
        let name = queueName(model: model)
        let uri = "socket://\(ip):9100"
        if queues().contains(where: { $0.name == name }) {
            try run("/usr/sbin/lpadmin", ["-p", name, "-v", uri, "-E"])
            return name
        }
        guard let ppd = ppd(model: model) else { throw NoDriver() }
        try run("/usr/sbin/lpadmin", ["-p", name, "-D", "Xprinter \(model) (Wi-Fi)", "-v", uri, "-P", ppd, "-E"])
        return name
    }

    public struct NoDriver: LocalizedError {
        public var errorDescription: String? {
            String(localized: "The Xprinter driver is not installed. Install it from xprintertech.com, then try again.", bundle: .module)
        }
    }

    public struct CommandError: LocalizedError {
        public let message: String
        public var errorDescription: String? { message }
    }

    @discardableResult
    static func run(_ tool: String, _ args: [String]) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        p.environment = ["LANG": "C", "LC_ALL": "C"]  // stable lpstat output for parsing
        let out = Pipe(), err = Pipe()
        p.standardOutput = out; p.standardError = err
        try p.run()
        let stdout = out.fileHandleForReading.readDataToEndOfFile()
        let stderr = err.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            throw CommandError(message: String(decoding: stderr, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return String(decoding: stdout, as: UTF8.self)
    }
}
