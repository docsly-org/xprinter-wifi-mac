import SwiftUI
import XprinterKit

func loc(_ key: String.LocalizationValue) -> String { String(localized: key, bundle: .module) }

/// Shared state: how the printer is reached (USB or Wi-Fi), its configuration and the Wi-Fi setup flow.
@MainActor
final class PrinterModel: ObservableObject {
    enum Phase: Equatable {
        case waitingForPrinter
        case ready
        case working(String)
        case failed(String)
    }

    @Published var phase: Phase = .waitingForPrinter
    @Published var config: PrinterConfig?
    /// USB when the cable is plugged in, otherwise Wi-Fi if the printer answers there.
    @Published var link: PrinterLink?
    /// The cable is plugged in (independent of the preference). Changing the Wi-Fi network needs it.
    @Published var usbPlugged = false
    @Published var settingsError: String?
    /// Bumped after a successful setup, so the view can leave the "change network" form.
    @Published var setupCompleted = 0
    /// The last failure was a missing Xprinter driver: the view offers a download link.
    @Published var needsDriver = false
    /// Name of the macOS printer that points at the printer's Wi-Fi address, as shown in Print dialogs.
    @Published var macPrinterName: String?
    var addedToMac: Bool { macPrinterName != nil }

    /// Default label size (mm) of the Xprinter printers in macOS, nil when none is added yet.
    @Published var labelSize: (width: Double, height: Double)?
    @Published var labelError: String?

    func loadLabelSize() async {
        guard !Demo.isOn else { return }
        labelSize = await Self.background {
            CUPS.xprinterQueues().lazy.compactMap { CUPS.labelSize(queue: $0.name) }.first.map { ($0.width, $0.height) }
        }
    }

    func setLabelSize(width: Double, height: Double) {
        guard !Demo.isOn else { labelSize = (width, height); return }
        Task {
            do {
                try await Self.background { try CUPS.setLabelSize(width: width, height: height) }
                labelError = nil
            } catch {
                labelError = error.localizedDescription
            }
            await loadLabelSize()
        }
    }

    /// How to reach the printer; "auto" prefers USB and falls back to Wi-Fi. Saved between launches.
    @Published var preference: LinkPreference = LinkPreference(rawValue: UserDefaults.standard.string(forKey: "link") ?? "") ?? .auto {
        didSet { UserDefaults.standard.set(preference.rawValue, forKey: "link"); link = nil; recheck = true }
    }
    enum LinkPreference: String, CaseIterable { case auto, usb, wifi }

    /// The printer accepts a connection (or is on USB) but answers nothing: its Wi-Fi module hung mid-transfer
    /// and the printer waits for the rest. Only turning the printer off and on helps.
    @Published var notResponding = false
    /// Printer on USB reports a Wi-Fi address, but nothing answers there: the module dropped off the network.
    @Published var wifiDown = false
    /// Cover / paper state, read over USB only.
    @Published var status: PrinterStatus?
    @Published var calibrating = false
    private var recheck = true  // check the network once at launch
    nonisolated(unsafe) private static var searchedOnce = false  // touched only from findOnNetwork, one call at a time
    private var polling: Task<Void, Never>?

    init() {
        if Demo.isOn {
            config = Demo.config; link = .usb; usbPlugged = true; phase = .ready; labelSize = (75, 130)
            Task { await Demo.capture(self) }
        } else {
            startPolling()
        }
    }

    /// Checks the printer again. Over Wi-Fi a normal refresh only tests that the printer is still there
    /// (no reply needed); `deep` also reads its settings — used for "Check Again" only. See NetworkPrinter.
    func refresh(deep: Bool = false) {
        recheck = true
        if deep { deepCheck = true }
    }
    private var deepCheck = false

    /// Every 2 s only the cable is checked (no printer traffic). The printer itself is asked only on `refresh()`
    /// or when the cable comes or goes: its Wi-Fi module hangs after a while, so the app never polls it in the background.
    func startPolling() {
        polling?.cancel()
        polling = Task {
            while !Task.isCancelled {
                if case .working = phase { try? await Task.sleep(nanoseconds: 2_000_000_000); continue }
                usbPlugged = await Self.background { USBPrinter.isConnected }
                let usb = preference != .wifi && usbPlugged
                if usb {
                    if link != .usb || recheck {
                        link = .usb
                        await reload()
                        notResponding = config == nil
                        status = try? await Self.background { try Xprinter.status() }
                        // only opens a connection, no reply needed from the module
                        if let ip = config?.wifiIP { wifiDown = !(await Self.background { NetworkPrinter.isReachable(ip) }) } else { wifiDown = false }
                    }
                } else if preference == .usb {
                    if link != nil { link = nil; config = nil }
                    notResponding = false
                    wifiDown = false
                    status = nil
                } else if link == .usb || recheck {
                    wifiDown = false  // only known (and fixable) with the cable
                    status = nil
                    if case .network(let host)? = link, config != nil, !deepCheck {
                        let there = await Self.background { NetworkPrinter.isReachable(host) }
                        if !there { link = nil; config = nil }
                    } else {
                        let found = await Self.background { Self.findOnNetwork() }
                        link = found.link
                        config = found.config
                        await reload()
                        notResponding = config == nil && found.silent
                    }
                }
                recheck = false
                deepCheck = false
                if config == nil { link = nil }
                if config == nil, phase != .waitingForPrinter { phase = .waitingForPrinter }
                if config != nil, phase == .waitingForPrinter { phase = .ready }
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    /// Printers added to this Mac, an address typed by the user, then the vendor's broadcast search.
    /// The broadcast is best effort: some Wi-Fi setups drop it, hence the typed-address fallback.
    /// `silent`: a known address accepts the connection but sends nothing back (hung Wi-Fi module).
    /// Reads the settings once from the first address that answers (each reply costs, see NetworkPrinter).
    nonisolated static func findOnNetwork() -> (link: PrinterLink?, config: PrinterConfig?, silent: Bool) {
        let typed = UserDefaults.standard.string(forKey: "printerIP").map { [$0] } ?? []
        var silent = false
        var hosts = Array(Set(CUPS.xprinterNetworkHosts() + typed))
        if !searchedOnce {  // one broadcast per launch is enough
            searchedOnce = true
            hosts += Discovery.search().map(\.ip).filter { !hosts.contains($0) }
        }
        for host in hosts where NetworkPrinter.isReachable(host) {
            let link = PrinterLink.network(host)
            if let c = try? Xprinter.config(via: link), c.isValid { return (link, c, false) }
            silent = true  // accepts the connection, answers nothing: hung module
        }
        return (nil, nil, silent)
    }

    /// Re-reads the settings over USB. Over Wi-Fi the copy in memory is kept when there is one.
    func reload() async {
        guard let link else { config = nil; macPrinterName = nil; return }
        if case .network = link, config != nil {} else {
            config = try? await Self.background { try Xprinter.config(via: link) }
        }
        guard let ip = config?.wifiIP else { macPrinterName = nil; return }
        let uri = "socket://\(ip):9100"
        macPrinterName = await Self.background {
            CUPS.queues().first { $0.uri == uri }.map { CUPS.displayName(of: $0.name) }
        }
    }

    /// Adds (or re-points) the macOS printer to the printer's Wi-Fi address.
    private func addQueue(ip: String) async throws {
        phase = .working(loc("Adding the printer to macOS…"))
        let model = config?.model ?? "Printer"
        try await Self.background { _ = try CUPS.addOrUpdateWiFiQueue(model: model, ip: ip) }
        // the Wi-Fi module may have just restarted: give the read-back a few tries
        for _ in 0..<3 {
            await reload()
            if config != nil { break }
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }
        phase = .ready
        setupCompleted += 1
    }

    private func fail(_ error: Error) {
        needsDriver = error is CUPS.NoDriver
        phase = .failed(error.localizedDescription)
    }

    /// The printer is already on Wi-Fi: only add it to this Mac, no password needed.
    func addToMac() {
        guard !Demo.isOn, let ip = config?.wifiIP else { return }
        Task {
            do { try await addQueue(ip: ip) } catch { fail(error) }
        }
    }

    /// Connects to a printer that is already on Wi-Fi, at an address the user typed.
    func useAddress(_ ip: String) async -> Bool {
        let link = PrinterLink.network(ip.trimmingCharacters(in: .whitespaces))
        guard case .network(let host) = link,
              let c = try? await Self.background({ try Xprinter.config(via: link) }), c.isValid else { return false }
        UserDefaults.standard.set(host, forKey: "printerIP")
        self.link = link
        await reload()
        if config != nil { phase = .ready }
        return config != nil
    }

    // MARK: Wi-Fi setup

    func connect(ssid: String, password: String) {
        do {
            try XprinterCommand.validate(ssid: ssid, password: password)
        } catch let e as XprinterCommand.ValidationError {
            let message: String = switch e {
            case .emptySSID: loc("Choose a Wi-Fi network.")
            case .quoteInSSID, .quoteInPassword: loc("The network name and password cannot contain the \" character.")
            case .shortPassword: loc("A Wi-Fi password is at least 8 characters.")
            }
            phase = .failed(message)
            return
        } catch { return }

        guard !Demo.isOn else { return }
        guard usbPlugged else { phase = .failed(loc("To change the Wi-Fi network, connect the printer with a USB cable.")); return }
        let oldIP = config?.wifiIP
        Task {
            do {
                phase = .working(loc("Sending settings to the printer…"))
                try await Self.background { try USBPrinter.send(XprinterCommand.connectWiFi(ssid: ssid, password: password)) }

                phase = .working(String(format: loc("Connecting to “%@”…"), ssid))
                try? await Task.sleep(nanoseconds: 8_000_000_000)  // the Wi-Fi module restarts first
                var ip: String?
                for attempt in 0..<20 {
                    // a single USB hiccup while the module restarts must not end the setup
                    let current = (try? await Self.background { try Xprinter.wifiIP() }) ?? nil
                    if let current, current != oldIP {
                        ip = current; break
                    }
                    // Same address as before: the module may just repeat it after a failed join.
                    // Trust it only when the printer really answers there.
                    if let current, attempt >= 4, await Self.background({ NetworkPrinter.isReachable(current) }) {
                        ip = current; break
                    }
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                }
                guard let ip else {
                    phase = .failed(String(format: loc("The printer could not join “%@”. Check the password and make sure the network is 2.4 GHz."), ssid))
                    return
                }
                try await addQueue(ip: ip)
            } catch {
                fail(error)
            }
        }
    }

    // MARK: Printer settings

    /// Sends a setting. Over USB the configuration is read back, so the UI shows what the printer really stored;
    /// over Wi-Fi the sent values are shown instead (a read-back would cost a reply, see NetworkPrinter).
    func apply(_ command: Data, shows changes: [String: String] = [:]) {
        guard !Demo.isOn else { return }  // demo never talks to a printer
        Task {
            do {
                guard let link else { throw USBPrinter.NotConnected() }
                try await Self.background { try Xprinter.send(command, via: link) }
                settingsError = nil
                if case .network = link { config = config?.with(changes) } else { await reload() }
            } catch {
                settingsError = error.localizedDescription
            }
        }
    }

    func printSelfTest() { apply(XprinterCommand.selfTest) }

    /// Calibrates the sensor to the loaded roll (USB only): feeds 2-3 labels without printing.
    func calibrate() {
        guard !Demo.isOn, usbPlugged else { return }
        Task {
            settingsError = nil
            let before = try? await Self.background { try Xprinter.status() }
            if let before, !before.isReady {
                status = before
                settingsError = before.contains(.coverOpen) ? loc("Close the printer cover first.")
                    : before.contains(.paperOut) ? loc("Load the label roll first.") : loc("The printer is busy. Try again in a moment.")
                return
            }
            calibrating = true
            defer { calibrating = false }
            do {
                try await Self.background { try USBPrinter.send(XprinterCommand.calibrateGapLabels) }
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                for _ in 0..<30 {  // wait until the feed is over
                    if let s = try? await Self.background({ try Xprinter.status() }), s.isReady { break }
                    try? await Task.sleep(nanoseconds: 1_000_000_000)
                }
                await reload()
            } catch {
                settingsError = error.localizedDescription
            }
        }
    }

    /// Soft restart over USB ("Reset Printer"). Settings are kept; Wi-Fi comes back about 10 s later.
    func restartPrinter() { restart(XprinterCommand.restartPrinter, wait: 15) }
    /// Restarts only the Wi-Fi module over USB.
    func restartWiFi() { restart(XprinterCommand.restartWiFi, wait: 10) }

    private func restart(_ command: Data, wait seconds: UInt64) {
        guard !Demo.isOn, usbPlugged else { return }
        Task {
            phase = .working(loc("Restarting…"))
            do {
                try await Self.background { try USBPrinter.send(command) }
            } catch {
                phase = .failed(error.localizedDescription)
                return
            }
            try? await Task.sleep(nanoseconds: seconds * 1_000_000_000)
            link = nil; config = nil
            phase = .waitingForPrinter
            refresh(deep: true)
        }
    }

    nonisolated static func background<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await Task.detached(priority: .userInitiated) { try work() }.value
    }

    nonisolated static func background<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await Task.detached(priority: .userInitiated) { work() }.value
    }
}
