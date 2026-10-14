# Class/Class_Json
extends Object
class_name Class_Json
#Версия оформления: 0.1.2
#2025-06-20 - godot.guru - начальная реализация
#2026-08-24 - fxG_SaveJson_Ch теперь заранее проверяет, что папка назначения
#	существует, и пишет понятную ошибку в лог, если нет (баг "не проходит
#	последняя проверка" ThirdPartyFiles) — см. changelog у самой функции ниже

#Переменные:
var vGS_LastPath: String = ""  # Последний использованный путь
var vGD_LastJson: Dictionary = {}  # Последний успешно загруженный JSON


#Функционал:
#	Загружает JSON-файл и преобразует его в Dictionary
#Форматы данных:
#	Входные:
#		vGS_Path: String — путь к .json файлу
#	Выходные:
#		Dictionary — содержимое файла, либо {}
#Принцип работы:
#	Открывает файл, читает текст, парсит как JSON и возвращает как Dictionary
func fxG_LoadJson_Cr(vGS_Path: String) -> Dictionary:
	var flL_File := FileAccess.open(vGS_Path, FileAccess.READ)
	if flL_File == null:
		push_error("❌ Не удалось открыть файл: %s" % vGS_Path)
		return {}
	
	var vGS_Text := flL_File.get_as_text()
	flL_File.close()

	var vL_Result = JSON.parse_string(vGS_Text)
	if typeof(vL_Result) != TYPE_DICTIONARY:
		push_error("❌ JSON не содержит словарь: %s" % vGS_Path)
		return {}

	vGS_LastPath = vGS_Path
	vGD_LastJson = vL_Result
	return vL_Result


#Функционал:
#	Сохраняет словарь в JSON-файл
#Форматы данных:
#	Входные:
#		vGS_Path: String — путь для сохранения
#		vGD_Data: Dictionary — данные для сохранения
#	Выходные:
#		-
#Принцип работы:
#	Открывает файл на запись, сериализует словарь как JSON и записывает
#2026-08-24 - правка (баг "не проходит последняя проверка" ThirdPartyFiles):
#	FileAccess.open(..., WRITE) в Godot 4 НЕ создаёт недостающие родительские
#	папки сам — если папки нет на диске, open() просто возвращает null, и
#	файл тихо не записывается (push_error уходит в лог, но приложение
#	продолжает работать как ни в чём не бывало, и было непонятно ПОЧЕМУ
#	запись не удалась). Именно так и было с res://Save/Server/FileManifest.json
#	— папки Save/Server/ не существовало, поэтому
#	test.gd::fC_RegenerateFileManifest_Ch ничего не сохранял, а сервер затем
#	грузил ПУСТОЙ manifest ({}) и помечал вообще все файлы, присланные
#	клиентом, как "Unexpected" — проверка ThirdPartyFiles проваливалась
#	гарантированно, при любом реальном состоянии файлов.
#	⚠️ По просьбе пользователя папка автоматически НЕ создаётся (папки
#	создаются осознанно, руками — см. Save/Server/, уже создана вручную) —
#	вместо этого здесь заранее, ДО попытки открыть файл, проверяется, что
#	папка назначения существует, и если нет — в лог уходит понятная,
#	однозначная ошибка с указанием именно отсутствующей папки (а не общая
#	"не удалось открыть для записи", из которой причина не видна)
func fxG_SaveJson_Ch(vGS_Path: String, vGD_Data: Dictionary) -> void:
	var vGS_Dir_S := vGS_Path.get_base_dir()
	if vGS_Dir_S != "" and not DirAccess.dir_exists_absolute(vGS_Dir_S):
		push_error("❌ Папка не существует, файл не сохранён: %s (нужна папка %s)" % [vGS_Path, vGS_Dir_S])
		return

	var flL_File := FileAccess.open(vGS_Path, FileAccess.WRITE)
	if flL_File == null:
		push_error("❌ Не удалось открыть для записи: %s" % vGS_Path)
		return

	flL_File.store_string(JSON.stringify(vGD_Data, "\t"))
	flL_File.close()
	vGS_LastPath = vGS_Path
	vGD_LastJson = vGD_Data


#Функционал:
#	Перезаписывает последний открытый файл новым словарём
#Форматы данных:
#	Входные:
#		vGD_NewData: Dictionary — данные для перезаписи
#	Выходные:
#		-
#Принцип работы:
#	Если файл ранее загружался, сохраняет новые данные по тому же пути
func fxG_OverwriteLastJson_Ch(vGD_NewData: Dictionary) -> void:
	if vGS_LastPath == "":
		push_error("⛔ Нет пути для перезаписи")
		return

	fxG_SaveJson_Ch(vGS_LastPath, vGD_NewData)


#Функционал:
#	Объединяет два JSON-файла, копируя данные из одного в другой
#Форматы данных:
#	Входные:
#		vGS_Source: String — путь к исходному JSON
#		vGS_Target: String — путь к целевому JSON
#		vBv_Overwrite: bool — перезаписывать ли существующие ключи
#	Выходные:
#		Dictionary — итоговое объединение
#Принцип работы:
#	Загружает оба словаря, сливает их, сохраняет обновлённый файл
func fxG_MergeJsonFiles_Tr(vGS_Source: String, vGS_Target: String, vBv_Overwrite: bool = true) -> Dictionary:
	var vGD_Source := fxG_LoadJson_Cr(vGS_Source)
	var vGD_Target := fxG_LoadJson_Cr(vGS_Target)

	for elS_Key in vGD_Source:
		if not vGD_Target.has(elS_Key) or vBv_Overwrite:
			vGD_Target[elS_Key] = vGD_Source[elS_Key]

	fxG_SaveJson_Ch(vGS_Target, vGD_Target)
	return vGD_Target
