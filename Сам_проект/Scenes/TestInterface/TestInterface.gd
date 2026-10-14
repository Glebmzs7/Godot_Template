extends Node

## Регрессионный тест для фикса, из-за которого дети пересоздаваемой ноды
## (вложенные под ключом-обёрткой рядом с __Data_D/__Inspector_D/__Node_D)
## терялись — fC_SyncingNodesWithConfig_1111 теперь вызывает
## fC_MassCreatingNode_0001 (обёрнутый по имени) вместо одиночного создателя
## ноды и в ветке создания новой ноды, и в ветке пересоздания существующей.

var _ui = load("res://Godot_Template/Class_UI.gd").new()
var _all_nodes: Dictionary = {}


func _build_config(panel_type: String) -> Dictionary:
	return {
		"TestPanel": {
			"__Data_D": {"__type_S": panel_type, "__Scene_size_V2i": Vector2i(540, 900)},
			"__Inspector_D": {"anchor_right": 1.0, "anchor_bottom": 1.0},
			"__Node_D": {},
			"Children": {
				"TestChildLabel": {
					"__Data_D": {"__type_S": "Label", "__Scene_size_V2i": Vector2i(540, 900)},
					"__Inspector_D": {"text": "child"},
					"__Node_D": {},
				},
			},
		},
	}


func _ready() -> void:
	add_child(_ui)

	var config_a: Dictionary = _build_config("Panel")
	_ui.fC_MassCreatingNode_0001(config_a, _all_nodes)
	var child_present_after_create: bool = _all_nodes.has("TestChildLabel")

	# Меняем __type_S у TestPanel, чтобы вызвать полное пересоздание — это тот
	# же признак, по которому _fC_SyncExistingNode решает "пересоздать, а не
	# просто обновить"
	var config_b: Dictionary = _build_config("PanelContainer")
	_ui.fC_SyncingNodesWithConfig_1111(_all_nodes, config_a, config_b)
	var child_present_after_recreate: bool = _all_nodes.has("TestChildLabel")

	var passed: bool = child_present_after_create and child_present_after_recreate
	if passed:
		print("TestInterface: PASSED — child survived create and recreate")
	else:
		print("TestInterface: FAILED — child after create: %s, child after recreate: %s" % [
			child_present_after_create, child_present_after_recreate,
		])
