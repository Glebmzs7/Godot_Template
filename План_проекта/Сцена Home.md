# Сцена Home

Путь: `res://Scenes/UIScenes/Home/home.gd` + `res://Scenes/UIScenes/Home/Home.tscn`
Наследует: `Control`

## Для чего нужна
По задумке — центральный экран приложения (нижняя панель с кнопками "Чек листы"/"Дела"/"Состояния / Здоровья"/"Финансы", верхняя панель со счётчиком прожитого времени и кнопкой настроек). [[Сцена Start_Program]] ведёт на неё после прохождения чек-листа (`Class_UI.fxC_SceneSwitching`).

## 2026-08-24 — очищена по просьбе пользователя
Содержимое `home.gd`, описанное ниже, было полностью удалено (по просьбе "Очисти home") — этот файл фиксирует, как сцена выглядела ДО очистки, для истории/справки. Сама сцена (`Home.tscn`) не менялась — только скрипт.

### Почему было решено очистить, а не оставить
Код был не просто черновиком, а фактически неработоспособным:
- `vXD_BottomPanel_D` (описание нижней панели с 4 кнопками) на верхнем уровне скрипта, в инициализаторе `var`, вызывал `ArrayAndOrDictionary.fG_RecursiveMassDictionaryMerging_Cr(...)` для каждой из 4 кнопок — такой функции **нет** ни в [[Class_ArrayAndOrDictionary]], ни где-либо ещё в проекте (проверено на 2026-08-24). Так как это инициализатор `var`, а не код внутри функции, вызов должен был выполняться уже при создании объекта скрипта — то есть сцена, по всей видимости, не могла даже загрузиться без ошибки.
- `_ready()` вызывал `ArrayAndOrDictionary.fG_DictionaryСomparisons_Cr(...)` — такой функции тоже нет.
- Реальная сборка интерфейса (`vSC_ClassUI.fC_Mass_Creating_Node_CrTr(...)` для обеих панелей, через `add_child(vSC_ClassUI)`) была полностью закомментирована — то есть даже если бы вышеописанные ошибки не возникали, кнопки/панели всё равно не появились бы на экране.
- `_ready()` фактически только сравнивал два тестовых словаря (`dG_DictA`/`dG_DictB`) через `fG_DictionaryСomparisons_Cr` (несуществующую) и печатал результат — то есть был черновиком для проверки самой функции сравнения словарей, а не рабочим экраном.

### Полный текст home.gd до очистки

```gdscript
#Версия оформления кода 0.1.1.1
#Центральный UI блок
#Волов Глеб Андреевич (mzs7)

#Подгрузка библиотек 
extends Control
var vSC_ClassUI = preload("res://Class/Class_UI.gd").new()
var ArrayAndOrDictionary = preload("res://Class/Class_ArrayAndOrDictionary.gd").new()

#Создания интерфейса
#Общие сдандарты
#Размер сцены
var vSV2_Scene_size_V2i = Vector2 (1080, 1920)
#Хранилище данных о нодах
var vSD_AseNode_D := {}
#Время
var current_datetime = Time.get_datetime_dict_from_system()
#Шаблон кнопки
var Button_Template = {
		"__Data_D": {
			"__type_S": "Button",
			"__Scene_size_V2i": vSV2_Scene_size_V2i,
				},
		"__Inspector_D": {
			"size_flags_horizontal": 3,
			"size_flags_vertical": 1,
			"theme_override_font_sizes/font_size": 32
				},
		"__Node_D": {},
		}
#Оботка для команды смены варинты сцны
func fxL__Wrapper_DeleteTopPanel_Ch(TypeToDelete: Array):
	vSC_ClassUI.fxC_MassDelitNode(vSD_AseNode_D, 
		func(elMOFNABA, node_data): 
			for elTOD in TypeToDelete:
				if elTOD == elMOFNABA:
					return true
			return false
	)
#Нижная понель
#Общие для кнопок
var vXD_Button_Template_BottomPanel_D := {
		"__Data_D": {
			"__Path_to_the_node_location_S": "MarginContainer/HBox_Buttons"
			},
		}
#Все элементы
var vXD_BottomPanel_D := {
		"BottomPanel":{
			"v__Ebeveyn": "BottomPanel",
			
			"MarginContainer": {
				"__Data_D": {
					"__type_S": "MarginContainer",
					"__Scene_size_V2i": vSV2_Scene_size_V2i,
					"__Path_to_the_node_location_S": "."
				},
				"__Inspector_D": {
					"name": "MarginContainer",
					"anchor_left": 0.0,
					"anchor_top": 1.0,
					"anchor_right": 1.0,
					"anchor_bottom": 1.0,
					"offset_top": -150, # высота панели снизу
					"offset_bottom": 0,
					"offset_left": 0,
					"offset_right": 0
				},
				"__Node_D": {}
			},

			# Вложенный GBoxContainer
			"HBox_Buttons": {
				"__Data_D": {
					"__type_S": "HBoxContainer",
					"__Scene_size_V2i": vSV2_Scene_size_V2i,
					"__Path_to_the_node_location_S": "MarginContainer"},
				"__Inspector_D": {
					"name": "HBox_Buttons",
					"alignment": 1, # центр
					"anchors_preset": 15,
					"anchor_left": 0.5,
					"anchor_right": 0.5,
					"offset_left": -100,
					"offset_right": 100,
					"offset_top": -200,
					"offset_bottom": 0},
				"__Node_D": {},
			},

			# Кнопка 1 — Чек листы
			"Button_CheckList": ArrayAndOrDictionary.fG_RecursiveMassDictionaryMerging_Cr ([Button_Template,vXD_Button_Template_BottomPanel_D,{
				"__Inspector_D": {
						"name": "Button_CheckList",
						"text": "Чек листы"
					},
				"__Node_D": {
					"pressed": Callable(self, "fxL__Wrapper_DeleteTopPanel_Ch").bind (["TopPanel"])}
				}]),


			# Кнопка 2 — Дела
			"Button_Tasks": ArrayAndOrDictionary.fG_RecursiveMassDictionaryMerging_Cr ([Button_Template,vXD_Button_Template_BottomPanel_D,{
				"__Inspector_D": {
					"name": "Button_Tasks",
					"text": "Дела",
					}
				}]),


			# Кнопка 3 — Состояния/Здоровья
			"Button_Status":  ArrayAndOrDictionary.fG_RecursiveMassDictionaryMerging_Cr ([Button_Template,vXD_Button_Template_BottomPanel_D,{
				"__Inspector_D": {
					"name": "Button_Status",
					"text": "Состояния / Здоровья",
					}
				}]),


			# Кнопка 4 — Финансы
			"Button_finans":  ArrayAndOrDictionary.fG_RecursiveMassDictionaryMerging_Cr ([Button_Template,vXD_Button_Template_BottomPanel_D,{
				"__Inspector_D": {
					"name": "Button_Status",
					"text": "Финансы",
					}
				}]),
		}
	}

#Верхния понель
var vXD_TopPanel_D := {
	"TopPanel": {
		"v__Ebeveyn": "TopPanel",
		"Counter":{
			"v__Ebeveyn": "Counter",
			"MarginContainer2": {
				"__Data_D": {
					"__type_S": "MarginContainer",
					"__Scene_size_V2i": vSV2_Scene_size_V2i,
					"__Path_to_the_node_location_S": "."
				},
				"__Inspector_D": {
					"name": "MarginContainer2",
					"anchor_left": 0.0,
					"anchor_top": 0.0,
					"anchor_right": 1.0,
					"anchor_bottom": 0.0,
					"offset_top": 0,
					"offset_bottom": 150, # высота верхней панели
					"offset_left": 0,
					"offset_right": 0
				},
				"__Node_D": {}
			},

			"LifeTime_Label": {
				"__Data_D": {
					"__type_S": "Label",
					"__Scene_size_V2i": vSV2_Scene_size_V2i,
					"__Path_to_the_node_location_S": "MarginContainer2"
				},
				"__Inspector_D": {
					"name": "LifeTime_Label",
					"text": "Прожито: 0 сек\nОсталось до 50 лет: 0 сек",
					"align": 1, # выравнивание по центру
					"valign": 1,
					"size_flags_horizontal": 3,
					"size_flags_vertical": 3,
					"theme_override_font_sizes/font_size": 32 # крупный шрифт
				},
				"__Node_D": {}
			},
		"Settings":{
			"v__Ebeveyn": "Settings",
			"Settings_Button": {
				"__Data_D": {
					"__type_S": "Button",
					"__Scene_size_V2i": vSV2_Scene_size_V2i,
					"__Path_to_the_node_location_S": "MarginContainer2"
				},
				"__Inspector_D": {
					"name": "Settings_Button",
					"text": "Настройки",
					"anchor_left": 1.0, # Якорь справа
					"anchor_top": 0.0,
					"anchor_right": 1.0,
					"anchor_bottom": 1.0,
					"offset_left": -150, # Ширина кнопки
					"offset_right": -10, # Отступ от правого края
					"offset_top": 10,
					"offset_bottom": -10,
					"theme_override_font_sizes/font_size": 20
				},
				"__Node_D": {}
				}
			}
		}
	}
}



var dG_DictA: = {
	"Name": "Knight",
	"Level": 10,
	"Stats": {
		"Health": 100,
		"Attack": 25,
		"Defense": 18
	},
	"Inventory": ["Sword", "Shield", "Potion"]
}

var dG_DictB: = {
	"Name": "Knight",
	"Level": 10,
	"Stats": {
		"Health": 95, # небольшое отличие
		"Attack": 25,
		"Defense": 20 # изменено значение
	},
	"Inventory": ["Sword", "Shield"] # отсутствует один элемент
}

var dG_DictC: = {}

#Первичный запуск
func _ready() -> void:
	ArrayAndOrDictionary.fG_DictionaryСomparisons_Cr (dG_DictA, dG_DictB, dG_DictC)
	print(dG_DictC)
	print (dG_DictA)
	print (dG_DictB)
	#add_child(vSC_ClassUI)
	#vSC_ClassUI.fC_Mass_Creating_Node_CrTr(vXD_BottomPanel_D, vSD_AseNode_D)
	#vSC_ClassUI.fC_Mass_Creating_Node_CrTr(vXD_TopPanel_D, vSD_AseNode_D)
	#print(vSD_AseNode_D)
```

### Home.tscn (не менялся)
```
[gd_scene load_steps=2 format=3 uid="uid://bwttb6wevcfcl"]

[ext_resource type="Script" uid="uid://blibakj54o7r0" path="res://Scenes/UIScenes/Home/home.gd" id="1_kp5ig"]

[node name="Home" type="Control"]
layout_mode = 3
anchors_preset = 15
anchor_right = 1.0
anchor_bottom = 1.0
grow_horizontal = 2
grow_vertical = 2
script = ExtResource("1_kp5ig")
```

## Текущее состояние (после очистки)
`home.gd` сведён к пустому минимальному скрипту (`extends Control`, пустой `_ready()`) — сцена больше не содержит нерабочего кода, ждёт новой реализации с нуля. `Home.tscn` не тронут.

## Связано с
- [[Сцена Start_Program]] — переключает на эту сцену после прохождения чек-листа
- [[Обзор проекта]]
- [[Class_ArrayAndOrDictionary]]
- [[Class_UI]]
