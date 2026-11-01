import SwiftUI
import XprinterKit

@main
struct XprinterSetupApp: App {
    @StateObject private var printer = PrinterModel()

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

        // The standard macOS settings window: tabs in the toolbar, "Settings…" (⌘,) in the app menu.
        Settings {
            SettingsView().environmentObject(printer)
        }
    }
}

/// Opens the Settings window: SettingsLink on macOS 14+, the AppKit action on macOS 13.
struct SettingsButton<Label: View>: View {
    @ViewBuilder let label: () -> Label

    var body: some View {
        if #available(macOS 14.0, *) {
            SettingsLink(label: label)
        } else {
            Button(action: openSettingsWindow, label: label)
        }
    }
}

/// Presses "Settings…" (⌘,) in the app menu, which SwiftUI creates for the Settings scene; works on every macOS.
func openSettingsWindow() {
    let item = NSApp.mainMenu?.items.first?.submenu?.items.first { $0.keyEquivalent == "," }
    if let item, let action = item.action {
        NSApp.sendAction(action, to: item.target, from: item)
    } else {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
    }
}
