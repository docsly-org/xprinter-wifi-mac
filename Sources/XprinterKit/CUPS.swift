import Foundation

/// A printer queue configured in macOS (CUPS).
public struct PrinterQueue: Hashable, Identifiable {
    public let name: String
    public let uri: String
    public var id: String { name }
    public var isUSB: Bool { uri.hasPrefix("usb://") }
}

public enum CUPS {
    /// Parses `LANG=C lpstat -v` output: "device for NAME: URI".
    public static func parseQueues(_ output: String) -> [PrinterQueue] {
        output.split(separator: "\n").compactMap { line in
            guard line.hasPrefix("device for "), let colon = line.range(of: ": ") else { return nil }
            let name = line[line.index(line.startIndex, offsetBy: 11)..<colon.lowerBound]
            return PrinterQueue(name: String(name), uri: String(line[colon.upperBound...]))
        }
    }

    /// Xprinter queues connected over USB.
    public static func xprinterUSBQueues() -> [PrinterQueue] {
        let out = (try? run("/usr/bin/lpstat", ["-v"])) ?? ""
        return parseQueues(out).filter { $0.isUSB && $0.uri.localizedCaseInsensitiveContains("xprinter") }
    }

    /// Sends bytes to a queue unchanged (raw), the way a USB tool would write them.
    public static func sendRaw(_ data: Data, to queue: String) throws {
        try run("/usr/bin/lp", ["-d", queue, "-o", "raw"], input: data)
    }

    /// Adds a network (port 9100) queue that reuses the driver of the USB queue.
    public static func addNetworkQueue(from usb: PrinterQueue, ip: String) throws -> String {
        let name = usb.name + "_WiFi"
        let ppd = "/etc/cups/ppd/\(usb.name).ppd"
        var args = ["-p", name, "-D", "\(usb.name.replacingOccurrences(of: "_", with: " ")) (Wi-Fi)",
                    "-v", "socket://\(ip):9100", "-E"]
        args += FileManager.default.fileExists(atPath: ppd) ? ["-P", ppd] : ["-m", "raw"]
        try run("/usr/sbin/lpadmin", args)
        return name
    }

    public struct CommandError: LocalizedError {
        public let message: String
        public var errorDescription: String? { message }
    }

    @discardableResult
    static func run(_ tool: String, _ args: [String], input: Data? = nil) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: tool)
        p.arguments = args
        p.environment = ["LANG": "C", "LC_ALL": "C"]  // stable lpstat output for parsing
        let out = Pipe(), err = Pipe(), inp = Pipe()
        p.standardOutput = out; p.standardError = err; p.standardInput = inp
        try p.run()
        if let input { inp.fileHandleForWriting.write(input) }
        try inp.fileHandleForWriting.close()
        let stdout = out.fileHandleForReading.readDataToEndOfFile()
        let stderr = err.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard p.terminationStatus == 0 else {
            throw CommandError(message: String(decoding: stderr, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return String(decoding: stdout, as: UTF8.self)
    }
}
