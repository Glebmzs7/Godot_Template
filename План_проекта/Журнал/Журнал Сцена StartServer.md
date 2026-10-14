---
type: журнал
subject: "[[Сцена StartServer]]"
---

# Журнал Сцена StartServer

История изменений. Текущее состояние описано в документе [[Сцена StartServer]]. Новые записи добавляются **сверху** (свежие первыми), в формате `### ГГГГ-ММ-ДД — что сделано`.

## Записи

### 2026-09-26 — документация разделена на Документы и Журнал

Документ [[Сцена StartServer]] создан впервые (раньше отдельного описания не было), по текущему коду (сверка 26.09). Подробности — [[Журнал Документации]].

### 2026-09-11/12 — переименована из `Scenes/test/test.gd` в `Scenes/StartServer/StartServer.gd`

По датам файлов, отдельной записи нет. Start_Program переключается на `res://Scenes/StartServer/StartServer.tscn`.

### 2026-08-24 — ловит удалённые файлы

`_fC_HandleCheckFilesRequest_Ch` отдельно сверяет пути manifest с тем, что прислал клиент; непришедшие уходят в поле `Missing` и проваливают проверку.

### 2026-08-23 — сцена отдана под сервер

Фаза 1: реальный сервер на порту 9050 при выборе "Server". Фаза 2: обработка `CheckUpdate`/`CheckFiles`, manifest `Save/Server/FileManifest.json`. Старые тесты Class_ArrayAndOrDictionary (`test_full_correctness`/`test_manual_diagnostic`/`test_performance`) из сцены убраны.

### 2026-08-09…08-23 — испытательный стенд Class_Logger / Class_ArrayAndOrDictionary

Сцена `Scenes/test/test.gd` служила местом для тестов сравнения и логгера.
