# Как написать плагин для Mouvi (`.mu`)

Этот документ описывает формат плагинов Mouvi, манифест, runtime-исполнение кода, хуки, UI-расширения, движки-адаптеры и сборку `.mu` через `mouvi-builder`.

## Возможности плагинов

Поддерживаются:
- **Декларативные правила импорта** (`importRules`) — распознавание конфигов без кода.
- **Runtime-код плагина (JavaScript, QuickJS)** — выполнение хуков из файла `entry` внутри `.mu` (Android-first, AOT-совместимо).
- **Хуки:** `importValidation` (в т.ч. кодовый парсинг/трансформация), `connectionEvents` (события соединения/сети), `uiExtensions` (экраны и действия в настройках плагинов), `uriHandlers`, `engineProvider` (адаптер/подготовка подключения).
- **Собственное хранилище плагина** (по разрешению `ownStorage`), изоляция сбоев (ошибка плагина не должна ломать приложение).
- Управление: установка из файла/URL/каталога, обновление, удаление, включение/выключение; базовый `mouvi-engine` гейтит работу остальных плагинов.

> **Ограничение по движкам (TUN):** VPN-туннель/TUN и текущие движки реализованы нативно (Kotlin/Go/Xray через `VpnService` и `MethodChannel`). Произвольная динамическая загрузка нативного/бинарного движка из `.mu` в рантайме не поддерживается. Хук `engineProvider` предназначен для **адаптера/трансформации**: плагин может разобрать свой формат и вернуть конфиг для **поддерживаемого нативного движка** (`wireguard`, `amneziawg`, `vless`) через `prepareEngineConnection`. Нативные контракт/мосты для полноценных сторонних движков требуют отдельной проработки.

## Что такое `.mu`

`.mu` (**Mouvi Universal**) — ZIP-архив с плагином. Минимальное содержимое — `manifest.json` в корне. Внутри могут находиться код (`.js`), ресурсы, документация и другие файлы.

Пример структуры (runtime-плагин):
```text
my-plugin/
├── manifest.json
├── main.js              # точка входа (runtime)
├── README.md            # опционально
└── assets/              # ресурсы (опционально)
```

## Быстрый старт

### 1. Создать шаблон
Из корня репозитория Mouvi (нужен Dart/Flutter SDK):

```bash
# декларативный шаблон
./mouvi-builder init ./my-plugin --id com.example.myplugin --name "My Plugin"

# шаблон с runtime-кодом (JS), UI, событиями и engine-адаптером
./mouvi-builder init ./my-plugin --id com.example.myplugin --name "My Plugin" --with-code

# Windows
mouvi-builder.bat init .\my-plugin --id com.example.myplugin --name "My Plugin" --with-code

# напрямую
dart run tool/mouvi_builder.dart init ./my-plugin --id com.example.myplugin --name "My Plugin" --with-code
```

### 2. Отредактировать `manifest.json` и код
Настройте манифест, добавьте `main.js` (если используете runtime) и ресурсы.

### 3. Проверить и собрать `.mu`
```bash
./mouvi-builder validate ./my-plugin
./mouvi-builder build ./my-plugin -o ./my-plugin.mu
```

`build` проверяет манифест и (для runtime) наличие файла `entry` внутри директории плагина.

### 4. Установить в приложение
Mouvi → **Настройки → Плагины → (＋) Установить плагин** → файл/URL/каталог магазина.

## `mouvi-builder` (CLI)

```text
Usage:
  dart run tool/mouvi_builder.dart <command> [options]
  ./mouvi-builder <command> [options]

Commands:
  build <plugin_dir> [-o <output.mu>]                 Упаковать директорию плагина в .mu
  validate <path>                                     Проверить manifest (директория или .mu)
  init <dir> [--id <id>] [--name <name>] [--with-code] Создать шаблон плагина
  help                                                Справка
```

## Манифест (`manifest.json`)

Пример runtime-плагина:
```json
{
  "id": "com.vendor.myplugin",
  "name": "My Plugin",
  "version": "1.0.0",
  "apiVersion": 1,
  "author": "Author Name",
  "description": "Короткое описание плагина.",
  "minAppVersion": "1.4.0",
  "permissions": ["ownStorage", "connectionState", "configsMetadata", "uiExtensions"],
  "hooks": ["importValidation", "connectionEvents", "uiExtensions", "engineProvider"],
  "runtime": "javascript",
  "entry": "main.js",
  "engine": { "type": "adapter" },
  "ui": { "entryScreen": "main" },
  "importRules": []
}
```

### Поля

| Поле | Тип | Обязательно | Описание |
|---|---|---:|---|
| `id` | string | да | Уникальный идентификатор `^[a-zA-Z0-9._-]{1,64}$` (рекомендуется reverse-DNS). |
| `name` | string | да | Отображаемое имя. |
| `version` | string | да | Версия плагина (semver). |
| `apiVersion` | int | да | Версия API плагинов Mouvi. Текущая поддерживаемая: `1`. |
| `author` | string | нет | Автор/издатель. |
| `description` | string | нет | Описание. |
| `minAppVersion` | string | нет | Минимальная версия приложения. |
| `homepage` | string | нет | Ссылка на сайт/репозиторий. |
| `permissions` | string[] | нет | Запрашиваемые разрешения. |
| `hooks` | string[] | нет | Используемые хуки. |
| `importRules` | object[] | нет | Декларативные правила импорта. |
| `dependencies` | object | нет | Зависимости (`"plugin.id": "versionRange"`), резерв. |
| `runtime` | string | нет | Тип runtime. Поддерживается: `"javascript"` (`"js"`, `"quickjs"`). |
| `entry` | string | нет | Путь к точке входа внутри `.mu` (напр. `main.js`). **Обязателен при `runtime`**. |
| `engine` | object | нет | Метаданные движка/адаптера (контракт). |
| `ui` | object | нет | Метаданные UI-расширений. |

## Разрешения (`permissions`)

| Значение | Смысл |
|---|---|
| `ownStorage` | Собственное изолированное хранилище плагина (персистентное). |
| `connectionState` | Доступ к состоянию соединения (без секретов). |
| `trafficStats` | Доступ к статистике трафика (в составе состояния). |
| `configsMetadata` | Метаданные конфигов **без** приватных ключей/секретов. |
| `sensitiveData` | Доступ к чувствительным данным (высокий риск, только при необходимости). |
| `manageConnection` | Управление подключением (резерв/контракт). |
| `engineAccess` | Доступ на уровне движка/сетевого стека (контракт). |
| `uiExtensions` | Расширения интерфейса. |
| `uriHandlers` | Обработка URI/ссылок. |

Запрашивайте минимально необходимый набор. Разрешения влияют на доступные данные (напр. персистентность `storage`).

## Хуки (`hooks`) и runtime API

### Точка входа
Файл `entry` (JS) выполняется в QuickJS один раз при инициализации плагина. Экспортируйте хуки как:

```js
globalThis.MouviPlugin = {
  hooks: {
    onImportValidate(payload, host) { /* ... */ },
    onConnectionEvent(payload, host) { /* ... */ },
    getUiExtensions(payload, host) { /* ... */ },
    onUiAction(payload, host) { /* ... */ },
    handleUri(payload, host) { /* ... */ },
    prepareEngineConnection(payload, host) { /* ... */ }
  }
};
```

Также поддерживаются `globalThis.MouviHooks` или функции на `globalThis`. Хуки вызываются синхронно; возвращайте обычные JSON-совместимые значения.

### Хост-объект `host`
`host.plugin` — метаданные плагина; `host.state` — разрешённое состояние приложения (напр. статус соединения, активный конфиг без секретов, статистика при наличии прав).

Хранилище (при `ownStorage`): `host.storage` — объект, читаемый/изменяемый в хуках (изменения сохраняются после вызова). Также доступен helper `Mouvi.storage.get/set/remove/all()`.

### `importValidation`
- **Декларативно (MVP+):** `importRules` в манифесте (`uriSchemes`, `containsAll`, `containsAny`, `regex`).
- **Runtime:** `onImportValidate({ content })` → вернуть `null/false` если не распознано, или объект:
  - `{ match: true, label: "..." }` — распознано (можно импортировать как есть),
  - `{ match: true, label, name?, protocol?, content? }` — распознано и (опционально) преобразовано/переименовано. Если возвращён валидный `protocol` (`wireguard`/`amneziawg`/`vless`) и `content`, Mouvi сохранит преобразованный конфиг.

### `connectionEvents`
`onConnectionEvent({ event, data }, host)` вызывается (best-effort, с изоляцией ошибок) на события: `beforeConnect`, `afterConnect`, `disconnect`, `connectError`, `networkChange`.

### `uiExtensions`
- `getUiExtensions(payload, host)` → массив расширений или одно расширение:
```json
{
  "id": "main",
  "title": "Plugin UI",
  "items": [
    { "type": "text", "style": "title", "text": "Hello" },
    { "type": "keyValue", "key": "Status", "value": "ok" },
    { "type": "button", "label": "Action", "action": "doThing", "primary": true }
  ]
}
```
Поддерживаемые элементы: `text` (style: `title|headline|caption`), `section`/`card` (`items`/`children`), `button` (`action`, `label`, `payload`, `primary`), `keyValue` (`key`, `value`), `divider`.
- `onUiAction({ action, payload }, host)` → `{ "message": "...", "items": [...] }` (опционально обновить UI/показать сообщение).

UI-расширения активных плагинов отображаются в **Настройки → Плагины**.

### `uriHandlers`
`handleUri({ uri }, host)` → `{ handled: true, ... }` если URI обработан плагином (контракт; интеграция вызовов зависит от сценария).

### `engineProvider` (адаптер)
`prepareEngineConnection({ id, name, protocol, content }, host)` вызывается при попытке подключения неподдерживаемого протокола. Плагин может вернуть:
```json
{ "handled": true, "protocol": "wireguard", "content": "...", "name": "optional" }
```
где `protocol` — один из нативно поддерживаемых (`wireguard`, `amneziawg`, `vless`), а `content` — валидный конфиг этого движка. Это позволяет реализовывать «движки-плагины» как адаптеры/конвертеры поверх существующего TUN-стека. Полноценные нативные движки внутри `.mu` не загружаются в рантайме.

## Базовый плагин `mouvi-engine`

`mouvi-engine` — встроенный системный плагин, его нельзя удалить. Можно отключить, но **при отключённом `mouvi-engine` все остальные плагины становятся неактивными** (хуки не применяются).

## Источники, магазин и безопасность

- **Официальный источник:** плагины из `bitplugg/mouvi-store` считаются официальными.
- **Сторонние плагины** (файл, произвольный URL) перед активацией требуют подтверждения: **«Я согласен со всеми рисками»**.
- Криптографическая подпись пакетов в текущем MVP не применяется — ориентируйтесь на источник и содержимое.

Каталог: `https://raw.githubusercontent.com/bitplugg/mouvi-store/master/index.json` (формат `{"plugins":[{"id","name","version","description","downloadUrl"}]}`).

## Установка, обновление и хранение

- **Установка:** из файла (`.mu`) или по URL. Повторная установка того же `id` обновляет плагин.
- **Включение/выключение:** в списке плагинов; для сторонних — с подтверждением рисков при первом включении.
- **Удаление:** доступно всем, кроме `mouvi-engine`.
- Пакеты распаковываются в `plugins/<id>/` во внутреннем хранилище приложения; данные `ownStorage` сохраняются отдельно (персистентно для плагина).

## Эталонный пример

- Декларативный: `examples/plugins/hello-import/` (и собранный `examples/plugins/hello-import.mu`) — хук `importValidation` для `mouvi-example://` и `[MouviExample]`.
- Runtime-шаблон с кодом/UI/событиями/engine-адаптером: создаётся командой
  `./mouvi-builder init ./my-plugin --with-code`.

## Рекомендации
- Уникальный `id` в стиле reverse-DNS; минимальные разрешения и только нужные хуки.
- Повышайте `version` при каждом выпуске; следите за `apiVersion`/`minAppVersion`.
- Проверяйте пакет: `./mouvi-builder validate <dir|file.mu>`.
- Публикация в каталог: добавьте `.mu` и запись в `index.json` репозитория `bitplugg/mouvi-store`.
- Пишите хуки устойчиво к ошибкам и учитывайте, что runtime-код выполняется в песочнице QuickJS (без прямого доступа к ФС/сети приложения вне предоставленного API).
