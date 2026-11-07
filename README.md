# Cursor Limits Tray

Native macOS menu-bar app for live **Cursor** / **ChatGPT** / **Claude** usage limits.

![Menu bar](docs/screenshots/tray-menubar-live.png)

## Install

Download the latest [**`.dmg`**](https://github.com/alebastr12/cursor-limits-tray/releases/latest) → open → drag **CursorLimitsTray** to **Applications**.

Gatekeeper (ad-hoc, not notarized): **right-click → Open**.

## Features

- **Bars** app icon + menu-bar glyph
- Tray & popover show **only connected** providers (no empty `C—` / `G—` / `A—`)
- Connect only in **Настройки…** (in-app login preferred — no Chrome Keychain)
- At most **one** foreign Keychain unlock until Reset
- **Открывать при входе** ON by default (turn off in Settings); from a DMG, one prompt to copy into Applications
- Closing windows keeps the tray; **Выйти** / ⌘Q quits

## Usage

1. Launch → bars glyph in the menu bar (percentages appear after connect).
2. Open popover → **Настройки…** → connect Cursor / ChatGPT / Claude.
3. Live `%` shows only for authorized providers with data.

## Keychain

Launch/poll: **zero** SecurityAgent dialogs.  
Login windows: **zero** Keychain.  
«Взять из браузера» / Cursor unlock: silent first, then **at most one** unlock until Reset.

## Build

```bash
./Scripts/build-icons.sh
./Scripts/build-app.sh
./Scripts/package-dmg.sh 0.2.5
```

## License

MIT
