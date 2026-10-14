extends Node

## 2026-08-23: сцена "test" — место, где поднимается сервер, когда в окне
## выбора аккаунта на Start_Program выбрано техническое значение "Server"
## (см. Start_Program.gd → _fC_RunServerCheck_Ch, Class_UI.fxC_SwitchingScene_0000(".../test.tscn")).
## Фаза 1 (2026-08-23): реальное поднятие сервера (порт слушается, Hello/
## авторизация работают, см. Class_InternetServer.gd). 2026-08-23 (фаза 2):
## обработка "CheckUpdate"/"CheckFiles" от клиента — РЕАЛИЗОВАНА (см.
## _fC_OnServerAppOpReceived_Ch/_fC_HandleCheckUpdateRequest_Ch/
## _fC_HandleCheckFilesRequest_Ch ниже и AppOpReceived_S — Class_Internet.gd).
## 2026-08-23 (правка по просьбе пользователя "убери из test прошлые
## проверки"): убраны старые тесты Class_ArrayAndOrDictionary
## (test_full_correctness/test_manual_diagnostic/test_performance +
## _generate_big_dict) вместе с их переменной и стартом логгера через неё —
## эта сцена больше не рабочая зона для тех тестов, только сервер. Сами
## тесты Class_ArrayAndOrDictionary никуда не делись, просто здесь на них
## больше нет ссылок. 2026-08-24 (ревью интернет-кода по просьбе
## пользователя): _fC_HandleCheckFilesRequest_Ch теперь ловит ещё и
## УДАЛЁННЫЕ файлы ("Missing" в ответе) — раньше проверялось только "что
## прислано, совпадает" и "лишнего нет", но не "ничего не пропало" (см. её
## собственный changelog ниже)
var Class_InternetServer = load("res://Godot_Template/Class_InternetServer.gd").new()

## Тот же порт и адрес, что использует клиент (см. Start_Program.gd →
## SERVER_ADDRESS_S) — для локальной проверки на одном устройстве двумя
## экземплярами программы. vGB_RequireAuth_Bv=false — "сервер игрока", без
## реального списка зарегистрированных пользователей (Class_InternetServer.FileUsers_S
## пока не заводится автоматически, см. её changelog) — подходит для
## локальной проверки, не для настоящего глобального сервера
const SERVER_PORT_I := 9050

## "Актуальная" версия, которую сервер сообщает клиенту в ответ на
## "CheckUpdate" (см. Start_Program.gd → APP_VERSION_S — клиентская сторона
## той же сверки). Пока константа в коде — см. тот же пункт про настройки,
## что и у APP_VERSION_S
const SERVER_LATEST_VERSION_S := "0.1.0.0"

var _vGL_Json = load("res://Godot_Template/Class_Json.gd").new()

## Manifest файлов для проверки "ThirdPartyFiles" — {Путь: {"Size","FirstByte",
## "LastByte"}}, см. Class_FileIntegrity.fC_BuildManifestEntry_Cr. Отдельная
## папка Save/Server — сюда же складывает Class_InternetServer.FileUsers_S
const FILE_MANIFEST_S := "res://Save/Server/FileManifest.json"

## true — manifest пересобирается заново при каждом запуске сцены (см.
## fC_RegenerateFileManifest_Ch, вызывается ниже в _ready()). Это ровно та
## ручная перегенерация "при каждом вышедшем обновлении", о которой пользователь
## говорил в постановке задачи ("пока работаем над проектом будем обновлять
## для проверки, а потом выключать") — ⚠️ отдельного переключателя "выключить
## саму проверку ThirdPartyFiles совсем" (для релиза/прод-режима) пока нет,
## это открытый вопрос на будущее (см. План проекта/Class_Internet.md)
const REGENERATE_MANIFEST_ON_START_Bv := true

##Функционал:
##	Точка входа тестовой сцены — поднимает сервер, если сцену открыли через
##	выбор "Server" на Start_Program (см. changelog у Class_InternetServer
##	выше). 2026-08-23 (правка "убери из test прошлые проверки"): раньше здесь
##	же запускался логгер и старые тесты Class_ArrayAndOrDictionary — убраны,
##	эта сцена больше не рабочая зона для тех тестов
func _ready() -> void:
	# 2026-08-23 (фаза 2): manifest пересобирается ДО того, как сервер начнёт
	# принимать подключения — чтобы первый же CheckFiles от клиента увидел
	# актуальный файл, а не пустой/устаревший (см. REGENERATE_MANIFEST_ON_START_Bv)
	if REGENERATE_MANIFEST_ON_START_Bv:
		fC_RegenerateFileManifest_Ch()

	# add_child ОБЯЗАТЕЛЕН — Class_InternetServer (как и Class_InternetClient,
	# Class_UI в Start_Program.gd) это Node с переопределённым _process, без
	# добавления в дерево сцены _process просто не будет вызываться
	add_child(Class_InternetServer)
	Class_InternetServer.AppOpReceived_S.connect(_fC_OnServerAppOpReceived_Ch)
	if not Class_InternetServer.fxG_EstablishingConnection_CrTr(SERVER_PORT_I, false):
		push_warning("⚠️ test.gd: сервер не смог начать слушать порт %d" % SERVER_PORT_I)
	else:
		print("Сервер слушает порт %d" % SERVER_PORT_I)


##Функционал:
##	2026-08-23 (фаза 2): пересобирает FILE_MANIFEST_S с нуля — обходит те же
##	проверяемые файлы, что и клиент (Class_FileIntegrity.fC_ListCheckableFiles_Cr),
##	и сохраняет {Size,FirstByte,LastByte} для каждого (см. её changelog —
##	случайный байт в manifest НЕ хранится, сервер читает его "живьём" из
##	настоящего файла при каждой проверке, см. _fC_HandleCheckFilesRequest_Ch)
func fC_RegenerateFileManifest_Ch() -> void:
	var vLD_Manifest_D := {}
	for elLS_Path in Class_FileIntegrity.fC_ListCheckableFiles_Cr():
		var vLD_Entry_D := Class_FileIntegrity.fC_BuildManifestEntry_Cr(elLS_Path)
		if not vLD_Entry_D.is_empty():
			vLD_Manifest_D[elLS_Path] = vLD_Entry_D
	_vGL_Json.fxG_SaveJson_Ch(FILE_MANIFEST_S, vLD_Manifest_D)
	print("Manifest пересобран: %d файлов → %s" % [vLD_Manifest_D.size(), FILE_MANIFEST_S])


##Функционал:
##	2026-08-23 (фаза 2): точка входа для всех прикладных запросов от клиента
##	(см. AppOpReceived_S, changelog Class_Internet.gd/Class_InternetServer.gd)
##Форматы данных:
##	Входные: см. Class_Internet.AppOpReceived_S (vGS_ReplyRoutingKey_S — уже
##		проверенный UserID, см. Class_InternetServer._fL_ResolveTrustedUserID_Cr —
##		используется как RecipientID для ответа)
func _fC_OnServerAppOpReceived_Ch(vGS_Op_S: String, vGD_Envelope_D: Dictionary, vGF_ReceivedNowAt_F: float, vGS_ReplyRoutingKey_S: String) -> void:
	match vGS_Op_S:
		"CheckUpdate":
			_fC_HandleCheckUpdateRequest_Ch(vGD_Envelope_D, vGF_ReceivedNowAt_F, vGS_ReplyRoutingKey_S)
		"CheckFiles":
			_fC_HandleCheckFilesRequest_Ch(vGD_Envelope_D, vGF_ReceivedNowAt_F, vGS_ReplyRoutingKey_S)
		_:
			push_warning("⚠️ test.gd: неизвестная прикладная операция от клиента Op=%s" % vGS_Op_S)


##Функционал:
##	2026-08-23 (фаза 2): сравнивает присланную клиентом версию с
##	SERVER_LATEST_VERSION_S и отвечает "CheckUpdateResult"
func _fC_HandleCheckUpdateRequest_Ch(vGD_Envelope_D: Dictionary, vGF_ReceivedNowAt_F: float, vGS_ReplyRoutingKey_S: String) -> void:
	var vGD_Messages_D: Dictionary = vGD_Envelope_D.get("Messages", {})
	var vGS_ClientVersion_S: String = String(vGD_Messages_D.get("Version", ""))
	var vGB_UpToDate_Bv := vGS_ClientVersion_S == SERVER_LATEST_VERSION_S

	var vGD_AnswerTo_D := {"UserID": vGD_Envelope_D.get("UserID", ""), "Time": vGD_Envelope_D.get("Time", 0.0), "OperationNumber": vGD_Envelope_D.get("OperationNumber", -1)}
	Class_InternetServer.fC_SendingMessage_Cr("CheckUpdateResult", {"LatestVersion": SERVER_LATEST_VERSION_S, "UpToDate": vGB_UpToDate_Bv}, vGD_AnswerTo_D, vGS_ReplyRoutingKey_S, false, 5.0, [1.0, 3.0, 7.0], "", vGF_ReceivedNowAt_F)


##Функционал:
##	2026-08-23 (фаза 2): проверяет присланные клиентом отпечатки файлов против
##	FILE_MANIFEST_S — размер сверяется "по таблице" (manifest), случайный байт
##	— "нахождением" вживую (Class_FileIntegrity.fC_ReadByteAt_I читает
##	настоящий файл с диска сервера, см. её changelog — так честнее, чем
##	пытаться заранее угадать в manifest все возможные случайные позиции).
##	Файл, которого нет в manifest — "лишний" (Unexpected), тоже проваливает
##	проверку (см. постановку задачи — "факт отсутствия дополнительных").
##	2026-08-24 (найден и починен баг при ревью интернет-кода): раньше цикл
##	шёл ТОЛЬКО по тому, что прислал клиент — то есть проверялось "то, что
##	есть, совпадает" и "лишнего нет", но НИКОГДА не проверялось "а всё ли
##	из manifest клиент вообще прислал". Если посторонний просто УДАЛЯЛ уже
##	отслеживаемый файл целиком — Class_FileIntegrity.fC_ListCheckableFiles_Cr
##	на клиенте его больше не находил (файла же нет), клиент честно не мог
##	прислать по нему отпечаток — и проверка проходила как "Ok=true", хотя
##	файл из проекта пропал. Теперь после основного цикла отдельно
##	проверяется обратное направление: какие пути из manifest НЕ встретились
##	среди присланных клиентом путей — они уходят в новый список "Missing" и
##	тоже проваливают проверку
func _fC_HandleCheckFilesRequest_Ch(vGD_Envelope_D: Dictionary, vGF_ReceivedNowAt_F: float, vGS_ReplyRoutingKey_S: String) -> void:
	var vGD_Messages_D: Dictionary = vGD_Envelope_D.get("Messages", {})
	var vGA_Files_A: Array = vGD_Messages_D.get("Files", [])
	var vGD_Manifest_D: Dictionary = _vGL_Json.fxG_LoadJson_Cr(FILE_MANIFEST_S)

	var vGB_Ok_Bv := true
	var vGA_Mismatches_A := []
	var vGA_Unexpected_A := []
	var vGD_SentPaths_D := {} # используется как множество — только сами ключи важны

	for elGV_Entry in vGA_Files_A:
		if not (elGV_Entry is Dictionary):
			continue
		var vGD_Entry_D: Dictionary = elGV_Entry
		var vGS_Path_S: String = String(vGD_Entry_D.get("Path", ""))
		vGD_SentPaths_D[vGS_Path_S] = true

		if not vGD_Manifest_D.has(vGS_Path_S):
			vGA_Unexpected_A.append(vGS_Path_S)
			vGB_Ok_Bv = false
			continue

		var vGD_Expected_D: Dictionary = vGD_Manifest_D[vGS_Path_S]
		var vGB_SizeOk_Bv: bool = int(vGD_Entry_D.get("Size", -1)) == int(vGD_Expected_D.get("Size", -2))

		var vGI_RandomIndex_I: int = int(vGD_Entry_D.get("RandomIndex", -1))
		var vGI_ClaimedRandomByte_I: int = int(vGD_Entry_D.get("RandomByte", -1))
		var vGI_ActualRandomByte_I := Class_FileIntegrity.fC_ReadByteAt_I(vGS_Path_S, vGI_RandomIndex_I)
		var vGB_RandomOk_Bv: bool = vGI_ActualRandomByte_I == vGI_ClaimedRandomByte_I

		if not (vGB_SizeOk_Bv and vGB_RandomOk_Bv):
			vGB_Ok_Bv = false
			vGA_Mismatches_A.append(vGS_Path_S)

	var vGA_Missing_A := []
	for elGS_ManifestPath_S in vGD_Manifest_D.keys():
		if not vGD_SentPaths_D.has(elGS_ManifestPath_S):
			vGA_Missing_A.append(elGS_ManifestPath_S)
			vGB_Ok_Bv = false

	var vGD_AnswerTo_D := {"UserID": vGD_Envelope_D.get("UserID", ""), "Time": vGD_Envelope_D.get("Time", 0.0), "OperationNumber": vGD_Envelope_D.get("OperationNumber", -1)}
	Class_InternetServer.fC_SendingMessage_Cr("CheckFilesResult", {"Ok": vGB_Ok_Bv, "Mismatches": vGA_Mismatches_A, "Unexpected": vGA_Unexpected_A, "Missing": vGA_Missing_A}, vGD_AnswerTo_D, vGS_ReplyRoutingKey_S, false, 5.0, [1.0, 3.0, 7.0], "", vGF_ReceivedNowAt_F)
