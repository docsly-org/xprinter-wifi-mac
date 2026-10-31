import XCTest
@testable import XprinterKit

final class XprinterKitTests: XCTestCase {
    func testConnectCommandMatchesVendorTool() {
        XCTAssertEqual(String(decoding: XprinterCommand.connectWiFi(ssid: "Home", password: "secret12"), as: UTF8.self),
                       "WIFI CONNECTION \"Home\",\"secret12\"\r\nWIFI RESET\r\nWIFI GETIP\r\nOUT \"WIRESET\"\r\n")
    }

    func testValidation() {
        XCTAssertThrowsError(try XprinterCommand.validate(ssid: "", password: "12345678"))
        XCTAssertThrowsError(try XprinterCommand.validate(ssid: "a\"b", password: "12345678"))
        XCTAssertThrowsError(try XprinterCommand.validate(ssid: "Home", password: "short"))
        XCTAssertNoThrow(try XprinterCommand.validate(ssid: "Мой дом 2.4G", password: "12345678"))
        XCTAssertNoThrow(try XprinterCommand.validate(ssid: "Open", password: ""))
    }

    func testParseQueues() {
        let out = """
        device for HP_LaserJet: usb://Hewlett-Packard/HP%20LaserJet?serial=1
        device for Xprinter_XP_420B: usb://Xprinter/XP-420B?serial=S420B
        device for Xprinter_XP_420B_WiFi: socket://192.168.31.125:9100
        """
        let q = CUPS.parseQueues(out)
        XCTAssertEqual(q.map(\.name), ["HP_LaserJet", "Xprinter_XP_420B", "Xprinter_XP_420B_WiFi"])
        XCTAssertEqual(q.filter { $0.isUSB && $0.uri.localizedCaseInsensitiveContains("xprinter") }.map(\.name), ["Xprinter_XP_420B"])
    }

    func testSubnetHosts() {
        let hosts = NetworkScan.hosts(ip: 0xC0A8_1F11, mask: 0xFFFF_FF00)  // 192.168.31.17/24
        XCTAssertEqual(hosts.count, 254)
        XCTAssertEqual(hosts.first, "192.168.31.1")
        XCTAssertEqual(hosts.last, "192.168.31.254")
        XCTAssertTrue(NetworkScan.hosts(ip: 0x0A00_0001, mask: 0xFF00_0000).isEmpty)  // /8 is too big to scan
    }
}
