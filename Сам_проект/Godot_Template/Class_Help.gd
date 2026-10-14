extends Node

class_name Class_Help

##Версия оформления
##2026-08-09 - mzs7 - добавлены ITERABLE_TYPES_MAP/ARRAY_TYPES_MAP (алиасы ITERABLE_TYPES/ARRAY_TYPES
##	под именем, которое уже использует Class_ArrayAndOrDictionary и Class_UI — см. Обзор проекта.md,
##	раздел «Замеченные несостыковки»), и опциональные параметры логирования в FunctionCall
##2026-08-16 - mzs7 - убран голый print("-FunctionCall-  ", ...) — в отличие от гейтованного
##	Logger-вызова прямо под ним (тот пишет, только если vC_Logger!=null и vC_StreamId!=""),
##	этот print был БЕЗУСЛОВНЫМ и печатал на КАЖДЫЙ вызов FunctionCall — а через FunctionCall
##	идёт вообще любой callback в UniversalBypass/PassageAlongWay (то есть буквально каждый
##	ключ, который UniversalBypass посещает при обходе). Тот же класс проблемы, что уже нашли
##	и починили в Class_ArrayAndOrDictionary.PassageAlongWay (см. её changelog, 2026-08-16) —
##	только этот print ещё "выше" по цепочке вызовов и потенциально даёт ещё больше сообщений

var TYPE_NAMES := {
	TYPE_NIL: "Nil",
	TYPE_BOOL: "Bool",
	TYPE_INT: "Int",
	TYPE_FLOAT: "Float",
	TYPE_STRING: "String",
	TYPE_VECTOR2: "Vector2",
	TYPE_VECTOR2I: "Vector2i",
	TYPE_RECT2: "Rect2",
	TYPE_RECT2I: "Rect2i",
	TYPE_VECTOR3: "Vector3",
	TYPE_VECTOR3I: "Vector3i",
	TYPE_TRANSFORM2D: "Transform2D",
	TYPE_VECTOR4: "Vector4",
	TYPE_VECTOR4I: "Vector4i",
	TYPE_PLANE: "Plane",
	TYPE_QUATERNION: "Quaternion",
	TYPE_AABB: "AABB",
	TYPE_BASIS: "Basis",
	TYPE_TRANSFORM3D: "Transform3D",
	TYPE_COLOR: "Color",
	TYPE_STRING_NAME: "StringName",
	TYPE_NODE_PATH: "NodePath",
	TYPE_RID: "RID",
	TYPE_OBJECT: "Object",
	TYPE_CALLABLE: "Callable",
	TYPE_SIGNAL: "Signal",
	TYPE_DICTIONARY: "Dictionary",
	TYPE_ARRAY: "Array",
	TYPE_PACKED_BYTE_ARRAY: "PackedByteArray",
	TYPE_PACKED_INT32_ARRAY: "PackedInt32Array",
	TYPE_PACKED_INT64_ARRAY: "PackedInt64Array",
	TYPE_PACKED_FLOAT32_ARRAY: "PackedFloat32Array",
	TYPE_PACKED_FLOAT64_ARRAY: "PackedFloat64Array",
	TYPE_PACKED_STRING_ARRAY: "PackedStringArray",
	TYPE_PACKED_VECTOR2_ARRAY: "PackedVector2Array",
	TYPE_PACKED_VECTOR3_ARRAY: "PackedVector3Array",
	TYPE_PACKED_COLOR_ARRAY: "PackedColorArray"
}

var ITERABLE_TYPES := {
	TYPE_ARRAY: true,
	TYPE_DICTIONARY: true,
	TYPE_PACKED_BYTE_ARRAY: true,
	TYPE_PACKED_INT32_ARRAY: true,
	TYPE_PACKED_INT64_ARRAY: true,
	TYPE_PACKED_FLOAT32_ARRAY: true,
	TYPE_PACKED_FLOAT64_ARRAY: true,
	TYPE_PACKED_STRING_ARRAY: true,
	TYPE_PACKED_VECTOR2_ARRAY: true,
	TYPE_PACKED_VECTOR3_ARRAY: true,
	TYPE_PACKED_COLOR_ARRAY: true
}

var ARRAY_TYPES := {
	TYPE_ARRAY: true,
	TYPE_PACKED_BYTE_ARRAY: true,
	TYPE_PACKED_INT32_ARRAY: true,
	TYPE_PACKED_INT64_ARRAY: true,
	TYPE_PACKED_FLOAT32_ARRAY: true,
	TYPE_PACKED_FLOAT64_ARRAY: true,
	TYPE_PACKED_STRING_ARRAY: true,
	TYPE_PACKED_VECTOR2_ARRAY: true,
	TYPE_PACKED_VECTOR3_ARRAY: true,
	TYPE_PACKED_COLOR_ARRAY: true
}

## Алиасы под именем с суффиксом _MAP — этим именем уже пользуются Class_ArrayAndOrDictionary
## (fC_OvergrowthIf_Tr) и Class_UI, хотя в этом файле переменные всегда назывались без _MAP.
## Ссылаются на ТЕ ЖЕ словари выше (не копии — Dictionary в GDScript передаётся по ссылке),
## поэтому это просто второе имя для одних и тех же данных, а не дублирование
var ITERABLE_TYPES_MAP := ITERABLE_TYPES
var ARRAY_TYPES_MAP := ARRAY_TYPES


func get_iter_keys(container):
	var type_id = typeof(container)
	if type_id == TYPE_DICTIONARY:
		return container.keys()
	if type_id == TYPE_ARRAY or type_id in ARRAY_TYPES:
		return range(container.size())
	return null


##Функционал:
##	Вызывает callback-функцию, переданную в словаре FuncParametrs, собрав ей аргументы
##	из FuncParametrs["Parametrs"] и (опционально) EmbeddedParameters
##Форматы данных:
##	Входные:
##		FuncParametrs: Dictionary — {"func": Callable, "Parametrs": Array/Dictionary (опц.)}
##		EmbeddedParameters — доп. параметры, добавляемые к FuncParametrs["Parametrs"]; null, если не нужны
##		vC_Logger — экземпляр Class_Logger вызывающего объекта; null, если логирование не нужно
##		vC_StreamId: String — id активного потока вызывающего объекта; "", если логирование не нужно
##	Выходные:
##		Variant — то, что вернул вызванный callback
##Принцип работы:
##	Без изменений в основной логике (не трогаем — код используется другими классами).
##	Добавлено только необязательное логирование вызова: если переданы vC_Logger и vC_StreamId —
##	перед вызовом callback пишем в лог, какая функция вызывается и с какими параметрами
func FunctionCall (FuncParametrs: Dictionary, EmbeddedParameters = null, vC_Logger = null, vC_StreamId: String = ""):
	if not FuncParametrs.has("func"):
		push_error("FunctionCall FuncParametrs missing 'func' key")
		return
	if typeof(FuncParametrs ["func"]) != TYPE_CALLABLE:
		push_error("FunctionCall FuncParametrs [func] not Callable. Actual value: ", FuncParametrs["func"], " Type: ", typeof(FuncParametrs ["func"]))
		return
	elif FuncParametrs ["func"] == null:
		push_error("FunctionCall FuncParametrs [func] is null")
		return null
	else:
		if FuncParametrs.has("Parametrs"):
			if not ITERABLE_TYPES.has(typeof(FuncParametrs ["Parametrs"])):
				push_error("FunctionCall FuncParametrs [Parametrs] not ITERABLE_TYPES")
				return
		else:
			FuncParametrs ["Parametrs"] = []
		var Parametrs
		if typeof(FuncParametrs ["Parametrs"]) == typeof(EmbeddedParameters) and EmbeddedParameters != null:
			if typeof(FuncParametrs ["Parametrs"]) == TYPE_DICTIONARY and typeof(EmbeddedParameters) == TYPE_DICTIONARY:
				# Создаем копию параметров, чтобы избежать изменений оригинала
				Parametrs = FuncParametrs ["Parametrs"].duplicate()
				Parametrs.merge(EmbeddedParameters)
			elif ITERABLE_TYPES.has(typeof(FuncParametrs ["Parametrs"])) and ITERABLE_TYPES.has(typeof(EmbeddedParameters)):
				Parametrs = FuncParametrs ["Parametrs"] + EmbeddedParameters
			else:
				push_error("FunctionCall FuncParametrs [Parametrs] and EmbeddedParameters not one type")
				return
		elif EmbeddedParameters == null:
			# Создаем копию параметров, чтобы избежать изменений оригинала
			Parametrs = FuncParametrs ["Parametrs"].duplicate()
		else:
			push_error("FunctionCall FuncParametrs [Parametrs] and EmbeddedParameters not one type")
			return
		# Логируем сам факт вызова callback-а — только если вызывающий объект передал
		# свой логгер и активный StreamId; иначе (vC_Logger == null) ничего не пишем —
		# это оставляет FunctionCall безопасным для всех остальных мест, которые его
		# вызывают без логгера (например, Class_UI)
		if vC_Logger != null and vC_StreamId != "":
			vC_Logger.fC_Adding_Buffer_Cr(vC_StreamId, "Class_Help.FunctionCall: " + str(FuncParametrs["func"]), Parametrs, null)
		var Return = FuncParametrs ["func"].call (Parametrs)
		return Return
