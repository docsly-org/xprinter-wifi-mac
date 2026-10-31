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
    /// Name of the macOS printer that points at the printer's Wi-Fi address, as shown in Print dialogs.
    @Published var macPrinterName: String?
    var addedToMac: Bool { macPrinterName != nil }

    /// How to reach the printer; "auto" prefers USB and falls back to Wi-Fi. Saved between launches.
    @Published var preference: LinkPreference = LinkPreference(rawValue: UserDefaults.standard.string(forKey: "link") ?? "") ?? .auto {
        didSet { UserDefaults.standard.set(preference.rawValue, forKey: "link"); link = nil; recheck = true }
    }
    enum LinkPreference: String, CaseIterable { case auto, usb, wifi }

    private var recheck = false
    nonisolated(unsafe) private static var searchedOnce = false  // touched only from findOnNetwork, one call at a time
    private var polling: Task<Void, Never>?

    init() {
        if Demo.isOn {
            config = Demo.config; link = .usb; usbPlugged = true; phase = .ready
            Task { await Demo.capture(self) }
        } else {
            startPolling()
        }
    }

    /// Every 2 s: prefer USB. Without it, look for the printer on Wi-Fi every 30 s and re-check it every 30 s:
    /// the printer's Wi-Fi module is fragile, so the network is touched as little as possible.
    func startPolling() {
        polling?.cancel()
        polling = Task {
            var tick = 0
            while !Task.isCancelled {
                defer { tick += 1 }
                if case .working = phase { try? await Task.sleep(nanoseconds: 2_000_000_000); continue }
                usbPlugged = await Self.background { USBPrinter.isConnected }
                let usb = preference != .wifi && usbPlugged
                if usb {
                    if link != .usb { link = .usb; await reload() }
                } else if preference == .usb {
                    if link != nil { link = nil; config = nil }
                } else if link == .usb || link == nil && (tick % 15 == 0 || recheck) {
                    link = await Self.background { Self.findOnNetwork() }
                    await reload()
                } else if case .network = link, tick % 15 == 0 {
                    await reload()  // notices a printer that was turned off
                }
                recheck = false
                if config == nil { link = nil }
                if config == nil, phase != .waitingForPrinter { phase = .waitingForPrinter }
                if config != nil, phase == .waitingForPrinter { phase = .ready }
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    /// Printers added to this Mac, an address typed by the user, then the vendor's broadcast search.
    /// The broadcast is best effort: some Wi-Fi setups drop it, hence the typed-address fallback.
    nonisolated static func findOnNetwork() -> PrinterLink? {
        let typed = UserDefaults.standard.string(forKey: "printerIP").map { [$0] } ?? []
        let known = CUPS.xprinterNetworkHosts() + typed
        if let link = known.lazy.map({ PrinterLink.network($0) }).first(where: { (try? Xprinter.config(via: $0))?.isValid == true }) {
            return link
        }
        guard !searchedOnce else { return nil }  // one broadcast per launch is enough
        searchedOnce = true
        return Discovery.search().lazy.map { PrinterLink.network($0.ip) }.first { (try? Xprinter.config(via: $0))?.isValid == true }
    }

    func reload() async {
        guard let link else { config = nil; macPrinterName = nil; return }
        config = try? await Self.background { try Xprinter.config(via: link) }
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
    }

    /// The printer is already on Wi-Fi: only add it to this Mac, no password needed.
    func addToMac() {
        guard !Demo.isOn, let ip = config?.wifiIP else { return }
        Task {
            do { try await addQueue(ip: ip) } catch { phase = .failed(error.localizedDescription) }
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
                    let current = try await Self.background { try Xprinter.wifiIP() }
                    // right after the restart the module may still report the old address
                    if let current, current != oldIP || attempt >= 4 { ip = current; break }
                    try? await Task.sleep(nanoseconds: 3_000_000_000)
                }
                guard let ip else {
                    phase = .failed(String(format: loc("The printer could not join “%@”. Check the password and make sure the network is 2.4 GHz."), ssid))
                    return
                }
                try await addQueue(ip: ip)
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    // MARK: Printer settings

    /// Sends a setting, then reads the configuration back so the UI shows what the printer really stored.
    func apply(_ command: Data) {
        guard !Demo.isOn else { return }  // demo never talks to a printer
        Task {
            do {
                guard let link else { throw USBPrinter.NotConnected() }
                try await Self.background { try Xprinter.send(command, via: link) }
                settingsError = nil
            } catch {
                settingsError = error.localizedDescription
            }
            await reload()
        }
    }

    func printSelfTest() { apply(XprinterCommand.selfTest) }

    nonisolated static func background<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await Task.detached(priority: .userInitiated) { try work() }.value
    }

    nonisolated static func background<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await Task.detached(priority: .userInitiated) { work() }.value
    }
}
