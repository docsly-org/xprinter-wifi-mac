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

    public static func density(_ n: Int) -> Data { cmd("DENSITY \(min(max(n, 0), 15))") }
    public static func speed(_ n: Int) -> Data { cmd("SPEED \(min(max(n, 2), 6))") }
    public static func direction(rotated: Bool, mirrored: Bool) -> Data { cmd("DIRECTION \(rotated ? 1 : 0),\(mirrored ? 1 : 0)") }
    public static func reprint(_ on: Bool) -> Data { cmd("SET REPRINT \(on ? "ON" : "OFF")") }
    /// Extra feed after printing, in dots (8 dots = 1 mm at 203 dpi).
    public static func offset(_ dots: Int) -> Data { cmd("OFFSET \(dots) dot") }
    public static func shift(x: Int, y: Int) -> Data { cmd("SHIFT \(x),\(y)") }
    public static func reference(x: Int, y: Int) -> Data { cmd("REFERENCE \(x),\(y)") }

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
    static func exchange(_ link: PrinterLink, _ data: Data, until end: String? = nil, timeout: TimeInterval = 3) throws -> String {
        switch link {
        case .usb: try USBPrinter.exchange(data, until: end, timeout: timeout)
        case .network(let host): try NetworkPrinter.exchange(host: host, data, until: end, timeout: timeout)
        }
    }

    public static func send(_ data: Data, via link: PrinterLink) throws { _ = try exchange(link, data) }

    public static func config(via link: PrinterLink = .usb) throws -> PrinterConfig {
        PrinterConfig(report: try exchange(link, XprinterCommand.readConfig, until: XprinterCommand.end, timeout: 6))
    }

    /// The printer's Wi-Fi address, or nil while it is not connected.
    public static func wifiIP(via link: PrinterLink = .usb) throws -> String? {
        let reply = try exchange(link, XprinterCommand.readWiFiIP, until: XprinterCommand.end)
        return PrinterConfig.okValue(reply).flatMap { $0 == "0.0.0.0" ? nil : $0 }
    }
}
