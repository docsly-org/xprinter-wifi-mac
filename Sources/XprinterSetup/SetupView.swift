import SwiftUI
import XprinterKit

/// Main window: pick a network, type the password, press Connect.
struct SetupView: View {
    @EnvironmentObject var printer: PrinterModel
    @Environment(\.openWindow) private var openWindow
    @StateObject private var wifi = WiFiScanner(demo: Demo.isOn)
    @State private var choice = SetupView.other
    @State private var ssid = ""
    @State private var password = ""
    @FocusState private var passwordFocused: Bool
    @State private var changeNetwork = false
    static let other = "\u{0}other"  // can't collide with a real SSID

    var body: some View {
        VStack(spacing: 0) {
            header.padding(.top, 28).padding(.bottom, 8)
            content
        }
        .toolbar {
            ToolbarItem {
                Button { openWindow(id: "settings") } label: { Image(systemName: "gearshape") }
                    .help(Text("Printer Settings…", bundle: .module))
                    .disabled(printer.config == nil)
            }
        }
        .onAppear {
            wifi.scan()
            if Demo.isOn { openWindow(id: "settings") }
        }
        .onChange(of: choice) {
            ssid = $0 == Self.other ? "" : $0
            if $0 != Self.other { passwordFocused = true }
        }
        .onChange(of: wifi.result.networks24) { list in
            // preselect the Mac's own network when the printer can use it
            if choice == Self.other, ssid.isEmpty, let cur = wifi.result.current, list.contains(cur) { choice = cur }
        }
    }

    private var header: some View {
        VStack(spacing: 6) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable().frame(width: 72, height: 72)
            Text(printer.config?.model.map { "Xprinter \($0)" } ?? "Xprinter")
                .font(.title2.weight(.semibold))
            statusLine.font(.callout).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var statusLine: some View {
        if printer.config == nil {
            Text("Connect the printer with a USB cable, or turn it on if it is already set up on Wi-Fi.", bundle: .module)
        } else if let ip = printer.config?.wifiIP {
            Label { Text("On Wi-Fi · \(ip)", bundle: .module) } icon: { Image(systemName: "wifi") }
        } else {
            Text("Connected over USB · not on Wi-Fi yet", bundle: .module)
        }
    }

    @ViewBuilder private var content: some View {
        switch printer.phase {
        case .waitingForPrinter:
            ProgressView().controlSize(.small).padding(.vertical, 28)

        case .working(let step):
            VStack(spacing: 12) {
                ProgressView()
                Text(step).foregroundStyle(.secondary)
            }
            .padding(.vertical, 32)

        case .done(let queue, let ip):
            VStack(spacing: 10) {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 40)).foregroundStyle(.green)
                Text("All set", bundle: .module).font(.headline)
                Text("Choose “\(queue)” in any Print dialog. The printer’s address is \(ip). You can unplug the USB cable.", bundle: .module)
                    .multilineTextAlignment(.center).foregroundStyle(.secondary)
                Button { changeNetwork = false; printer.phase = .ready } label: { Text("Done", bundle: .module) }
                    .keyboardShortcut(.defaultAction).padding(.top, 6)
            }
            .padding(24)

        case .ready, .failed:
            if let ip = printer.config?.wifiIP, !changeNetwork, printer.phase == .ready {
                onWiFi(ip: ip)
            } else {
                form
            }
        }
    }

    /// Printer already on Wi-Fi: nothing to type. Either all is set, or one click adds it to macOS.
    private func onWiFi(ip: String) -> some View {
        VStack(spacing: 10) {
            if printer.addedToMac {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 40)).foregroundStyle(.green)
                Text("The printer works over Wi-Fi", bundle: .module).font(.headline)
                Text("Choose “\(printer.wifiQueueTitle)” in any Print dialog.", bundle: .module)
                    .multilineTextAlignment(.center).foregroundStyle(.secondary)
            } else {
                Text("The printer is on Wi-Fi but not added to this Mac yet.", bundle: .module)
                    .multilineTextAlignment(.center).foregroundStyle(.secondary)
                Button { printer.addToMac() } label: { Text("Add to This Mac", bundle: .module).frame(maxWidth: .infinity) }
                    .controlSize(.large).buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
            if printer.link == .usb {
                Button { changeNetwork = true } label: { Text("Connect to Another Network…", bundle: .module) }
                    .buttonStyle(.link).padding(.top, 6)
            } else {
                Text("Connected over Wi-Fi. To change the network, connect the USB cable.", bundle: .module)
                    .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).padding(.top, 6)
            }
        }
        .padding(.horizontal, 24).padding(.top, 16).padding(.bottom, 24)
    }

    private var form: some View {
        Form {
            Section {
                Picker(selection: $choice) {
                    ForEach(wifi.result.networks24, id: \.self) { Text($0).tag($0) }
                    if !wifi.result.networks24.isEmpty { Divider() }
                    Text("Other Network…", bundle: .module).tag(Self.other)
                } label: { Text("Network", bundle: .module) }
                if choice == Self.other {
                    TextField(text: $ssid, prompt: Text("Required", bundle: .module)) { Text("Network name", bundle: .module) }
                }
                SecureField(text: $password, prompt: Text("Required", bundle: .module)) { Text("Password", bundle: .module) }
                    .focused($passwordFocused)
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    if wifi.needsLocation {
                        Text("To list networks, allow Location access for Xprinter Setup in System Settings → Privacy & Security → Location Services.", bundle: .module)
                    }
                    Text("The printer works with 2.4 GHz networks only, so 5 GHz-only networks are not listed.", bundle: .module)
                    if case .failed(let message) = printer.phase {
                        Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
                    }
                }
                .font(.callout).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .safeAreaInset(edge: .bottom) {
            Button { printer.connect(ssid: ssid, password: password) } label: {
                Text("Connect", bundle: .module).frame(maxWidth: .infinity)
            }
            .controlSize(.large)
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(printer.config == nil || ssid.isEmpty)
            .padding([.horizontal, .bottom], 20)
        }
    }
}
