---
type: сцена
status: тест
path: res://Scenes/TestLogger/TestLogger.tscn
extends: Node
depends: ["[[Class_Logger]]", "[[Class_Json]]"]
checked: 2026-09-26
journal: "[[Журнал Сцена TestLogger]]"
---
# Сцена TestLogger

## Назначение
Регрессионный тест того, что [[Class_Logger]] — **один общий** экземпляр (автозагрузка `Logger`), а не отдельный у каждого класса. Смысл исправления: записи из разных частей программы должны попадать в один файл лога сессии.

## Как работает
1. `Logger.fxG_StartingLogger_CrTr("test")` — лог с ролью `test` (файл `Logger_test_<дата>_<время>.log`).
2. Регистрирует два потока (`TestLogger_ContextA`, `TestLogger_ContextB`) — имитация двух разных классов. Пишет в каждый по записи, завершает, сбрасывает буфер.
3. Читает файл сессии через [[Class_Json]] и проверяет, что оба потока в нём есть и не пусты.
4. Печатает `TestLogger: PASSED` или `FAILED` с путём к логу.

Запуск — «Run Current Scene» (F6).

## Связи
- Проверяет: [[Class_Logger]]
- История: [[Журнал Сцена TestLogger]]
