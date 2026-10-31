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
        .onChange(of: printer.phase) { if $0 == .ready { changeNetwork = false } }
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
        VStack(spacing: 4) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable().frame(width: 64, height: 64)
                .padding(.bottom, 4)
            Text(printer.config?.model.map { "Xprinter \($0)" } ?? "Xprinter")
                .font(.title3.weight(.semibold))
            statusLine.font(.callout).foregroundStyle(.secondary)
        }
    }

    /// One calm line with a colored dot, like the status of a device in System Settings.
    @ViewBuilder private var statusLine: some View {
        if printer.config == nil {
            Text("Connect the printer with a USB cable, or turn it on if it is already set up on Wi-Fi.", bundle: .module)
                .multilineTextAlignment(.center).padding(.horizontal, 32)
        } else if printer.config?.wifiIP == nil {
            dot(.secondary) { Text("Not on Wi-Fi", bundle: .module) }
        } else if printer.addedToMac {
            dot(.green) { Text("Ready to print over Wi-Fi", bundle: .module) }
        } else {
            dot(.orange) { Text("On Wi-Fi, not added to this Mac", bundle: .module) }
        }
    }

    private func dot(_ color: Color, _ text: () -> Text) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 8, height: 8)
            text()
        }
    }

    @ViewBuilder private var content: some View {
        switch printer.phase {
        case .waitingForPrinter:
            ProgressView().controlSize(.small).padding(.vertical, 28)

        case .working(let step):
            VStack(spacing: 12) {
                ProgressView().controlSize(.small)
                Text(step).font(.callout).foregroundStyle(.secondary)
            }
            .padding(.vertical, 36)

        case .ready, .failed:
            if let ip = printer.config?.wifiIP, !changeNetwork, printer.phase == .ready {
                status(ip: ip)
            } else {
                form
            }
        }
    }

    /// Printer on Wi-Fi: facts about it, nothing to type.
    private func status(ip: String) -> some View {
        Form {
            Section {
                LabeledContent { Text(ip).textSelection(.enabled) } label: { Text("IP Address", bundle: .module) }
                LabeledContent {
                    printer.addedToMac ? Text(printer.wifiQueueTitle) : Text("Not added", bundle: .module)
                } label: { Text("Printer in macOS", bundle: .module) }
                LabeledContent {
                    printer.link == .usb ? Text("USB") : Text("Wi-Fi")
                } label: { Text("Connected via", bundle: .module) }
            } footer: {
                Group {
                    if !printer.addedToMac {
                        Text("Add the printer to print to it from this Mac.", bundle: .module)
                    } else if printer.link == .usb {
                        Text("Choose this printer in the Print dialog of any app. You can unplug the USB cable.", bundle: .module)
                    } else {
                        Text("Choose this printer in the Print dialog of any app. To change its Wi-Fi network, connect the USB cable.", bundle: .module)
                    }
                }
                .font(.callout).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .safeAreaInset(edge: .bottom) {
            HStack {
                if printer.link == .usb {
                    Button { changeNetwork = true } label: { Text("Change Network…", bundle: .module) }
                }
                Spacer()
                if printer.addedToMac {
                    Button { openWindow(id: "settings") } label: { Text("Printer Settings…", bundle: .module) }
                } else {
                    Button { printer.addToMac() } label: { Text("Add to This Mac", bundle: .module) }
                        .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                }
            }
            .padding([.horizontal, .bottom], 20)
        }
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
            HStack {
                Spacer()
                if changeNetwork {
                    Button { changeNetwork = false; printer.phase = .ready } label: { Text("Cancel", bundle: .module) }
                        .keyboardShortcut(.cancelAction)
                }
                Button { printer.connect(ssid: ssid, password: password) } label: { Text("Connect", bundle: .module) }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(printer.config == nil || ssid.isEmpty)
            }
            .padding([.horizontal, .bottom], 20)
        }
    }
}
