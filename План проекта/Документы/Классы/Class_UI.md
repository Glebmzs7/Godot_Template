---
type: класс
status: работает
path: res://Godot_Template/Class_UI.gd
extends: Node
depends: ["[[Class_ArrayAndOrDictionary]]", "[[Class_Logger]]"]
checked: 2026-09-26
journal: "[[Журнал Class_UI]]"
---
# Class_UI

## Назначение
Строит интерфейс не в редакторе Godot, а из словаря-конфига. Умеет:
- создать целое дерево нод одним проходом;
- **синхронизировать** экран со старого конфига на новый — создать новое, точечно обновить изменившиеся свойства, пересоздать ноду при смене типа/сигналов, удалить исчезнувшее. Так работают смена ориентации, обновление списков и смена языка без перестройки всего экрана.

## Как подключать
```gdscript
var Class_UI = load("res://Godot_Template/Class_UI.gd").new()
func _ready():
	add_child(Class_UI)  # ОБЯЗАТЕЛЬНО: без этого не работает get_tree()
```
Нода вставляется в **текущую сцену** (`get_tree().get_root().get_child(0)`) по пути относительно её корня.

## Формат конфига
Экран — вложенный словарь. Словарь считается **нодой**, если в нём есть все три ключа `__Data_D`, `__Inspector_D`, `__Node_D`:
```gdscript
{
	"ИмяНоды": {
		"__Data_D": {"__type_S": "Label", "__Scene_size_V2i": Vector2i(540, 900)},
		"__Inspector_D": {"text": "Привет", "anchor_right": 1.0},   # свойства ноды (.set)
		"__Node_D": {"pressed": Callable(self, "_on_pressed")},    # сигналы
		"v__Ebeveyn": "метка",                                       # необязательно
		"__Children_D": {                                            # обёртка для детей
			"ИмяРебёнка": { ...тот же формат... }
		}
	}
}
```
- **`__Data_D`** — служебное: `__type_S` (класс Godot, создаётся через `ClassDB`); необязательно `__Scene_size_V2i`, `__Zero_point`. Поле `__Path_to_the_node_location_S` **выставляется автоматически** из структуры дерева, руками не пишется (при массовом создании/синхронизации).
- **`__Inspector_D`** — свойства ноды. `name` выставляется автоматически из ключа словаря. Если значение — словарь с ключом `"type"`, создаётся вложенный объект этого типа (например, стиль) и заполняется его полями.
- **`__Node_D`** — `{имя_сигнала: Callable}`.
- **Обёртки.** Любой ключ, значение которого — словарь, но не нода, считается обёрткой для группировки и обходится глубже. `__Children_D` — принятое соглашение (им пользуется [[Сцена Start_Program]]), но не обязательное имя. В тесте, например, используется `"Children"`. Путь в дереве Godot строится только по реальным нодам, обёртки пропускаются.
- **`v__Ebeveyn`** — необязательная логическая метка на любом уровне. Все метки от корня до ноды собираются в `A_BelongTo_A`. Это не путь в дереве, а признак для массовых операций (`fxC_MassDeletingNode_0010`, `fC_ChangingNodesByKey_0011`).
- Хелпер для сборки конфигов — `_fC_NodeCfg(тип, свойства, сигналы, дети)` в [[Сцена Start_Program]]. Памятка по свойствам типовых нод — [[ShablonUI]] (см. «Известные проблемы»).

## Реестр созданных нод
`vXD_All_nodes` (у вызывающей сцены) — `{ИмяНоды: запись}`:
```
{"Node": Node, "name", "Scene_size", "Zero_point", "Size", "A_BelongTo_A": Array, "__Path_to_the_node_location_S"}
```
Имена нод должны быть **уникальны на весь экран** — реестр плоский.

## Функции

### Создание
- **`fC_CreatingNode_1000(X_NodeConfig_D, A_BelongTo_A) -> Dictionary`** — создать одну ноду по конфигу. Шаги: тип → свойства → сигналы → вставка в контейнер по `__Path_to_the_node_location_S`. Возвращает `{имя: запись реестра}`. При ошибке (нет типа, несуществующий тип, нет пути, контейнер не найден) — `push_error` и `{}`.
- **`fC_MassCreatingNode_0001(vXD_NodeConfig, vXD_All_nodes)`** — создать всё дерево одним проходом `UniversalBypass` ([[Class_ArrayAndOrDictionary]]) с callback `f__MassCreateCallback`. Имена и пути выставляет сам. Реестр и конфиг меняются на месте.
- **`fxG_BatchFillingNodeConfig_1000(vD_BaseTemplate, vD_DiffTemplate, vI_Count) -> Dictionary`** — размножить шаблон ноды на N копий: `%N` в строках заменяется на номер (с 1). Имя копии — из `__name_S` (по умолчанию `Node%N`), остальные поля `vD_DiffTemplate` записываются в `__Inspector_D` копии.

### Синхронизация
- **`fC_SyncingNodesWithConfig_1111(vXD_All_nodes, vXD_OldConfig, vXD_NewConfig) -> Dictionary`** — привести экран от старого конфига к новому. Возвращает копию нового — её сохраняют как «старый» для следующего вызова. Два прохода:
	1. По новому конфигу (`f__SyncCallback_CreateOrUpdate`): новых нод нет в реестре → создать, существующие → `_fC_SyncExistingNode`.
	2. По старому конфигу (`f__SyncCallback_Delete`): ноды, которых больше нет, удалить (`_fC_DeleteNodeByConfigKey`).
	
	Первое построение экрана можно делать и так: `old = {}` → `new = конфиг`.
- **`_fC_SyncExistingNode(...)`** — сравнивает старый и новый конфиг одной ноды через `fC_ComparisonsOf2Variables_0101` ([[Class_ArrayAndOrDictionary]]):
	- всё совпало (`+…`) → ничего;
	- изменились `__Data_D` или `__Node_D` → пересоздать (`queue_free` + `fC_CreatingNode_1000`);
	- изменился только `__Inspector_D` → точечно `.set()` изменившихся свойств через `fxC_UpdatingExistingNodes_0100`.

### Изменение и удаление
- **`fxC_UpdatingExistingNodes_0100(vXD_All_nodes, vD_Changes)`** — `{Имя: {свойство: значение}}` → `.set()` у существующих нод. Отсутствующая нода или свойство — предупреждение, без падения.
- **`fC_ChangingNodesByKey_0011(vXD_All_nodes, vXA_Array_key, vLS_func, vLD_func_variable)`** — для каждой ноды реестра, у которой в `A_BelongTo_A` есть одна из переданных меток, вызывает `vLS_func(реестр, имя_ноды, метка, массив_на_удаление, vLD_func_variable)`. Функция возвращает `[продолжать_по_меткам, продолжать_по_нодам]`: `false` в позиции [0] прерывает перебор меток этой ноды, в позиции [1] — весь обход.- **`fxC_MassDeletingNode_0010(MassOfExistingNodes, RemovalCondition: Callable)`** — удалить ноды, у которых хотя бы одна метка из `A_BelongTo_A` удовлетворяет условию `RemovalCondition(метка, запись)`.
- **`fxC_SwitchingScene_0000(scene_path)`** — сменить сцену (`change_scene_to_file`, отложенно).

### Служебные
- `_fC_IsNodeConfig(d)` — есть ли `__Data_D`, `__Inspector_D` и `__Node_D`.
- `_fC_WalkAncestorLevels_A`, `_fC_RealNodePath_A`, `_fC_CollectBelongTo_A` — проход от корня по пути: реальный путь до родителя (без обёрток) и накопленные метки `v__Ebeveyn`.
- `_fC_SafeGetByPath(root, path)` — значение по пути или `null` без падения.
- `f__MassCreateCallback`, `f__SyncCallback_CreateOrUpdate`, `f__SyncCallback_Delete` — callbacks для `UniversalBypass`.
- `_fC_DeleteNodeByConfigKey` — убрать ноду из реестра. Безопасно для уже удалённых каскадом детей (`is_instance_valid`).

## Логирование
Пишет в поток `vCC_ClassArrDict._vC_ActiveStreamId` (тот же, что у [[Class_ArrayAndOrDictionary]]) через автозагрузку `Logger` — только если поток задан. При обычной сборке экрана поток не регистрируется, поэтому логи `Class_UI` молчат.

## Известные проблемы
- **Пересоздание ноды с детьми.** При смене `__Data_D`/`__Node_D` нода удаляется вместе с детьми (каскадно), а заново создаётся только она сама — дети в этом же проходе не восстанавливаются. Точечных обновлений (`__Inspector_D`) это не касается. В реестре при этом остаются записи уже уничтоженных детей. [[Сцена TestInterface]] проверяет исправление этого бага, но в текущем коде исправления нет: пересоздание идёт через `fC_CreatingNode_1000`, а не `fC_MassCreatingNode_0001`. Сам тест, скорее всего, проходит ложно (см. его документ).
- **`fxC_ZoneReplacement` нерабочая** (`erase()` без аргумента, последняя строка ничего не делает). Нигде не вызывается.
- **[[ShablonUI]] частично устарел:** в заготовках указан `__Path_to_the_node_location_S` (теперь выставляется сам) и названия свойств Godot 3 (`rect_min_size`, `rect_clip_content`; в Godot 4 — `custom_minimum_size`, `clip_contents`).
- В записи реестра `"name"` по умолчанию `Vector2i.ZERO`, а `__Path_to_the_node_location_S` по умолчанию `Vector2.ZERO` — опечатки значений по умолчанию, на работу не влияют.
- Имена служебных функций и callbacks не по [[README]].

## Связи
- Использует: [[Class_ArrayAndOrDictionary]], [[Class_Logger]]
- Используется: [[Сцена Start_Program]], [[Сцена TestInterface]]
- Памятка: [[ShablonUI]]
- История: [[Журнал Class_UI]]
