import Foundation

/// Two-way talk with the printer over Wi-Fi: the same TSPL commands on TCP port 9100, replies on the same socket.
///
/// Firmware bug (XP-420B, Wi-Fi module X4_V95.0.9): after power-on the module passes only about nine replies
/// from the printer to the network (a reply = an ALLCONFIG report, ~2.5 KB); then it hangs and the printer
/// stops answering on USB too until it is turned off and on. Data sent *to* the printer is not affected:
/// 20 write-only sessions in a row were fine, so normal printing over Wi-Fi is safe.
/// Callers therefore ask the printer for a reply over Wi-Fi as rarely as possible.
public enum NetworkPrinter {
    public struct Unreachable: LocalizedError {
        public var errorDescription: String? { String(localized: "The printer does not answer over Wi-Fi.", bundle: .module) }
    }

    public static func exchange(host: String, port: UInt16 = 9100, _ data: Data,
                                until terminator: String? = nil, timeout: TimeInterval = 3) throws -> String {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw Unreachable() }
        defer { close(fd) }
        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
        guard connect(fd, host: host, port: port, timeout: 3) else { throw Unreachable() }

        var tv = timeval(tv_sec: 0, tv_usec: 300_000)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        let sent = data.withUnsafeBytes { write(fd, $0.baseAddress, data.count) }
        guard sent == data.count else { throw Unreachable() }
        guard let terminator else { closeGracefully(fd); return "" }

        var reply = Data()
        var buf = [UInt8](repeating: 0, count: 4096)
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline, !String(decoding: reply, as: UTF8.self).contains(terminator) {
            let n = read(fd, &buf, buf.count)
            if n > 0 { reply.append(buf, count: n) } else if n == 0 { break }  // n < 0: timeout tick
        }
        closeGracefully(fd)
        return String(decoding: reply, as: UTF8.self)
    }

    /// Says "done" and lets the printer close first. Closing with unread bytes makes macOS send a reset,
    /// which the printer's Wi-Fi module handles badly.
    static func closeGracefully(_ fd: Int32) {
        shutdown(fd, SHUT_WR)
        var buf = [UInt8](repeating: 0, count: 512)
        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            let n = read(fd, &buf, buf.count)
            if n == 0 { break }  // printer closed its side
            if n < 0 && errno != EAGAIN && errno != EWOULDBLOCK { break }
        }
    }

    /// Opens and closes a connection without sending anything.
    public static func isReachable(_ host: String, port: UInt16 = 9100) -> Bool {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { return false }
        defer { close(fd) }
        return connect(fd, host: host, port: port, timeout: 3)
    }

    /// Non-blocking connect with a timeout, then back to blocking mode.
    static func connect(_ fd: Int32, host: String, port: UInt16, timeout: TimeInterval) -> Bool {
        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        guard inet_pton(AF_INET, host, &addr.sin_addr) == 1 else { return false }
        let flags = fcntl(fd, F_GETFL)
        _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
        defer { _ = fcntl(fd, F_SETFL, flags) }
        let rc = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
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
