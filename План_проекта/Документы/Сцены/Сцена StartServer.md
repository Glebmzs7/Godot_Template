---
type: сцена
status: работает
path: res://Scenes/StartServer/StartServer.tscn
extends: Node
depends: ["[[Class_InternetServer]]", "[[Class_Json]]", "[[Class_FileIntegrity]]"]
checked: 2026-09-26
journal: "[[Журнал Сцена StartServer]]"
---
# Сцена StartServer

## Назначение
Локальный сервер «для одного компьютера». [[Сцена Start_Program]] переключается сюда, если в окне выбора аккаунта выбрано техническое значение `"Server"`. Вместе со вторым экземпляром программы (реальный аккаунт) позволяет проверить клиент и сервер на одном устройстве.

Раньше эта сцена называлась `Scenes/test/test.gd` и заодно служила стендом для тестов [[Class_ArrayAndOrDictionary]]. Сейчас она только сервер. В коде ещё встречаются упоминания `test.gd` в комментариях и сообщениях.

- Сцена: корень `Node2D` со скриптом `StartServer.gd`.

## Что делает `_ready`
1. Если `REGENERATE_MANIFEST_ON_START_Bv = true` — пересобирает manifest файлов (`fC_RegenerateFileManifest_Ch`).
2. `add_child(Class_InternetServer)` (обязательно — нужен `_process`), подключает `AppOpReceived_S`.
3. Слушает порт `SERVER_PORT_I = 9050`, **без авторизации** (`RequireAuth = false`, сервер игрока).

## Константы
| Имя | Значение | Смысл |
|---|---|---|
| `SERVER_PORT_I` | `9050` | Тот же порт, что в `SERVER_ADDRESS_S` клиента |
| `SERVER_LATEST_VERSION_S` | `"0.1.0.0"` | «Актуальная» версия для `CheckUpdate` |
| `FILE_MANIFEST_S` | `res://Save/Server/FileManifest.json` | Manifest: `{путь: {Size, FirstByte, LastByte}}` |
| `REGENERATE_MANIFEST_ON_START_Bv` | `true` | Пересобирать manifest при каждом запуске (режим разработки) |

## Функции
- **`fC_RegenerateFileManifest_Ch()`** — обходит проверяемые файлы ([[Class_FileIntegrity]]) и сохраняет manifest.
- **`_fC_OnServerAppOpReceived_Ch(op, envelope, receivedNow, replyKey)`** — диспетчер прикладных операций.
- **`_fC_HandleCheckUpdateRequest_Ch`** — ответ `CheckUpdateResult {LatestVersion, UpToDate}`.
- **`_fC_HandleCheckFilesRequest_Ch`** — сверка присланных отпечатков. Размер, первый и последний байт — с manifest, случайный байт — живым чтением файла. Ответ `CheckFilesResult {Ok, Mismatches, Unexpected, Missing}`. `Missing` — файлы из manifest, которые клиент не прислал (удалённые).

## Известные проблемы / открытые вопросы
- Нет переключателя «выключить проверку файлов совсем» для релизной сборки.
- Версия и порт — константы в коде.
- `Users.json` не заводится: сервер работает без авторизации.
- Сервер работает из того же проекта, что и клиент. Для настоящего сервера понадобится своя эталонная копия файлов.

## Связи
- Использует: [[Class_InternetServer]], [[Class_Json]], [[Class_FileIntegrity]]
- Приходит из: [[Сцена Start_Program]]
- Протокол: [[Class_Internet]]
- История: [[Журнал Сцена StartServer]]
