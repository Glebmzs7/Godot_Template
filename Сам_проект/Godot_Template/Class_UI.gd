##Версия оформления
##2026-08-16 - mzs7 - добавлена fC_SyncingNodesWithConfig_1111: рекурсивно сравнивает старый и
##	новый конфиг нод через fC_ComparisonsOf2Variables_0101 (Class_ArrayAndOrDictionary) и
##	сама вызывает создание/пересоздание/точечное обновление/удаление нод — см. комментарий
##	прямо над функцией. Обход — через vCC_ClassArrDict.UniversalBypass (тот же обход, что чинили
##	вместе в Class_ArrayAndOrDictionary — см. её changelog про PathArray.pop_back)
##2026-08-16 - mzs7 - попутно починена fxC_UpdatingExistingNodes_0100 (её теперь использует
##	fC_SyncingNodesWithConfig_1111 для точечного обновления): звала несуществующие
##	Class_Logger.fx__Log_Warn/fx__Log_Info (у Class_Logger другой, потоковый API) и
##	несуществующий в Godot 4 node.has_property() — заменено на "property in node"
##2026-08-16 - mzs7 - print/push_warning заменены на vCC_ClassArrDict.Class_Logger.fC_Adding_Buffer_Cr
##	в поток, гейтованный через vCC_ClassArrDict._vC_ActiveStreamId, по тому же принципу, что уже
##	используют Class_ArrayAndOrDictionary/test.gd. Для настоящих проблем (нода не найдена и
##	т.п.) push_warning всё равно вызывается ДОПОЛНИТЕЛЬНО к логу — как это уже делает
##	UniversalBypass с push_error при превышении глубины рекурсии, т.е. в лог и в консоль
##	редактора одновременно, а не взамен друг друга
##	⚠️ ВАЖНО про то, ЧЕЙ Class_Logger/_vC_ActiveStreamId используется: у этого класса своя
##	собственная var Class_Logger (отдельный объект от vCC_ClassArrDict.Class_Logger — ДВА разных
##	экземпляра Class_Logger.gd). Но UniversalBypass/PassageAlongWay/_CP_CO2V внутри
##	Class_ArrayAndOrDictionary жёстко используют СВОЙ ЖЕ vCC_ClassArrDict.Class_Logger и СВОЙ ЖЕ
##	vCC_ClassArrDict._vC_ActiveStreamId — подставить туда чужой логгер снаружи нельзя. Поэтому,
##	чтобы весь обход (и решения Class_UI, и внутренности UniversalBypass) попадал в ОДИН
##	файл лога, а не в два независимых, весь код ниже (fC_SyncingNodesWithConfig_1111 и всё, что
##	она вызывает) читает/пишет ИМЕННО vCC_ClassArrDict._vC_ActiveStreamId и
##	vCC_ClassArrDict.Class_Logger — а не свои собственные. Свой Class_Logger этого класса
##	(объявлен чуть ниже) кодом синхронизации не используется, оставлен как было
##2026-08-16 - mzs7 - ⚠️ БЫЛО ЗАМЕЧЕНО (починено ниже, 2026-08-17): fC_MassCreatingNode_0001
##	звала vCC_ClassArrDict.fC_Overgrowth_tree_Tr — такой функции в Class_ArrayAndOrDictionary.gd
##	не было (только fC_OvergrowthIf_Tr, с другим именем И с другой сигнатурой callback).
##	f__Checking_conditions при этом никогда не вызывался и вся цепочка падала с
##	"Invalid call. Nonexistent function" при первом же вызове
##2026-08-17 - mzs7 - fC_MassCreatingNode_0001 починена и формат конфига сменился на
##	ВЛОЖЕННЫЙ: {ИмяНоды: {__Data_D:{...}, __Inspector_D:{...}, __Node_D:{...},
##	__Children_D: {ИмяРебёнка: {... тот же формат, рекурсивно ...}, ...}}, ...} —
##	__Children_D лежит РЯДОМ с __Data_D/__Inspector_D/__Node_D, в том же словаре ноды
##	(своя, отдельная попытка была без __Children_D — дети прямо вперемешку с __Data_D
##	и т.п. — от неё отказались: __Children_D явно отделяет "тут дети" от "тут данные
##	этой самой ноды", а не полагается на "всё, что не __Data_D/__Inspector_D/__Node_D
##	— значит ребёнок"). Так по построению не может быть детей без родителей — раньше
##	путь и имя набирались руками и могли разойтись с реальной структурой словаря.
##	f__Checking_conditions (нерабочий, под старый формат) удалён, вместо него —
##	f__MassCreateCallback, обход — vCC_ClassArrDict.UniversalBypass (тот же обход, что и у
##	fC_SyncingNodesWithConfig_1111). Имя ноды (__Inspector_D.name) и путь до родителя
##	(__Data_D.__Path_to_the_node_location_S) теперь ВСЕГДА выставляются автоматически —
##	из ключа словаря и цепочки PathArray (для пути — без учёта служебных "__Children_D"
##	в цепочке, см. _fC_StripChildrenMarker_A). Ручные __Path_to_the_node_location_S/name
##	в конфиге больше не нужны и будут молча перезаписаны. Формат конфига в примерах ниже
##	(см. fC_CreatingNode_1000) — старый, для него путь по-прежнему нужно указывать
##	руками; новый вложенный формат — только через fC_MassCreatingNode_0001/
##	fC_SyncingNodesWithConfig_1111
##2026-08-17 - mzs7 - f__SyncCallback_CreateOrUpdate/f__SyncCallback_Delete переведены на
##	тот же вложенный формат (__Children_D) и то же автоматическое имя/путь — иначе
##	fC_MassCreatingNode_0001 (создание) и fC_SyncingNodesWithConfig_1111 (обновление/
##	переключение раскладки) ждали бы от Start_Program.gd два РАЗНЫХ формата одного и
##	того же экрана. Важно: старый/новый конфиг в _fC_SafeGetByPath ищутся по ИСХОДНОМУ
##	PathArray (С "__Children_D" внутри — у old и new одна и та же вложенность, поэтому
##	путь совпадает буквально), а вот путь для fC_CreatingNode_1000 считается через
##	_fC_StripChildrenMarker_A — Godot ничего не знает про "__Children_D", это чисто
##	наша служебная разметка. ⚠️ ИЗВЕСТНОЕ ОГРАНИЧЕНИЕ, НЕ РЕШЕНО: если у ноды с
##	вложенными детьми меняются __Data_D/__Node_D (триггер пересоздания в
##	_fC_SyncExistingNode) — она queue_free()-ится вместе со всеми детьми каскадно на
##	уровне Godot, но fC_CreatingNode_1000 пересоздаёт только ЕЁ саму, не спускаясь во
##	вложенных детей заново; т.е. дети пересозданного контейнера сейчас не гарантированно
##	восстанавливаются в этом же проходе. Для точечных обновлений (__Inspector_D,
##	например якоря при смене ориентации) это не задевает — там всё ок
##2026-08-18 - mzs7 - восстановлен v__Ebeveyn (был у старого, нерабочего
##	f__Checking_conditions) — но это НЕ то же самое, что путь ноды в Godot.
##	"v__Ebeveyn" — необязательный ключ у любого словаря-уровня (нода это или
##	обёртка), его значение накапливается в A_BelongTo_A ПО ВСЕМ уровням от корня
##	до ноды (см. _fC_CollectBelongTo_A) и кладётся в реестр (vXD_All_nodes[имя]
##	["A_BelongTo_A"]) — это чисто логическая метка для массовых операций
##	(fxC_MassDeletingNode_0010/fC_ChangingNodesByKey_0011 ищут по ней), она может вообще не
##	совпадать с реальной вложенностью. Раньше (см. запись 2026-08-17 выше)
##	A_BelongTo_A ошибочно заполнялся структурным путём — метки задваивали путь
##	и не несли отдельного смысла
##2026-08-18 - mzs7 - "__Children_D" перестал быть единственным жёстко зашитым
##	именем ключа-обёртки: f__MassCreateCallback/f__SyncCallback_CreateOrUpdate/
##	f__SyncCallback_Delete больше не сравнивают ключ буквально с "__Children_D" —
##	любой ключ, чьё значение — Dictionary и не является нодой (_fC_IsNodeConfig),
##	считается обёрткой для удобства группировки и просто обходится глубже. Имя
##	такой обёртки можно выбирать по смыслу конкретного случая (например, "набор
##	при разных условиях"), а не обязательно "__Children_D" — Start_Program.gd
##	по-прежнему использует "__Children_D" как принятое соглашение, но это теперь
##	именно соглашение, а не требование обхода. "Дети без родителей" всё равно
##	невозможны — гарантия идёт не от имени ключа, а от того, что путь и
##	A_BelongTo_A строятся из фактической структуры дерева, а не руками
##2026-08-18 - mzs7 - _fC_StripChildrenMarker_A заменена на три хелпера:
##	_fC_WalkAncestorLevels_A (общий проход по PathArray от корня), поверх неё —
##	_fC_RealNodePath_A (путь Godot, только реальные ноды-предки, обёртки
##	пропускаются) и _fC_CollectBelongTo_A (см. выше). Обеим нужен КОРЕНЬ всего
##	дерева конфига, а не только текущий уровень — поэтому fC_MassCreatingNode_0001
##	и fC_SyncingNodesWithConfig_1111 теперь передают его отдельным параметром в
##	Parametrs (root добавлен к [vXD_All_nodes] и к [vXD_All_nodes, vXD_OldConfig])
##2026-08-18 - mzs7 - ⚠️ ПОПУТНО НАЙДЕН И ПОЧИНЕН БАГ: f__MassCreateCallback читал
##	InputArray по индексам [0],[3],[4],[5], хотя при "Parametrs": [vXD_All_nodes]
##	(1 свой параметр) Class_Help.FunctionCall собирает массив всего из 5
##	элементов (0=свой параметр, 1=type_id, 2=vLD_CurrentLevel, 3=vLA_PathArray,
##	4=vL_Key) — индекс [5] был ЗА границей массива. Не проявлялось, потому что
##	функция проверялась только статически (баланс скобок/список функций), ни разу
##	не запускалась в самом Godot. Правильные индексы для 1 своего параметра —
##	[0],[2],[3],[4]; сейчас, после добавления root вторым параметром (см. выше),
##	параметров стало 2 — индексы [0],[1],[3],[4],[5], как и у синхронизации
##2026-08-19 - mzs7 - ⚠️ ДОЧИНЕНО: 2 "забытых" print() в fC_CreatingNode_1000 (замечены
##	при работе над Start_Program.gd/окном настроек) — changelog от 2026-08-16 выше says
##	print/push_warning уже заменили на vCC_ClassArrDict.Class_Logger.fC_Adding_Buffer_Cr, но
##	эти два пропустили при переносе. Заменены на ТОТ ЖЕ гейтованный паттерн, что уже везде
##	в файле (if vCC_ClassArrDict._vC_ActiveStreamId != "": ... fC_Adding_Buffer_Cr(...)) — не
##	новая логика, а доведение уже начатой миграции до конца. ⚠️ Важный нюанс: при вызове через
##	fC_MassCreatingNode_0001 (так строится экран при первом запуске — Start_Program._ready)
##	vCC_ClassArrDict._vC_ActiveStreamId сейчас НЕ регистрируется, значит эти два лога там
##	по-прежнему молчат — так же, как молчали бы и старые print(), просто теперь через общий
##	с остальным файлом механизм, а не отдельным способом. Регистрация отдельного потока для
##	mass-create — уже другая, более широкая задача, в эту правку не входит
extends Node
class_name Class_UI

var vCC_ClassArrDict = load("res://Godot_Template/Class_ArrayAndOrDictionary.gd").new()

#Функционал:
#	Создание и вставка узла в сцену по конфигурации
#Форматы данных:
#	Входные:
#		X_NodeConfig_D: Dictionary —  {"__Data_D": {"__type_S": ,"__Scene_size_V2i": ,"__Path_to_the_node_location_S": },"__Inspector_D": {}, "__Node_D": {}}
#	Выходные:
#		Dictionary — {уникалноье_имя: {Node, Scene_size, Zero_point, Size}}
#Принцип работы:
#	1. Читает тип из __Data_D и создаёт узел
#	2. Применяет свойства из __Inspector_D
#	3. Подключает сигналы из __Node_D
#	4. Вставляет в указанный контейнер текущей сцены
#	5. Возвращает инфу о созданном узле
func fC_CreatingNode_1000(X_NodeConfig_D: Dictionary, A_BelongTo_A: Array) -> Dictionary:
	if vCC_ClassArrDict._vC_ActiveStreamId != "":
		Logger.fC_Adding_Buffer_Cr(vCC_ClassArrDict._vC_ActiveStreamId, "fC_CreatingNode_1000: start", [], null)

	# 0. Подготовка словарей
	var pLX_Data_D: Dictionary = X_NodeConfig_D.get("__Data_D", {})
	var pLX_Inspector_D: Dictionary = X_NodeConfig_D.get("__Inspector_D", {})
	var pLX_Signals_D: Dictionary = X_NodeConfig_D.get("__Node_D", {})

	# 1. Создание узла по типу
	if not pLX_Data_D.has("__type_S"):
		push_error("⛔ Не указан тип объекта (__type_S)")
		return {}

	var pLX_NodeType_S: String = pLX_Data_D["__type_S"]
	var pLX_NodeObj: Node
	
	if ClassDB.class_exists(pLX_NodeType_S):
		pLX_NodeObj = ClassDB.instantiate(pLX_NodeType_S)
	else:
		push_error("⛔ Несуществующий тип: %s" % pLX_NodeType_S)
		return {}

	# 2. Применение свойств из Inspector
	for key in pLX_Inspector_D:
		var value = pLX_Inspector_D[key]

		if typeof(value) != TYPE_DICTIONARY:
			pLX_NodeObj.set(key, value)
		else:
			var sub_obj = ClassDB.instantiate(value["type"])
			for sub_key in value:
				sub_obj.set(sub_key, value[sub_key])
			pLX_NodeObj.set(key, sub_obj)

	# 3. Подключение сигналов через Callable
	for pLX_SignalName_S: String in pLX_Signals_D.keys():
		var pLX_Callback: Callable = pLX_Signals_D[pLX_SignalName_S]
		if not pLX_Callback.is_valid():
			push_warning("⚠️ Callable недействителен для сигнала: %s" % pLX_SignalName_S)
			continue
		if pLX_NodeObj.has_signal(pLX_SignalName_S):
			pLX_NodeObj.connect(pLX_SignalName_S, pLX_Callback)
		else:
			push_warning("⚠️ Узел не имеет сигнала: %s" % pLX_SignalName_S)

	# 4. Поиск контейнера в текущей сцене
	if not pLX_Data_D.has("__Path_to_the_node_location_S"):
		push_error("⛔ Нет '__Path_to_the_node_location_S' в конфигурации")
		return {}

	var pLX_InsertPath: NodePath = pLX_Data_D["__Path_to_the_node_location_S"]
	
	# Проверка доступности дерева сцены
	var pLX_Tree: SceneTree = get_tree()
	if pLX_Tree == null:
		push_error("⛔ SceneTree не инициализирован")
		return {}
	
	# Получение корневой сцены
	var pLX_Root: Window = pLX_Tree.get_root()
	if pLX_Root == null:
		push_error("⛔ Корневое окно не найдено")
		return {}

	var pLX_CurrentScene: Node = pLX_Root.get_child(0)
	if pLX_CurrentScene == null:
		push_error("⛔ Активная сцена не найдена")
		return {}

	if not pLX_CurrentScene.has_node(pLX_InsertPath):
		push_error("⛔ Узел по пути '%s' не найден" % pLX_InsertPath)
		return {}

	var pLX_Container: Node = pLX_CurrentScene.get_node(pLX_InsertPath)
	pLX_Container.add_child(pLX_NodeObj)

	# 5. Возврат результата
	var pLX_NodeName_S: String = pLX_Inspector_D.get("name", "UnnamedNode")

	if vCC_ClassArrDict._vC_ActiveStreamId != "":
		Logger.fC_Adding_Buffer_Cr(vCC_ClassArrDict._vC_ActiveStreamId, "fC_CreatingNode_1000: node created and inserted", [pLX_NodeName_S, str(pLX_InsertPath)], null)
	return {
		pLX_NodeName_S: {
			"Node": pLX_NodeObj,
			"Scene_size": pLX_Data_D.get("__Scene_size_V2i", Vector2i.ZERO),
			"Zero_point": pLX_Data_D.get("__Zero_point", Vector2.ZERO),
			"name": pLX_Inspector_D.get("name", Vector2i.ZERO),
			"Size": pLX_Inspector_D.get("Size", Vector2i.ZERO),
			"A_BelongTo_A": A_BelongTo_A,
			"__Path_to_the_node_location_S": pLX_Data_D.get("__Path_to_the_node_location_S", Vector2.ZERO),
		}
	}


#Функционал:
#	Создаёт целое дерево нод по ВЛОЖЕННОМУ конфигу за один проход — каждый узел
#	описывается словарём с __Data_D/__Inspector_D/__Node_D, а его дети — это
#	просто дополнительные ключи В ТОМ ЖЕ словаре (см. changelog 2026-08-17)
#Форматы данных:
#	Входные:
#		vXD_NodeConfig: Dictionary — {ИмяНоды: {__Data_D:{...}, __Inspector_D:{...},
#			__Node_D:{...}, ИмяРебёнка: {... тот же формат, рекурсивно ...}, ...}, ...}
#			__Path_to_the_node_location_S и __Inspector_D.name указывать не нужно —
#			выставляются автоматически из структуры словаря
#		vXD_All_nodes: Dictionary — реестр, куда сохраняются все созданные ноды
#	Выходные:
#		Нет (vXD_All_nodes и сам vXD_NodeConfig изменяются на месте)
#Принцип работы:
#	Один проход vCC_ClassArrDict.UniversalBypass с f__MassCreateCallback — тот же
#	обход, что использует fC_SyncingNodesWithConfig_1111
func fC_MassCreatingNode_0001(vXD_NodeConfig: Dictionary, vXD_All_nodes: Dictionary) -> void:
	vCC_ClassArrDict.UniversalBypass(vXD_NodeConfig, {"func": f__MassCreateCallback, "Parametrs": [vXD_All_nodes, vXD_NodeConfig]})


#Функционал:
#	Идёт от корня дерева конфига по цепочке ключей vLA_PathArray и возвращает
#	словари всех ПРОМЕЖУТОЧНЫХ уровней — то есть без последнего ключа (сама
#	текущая нода в результат не входит, только всё, что было ДО неё). Общий
#	helper для _fC_RealNodePath_A и _fC_CollectBelongTo_A
#Форматы данных:
#	Входные:
#		vLD_Root: Dictionary — корень ВСЕГО дерева конфига (а не текущий уровень)
#		vLA_PathArray: Array — цепочка ключей от корня до текущего элемента
#	Выходные:
#		Array — словари каждого промежуточного уровня, по порядку от корня
func _fC_WalkAncestorLevels_A(vLD_Root: Dictionary, vLA_PathArray: Array) -> Array:
	var vLA_Levels_A: Array = []
	var vL_Current = vLD_Root
	for vLI_Step in range(vLA_PathArray.size() - 1):
		var vLS_Key = vLA_PathArray[vLI_Step]
		if typeof(vL_Current) != TYPE_DICTIONARY or not vL_Current.has(vLS_Key):
			break
		vL_Current = vL_Current[vLS_Key]
		vLA_Levels_A.append(vL_Current)
	return vLA_Levels_A


#Функционал:
#	Собирает РЕАЛЬНЫЙ путь до родителя ноды в дереве сцены Godot: из всех
#	промежуточных уровней (_fC_WalkAncestorLevels_A) оставляет только те ключи,
#	чьи словари сами являются нодами (_fC_IsNodeConfig) — то есть пропускает
#	любые обёртки для удобства группировки, как бы они ни назывались (раньше
#	это делала _fC_StripChildrenMarker_A, но только для буквального "__Children_D")
#Форматы данных:
#	Входные:
#		vLD_Root: Dictionary, vLA_PathArray: Array — как в _fC_WalkAncestorLevels_A
#	Выходные:
#		Array — цепочка имён реальных нод-предков, без обёрток
func _fC_RealNodePath_A(vLD_Root: Dictionary, vLA_PathArray: Array) -> Array:
	var vLA_RealPath_A: Array = []
	var vLA_Levels_A: Array = _fC_WalkAncestorLevels_A(vLD_Root, vLA_PathArray)
	for vLI_Step in range(vLA_Levels_A.size()):
		if typeof(vLA_Levels_A[vLI_Step]) == TYPE_DICTIONARY and _fC_IsNodeConfig(vLA_Levels_A[vLI_Step]):
			vLA_RealPath_A.append(vLA_PathArray[vLI_Step])
	return vLA_RealPath_A


#Функционал:
#	Собирает логическую цепочку "принадлежности" ноды (A_BelongTo_A) — значения
#	"v__Ebeveyn", встреченные на ВСЕХ промежуточных уровнях по пути от корня (см.
#	changelog 2026-08-18: раньше эту роль играл старый f__Checking_conditions).
#	Это НЕ путь в дереве сцены (его считает _fC_RealNodePath_A) — отдельная,
#	чисто логическая метка для массовых операций (fxC_MassDeletingNode_0010,
#	fC_ChangingNodesByKey_0011), которая может вообще не совпадать с реальной структурой
#Форматы данных:
#	Входные:
#		vLD_Root: Dictionary, vLA_PathArray: Array — как в _fC_WalkAncestorLevels_A
#	Выходные:
#		Array — значения "v__Ebeveyn", по порядку от корня, у кого он указан
func _fC_CollectBelongTo_A(vLD_Root: Dictionary, vLA_PathArray: Array) -> Array:
	var vLA_Tags_A: Array = []
	var vLA_Levels_A: Array = _fC_WalkAncestorLevels_A(vLD_Root, vLA_PathArray)
	for elLD_Level in vLA_Levels_A:
		if typeof(elLD_Level) == TYPE_DICTIONARY and elLD_Level.has("v__Ebeveyn"):
			vLA_Tags_A.append(elLD_Level["v__Ebeveyn"])
	return vLA_Tags_A


#Функционал:
#	Callback для UniversalBypass, вызываемый fC_MassCreatingNode_0001 — для
#	каждого ключа дерева решает: это нода (создать) или нет. Специального
#	ключа-маркера у обёрток больше нет (см. changelog 2026-08-18) — любой
#	Dictionary, который сам не является нодой, просто обходится глубже
func f__MassCreateCallback(InputArray: Array) -> String:
	var vXD_All_nodes: Dictionary = InputArray[0]
	var vXD_RootConfig: Dictionary = InputArray[1]
	var vLD_CurrentLevel: Dictionary = InputArray[3]
	var vLA_PathArray: Array = InputArray[4]
	var vL_Key = InputArray[5]

	if vL_Key == null:
		return "Further"
	if vL_Key == "__Data_D" or vL_Key == "__Inspector_D" or vL_Key == "__Node_D" or vL_Key == "v__Ebeveyn":
		return "Further"

	var vLD_Value = vLD_CurrentLevel[vL_Key]
	if typeof(vLD_Value) != TYPE_DICTIONARY:
		return "Further"

	if _fC_IsNodeConfig(vLD_Value):
		var vLA_RealPath_A: Array = _fC_RealNodePath_A(vXD_RootConfig, vLA_PathArray)
		var vLA_BelongTo_A: Array = _fC_CollectBelongTo_A(vXD_RootConfig, vLA_PathArray)
		var vLS_ParentPath_S: String = "." if vLA_RealPath_A.is_empty() else "/".join(vLA_RealPath_A)

		# Имя и путь до родителя берём из структуры словаря (реальные ноды-предки,
		# обёртки пропущены) — так по построению не может быть детей без
		# родителей. A_BelongTo_A — отдельная логическая метка из "v__Ebeveyn"
		# по всем уровням-обёрткам (см. _fC_CollectBelongTo_A), не путь Godot
		vLD_Value["__Inspector_D"]["name"] = vL_Key
		vLD_Value["__Data_D"]["__Path_to_the_node_location_S"] = vLS_ParentPath_S

		var vLD_Created: Dictionary = fC_CreatingNode_1000(vLD_Value, vLA_BelongTo_A)
		vXD_All_nodes.merge(vLD_Created)

	# Рекурсия внутрь ЭТОГО ЖЕ словаря — тут может найтись её обёртка с детьми
	return "Deeper"


#Функционал:
#	Переберает словарь и если ключь из массива ключей совпадает то вызыввает функцию передовай туда всю информацию
#Форматы данных:
#	Входные:
#		vXD_All_nodes: Dictionary, vXA_Array_key: [key1, key2,...], vLS_func: Callable, vLD_func_variable: Dictionary
#	Выходные:
#		Нет
#Принцип работы:
#	Как именно функция достигает результата, какие шаги предпринимает
func fC_ChangingNodesByKey_0011 (vXD_All_nodes: Dictionary, vXA_Array_key: Array, vLS_func: Callable, vLD_func_variable: Dictionary):
	var vL_Array_Del := []
	var v__Result
	
	for vL_An in vXD_All_nodes:
		for vL_Ak in vXA_Array_key:
			if vXD_All_nodes [vL_An] ["A_BelongTo_A"].has (vL_Ak):
				v__Result = vLS_func.call(vXD_All_nodes, vL_An, vL_Ak, vL_Array_Del, vLD_func_variable)
				if v__Result [0] == false:
					break
		if v__Result [1] == false:
			break
	
	for vL_Ad in vL_Array_Del:
		vXD_All_nodes.erase(vL_Ad)


#Функционал:
#	Генерация набора конфигураций по шаблону с вариативной частью
#Форматы данных:
#	Входные:
#		vD_BaseTemplate: Dictionary — общая часть
#		vD_DiffTemplate: Dictionary — часть, где есть %N (индекс)
#		vI_Count: Int — сколько копий делать
#Выходные:
#		Dictionary с уникальными узлами
#Принцип работы:
#	Создает N копий с заменой %N на индекс
func fxG_BatchFillingNodeConfig_1000(vD_BaseTemplate: Dictionary, vD_DiffTemplate: Dictionary, vI_Count: int) -> Dictionary:
	var vD_Result: Dictionary = {}

	for vI_N in range(vI_Count):
		var vD_Clone := vD_BaseTemplate.duplicate(true)
		var vS_Name = vD_DiffTemplate.get("__name_S", "Node%N").replace("%N", str(vI_N + 1))

		# Вставляем имя
		vD_Clone["__Inspector_D"]["name"] = vS_Name

		# Заменяем другие поля, если указаны
		for k in vD_DiffTemplate:
			if k == "__name_S":
				continue
			var val = vD_DiffTemplate[k]
			if typeof(val) == TYPE_STRING:
				val = val.replace("%N", str(vI_N + 1))
			vD_Clone["__Inspector_D"][k] = val

		# Сохраняем под уникальным ключом
		vD_Result[vS_Name] = vD_Clone
	
	return vD_Result


#Функционал:
#	Изменяет свойства существующих нод
func fxC_UpdatingExistingNodes_0100(vXD_All_nodes: Dictionary, vD_Changes: Dictionary):
	for name in vD_Changes:
		if not vXD_All_nodes.has(name):
			if vCC_ClassArrDict._vC_ActiveStreamId != "":
				Logger.fC_Adding_Buffer_Cr(vCC_ClassArrDict._vC_ActiveStreamId, "fxC_UpdatingExistingNodes_0100: node not found", [name], "push_warning")
			push_warning("⚠️ Нода %s не найдена для обновления." % name)
			continue
		var node = vXD_All_nodes[name]["Node"]
		for property in vD_Changes[name]:
			if property in node:
				node.set(property, vD_Changes[name][property])
				if vCC_ClassArrDict._vC_ActiveStreamId != "":
					Logger.fC_Adding_Buffer_Cr(vCC_ClassArrDict._vC_ActiveStreamId, "fxC_UpdatingExistingNodes_0100: property updated", [name, property, vD_Changes[name][property]], null)
			else:
				if vCC_ClassArrDict._vC_ActiveStreamId != "":
					Logger.fC_Adding_Buffer_Cr(vCC_ClassArrDict._vC_ActiveStreamId, "fxC_UpdatingExistingNodes_0100: property not found on node", [name, property], "push_warning")
				push_warning("⚠️ Свойство %s не найдено у ноды %s." % [property, name])


#Функционал:
#	Проверяет, является ли словарь конфигурацией ноды (а не промежуточной "зоной"/группой)
func _fC_IsNodeConfig(vLD_Candidate: Dictionary) -> bool:
	return vLD_Candidate.has("__Data_D") and vLD_Candidate.has("__Inspector_D") and vLD_Candidate.has("__Node_D")


#Функционал:
#	Читает значение по пути ключей, не падая, если пути не существует (в отличие от PassageAlongWay)
#Форматы данных:
#	Входные:
#		vLD_Root: Dictionary — корень, откуда начинаем
#		vLA_Path: Array — последовательность ключей
#	Выходные:
#		Variant — найденное значение, или null, если путь не существует
func _fC_SafeGetByPath(vLD_Root: Dictionary, vLA_Path: Array):
	var vL_Current = vLD_Root
	for vLS_Step in vLA_Path:
		if typeof(vL_Current) != TYPE_DICTIONARY or not vL_Current.has(vLS_Step):
			return null
		vL_Current = vL_Current[vLS_Step]
	return vL_Current


#Функционал:
#	Сверяет старый и новый конфиг нод (рекурсивно, через fC_ComparisonsOf2Variables_0101) и сама
#	вызывает создание/пересоздание/точечное обновление/удаление нод — см. changelog в начале файла
#Форматы данных:
#	Входные:
#		vXD_All_nodes: Dictionary — текущий реестр созданных нод (изменяется на месте)
#		vXD_OldConfig: Dictionary — конфиг, который действовал раньше
#		vXD_NewConfig: Dictionary — конфиг, который должен действовать теперь
#	Выходные:
#		Dictionary — копия vXD_NewConfig (новый "старый" конфиг для следующего вызова)
#Принцип работы:
#	1. Проход по новому конфигу (UniversalBypass) — создаёт отсутствовавшие ноды, точечно
#	   обновляет/пересоздаёт изменившиеся
#	2. Проход по старому конфигу (UniversalBypass) — удаляет ноды, которых больше нет в новом
#	Обход — vCC_ClassArrDict.UniversalBypass; логи — в vCC_ClassArrDict.Class_Logger, см. changelog
func fC_SyncingNodesWithConfig_1111(vXD_All_nodes: Dictionary, vXD_OldConfig: Dictionary, vXD_NewConfig: Dictionary) -> Dictionary:
	var vLS_StreamId: String = Logger.fC_RegisterStream_Cr("UI:Sync")
	vCC_ClassArrDict._vC_ActiveStreamId = vLS_StreamId

	Logger.fC_Adding_Buffer_Cr(vLS_StreamId, "fC_SyncingNodesWithConfig_1111: start, pass 1 (create/update)", [], null)
	vCC_ClassArrDict.UniversalBypass(vXD_NewConfig, {"func": f__SyncCallback_CreateOrUpdate, "Parametrs": [vXD_All_nodes, vXD_OldConfig, vXD_NewConfig]})

	Logger.fC_Adding_Buffer_Cr(vLS_StreamId, "fC_SyncingNodesWithConfig_1111: pass 2 (delete)", [], null)
	vCC_ClassArrDict.UniversalBypass(vXD_OldConfig, {"func": f__SyncCallback_Delete, "Parametrs": [vXD_All_nodes, vXD_NewConfig]})

	Logger.fC_Adding_Buffer_Cr(vLS_StreamId, "fC_SyncingNodesWithConfig_1111: done", [], null)
	Logger.fC_FinishStream_Ch(vLS_StreamId)
	vCC_ClassArrDict._vC_ActiveStreamId = ""

	return vXD_NewConfig.duplicate(true)


#Функционал:
#	Callback для UniversalBypass (проход 1, по новому конфигу): создаёт новые ноды,
#	сверяет и точечно обновляет/пересоздаёт уже существующие
func f__SyncCallback_CreateOrUpdate(InputArray: Array) -> String:
	var vXD_All_nodes: Dictionary = InputArray[0]
	var vXD_OldConfig: Dictionary = InputArray[1]
	var vXD_NewConfig: Dictionary = InputArray[2]
	var vLD_CurrentLevel: Dictionary = InputArray[4]
	var vLA_PathArray: Array = InputArray[5]
	var vL_Key = InputArray[6]

	if vL_Key == null:
		return "Further"
	if vL_Key == "__Data_D" or vL_Key == "__Inspector_D" or vL_Key == "__Node_D" or vL_Key == "v__Ebeveyn":
		return "Further"

	var vLD_NewVal = vLD_CurrentLevel[vL_Key]
	if typeof(vLD_NewVal) != TYPE_DICTIONARY:
		return "Further"

	if _fC_IsNodeConfig(vLD_NewVal):
		var vLA_RealPath_A: Array = _fC_RealNodePath_A(vXD_NewConfig, vLA_PathArray)
		var vLA_BelongTo_A: Array = _fC_CollectBelongTo_A(vXD_NewConfig, vLA_PathArray)
		var vLS_ParentPath_S: String = "." if vLA_RealPath_A.is_empty() else "/".join(vLA_RealPath_A)

		# Тот же принцип, что и в f__MassCreateCallback: имя/путь — из реальной
		# структуры (обёртки пропущены), A_BelongTo_A — из "v__Ebeveyn" (см. changelog)
		vLD_NewVal["__Inspector_D"]["name"] = vL_Key
		vLD_NewVal["__Data_D"]["__Path_to_the_node_location_S"] = vLS_ParentPath_S

		# Старый конфиг адресуем ТЕМ ЖЕ vLA_PathArray — у old и new одна и та же
		# вложенность (какими бы ни были имена обёрток), путь совпадает буквально
		var vLD_OldVal = _fC_SafeGetByPath(vXD_OldConfig, vLA_PathArray)
		if typeof(vLD_OldVal) != TYPE_DICTIONARY or not _fC_IsNodeConfig(vLD_OldVal):
			if vCC_ClassArrDict._vC_ActiveStreamId != "":
				Logger.fC_Adding_Buffer_Cr(vCC_ClassArrDict._vC_ActiveStreamId, "f__SyncCallback_CreateOrUpdate: new node, creating", [vLA_PathArray.duplicate()], null)
			var vLD_Created = fC_CreatingNode_1000(vLD_NewVal, vLA_BelongTo_A)
			vXD_All_nodes.merge(vLD_Created)
		else:
			if vCC_ClassArrDict._vC_ActiveStreamId != "":
				Logger.fC_Adding_Buffer_Cr(vCC_ClassArrDict._vC_ActiveStreamId, "f__SyncCallback_CreateOrUpdate: existing node, comparing", [vLA_PathArray.duplicate()], null)
			_fC_SyncExistingNode(vXD_All_nodes, vLD_OldVal, vLD_NewVal, vLA_BelongTo_A)

	# Рекурсия внутрь ЭТОГО ЖЕ словаря — тут может найтись её обёртка с детьми
	return "Deeper"


#Функционал:
#	Callback для UniversalBypass (проход 2, по старому конфигу): удаляет ноды, которых
#	больше нет в новом конфиге
func f__SyncCallback_Delete(InputArray: Array) -> String:
	var vXD_All_nodes: Dictionary = InputArray[0]
	var vXD_NewConfig: Dictionary = InputArray[1]
	var vLD_CurrentLevel: Dictionary = InputArray[3]
	var vLA_PathArray: Array = InputArray[4]
	var vL_Key = InputArray[5]

	if vL_Key == null:
		return "Further"
	if vL_Key == "__Data_D" or vL_Key == "__Inspector_D" or vL_Key == "__Node_D" or vL_Key == "v__Ebeveyn":
		return "Further"

	var vLD_OldVal = vLD_CurrentLevel[vL_Key]
	if typeof(vLD_OldVal) != TYPE_DICTIONARY:
		return "Further"

	if _fC_IsNodeConfig(vLD_OldVal):
		var vLD_NewVal = _fC_SafeGetByPath(vXD_NewConfig, vLA_PathArray)
		if typeof(vLD_NewVal) != TYPE_DICTIONARY or not _fC_IsNodeConfig(vLD_NewVal):
			if vCC_ClassArrDict._vC_ActiveStreamId != "":
				Logger.fC_Adding_Buffer_Cr(vCC_ClassArrDict._vC_ActiveStreamId, "f__SyncCallback_Delete: node removed from config, deleting", [vLA_PathArray.duplicate()], null)
			_fC_DeleteNodeByConfigKey(vXD_All_nodes, vLD_OldVal)
			# Дальше НЕ "return Further" — идём "Deeper" и по бывшим детям тоже,
			# чтобы вычистить их из vXD_All_nodes (сами Godot-ноды каскадно
			# уже уничтожены через queue_free() выше — _fC_DeleteNodeByConfigKey
			# проверяет is_instance_valid и не пытается освободить их повторно)

	return "Deeper"


#Функционал:
#	Сравнивает старую и новую конфигурацию одной ноды через fC_ComparisonsOf2Variables_0101
#	и решает: ничего не делать / точечно обновить (.set через fxC_UpdatingExistingNodes_0100) /
#	пересоздать (queue_free + fC_CreatingNode_1000) — см. changelog про гибридную стратегию
func _fC_SyncExistingNode(vXD_All_nodes: Dictionary, vLD_OldNodeConfig: Dictionary, vLD_NewNodeConfig: Dictionary, A_BelongTo_A: Array):
	var vLD_Diff: Dictionary = {}
	vCC_ClassArrDict.fC_ComparisonsOf2Variables_0101(vLD_OldNodeConfig, vLD_NewNodeConfig, vLD_Diff)

	if String(vLD_Diff.get("result", "")).begins_with("+"):
		# Полное совпадение — менять нечего
		return

	var vLB_NeedsRecreate: bool = false
	if vLD_Diff.has("Child"):
		for vLS_TopKey in ["__Data_D", "__Node_D"]:
			if vLD_Diff["Child"].has(vLS_TopKey):
				var vLS_ChildResult: String = String(vLD_Diff["Child"][vLS_TopKey].get("result", ""))
				if not vLS_ChildResult.begins_with("+"):
					vLB_NeedsRecreate = true
					break

	var vLS_OldName: String = vLD_OldNodeConfig.get("__Inspector_D", {}).get("name", "")

	if vLB_NeedsRecreate:
		if vCC_ClassArrDict._vC_ActiveStreamId != "":
			Logger.fC_Adding_Buffer_Cr(vCC_ClassArrDict._vC_ActiveStreamId, "_fC_SyncExistingNode: __Data_D/__Node_D changed, recreating", [vLS_OldName], null)
		if vXD_All_nodes.has(vLS_OldName):
			vXD_All_nodes[vLS_OldName]["Node"].queue_free()
			vXD_All_nodes.erase(vLS_OldName)
		else:
			push_warning("⚠️ Нода %s не найдена в реестре для пересоздания." % vLS_OldName)
		var vLD_Created = fC_CreatingNode_1000(vLD_NewNodeConfig, A_BelongTo_A)
		vXD_All_nodes.merge(vLD_Created)
		return

	# Только __Inspector_D мог измениться — точечное обновление через .set()
	if not vLD_Diff.has("Child") or not vLD_Diff["Child"].has("__Inspector_D"):
		return
	var vLD_InspectorDiff: Dictionary = vLD_Diff["Child"]["__Inspector_D"]
	if not vLD_InspectorDiff.has("Child"):
		return

	var vLD_ChangedProps: Dictionary = {}
	var vLX_NewInspector: Dictionary = vLD_NewNodeConfig.get("__Inspector_D", {})
	for vLS_PropKey in vLD_InspectorDiff["Child"]:
		var vLS_PropResult: String = String(vLD_InspectorDiff["Child"][vLS_PropKey].get("result", ""))
		if vLS_PropResult.begins_with("+"):
			continue
		if not vLX_NewInspector.has(vLS_PropKey):
			# Свойство убрано из нового конфига — .set() нечего применять, пропускаем
			continue
		vLD_ChangedProps[vLS_PropKey] = vLX_NewInspector[vLS_PropKey]

	if vLD_ChangedProps.is_empty():
		return

	if vCC_ClassArrDict._vC_ActiveStreamId != "":
		Logger.fC_Adding_Buffer_Cr(vCC_ClassArrDict._vC_ActiveStreamId, "_fC_SyncExistingNode: only __Inspector_D changed, point-updating", [vLS_OldName, vLD_ChangedProps], null)
	fxC_UpdatingExistingNodes_0100(vXD_All_nodes, {vLS_OldName: vLD_ChangedProps})


#Функционал:
#	Удаляет ноду из vXD_All_nodes по её конфигу (ищет по __Inspector_D.name).
#	Проверяет is_instance_valid — эту же функцию f__SyncCallback_Delete вызывает
#	повторно для БЫВШИХ детей уже удалённого родителя (queue_free каскадно
#	уничтожил их на уровне Godot), здесь только чистим реестр, не падаем на double-free
func _fC_DeleteNodeByConfigKey(vXD_All_nodes: Dictionary, vLD_OldNodeConfig: Dictionary):
	var vLS_Name: String = vLD_OldNodeConfig.get("__Inspector_D", {}).get("name", "")
	if vXD_All_nodes.has(vLS_Name):
		var vL_Node = vXD_All_nodes[vLS_Name]["Node"]
		if is_instance_valid(vL_Node):
			vL_Node.queue_free()
		vXD_All_nodes.erase(vLS_Name)
	else:
		if vCC_ClassArrDict._vC_ActiveStreamId != "":
			Logger.fC_Adding_Buffer_Cr(vCC_ClassArrDict._vC_ActiveStreamId, "_fC_DeleteNodeByConfigKey: node not found in registry", [vLS_Name], "push_warning")
		push_warning("⚠️ Нода %s не найдена в реестре для удаления." % vLS_Name)


#Функционал:
#	Выполнить смену сцены с любого места
func fxC_SwitchingScene_0000 (scene_path):
	get_tree().call_deferred("change_scene_to_file", scene_path)


#Функционал:
#Удаляет ноды по условию
func fxC_MassDeletingNode_0010(MassOfExistingNodes: Dictionary, RemovalCondition: Callable) -> void:
	# Массив для удаления
	var v_DeletionQueue_A: Array = []

	for elMOFN in MassOfExistingNodes:
		# Перебор тегов для проверки
		for elMOFNABA in MassOfExistingNodes[elMOFN]["A_BelongTo_A"]:
			# Проверяем условие с помощью переданной функции
			if RemovalCondition.call(elMOFNABA, MassOfExistingNodes[elMOFN]):
				MassOfExistingNodes[elMOFN]["Node"].queue_free()
				v_DeletionQueue_A.append(elMOFN)
				break # можно прервать, чтобы не удалять дважды

	# Удаляем отмеченные элементы
	for elDQ in v_DeletionQueue_A:
		MassOfExistingNodes.erase(elDQ) 


func fxC_ZoneReplacement(Coordinates: Dictionary, Zones: String, MewZones: Dictionary):
	for el_Z in Coordinates [Zones]:
		el_Z["Node"].queue_free()
	Coordinates [Zones].erase()
	Coordinates [MewZones]


#func fxC_StatusOperator(Zones, Status, ):
#	fxC_ZoneReplacement(Zones, )
