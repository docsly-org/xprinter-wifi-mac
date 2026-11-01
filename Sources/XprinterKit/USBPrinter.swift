import Foundation
import IOKit
import IOUSBHost

/// Two-way talk with an Xprinter over USB (printer class), without CUPS.
/// The device is opened only for the duration of one exchange, so normal printing is not blocked.
public enum USBPrinter {
    public static let vendorID = 0x2D37  // Xprinter

    public struct NotConnected: LocalizedError {
        public init() {}
        public var errorDescription: String? { String(localized: "The printer is not connected over USB.", bundle: .module) }
    }

    public static var isConnected: Bool {
        guard let s = service() else { return false }
        IOObjectRelease(s)
        return true
    }

    /// Sends `data` and collects the reply until `terminator` appears or `timeout` passes.
    public static func exchange(_ data: Data, until terminator: String? = nil, timeout: TimeInterval = 3) throws -> String {
        let reply = try exchangeData(data, timeout: timeout) { reply in
            terminator.map { String(decoding: reply, as: UTF8.self).contains($0) } ?? true
        }
        return String(decoding: reply, as: UTF8.self)
    }

    /// Raw variant for binary replies (status byte).
    public static func exchangeData(_ data: Data, minBytes: Int, timeout: TimeInterval) throws -> Data {
        try exchangeData(data, timeout: timeout) { $0.count >= minBytes }
    }

    static func exchangeData(_ data: Data, timeout: TimeInterval, done: (Data) -> Bool) throws -> Data {
        guard let svc = service() else { throw NotConnected() }
        defer { IOObjectRelease(svc) }
        let intf = try IOUSBHostInterface(__ioService: svc, options: [], queue: nil, interestHandler: nil)
        defer { intf.destroy() }
        guard let out = pipe(intf, in: 0x01...0x0F), let inp = pipe(intf, in: 0x81...0x8F) else { throw NotConnected() }

        func read(_ wait: TimeInterval) -> Data {
            let buf = NSMutableData(length: 512)!
            var n = 0
            try? inp.__sendIORequest(with: buf, bytesTransferred: &n, completionTimeout: wait)
            return Data(bytes: buf.bytes, count: n)
        }
        while !read(0.05).isEmpty {}  // drop stale replies

        var sent = 0
        try out.__sendIORequest(with: NSMutableData(data: data), bytesTransferred: &sent, completionTimeout: 5)

        var reply = Data()
        let deadline = Date().addingTimeInterval(timeout)
        while !done(reply), Date() < deadline {
            reply += read(0.3)
        }
        return reply
    }

    public static func send(_ data: Data) throws { _ = try exchange(data) }

    static func pipe(_ intf: IOUSBHostInterface, in range: ClosedRange<Int>) -> IOUSBHostPipe? {
        range.lazy.compactMap { try? intf.copyPipe(withAddress: $0) }.first
    }

    static func service() -> io_service_t? {
        var it: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOUSBHostInterface"), &it) == KERN_SUCCESS else { return nil }
        defer { IOObjectRelease(it) }
        while case let s = IOIteratorNext(it), s != 0 {
            if prop(s, "idVendor") == vendorID && prop(s, "bInterfaceClass") == 7 { return s }  // 7 = printer class
            IOObjectRelease(s)
        }
        return nil
    }

    static func prop(_ s: io_service_t, _ key: String) -> Int? {
        IORegistryEntryCreateCFProperty(s, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue() as? Int
    }
}
