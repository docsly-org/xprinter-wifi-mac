import Foundation

/// Finds Xprinter network printers with the vendor's UDP broadcast (port 22368).
/// Only Xprinter network modules answer it, so other printers never receive print data.
public enum Discovery {
    public struct Found: Equatable, Sendable {
        public let ip: String
        public let name: String
    }

    static let port: UInt16 = 22368
    static let request: [UInt8] = [0, 32, 0, 1, 0, 1, 8, 0, 0, 2, 0, 0, 0, 6, 0, 0, 1, 0, 0, 0,
                                   0, 0, 255, 255, 255, 255, 255, 255, 0, 0, 0, 0]

    /// Reply layout (seen from an XP-420B): MAC at 22, IPv4 at 44, model name (NUL-padded) at 52.
    public static func parse(_ reply: [UInt8]) -> Found? {
        guard reply.count >= 84, reply[0...1] == request[0...1] else { return nil }
        let ip = reply[44..<48].map(String.init).joined(separator: ".")
        let name = String(decoding: reply[52..<84].prefix { $0 != 0 }, as: UTF8.self)
        return ip == "0.0.0.0" ? nil : Found(ip: ip, name: name)
    }

    public static func search(timeout: TimeInterval = 2) -> [Found] {
        let fd = socket(AF_INET, SOCK_DGRAM, 0)
        guard fd >= 0 else { return [] }
        defer { close(fd) }
        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &one, socklen_t(MemoryLayout<Int32>.size))
        var tv = timeval(tv_sec: 0, tv_usec: 300_000)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        var to = sockaddr_in()
        to.sin_family = sa_family_t(AF_INET)
        to.sin_port = port.bigEndian
        to.sin_addr.s_addr = INADDR_BROADCAST
        let sent = withUnsafePointer(to: &to) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                sendto(fd, request, request.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard sent == request.count else { return [] }

        var found: [Found] = []
        var buf = [UInt8](repeating: 0, count: 2048)
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let n = recv(fd, &buf, buf.count, 0)
            if n > 0, let f = parse(Array(buf[0..<n])), !found.contains(f) { found.append(f) }
        }
        return found
    }
}
