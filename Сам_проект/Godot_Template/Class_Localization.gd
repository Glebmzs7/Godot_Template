extends Node

class_name Class_Localization

##Версия оформления
##2026-08-19 - mzs7 - первая версия: обёртка над встроенной локализацией Godot
##	(TranslationServer/Translation) для экрана настроек (см. Start_Program.gd).
##	Файл-источник переводов — res://Save/Localization.csv, простой CSV без
##	экранирования запятых (в самих значениях запятых сейчас нет — если появятся,
##	парсер ниже потребует доработки). Формат: первая строка — заголовок
##	"keys,<локаль1>,<локаль2>,...", дальше по строке на ключ. Значения — пока
##	ВСЕ заглушки: русское слово с окончанием на буквенный индекс языка (например,
##	для ключа CATEGORY_LANGUAGE: "Язык_RU" в столбце ru, "Язык_EN" в столбце en
##	и т.п.) — реальных переводов не делаем, это не входит в задачу сейчас
##2026-08-19 - mzs7 - переводы читаются в Translation-ресурсы и регистрируются
##	через TranslationServer.add_translation() — это и есть "встроенная система
##	локализации Godot", просто без ручного импорта CSV через редактор (проект
##	собирается кодом, редакторский импорт сюда не вписывается). Дальше везде,
##	где нужен переводимый текст у Control-ноды (Button.text, Label.text,
##	LineEdit.placeholder_text и т.п.), в конфиг подставляется САМ КЛЮЧ (например
##	"CATEGORY_LANGUAGE"), а не текст — Godot сам переводит его на отрисовке
##	через auto_translate_mode (по умолчанию включён) и сам обновляет надпись при
##	смене locale (TranslationServer.set_locale) — вручную дёргать tr() или
##	перестраивать ноды при смене языка не нужно
##2026-08-19 - mzs7 - ⚠️ fxG_LoadLocalization_Ch больше не вызывает push_error сама —
##	вместо этого ВОЗВРАЩАЕТ String с описанием проблемы ("" = успех). Раньше при
##	отсутствующем/пустом/битом CSV ошибка тихо уходила только в консоль редактора
##	push_error'ом, а сам экран настроек никак не показывал, что переводов нет —
##	пользователь просто увидел бы сырые ключи ("CATEGORY_LANGUAGE" и т.п.) без
##	объяснения почему. Теперь вызывающий код (Start_Program._ready) сам решает,
##	что делать с ошибкой — логирует и показывает в окне информации через
##	_fC_ReportError_Ch, ничего не падает и не завершает программу (см. её же
##	changelog в Start_Program.gd про полную переработку по 8-пунктовому ТЗ,
##	пункт про push_error)
##2026-08-19 - mzs7 - ⚠️ ПЕРЕЕХАЛ FileLocalization: было res://Save/Localization.csv,
##	стало res://Localization/Localization.csv — обратная связь "убери
##	локализацию в папку, чтобы всё выглядело аккуратнее" (в project.godot в
##	file_customization/folder_colors уже была заведена res://Localization/,
##	жёлтая, но реально не использовалась — файл лежал в Save/ вместе с
##	настройками). ⚠️ Класс этого файла (Class_Localization.gd) остался в
##	Class/ — переехал только CSV с данными переводов, сам класс-скрипт
##	по-прежнему живёт рядом с остальными классами проекта (Class_Logger.gd,
##	Class_UI.gd, Class_Json.gd), это соответствует уже принятой в проекте
##	раскладке папок. ⚠️ Старые Save/Localization.csv.import и
##	Save/Localization.{ru,en,de,fr,es}.translation НЕ перенесены и НЕ
##	удалены — это артефакты штатного импорта CSV через редактор Godot, а
##	этот класс их не использует (парсит CSV сам через FileAccess, см.
##	fxG_LoadLocalization_Ch ниже) — они остались висеть в Save/ как мусор,
##	у меня нет инструмента удалить/переместить файлы на твоём диске, только
##	записать новые — почисти их сам в проводнике или в самом Godot, когда
##	будет удобно
##2026-08-20 - mzs7 - ⚠️ Localization.csv: заглушки ("Язык_RU"/"Язык_EN" и
##	т.п., см. запись 2026-08-19 выше) заменены на настоящие переводы на
##	английский/немецкий/французский/испанский (обратная связь: "переведи на
##	выбор языка весь интерфейс"). Заодно из русского столбца убрана приписка
##	"_RU" — теперь там просто "Язык" вместо "Язык_RU". Суффиксы были ЧИСТО
##	косметическими метками-заглушками, ни этот файл, ни Start_Program.gd на
##	них нигде не завязаны (ключи локализации типа LANG_RU — это отдельно,
##	идентификаторы переводов, не сами значения) — можно было менять без
##	риска что-то сломать в логике

## Путь к CSV-файлу с переводами
var FileLocalization := "res://Localization/Localization.csv"

## Список кодов поддерживаемых локалей — тот же порядок, что и в CSV-заголовке,
## дублируется здесь для удобства (языковой список в настройках берёт именно отсюда,
## а не парсит CSV-заголовок повторно)
var SupportedLocales_A := ["ru", "en", "de", "fr", "es"]

## true после успешного fxG_LoadLocalization_Ch — повторные вызовы не нужны
var _vGB_Loaded_Bv := false


#Функционал:
#	Загружает CSV-файл переводов и регистрирует по одному Translation-ресурсу
#	на каждую локаль из заголовка файла через TranslationServer.add_translation()
#Форматы данных:
#	Входные: нет (использует FileLocalization)
#	Выходные:
#		String — "" при успехе; иначе человекочитаемое описание проблемы (см.
#			changelog 2026-08-19 — раньше эти случаи были push_error'ом внутри
#			самого этого файла, теперь решение "что делать с ошибкой" отдано
#			вызывающему коду)
#Принцип работы:
#	1. Читает файл целиком, разбивает на строки
#	2. Первая строка — заголовок: "keys" + один столбец на локаль
#	3. Каждая следующая строка — один ключ перевода + значение на каждую локаль
#	4. На каждую локаль заводит Translation.new(), добавляет туда все ключи,
#	   регистрирует ресурс в TranslationServer
func fxG_LoadLocalization_Ch() -> String:
	if _vGB_Loaded_Bv:
		return ""

	if not FileAccess.file_exists(FileLocalization):
		return "Файл локализации не найден: %s" % FileLocalization

	var vL_File := FileAccess.open(FileLocalization, FileAccess.READ)
	if vL_File == null:
		return "Не удалось открыть файл локализации: %s" % FileLocalization
	var vLA_Lines: Array = vL_File.get_as_text().split("\n")
	vL_File.close()

	if vLA_Lines.is_empty():
		return "Файл локализации пуст: %s" % FileLocalization

	# Блок: заголовок — первый столбец "keys" пропускаем, остальные — коды локалей
	var vLA_Header: Array = vLA_Lines[0].strip_edges().split(",")
	var vLD_Translations := {} # {код_локали: Translation}
	for vLI_Col in range(1, vLA_Header.size()):
		var vLS_Locale: String = vLA_Header[vLI_Col].strip_edges()
		if vLS_Locale == "":
			continue
		var vL_Translation := Translation.new()
		vL_Translation.locale = vLS_Locale
		vLD_Translations[vLS_Locale] = vL_Translation

	# Блок: сами строки с переводами — по одной на ключ
	for vLI_Row in range(1, vLA_Lines.size()):
		var vLS_Line: String = vLA_Lines[vLI_Row].strip_edges()
		if vLS_Line == "":
			continue
		var vLA_Cells: Array = vLS_Line.split(",")
		var vLS_Key: String = vLA_Cells[0].strip_edges()
		if vLS_Key == "":
			continue
		for vLI_Col in range(1, min(vLA_Cells.size(), vLA_Header.size())):
			var vLS_Locale: String = vLA_Header[vLI_Col].strip_edges()
			if not vLD_Translations.has(vLS_Locale):
				continue
			vLD_Translations[vLS_Locale].add_message(vLS_Key, vLA_Cells[vLI_Col].strip_edges())

	# Блок: регистрируем все собранные Translation-ресурсы в движке разом
	for vLS_Locale in vLD_Translations:
		TranslationServer.add_translation(vLD_Translations[vLS_Locale])

	_vGB_Loaded_Bv = true
	return ""


#Функционал:
#	Определяет локаль системы (OS.get_locale()) и подбирает ближайшую
#	поддерживаемую (SupportedLocales_A) — используется, когда в настройках
#	ещё не сохранён явный выбор языка
#Форматы данных:
#	Входные: нет
#	Выходные:
#		String — код поддерживаемой локали (например "ru"); "en", если система
#			говорит на языке, которого нет в SupportedLocales_A
#Принцип работы:
#	OS.get_locale() отдаёт что-то вроде "ru_RU"/"en_US" — берём первые 2 буквы
#	до "_" и ищем такой код среди SupportedLocales_A
func fC_DetectSystemLocale_S() -> String:
	var vLS_SystemLocale: String = OS.get_locale()
	var vLS_ShortCode: String = vLS_SystemLocale.split("_")[0].to_lower()
	if SupportedLocales_A.has(vLS_ShortCode):
		return vLS_ShortCode
	return "en"


#Функционал:
#	Переключает активную локаль движка — все переводимые надписи на экране
#	обновляются автоматически (см. changelog про auto_translate_mode), вручную
#	перестраивать ноды не нужно
#Форматы данных:
#	Входные:
#		vLS_LocaleCode: String — код локали (например "ru")
#	Выходные: нет
func fC_SetLocale_Ch(vLS_LocaleCode: String) -> void:
	TranslationServer.set_locale(vLS_LocaleCode)


#Функционал:
#	Фильтрует список поддерживаемых локалей по тому, что пользователь набрал в
#	поиске — детектирует "раскладку" по алфавиту введённых символов (кириллица/
#	хирагана-катакана/CJK-иероглифы/латиница), а не ищет подстроку в названии
#	языка (сами названия сейчас — заглушки на русском для ВСЕХ языков, поиск
#	подстрокой по ним не имел бы смысла — см. changelog)
#Форматы данных:
#	Входные:
#		vLS_Query_S: String — то, что сейчас введено в поле поиска (может быть "")
#	Выходные:
#		Array — подмножество SupportedLocales_A, подходящее под запрос;
#			пустой vLS_Query_S -> весь список без фильтрации
#Принцип работы:
#	1. Пустой запрос — возвращаем всё как есть
#	2. Смотрим, символы какого юникод-диапазона есть в запросе (кириллица,
#	   хирагана/катакана, CJK-иероглифы, иначе считаем латиницей)
#	3. Возвращаем поддерживаемые локали, для которых этот диапазон — "родной"
#	   (сейчас родные диапазоны есть только у ru/en/de/fr/es — de/fr/es тоже
#	   латиница, поэтому при вводе латиницы предлагаются все три сразу)
func fC_FilterLocalesByInputScript_A(vLS_Query_S: String) -> Array:
	if vLS_Query_S.strip_edges() == "":
		return SupportedLocales_A.duplicate()

	var vLB_HasCyrillic_Bv := false
	var vLB_HasKana_Bv := false
	var vLB_HasCjk_Bv := false
	var vLB_HasLatin_Bv := false
	for elLS_Char in vLS_Query_S:
		var vLI_Code: int = elLS_Char.unicode_at(0)
		if vLI_Code >= 0x0400 and vLI_Code <= 0x04FF:
			vLB_HasCyrillic_Bv = true
		elif vLI_Code >= 0x3040 and vLI_Code <= 0x30FF:
			vLB_HasKana_Bv = true
		elif vLI_Code >= 0x4E00 and vLI_Code <= 0x9FFF:
			vLB_HasCjk_Bv = true
		elif (vLI_Code >= 0x0041 and vLI_Code <= 0x007A):
			vLB_HasLatin_Bv = true

	# Кириллица в запросе — уверенно предлагаем русский раньше остальных
	if vLB_HasCyrillic_Bv:
		return ["ru"]
	# Хирагана/катакана/CJK — сейчас в SupportedLocales_A нет ja/zh, поэтому
	# просто ничего не предлагаем (честно, а не подсовываем случайный вариант)
	if vLB_HasKana_Bv or vLB_HasCjk_Bv:
		return []
	if vLB_HasLatin_Bv:
		var vLA_LatinLocales_A: Array = []
		for elLS_Locale in SupportedLocales_A:
			if elLS_Locale != "ru":
				vLA_LatinLocales_A.append(elLS_Locale)
		return vLA_LatinLocales_A

	# Ничего не распознали (цифры/пунктуация и т.п.) — не сужаем список
	return SupportedLocales_A.duplicate()
