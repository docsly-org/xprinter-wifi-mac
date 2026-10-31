<img src="Assets/AppIcon.png" width="128" alt="">

# Xprinter Setup for macOS

Connect an **Xprinter XP-420B** (and other Xprinter label printers with the X4 Wi-Fi module, e.g. XP-460B) to your Wi-Fi network from a Mac — no Windows and no vendor tool needed.

[Русская версия ниже](#русский)

## Download

Get `Xprinter-Setup.zip` from [Releases](../../releases), unzip, and move **Xprinter Setup** to Applications.
The app is not notarized: on first launch, right-click it → **Open** → **Open**.

Requires macOS 13 or later (Apple Silicon and Intel).

## How to use

1. Connect the printer with a USB cable and make sure it appears in **System Settings → Printers & Scanners** (install the Xprinter driver if needed).
2. Open **Xprinter Setup**, pick your network from the list, enter the password and press **Connect Printer to Wi-Fi**.
   The printer supports **2.4 GHz** networks only, so 5 GHz-only networks are hidden. macOS shows network names only to apps with Location access — allow it when asked (or choose **Other Network…** and type the name).
3. Wait ~30 seconds and press **Print Self-Test Page**. The `STA IP` line shows the printer's address in your network.
4. Press **Find** (or type the address) and **Add Wi-Fi Printer to macOS**. Choose the new “(Wi-Fi)” printer in any Print dialog.

Tip: reserve the printer's address in your router (DHCP reservation), so it never changes.

## Why this exists

Out of the box, the XP-420B only runs its own access point (`XP-420B` / `12345678`, `10.10.100.1`) and has no web setup page.
Joining a home network requires sending commands over USB, which the vendor only does from a Windows tool.
This app sends the same commands through macOS printing (CUPS).

### Protocol

Plain TSPL text sent raw to the printer (over USB or TCP port 9100):

| Command | Effect |
|---|---|
| `WIFI CONNECTION "<ssid>","<password>"` | Join a Wi-Fi network (STA mode, address via DHCP) |
| `WIFI RESET` | Restart the Wi-Fi module to apply settings |
| `SELFTEST` | Print the self-test page with AP/STA addresses |

Strings have no escaping, so the network name and password cannot contain `"`.
The same from Terminal:

```sh
printf 'WIFI CONNECTION "MyWiFi","password"\r\nWIFI RESET\r\n' | lp -d Xprinter_XP_420B -o raw
```

The commands were identified for interoperability by examining what the vendor's Windows tool sends. No vendor code is included in this repository.
Tested on an XP-420B, firmware 1.040.3552, Wi-Fi module X4_V95.0.9.

## Build from source

```sh
swift test          # unit tests
./build-app.sh      # → dist/Xprinter Setup.app and dist/Xprinter-Setup.zip
```

---

## Русский

Программа подключает принтер этикеток **Xprinter XP-420B** (и другие Xprinter с модулем Wi-Fi X4, например XP-460B) к домашнему Wi-Fi прямо с Mac — без Windows и фирменной утилиты. Язык интерфейса — как в системе (русский или английский).

**Установка:** скачайте `Xprinter-Setup.zip` в [Releases](../../releases), распакуйте и перенесите в «Программы». При первом запуске: правый клик → «Открыть» → «Открыть» (программа не нотаризована).

**Как пользоваться:**

1. Подключите принтер по USB — он должен появиться в «Системные настройки → Принтеры и сканеры».
2. Выберите сеть из списка, введите пароль и нажмите «Подключить принтер к Wi‑Fi». Принтер работает **только с 2,4 ГГц**, поэтому сети только на 5 ГГц скрыты. Список сетей macOS показывает только с разрешением на геолокацию — разрешите его (или выберите «Другая сеть…» и введите название).
3. Через ~30 секунд нажмите «Напечатать тестовую страницу» — в строке `STA IP` будет адрес принтера.
4. Нажмите «Найти» (или введите адрес) и «Добавить Wi‑Fi принтер в macOS». Новый принтер «(Wi-Fi)» выбирайте в окне печати.

Совет: закрепите адрес принтера в роутере, чтобы он не менялся.

## License

MIT
