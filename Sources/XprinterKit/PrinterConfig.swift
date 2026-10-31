import Foundation

/// Parsed ALLCONFIG report ("Key: Value" per line).
public struct PrinterConfig: Equatable {
    public let values: [String: String]
    public let model: String?
    public let firmware: String?

    public init(report: String) {
        var values: [String: String] = [:]
        var model: String?, firmware: String?
        for line in report.split(whereSeparator: \.isNewline) {
            guard let sep = line.range(of: ": ") else { continue }
            let key = line[..<sep.lowerBound].trimmingCharacters(in: .whitespaces)
            let value = line[sep.upperBound...].trimmingCharacters(in: .whitespaces)
            // first line looks like "XP-420B Version: 1.040.3552 CEZD"
            if model == nil, key.hasSuffix(" Version"), key != "Bluetooth Versions" {
                model = String(key.dropLast(" Version".count)); firmware = value
            }
            values[key] = value
        }
        self.values = values; self.model = model; self.firmware = firmware
    }

    public subscript(key: String) -> String? { values[key] }

    func int(_ key: String) -> Int? { values[key].flatMap { Int($0.prefix { $0 == "-" || $0.isNumber }) } }
    func on(_ key: String) -> Bool? { values[key].map { $0.uppercased().hasPrefix("ON") } }

    public var isValid: Bool { model != nil }
    public var density: Int? { values["Density"].flatMap(Double.init).map { Int($0) } }
    public var speed: Int? { int("Speed") }
    public var rotated: Bool? { int("Direction").map { $0 == 1 } }
    public var mirrored: Bool? { on("Mirror") }
    public var reprint: Bool? { on("Reprint") }
    public var offset: Int? { int("Offset") }
    public var shiftX: Int? { int("Shift X") }
    public var shiftY: Int? { int("Shift Y") }
    public var referenceX: Int? { int("Reference X") }
    public var referenceY: Int? { int("Reference Y") }
    public var hasWiFi: Bool { values["Wifi"]?.uppercased() == "YES" }
    public var wifiIP: String? { values["Wifi Sta Ip"].flatMap { $0 == "0.0.0.0" || $0.isEmpty ? nil : $0 } }
    public var wifiModule: String? { values["Wifi Versions"] }
    public var accessPointName: String? { values["Wifi Name"] }

    /// Value of a "+OK=value" reply.
    public static func okValue(_ reply: String) -> String? {
        guard let r = reply.range(of: "+OK=") else { return nil }
        return String(reply[r.upperBound...].prefix { !$0.isNewline })
    }
}
