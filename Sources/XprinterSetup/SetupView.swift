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
    @State private var typingAddress = false
    @State private var address = ""
    @State private var addressFailed = false
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
        .onChange(of: printer.setupCompleted) { _ in changeNetwork = false }
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
        if printer.notResponding {
            dot(.red) { Text("Not responding", bundle: .module) }
        } else if printer.config == nil {
            Text("Connect the printer with a USB cable, or turn it on if it is already set up on Wi-Fi.", bundle: .module)
                .multilineTextAlignment(.center).padding(.horizontal, 32)
        } else if printer.config?.wifiIP == nil {
            dot(.secondary) { Text("Not on Wi-Fi", bundle: .module) }
        } else if printer.wifiDown {
            dot(.orange) { Text("Wi-Fi module is offline", bundle: .module) }
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
        case .waitingForPrinter where printer.notResponding:
            VStack(spacing: 12) {
                if printer.usbPlugged {
                    Text("The printer’s Wi-Fi module sometimes hangs and stops the printer. A restart fixes it; settings are kept.", bundle: .module)
                        .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button { printer.restartPrinter() } label: { Text("Restart Printer", bundle: .module) }
                        .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                } else {
                    Text("The printer does not answer. Turn it off, wait 5 seconds and turn it on again.", bundle: .module)
                        .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    Button { printer.refresh(deep: true) } label: { Text("Check Again", bundle: .module) }
                }
            }
            .padding(.horizontal, 24).padding(.top, 16).padding(.bottom, 28)

        case .waitingForPrinter:
            VStack(spacing: 14) {
                ProgressView().controlSize(.small)
                if typingAddress {
                    HStack {
                        TextField(text: $address, prompt: Text(verbatim: "192.168.1.50")) { Text("IP Address", bundle: .module) }
                            .labelsHidden().textFieldStyle(.roundedBorder).frame(width: 160)
                            .onSubmit(useAddress)
                        Button(action: useAddress) { Text("Connect", bundle: .module) }
                            .disabled(address.isEmpty)
                    }
                    if addressFailed {
                        Text("No Xprinter answers at this address.", bundle: .module).font(.callout).foregroundStyle(.red)
                    } else {
                        Text("The address is on the printer’s self-test page (STA IP) or in this app on the Mac where the printer was set up.", bundle: .module)
                            .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                } else {
                    Button { typingAddress = true } label: { Text("Printer already on Wi-Fi? Enter Its Address…", bundle: .module) }
                        .buttonStyle(.link)
                }
            }
            .padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 28)

        case .working(let step):
            VStack(spacing: 12) {
                ProgressView().controlSize(.small)
                Text(step).font(.callout).foregroundStyle(.secondary)
            }
            .padding(.vertical, 36)

        case .ready, .failed:
            if let ip = printer.config?.wifiIP, !changeNetwork {
                status(ip: ip)
            } else {
                form
            }
        }
    }

    private func useAddress() {
        addressFailed = false
        Task { addressFailed = !(await printer.useAddress(address)) }
    }

    /// Printer on Wi-Fi: facts about it, nothing to type.
    private func status(ip: String) -> some View {
        Form {
            Section {
                LabeledContent { Text(ip).textSelection(.enabled) } label: { Text("IP Address", bundle: .module) }
                LabeledContent {
                    printer.macPrinterName.map { Text(verbatim: $0) } ?? Text("Not added", bundle: .module)
                } label: { Text("Printer in macOS", bundle: .module) }
                LabeledContent {
                    Text(verbatim: printer.link == .usb ? "USB" : "Wi-Fi")
                } label: { Text("Connected via", bundle: .module) }
            } footer: {
                Group {
                    if printer.wifiDown {
                        Text("The printer is on USB, but its Wi-Fi module dropped off the network. Reconnecting takes a few seconds; settings are kept.", bundle: .module)
                    } else if case .failed(let message) = printer.phase {
                        VStack(alignment: .leading, spacing: 4) {
                            Label(message, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
                            if printer.needsDriver {
                                Link(destination: URL(string: "https://www.xprintertech.com/")!) {
                                    Text("Download the Xprinter Driver…", bundle: .module)
                                }
                            }
                        }
                    } else if !printer.addedToMac {
                        Text("Add the printer to print to it from this Mac.", bundle: .module)
                    } else if printer.usbPlugged {
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
                if printer.usbPlugged {
                    Button { printer.phase = .ready; changeNetwork = true } label: { Text("Change Network…", bundle: .module) }
                }
                Spacer()
                if printer.wifiDown {
                    Button { printer.restartWiFi() } label: { Text("Reconnect Wi-Fi", bundle: .module) }
                        .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
                } else if !printer.addedToMac {
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
