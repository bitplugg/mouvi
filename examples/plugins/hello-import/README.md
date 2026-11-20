# Example Mouvi plugins

## `hello-import.mu`
Эталонный `.mu`-плагин для проверки системы плагинов.

- **Хук:** `importValidation` (декларативные правила в манифесте)
- **Что делает:** распознаёт конфиги, начинающиеся с `mouvi-example://` или содержащие маркер `[MouviExample]`, и позволяет импортировать их в Mouvi.
- **Установка:** Настройки → Плагины → «Установить плагин» → «Установить из файла» → выбрать `hello-import.mu`.
- **Примечание:** плагин сторонний (не из `bitplugg/mouvi-store`), поэтому при включении потребуется подтверждение: **«Я согласен со всеми рисками»**.

### Тестовый конфиг
```
mouvi-example://demo#Example
```
или
```
[MouviExample]
name=demo
```

## Формат `.mu` (MVP)
`.mu` — это ZIP-архив, содержащий как минимум `manifest.json` в корне.

Минимальный пример манифеста:
```json
{
  "id": "com.vendor.plugin",
  "name": "My Plugin",
  "version": "1.0.0",
  "apiVersion": 1,
  "author": "Author",
  "description": "Description",
  "permissions": ["ownStorage", "connectionState", "configsMetadata"],
  "hooks": ["importValidation"],
  "importRules": [
    {
      "id": "rule-id",
      "label": "MyFormat",
      "uriSchemes": ["myproto://"],
      "containsAny": ["[MySection]"]
    }
  ]
}
```

Базовый плагин `mouvi-engine` поставляется встроенным: при его отключении остальные плагины не работают. Плагины не из `bitplugg/mouvi-store` требуют явного согласия с рисками перед активацией.
