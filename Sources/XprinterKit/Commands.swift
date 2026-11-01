import Foundation

/// TSPL commands for Xprinter label printers. Every command here was checked on an XP-420B
/// (firmware 1.040.3552) by writing a value and reading it back from ALLCONFIG.
public enum XprinterCommand {
    static let end = "XPSETUP-END"  // our own marker that ends a reply
    static func cmd(_ s: String) -> Data { Data((s + "\r\n").utf8) }

    /// Joins a Wi-Fi network (STA mode, address via DHCP) and restarts the Wi-Fi module.
    public static func connectWiFi(ssid: String, password: String) -> Data {
        cmd("WIFI CONNECTION \"\(ssid)\",\"\(password)\"\r\nWIFI RESET")
    }

    /// Full printer configuration as "Key: Value" lines.
    public static let readConfig = cmd("ALLCONFIG\r\nOUT \"\(end)\"")
    /// Printer address in the Wi-Fi network, reply "+OK=a.b.c.d".
    public static let readWiFiIP = cmd("WIFI GETIP\r\nOUT \"\(end)\"")
    public static let selfTest = cmd("SELFTEST")

    /// Feeds 2-3 labels without printing, measures label and gap length and switches the sensor to gap labels.
    /// Same command as the vendor tool's "Calibrate Sensor" for labels with gaps.
    public static let calibrateGapLabels = cmd("GAPDETECT")

    /// Switches the sensor to continuous paper. No feed. The printer keeps the measured label and gap length.
    public static let continuousPaper = cmd("GAP 0,0")

    /// Back to labels with gaps without feeding, using the gap the printer measured before (in dots).
    /// Millimetres get rounded by the printer (1.6 mm → 12.8 dots), so dots are used.
    public static func gapLabels(gapDots: Double, offsetDots: Double) -> Data {
        cmd("GAP \(Int(gapDots.rounded())) dot,\(Int(offsetDots.rounded())) dot")
    }

    /// Immediate status query (answered even while the printer is busy): one byte, see `PrinterStatus`.
    public static let status = Data([27, 33, 63])

    /// Restarts only the Wi-Fi module; it rejoins the saved network in a few seconds. Settings are kept.
    public static let restartWiFi = cmd("WIFI RESET")

    /// Soft restart of the whole printer, the same bytes as "Reset Printer" in the vendor's tool:
    /// ESC ! exit, then the immediate command ESC ! R, which runs even when the printer is stuck.
    /// Settings are kept (checked on an XP-420B). Never confuse it with ESC ! C — that is FACTORY RESET.
    public static let restartPrinter = Data([27, 33]) + Data("exit\r\n".utf8) + Data([27, 33, 82])

    public static func density(_ n: Int) -> Data { cmd("DENSITY \(min(max(n, 0), 15))") }
    public static func speed(_ n: Int) -> Data { cmd("SPEED \(min(max(n, 2), 6))") }
    public static func direction(rotated: Bool, mirrored: Bool) -> Data { cmd("DIRECTION \(rotated ? 1 : 0),\(mirrored ? 1 : 0)") }
    public static func reprint(_ on: Bool) -> Data { cmd("SET REPRINT \(on ? "ON" : "OFF")") }
    /// Extra feed after printing, in dots (8 dots = 1 mm at 203 dpi).
    public static func offset(_ dots: Int) -> Data { cmd("OFFSET \(dots) dot") }
    public static func shift(x: Int, y: Int) -> Data { cmd("SHIFT \(x),\(y)") }
    public static func reference(x: Int, y: Int) -> Data { cmd("REFERENCE \(x),\(y)") }

    /// Factory password of the printer's own network.
    public static let defaultAccessPointPassword = "12345678"

    /// Sets the password of the printer's own network (it keeps its name) and restarts the Wi-Fi module.
    /// Security 3 = WPA2: checked on an XP-420B by scanning the network (2 gives old WPA). 0 and 1 are never used.
    public static func setAccessPoint(name: String, password: String) -> Data {
        cmd("WIFI SETAP \"\(name)\",3,\"\(password)\"\r\nWIFI RESET")
    }

    /// WPA2 password rules plus TSPL's "no double quote".
    public static func isValidAccessPointPassword(_ p: String) -> Bool {
        (8...63).contains(p.count) && p.allSatisfy { $0.isASCII && !$0.isNewline && $0 != "\"" }
    }

    public enum ValidationError: Error, Equatable {
        case emptySSID, quoteInSSID, quoteInPassword, shortPassword
    }

    /// TSPL strings have no escaping, so a double quote would break the command.
    public static func validate(ssid: String, password: String) throws {
        if ssid.isEmpty { throw ValidationError.emptySSID }
        if ssid.contains("\"") { throw ValidationError.quoteInSSID }
        if password.contains("\"") { throw ValidationError.quoteInPassword }
        if !password.isEmpty && password.count < 8 { throw ValidationError.shortPassword }  // WPA minimum
    }
}

/// How the app reaches the printer.
public enum PrinterLink: Equatable, Sendable {
    case usb
    case network(String)  // IPv4 address, TCP port 9100
}

/// High-level operations over USB or Wi-Fi.
public enum Xprinter {
    /// One exchange at a time: the printer runs commands in order, and its Wi-Fi module
    /// hangs when several connections or queries overlap.
    static let lock = NSLock()

    static func exchange(_ link: PrinterLink, _ data: Data, until end: String? = nil, timeout: TimeInterval = 3) throws -> String {
        lock.lock(); defer { lock.unlock() }
        switch link {
        case .usb: return try USBPrinter.exchange(data, until: end, timeout: timeout)
        case .network(let host): return try NetworkPrinter.exchange(host: host, data, until: end, timeout: timeout)
        }
    }

    public static func send(_ data: Data, via link: PrinterLink) throws { _ = try exchange(link, data) }

    /// Printer status over USB (over Wi-Fi every reply costs, see NetworkPrinter).
    public static func status() throws -> PrinterStatus? {
        lock.lock(); defer { lock.unlock() }
        return try USBPrinter.exchangeData(XprinterCommand.status, minBytes: 1, timeout: 1).last.map { PrinterStatus(rawValue: $0) }
    }

    public static func config(via link: PrinterLink = .usb) throws -> PrinterConfig {
        PrinterConfig(report: try exchange(link, XprinterCommand.readConfig, until: XprinterCommand.end, timeout: 6))
    }

    /// The printer's Wi-Fi address, or nil while it is not connected.
    public static func wifiIP(via link: PrinterLink = .usb) throws -> String? {
        let reply = try exchange(link, XprinterCommand.readWiFiIP, until: XprinterCommand.end)
        return PrinterConfig.okValue(reply).flatMap { $0 == "0.0.0.0" ? nil : $0 }
    }
}
