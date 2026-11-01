import SwiftUI
import XprinterKit

/// Tabs of the Settings window, like the settings of Apple's own apps.
enum SettingsTab: String, CaseIterable {
    case printing, labels, network, about
}

/// Printer settings in tabs. Values are read from the printer and written back immediately.
struct SettingsView: View {
    @EnvironmentObject var printer: PrinterModel

    var body: some View {
        TabView(selection: $printer.settingsTab) {
            PrintingTab().tabItem { Label { Text("Printing", bundle: .module) } icon: { Image(systemName: "printer") } }
                .tag(SettingsTab.printing)
            LabelsTab().tabItem { Label { Text("Labels", bundle: .module) } icon: { Image(systemName: "tag") } }
                .tag(SettingsTab.labels)
            NetworkTab().tabItem { Label { Text("Network", bundle: .module) } icon: { Image(systemName: "wifi") } }
                .tag(SettingsTab.network)
            AboutTab().tabItem { Label { Text("About", bundle: .module) } icon: { Image(systemName: "info.circle") } }
                .tag(SettingsTab.about)
        }
        .frame(width: 480)
        .onAppear { printer.refresh(); Task { await printer.loadLabelSize() } }
    }
}

// MARK: - Tabs

private struct PrintingTab: View {
    @EnvironmentObject var printer: PrinterModel
    @State private var density = 8.0

    var body: some View {
        PrinterForm(height: 495) { c in
            Section {
                LabeledContent {
                    HStack {
                        Slider(value: $density, in: 0...15, step: 1) { editing in
                            if !editing { printer.apply(XprinterCommand.density(Int(density)), shows: ["Density": "\(Int(density)).0"]) }
                        }
                        Text("\(Int(density))").monospacedDigit().frame(width: 22, alignment: .trailing)
                    }
                } label: { Text("Darkness", bundle: .module) }

                Picker(selection: Binding(get: { c.speed ?? 4 }, set: { printer.apply(XprinterCommand.speed($0), shows: ["Speed": "\($0) Inch"]) })) {
                    ForEach(2...6, id: \.self) { Text("\($0) in/s", bundle: .module).tag($0) }
                } label: { Text("Speed", bundle: .module) }

                Toggle(isOn: Binding(get: { c.rotated ?? false },
                                     set: { printer.apply(XprinterCommand.direction(rotated: $0, mirrored: c.mirrored ?? false), shows: ["Direction": $0 ? "1" : "0"]) })) {
                    Text("Rotate 180°", bundle: .module)
                }
                Toggle(isOn: Binding(get: { c.mirrored ?? false },
                                     set: { printer.apply(XprinterCommand.direction(rotated: c.rotated ?? false, mirrored: $0), shows: ["Mirror": $0 ? "ON" : "OFF"]) })) {
                    Text("Mirror", bundle: .module)
                }
                Toggle(isOn: Binding(get: { c.reprint ?? true }, set: { printer.apply(XprinterCommand.reprint($0), shows: ["Reprint": $0 ? "ON" : "OFF"]) })) {
                    Text("Reprint after an error", bundle: .module)
                }
            }

            Section {
                millimetres("Shift left / right", c.shiftX) { printer.apply(XprinterCommand.shift(x: $0, y: c.shiftY ?? 0), shows: ["Shift X": "\($0)"]) }
                millimetres("Shift up / down", c.shiftY) { printer.apply(XprinterCommand.shift(x: c.shiftX ?? 0, y: $0), shows: ["Shift Y": "\($0)"]) }
                millimetres("Feed after printing", c.offset) { printer.apply(XprinterCommand.offset($0), shows: ["Offset": "\($0)"]) }
            } header: { Text("Position on the label", bundle: .module) }
              footer: {
                Text("If printing is off the label, shift it. Feed after printing: how far the label comes out, so it is easy to tear off.", bundle: .module)
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .onAppear { density = Double(printer.config?.density ?? 8) }
        .onChange(of: printer.config?.density) { density = Double($0 ?? 8) }
    }
}

private struct LabelsTab: View {
    @EnvironmentObject var printer: PrinterModel
    @State private var confirmCalibration = false

    enum Paper: Hashable { case labels, continuous }

    var body: some View {
        PrinterForm(height: 420) { c in
            Section {
                Picker(selection: Binding(get: { c.sensor == .continuous ? Paper.continuous : .labels }, set: choose)) {
                    Text("Labels with gaps", bundle: .module).tag(Paper.labels)
                    Text("Continuous paper", bundle: .module).tag(Paper.continuous)
                } label: { Text("Paper", bundle: .module) }
                .disabled(!printer.usbPlugged || printer.calibrating)

                if c.sensor != .continuous {
                    LabeledContent { Text(measuredText(c)) } label: { Text("Label length", bundle: .module) }
                    HStack {
                        Spacer()
                        if printer.calibrating { ProgressView().controlSize(.small) }
                        Button { confirmCalibration = true } label: { Text("Calibrate…", bundle: .module) }
                            .disabled(!printer.usbPlugged || printer.calibrating)
                    }
                }
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Switching paper type feeds nothing. After loading a roll of another size, calibrate: the printer feeds 2–3 labels without printing and learns their length.", bundle: .module)
                    if !printer.usbPlugged { Text("Needs the USB cable.", bundle: .module) }
                }
                .font(.callout).foregroundStyle(.secondary)
            }

            Section {
                if let size = printer.labelSize {
                    mm("Width", size.width, LabelSize.widthRange) { printer.setLabelSize(width: $0, height: size.height) }
                    mm("Height", size.height, LabelSize.heightRange) { printer.setLabelSize(width: size.width, height: $0) }
                } else {
                    Text("Add the printer to this Mac first.", bundle: .module).foregroundStyle(.secondary)
                }
            } header: { Text("Default paper size", bundle: .module) }
              footer: {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Used when you print from any app.", bundle: .module)
                    if let e = printer.labelError { Text(e).foregroundStyle(.red) }
                }
                .font(.callout).foregroundStyle(.secondary)
            }
        }
        .confirmationDialog(Text("Calibrate to the loaded roll?", bundle: .module), isPresented: $confirmCalibration) {
            Button { printer.calibrate() } label: { Text("Calibrate", bundle: .module) }
        } message: {
            Text("The printer feeds 2–3 labels and prints nothing on them.", bundle: .module)
        }
    }

    /// Both switches are instant and feed nothing; only labels never measured before need a calibration.
    private func choose(_ paper: Paper) {
        guard let c = printer.config else { return }
        switch paper {
        case .continuous:
            printer.apply(XprinterCommand.continuousPaper, shows: ["Sensor Mode": "CONTINUOUS(T)"])
        case .labels:
            if let gap = c.gapDots, c.labelLengthMM ?? 0 > 0 {
                printer.apply(XprinterCommand.gapLabels(gapDots: gap, offsetDots: c.gapOffsetDots), shows: ["Sensor Mode": "GAP"])
            } else {
                confirmCalibration = true
            }
        }
    }

    private func measuredText(_ c: PrinterConfig) -> String {
        guard c.sensor == .gap, let l = c.labelLengthMM, let g = c.gapMM else { return "—" }
        return String(format: loc("%@ mm, gap %@ mm"), mmText(l), mmText(g))
    }
}

private struct NetworkTab: View {
    @EnvironmentObject var printer: PrinterModel
    @State private var newAPPassword = ""
    @State private var changingAP = false
    @State private var apChanged = false
    @State private var showAPPassword = false

    var body: some View {
        PrinterForm(height: 440) { c in
            Section {
                info("Wi-Fi address", c.wifiIP ?? loc("Not connected"))
                Picker(selection: $printer.preference) {
                    Text("Automatically", bundle: .module).tag(PrinterModel.LinkPreference.auto)
                    Text("USB only", bundle: .module).tag(PrinterModel.LinkPreference.usb)
                    Text("Wi-Fi only", bundle: .module).tag(PrinterModel.LinkPreference.wifi)
                } label: { Text("Connection", bundle: .module) }
            } footer: {
                Group {
                    if printer.link == .usb { Text("Now connected over USB.", bundle: .module) }
                    else if case .network(let ip) = printer.link { Text("Now connected over Wi-Fi (\(ip)).", bundle: .module) }
                }
                .font(.callout).foregroundStyle(.secondary)
            }

            if c.hasWiFi, let name = c.accessPointName {
                Section {
                    info("Network name", name)
                    if let pin = c.accessPointPassword {
                        LabeledContent {
                            HStack(spacing: 6) {
                                Text(verbatim: showAPPassword ? pin : String(repeating: "•", count: pin.count))
                                    .textSelection(.enabled).monospaced()
                                Button { showAPPassword.toggle() } label: { Image(systemName: showAPPassword ? "eye.slash" : "eye") }
                                    .buttonStyle(.borderless)
                                    .help(showAPPassword ? Text("Hide", bundle: .module) : Text("Show", bundle: .module))
                            }
                        } label: { Text("Current password", bundle: .module) }
                    }
                    LabeledContent {
                        HStack(spacing: 6) {
                            SecureField(text: $newAPPassword, prompt: Text("8–63 characters", bundle: .module)) { EmptyView() }
                                .labelsHidden().textFieldStyle(.roundedBorder).frame(width: 150)
                            if changingAP { ProgressView().controlSize(.small) }
                            Button { changeAPPassword() } label: { Text("Change", bundle: .module) }
                                .disabled(!printer.usbPlugged || changingAP || !XprinterCommand.isValidAccessPointPassword(newAPPassword))
                        }
                    } label: { Text("New password", bundle: .module) }
                } header: { Text("Printer’s Own Network", bundle: .module) }
                  footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        if c.accessPointPassword == XprinterCommand.defaultAccessPointPassword {
                            Label { Text("The factory password 12345678 is still set — anyone nearby can join and use the printer. Change it.", bundle: .module) }
                                icon: { Image(systemName: "exclamationmark.triangle.fill") }
                                .foregroundStyle(.orange)
                        } else if apChanged {
                            Label { Text("Password changed.", bundle: .module) } icon: { Image(systemName: "checkmark.circle.fill") }
                                .foregroundStyle(.green)
                        }
                        Text("The printer broadcasts its own Wi-Fi so you can connect without a router. WPA2 protection. Needs the USB cable.", bundle: .module)
                    }
                    .font(.callout).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func changeAPPassword() {
        changingAP = true; apChanged = false
        Task {
            apChanged = await printer.setAccessPointPassword(newAPPassword)
            if apChanged { newAPPassword = "" }
            changingAP = false
        }
    }
}

private struct AboutTab: View {
    @EnvironmentObject var printer: PrinterModel
    @State private var confirmTestPage = false

    var body: some View {
        PrinterForm(height: 290) { c in
            Section {
                info("Model", c.model)
                info("Firmware", c.firmware)
                if c.hasWiFi { info("Wi-Fi module", c.wifiModule) }
            }
            Section {
                Button { confirmTestPage = true } label: { Text("Print Test Page…", bundle: .module) }
            } footer: {
                Text("The page lists the printer’s settings and uses about one label.", bundle: .module)
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
        .confirmationDialog(Text("Print a test page?", bundle: .module), isPresented: $confirmTestPage) {
            Button { printer.printSelfTest() } label: { Text("Print", bundle: .module) }
        } message: {
            Text("The page lists the printer’s settings and uses about one label.", bundle: .module)
        }
    }
}

// MARK: - Shared pieces

/// A grouped form for one tab; shows a hint instead when no printer is connected.
private struct PrinterForm<Content: View>: View {
    @EnvironmentObject var printer: PrinterModel
    let height: CGFloat
    @ViewBuilder let content: (PrinterConfig) -> Content

    var body: some View {
        Group {
            if let c = printer.config {
                Form {
                    content(c)
                    if let e = printer.settingsError {
                        Label(e, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
                    }
                }
                .formStyle(.grouped)
                .scrollDisabled(Demo.isOn)  // screenshots: a non-scrolling form can be snapshotted
            } else {
                VStack(spacing: 10) {
                    Image(systemName: "cable.connector").font(.system(size: 36)).foregroundStyle(.secondary)
                    Text("Connect the printer with a USB cable, or turn it on if it is already set up on Wi-Fi.", bundle: .module)
                        .multilineTextAlignment(.center).foregroundStyle(.secondary)
                }
                .padding(40)
            }
        }
        .frame(height: height)
    }
}

private func mmText(_ v: Double) -> String { v.formatted(.number.precision(.fractionLength(0...1))) }

private func info(_ title: String.LocalizationValue, _ value: String?) -> some View {
    LabeledContent { Text(value ?? "—").textSelection(.enabled) } label: { Text(loc(title)) }
}

/// Millimetre field; applies on Return or when focus leaves.
private func mm(_ title: String.LocalizationValue, _ value: Double, _ range: ClosedRange<Double>,
                set: @escaping (Double) -> Void) -> some View {
    LabeledContent {
        HStack(spacing: 6) {
            TextField("", value: Binding(get: { value }, set: { set(min(max($0, range.lowerBound), range.upperBound)) }),
                      format: .number.precision(.fractionLength(0...1)))
                .labelsHidden().multilineTextAlignment(.trailing).frame(width: 64)
                .textFieldStyle(.roundedBorder)
            Text("mm", bundle: .module).foregroundStyle(.secondary)
        }
    } label: { Text(loc(title)) }
}

/// Field with stepper in millimetres (step 0.5); the printer stores dots (203 dpi: 8 dots = 1 mm).
private func millimetres(_ title: String.LocalizationValue, _ dots: Int?, set: @escaping (Int) -> Void) -> some View {
    let binding = Binding<Double>(get: { Double(dots ?? 0) / 8 },
                                  set: { set(Int((min(max($0, -50), 50) * 8).rounded())) })
    return LabeledContent {
        HStack(spacing: 6) {
            TextField("", value: binding, format: .number.precision(.fractionLength(0...1)))
                .labelsHidden().multilineTextAlignment(.trailing).frame(width: 56)
                .textFieldStyle(.roundedBorder)
            Text("mm", bundle: .module).foregroundStyle(.secondary)
            Stepper("", value: binding, in: -50...50, step: 0.5).labelsHidden()
        }
    } label: { Text(loc(title)) }
}
