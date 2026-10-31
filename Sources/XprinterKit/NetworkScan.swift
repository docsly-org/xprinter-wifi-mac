import Foundation

public enum NetworkScan {
    /// All host addresses of the Mac's IPv4 subnets (only /22 and smaller, to keep the scan short).
    public static func localHosts() -> [String] {
        var result: [String] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return [] }
        defer { freeifaddrs(ifaddr) }
        for ptr in sequence(first: first, next: { $0.pointee.ifa_next }) {
            let ifa = ptr.pointee
            guard let addr = ifa.ifa_addr, addr.pointee.sa_family == UInt8(AF_INET), let mask = ifa.ifa_netmask,
                  String(cString: ifa.ifa_name).hasPrefix("en") else { continue }
            let ip = addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { UInt32(bigEndian: $0.pointee.sin_addr.s_addr) }
            let m = mask.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { UInt32(bigEndian: $0.pointee.sin_addr.s_addr) }
            result += hosts(ip: ip, mask: m).filter { $0 != format(ip) }
        }
        return result
    }

    public static func hosts(ip: UInt32, mask: UInt32) -> [String] {
        guard mask >= 0xFFFF_FC00, mask < 0xFFFF_FFFF else { return [] }
        let net = ip & mask, broadcast = net | ~mask
        return ((net + 1)..<broadcast).map(format)
    }

    public static func format(_ ip: UInt32) -> String {
        "\(ip >> 24).\((ip >> 16) & 255).\((ip >> 8) & 255).\(ip & 255)"
    }

    /// Hosts in the local network that accept connections on the raw printing port 9100.
    public static func findPrinters(port: UInt16 = 9100, timeout: TimeInterval = 0.6) async -> [String] {
        await withTaskGroup(of: String?.self) { group in
            for host in localHosts() {
                group.addTask { isOpen(host, port: port, timeout: timeout) ? host : nil }
            }
            var found: [String] = []
            for await h in group { if let h { found.append(h) } }
            return found.sorted { $0.compare($1, options: .numeric) == .orderedAscending }
        }
    }

    public static func isOpen(_ host: String, port: UInt16, timeout: TimeInterval) -> Bool {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        guard inet_pton(AF_INET, host, &addr.sin_addr) == 1 else { return false }
        let rc = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        if rc == 0 { return true }
        guard errno == EINPROGRESS else { return false }
        var pfd = pollfd(fd: fd, events: Int16(POLLOUT), revents: 0)
        guard poll(&pfd, 1, Int32(timeout * 1000)) == 1 else { return false }
        var err: Int32 = 0
        var len = socklen_t(MemoryLayout<Int32>.size)
        getsockopt(fd, SOL_SOCKET, SO_ERROR, &err, &len)
        return err == 0
    }
}
