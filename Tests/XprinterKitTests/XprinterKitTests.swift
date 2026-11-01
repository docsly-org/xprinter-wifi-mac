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

    func testRestartIsNotFactoryReset() {
        // vendor "Reset Printer": ESC ! exit CR LF, ESC ! R — and never ESC ! C (factory reset)
        XCTAssertEqual(Array(XprinterCommand.restartPrinter), [27, 33] + Array("exit\r\n".utf8) + [27, 33, 82])
        XCTAssertFalse(Array(XprinterCommand.restartPrinter).suffix(3) == [27, 33, 67])
    }

    func testAccessPoint() {
        XCTAssertEqual(String(decoding: XprinterCommand.setAccessPoint(name: "XP-420B", password: "secret123"), as: UTF8.self),
                       "WIFI SETAP \"XP-420B\",3,\"secret123\"\r\nWIFI RESET\r\n")  // 3 = WPA2, checked on the printer
        XCTAssertTrue(XprinterCommand.isValidAccessPointPassword("12345678"))
        XCTAssertFalse(XprinterCommand.isValidAccessPointPassword("short"))
        XCTAssertFalse(XprinterCommand.isValidAccessPointPassword("with\"quote1"))
        XCTAssertFalse(XprinterCommand.isValidAccessPointPassword("пароль-кириллицей"))
        XCTAssertEqual(PrinterConfig(report: "Wifi Pin: 12345678").accessPointPassword, "12345678")
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
    Wifi Sta Ip: 192.168.1.50\r
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
        XCTAssertEqual(c.wifiIP, "192.168.1.50")
        XCTAssertEqual(c.density, 8)
        XCTAssertEqual(c.speed, 6)
        XCTAssertEqual(c.rotated, true)
        XCTAssertEqual(c.mirrored, false)
        XCTAssertEqual(c.reprint, true)
        XCTAssertEqual(c.offset, -3)
        XCTAssertEqual(PrinterConfig(report: "Wifi Sta Ip: 0.0.0.0").wifiIP, nil)
    }

    func testConfigWithChanges() {
        let c = PrinterConfig(report: report).with(["Density": "12.0", "Mirror": "ON"])
        XCTAssertEqual(c.density, 12)
        XCTAssertEqual(c.mirrored, true)
        XCTAssertEqual(c.speed, 6)  // untouched values stay
        // the exact strings the settings screen writes over Wi-Fi parse like the printer's own report
        let w = PrinterConfig(report: report).with(["Speed": "4 Inch", "Direction": "1", "Reprint": "OFF", "Offset": "-2", "Shift Y": "3"])
        XCTAssertEqual(w.speed, 4); XCTAssertEqual(w.rotated, true); XCTAssertEqual(w.reprint, false)
        XCTAssertEqual(w.offset, -2); XCTAssertEqual(w.shiftY, 3)
    }

    func testStatusAndSensor() {
        XCTAssertTrue(PrinterStatus(rawValue: 0).isReady)
        XCTAssertEqual(PrinterStatus(rawValue: 0x01), .coverOpen)  // seen on an XP-420B with the cover open
        XCTAssertTrue(PrinterStatus(rawValue: 0x05).contains(.paperOut))
        let gap = PrinterConfig(report: "Sensor Mode: GAP\nPaper Size: 1021.0\nGap Size: 13.0")  // after GAPDETECT
        XCTAssertEqual(gap.sensor, .gap)
        XCTAssertEqual(gap.labelLengthMM, 127.625)
        XCTAssertEqual(gap.gapMM, 1.625)
        XCTAssertEqual(PrinterConfig(report: "Sensor Mode: CONTINUOUS(T)").sensor, .continuous)
        XCTAssertEqual(String(decoding: XprinterCommand.calibrateGapLabels, as: UTF8.self), "GAPDETECT\r\n")
    }

    func testPaperType() {
        XCTAssertEqual(String(decoding: XprinterCommand.continuousPaper, as: UTF8.self), "GAP 0,0\r\n")
        // seen on an XP-420B: after GAP 0,0 the printer keeps Paper Size / Gap Size; GAP <n> dot restores them exactly
        let cont = PrinterConfig(report: "Sensor Mode: CONTINUOUS(T)\nPaper Size: 1020.0\nGap Size: 14.0\nGap Offset: 0.0")
        XCTAssertEqual(cont.gapDots, 14)
        XCTAssertEqual(String(decoding: XprinterCommand.gapLabels(gapDots: 12.8, offsetDots: 0), as: UTF8.self), "GAP 13 dot,0 dot\r\n")
        XCTAssertNil(PrinterConfig(report: "Gap Size: 0.0").gapDots)
    }

    func testOkReply() {
        XCTAssertEqual(PrinterConfig.okValue("+OK=192.168.1.50\r\nXPSETUP-END\r\n"), "192.168.1.50")
        XCTAssertNil(PrinterConfig.okValue("garbage"))
    }

    func testDiscoveryReply() {
        // real reply of an XP-420B (address changed to 192.168.1.50)
        var r = [UInt8](repeating: 0, count: 116)
        r[0...1] = [0, 32]
        r[44..<48] = [192, 168, 1, 50]
        r[52..<59] = ArraySlice("XP-420B".utf8)
        XCTAssertEqual(Discovery.parse(r), Discovery.Found(ip: "192.168.1.50", name: "XP-420B"))
        XCTAssertNil(Discovery.parse(Array(r.prefix(40))))
    }

    func testPrinterInfo() {
        XCTAssertEqual(CUPS.parseInfo("device-uri=socket://1.2.3.4:9100 printer-info='Xprinter XP-420B (Wi-Fi)' printer-is-shared=false"),
                       "Xprinter XP-420B (Wi-Fi)")
        XCTAssertEqual(CUPS.parseInfo("printer-info=Office printer-location=x"), "Office")
    }

    func testLabelSizeInPPD() throws {
        let ppd = try String(contentsOfFile: "/Library/Printers/PPDs/Contents/Resources/XP-420B.ppd", encoding: .isoLatin1)
        XCTAssertEqual(LabelSize.read(ppd: ppd)?.width, 50.8)  // vendor default: 2 x 4 in
        let once = LabelSize.apply(ppd: ppd, width: 75, height: 130)
        let r = try XCTUnwrap(LabelSize.read(ppd: once))
        XCTAssertEqual(r.width, 75); XCTAssertEqual(r.height, 130)
        // applying again replaces our size instead of adding a second one
        let twice = LabelSize.apply(ppd: once, width: 58, height: 40)
        XCTAssertEqual(LabelSize.read(ppd: twice)?.width, 58)
        XCTAssertEqual(twice.components(separatedBy: "*PageSize XPSetupLabel").count - 1, 1)
        XCTAssertEqual(twice.components(separatedBy: "*PaperDimension XPSetupLabel").count - 1, 1)
        XCTAssertTrue(twice.contains("*PageSize w4h6/"))  // vendor sizes stay
    }

    func testQueueParsingAndNaming() {
        let q = CUPS.parseQueues("device for Xprinter_XP_420B: usb://Xprinter/XP-420B?serial=S\ndevice for X_WiFi: socket://1.2.3.4:9100")
        XCTAssertEqual(q.map(\.name), ["Xprinter_XP_420B", "X_WiFi"])
        XCTAssertEqual(CUPS.queueName(model: "XP-420B"), "Xprinter_XP_420B_WiFi")
        // lpstat output is localized on a Russian macOS
        XCTAssertEqual(CUPS.parseQueues("устройство для Xprinter_XP_420B_WiFi: socket://192.168.1.50:9100"),
                       [PrinterQueue(name: "Xprinter_XP_420B_WiFi", uri: "socket://192.168.1.50:9100")])
    }

    /// Read-only check against a real printer: XPRINTER_LIVE=1 swift test
    func testLiveReadOnly() throws {
        try XCTSkipUnless(ProcessInfo.processInfo.environment["XPRINTER_LIVE"] == "1", "set XPRINTER_LIVE=1 with a printer on USB")
        let c = try Xprinter.config()
        XCTAssertNotNil(c.model)
        XCTAssertNotNil(c.density)
        print("LIVE model=\(c.model ?? "-") fw=\(c.firmware ?? "-") density=\(c.density ?? -1) speed=\(c.speed ?? -1) wifi=\(c.wifiIP ?? "-")")
        print("LIVE wifiIP=\(try Xprinter.wifiIP() ?? "-")")
        print("LIVE status=\(String(describing: try Xprinter.status()))")
    }

    /// Read-only check over Wi-Fi: XPRINTER_LIVE_IP=a.b.c.d swift test
    func testLiveNetworkReadOnly() throws {
        guard let ip = ProcessInfo.processInfo.environment["XPRINTER_LIVE_IP"] else { throw XCTSkip("set XPRINTER_LIVE_IP") }
        let c = try Xprinter.config(via: .network(ip))
        XCTAssertEqual(c.wifiIP, ip)
        print("LIVE-NET model=\(c.model ?? "-") density=\(c.density ?? -1) speed=\(c.speed ?? -1)")
        print("LIVE-DISCOVERY \(Discovery.search())")  // best effort: some Wi-Fi setups drop the broadcast
    }
}
