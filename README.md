# Cursor Limits Tray

Native macOS menu-bar app for live **Cursor** / **ChatGPT** / **Claude** usage limits.

## Install

[**Download DMG**](https://github.com/alebastr12/cursor-limits-tray/releases/latest) → Applications.  
Ad-hoc (not notarized): right-click → **Open**.

## Product answer: zero password prompts?

**YES for normal use.** Default path = **0** SecurityAgent / admin / browser Keychain dialogs.

| Action | Dialogs |
|--------|---------|
| Launch / poll | **Zero** |
| Подключить ChatGPT / Claude (login window) | **Zero** Keychain |
| Открывать при входе / copy from DMG | No admin loop (manual drag if copy fails) |
| Advanced → browser / Cursor Safe Storage | **May** ask Keychain password — optional |

Cursor uses an app-cached token; if missing, paste session in Advanced (no Keychain unlock) or optional Safe Storage there.

## Features

- Bars app icon; tray shows only connected providers with live `%`
- Connect only in Settings (WKWebView for ChatGPT/Claude)
- Open at login ON by default

## Build

```bash
./Scripts/build-app.sh
./Scripts/package-dmg.sh 0.2.6
```

## License

MIT
