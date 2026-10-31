import XCTest
@testable import XprinterKit

final class XprinterKitTests: XCTestCase {
    func testConnectCommandMatchesVendorTool() {
        XCTAssertEqual(String(decoding: XprinterCommand.connectWiFi(ssid: "Home", password: "secret12"), as: UTF8.self),
                       "WIFI CONNECTION \"Home\",\"secret12\"\r\nWIFI RESET\r\n")
    }

    func testSettingCommandsAreClamped() {
        XCTAssertEqual(String(decoding: XprinterCommand.density(20), as: UTF8.self), "DENSITY 15\r\n")
        XCTAssertEqual(String(decoding: XprinterCommand.speed(8), as: UTF8.self), "SPEED 6\r\n")
        XCTAssertEqual(String(decoding: XprinterCommand.direction(rotated: true, mirrored: false), as: UTF8.self), "DIRECTION 1,0\r\n")
        XCTAssertEqual(String(decoding: XprinterCommand.offset(-5), as: UTF8.self), "OFFSET -5 dot\r\n")
    }

    func testValidation() {
        XCTAssertThrowsError(try XprinterCommand.validate(ssid: "", password: "12345678"))
        XCTAssertThrowsError(try XprinterCommand.validate(ssid: "a\"b", password: "12345678"))
        XCTAssertThrowsError(try XprinterCommand.validate(ssid: "Home", password: "short"))
        XCTAssertNoThrow(try XprinterCommand.validate(ssid: "Мой дом 2.4G", password: "12345678"))
        XCTAssertNoThrow(try XprinterCommand.validate(ssid: "Open", password: ""))
    }

    /// Excerpt of a real ALLCONFIG reply from an XP-420B.
    let report = """
    \r
    XP-420B Version: 1.040.3552 CEZD\r
    Wifi : YES\r
    Wifi Name: XP-420B\r
    Wifi Sta Ip: 192.168.31.125\r
    Wifi Versions: X4_V95.0.9\r
    Bluetooth Versions: \r
    Direction: 1\r
    Mirror: OFF\r
    Density: 8.0\r
    Reprint: ON\r
    Offset: -3\r
    Shift X: 0\r
    Speed: 6 Inch\r
    XPSETUP-END\r
    """

    func testParseConfig() {
        let c = PrinterConfig(report: report)
        XCTAssertEqual(c.model, "XP-420B")
        XCTAssertEqual(c.firmware, "1.040.3552 CEZD")
        XCTAssertTrue(c.hasWiFi)
        XCTAssertEqual(c.wifiIP, "192.168.31.125")
        XCTAssertEqual(c.density, 8)
        XCTAssertEqual(c.speed, 6)
        XCTAssertEqual(c.rotated, true)
        XCTAssertEqual(c.mirrored, false)
        XCTAssertEqual(c.reprint, true)
        XCTAssertEqual(c.offset, -3)
        XCTAssertEqual(PrinterConfig(report: "Wifi Sta Ip: 0.0.0.0").wifiIP, nil)
    }

    func testOkReply() {
        XCTAssertEqual(PrinterConfig.okValue("+OK=192.168.31.125\r\nXPSETUP-END\r\n"), "192.168.31.125")
        XCTAssertNil(PrinterConfig.okValue("garbage"))
    }

    func testQueueParsingAndNaming() {
        let q = CUPS.parseQueues("device for Xprinter_XP_420B: usb://Xprinter/XP-420B?serial=S\ndevice for X_WiFi: socket://1.2.3.4:9100")
        XCTAssertEqual(q.map(\.name), ["Xprinter_XP_420B", "X_WiFi"])
        XCTAssertEqual(CUPS.queueName(model: "XP-420B"), "Xprinter_XP_420B_WiFi")
    }

    /// Read-only check against a real printer: XPRINTER_LIVE=1 swift test
    func testLiveReadOnly() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["XPRINTER_LIVE"] == "1", "set XPRINTER_LIVE=1 with a printer on USB")
        let c = try Xprinter.config()
        XCTAssertNotNil(c.model)
        XCTAssertNotNil(c.density)
        print("LIVE model=\(c.model ?? "-") fw=\(c.firmware ?? "-") density=\(c.density ?? -1) speed=\(c.speed ?? -1) wifi=\(c.wifiIP ?? "-")")
        print("LIVE wifiIP=\(try Xprinter.wifiIP() ?? "-")")
    }
}
