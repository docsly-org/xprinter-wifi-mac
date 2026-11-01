# Development guide

Everything needed to continue work on Xprinter Setup from a fresh clone.

## First steps after cloning

```sh
git clone https://github.com/docsly-org/xprinter-wifi-mac.git
cd xprinter-wifi-mac
scripts/setup-dev.sh        # commits in this repo are signed as docsly-org (not your global git name)
swift test                  # 15 unit tests, 2 live tests skipped
./build-app.sh              # → dist/Xprinter Setup.app and dist/Xprinter-Setup.zip
```

Needs macOS 13+ with Xcode (Swift 5.9+), and `gh` logged in as docsly-org for releases.

**Always run `scripts/setup-dev.sh` in a new clone.** Without it git uses your global name and email, and they end up in the public history.

## How the code is laid out

| File | Role |
|---|---|
| `Sources/XprinterKit/Commands.swift` | TSPL commands, validation, `Xprinter` (one exchange at a time over USB or Wi-Fi), `PrinterLink` |
| `Sources/XprinterKit/USBPrinter.swift` | Two-way USB via `IOUSBHostInterface` (no libusb) |
| `Sources/XprinterKit/NetworkPrinter.swift` | TCP 9100 with graceful close; the Wi-Fi module limitation is described here |
| `Sources/XprinterKit/Discovery.swift` | Vendor UDP broadcast search (port 22368) |
| `Sources/XprinterKit/PrinterConfig.swift` / `PrinterStatus.swift` | Parse `ALLCONFIG` and the `ESC ! ?` status byte |
| `Sources/XprinterKit/CUPS.swift` / `LabelSize.swift` | macOS printers: list (language-independent), add the Wi-Fi queue, default label size in the PPD |
| `Sources/XprinterSetup/PrinterModel.swift` | App state: which link to use, when to ask the printer, setup / restart / calibration flows |
| `Sources/XprinterSetup/SetupView.swift` / `SettingsView.swift` | Main window / Printer Settings window |
| `Sources/XprinterSetup/WiFiScanner.swift` | Nearby 2.4 GHz networks (needs Location access) |
| `Sources/XprinterSetup/Demo.swift` | `--screenshots <dir>`: sample data, never touches a printer |
| `Sources/*/Resources/*.lproj`, `AppResources/*.lproj` | Russian strings; English strings are the keys. `AppResources` = permission prompts (InfoPlist.strings) |
| `tools/make-icon.swift` | Draws `Assets/AppIcon.icns` and `.png` |
| `docs/PROTOCOL.md` | Everything known about the printer — read before adding a printer feature |

## Rules for printer features

The printer is real hardware; a wrong command can lose settings or damage the head.

1. Look the command up in `docs/PROTOCOL.md`. Only ✅ commands go into the app unchanged.
2. Before trying anything new on the printer: save its configuration (`ALLCONFIG` over USB) to compare and restore.
3. Change one value, read it back, restore the original, compare the whole configuration with the saved copy.
4. Never send: `ESC ! C` (factory reset), `XA…JUSXZ` / `SD…` / `TA…` (factory head adjustments), `INITIALPRINTER`, `WIFI SETAP` security `0` or `1`.
5. Over Wi-Fi ask for replies as rarely as possible and never poll in the background (the module fails ~30 min after start, see PROTOCOL §4). Prefer USB for settings and tests.
6. Things that use paper (calibration, self-test) only with a confirmation in the UI.
7. Update `docs/PROTOCOL.md` with what you verified.

Live tests (read-only): `XPRINTER_LIVE=1 swift test` with the printer on USB; add `XPRINTER_LIVE_IP=<ip>` for the Wi-Fi read (costs one reply from the Wi-Fi module).

## Making a release

1. `Info.plist`: raise `CFBundleShortVersionString` (e.g. 1.5.1 → 1.6) **and** `CFBundleVersion` (+1).
2. `swift test`.
3. `./build-app.sh`. It builds in `/tmp/xprinter-setup-build` and strips the binary, so no user name or home path ends up inside the app. Check: `grep -c -a /Users/ "dist/Xprinter Setup.app/Contents/MacOS/XprinterSetup"` → `0`.
4. If the UI changed, refresh screenshots: `"dist/Xprinter Setup.app/Contents/MacOS/XprinterSetup" -AppleLanguages "(en)" --screenshots Screenshots`, then `"(ru)"`. The settings window height for screenshots is set in `App.swift` (`Demo.isOn ? … : 420`).
5. Make sure nothing private is in the repo (your Wi-Fi name and password, home addresses, serial numbers).
6. Commit, `git push`, then:
   `gh release create vX.Y dist/Xprinter-Setup.zip --title "Xprinter Setup X.Y" --notes "…"`
   End the notes with: *Universal app, macOS 13+. Not notarized: on first launch open it via System Settings → Privacy & Security → Open Anyway (see README). Provided as is, without warranty.*
7. Update both `README.md` and `README.ru.md` when behaviour changes.

## Not in this repository (on purpose)

- Decompiled code of the vendor's Diagnostic Tool and notes on how it was analysed — private (vendor code must not be published). Everything useful from it is in `docs/PROTOCOL.md`.
- Backups of a real printer's configuration.
