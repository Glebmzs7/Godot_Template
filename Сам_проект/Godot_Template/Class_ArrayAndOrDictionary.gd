##Версия оформления
##2025-06-20 - mzs7 - начальная реализация
##2026-03-28 - mzs7 - обновление комментариев по стандартам
##0.2.0.1 - обновление комментариев
##2026-03-28 - mzs7 - обновление комментариев по стандартам
##2026-08-09 - mzs7 - встроен Class_Logger по всей цепочке вызовов, exercised из
##	Scenes/test/test.gd (fC_ComparisonsOf2Variables_0101 -> UniversalBypass ->
##	_C_ComparisonsOf2Variables_0101 -> PassageAlongWay/_PAW_CO2V
##	-> Class_Help.FunctionCall). Логирование включается ТОЛЬКО если вызывающий код явно
##	выставил _vC_ActiveStreamId (см. test.gd) — без этого все вызовы логгера внутри этого
##	файла no-op, чтобы не портить test_performance()
##2026-08-13 - mzs7 - CheckingPath/PathArray-подход к пересчёту агрегированного result убран
##	(падал: пытался применить "Child" к листовому узлу без потомков, т.к. ему передавали не
##	корень дерева, а локальный узел текущей глубины рекурсии). Вместо него — RecalculateResultsRecursive,
##	отдельный проход по уже построенному дереву снизу вверх, вызывается один раз после UniversalBypass
##2026-08-13 - mzs7 - _C_ComparisonsOf2Variables_0101 разделена на 3 явных случая по ключу
##	(InputArray[5]): "Child" -> просто "Deeper" без пересчёта; "result"/"Values" -> "Further";
##	любой другой ключ -> настоящее сравнение. Раньше единое условие "не result и не Values"
##	пропускало и "Child" тоже — а "Child" сам порождал новый "Child" при каждом заходе (потому
##	что _PAW_CO2V всегда пропускает "Child"-токены пути, поэтому originalVariables1/2 никогда
##	не сдвигались с места) — это была бесконечная рекурсия, см. лог value_diff 1.5МБ вместо ~8КБ
##2026-08-14 - mzs7 - добавлен суффикс KM ("keys match") к result: если сравнение произошло
##	между значениями, присутствующими В ОБЕИХ структурах (т.е. это не ">"/"<" — ключ был
##	только у одной стороны), к символу результата добавляется "KM" ("+KM","-KM","~KM",
##	"~-KM" и т.д.). Проставляется в 6 местах прямого сравнения (fC_ComparisonsOf2Variables_0101
##	и _C_ComparisonsOf2Variables_0101 — везде, кроме установки "-в-a"/"-в-b") и в _CP_CO2V
##	при агрегации — там KM добавляется, только если среди потомков был хотя бы один с
##	совпавшим ключом (Bv_HasMatchedKeyChild), иначе узел, схлопнувшийся из чистых ">"/"<"
##	(полностью непересекающиеся ключи), KM не получает
##2026-08-14 - mzs7 - (отменено тем же днём, см. следующую запись) кратко убирались ВСЕ
##	"if _vC_ActiveStreamId != '':" гейты + снижался Class_Logger.FrequencyUpdates до 1, чтобы
##	поймать логом "Программа вылетела" на test_performance(). Эффект оказался хуже причины:
##	лог за один прогон вырос до 49МБ, а Class_Logger.fC_Saving_Logs_Ch перечитывает и
##	перезаписывает файл лога ЦЕЛИКОМ при каждом сбросе — вот это (O(n²) дисковый I/O), а не
##	сама логика сравнения, и создавало ощущение зависшей/упавшей программы
##2026-08-14 - mzs7 - НАЙДЕН И ПОЧИНЕН настоящий баг (см. полный текст ошибки и стек в чате:
##	"Invalid access to property or key 'k_2_2'"): в UniversalBypass, в ветке match "Deeper"
##	для итерируемого элемента, не хватало PathArray.pop_back() после рекурсивного
##	UniversalBypass(...) — единственная из 4 веток match, которая не снимала elV,
##	добавленный перед match через PathArray.append(elV). Пока в словаре/массиве на каждом
##	уровне ровно 1 ключ (как во всех test_full_correctness()) — незаметно, "грязный хвост"
##	всегда последний и никто его не читает. А в test_performance()/_generate_big_dict, где
##	на каждом уровне по 4 ключа, и не последний уходит в Deeper — PathArray накапливал
##	мусорные сегменты от уже обработанных чужих поддеревьев, переставал быть валидным путём,
##	и PassageAlongWay в какой-то момент пытался зайти по несуществующему ключу вроде "k_2_2".
##	Как следствие этой находки: "if _vC_ActiveStreamId != '':" гейты (все 28) возвращены на
##	место, Class_Logger.FrequencyUpdates возвращён на 10 (см. Class_Logger.gd) — были нужны
##	только для отладки, сама причина крашей была не в логировании. Depth-лимит в
##	UniversalBypass (параметр Depth, 40) оставлен как дешёвая защита на будущее
##2026-08-14 - mzs7 - убраны 2 голых print() в PassageAlongWay ("Good/Not flagPassageAlongWay").
##	В отличие от остального debug-вывода в файле, они НЕ были завязаны на
##	"if _vC_ActiveStreamId != '':" и печатали безусловно на КАЖДОМ шаге PathArray — а
##	PassageAlongWay с колбэком вызывается дважды на каждый узел дерева сравнения (см.
##	_C_ComparisonsOf2Variables_0101, строки ~612-613). На depth=4/width=4 из test_performance()
##	(1000 итераций) это давало десятки тысяч сообщений в консоль редактора — именно это
##	увидел mzs7 (43.5 тыс. сообщений). Сама логика через Class_Logger.fC_Adding_Buffer_Cr
##	(гейтованная, как и везде) оставлена без изменений
extends Node
class_name Class_ArrayAndOrDictionary

var Class_Help = load("res://Godot_Template/Class_Help.gd").new()
## Собственный логгер этого класса — все функции ниже, участвующие в графе вызовов
## fC_ComparisonsOf2Variables_0101, пишут именно сюда (см. _vC_ActiveStreamId)

## Id потока, в который сейчас нужно логировать (пустая строка = логирование выключено).
## Выставляется СНАРУЖИ (например, test.gd) перед вызовом fC_ComparisonsOf2Variables_0101 —
## сам этот класс поток не регистрирует и не завершает, чтобы оставаться пригодным
## и для вызовов без логирования (например, из test_performance(), где 1000 вызовов
## подряд не должны создавать 1000 потоков)
var _vC_ActiveStreamId: String = ""

##Функционал:
##	Сравнивает два массива на полное совпадение (порядок и значение элементов)
##Форматы данных:
##	Входные:
##		array1: Array - первый массив для сравнения
##		array2: Array - второй массив для сравнения
##	Выходные:
##		bool - true если массивы идентичны, иначе false
##Принцип работы:
##	1. Проверка совпадения длины массивов
##	2. Поэлементное сравнение через оператор ==
##	3. Немедленный возврат false при обнаружении расхождения
func fL_CompareArrays_Tr(array1: Array, array2: Array) -> bool:
	## Длина должна совпадать
	if array1.size() != array2.size():
		return false

	## Поэлементное сравнение
	for i in range(array1.size()):
		if array1[i] != array2[i]:
			return false

	return true



##Функционал:
##	Сравнивает два массива на идентичность элементов без учета их порядка
##Форматы данных:
##	Входные:
##		array1: Array - первый массив для сравнения
##		array2: Array - второй массив для сравнения
##	Выходные:
##		bool - true если массивы содержат одинаковые элементы (количество и тип), иначе false
##Принцип работы:
##	1. Проверка равенства длин массивов
##	2. Подсчет частоты встречаемости элементов в первом массиве
##	3. Сравнение с частотой элементов во втором массиве
##	4. Возврат false при любом несоответствии
func fL_CompareArraysUnordered_Tr(array1: Array, array2: Array) -> bool:
	## Быстрая проверка длины
	if array1.size() != array2.size():
		return false

	## Создание словаря для подсчета элементов
	var element_count := {}

	## Подсчет элементов в первом массиве
	for element in array1:
		if element_count.has(element):
			element_count[element] += 1
		else:
			element_count[element] = 1

	## Проверка элементов второго массива
	for element in array2:
		if not element_count.has(element):
			return false  ## Элемент отсутствует в первом массиве

		element_count[element] -= 1
		if element_count[element] < 0:
			return false  ## Элемент встречается чаще, чем в первом массиве

	return true

##Функционал:
##	Callback-функция для слияния значений из второго словаря в первый
##Форматы данных:
##	Входные:
##		vLS_Key: String — текущий ключ
##		v_: Variant — текущее значение
##		vLD_External: Dictionary — {
##			"Target_D": Dictionary (куда пишем),
##			"Source_D": Dictionary (откуда берём)
##		}
##	Выходные:
##		Array:
##			[ [Bv_Continue, Bv_ContinueFor, Bv_GoDeeper], v_ChildValue ]
##Принцип работы:
##	1. Если значение — словарь и есть соответствие в обоих — рекурсивно
##	2. Иначе: перезаписываем/добавляем значение из второго словаря в первый
func fxL_MergeCallback_Tr(vLS_Key: String, v_, vLD_External: Dictionary) -> Array:
	var vLD_Target = vLD_External["Target_D"]
	var vLD_Source = vLD_External["Source_D"]

	## Если в Source есть этот ключ
	if vLD_Source.has(vLS_Key):
		var v_ValueFromSecond = vLD_Source[vLS_Key]

		## Если оба значения — словари, объединяем глубже
		if typeof(v_) == TYPE_DICTIONARY and typeof(v_ValueFromSecond) == TYPE_DICTIONARY:
			var new_sub_dict = v_.duplicate()
			vLD_Target[vLS_Key] = new_sub_dict  ## вставляем временно
			return [
				[true, true, true],  ## продолжать, цикл, рекурсивно
				v_ValueFromSecond  ## это будет следующая структура обхода
			]
		else:
			## Прямое копирование/перезапись
			vLD_Target[vLS_Key] = v_ValueFromSecond

	## В любом случае: не нужно углубляться
	return [[true, true, false], null]


##Функционал:
##	Рекурсивное объединение двух словарей с приоритетом второго словаря
##Форматы данных:
##	Входные:
##		@param Dict1: Dictionary - базовый словарь
##		@param Dict2: Dictionary - словарь с приоритетными значениями
##	Выходные:
##		@returns Dictionary - объединенный словарь
##Принцип работы:
##	1. Создает глубокую копию Dict1
##	2. Для каждого ключа в Dict2:
##		- Если ключ существует в основном словаре:
##			* Если оба значения - словари, выполняется рекурсивное слияние
##			* Иначе значение заменяется на значение из Dict2
##		- Если ключа нет, он добавляется из Dict2
##	3. Возвращает результирующий словарь
func fG_MergeDictionariesRecursive_Cr(Dict1: Dictionary, Dict2: Dictionary) -> Dictionary:
	var result := Dict1.duplicate(true)

	for key in Dict2:
		if result.has(key):
			## Если оба значения - словари, рекурсивно объединяем их
			if typeof(result[key]) == TYPE_DICTIONARY and typeof(Dict2[key]) == TYPE_DICTIONARY:
				result[key] = fG_MergeDictionariesRecursive_Cr(result[key], Dict2[key])
			else:
				## Если не оба словари, перезаписываем значением из Dict2
				result[key] = Dict2[key]
		else:
			## Если ключа нет в result, просто добавляем его
			result[key] = Dict2[key]

	return result


##Функционал:
##	Рекурсивный обход словаря с применением callback-функции
##	и управлением процессом через возвращаемые флаги
##Форматы данных:
##	Входные:
##		vLD_FirstVariable: Dictionary - словарь для обработки
##		vLS_func: Callable - callback-функция обработки
##		vLD_func_variable: Dictionary - дополнительные данные
##	Выходные:
##		нет
##Принцип работы:
##	1. Инициализация флага глобального продолжения
##	2. Рекурсивный обход элементов словаря
##	3. Вызов callback-функции для каждого элемента
##	4. Обработка возвращаемых флагов управления
##	5. Рекурсивный вызов при необходимости углубления
##Примечание:
##	Не входит в цепочку вызовов из test.gd (её использует UniversalBypass, а не эта функция) —
##	логгер сюда не добавлялся, оставлено как было
func fC_OvergrowthIf_Tr (vLD_FirstVariable: Dictionary, vLS_func: Dictionary, PathArray:= []) -> void:
	## Флаг продолжения глобального обхода
	var vLBv_GlobalContinue := true

	## Создаем копию словаря параметров, чтобы не изменять оригинальный
	var vLS_func_copy = vLS_func.duplicate()

	## Перебор ключей словаря
	for vLS_Key in vLD_FirstVariable:
		## Проверка флага глобального продолжения
		if not vLBv_GlobalContinue:
			break
		## Вызов callback-функции с параметрами:
		##	- ключ элемента
		##	- значение элемента
		##	- дополнительные данные
		PathArray.append(vLS_Key)
		if not Class_Help.ITERABLE_TYPES_MAP.has(typeof(vLS_func_copy["Parametrs"])):
			vLS_func_copy["Parametrs"] = []
		var v__Result = Class_Help.FunctionCall(vLS_func_copy, PathArray)

		## Декомпозиция результата callback:
		var v_Bv_Continue = v__Result[0][0]		## Продолжать глобальный обход?
		var v_Bv_ContinueFor = v__Result[0][1]	## Продолжать текущий цикл?
		var v_Bv_GoDeeper = v__Result[0][2]		## Идти вглубь структуры?

		## Управление флагами на основе результата
		if not v_Bv_Continue:
			vLBv_GlobalContinue = false
		if not v_Bv_ContinueFor:
			PathArray.pop_back()
			break
		if v_Bv_GoDeeper:
			##N Рекурсивный вызов для вложенных данных
			fC_OvergrowthIf_Tr(v__Result[1], vLS_func_copy, PathArray)
		PathArray.pop_back()


## Обход любой структуры данных (массивы, словари и т.д.)
##
## @param variables: Структура данных для обхода
## @param funcparametrs: Параметры функции обратного вызова
## @param PathArray: Массив путей к элементам (по умолчанию пустой)
##
## КАК ПОЛЬЗОВАТЬСЯ (программисту, для логирования):
##	Ничего специально передавать не нужно — функция сама читает _vC_ActiveStreamId
##	этого же объекта (Class_ArrayAndOrDictionary). Если вызывающий код выставил
##	_vC_ActiveStreamId перед вызовом fC_ComparisonsOf2Variables_0101 — сюда, в match,
##	автоматически попадут записи по каждой ветке ("Deeper"/"Further"/"Higher"/ошибка)
##
## 2026-08-14: добавлен Depth (по умолчанию 0, растёт на 1 на каждый "Deeper"-рекурсивный
## вызов). Защита от аварийного завершения программы (см. чат — "Программа вылетела" на
## test_performance со случайными данными): вместо ухода в неограниченную рекурсию (которая
## рушит процесс через stack overflow ДО того, как логгер успеет что-либо сохранить на диск)
## функция логирует превышение и корректно останавливается сама, оставляя в логе точное
## место и PathArray, где предел был достигнут
func UniversalBypass (variables, funcparametrs: Dictionary, PathArray:= [], Depth: int = 0):
	if Depth > 40:
		if _vC_ActiveStreamId != "":
			Logger.fC_Adding_Buffer_Cr(_vC_ActiveStreamId, "UniversalBypass: Depth limit exceeded — aborting to avoid stack overflow", [Depth, PathArray.duplicate()], "push_error")
		push_error("⛔ UniversalBypass: превышена глубина рекурсии (", Depth, ") на PathArray=", PathArray, " — прерываю обход, см. лог")
		return
	var variables1 = variables
	var type_id = typeof(variables)
	# Не нашел где =нужен был duplicate а вот данные оставались в копии
	#if type_id in Class_Help.ITERABLE_TYPES:
	#	variables1duplicate = variables.duplicate(true)
	var returnfunc1
	var keys = Class_Help.get_iter_keys(variables1)
	if keys == null:
		# if: обходить нечего (variables1 не итерируемый контейнер) — вызываем callback один раз
		# на весь объект целиком (elV=null сигналит callback-у "это не элемент коллекции")
		if _vC_ActiveStreamId != "":
			Logger.fC_Adding_Buffer_Cr(_vC_ActiveStreamId, "UniversalBypass: keys == null, single call", [Class_Help.TYPE_NAMES.get(type_id, str(type_id))], null)
		returnfunc1 = Class_Help.FunctionCall(funcparametrs, [type_id, variables1, PathArray, null], Class_Logger, _vC_ActiveStreamId)
	else:
		# for: обходим все ключи/индексы контейнера по очереди
		for elV in keys:
			var element = variables1[elV]
			PathArray.append(elV)
			if _vC_ActiveStreamId != "":
				Logger.fC_Adding_Buffer_Cr(_vC_ActiveStreamId, "UniversalBypass: visiting key", [elV, PathArray.duplicate()], null)
			returnfunc1 = Class_Help.FunctionCall(funcparametrs, [type_id , variables1, PathArray, elV], Class_Logger, _vC_ActiveStreamId)
			match returnfunc1:
				"Deeper":
					# if: элемент сам по себе — контейнер, обходим его рекурсивно
					if typeof (variables1[elV]) in Class_Help.ITERABLE_TYPES_MAP:
						if _vC_ActiveStreamId != "":
							Logger.fC_Adding_Buffer_Cr(_vC_ActiveStreamId, "UniversalBypass: Deeper, recursing", [elV, Depth+1], null)
						UniversalBypass(variables1[elV], funcparametrs, PathArray, Depth + 1)
						#2026-08-14: КРИТИЧНЫЙ ФИКС — здесь не хватало pop_back(). Все остальные
						#ветки match (Further/Higher/Deeper-не-итерируемый) корректно снимают
						#elV, добавленный строкой выше (PathArray.append(elV)), перед следующей
						#итерацией "for elV in keys". Эта ветка — единственная, где PathArray
						#оставался "грязным": после возврата из рекурсивного UniversalBypass
						#(который сам сбалансированно append/pop_back внутри СЕБЯ) elV этого
						#уровня так и оставался в PathArray. На один ключ это незаметно, но если
						#в словаре/массиве НЕСКОЛЬКО ключей и хотя бы один не последний уходит в
						#Deeper — следующий соседний ключ добавлялся ПОВЕРХ уже накопленного
						#"хвоста" от предыдущего, ушедшего вглубь. PathArray разрастался мусорными
						#сегментами от уже обработанных чужих поддеревьев и переставал быть
						#валидным путём — отсюда "Invalid access to property or key 'k_2_2'":
						#PassageAlongWay пытался идти по искажённому PathArray, а не по
						#настоящему пути до этого ключа (см. чат — репродуцировалось на
						#test_performance()/_generate_big_dict, где на каждом уровне по 4 ключа,
						#а не на test_full_correctness(), где почти везде по 1 ключу на уровень —
						#там "грязный хвост" был всегда последним и его никто не читал)
						PathArray.pop_back()
					else:
						PathArray.pop_back()
						if _vC_ActiveStreamId != "":
							Logger.fC_Adding_Buffer_Cr(_vC_ActiveStreamId, "UniversalBypass: Deeper requested but element not iterable — error", [elV], "push_error")
						push_error("⛔ ",variables1," при ", elV, " Не обходится")
				"Further":
					# else (в рамках match): просто идём к следующему ключу на этом же уровне
					PathArray.pop_back()
					pass
				"Higher":
					# else: сигнал остановить обход текущего уровня целиком
					PathArray.pop_back()
					if _vC_ActiveStreamId != "":
						Logger.fC_Adding_Buffer_Cr(_vC_ActiveStreamId, "UniversalBypass: Higher, stopping this level", [elV], null)
					break
				_:
					# else: callback вернул что-то незнакомое — это ошибка использования UniversalBypass
					if _vC_ActiveStreamId != "":
						Logger.fC_Adding_Buffer_Cr(_vC_ActiveStreamId, "UniversalBypass: unknown returnfunc1 — error", [elV, returnfunc1], "push_error")
					push_error("⛔ returnfunc1 UniversalBypass при ",variables1," и ", funcparametrs, " = ", returnfunc1)
					return

##Функционал:
##	Проходит по Variables1 шаг за шагом согласно ключам из PathArray и возвращает
##	значение, до которого дошли. Без FuncParametrs — обычный прямой проход
##	(VariablesReturn = VariablesReturn[elPA] на каждом шаге, без исключений).
##	С FuncParametrs (например {"func":_PAW_CO2V}) — перед каждым шагом спрашивает
##	callback, точно ли нужно заходить в этот ключ (используется, чтобы пропускать
##	служебные "Child"-сегменты пути при проходе по originalVariables1/2, у которых
##	такого ключа нет — см. _PAW_CO2V).
##Форматы данных:
##	Входные:
##		Variables1 - исходная структура данных, по которой идём (не мутируется —
##			функция сразу делает глубокую копию и работает с ней)
##		PathArray: Array - массив ключей/индексов пути, куда нужно дойти
##		FuncParametrs: Dictionary - {"func": Callable, ...} — если передан, каждый шаг
##			пути идёт через этот callback (см. _PAW_CO2V); если {} (по умолчанию) —
##			прямой проход без пропусков
##	Выходные:
##		Variant - значение по указанному пути (или там, где остановились, если
##			callback сказал flagPassageAlongWay=false на каком-то шаге)
##Принцип работы:
##	1. Делаем глубокую копию Variables1, чтобы не менять оригинал
##	2. Для каждого ключа из PathArray по очереди:
##		- если FuncParametrs пуст — просто заходим по ключу (VariablesReturn[elPA])
##		- если не пуст — спрашиваем callback (через Class_Help.FunctionCall), и заходим
##		  внутрь только если он не сказал flagPassageAlongWay=false
##	3. Возвращаем то, до чего дошли
func PassageAlongWay (Variables1, PathArray: Array, FuncParametrs:= {}):
	var VariablesReturn = Variables1.duplicate(true)  # Глубокое копирование
	for elPA in PathArray:
		if FuncParametrs != {}:
			var flagPassageAlongWay = true
			# Создаем копию словаря параметров, чтобы не изменять оригинальный
			var FuncParametrsCopy = FuncParametrs.duplicate()
			var ReturnFunctionCall = Class_Help.FunctionCall(FuncParametrsCopy,[VariablesReturn, Variables1, elPA], Class_Logger, _vC_ActiveStreamId)
			pass
			if ReturnFunctionCall != null and ReturnFunctionCall.has("VariablesReturn"):
				VariablesReturn = PassageAlongWay(VariablesReturn, ReturnFunctionCall ["VariablesReturn"])
			if ReturnFunctionCall != null and ReturnFunctionCall.has("flagPassageAlongWay"):
				flagPassageAlongWay = ReturnFunctionCall ["flagPassageAlongWay"]
			if flagPassageAlongWay:
				VariablesReturn = VariablesReturn [elPA]
				if _vC_ActiveStreamId != "":
					Logger.fC_Adding_Buffer_Cr(_vC_ActiveStreamId, "PassageAlongWay: Good flagPassageAlongWay, stepping into", [elPA], null)
			else:
				if _vC_ActiveStreamId != "":
					Logger.fC_Adding_Buffer_Cr(_vC_ActiveStreamId, "PassageAlongWay: Not flagPassageAlongWay, staying at current level", [elPA], null)
		else:
			VariablesReturn = VariablesReturn [elPA]
	return VariablesReturn

##⚠️ 2026-08-13: больше НЕ вызывается ни из одного места в файле — заменена на
##	RecalculateResultsRecursive (см. рядом с _CP_CO2V). Причина замены: сюда передавался
##	локальный узел текущей глубины рекурсии вместо корня дерева, а PathArray был при этом
##	абсолютным путём от корня — при попытке применить "Child" к листовому узлу без потомков
##	падало (см. чат/лог теста value_diff). Оставлена в файле неудалённой на случай, если
##	где-то ещё понадобится — можно убрать вместе с PassageAlongWay-веткой без FuncParametrs (строка ~318-319), если она тоже станет не нужна
##Функционал:
##	Описание, что делает функция на уровне задачи
##Форматы данных:
##	Входные:
##		PathArray: Array - массив ключей/индексов пути
##		FuncParametrs: Dictionary - функциональные параметры
##		Variables - структура данных для проверки
##	Выходные:
##		Нет
##Принцип работы:
##	Как именно функция достигает результата, какие шаги предпринимает
func CheckingPath (PathArray: Array, FuncParametrs: Dictionary, Variables):
	var originalPathArray = PathArray.duplicate()
	# while: поднимаемся от текущего пути к корню, шаг за шагом, и на каждом шаге
	# вызываем FuncParametrs["func"] (например _CP_CO2V) для пересчёта агрегированного result
	while len(originalPathArray)-1 > 0:
		originalPathArray.pop_back()
		if _vC_ActiveStreamId != "":
			Logger.fC_Adding_Buffer_Cr(_vC_ActiveStreamId, "CheckingPath: while, walking up one level", [originalPathArray.duplicate()], null)
		# Создаем копию словаря параметров, чтобы не изменять оригинальный
		var FuncParametrsCopy = FuncParametrs.duplicate()
		Class_Help.FunctionCall(FuncParametrsCopy, [PassageAlongWay(Variables, originalPathArray)], Class_Logger, _vC_ActiveStreamId)



##Функционал:
##	Сравнивает 2 переменных если переменные не совпали но явялются контенером проходятся в нутри и сравниваются
##Форматы данных:
##	Входные:
##		Variables1 - Перва переменная для сравнения
##		Variables2 - Вторая переменная для сравнения
##		ReturnDictionary - Словарь по формату "result": "", "Values": [],"Child"*: [] *только если будет сравнения на уровне ниже
##Принцип работы:
##	1. Проверка на полное соотвествие
##	2. Если 1. false то Проверка на то что оба контенеры если да то создаем список детей и вызываем UniversalBypass с _C_ComparisonsOf2Variables_0101 для обхода и сравнения
##	3. Если нет то сохраем в ReturnDictionary что переменные разные
##
## КАК ПОЛЬЗОВАТЬСЯ (программисту):
##	Единственная точка входа, которую вызывает test.gd. Вызывающий код может (не обязан)
##	выставить _vC_ActiveStreamId ДО вызова этой функции (через Class_Logger.fC_RegisterStream_Cr)
##	и сбросить/завершить поток ПОСЛЕ (через Class_Logger.fC_FinishStream_Ch) — см.
##	test.gd::test_full_correctness — тогда записи попадут в именованный поток. 2026-08-14:
##	раньше при пустом _vC_ActiveStreamId логирование было no-op (условие "if _vC_ActiveStreamId
##	!= ''" перед каждым вызовом Class_Logger); убрано по просьбе автора — логирование теперь
##	ВСЕГДА включено, даже без зарегистрированного потока (пишет в поток с id "" — это
##	осознанный временный компромисс для отладки краша test_performance() на случайных данных,
##	см. чат "Программа вылетела" — POI ниже: без этого test_performance() не логировал вообще
##	ничего, и падение было не поймать). У этого решения есть цена — test_performance() больше
##	не измеряет "чистое" время сравнения без логгера (см. её собственный комментарий, тоже
##	частично устаревший теперь), лог растёт быстрее. Вернуть "if _vC_ActiveStreamId != ''"
##	назад на все места, когда баг найден
func fC_ComparisonsOf2Variables_0101 (Variables1, Variables2, ReturnDictionary):
	var ChildReturnDictionary := {}
	# if: типы переменных совпадают — можно сравнивать напрямую
	if typeof(Variables1) == typeof(Variables2):
		if _vC_ActiveStreamId != "":
			Logger.fC_Adding_Buffer_Cr(_vC_ActiveStreamId, "fC_ComparisonsOf2Variables_0101: types match", [Variables1, Variables2], null)
		# if: значения полностью равны (для Dictionary/Array — глубокое сравнение через ==)
		if Variables1 == Variables2:
			#2026-08-14: KM ("keys match") - суффикс, добавляемый к любому result, кроме
			#">"/"<" (см. правило ниже в _CP_CO2V). Здесь сравниваем два значения, которые
			#ОБА присутствуют (это не "-в-a"/"-в-b" случай) -> всегда с KM
			ReturnDictionary["result"] = "+KM"
			ReturnDictionary["Values"] = [Variables1, Variables2]
			if _vC_ActiveStreamId != "":
				Logger.fC_Adding_Buffer_Cr(_vC_ActiveStreamId, "fC_ComparisonsOf2Variables_0101: fully equal -> +KM", [], "result=+KM")
		# elif: оба — словари, но не равны целиком -> сравниваем по ключам, уходим вглубь
		elif TYPE_DICTIONARY == typeof(Variables1) and  TYPE_DICTIONARY == typeof(Variables2):
			if _vC_ActiveStreamId != "":
				Logger.fC_Adding_Buffer_Cr(_vC_ActiveStreamId, "fC_ComparisonsOf2Variables_0101: both Dictionary, not equal -> diff by key", [Variables1.keys(), Variables2.keys()], null)
			for elV1 in Variables1:
				if Variables2.has(elV1):
					ChildReturnDictionary[elV1] = {}
				else:
					# 2026-08-09 fix: раньше тут не было ChildReturnDictionary[elV1] = {},
					# и присвоение ["result"] на несуществующий ключ падало с
					# "Invalid access to property or key" (см. лог теста only_in_a)
					ChildReturnDictionary[elV1] = {}
					ChildReturnDictionary[elV1]["result"] = ">"
					ChildReturnDictionary[elV1]["Values"] = [Variables1 [elV1]]
			for elV2 in Variables2:
				if Variables1.has(elV2):
					ChildReturnDictionary[elV2] = {}
				else:
					# 2026-08-09 fix: то же самое для ветки "<" (см. выше)
					ChildReturnDictionary[elV2] = {}
					ChildReturnDictionary[elV2]["result"] = "<"
					ChildReturnDictionary[elV2]["Values"] = [Variables2 [elV2]]
			ReturnDictionary["result"] = "~"
			ReturnDictionary["Values"] = [Variables1, Variables2]
			ReturnDictionary["Child"] = ChildReturnDictionary
			UniversalBypass(ReturnDictionary, {"func": _C_ComparisonsOf2Variables_0101, "Parametrs": [Variables1, Variables2]})
			RecalculateResultsRecursive(ReturnDictionary)
		# else: типы совпали, но это не Dictionary и не равны — значит различающиеся простые значения
		else:
			#2026-08-14: KM - оба значения присутствуют (просто различаются) -> с KM
			ReturnDictionary["result"] = "-KM"
			ReturnDictionary["Values"] = [Variables1, Variables2]
			if _vC_ActiveStreamId != "":
				Logger.fC_Adding_Buffer_Cr(_vC_ActiveStreamId, "fC_ComparisonsOf2Variables_0101: same type, not equal, not Dictionary -> -KM", [Variables1, Variables2], "result=-KM")
	# elif: типы разные, но оба — какие-то массивы (Array/Packed*Array) -> сравниваем поэлементно
	elif Class_Help.ARRAY_TYPES_MAP.has(typeof(Variables1)) and Class_Help.ARRAY_TYPES_MAP.has(typeof(Variables2)):
		if _vC_ActiveStreamId != "":
			Logger.fC_Adding_Buffer_Cr(_vC_ActiveStreamId, "fC_ComparisonsOf2Variables_0101: both array-like, different exact type -> diff by index", [Variables1.size(), Variables2.size()], null)
		var LengthArray = min(Variables1.size(), Variables2.size())
		var Counter = 0
		while LengthArray > 0:
			ChildReturnDictionary[str(Counter)] = {}
			LengthArray -= 1
			Counter += 1
		LengthArray = max(Variables1.size(), Variables2.size()) - Counter
		while LengthArray > 0:
			if Variables1.size() > Variables2.size():
				ChildReturnDictionary[str(Counter)]["result"] = ">"
				ChildReturnDictionary[str(Counter)]["Values"] = [Variables1]
			else:
				ChildReturnDictionary[str(Counter)]["result"] = "<"
				ChildReturnDictionary[str(Counter)]["Values"] = [Variables2]
			LengthArray -= 1
			Counter += 1
		ReturnDictionary["result"] = "~"
		ReturnDictionary["Values"] = [Variables1, Variables2]
		ReturnDictionary["Child"] = ChildReturnDictionary
		UniversalBypass(ReturnDictionary, {"func": _C_ComparisonsOf2Variables_0101, "Parametrs": [Variables1, Variables2]})
		RecalculateResultsRecursive(ReturnDictionary)
	# else: типы совсем разные и не оба массивы — считаем переменные разными без углубления
	else:
		#2026-08-14: KM - оба значения присутствуют (типы просто не совпали) -> с KM
		ReturnDictionary["result"] = "-KM"
		ReturnDictionary["Values"] = [Variables1, Variables2]
		if _vC_ActiveStreamId != "":
			Logger.fC_Adding_Buffer_Cr(_vC_ActiveStreamId, "fC_ComparisonsOf2Variables_0101: different types, not both arrays -> -KM", [Variables1, Variables2], "result=-KM")


##Функционал:
##	Callback для UniversalBypass(ReturnDictionary, ...) — вызывается по одному разу на
##	каждый ключ, который UniversalBypass встречает при обходе ReturnDictionary/его "Child"-веток.
##	Получаем актуальные по пути переменные для сравнения и сравниваем их.
##Форматы данных:
##	Входные:
##		InputArray: Array - собран Class_Help.FunctionCall из
##			FuncParametrs["Parametrs"]=[originalVariables1, originalVariables2] (см.
##			UniversalBypass(ReturnDictionary, {"func":_C_ComparisonsOf2Variables_0101,
##			"Parametrs":[Variables1,Variables2]}) в fC_ComparisonsOf2Variables_0101) +
##			EmbeddedParameters=[type_id, variables1, PathArray, elV] от самого UniversalBypass:
##			[0] originalVariables1 (не меняется на всей глубине рекурсии)
##			[1] originalVariables2 (не меняется на всей глубине рекурсии)
##			[2] type_id — typeof() контейнера, который сейчас обходит UniversalBypass
##			[3] variables1 — ТЕКУЩИЙ узел на этой глубине рекурсии (не корень дерева!)
##			[4] PathArray — полный путь от корня дерева до текущего ключа (общий на всю рекурсию)
##			[5] elV — ключ, который сейчас обходится (значение самого верхнего уровня InputArray[3])
##	Выходные:
##		String - "Deeper" (у ключа есть что обходить глубже) / "Further" (ключ пропускаем,
##			идём к следующему на этом же уровне)
##Принцип работы:
##	Ключ InputArray[5] может означать 3 разных случая — их нельзя обрабатывать одинаково:
##	1. InputArray[5] == "Child" — служебное поле-указатель "здесь лежат дети для сравнения".
##		Просто return "Deeper", ничего не считаем и не трогаем ReturnDictionary — иначе
##		получится повторное сравнение originalVariables1/2 самих с собой и бесконечная
##		рекурсия (см. чат/лог теста value_diff от 2026-08-13: было ==/!= "Child" на любой
##		глубине, а не только на самом верхнем узле — "Child" сам порождал новый "Child").
##	2. InputArray[5] == "result" или "Values" — служебные поля узла, не ключи данных.
##		return "Further", пропускаем.
##	3. Любой другой ключ (например "x") — это настоящий ключ данных. Через
##		PassageAlongWay(InputArray[0/1], PathArray, {"func":_PAW_CO2V}) достаём актуальные
##		значения (originalVariables1/2 не меняются, поэтому путь всегда от истинного корня;
##		_PAW_CO2V пропускает служебные "Child"-сегменты в PathArray, которых в originalVariables
##		нет), сравниваем их и пишем "result"/"Values"/"Child" в
##		ReturnDictionary = InputArray[3][InputArray[5]] (узел ИМЕННО этого ключа на этой глубине).
##		Дальнейшая агрегация "~" в финальный символ — не здесь, а отдельным проходом
##		RecalculateResultsRecursive после того как UniversalBypass закончит весь обход целиком.
func _C_ComparisonsOf2Variables_0101 (InputArray: Array):
	if _vC_ActiveStreamId != "":
		Logger.fC_Adding_Buffer_Cr(_vC_ActiveStreamId, "_C_ComparisonsOf2Variables_0101 (Child): InputArray snapshot 0",[InputArray[0]], null)
	if _vC_ActiveStreamId != "":
		Logger.fC_Adding_Buffer_Cr(_vC_ActiveStreamId, "_C_ComparisonsOf2Variables_0101 (Child): InputArray snapshot 1",[InputArray[1]], null)
	if _vC_ActiveStreamId != "":
		Logger.fC_Adding_Buffer_Cr(_vC_ActiveStreamId, "_C_ComparisonsOf2Variables_0101 (Child): InputArray snapshot 2",[InputArray[2]], null)
	if _vC_ActiveStreamId != "":
		Logger.fC_Adding_Buffer_Cr(_vC_ActiveStreamId, "_C_ComparisonsOf2Variables_0101 (Child): InputArray snapshot 3",[InputArray[3]], null)
	if _vC_ActiveStreamId != "":
		Logger.fC_Adding_Buffer_Cr(_vC_ActiveStreamId, "_C_ComparisonsOf2Variables_0101 (Child): InputArray snapshot 4",[InputArray[4]], null)
	if _vC_ActiveStreamId != "":
		Logger.fC_Adding_Buffer_Cr(_vC_ActiveStreamId, "_C_ComparisonsOf2Variables_0101 (Child): InputArray snapshot 5",[InputArray[5]], null)

	if InputArray[5] == "Child":
		if _vC_ActiveStreamId != "":
			Logger.fC_Adding_Buffer_Cr(_vC_ActiveStreamId, "_C_ComparisonsOf2Variables_0101: key == \"Child\" -> just Deeper, no recompute", [], null)
		return "Deeper"
	elif InputArray[5] == "result" or InputArray[5] == "Values":
		if _vC_ActiveStreamId != "":
			Logger.fC_Adding_Buffer_Cr(_vC_ActiveStreamId, "_C_ComparisonsOf2Variables_0101: key == \"result\"/\"Values\" -> skip, Further", [InputArray[5]], null)
		return "Further"
	else:
		var PathArray = InputArray[4]
		#1.Получаем акуальные изменения
		var ReturnDictionary = InputArray[3][InputArray[5]]
		if ReturnDictionary.has("result"):
			if _vC_ActiveStreamId != "":
				Logger.fC_Adding_Buffer_Cr(_vC_ActiveStreamId, "_C_ComparisonsOf2Variables_0101: already resolved (>/< с первого прохода) -> skip, Further", [InputArray[5]], null)
			return "Further"
		var Variables1 = PassageAlongWay(InputArray[0],PathArray, {"func":_PAW_CO2V})
		var Variables2 = PassageAlongWay(InputArray[1],PathArray, {"func":_PAW_CO2V})
		#Сверка переменных
		#3.Формируем результат
		var ChildReturnDictionary := {}
		if _vC_ActiveStreamId != "":
			Logger.fC_Adding_Buffer_Cr(_vC_ActiveStreamId, "_C_ComparisonsOf2Variables_0101: Child branch entered", [PathArray.duplicate()], null)
		if  typeof(Variables1) == typeof(Variables2):
			if Variables1 == Variables2:
				#2026-08-14: KM - ключ присутствует в обеих структурах (иначе сюда бы не
				#дошли - см. "already resolved"/">"/"<" выше по коду) -> всегда с KM
				ReturnDictionary["result"] = "+KM"
				ReturnDictionary["Values"] = [Variables1, Variables2]
				if _vC_ActiveStreamId != "":
					Logger.fC_Adding_Buffer_Cr(_vC_ActiveStreamId, "_C_ComparisonsOf2Variables_0101: equal -> +KM -> Further", [], null)
				return "Further"
			elif TYPE_DICTIONARY == typeof(Variables1) and TYPE_DICTIONARY == typeof(Variables2):
				if _vC_ActiveStreamId != "":
					Logger.fC_Adding_Buffer_Cr(_vC_ActiveStreamId, "_C_ComparisonsOf2Variables_0101: both Dictionary, not equal -> Deeper", [], null)
				for elV1 in Variables1:
					if Variables2.has(elV1):
						ChildReturnDictionary[elV1] = {}
					else:
						# 2026-08-09 fix: то же исправление, что и в fC_ComparisonsOf2Variables_0101
						ChildReturnDictionary[elV1] = {}
						ChildReturnDictionary[elV1]["result"] = ">"
						ChildReturnDictionary[elV1]["Values"] = [Variables1 [elV1]]
				for elV2 in Variables2:
					if Variables1.has(elV2):
						ChildReturnDictionary[elV2] = {}
					else:
						# 2026-08-09 fix: то же исправление, что и в fC_ComparisonsOf2Variables_0101
						ChildReturnDictionary[elV2] = {}
						ChildReturnDictionary[elV2]["result"] = "<"
						ChildReturnDictionary[elV2][ "Values"] = [Variables2 [elV2]]
				ReturnDictionary["result"] = "~"
				ReturnDictionary["Values"] = [Variables1, Variables2]
				ReturnDictionary["Child"] = ChildReturnDictionary
				return "Deeper"
			else:
				#2026-08-14: KM - ключ присутствует в обеих структурах -> с KM
				ReturnDictionary["result"] = "-KM"
				ReturnDictionary["Values"] = [Variables1, Variables2]
				if _vC_ActiveStreamId != "":
					Logger.fC_Adding_Buffer_Cr(_vC_ActiveStreamId, "_C_ComparisonsOf2Variables_0101: same type, not equal, not Dictionary -> -KM -> Further", [], null)
				return "Further"

		elif Class_Help.ARRAY_TYPES_MAP.has(typeof(Variables1)) and Class_Help.ARRAY_TYPES_MAP.has(typeof(Variables2)):
			if _vC_ActiveStreamId != "":
				Logger.fC_Adding_Buffer_Cr(_vC_ActiveStreamId, "_C_ComparisonsOf2Variables_0101: both array-like -> Deeper", [], null)
			var LengthArray = min(Variables1.size(), Variables2.size())
			var Counter = 0
			while LengthArray > 0:
				ChildReturnDictionary[str(Counter)] = {}
				LengthArray -= 1
				Counter += 1
			LengthArray = max(Variables1.size(), Variables2.size()) - Counter
			while LengthArray > 0:
				if Variables1.size() > Variables2.size():
					ChildReturnDictionary[str(Counter)]["result"] = ">"
					ChildReturnDictionary[str(Counter)]["Values"] = [Variables1]
				else:
					ChildReturnDictionary[str(Counter)]["result"] = "<"
					ChildReturnDictionary[str(Counter)]["Values"] = [Variables2]
				LengthArray -= 1
				Counter += 1
			ReturnDictionary["result"] = "~"
			ReturnDictionary["Values"] = [Variables1, Variables2]
			ReturnDictionary["Child"] = ChildReturnDictionary
			return "Deeper"
		else:
			#2026-08-14: KM - ключ присутствует в обеих структурах -> с KM
			ReturnDictionary["result"] = "-KM"
			ReturnDictionary["Values"] = [Variables1, Variables2]
			if _vC_ActiveStreamId != "":
				Logger.fC_Adding_Buffer_Cr(_vC_ActiveStreamId, "_C_ComparisonsOf2Variables_0101: different types, not both arrays -> -KM -> Further", [], null)
			return "Further"



##Функционал:
##	Пересчитывает агрегированные "result" по всему дереву сравнения снизу вверх:
##	сначала все потомки узла, потом сам узел (через _CP_CO2V). Заменяет собой
##	CheckingPath/PathArray-подход (падал: пытался применить ключ "Child" к листовому узлу
##	без потомков, т.к. ему передавали локальный узел текущей глубины рекурсии вместо корня
##	дерева) — здесь путь вообще не нужен, обход идёт по собственным связям "Child" самого дерева
##Форматы данных:
##	Входные:
##		Node: Dictionary - узел дерева сравнения (ReturnDictionary целиком или один из
##			ChildReturnDictionary[key] на любой глубине)
##	Выходные:
##		Нет — мутирует Node (и вложенные узлы) на месте, по ссылке
##Принцип работы:
##	1. Если у узла есть "Child" — берём его ключи через Class_Help.get_iter_keys
##	   (тот же инструмент обхода, что использует UniversalBypass) и рекурсивно
##	   пересчитываем сначала всех потомков — снизу вверх, потомки раньше родителя
##	2. Только когда все потомки уже пересчитаны и если у самого узла result == "~" —
##	   пересчитываем его через _CP_CO2V (там уже все ValueCounter[...] будут корректны)
func RecalculateResultsRecursive(Node: Dictionary):
	if Node.has("Child"):
		var keys = Class_Help.get_iter_keys(Node["Child"])
		for elKey in keys:
			RecalculateResultsRecursive(Node["Child"][elKey])
		if Node.get("result", null) == "~":
			_CP_CO2V(Node)

##Функционал:
##	Пересчитывает агрегированный "result" одного узла дерева сравнения на основе
##	результатов его уже пересчитанных потомков (вызывается из RecalculateResultsRecursive
##	снизу вверх, поэтому к моменту вызова Variables["Child"][...]["result"] уже финальны)
##Форматы данных:
##	Входные:
##		Variables - словарь-узел дерева сравнения для обновления результата
##			(2026-08-13: убран неиспользуемый параметр PathArray — артефакт версии
##			на CheckingPath, внутри функции он никогда не читался)
##	Выходные:
##		Нет — мутирует Variables["result"] на месте
##Принцип работы:
##	1. Считаем ValueCounter по базовым символам потомков (KM-суффикс снимается перед
##	   подсчётом, см. 2026-08-14 ниже)
##	2. Обычная агрегация в "-"/"+"/"~"/"~-"/"~>"/"~<"/"~>-"/"~<-" (логика не менялась)
##	3. 2026-08-14: если среди потомков был хотя бы один с совпавшим ключом (не голый
##	   ">"/"<") — добавляем суффикс "KM" к итоговому символу. Узлы, полностью собранные
##	   из непересекающихся ключей (только ">"/"<" потомки), KM не получают
func _CP_CO2V (Variables):
	if Variables.has("result"):
		if Variables ["result"] == "~":
			var ValueCounter = {"-":0, "+":0, ">":0, "<": 0,"~": 0, "~-":0, "~>":0, "~<":0, "~>-":0, "~<-":0 }
			for elChild in Variables["Child"]:
				var ChildResult = Variables ["Child"] [elChild] ["result"]
				#2026-08-14: KM ("keys match") - суффикс, который стоит на любом result
				#потомка, кроме ">"/"<" (см. места установки result выше по файлу). Для
				#подсчёта в ValueCounter он не нужен - считаем по базовому символу,
				#снимаем суффикс перед инкрементом (иначе "-KM"/"+KM"/... не попадут
				#ни в один ключ ValueCounter и вся ветка ниже сломается)
				if typeof(ChildResult) == TYPE_STRING and ChildResult.ends_with("KM"):
					ChildResult = ChildResult.substr(0, ChildResult.length() - 2)
				ValueCounter [ChildResult] += 1
			if _vC_ActiveStreamId != "":
				Logger.fC_Adding_Buffer_Cr(_vC_ActiveStreamId, "_CP_CO2V: recomputing aggregated result from children", [ValueCounter], null)
			#2026-08-14: KM нужно добавить к итоговому result этого узла, ТОЛЬКО если среди
			#потомков был хотя бы один, полученный из настоящего сравнения СОВПАВШЕГО ключа
			#(+, -, ~ и любые ~-варианты) - а не только из ">"/"<" (ключ был только у одной
			#из сторон, сравнивать было нечего). Если все потомки - чистые ">"/"<", ни один
			#ключ не совпал вообще -> KM не добавляем
			var Bv_HasMatchedKeyChild = ValueCounter["+"]>0 or ValueCounter["-"]>0 or ValueCounter["~"]>0 or ValueCounter["~-"]>0 or ValueCounter["~>"]>0 or ValueCounter["~<"]>0 or ValueCounter["~>-"]>0 or ValueCounter["~<-"]>0
			if ValueCounter["~>-"] + ValueCounter["~<-"] > 0:
				pass
			elif ValueCounter["~-"] + ValueCounter["~>"] + ValueCounter ["~<"] > 0:
				pass
			else:
				if ValueCounter["+"]>0:
					if ValueCounter["-"]>0:
						if ValueCounter[">"]>0 and ValueCounter["<"]>0:
							Variables ["result"] = "~-"
						elif ValueCounter[">"]>0:
							Variables ["result"] = "~>-"
						elif  ValueCounter["<"]>0:
							Variables ["result"] = "~<-"
						else:
							Variables ["result"] = "~-"
					else:
						if ValueCounter[">"]>0 and ValueCounter["<"]>0:
							Variables ["result"] = "~-"
						elif ValueCounter[">"]>0:
							Variables ["result"] = "~>"
						elif ValueCounter["<"]>0:
							Variables ["result"] = "~<"
						else:
							Variables ["result"] = "~"
				else:
					if ValueCounter["-"]>0:
						Variables ["result"] = "-"
					else:
						if ValueCounter[">"]>0 and ValueCounter["<"]>0:
							Variables ["result"] = "-"
						elif ValueCounter[">"]>0:
							Variables ["result"] = ">"
						elif  ValueCounter["<"]>0:
							Variables ["result"] = "<"
						else:
							Variables ["result"] = "+"
			#2026-08-14: применяем KM к итоговому символу этого узла (кроме голых ">"/"<" -
			#но для них Bv_HasMatchedKeyChild и так всегда false, см. формулу выше, так что
			#проверка "!= > и != <" здесь чисто защитная)
			if Bv_HasMatchedKeyChild and Variables["result"] != ">" and Variables["result"] != "<":
				Variables["result"] += "KM"
			if _vC_ActiveStreamId != "":
				Logger.fC_Adding_Buffer_Cr(_vC_ActiveStreamId, "_CP_CO2V: result recomputed", [], Variables.get("result", null))

##Функционал:
##	Callback для PassageAlongWay — решает, нужно ли на данном шаге пути заходить внутрь
##	по текущему ключу, когда PassageAlongWay идёт по originalVariables1/2 (исходным,
##	неизменным данным). Смысл: PathArray собирается из обхода ReturnDictionary/дерева
##	результата, где на каждом уровне вложенности есть служебный ключ "Child" — а вот в
##	originalVariables1/2 такого ключа нет вообще (там только настоящие ключи данных, типа
##	"x"). Поэтому при проходе по originalVariables1/2 все "Child"-сегменты пути нужно
##	пропускать (оставаться на месте), а настоящие ключи — проходить как обычно.
##Форматы данных:
##	Входные:
##		Array - EmbeddedParameters, собранные PassageAlongWay: [VariablesReturn (то, до
##			чего дошли к этому шагу), Variables1 (исходная структура целиком), elPA
##			(ключ текущего шага пути)] — используется только Array[2] (elPA)
##	Выходные:
##		Dictionary {"flagPassageAlongWay": false} — если elPA == "Child" (не заходить,
##			остаться на текущем уровне); null (по умолчанию) — если ключ настоящий,
##			тогда PassageAlongWay зайдёт внутрь как обычно (flagPassageAlongWay=true)
##Принцип работы:
##	Проверяем elPA. Если это служебное "Child" — говорим PassageAlongWay остаться на
##	месте. Иначе — ничего не возвращаем (null), и PassageAlongWay сам зайдёт по ключу.
func _PAW_CO2V (Array):
	var elPA = Array[2]
	if elPA == "Child":
		if _vC_ActiveStreamId != "":
			Logger.fC_Adding_Buffer_Cr(_vC_ActiveStreamId, "_PAW_CO2V: elPA == Child -> skip this level", [elPA], "flagPassageAlongWay=false")
		return {"flagPassageAlongWay": false}
