<p align="center"><img src="Assets/AppIcon.png" width="128" alt="Xprinter Setup app icon"></p>

<h1 align="center">Xprinter Setup for macOS</h1>

<p align="center">
  Set up Wi-Fi on an <b>Xprinter XP-420B</b> label printer from a Mac — no Windows, no vendor tool, no wasted labels.<br>
  <b>English</b> · <a href="README.ru.md">Русский</a>
</p>

<p align="center">
  <img src="Screenshots/setup-en.png" width="270" alt="Main window: choose a Wi-Fi network, type the password, press Connect">
  <img src="Screenshots/done-en.png" width="270" alt="Printer ready to print over Wi-Fi, with its IP address and macOS printer name">
  <img src="Screenshots/settings-en.png" width="230" alt="Printer Settings: darkness, speed, labels, calibration, printer's own network">
</p>
<p align="center"><sub>Connect · Ready to print · Printer Settings</sub></p>

## What it does

- **Connects the printer to your Wi-Fi in one click.** Pick a network (only 2.4 GHz ones are listed — the printer can't use 5 GHz), type the password, press **Connect**. The app sends the settings over USB, asks the printer for its new address and adds it to macOS as a Wi-Fi printer. No test pages.
- **Recognizes a printer that is already set up**, and adds it to another Mac — found on the network, or by its address.
- **Printer Settings** (⌘,) over USB, or over Wi-Fi without the cable: darkness, speed, rotate 180°, mirror, reprint after an error, fine position.
- **Labels:** default label size for every app, and **Calibrate to the Roll** — the printer feeds 2–3 blank labels and learns their length.
- **Printer status:** cover open, out of labels, paper jam.
- **Fixes without the power button:** **Reconnect Wi-Fi** and **Restart Printer** (see [Known limitation](#known-printer-limitation-wi-fi-stays-healthy-for-about-30-minutes)).
- **Printer's own network:** see and change the password of the printer's built-in Wi-Fi (factory password `12345678`).
- English and Russian, following the system language. Universal app (Apple Silicon and Intel).

## Tested printer

**Xprinter XP-420B (USB + Wi-Fi, 203 dpi, 108 mm)**, firmware 1.040.3552, Wi-Fi module X4_V95.0.9.

This is the only printer it was tested on. Other Xprinter label printers that speak TSPL and have the same Wi-Fi module will *probably* work, because the vendor's Windows tool uses the same commands for all of them — but this has not been checked. Reports are welcome in [Issues](../../issues).

## Install

1. **Install the Xprinter macOS driver** from [xprintertech.com](https://www.xprintertech.com/) (Support → Download). macOS does not include it. The app can set up Wi-Fi without it, but printing needs it.
2. Download `Xprinter-Setup.zip` from [Releases](../../releases/latest), unzip, move **Xprinter Setup** to Applications.
3. Open it. The app is not notarized by Apple, so the first time macOS blocks it — that is expected:
   1. macOS says *“Xprinter Setup” Not Opened*. Click **Done**.
   2. Open **System Settings → Privacy & Security** and scroll down to **Security**: *“Xprinter Setup” was blocked to protect your Mac.* Click **Open Anyway**.
   3. macOS asks *Open “Xprinter Setup”?* Click **Open Anyway** and confirm with Touch ID or your password.

   macOS remembers this; later launches open normally. Apple's own guide: [Open a Mac app from an unknown developer](https://support.apple.com/guide/mac-help/open-a-mac-app-from-an-unknown-developer-mh40616/mac). On macOS 14 and older, right-click the app → **Open** → **Open** also works; since macOS 15 it doesn't.

   Prefer Terminal? `xattr -dr com.apple.quarantine "/Applications/Xprinter Setup.app"` removes the “downloaded from the internet” mark, then the app opens normally.

Requires macOS 13 or later.

## How to use

1. Connect the printer with a USB cable and turn it on.
2. Choose your Wi-Fi network, enter the password, press **Connect**.
3. In about 30 seconds the dot turns green: **Ready to print over Wi-Fi**. Choose “Xprinter XP-420B (Wi-Fi)” in any Print dialog and unplug the cable.

**Tip:** reserve the printer's address in your router (DHCP reservation), so it never changes.

**Another Mac?** Install the driver and open the app there. It finds the printer on the network, or asks for its address (shown in the app on the first Mac, or as `STA IP` on the self-test page), then **Add to This Mac**.

**New roll?** Printer Settings → Labels → **Calibrate to the Roll…** (USB). Then type the label width and height: that becomes the default paper size, so apps start with it.

**Printer's own network.** The printer also broadcasts its own Wi-Fi (`XP-420B`) for direct connections without a router. With the factory password `12345678` anyone nearby can join it — change it in Printer Settings → Printer's Own Network (USB, WPA2). Printing from the Mac goes through your router and is not affected.

**Connection.** By default the app uses USB when the cable is plugged in and Wi-Fi otherwise. Printer Settings → Connection lets you force one. Changing the Wi-Fi network always needs the cable, so a typo in the password can't lock you out.

## Known printer limitation: Wi-Fi stays healthy for about 30 minutes

Found while building this app, on an XP-420B with Wi-Fi module X4_V95.0.9 and a Xiaomi router. Repeated four times, with and without traffic:

- About **30–35 minutes after the Wi-Fi module starts**, it goes bad on its own: it either **drops off the network**, or keeps the connection but **hangs mid-transfer** — and then the whole printer stops answering, even on USB, with the blue light still on.
- At that point printing over Wi-Fi fails too. Printing over **USB is not affected** while the printer itself is not stuck.
- It is **not the driver** (the tests talked to the printer directly) and **not load** (it happens after 30 minutes of complete silence too).
- A guess, not verified: many cheap Wi-Fi modules break when the router renews its encryption keys; the timing fits.

**What helps — all verified on the printer, all keep the settings:**

| Problem | Fix |
|---|---|
| Dropped off the network | **Reconnect Wi-Fi** in the app (`WIFI RESET` over USB) — back in ~6 s |
| Printer stuck, no answer even on USB | **Restart Printer** in the app (the vendor's "Reset Printer": `ESC ! exit`, `ESC ! R`) — back in ~6 s |
| No cable at hand | Turn the printer off and on |

A broken module can't be fixed over the network: it does not pass the fix either. The app asks the printer for replies over Wi-Fi as rarely as possible and never polls it in the background.

**If you rely on Wi-Fi printing**, try on your router (not verified yet): a separate 2.4 GHz network name, a fixed channel (1, 6 or 11), band steering / "smart connect" off, a longer group key update interval if available. If a setting keeps the printer alive longer than 30 minutes, please open an issue.

## FAQ

**macOS blocks the app: “Xprinter Setup” Not Opened.** It is not notarized (that needs a paid Apple developer account). Open it once via **System Settings → Privacy & Security → Open Anyway** — see [Install](#install), step 3.

**Why does it ask for my location?** macOS shows Wi-Fi network names only to apps with Location access. The app asks only when you choose a network, and uses it only for that list. You can deny it and type the network name under **Other Network…**.

**My network is not in the list.** The printer works with 2.4 GHz only; 5 GHz-only networks are hidden. If your router uses one name for both bands, it is listed; otherwise turn on 2.4 GHz on the router.

**The printer is not found / “Not responding”.** Plug in the USB cable: the app offers **Reconnect Wi-Fi** or **Restart Printer**. Without the cable, turn the printer off and on.

**Printing slides across the labels.** Calibrate to the roll (Printer Settings → Labels). After calibration the printer feeds one label when you close the cover — that aligns it to the gap and is normal.

**Printing fails: “driver not installed”.** Install the Xprinter macOS driver (see Install).

## What is deliberately not included

To keep the printer safe: factory reset (`ESC ! C` — it erases everything, Wi-Fi included), factory/head calibration commands, firmware and file operations, a fixed IP address on the printer (reserve it in the router instead), open or WEP security for the printer's own network. Not available on the XP-420B: cutter, peeler, ribbon, Ethernet, Bluetooth.

## Privacy

The app stores nothing but your connection choice and, if you typed one, the printer's address. It talks only to the printer (USB, or your local network) and to macOS printing. No analytics, no internet access. Your Wi-Fi password goes straight to the printer and is not saved.

## The problem this solves

- How to set up Wi-Fi on an Xprinter XP-420B on a Mac / MacBook / macOS
- XP-420B does not connect to Wi-Fi, only shows its own network `XP-420B` (password `12345678`)
- `10.10.100.1` does not open, `ERR_CONNECTION_REFUSED`, no web configuration page
- The self-test page shows `STA IP: 0.0.0.0`
- Xprinter Diagnostic Tool / Wi-Fi config tool works only on Windows
- The Print Label app does not find the printer
- The printer drops off Wi-Fi after a while

## Protocol

Plain TSPL text sent raw to the printer over USB (bulk endpoints of the printer-class interface, vendor ID `0x2D37`) or TCP port 9100. Replies come back on the same channel.

| Command | Effect |
|---|---|
| `WIFI CONNECTION "<ssid>","<password>"` | Join a Wi-Fi network (DHCP) |
| `WIFI RESET` | Restart the Wi-Fi module to apply settings |
| `WIFI GETIP` | Reply `+OK=<address>` (`0.0.0.0` when not connected) |
| `WIFI SETAP "<name>",3,"<password>"` | Printer's own network; `3` = WPA2, `2` = WPA |
| `ALLCONFIG` | Reply with all settings as `Key: Value` lines |
| `OUT "<text>"` | Echo text back — handy as an end-of-reply marker |
| `DENSITY n` (0–15), `SPEED n` (2–6), `DIRECTION r,m`, `SET REPRINT ON/OFF`, `OFFSET n dot`, `SHIFT x,y`, `REFERENCE x,y` | Print settings, stored in the printer |
| `GAPDETECT` | Calibrate to labels with gaps (feeds 2–3 labels) |
| `ESC ! ?` | Status byte: `0x01` cover open (verified); `0x02` jam, `0x04` out of paper (per TSPL, not verified) |
| `ESC ! exit`, `ESC ! R` | Soft restart ("Reset Printer"); settings are kept |
| `SELFTEST` | Print the self-test page |

Strings have no escaping, so names and passwords cannot contain `"`. Without the app, from Terminal:

```sh
printf 'WIFI CONNECTION "MyWiFi","password"\r\nWIFI RESET\r\n' | lp -d Xprinter_XP_420B -o raw
```

The commands were identified for interoperability by examining what the vendor's Windows tool sends, and every command above was verified on a real XP-420B unless marked otherwise. No vendor code is included in this repository.

## Build from source

```sh
swift test                         # unit tests
XPRINTER_LIVE=1 swift test         # plus a read-only check with a printer on USB
./build-app.sh                     # → dist/Xprinter Setup.app and dist/Xprinter-Setup.zip
"dist/Xprinter Setup.app/Contents/MacOS/XprinterSetup" --screenshots Screenshots   # README screenshots (sample data, never touches a printer)
```

## Disclaimer

Free and unofficial, not affiliated with Xprinter. Provided **“as is”, without warranty of any kind** — you use it at your own risk. The authors are not liable for any damage to your printer, data or anything else. [MIT License](LICENSE).
