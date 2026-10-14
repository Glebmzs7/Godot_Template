# === UI NODE REFERENCE / Памятка по настройкам ===
# Формат совместим с твоей системой UI-шаблонов

# БАЗОВЫЙ Control — корень всех UI-элементов
var Control_Template := {
	"__Data_D": {
		"__type_S": "Control", # Базовый UI-узел (все элементы UI наследуют его)
		"__Scene_size_V2i": vSV2_Scene_size_V2i,
		"__Path_to_the_node_location_S": "."
	},
	"__Inspector_D": {
		# === Геометрия и позиционирование ===
		"anchor_left": 0.0,   # Привязка к левой стороне родителя (0 = абсолютное позиционирование)
		"anchor_top": 0.0,    # Привязка к верхней стороне
		"anchor_right": 0.0,  # Привязка к правой
		"anchor_bottom": 0.0, # Привязка к нижней
		"offset_left": 0,     # Отступ от левой границы
		"offset_top": 0,      # Отступ от верхней
		"offset_right": 0,    # Отступ от правой
		"offset_bottom": 0,   # Отступ от нижней

		# === Размеры и поведение ===
		"rect_min_size": Vector2(0, 0), # Минимальный размер
		"size_flags_horizontal": 1, # 1 = Fill, 2 = Expand, 3 = Fill+Expand
		"size_flags_vertical": 1,   # Как ведёт себя по вертикали
		"rect_clip_content": false, # true — обрезает дочерние элементы за границами

		# === Взаимодействие и фокус ===
		"mouse_filter": 0, # 0 = Stop (ловит мышь), 1 = Pass (пропускает), 2 = Ignore (не ловит)
		"focus_mode": 2,   # 0 = Нет фокуса, 1 = По клику, 2 = По клавиатуре

		# === Внешний вид ===
		"theme_override_font_sizes/font_size": 16, # Размер шрифта, если есть текст
		"theme_override_colors/font_color": Color(1,1,1,1), # Цвет текста / интерфейса

		# === Подсказки ===
		"tooltip_text": "", # Всплывающая подсказка при наведении
	}
}

# LABEL — простой текстовый элемент
var Label_Template := {
	"__Data_D": {
		"__type_S": "Label",
		"__Scene_size_V2i": vSV2_Scene_size_V2i,
		"__Path_to_the_node_location_S": "."
	},
	"__Inspector_D": {
		"text": "Пример текста", # Отображаемая строка
		"bbcode_enabled": false, # Разрешить BBCode для форматирования
		"autowrap_mode": 1,      # 0 = Нет, 1 = Перенос по словам
		"horizontal_alignment": 1, # 0=лево, 1=центр, 2=право, 3=растянуть
		"vertical_alignment": 1,   # 0=верх, 1=центр, 2=низ, 3=растянуть
		"line_spacing": 0,         # Межстрочный интервал
		"clip_text": false,        # true = обрезать текст по границам
		"theme_override_font_sizes/font_size": 24, # Размер шрифта
		"theme_override_colors/font_color": Color(1,1,1,1) # Цвет текста
	}
}

# BASE BUTTON — общий базовый класс кнопок
var BaseButton_Template := {
	"__Data_D": {
		"__type_S": "BaseButton",
		"__Scene_size_V2i": vSV2_Scene_size_V2i,
		"__Path_to_the_node_location_S": "."
	},
	"__Inspector_D": {
		"disabled": false,    # true = неактивна
		"toggle_mode": false, # true = переключатель
		"pressed": false,     # Состояние "нажата" (для toggle)
		"flat": false,        # Без фона, если true
		"focus_mode": 2,      # 2 = можно выбрать клавиатурой
		"theme_override_font_sizes/font_size": 20,
		"group": null,        # Группа кнопок (Radio-группы)
	}
}

# BUTTON — стандартная текстовая кнопка
var Button_Template := {
	"__Data_D": {
		"__type_S": "Button",
		"__Scene_size_V2i": vSV2_Scene_size_V2i,
		"__Path_to_the_node_location_S": "."
	},
	"__Inspector_D": {
		# --- Унаследовано из BaseButton ---
		"disabled": false,
		"toggle_mode": false,
		"flat": false,

		# --- Уникальные свойства Button ---
		"text": "Кнопка",           # Отображаемый текст
		"alignment": 1,             # Выравнивание текста по горизонтали (0=лево,1=центр,2=право)
		"vertical_alignment": 1,    # Вертикальное выравнивание
		"icon": null,               # Иконка (через тему)
		"icon_alignment": 0,        # Положение иконки (0=слева, 1=справа)
		"theme_override_font_sizes/font_size": 22, # Размер текста
		"theme_override_colors/font_color": Color(1,1,1,1),
	}
}

# TEXTURE BUTTON — кнопка с текстурами (иконки, состояния)
var TextureButton_Template := {
	"__Data_D": {
		"__type_S": "TextureButton",
		"__Scene_size_V2i": vSV2_Scene_size_V2i,
		"__Path_to_the_node_location_S": "."
	},
	"__Inspector_D": {
		# --- Основное ---
		"texture_normal": "res://textures/btn_normal.png",  # Текстура по умолчанию
		"texture_pressed": "res://textures/btn_pressed.png",# При нажатии
		"texture_hover": "res://textures/btn_hover.png",    # При наведении
		"texture_disabled": "res://textures/btn_disabled.png", # Неактивна
		"expand": true,          # Подгонка текстуры под размер
		"stretch_mode": 2,       # 0=scale,1=tile,2=fit,3=keep_aspect
		"modulate": Color(1,1,1,1), # Цветовой фильтр текстуры
		"flip_h": false,         # Отразить по горизонтали
		"flip_v": false,         # Отразить по вертикали
	}
}

# HBOX CONTAINER — контейнер, размещающий детей по горизонтали
var HBoxContainer_Template := {
	"__Data_D": {
		"__type_S": "HBoxContainer",
		"__Scene_size_V2i": vSV2_Scene_size_V2i,
		"__Path_to_the_node_location_S": "."
	},
	"__Inspector_D": {
		"alignment": 1, # 0=начало, 1=середина, 2=конец
		"separation": 8, # Пикселей между элементами
		"theme_override_constants/separation": 8, # Можно переопределить через тему
		"size_flags_horizontal": 3, # Растягивает содержимое
		"size_flags_vertical": 1,
	}
}

# VBOX CONTAINER — вертикальный вариант
var VBoxContainer_Template := {
	"__Data_D": {
		"__type_S": "VBoxContainer",
		"__Scene_size_V2i": vSV2_Scene_size_V2i,
		"__Path_to_the_node_location_S": "."
	},
	"__Inspector_D": {
		"alignment": 1, # 0=начало, 1=центр, 2=конец
		"separation": 8,
		"theme_override_constants/separation": 8
	}
}
