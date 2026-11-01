import Foundation

/// Status byte of `ESC ! ?` (TSPL). "Cover open" was checked on an XP-420B (0x01); the other bits follow TSPL.
public struct PrinterStatus: OptionSet, Equatable, Sendable {
    public let rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }

    public static let coverOpen = PrinterStatus(rawValue: 0x01)
    public static let paperJam = PrinterStatus(rawValue: 0x02)
    public static let paperOut = PrinterStatus(rawValue: 0x04)
    public static let paused = PrinterStatus(rawValue: 0x10)
    public static let printing = PrinterStatus(rawValue: 0x20)

    public var isReady: Bool { isEmpty }
}
