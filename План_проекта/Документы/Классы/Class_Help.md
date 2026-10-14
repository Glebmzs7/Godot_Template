---
type: класс
status: работает
path: res://Godot_Template/Class_Help.gd
extends: Node
depends: []
checked: 2026-09-26
journal: "[[Журнал Class_Help]]"
---
# Class_Help

## Назначение
Мелкие общие утилиты для остальных классов: таблицы типов данных Godot и единый способ вызвать callback-функцию с собранными параметрами. Используется прежде всего обходом структур в [[Class_ArrayAndOrDictionary]] (а через него — [[Class_UI]]) и [[Class_Logger]].

## Как подключать
`var Class_Help = load("res://Godot_Template/Class_Help.gd").new()` — свой экземпляр у каждого использующего класса.

## Переменные
| Имя | Что хранит |
|---|---|
| `TYPE_NAMES` | `{TYPE_*: "Имя"}` — человекочитаемые имена всех типов Variant (для логов) |
| `ITERABLE_TYPES` | `{TYPE_*: true}` — типы, по которым можно итерироваться (Array, Dictionary, Packed*Array) |
| `ARRAY_TYPES` | `{TYPE_*: true}` — только массивные типы |
| `ITERABLE_TYPES_MAP`, `ARRAY_TYPES_MAP` | Второе имя для тех же словарей (ссылки, не копии). Этими именами пользуются [[Class_ArrayAndOrDictionary]] и [[Class_UI]] |

## Функции

### get_iter_keys(container)
Возвращает, по чему итерироваться в контейнере: ключи словаря, диапазон индексов массива/Packed-массива. Для не-контейнера — `null` (так `UniversalBypass` ([[Class_ArrayAndOrDictionary]]) понимает, что перед ним лист).

### FunctionCall(FuncParametrs, EmbeddedParameters = null, vC_Logger = null, vC_StreamId = "")
Вызывает callback, переданный в словаре, и возвращает то, что он вернул.
- `FuncParametrs: Dictionary` — `{"func": Callable, "Parametrs": Array|Dictionary (необязательно)}`.
- `EmbeddedParameters` — дополнительные параметры, которые добавляются к `Parametrs` (так `UniversalBypass` передаёт в callback тип, текущий уровень, путь и ключ).
- `vC_Logger`, `vC_StreamId` — если переданы оба, перед вызовом в лог пишется, какая функция вызывается и с какими параметрами. Иначе ничего не логируется.
- **Порядок аргументов в callback:** сначала собственные `Parametrs`, затем `EmbeddedParameters`. От этого зависят индексы в `InputArray` у всех callback-функций [[Class_UI]] и [[Class_ArrayAndOrDictionary]].

## Известные проблемы
- Имена функций не по стандарту [[README]] (нет префикса `f…` и окончания `_XXXX`).

## Связи
- Используется: [[Class_ArrayAndOrDictionary]], [[Class_Logger]]
- История: [[Журнал Class_Help]]
