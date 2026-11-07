# Cursor Limits Tray

**RU:** Меню-бар приложение для macOS — живые остатки лимитов **Cursor**, **ChatGPT** и (по желанию) **Claude** у Dynamic Island / в строке меню.

**EN:** A native macOS menu-bar app for live **Cursor** / **ChatGPT** limits (and **Claude** after you connect it).

![Menu bar](docs/screenshots/tray-menubar-live.png)

## Install (one line)

Download the latest [**`.dmg`**](https://github.com/alebastr12/cursor-limits-tray/releases/latest) → open → drag **CursorLimitsTray** to **Applications**.

If macOS blocks it (unsigned / not notarized): **right-click** → **Open**. Ad-hoc signed only.

## Features

- Menu bar: `C75% · G40%` — **Claude (`A…`) only after** Settings → **Подключить Claude** (no empty `A—`)
- Prefer **in-app login** for ChatGPT/Claude (no Chrome Keychain)
- **At most one** foreign Keychain unlock until Reset (not Chrome→Brave→Edge cascade)
- Cursor token cached in app Keychain after first successful read
- Closing windows keeps the tray; **Выйти** / ⌘Q quits

## Usage

1. Launch → tray shows `C… · G…` (Claude hidden until connected).
2. **Подключить ChatGPT** in the popover (login window — preferred).
3. **Claude:** Settings → **Подключить Claude** — then `A…` appears in the tray.
4. **Close vs Quit:** ✕ / ⌘W hides windows; **Выйти** quits.

## Keychain — what the old “3 passwords” were

On older builds, launch/connect unlocked **Cursor Safe Storage + Chrome Safe Storage + Claude Safe Storage** in a row.

**Now (0.2.3+):**
| Action | Dialogs |
|--------|---------|
| Launch / poll | **Zero** SecurityAgent prompts |
| Подключить ChatGPT / Claude (login window) | **Zero** Keychain (cookies from WKWebView) |
| «Взять из браузера» / «Разрешить Cursor» | Silent first; then **at most one** unlock app-wide until Reset |

Remaining single prompt (optional): only if you choose browser/Desktop import or Cursor unlock and Safe Storage isn’t already Always Allow’d.

## Build / package

```bash
./Scripts/build-app.sh
./Scripts/package-dmg.sh 0.2.3
./Scripts/package-release.sh 0.2.3
```

## License

MIT
