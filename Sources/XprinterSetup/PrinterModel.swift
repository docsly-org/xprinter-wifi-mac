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
        case done(queue: String, ip: String)
        case failed(String)
    }

    @Published var phase: Phase = .waitingForPrinter
    @Published var config: PrinterConfig?
    /// USB when the cable is plugged in, otherwise Wi-Fi if the printer answers there.
    @Published var link: PrinterLink?
    /// How to reach the printer; "auto" prefers USB and falls back to Wi-Fi. Saved between launches.
    @Published var preference: LinkPreference = LinkPreference(rawValue: UserDefaults.standard.string(forKey: "link") ?? "") ?? .auto {
        didSet { UserDefaults.standard.set(preference.rawValue, forKey: "link"); link = nil; recheck = true }
    }
    enum LinkPreference: String, CaseIterable { case auto, usb, wifi }
    private var recheck = false
    @Published var settingsError: String?
    /// True when macOS already has a printer queue pointing at the printer's current Wi-Fi address.
    @Published var addedToMac = false
    private var polling: Task<Void, Never>?

    init() {
        if Demo.isOn {
            config = Demo.config; link = .usb; phase = .ready
            Task { await Demo.capture(self) }
        } else {
            startPolling()
        }
    }

    /// Prefers USB; without the cable, looks for the printer at the Wi-Fi addresses macOS knows.
    func startPolling() {
        polling?.cancel()
        polling = Task {
            var tick = 0
            while !Task.isCancelled {
                defer { tick += 1 }
                if case .working = phase { try? await Task.sleep(nanoseconds: 2_000_000_000); continue }
                let plugged = await Self.background { USBPrinter.isConnected }
                let usb = preference != .wifi && plugged
                let lookForWiFi = link == .usb || (link == nil && (tick % 5 == 0 || recheck))
                recheck = false
                if usb, link != .usb {
                    link = .usb
                    await reload()
                } else if !usb, preference != .usb, lookForWiFi {
                    link = await Self.background { Self.findOnNetwork() }
                    await reload()
                } else if !usb, link == .usb {
                    link = nil; config = nil
                }
                if config == nil { link = nil }
                if config == nil, phase != .waitingForPrinter { phase = .waitingForPrinter }
                if config != nil, phase == .waitingForPrinter { phase = .ready }
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    nonisolated static func findOnNetwork() -> PrinterLink? {
        CUPS.xprinterNetworkHosts().lazy
            .map { PrinterLink.network($0) }
            .first { (try? Xprinter.config(via: $0))?.isValid == true }
    }

    func reload() async {
        guard let link else { config = nil; return }
        config = try? await Self.background { try Xprinter.config(via: link) }
        if let ip = config?.wifiIP {
            let uri = "socket://\(ip):9100"
            addedToMac = await Self.background { CUPS.queues().contains { $0.uri == uri } }
        } else {
            addedToMac = false
        }
    }

    var wifiQueueTitle: String { "Xprinter \(config?.model ?? "") (Wi-Fi)" }

    /// The printer is already on Wi-Fi: only (re)create the macOS printer, no password needed.
    func addToMac() {
        guard !Demo.isOn, let ip = config?.wifiIP else { return }
        let model = config?.model ?? "Printer"
        Task {
            do {
                phase = .working(loc("Adding the printer to macOS…"))
                try await Self.background { try CUPS.addOrUpdateWiFiQueue(model: model, ip: ip) }
                await reload()
                phase = .done(queue: wifiQueueTitle, ip: ip)
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
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
        guard link == .usb else { phase = .failed(loc("To change the Wi-Fi network, connect the printer with a USB cable.")); return }
        Task {
            do {
                phase = .working(loc("Sending settings to the printer…"))
                try await Self.background { try USBPrinter.send(XprinterCommand.connectWiFi(ssid: ssid, password: password)) }

                phase = .working(String(format: loc("Connecting to “%@”…"), ssid))
                try? await Task.sleep(nanoseconds: 8_000_000_000)  // the Wi-Fi module restarts first
                var ip: String?
                for _ in 0..<20 where ip == nil {
                    ip = try await Self.background { try Xprinter.wifiIP() }
                    if ip == nil { try? await Task.sleep(nanoseconds: 3_000_000_000) }
                }
                guard let ip else {
                    phase = .failed(String(format: loc("The printer could not join “%@”. Check the password and make sure the network is 2.4 GHz."), ssid))
                    return
                }

                phase = .working(loc("Adding the printer to macOS…"))
                let model = config?.model ?? "Printer"
                let queue = try await Self.background { try CUPS.addOrUpdateWiFiQueue(model: model, ip: ip) }
                await reload()
                _ = queue
                phase = .done(queue: wifiQueueTitle, ip: ip)
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
