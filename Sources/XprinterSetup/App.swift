import SwiftUI
import XprinterKit

@main
struct XprinterSetupApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 520, idealWidth: 560, minHeight: 600)
        }
        .windowResizability(.contentSize)
    }
}

private func loc(_ key: String.LocalizationValue) -> String { String(localized: key, bundle: .module) }

struct ContentView: View {
    @State private var queues: [PrinterQueue] = []
    @State private var selected: PrinterQueue?
    @State private var ssid = ""
    @State private var password = ""
    @State private var ip = ""
    @State private var found: [String] = []
    @State private var scanning = false
    @State private var status: (text: String, isError: Bool)?
    @StateObject private var wifi = WiFiScanner()
    @State private var choice = ContentView.other
    static let other = "\u{0}other"  // can't collide with a real SSID

    var body: some View {
        Form {
            Section {
                if queues.isEmpty {
                    Label { Text("No Xprinter connected over USB. Connect the printer with a cable and add it in System Settings → Printers & Scanners.", bundle: .module) }
                        icon: { Image(systemName: "cable.connector").foregroundStyle(.orange) }
                } else {
                    Picker(selection: $selected) {
                        ForEach(queues) { Text($0.name.replacingOccurrences(of: "_", with: " ")).tag(Optional($0)) }
                    } label: { Text("Printer", bundle: .module) }
                }
                HStack {
                    Button { refresh() } label: { Text("Refresh", bundle: .module) }
                    Button { send(XprinterCommand.selfTest, done: loc("Self-test page sent.")) } label: { Text("Print Self-Test Page", bundle: .module) }
                        .disabled(selected == nil)
                }
            } header: { Text("1. Printer (USB)", bundle: .module) }

            Section {
                HStack {
                    Picker(selection: $choice) {
                        ForEach(wifi.result.networks24, id: \.self) { Text($0).tag($0) }
                        if !wifi.result.networks24.isEmpty { Divider() }
                        Text("Other Network…", bundle: .module).tag(Self.other)
                    } label: { Text("Network", bundle: .module) }
                    Button { wifi.scan() } label: {
                        if wifi.scanning { ProgressView().controlSize(.small) } else { Image(systemName: "arrow.clockwise") }
                    }
                    .buttonStyle(.borderless)
                    .help(Text("Scan for networks", bundle: .module))
                }
                if choice == Self.other {
                    TextField(text: $ssid) { Text("Network name", bundle: .module) }
                }
                if wifi.needsLocation {
                    Text("To list networks, allow Location access for Xprinter Setup in System Settings → Privacy & Security → Location Services.", bundle: .module)
                        .font(.callout).foregroundStyle(.orange)
                }
                if wifi.result.only5GHz > 0 {
                    Text("Hidden 5 GHz-only networks: \(wifi.result.only5GHz)", bundle: .module)
                        .font(.callout).foregroundStyle(.secondary)
                }
                SecureField(text: $password) { Text("Password", bundle: .module) }
                Button { connect() } label: { Text("Connect Printer to Wi-Fi", bundle: .module) }
                    .buttonStyle(.borderedProminent)
                    .disabled(selected == nil || ssid.isEmpty)
            } header: { Text("2. Wi-Fi network", bundle: .module) }
              footer: { Text("The printer supports 2.4 GHz networks only. After connecting, print the self-test page: the STA IP line shows the printer's address.", bundle: .module).foregroundStyle(.secondary) }

            Section {
                HStack {
                    TextField(text: $ip) { Text("Printer IP address", bundle: .module) }
                    Button { scan() } label: { scanning ? Text("Searching…", bundle: .module) : Text("Find", bundle: .module) }
                        .disabled(scanning)
                }
                if !found.isEmpty {
                    Picker(selection: $ip) {
                        ForEach(found, id: \.self) { Text($0).tag($0) }
                    } label: { Text("Found on port 9100", bundle: .module) }
                }
                Button { addQueue() } label: { Text("Add Wi-Fi Printer to macOS", bundle: .module) }
                    .disabled(selected == nil || !isIPv4(ip))
            } header: { Text("3. Print over Wi-Fi", bundle: .module) }
              footer: { Text("Adds a printer that uses the same driver as the USB one. Then pick it in any Print dialog — the cable is no longer needed.", bundle: .module).foregroundStyle(.secondary) }

            if let status {
                Section {
                    Label(status.text, systemImage: status.isError ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(status.isError ? .red : .green)
                        .textSelection(.enabled)
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { refresh(); wifi.scan() }
        .onChange(of: choice) { ssid = $0 == Self.other ? "" : $0 }
        .onChange(of: wifi.result.networks24) { list in
            // preselect the Mac's own network when it also works on 2.4 GHz
            if choice == Self.other, ssid.isEmpty, let cur = wifi.result.current, list.contains(cur) { choice = cur }
        }
    }

    private func refresh() {
        queues = CUPS.xprinterUSBQueues()
        if selected.map({ !queues.contains($0) }) ?? true { selected = queues.first }
    }

    private func send(_ data: Data, done: String) {
        guard let q = selected else { return }
        do { try CUPS.sendRaw(data, to: q.name); status = (done, false) }
        catch { status = (error.localizedDescription, true) }
    }

    private func connect() {
        do {
            try XprinterCommand.validate(ssid: ssid, password: password)
        } catch let e as XprinterCommand.ValidationError {
            let text: String = switch e {
            case .emptySSID: loc("Enter the network name.")
            case .quoteInSSID, .quoteInPassword: loc("The network name and password cannot contain the \" character.")
            case .shortPassword: loc("A Wi-Fi password is at least 8 characters.")
            }
            status = (text, true); return
        } catch { return }
        send(XprinterCommand.connectWiFi(ssid: ssid, password: password),
             done: loc("Settings sent. The printer is restarting Wi-Fi — wait about 30 seconds, then press Find or print the self-test page."))
    }

    private func scan() {
        scanning = true
        Task {
            let hosts = await NetworkScan.findPrinters()
            found = hosts
            if ip.isEmpty, let first = hosts.first { ip = first }
            scanning = false
            if hosts.isEmpty { status = (loc("No printers found. Check the STA IP line on the self-test page and allow Local Network access for this app in System Settings → Privacy & Security."), true) }
        }
    }

    private func addQueue() {
        guard let q = selected else { return }
        do {
            let name = try CUPS.addNetworkQueue(from: q, ip: ip)
            status = (String(format: loc("Printer “%@” added. Choose it in the Print dialog."), name.replacingOccurrences(of: "_", with: " ")), false)
        } catch { status = (error.localizedDescription, true) }
    }

    private func isIPv4(_ s: String) -> Bool {
        var a = in_addr()
        return inet_pton(AF_INET, s, &a) == 1
    }
}
