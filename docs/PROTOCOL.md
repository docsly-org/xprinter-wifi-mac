# Xprinter XP-420B: protocol reference

Everything this project learned about talking to the printer, so new features can be added without analysing the vendor's Windows tool again.

Source of each fact:
- **✅ verified** — tried on a real XP-420B (firmware 1.040.3552, Wi-Fi module X4_V95.0.9) and the result read back.
- **🔍 vendor tool** — this is what Xprinter's *Diagnostic Tool* (Windows) sends; not tried on the printer. Analysed versions: **V1.036** (2024) and **V1.039b** (Dec 2025) — the commands used here are the same in both.
- **📘 TSPL** — standard TSPL behaviour, not tried.

The commands were identified for interoperability. No vendor code is in this repository.

---

## 1. Transports

| Way | Details | Status |
|---|---|---|
| **USB** | Printer-class interface (class 7), vendor ID `0x2D37`, product `0x83D7`. Bulk OUT `0x01`, bulk IN `0x82`. Replies come back on bulk IN. Open the interface only for one exchange, so macOS printing (CUPS) is not blocked. In Swift: `IOUSBHostInterface`, no extra libraries. | ✅ |
| **TCP 9100** | Same commands, replies on the same socket. Close gracefully (shutdown write, read to EOF). | ✅ |
| **CUPS raw** | `lp -d <queue> -o raw` sends bytes one way (no replies). | ✅ |
| **UDP 22368** | Vendor discovery broadcast, see §6. | ✅ (works only in the first minutes after the Wi-Fi module starts) |

All text commands end with `\r\n`. Strings are in double quotes and have **no escaping** — a value must not contain `"`.

**One command at a time.** The printer runs commands from USB and Wi-Fi in one queue. A command that waits for the Wi-Fi module (e.g. `WIFI GETIP` while the module is stuck) blocks everything after it, USB included.

**Reply marker.** Append `OUT "SOME-MARKER"` after a query and read until the marker appears: `OUT` echoes its text plus `\r\n`. ✅

---

## 2. Reading the configuration

`ALLCONFIG` → about 2.5 KB of `Key: Value` lines. ✅ The first line is `<model> Version: <firmware>`. Sample (addresses replaced):

```
XP-420B Version: 1.040.3552 CEZD
Soruce Rev: 1.040.3552.10 2025-07-04
Label Milage: 5
Dot Milage: 27660
Ethernet: NO
Wifi : YES
Wifi Func: ON
Wifi Name: XP-420B            ← printer's own network (AP) name
Wifi Pin: 12345678            ← its password
Wifi Ap Address: 244CAB000000 ← AP MAC
Wifi Sta Address: 264CAB000000← STA MAC
Wifi Ap Ip: 10.10.100.1
Wifi Sta Ip: 192.168.1.50     ← address in your network, 0.0.0.0 = not connected
Wifi Versions: X4_V95.0.9
Bluetooth : NO
Sensor Mode: CONTINUOUS(T)    ← GAP after GAPDETECT; BLINE… for black mark
Print Out: TEAR
Density: 8.0
Paper Size: 1040.0            ← label length in dots (8 dots = 1 mm at 203 dpi)
Gap Size: 24.0                ← gap in dots
Gap Offset: 0.0
Direction: 0
Mirror: OFF
Carriage Open: ON
Reprint: ON
Gap Reference: 610            ← sensor tuning, changes on calibration
Gap Intension: 2
Over Head: 195                ← head temperature reading, not a setting
Limit Feed: 2032
Network Raw Data Port: 9100
Offset: 0
Reference X: 0
Reference Y: 0
Shift X: 0
Shift Y: 0
Speed: 6 Inch
Country Code: 001
Code Page: 850
```

The vendor tool reads the Wi-Fi extras with:
`OUT "START"\r\nALLCONFIG\r\nOUT "WIDHCP="\r\nWIFI GETDHCP\r\nOUT "ENCP"\r\nOUT "WIDHIP="\r\nWIFI GETDHIP\r\nOUT "ENIP"\r\nOUT "END"\r\n` ✅

- `WIFI GETDHCP` → `+OK=1` (1 = DHCP on). ✅
- `WIFI GETDHIP` → `+OK=<ip>,<gateway>,<mask>` (note the order). ✅
- `WIFI GETIP` → `+OK=<sta ip>`, `0.0.0.0` when not connected. ✅ Asks the Wi-Fi module; blocks the queue if the module hangs.

---

## 3. Commands

### Wi-Fi

| Command | Effect | Status |
|---|---|---|
| `WIFI CONNECTION "<ssid>","<password>"` | Join a network (STA, DHCP). Follow with `WIFI RESET`. | ✅ |
| `WIFI RESET` | Restart only the Wi-Fi module; rejoins in ~6 s; settings kept. Fixes a module that dropped off the network. | ✅ |
| `WIFI SETAP "<name>",<security>,"<password>"` | Printer's own network. `3` = WPA2, `2` = WPA (checked by scanning the network from a Mac). `0`/`1` not tried (probably open / WEP) — do not use. Follow with `WIFI RESET`. Password 8–63 ASCII. | ✅ (3, 2) |
| `WIFI SETDHCP <n>` | `1` = DHCP, `0` = static (vendor UI labels: OFF/ON, sends index−1). | 🔍 |
| `WIFI SETDHIP "<ip>","<mask>","<gateway>"` | Static address (note: mask before gateway, unlike GETDHIP). | 🔍 |
| `OUT "WISTART"\r\nWIFI SCAN\r\nOUT "WIEND"` | Printer-side scan of networks. | 🔍 |
| `AT+EAPMODE=…`, `AT+EAPCFG=…`, `AT+CLIKEY=…`, `AT+CICA=…`, `AT+EAPEN=0/1`, `AT+REBOOT` | WPA-Enterprise (EAP-TLS) setup sent to the module. | 🔍 |

### Print settings (stored in the printer)

| Command | Range / notes | Status |
|---|---|---|
| `DENSITY n` | 0–15 | ✅ |
| `SPEED n` | 2–6 (inch/s); 8 is ignored | ✅ |
| `DIRECTION r,m` | r: 0/1 = rotate 180°; m: 0/1 = mirror | ✅ |
| `SET REPRINT ON/OFF` | reprint after an error | ✅ |
| `OFFSET n dot` | tear-off feed, dots, may be negative | ✅ |
| `SHIFT x,y` | dots | ✅ |
| `REFERENCE x,y` | origin, dots | ✅ |
| `SET TEAR ON` + `SET PEEL OFF` + `SET CUTTER OFF` | output mode; the vendor tool sends all three together. XP-420B has no peeler/cutter. | 🔍 |
| `SET CUTTER <n>` / `ON` | cut every n labels | 🔍 |
| `SIZE w mm,h mm` / `SIZE w,h` | label size (the macOS driver sends it with every job) | 🔍 |
| `GAP g mm,o mm` / `BLINE g mm,o mm` / `GAP 0,0` | gap labels / black mark / continuous | 🔍 |
| `SET GAP n` / `SET SENSOR_REF AUTO`/`MANUAL` | sensor sensitivity | 🔍 |
| `LIMITFEED n dot` | max feed when looking for a gap | 🔍 |
| `SET HEAD ON/OFF` | cover-open detection (off = may print with the head open) | 🔍 — not recommended |
| `SET RIBBON ON/OFF`, `SET RIBBONEND`, `SET ENCODER` | ribbon models only (XP-420B is direct thermal) | 🔍 |
| `CODEPAGE <cp>`, `COUNTRY <code>` | built-in fonts only | 🔍 |
| `SET COM1 <baud><parity><bits>,<stop>` | serial port | 🔍 |
| `NET IP "…"`, `NET DHCP`, `NET NAME "…"` | Ethernet models | 🔍 |
| `BT NAME "…"`, `BT PIN "…"` | Bluetooth models | 🔍 |
| `SOUND 5,500` | beep | 🔍 |
| `SET CONTINUE_CUTTER ON/OFF`, `SET BACK ON/OFF` | continuous cutter mode / back-feed after cut (cutter models; new in V1.039b) | 🔍 |
| `^XA … ^XZ`, `^RS…`, `^RW…`, `^RFW…`, `^RFR…` | ZPL commands for RFID models (new in V1.039b): these printers also accept ZPL | 🔍 |

### Calibration

| Command | Effect | Status |
|---|---|---|
| `GAPDETECT` | Feeds 2–3 labels **without printing**, measures label (`Paper Size`) and gap (`Gap Size`), switches `Sensor Mode` to `GAP`, retunes `Gap Reference`/`Gap Intension`. Nothing else changes. Afterwards the printer feeds one label each time the cover is closed (aligns to the gap) — normal. | ✅ |
| `BLINEDETECT` | Same for black-mark paper. | 🔍 |
| `AUTODETECT` | Detects the paper type itself. | 🔍 |
| `GAPDETECT x,y` / `AUTODETECT x,y` / `BLINEDETECT x,y` | With paper length and gap in dots. | 🔍 |

### Immediate commands (processed even when the queue is busy)

| Bytes | Effect | Status |
|---|---|---|
| `ESC ! ?` (`1B 21 3F`) | One status byte, see below. | ✅ |
| `ESC ! exit\r\n` (`1B 21 65 78 69 74 0D 0A`) | Vendor tool sends it before status and reset; replies `FE`/`FF`. | ✅ |
| `ESC ! R` (`1B 21 52`) | **Soft restart** (vendor "Reset Printer"). Unsticks a hung printer over USB; all settings kept; USB back in ~6 s. Send `ESC ! exit\r\n` first, as the vendor tool does. | ✅ |
| `ESC ! C` (`1B 21 43`) | **FACTORY RESET** (vendor "Factory Default"). Erases everything, Wi-Fi included. **Never send.** | 🔍 |

Status byte (`ESC ! ?`): `0x00` ready ✅, `0x01` cover/head open ✅, `0x02` paper jam 📘, `0x04` out of paper 📘, `0x08` out of ribbon 📘, `0x10` paused 📘, `0x20` printing 📘.

### Maintenance and diagnostics

| Command | Effect | Status |
|---|---|---|
| `SELFTEST` | Prints the self-test page (uses a label). | ✅ |
| `INITIALPRINTER` | Resets printer settings. | 🔍 — avoid |
| `DIGNOSTIC DIGREPORT REPGAPSENSOR` / `REPBLINESENSOR` | Sensor report. | 🔍 |
| `DIGNOSTIC DIGFILE "Dump.txt"` | Dump mode to a file. | 🔍 |
| `TEXTDUMP` / `TEXTDUMP SAVE 1000,E,"…"` | Print received data as text. | 🔍 |
| `DOWNLOAD F,"name",…` / `DOWNLOAD E,…` | Store files in flash (F) or DRAM (E). | 🔍 |
| `KILL "*.*"`, `KILL F,"*.*"`, `KILL E,"*.*"` | Delete stored files. | 🔍 |
| `XA…JUSXZ`, `SD…XAJUSXZ`, `TA…XAJUSXZ` | Factory head/motor/print-width adjustments. | 🔍 — **do not use**, may damage the head |

---

## 4. Wi-Fi module behaviour (important)

Repeated four times, with and without traffic (✅):

- About **30–35 minutes after the Wi-Fi module starts** it fails on its own: it either drops off the network (no ping, while `WIFI GETIP` still reports the old address), or keeps TCP open but **hangs mid-transfer** — then the printer waits for the rest of that transfer and stops answering on USB too (blue light stays on).
- Data sent over Wi-Fi does not arrive at that point either, so printing over Wi-Fi fails.
- 30 minutes of complete silence did not prevent it; 15 reads in a row right after a module restart were fine. So it is time since start, not load.
- Fixes: dropped off → `WIFI RESET` over USB. Hung → `ESC ! exit` + `ESC ! R` over USB. Over the network nothing helps (the fix doesn't pass either). Without a cable: power cycle.
- The vendor discovery broadcast (§6) is answered only shortly after the module starts.
- Guess, not verified: the module breaks at the router's group-key renewal.

Consequence for software: ask for replies over Wi-Fi as rarely as possible, never poll in the background, prefer USB for settings.

---

## 5. macOS printing (CUPS) notes ✅

- The Xprinter driver (`com.mygreatcompany.pkg.Xprinter`) installs PPDs into `/Library/Printers/PPDs/Contents/Resources/XP-*.ppd` and the filter `/usr/libexec/cups/filter/xprinter`. macOS does not include it.
- Wi-Fi queue: `lpadmin -p Xprinter_XP_420B_WiFi -D "Xprinter XP-420B (Wi-Fi)" -v socket://<ip>:9100 -P <ppd> -o printer-is-shared=false -E`.
- PPD sizes: only 2×4, 4×4, 4×6 in; custom sizes allowed up to 306 × 6480 pt (108 mm × 2.28 m). A default custom size can be added as an extra `*PageSize` (+ `PageRegion`, `ImageableArea`, `PaperDimension`) and set as `*DefaultPageSize`, then installed with `lpadmin -p <queue> -P <file>`. Other options stay.
- PPD options: `PaperType` Normal / LabelGaps / LabelMark / Continue, `GapsHeight` 0–10, `PostAction`, `PrintSpeed`, `Darkness` 0–15, `MirrorImage`, `NegativeImage`, `Origin`.
- `lpstat` output is localized (e.g. `устройство для <name>: <uri>`): parse the last word before `: `, never the English prefix. `lpoptions -p <queue>` gives non-localized `printer-info='…'`.
- Chromium browsers show only the default and recent printers; others are under **See more…**.

---

## 6. Vendor discovery (UDP 22368)

Request, 32 bytes, broadcast to `255.255.255.255:22368` (the vendor tool also tries multicast `224.0.0.1:22368`):

```
00 20 00 01 00 01 08 00 00 02 00 00 00 06 00 00
01 00 00 00 00 00 FF FF FF FF FF FF 00 00 00 00
```

Reply (116 bytes from an XP-420B): bytes 0–1 = `00 20`; **MAC** at 22–27; **IPv4** at 44–47; **model name** (NUL-padded) at 52–83 and again at 84–115. Answered by the Wi-Fi module itself, so other printers never receive print data. ✅ (unreliable later, see §4)

---

## 7. Driving the vendor tool's UI → commands (for future features)

The tool builds one text from its settings form and sends it at once. Combo boxes usually send `SelectedIndex − 1` (index 0 = "don't change"). Known mappings: DHCP combo → `WIFI SETDHCP` (OFF = 0, ON = 1); density combo → `DENSITY 0…15`; direction combos → `DIRECTION a,b`; output combo → Tear / Peel / Cutter. If any `WIFI …` command is in the text, the tool appends `WIFI RESET`.
