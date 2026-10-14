extends Node

## Регрессионный тест: Class_Logger.gd теперь общий автозагружаемый синглтон
## ("Logger" в project.godot), а не отдельный экземпляр на каждый класс.
## Регистрирует два потока, имитируя два разных класса, и проверяет, что оба
## попали в ОДИН И ТОТ ЖЕ файл лога сессии — в этом и был смысл фикса автозагрузки.

var _json = load("res://Godot_Template/Class_Json.gd").new()


func _ready() -> void:
	Logger.fxG_StartingLogger_CrTr("test")

	var stream_a: String = Logger.fC_RegisterStream_Cr("TestLogger_ContextA")
	Logger.fC_Adding_Buffer_Cr(stream_a, "Message from context A", [], null)
	Logger.fC_FinishStream_Ch(stream_a)

	var stream_b: String = Logger.fC_RegisterStream_Cr("TestLogger_ContextB")
	Logger.fC_Adding_Buffer_Cr(stream_b, "Message from context B", [], null)
	Logger.fC_FinishStream_Ch(stream_b)

	Logger.fC_Saving_Logs_Ch()

	var log_path: String = Logger.FileLogger
	var saved: Dictionary = _json.fxG_LoadJson_Cr(log_path)
	var streams: Dictionary = saved.get("Streams", {})
	var passed: bool = streams.has(stream_a) and streams.has(stream_b) \
		and not streams.get(stream_a, []).is_empty() and not streams.get(stream_b, []).is_empty()

	if passed:
		print("TestLogger: PASSED — both streams found in %s" % log_path)
	else:
		print("TestLogger: FAILED — see %s" % log_path)
