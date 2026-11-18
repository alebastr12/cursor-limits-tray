# Tray AI limits

Native macOS menu-bar app for live **Cursor** / **ChatGPT** / **Claude** usage limits.

Нативное приложение в строке меню macOS: живые лимиты Cursor, ChatGPT и Claude — без паролей Keychain в обычном сценарии.

Репозиторий: [`cursor-limits-tray`](https://github.com/alebastr12/cursor-limits-tray) (имя продукта — **Tray AI limits**).

![Строка меню](docs/screenshots/menubar.png)

## Что это

**Tray AI limits** показывает остаток лимитов прямо в menu bar (иконка + все `%` каждого подключённого сервиса) и в компактном popover. Опрос раз в ~45 с. В трее и popover видны только подключённые провайдеры — без букв `C`/`G`/`A` и без заглушек. Если у провайдера несколько лимитов, в строке меню показываются все. Popover открывается поверх fullscreen Space; при наведении на трей — подсказка с типами лимитов (5ч / неделя / месяц) и остатком `%`.

macOS 14+, не нотаризовано (локальная подпись TrayAILimits Dev / Apple Development либо ad-hoc).

## Функции

- Живые проценты в строке меню и подробности в popover
- Cursor — токен с этого Mac / cookie (кэш в Keychain приложения)
- ChatGPT и Claude — вход в окне приложения (WKWebView), без чтения паролей браузера
- ChatGPT: если web-сессия истекла — локальный fallback на вход Codex CLI (источник виден в popover)
- «Открывать при входе» включено по умолчанию
- Advanced — опциональный импорт из браузера / Safe Storage (может спросить пароль Keychain)

## Что нового в 0.2.17

- Исправлено «замерзание» лимитов ChatGPT: истёкшая сессия (`RefreshAccessTokenError`) теперь видна в popover, а не молча оставляет старые проценты.
- Fallback на локальный вход **Codex CLI** (`~/.codex/auth.json`), если web-сессия ChatGPT мертва; источник показан в popover.
- Сессия ChatGPT восстанавливается из окна входа без пароля Keychain; «Сбросить секреты» очищает и её.
- Провайдеры опрашиваются параллельно, HTTP-клиент общий и без кэша — «Обновить» всегда идёт в сеть.
- Полная локализация деталей Cursor/Claude/ChatGPT, скрытые поля cookie в Настройках.
- Стабильная подпись сборки, тесты парсеров, диагностика `--probe-chatgpt`.

## Скриншоты

### Popover

![Popover с лимитами](docs/screenshots/popover.png)

### Настройки

![Окно настроек](docs/screenshots/settings.png)

### Строка меню

![Menu bar](docs/screenshots/menubar.png)

### Иконка приложения

![App icon](docs/screenshots/appicon.png)

## Установка

### DMG (рекомендуется) — v0.2.17

1. Скачайте [**TrayAILimits-0.2.17.dmg**](https://github.com/alebastr12/cursor-limits-tray/releases/download/v0.2.17/TrayAILimits-0.2.17.dmg) или откройте [последний релиз](https://github.com/alebastr12/cursor-limits-tray/releases/latest).
2. Перетащите `TrayAILimits.app` в **Программы** (в Finder отображается как **Tray AI limits**).
3. Первый запуск: правый клик → **Открыть** (приложение не нотаризовано, Gatekeeper спросит подтверждение).
4. Старую `CursorLimitsTray.app` можно удалить из Программ.

Интерфейс следует языку macOS (`preferredLanguages`): English + Русский через `Localizable.strings`.

### Из исходников

```bash
git clone https://github.com/alebastr12/cursor-limits-tray.git
cd cursor-limits-tray
./Scripts/setup-signing.sh                  # один раз: identity TrayAILimits Dev
export CODESIGN_IDENTITY="TrayAILimits Dev"
./Scripts/package-dmg.sh 0.2.17
./Scripts/package-release.sh 0.2.17
open dist/TrayAILimits-0.2.17.dmg
```

Артефакты релиза: `dist/TrayAILimits-0.2.17.dmg`, `dist/TrayAILimits-0.2.17.zip` и стабильные копии `TrayAILimits-macOS.*`.

Нужны Xcode Command Line Tools / Swift toolchain.

Стабильная подпись (важно для Keychain): один раз создайте локальный сертификат:

```bash
./Scripts/setup-signing.sh
./Scripts/build-app.sh
```

`build-app.sh` сам выбирает `CODESIGN_IDENTITY` → «TrayAILimits Dev» → «Apple Development» → ad-hoc. Ad-hoc подпись меняется при каждой пересборке, из-за чего macOS может «забыть» сохранённые сессии и попросить подключить провайдеров заново. Если создан `TrayAILimits Dev`, он имеет приоритет, чтобы обычная пересборка не меняла Keychain ACL.

Тесты:

```bash
swift test
```

## Использование

1. Запустите приложение — иконка с полосками появится в строке меню.
2. Клик по иконке открывает popover с живыми данными.
3. **Настройки…** — подключение провайдеров.

### Cursor

Обычно подхватывается автоматически с этого Mac (токен кэшируется в Keychain приложения). Если нет — в **Advanced** вставьте session cookie или bearer (без разблокировки чужих Keychain).

### ChatGPT

В Настройках нажмите **Подключить ChatGPT** → войдите в окне приложения. Пароль Keychain / SecurityAgent не нужен.

Сессия chatgpt.com периодически истекает на стороне OpenAI (`RefreshAccessTokenError`). В этом случае приложение показывает ошибку в popover и предлагает войти заново. Пока сессия не восстановлена, лимиты читаются из локального входа **Codex CLI** (`~/.codex/auth.json`), если он есть на этом Mac — источник виден в popover как «через Codex CLI». Токен Codex не копируется в Keychain приложения и перечитывается при каждом опросе.

### Claude

**Подключить Claude** → вход на claude.ai в окне приложения. После подключения Claude появится в трее и popover.

### Трей

Показываются только подключённые сервисы: узнаваемая иконка провайдера + `%`. Цвет — зелёный / оранжевый / красный по остатку. Закрытие окон (✕ / ⌘W) не завершает приложение — оно остаётся в меню.

### Настройки

- Интервал опроса (по умолчанию 45 с)
- Демо-данные
- Открывать при входе
- **Advanced** — ручные cookie и импорт из браузера (опционально)
- **Сбросить секреты** — очистить сохранённые токены

## Автозапуск

«Открывать при входе» **включено по умолчанию** (`SMAppService`). Отключить можно в Настройках.

Если запускаете с DMG, приложение предложит скопировать себя в **Программы** — так login item работает надёжнее, без цикла запросов пароля администратора.

## Диагностика

Проверить источники ChatGPT без вывода токенов:

```bash
./dist/TrayAILimits.app/Contents/MacOS/CursorLimitsTray --probe-chatgpt
```

Печатает строки `app-session:` (cookie из Keychain / окна входа) и `codex-cli:` (локальный вход Codex) — только статус, названия лимитов и проценты.

## FAQ

### Будут ли пароли Keychain / SecurityAgent?

**Нет при обычном использовании.** Запуск, опрос и кнопки «Подключить ChatGPT / Claude» не трогают Keychain браузера и Cursor Safe Storage.

| Действие | Диалоги |
|----------|---------|
| Запуск / опрос | **Нет** (нет Safe Storage; Keychain только если уже сохраняли сессию) |
| Подключить ChatGPT / Claude | Нет (Keychain) |
| Открывать при входе / копия с DMG | Без admin-цикла |
| **Advanced** → браузер / Safe Storage | Может спросить пароль — опционально |

### Зачем Advanced?

Только если авто / окно входа не сработали: вставить cookie вручную или один раз импортировать из браузера. Для повседневной работы не нужно.

### Почему Claude нет в трее?

Не подключён. Подключите в Настройках — появится и процент `A…%`, и блок в popover.

### После пересборки просят подключить провайдеров заново

Так работает ad-hoc подпись: каждый билд получает новую code identity, а Keychain ACL привязан именно к ней. Один раз выполните `./Scripts/setup-signing.sh` (или соберите с `CODESIGN_IDENTITY="Apple Development: …"`) — и сохранённые сессии переживут пересборки. ChatGPT дополнительно восстанавливается из persistent-хранилища окна входа без пароля.

### Gatekeeper / «не удаётся открыть»

Правый клик по приложению → **Открыть**. Локальная подпись (`TrayAILimits Dev` / Apple Development или ad-hoc), без Apple notarization. Проверить: `codesign -dvv dist/TrayAILimits.app`.

## Релизы

Все версии и DMG: **[Releases](https://github.com/alebastr12/cursor-limits-tray/releases)**  
Актуальный: [v0.2.17](https://github.com/alebastr12/cursor-limits-tray/releases/tag/v0.2.17)

## Лицензия

[MIT](LICENSE)
