import SwiftUI
import XprinterKit

/// Printer settings read from the printer and written back immediately (USB).
struct SettingsView: View {
    @EnvironmentObject var printer: PrinterModel
    @State private var density = 8.0
    @State private var confirmTestPage = false
    @State private var showPosition = Demo.isOn

    var body: some View {
        if let c = printer.config {
            Form {
                Section {
                    LabeledContent {
                        HStack {
                            Slider(value: $density, in: 0...15, step: 1) { editing in
                                if !editing { printer.apply(XprinterCommand.density(Int(density))) }
                            }
                            Text("\(Int(density))").monospacedDigit().frame(width: 22, alignment: .trailing)
                        }
                    } label: { Text("Darkness", bundle: .module) }

                    Picker(selection: Binding(get: { c.speed ?? 4 }, set: { printer.apply(XprinterCommand.speed($0)) })) {
                        ForEach(2...6, id: \.self) { Text("\($0) in/s", bundle: .module).tag($0) }
                    } label: { Text("Speed", bundle: .module) }

                    Toggle(isOn: Binding(get: { c.rotated ?? false },
                                         set: { printer.apply(XprinterCommand.direction(rotated: $0, mirrored: c.mirrored ?? false)) })) {
                        Text("Rotate 180°", bundle: .module)
                    }
                    Toggle(isOn: Binding(get: { c.mirrored ?? false },
                                         set: { printer.apply(XprinterCommand.direction(rotated: c.rotated ?? false, mirrored: $0)) })) {
                        Text("Mirror", bundle: .module)
                    }
                    Toggle(isOn: Binding(get: { c.reprint ?? true }, set: { printer.apply(XprinterCommand.reprint($0)) })) {
                        Text("Reprint after an error", bundle: .module)
                    }
                } header: { Text("Printing", bundle: .module) }

                Section {
                    if let size = printer.labelSize {
                        mm("Width", size.width, LabelSize.widthRange) { printer.setLabelSize(width: $0, height: size.height) }
                        mm("Height", size.height, LabelSize.heightRange) { printer.setLabelSize(width: size.width, height: $0) }
                    } else {
                        Text("Add the printer to this Mac first.", bundle: .module).foregroundStyle(.secondary)
                    }
                } header: { Text("Labels", bundle: .module) }
                  footer: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("The default paper size when you print from any app. Change it when you load a roll of another size.", bundle: .module)
                        if let e = printer.labelError { Text(e).foregroundStyle(.red) }
                    }
                    .font(.callout).foregroundStyle(.secondary)
                }

                Section {
                    DisclosureGroup(isExpanded: $showPosition) {
                        dots("Tear-off offset", c.offset) { printer.apply(XprinterCommand.offset($0)) }
                        dots("Shift horizontally", c.shiftX) { printer.apply(XprinterCommand.shift(x: $0, y: c.shiftY ?? 0)) }
                        dots("Shift vertically", c.shiftY) { printer.apply(XprinterCommand.shift(x: c.shiftX ?? 0, y: $0)) }
                        dots("Origin X", c.referenceX) { printer.apply(XprinterCommand.reference(x: $0, y: c.referenceY ?? 0)) }
                        dots("Origin Y", c.referenceY) { printer.apply(XprinterCommand.reference(x: c.referenceX ?? 0, y: $0)) }
                    } label: { Text("Fine position", bundle: .module) }
                } footer: {
                    Text("Values are in dots: 8 dots = 1 mm.", bundle: .module).font(.callout).foregroundStyle(.secondary)
                }

                Section {
                    info("Model", c.model)
                    info("Firmware", c.firmware)
                    if c.hasWiFi {
                        info("Wi-Fi address", c.wifiIP ?? loc("Not connected"))
                        info("Printer’s own network", c.accessPointName)
                        info("Wi-Fi module", c.wifiModule)
                    }
                    Button { confirmTestPage = true } label: { Text("Print Test Page…", bundle: .module) }
                } header: { Text("About This Printer", bundle: .module) }

                Section {
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

                if let e = printer.settingsError {
                    Label(e, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(Demo.isOn)  // screenshots: a non-scrolling form can be snapshotted
            .onAppear { density = Double(c.density ?? 8); Task { await printer.loadLabelSize() } }
            .onChange(of: c.density) { density = Double($0 ?? 8) }
            .confirmationDialog(Text("Print a test page?", bundle: .module), isPresented: $confirmTestPage) {
                Button { printer.printSelfTest() } label: { Text("Print", bundle: .module) }
            } message: {
                Text("The page lists the printer’s settings and uses about one label.", bundle: .module)
            }
        } else {
            VStack(spacing: 10) {
                Image(systemName: "cable.connector").font(.system(size: 36)).foregroundStyle(.secondary)
                Text("Connect the printer with a USB cable, or turn it on if it is already set up on Wi-Fi.", bundle: .module)
                    .multilineTextAlignment(.center).foregroundStyle(.secondary)
            }
            .padding(40)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

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

    /// Number field with stepper, like in System Settings. Values are in dots.
    private func dots(_ title: String.LocalizationValue, _ value: Int?, set: @escaping (Int) -> Void) -> some View {
        let binding = Binding(get: { value ?? 0 }, set: { set(min(max($0, -400), 400)) })
        return LabeledContent {
            HStack(spacing: 6) {
                TextField("", value: binding, format: .number)
                    .labelsHidden().multilineTextAlignment(.trailing).frame(width: 56)
                    .textFieldStyle(.roundedBorder)
                Stepper("", value: binding, in: -400...400).labelsHidden()
            }
        } label: { Text(loc(title)) }
    }
}
