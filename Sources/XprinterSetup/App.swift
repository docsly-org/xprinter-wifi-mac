import SwiftUI
import XprinterKit

@main
struct XprinterSetupApp: App {
    @StateObject private var printer = PrinterModel()
    @Environment(\.openWindow) private var openWindow

    var body: some Scene {
        Window(Text("Xprinter Setup", bundle: .module), id: "main") {
            SetupView()
                .environmentObject(printer)
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
                    printer.refresh()
                }
                .frame(width: 420)
                .fixedSize(horizontal: false, vertical: true)
        }
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button { openWindow(id: "settings") } label: { Text("Printer Settings…", bundle: .module) }
                    .keyboardShortcut(",")
            }
        }

        Window(Text("Printer Settings", bundle: .module), id: "settings") {
            SettingsView()
                .environmentObject(printer)
                .frame(width: 460)
                .frame(minHeight: Demo.isOn ? 1060 : 420)
        }
        .windowResizability(.contentSize)
    }
}
