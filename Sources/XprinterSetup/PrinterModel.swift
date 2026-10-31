import SwiftUI
import XprinterKit

func loc(_ key: String.LocalizationValue) -> String { String(localized: key, bundle: .module) }

/// Shared state: the USB printer, its configuration and the Wi-Fi setup flow.
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
    @Published var settingsError: String?
    private var polling: Task<Void, Never>?

    init() {
        if Demo.isOn {
            config = Demo.config; phase = .ready
            Task { await Demo.capture(self) }
        } else {
            startPolling()
        }
    }

    /// Watches for the USB printer and keeps `config` fresh.
    func startPolling() {
        polling?.cancel()
        polling = Task {
            while !Task.isCancelled {
                let connected = await Self.background { USBPrinter.isConnected }
                if !connected {
                    config = nil
                    if case .working = phase {} else { phase = .waitingForPrinter }
                } else if config == nil {
                    await reload()
                    if phase == .waitingForPrinter { phase = .ready }
                }
                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    func reload() async {
        config = try? await Self.background { try Xprinter.config() }
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
                phase = .done(queue: "Xprinter \(model) (Wi-Fi)", ip: ip)
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
                try await Self.background { try USBPrinter.send(command) }
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
