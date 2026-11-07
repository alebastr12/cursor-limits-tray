# Cursor Limits Tray

**RU:** Меню-бар приложение для macOS — живые остатки лимитов **Cursor** и **ChatGPT** прямо у Dynamic Island / в строке меню.

**EN:** A native macOS menu-bar app that shows live remaining **Cursor** and **ChatGPT** usage limits next to the notch.

![Menu bar](docs/screenshots/tray-menubar-live.png)

## Features

- Live menu-bar text: `C75% · G40%` (updates every ~45s; `G—` if ChatGPT is not connected)
- Popover with progress bars and reset times (Russian UI)
- **Cursor** — usually automatic (reads the local Cursor app session on this Mac)
- **ChatGPT** — one-tap **Подключить ChatGPT** in a floating login window (no DevTools); optional browser-session pickup
- Secrets only in macOS Keychain (`local.cursor-limits-tray`) — never hardcoded

## Requirements

- macOS 14+
- Apple Silicon or Intel
- Xcode / Swift toolchain (`xcode-select --install` if needed)

## Install

```bash
git clone https://github.com/alebastr12/cursor-limits-tray.git
cd cursor-limits-tray
./Scripts/build-app.sh
open dist/CursorLimitsTray.app
```

Optional:

1. Move `dist/CursorLimitsTray.app` → `/Applications/`
2. Open the popover → **Настройки…** → enable **Открывать при входе**

## Usage

1. After launch, the menu bar shows `C…% · G…%` (or `—` while disconnected).
2. Click the item for details.
3. If ChatGPT shows `G—`, click **Подключить ChatGPT**, sign in in the floating window.
4. Cursor usually works if the Cursor desktop app is already signed in.

## Privacy

- No telemetry from this app.
- Tokens/cookies stay in the local Keychain.
- Undocumented vendor endpoints (Cursor / ChatGPT web) may change.

## Dev

```bash
swift build -c release --product CursorLimitsTray
./Scripts/run.sh
# Demo / login helpers:
open dist/CursorLimitsTray.app --args --demo
open dist/CursorLimitsTray.app --args --connect-chatgpt
```

## License

MIT
