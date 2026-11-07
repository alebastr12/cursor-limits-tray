# Cursor Limits Tray

**RU:** Меню-бар приложение для macOS — живые остатки лимитов **Cursor**, **ChatGPT** и **Claude** прямо у Dynamic Island / в строке меню.

**EN:** A native macOS menu-bar app that shows live remaining **Cursor**, **ChatGPT**, and **Claude** usage limits next to the notch.

![Menu bar](docs/screenshots/tray-menubar-live.png)

## Install (one line)

Download the latest [**`.dmg`**](https://github.com/alebastr12/cursor-limits-tray/releases/latest) → open → drag **CursorLimitsTray** to **Applications**.

If macOS says the app can’t be opened (unsigned / not notarized): **right-click** the app → **Open** → confirm. Gatekeeper only; this release is **ad-hoc signed**, not Apple-notarized.

Also available: [`.zip` of the `.app`](https://github.com/alebastr12/cursor-limits-tray/releases/latest) if you prefer not to use a disk image.

## Features

- Live menu-bar text: `C75% · G40% · A60%` (updates every ~45s; `—` if a provider is not connected)
- Popover with progress bars and reset times (Russian UI)
- **Cursor** — usually automatic (reads the local Cursor app session on this Mac)
- **ChatGPT** — one-tap **Подключить ChatGPT** in a floating login window; optional browser-session pickup
- **Claude** — auto from Claude Desktop `sessionKey` when available, or **Подключить Claude** login window / browser cookie
- Secrets only in macOS Keychain (`local.cursor-limits-tray`) — never hardcoded

## Requirements

- macOS 14+
- Apple Silicon or Intel

## Build from source

```bash
git clone https://github.com/alebastr12/cursor-limits-tray.git
cd cursor-limits-tray
./Scripts/build-app.sh
open dist/CursorLimitsTray.app
```

Package distributables:

```bash
./Scripts/package-dmg.sh 0.2.0      # dist/CursorLimitsTray-0.2.0.dmg
./Scripts/package-release.sh 0.2.0  # dist/CursorLimitsTray-0.2.0.zip
```

Optional after install: popover → **Настройки…** → **Открывать при входе**.

## Usage

1. After launch, the menu bar shows `C…% · G…% · A…%` (or `—` while disconnected).
2. Click the item for details.
3. If ChatGPT shows `G—`, click **Подключить ChatGPT** and sign in.
4. If Claude shows `A—`, open Claude Desktop (often enough) or click **Подключить Claude**.
5. Cursor usually works if the Cursor desktop app is already signed in.

## Privacy

- No telemetry from this app.
- Tokens/cookies stay in the local Keychain.
- Undocumented vendor endpoints (Cursor / ChatGPT / Claude web) may change.
- Free Claude accounts often return empty usage percentages; Pro/Max show windows.

## Dev

```bash
swift build -c release --product CursorLimitsTray
./Scripts/run.sh
open dist/CursorLimitsTray.app --args --demo
open dist/CursorLimitsTray.app --args --connect-chatgpt
open dist/CursorLimitsTray.app --args --connect-claude
```

## License

MIT
