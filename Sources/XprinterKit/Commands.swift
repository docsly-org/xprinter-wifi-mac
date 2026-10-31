import Foundation

/// TSPL text commands understood by Xprinter label printers with the X4 Wi-Fi module (XP-420B, XP-460B, ...).
/// These are the same commands the vendor's Windows "Diagnostic Tool" sends.
public enum XprinterCommand {
    /// Joins a Wi-Fi network (STA mode, address via DHCP) and restarts the Wi-Fi module.
    public static func connectWiFi(ssid: String, password: String) -> Data {
        Data("WIFI CONNECTION \"\(ssid)\",\"\(password)\"\r\nWIFI RESET\r\nWIFI GETIP\r\nOUT \"WIRESET\"\r\n".utf8)
    }

    /// Prints the self-test page (firmware, Wi-Fi AP/STA addresses, MACs).
    public static let selfTest = Data("SELFTEST\r\n".utf8)

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
