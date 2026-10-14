extends Node

class_name Class_Logger

##Версия оформления: 1.0.0.0
##2026-07-22 - mzs7 - структурная переработка: потоки как словарь, автолог создания/завершения
##	потока, единый запуск логгера (fxG_StartingLogger_CrTr)
##2026-08-09 - mzs7 - добавлены построчные комментарии к блокам и if/while внутри функций
##2026-08-18 - mzs7 - fC_RegisterStream_Cr теперь сразу после регистрации потока
##	вызывает ещё и fC_Saving_Logs_Ch() (раньше сохранялся немедленно только реестр
##	через _fL_SaveStramingPath_Ch, а сам файл лога — только при fC_FinishStream_Ch
##	или переполнении буфера). Проявилось как реальный краш в Start_Program.gd:
##	её честная проверка "логгер работает" смотрит FileAccess.file_exists(FileLogger)
##	сразу после fC_RegisterStream_Cr — а файла на диске ещё физически не было,
##	хотя логгер работал нормально. Файл лога всё-таки появлялся, но только потому,
##	что обработчик фатальной ошибки сам вызывает fC_Saving_Logs_Ch() перед
##	выходом — то есть уже ПОСЛЕ того, как программа ошибочно решила, что логгер
##	не работает. Теперь файл лога гарантированно физически существует на диске
##	сразу по возврату из fC_RegisterStream_Cr — для ЛЮБОГО потока, а не только
##	для конкретной проверки в Start_Program.gd
##2026-08-22 - mzs7 - ⚠️ лимиты очистки логов (возраст/объём папки, теперь и
##	количество файлов) БОЛЬШЕ НЕ захардкожены — читаются из Settings.json
##	(категория "Логи и реплеи" в окне Настроек, Start_Program.gd — она же
##	пишет туда LogMaxCount(Enabled)/LogMaxAgeDays(Enabled)/LogMaxSizeMB(Enabled),
##	см. её _fC_LoadSettings_Cr) — обратная связь: "сделай так, чтобы логи брали
##	настройки из Settings". Новая fC_LoadLogSettings_Ch() — свой отдельный
##	Class_Json (уже был), тот же путь FileSettings, что и у Start_Program.gd,
##	но полностью независимое чтение — Class_Logger ничего не знает про
##	vXD_Settings_D и не обязан ждать, пока Start_Program его прочитает; если
##	файла/ключей ещё нет на диске (самый первый запуск, Настройки ни разу не
##	открывались) — тихо остаётся на значениях по умолчанию (те же 100/30/50,
##	что и у Start_Program.gd, чтобы поведение "до первого открытия Настроек" и
##	"после" не отличалось). Вызывается в начале fxG_StartingLogger_CrTr, ДО
##	fxG_Resetting_FileLogger_Ch — то есть лимиты подхватываются заново при
##	КАЖДОМ старте программы, а очистка по ним применяется на СЛЕДУЮЩЕМ старте
##	после того, как их поменяли в Настройках (не мгновенно посреди сессии —
##	жёстко удалять файлы в момент, когда пользователь просто печатает новое
##	число в поле, было бы неожиданно и агрессивно). Добавлена ТРЕТЬЯ ось
##	очистки — по количеству файлов (LogMaxCount/LogMaxCountEnabled), раньше
##	было только возраст+объём; у каждой из 3 осей теперь свой Enabled-флаг —
##	галочка "выключено" в Настройках реально отключает именно эту проверку,
##	а не просто визуальная бутафория. Реплеи (FolderReplays/ReplayMax*) НЕ
##	трогал — Class_Logger в эту папку пока вообще ничего не пишет (см.
##	ReplayReader — незаконченная заглушка), настройки для неё уже есть в
##	Settings.json, но подключать их сейчас нечему; попросили именно "логи"

var Class_Help = load("res://Godot_Template/Class_Help.gd").new()
var Class_Json = load("res://Godot_Template/Class_Json.gd").new()

## Папка, где лежат файлы логов текущей и прошлых сессий (только они — не реестр и не реплеи)
var FolderLogger := "res://Save/Logger/Logs/"
## Папка с реплеями — заполняется данными, которые присылает сервер;
## сам Class_Logger в неё пока ничего не пишет (только зарезервировано под ReplayReader)
var FolderReplays := "res://Save/Logger/Replays/"
## Реестр потоков — что было активно/завершено в текущей (а до старта — в прошлой) сессии.
## Лежит прямо в Save/Logger/, а не в Logs/ — это не сам лог, а служебный указатель на него
var FileStraming_path := "res://Save/Logger/Straming_path.json"
## Файл лога текущей сессии — назначается заново в fxG_StartingLogger_CrTr
var FileLogger := ""
## 2026-08-22: путь к общему Settings.json — тот же файл, что читает/пишет
## Start_Program.gd (см. её FileSettings), только читается ЗДЕСЬ отдельно,
## своим Class_Json — см. fC_LoadLogSettings_Ch
var FileSettings := "res://Save/Settings.json"

## Потоки: {StreamId: {"name":, "started_at":, "status": "active"/"finished"}}
var Straming_path := {}
## Буфер записей по потокам, ждущих сброса на диск: {StreamId: [запись, запись, ...]}
var LogBuffer := {}

## 2026-08-14: накопленное содержимое ТЕКУЩЕГО FileLogger в памяти — см. fC_Saving_Logs_Ch.
## Заполняется с диска максимум один раз на каждую смену FileLogger, дальше только
## дополняется в памяти, без повторного чтения/парсинга уже написанного
var _GD_SessionStreamsCache := {}
## Для какого именно FileLogger сейчас актуален _GD_SessionStreamsCache — если FileLogger
## поменялся (новая сессия / дозапись старой), кэш нужно перечитать с диска заново
var _GS_CachedForFile := ""

## Счётчик для генерации уникальных StreamId в рамках сессии
var vGI_NextStreamId := 0

## Через сколько записей в буфере ОДНОГО потока делать автосброс на диск
## 2026-08-14: было временно снижено с 10 до 1 для отладки предполагаемого краша в
## test_performance() — возвращено обратно на 10. Причина отката: fC_Saving_Logs_Ch при
## каждом сбросе перечитывает ВЕСЬ существующий файл лога, декодирует JSON, дописывает и
## перезаписывает файл ЦЕЛИКОМ (см. её komментарии ниже) — это O(n) на каждый сброс. При
## FrequencyUpdates=1 и одновременно включённом логировании ВНУТРИ 1000-итерационного цикла
## test_performance() (см. правки в Class_ArrayAndOrDictionary.gd от того же дня) это дало
## O(n²) и лог вырос до 49МБ за один прогон — сам файл почти наверняка и "положил" программу
## (не логика сравнения и не ОС, убивающая "простаивающий" процесс — процесс был максимально
## занят перезаписью разрастающегося файла). Настоящий баг (см. UniversalBypass — не хватало
## PathArray.pop_back() в ветке "Deeper") найден и починен независимо от этого — он был не
## связан с логированием вообще, просто без реального лога/трейса не был виден
var FrequencyUpdates := 10
## Зарезервировано под будущий сброс по таймеру (нужен Node в дереве сцены — пока не подключено)
var TimeUpdate := 1.0

## 2026-08-22: настройки очистки старых логов — БОЛЬШЕ НЕ захардкожены,
## читаются из Settings.json (см. fC_LoadLogSettings_Ch, вызывается из
## fxG_StartingLogger_CrTr при каждом старте программы). Значения ниже —
## только дефолты НА СЛУЧАЙ, если файла/ключей ещё нет на диске (те же
## числа, что и у Start_Program.gd._fC_LoadSettings_Cr, чтобы поведение "до
## первого открытия Настроек" совпадало с "после" — см. её changelog)
var vGB_LogMaxCountEnabled := true
var vGI_LogMaxCount := 100
var vGB_LogMaxAgeEnabled := true
var vGI_MaxLogAgeDays := 30
var vGB_LogMaxSizeEnabled := true
var vGI_MaxLogFolderSizeMb := 50


##Функционал:
##	Единая точка входа при старте программы. Проверяет, что лог прошлой сессии
##	сохранён целиком (при необходимости дозаписывает в него незавершённые потоки),
##	затем чистит устаревшие файлы логов и запускает новую сессию
##Форматы данных:
##	Входные:
##		vGS_Role: String — роль сессии, "user" или "server" (по умолчанию "user")
##	Выходные:
##		нет
##Принцип работы:
##	1. Загружает реестр потоков прошлой сессии (если есть) вместе с именем её файла лога
##	2. Для каждого потока, оставшегося "active" (то есть поток не был завершён штатно —
##		следствие вылета/аварийного закрытия), дописывает в СТАРЫЙ файл лога закрывающую
##		запись и сохраняет — тем самым старый лог гарантированно сохранён целиком
##	3. Только после этого очищает реестр потоков в памяти
##	3.5. Перечитывает лимиты очистки из Settings.json (см. fC_LoadLogSettings_Ch)
##	4. Удаляет устаревшие файлы логов по количеству/возрасту/объёму папки
##	5. Назначает файл лога новой сессии и регистрирует служебный поток "System"
##
## КАК ПОЛЬЗОВАТЬСЯ (программисту):
##	Вызвать РОВНО ОДИН РАЗ при старте программы (например, в _ready() стартовой сцены),
##	до любых других вызовов Class_Logger. Дальше просто работать с потоками — см.
##	fC_RegisterStream_Cr / fC_Adding_Buffer_Cr / fC_FinishStream_Ch.
func fxG_StartingLogger_CrTr(vGS_Role: String = "user") -> void:
	# Блок 0: обнуляем рабочее состояние в памяти перед тем как что-либо грузить с диска
	Straming_path = {}
	LogBuffer = {}
	vGI_NextStreamId = 0
	# 2026-08-14: сбрасываем и кэш fC_Saving_Logs_Ch — на новый/старый FileLogger он всё
	# равно перечитается сам (см. её "_GS_CachedForFile != FileLogger"), но явный сброс
	# здесь на всякий случай, чтобы не держать в памяти данные закрывшейся сессии
	_GD_SessionStreamsCache = {}
	_GS_CachedForFile = ""

	## 1-2. Проверяем и, если нужно, дозаписываем лог прошлой сессии
	# if: реестр прошлой сессии вообще существует на диске (первый запуск программы — не существует)
	if FileAccess.file_exists(FileStraming_path):
		var vGD_Old: Dictionary = Class_Json.fxG_LoadJson_Cr(FileStraming_path)
		var vGD_OldStreams: Dictionary = vGD_Old.get("Streams", {})
		var vGS_OldSessionFile: String = vGD_Old.get("SessionFile", "")

		# if: в реестре реально указан файл лога прошлой сессии (а не пустая/битая запись)
		if vGS_OldSessionFile != "":
			# Блок: временно подставляем данные прошлой сессии в рабочие переменные,
			# чтобы дозапись ушла в ЕЁ файл, а не создавала новый файл раньше времени
			Straming_path = vGD_OldStreams
			LogBuffer = {}
			FileLogger = vGS_OldSessionFile

			# for: проходим по всем потокам прошлой сессии
			for elS_StreamId in Straming_path:
				# if: поток остался "active" — значит fC_FinishStream_Ch для него не вызывали,
				# то есть программа завершилась (вылетела) пока поток был открыт
				if Straming_path[elS_StreamId].get("status", "") != "finished":
					# Действие: дописываем в буфер этого потока запись-индикатор незавершения
					fC_Adding_Buffer_Cr(
						elS_StreamId,
						"Stream was not finished properly — appended on next startup",
						[],
						null
					)
					# Действие: принудительно закрываем поток в реестре, чтобы при
					# следующем запуске он не попал в эту же обработку повторно
					Straming_path[elS_StreamId]["status"] = "finished"

			# Действие: физически сбрасываем всё накопленное (включая индикаторы незавершения)
			# в СТАРЫЙ FileLogger — старая сессия закрывается её собственным файлом
			fC_Saving_Logs_Ch()

	## 3. Старый лог сохранён целиком — реестр и буфер можно очищать
	# Блок: второй раз чистим память — теперь уже окончательно, старые данные не нужны
	Straming_path = {}
	LogBuffer = {}

	## 3.5. Перечитываем лимиты очистки из Settings.json — ДО самой очистки,
	## чтобы она сразу использовала актуальные значения (2026-08-22)
	fC_LoadLogSettings_Ch()

	## 4. Удаляем устаревшие файлы логов
	fxG_Resetting_FileLogger_Ch()

	## 5. Запускаем новую сессию
	# Блок: собираем имя файла новой сессии из роли и текущего календарного времени
	var vGD_Now := Time.get_datetime_dict_from_system()
	var vGS_Timestamp := "%04d-%02d-%02d_%02d-%02d-%02d" % [
		vGD_Now["year"], vGD_Now["month"], vGD_Now["day"],
		vGD_Now["hour"], vGD_Now["minute"], vGD_Now["second"]
	]
	FileLogger = FolderLogger + "Logger_%s_%s.log" % [vGS_Role, vGS_Timestamp]

	# Действие: с первой секунды сессии всегда есть минимум один активный поток — "System"
	fC_RegisterStream_Cr("System")


##Функционал:
##	Регистрирует новый поток — независимую цепочку задач, не пересекающуюся
##	с другими потоками до своего завершения (может считаться параллельно с ними)
##Форматы данных:
##	Входные:
##		vCS_Name: String — понятное имя потока (для чего он нужен)
##	Выходные:
##		String — уникальный StreamId; передаётся дальше во все вызовы
##			fC_Adding_Buffer_Cr / fC_FinishStream_Ch для этого потока
##Принцип работы:
##	1. Генерирует уникальный StreamId
##	2. Заводит запись потока в Straming_path со статусом "active"
##	3. Заводит пустой буфер для потока в LogBuffer
##	4. Первой записью в буфер потока пишет сам факт его создания
##
## КАК ПОЛЬЗОВАТЬСЯ (программисту):
##	Вызывать в начале каждой независимой цепочки задач (экран, загрузка, фоновая операция —
##	то, что не пересекается с другими такими же цепочками до своего завершения). Полученный
##	StreamId сохранить в переменную и передавать во все fC_Adding_Buffer_Cr / fC_FinishStream_Ch
##	для этой цепочки. Один StreamId — один логический поток; параллельно можно вести сколько
##	угодно потоков одновременно.
func fC_RegisterStream_Cr(vCS_Name: String) -> String:
	# Блок: генерируем id как строку из растущего счётчика (ключи словарей — только String)
	var vCS_StreamId := str(vGI_NextStreamId)
	vGI_NextStreamId += 1

	# Блок: заводим метаданные потока в реестре — статус сразу "active"
	Straming_path[vCS_StreamId] = {
		"name": vCS_Name,
		"started_at": Time.get_ticks_usec(),
		"status": "active"
	}
	# Действие: заводим отдельный пустой буфер именно для этого потока
	LogBuffer[vCS_StreamId] = []

	# Действие: первая запись в потоке — всегда факт его создания
	fC_Adding_Buffer_Cr(vCS_StreamId, "Stream created: " + vCS_Name, [], null)
	# Действие: сохраняем реестр на диск немедленно — если программа упадёт сразу
	# после регистрации, на диске уже будет видно, что поток создан и не завершён
	_fL_SaveStramingPath_Ch()
	# Действие: сразу же физически сбрасываем и сам файл лога (не только реестр) —
	# без этого FileLogger был бы просто строкой в памяти до первого
	# fC_FinishStream_Ch/переполнения буфера, а любой код, честно проверяющий
	# "логгер реально работает" через FileAccess.file_exists(FileLogger) сразу
	# после регистрации потока (см. Start_Program.gd, changelog 2026-08-18), видел
	# бы файл ещё не созданным — даже когда логгер работает нормально
	fC_Saving_Logs_Ch()

	return vCS_StreamId


##Функционал:
##	Корректно завершает поток: перед сохранением пишет в его буфер запись
##	о завершении, помечает поток завершённым и сохраняет буфер на диск
##Форматы данных:
##	Входные:
##		vCS_StreamId: String — id потока, полученный от fC_RegisterStream_Cr
##	Выходные:
##		нет
##Принцип работы:
##	1. Пишет в буфер потока запись о завершении — последней записью потока
##	2. Меняет статус потока на "finished" и сохраняет обновлённый реестр
##	3. Сохраняет буфер (в т.ч. этот поток) в файл лога
##
## КАК ПОЛЬЗОВАТЬСЯ (программисту):
##	Вызывать РОВНО ОДИН РАЗ в конце цепочки задач, которую открыли через
##	fC_RegisterStream_Cr, передав тот же StreamId. Если этого не сделать (например,
##	из-за краша) — при следующем fxG_StartingLogger_CrTr поток будет автоматически
##	закрыт как незавершённый (см. её описание).
func fC_FinishStream_Ch(vCS_StreamId: String) -> void:
	# if: защита от неправильного/уже несуществующего StreamId — не роняем программу,
	# просто предупреждаем в консоль и выходим
	if not Straming_path.has(vCS_StreamId):
		push_warning("⚠️ fC_FinishStream_Ch: stream not found — %s" % vCS_StreamId)
		return

	# Блок: пишем финальную запись потока (пока ещё только в буфер, не на диск)
	var vCS_Name: String = Straming_path[vCS_StreamId]["name"]
	fC_Adding_Buffer_Cr(vCS_StreamId, "Stream finished: " + vCS_Name, [], null)

	# Блок: помечаем поток завершённым и сразу сохраняем реестр — важно сделать
	# это ДО fC_Saving_Logs_Ch, чтобы при сбое между этими строками на диске уже
	# было видно, что поток закрыт штатно, а не завис
	Straming_path[vCS_StreamId]["status"] = "finished"
	_fL_SaveStramingPath_Ch()

	# Действие: физически дописываем буфер (включая финальную запись) в файл лога
	fC_Saving_Logs_Ch()


##Функционал:
##	Добавляет одну запись в буфер указанного потока
##Форматы данных:
##	Входные:
##		vCS_StreamId: String — id потока
##		vCS_Code: String — описание точки лога ("if A and B", "func A(A,B,C)", "A = B.func()")
##		vCA_Values: Array — значения переменных, относящихся к этой записи
##		vC_Other — доп. информация (например, результат if); null, если не нужна
##	Выходные:
##		нет
##Принцип работы:
##	Собирает запись в формате [Время, Код, Значения, Другое] и кладёт в LogBuffer[StreamId];
##	если буфер потока переполнен (>= FrequencyUpdates) — сразу сбрасывает его на диск
##
## КАК ПОЛЬЗОВАТЬСЯ (программисту):
##	Вызывать вручную в каждой точке ветвления кода, которую хотите видеть в логе:
##	перед/после if, при входе в функцию, при изменении значимой переменной и т.п.
##	Передавать StreamId, полученный от fC_RegisterStream_Cr для текущей цепочки задач.
##	Текст vCS_Code и всё, что уходит в лог — писать на английском.
func fC_Adding_Buffer_Cr(vCS_StreamId: String, vCS_Code: String, vCA_Values: Array, vC_Other = null) -> void:
	# if: страховка — буфер для этого StreamId ещё не заводили (не должно случаться
	# в нормальном потоке работы, но не роняем программу, если случилось)
	if not LogBuffer.has(vCS_StreamId):
		LogBuffer[vCS_StreamId] = []

	# Действие: добавляем запись строго в формате [Время, Код, Значения, Другое]
	LogBuffer[vCS_StreamId].append([Time.get_ticks_usec(), vCS_Code, vCA_Values, vC_Other])

	# if: буфер конкретно этого потока переполнен — автосброс всего LogBuffer на диск,
	# не дожидаясь ручной команды или таймера
	if LogBuffer[vCS_StreamId].size() >= FrequencyUpdates:
		fC_Saving_Logs_Ch()


##Функционал:
##	Сбрасывает накопленный буфер всех потоков в файл лога текущей сессии
##Форматы данных:
##	Входные: нет (использует LogBuffer, FileLogger, _GD_SessionStreamsCache)
##	Выходные: нет
##Принцип работы:
##	1. Если _GD_SessionStreamsCache ещё не соответствует текущему FileLogger (первый сброс
##	   после смены файла — новая сессия или дозапись старой) — загружает то, что уже
##	   накоплено В ФАЙЛЕ, В ПАМЯТЬ ровно один раз
##	2. Дописывает к каждому потоку новые записи из LogBuffer ПРЯМО В КЭШ (без диска)
##	3. Сохраняет ВЕСЬ кэш обратно в файл одним словарём {"Streams": {...}}
##	4. Очищает буфер в памяти (кэш — не буфер, он не чистится, копится всю сессию)
##
## КАК ПОЛЬЗОВАТЬСЯ (программисту):
##	Обычно вызывать не нужно вручную — вызывается автоматически из fC_Adding_Buffer_Cr
##	(при переполнении), fC_RegisterStream_Cr/fC_FinishStream_Ch (через сохранение реестра)
##	и fxG_StartingLogger_CrTr. Можно вызвать вручную, если нужно принудительно
##	сбросить буфер на диск прямо сейчас (например, перед заведомо рискованной операцией).
##
## 2026-08-14: раньше на КАЖДЫЙ сброс здесь заново читался и парсился ВЕСЬ файл лога с диска
## (см. чат — "Программа вылетела" на большом логе). Для маленьких логов не заметно, но чем
## больше файл — тем дороже КАЖДЫЙ следующий сброс: O(текущий размер файла) на вызов, а
## вызовов за сессию много (см. FrequencyUpdates) — суммарно O(n²) от итогового объёма лога.
## На логе в десятки МБ это выглядело как зависшая/упавшая программа. Теперь читаем с диска
## максимум ОДИН раз на каждую смену FileLogger — дальше держим накопленное в памяти
## (_GD_SessionStreamsCache) и только дополняем его. Финальная запись на диск (сам
## Class_Json.fxG_SaveJson_Ch) всё ещё перезаписывает файл целиком за один вызов — это
## неизбежно при JSON-формате "один словарь на файл", но она была НЕ основной частью
## проблемы (запись быстрее, чем чтение+парсинг того же объёма)
func fC_Saving_Logs_Ch() -> void:
	# if: нечего сохранять — сессия ещё не начата или буфер пуст; ранний выход,
	# чтобы не делать лишние чтения/записи файла на пустом месте
	if FileLogger == "" or LogBuffer.is_empty():
		return

	# if: кэш ещё не соответствует текущему FileLogger — читаем с диска РОВНО ОДИН раз
	# (первый сброс после fxG_StartingLogger_CrTr, либо после смены FileLogger на дозапись
	# прошлой сессии) — все последующие сбросы для ЭТОГО ЖЕ FileLogger диск не трогают
	if _GS_CachedForFile != FileLogger:
		var vGD_Existing := {}
		if FileAccess.file_exists(FileLogger):
			vGD_Existing = Class_Json.fxG_LoadJson_Cr(FileLogger)
		_GD_SessionStreamsCache = vGD_Existing.get("Streams", {})
		_GS_CachedForFile = FileLogger

	# for: проходим по каждому потоку, накопившему записи в буфере
	for elS_StreamId in LogBuffer:
		# if: у этого потока в буфере пусто (уже сбрасывали или ничего не добавляли) — пропускаем
		if LogBuffer[elS_StreamId].is_empty():
			continue
		# if: для этого потока в кэше ещё вообще ничего нет — заводим пустой массив,
		# чтобы было куда дописывать
		if not _GD_SessionStreamsCache.has(elS_StreamId):
			_GD_SessionStreamsCache[elS_StreamId] = []
		# Действие: дописываем новые записи в конец уже накопленных в кэше (не заменяем их)
		_GD_SessionStreamsCache[elS_StreamId].append_array(LogBuffer[elS_StreamId])

	# Действие: перезаписываем файл целиком накопленным в памяти кэшем
	Class_Json.fxG_SaveJson_Ch(FileLogger, {"Streams": _GD_SessionStreamsCache})

	# for: то, что уже физически на диске, больше не нужно держать в буфере — чистим буфер
	for elS_StreamId in LogBuffer:
		LogBuffer[elS_StreamId] = []


##Функционал:
##	Служебная функция — сохраняет текущий реестр потоков (Straming_path) на диск
##	вместе с именем файла лога текущей сессии, чтобы при следующем запуске можно
##	было проверить, всё ли было завершено штатно
##Форматы данных:
##	Входные: нет (использует Straming_path, FileLogger)
##	Выходные: нет
##
## КАК ПОЛЬЗОВАТЬСЯ (программисту):
##	Не вызывать напрямую — используется изнутри fC_RegisterStream_Cr и fC_FinishStream_Ch.
func _fL_SaveStramingPath_Ch() -> void:
	# Действие: сохраняем реестр ВМЕСТЕ с FileLogger — это единственная связка, по которой
	# fxG_StartingLogger_CrTr при следующем запуске понимает, в какой файл дозаписывать
	Class_Json.fxG_SaveJson_Ch(FileStraming_path, {"SessionFile": FileLogger, "Streams": Straming_path})


##Функционал:
##	Перечитывает лимиты очистки логов из Settings.json — количество/возраст/
##	объём памяти и их Enabled-флаги (категория "Логи и реплеи" в окне
##	Настроек, Start_Program.gd). 2026-08-22, обратная связь: "сделай так,
##	чтобы логи брали настройки из Settings"
##Форматы данных:
##	Входные: нет
##	Выходные: нет
##Принцип работы:
##	Читает тот же Settings.json, что и Start_Program.gd (свой отдельный
##	Class_Json, тот же путь FileSettings) — если файла или отдельных ключей
##	ещё нет (самый первый запуск, Настройки ни разу не открывались), просто
##	оставляет значения по умолчанию, объявленные выше как var (те же числа,
##	что и у Start_Program.gd._fC_LoadSettings_Cr)
##
## КАК ПОЛЬЗОВАТЬСЯ (программисту):
##	Не вызывать напрямую — вызывается изнутри fxG_StartingLogger_CrTr, ДО
##	fxG_Resetting_FileLogger_Ch, при каждом старте программы.
func fC_LoadLogSettings_Ch() -> void:
	if not FileAccess.file_exists(FileSettings):
		return
	var vGD_Settings_D: Dictionary = Class_Json.fxG_LoadJson_Cr(FileSettings)
	if vGD_Settings_D.is_empty():
		return
	vGB_LogMaxCountEnabled = vGD_Settings_D.get("LogMaxCountEnabled", vGB_LogMaxCountEnabled)
	vGI_LogMaxCount = int(vGD_Settings_D.get("LogMaxCount", vGI_LogMaxCount))
	vGB_LogMaxAgeEnabled = vGD_Settings_D.get("LogMaxAgeEnabled", vGB_LogMaxAgeEnabled)
	vGI_MaxLogAgeDays = int(vGD_Settings_D.get("LogMaxAgeDays", vGI_MaxLogAgeDays))
	vGB_LogMaxSizeEnabled = vGD_Settings_D.get("LogMaxSizeEnabled", vGB_LogMaxSizeEnabled)
	vGI_MaxLogFolderSizeMb = int(vGD_Settings_D.get("LogMaxSizeMB", vGI_MaxLogFolderSizeMb))


##Функционал:
##	Удаляет устаревшие файлы логов в папке FolderLogger — по количеству,
##	возрасту и по общему объёму папки (2026-08-22: раньше было только
##	возраст+объём, количество добавлено; у каждой из 3 проверок теперь свой
##	Enabled-флаг — см. fC_LoadLogSettings_Ch)
##Форматы данных:
##	Входные: нет (использует vGB/vGI_LogMax*, см. fC_LoadLogSettings_Ch)
##	Выходные: нет
##Принцип работы:
##	1. Собирает список *.log файлов папки с временем изменения и размером
##	2. Если включено (vGB_LogMaxAgeEnabled) — удаляет файлы старше vGI_MaxLogAgeDays
##	3. Если включено (vGB_LogMaxCountEnabled) и файлов больше vGI_LogMaxCount —
##		удаляет самые старые сверх лимита
##	4. Если включено (vGB_LogMaxSizeEnabled) и оставшиеся файлы всё ещё
##		превышают vGI_MaxLogFolderSizeMb суммарно — удаляет самые старые из
##		них, пока не впишемся в лимит
##	Каждый шаг работает над тем, что ОСТАЛОСЬ после предыдущего — файл,
##	удалённый по возрасту, не участвует в проверке по количеству/объёму,
##	и т.д. Любой из 3 шагов с выключенным Enabled-флагом просто пропускается
##	целиком, ничего не удаляя по этой оси
##
## КАК ПОЛЬЗОВАТЬСЯ (программисту):
##	Не вызывать напрямую — вызывается изнутри fxG_StartingLogger_CrTr при каждом старте
##	программы, сразу после fC_LoadLogSettings_Ch.
func fxG_Resetting_FileLogger_Ch() -> void:
	# if: папки логов не существует (ещё не создана) — нечего чистить, выходим
	var vGD_Dir := DirAccess.open(FolderLogger)
	if vGD_Dir == null:
		return

	## 1. Собираем список всех *.log файлов с их размером и временем изменения
	var vGA_Files := []
	vGD_Dir.list_dir_begin()
	var vGS_FileName := vGD_Dir.get_next()
	# while: перебираем содержимое папки, пока get_next() не вернёт пустую строку (конец списка)
	while vGS_FileName != "":
		# if: пропускаем подпапки и всё, что не заканчивается на ".log" (не наш файл)
		if not vGD_Dir.current_is_dir() and vGS_FileName.ends_with(".log"):
			var vGS_FullPath := FolderLogger + vGS_FileName
			var vGI_Size := 0
			var vGL_File := FileAccess.open(vGS_FullPath, FileAccess.READ)
			# if: файл удалось открыть — узнаём размер и сразу закрываем
			if vGL_File != null:
				vGI_Size = vGL_File.get_length()
				vGL_File.close()
			# Действие: складываем метаданные файла в общий список кандидатов на удаление
			vGA_Files.append({
				"path": vGS_FullPath,
				"modified": FileAccess.get_modified_time(vGS_FullPath),
				"size": vGI_Size
			})
		vGS_FileName = vGD_Dir.get_next()
	vGD_Dir.list_dir_end()

	var vGA_Remaining := vGA_Files

	## 2. По возрасту — только если включено
	if vGB_LogMaxAgeEnabled:
		var vGI_NowSec := Time.get_unix_time_from_system()
		var vGI_MaxAgeSec := vGI_MaxLogAgeDays * 24 * 60 * 60
		var vGA_AfterAge := []
		# for: проходим по всем найденным .log файлам
		for elGD_File in vGA_Remaining:
			# if: файл старше допустимого возраста — удаляем сразу
			if vGI_NowSec - elGD_File["modified"] > vGI_MaxAgeSec:
				DirAccess.remove_absolute(elGD_File["path"])
			# else: файл ещё не устарел — переносим в список кандидатов для дальнейших проверок
			else:
				vGA_AfterAge.append(elGD_File)
		vGA_Remaining = vGA_AfterAge

	## 3. По количеству — только если включено, удаляем самые старые сверх лимита
	if vGB_LogMaxCountEnabled and vGA_Remaining.size() > vGI_LogMaxCount:
		# Действие: сортируем от самых старых к самым новым, чтобы удалять именно старые
		vGA_Remaining.sort_custom(func(a, b): return a["modified"] < b["modified"])
		var vGI_ExcessCount: int = vGA_Remaining.size() - vGI_LogMaxCount
		for elGI_Index in range(vGI_ExcessCount):
			DirAccess.remove_absolute(vGA_Remaining[elGI_Index]["path"])
		vGA_Remaining = vGA_Remaining.slice(vGI_ExcessCount)

	## 4. По суммарному объёму — только если включено, удаляем самые старые, пока не впишемся
	if vGB_LogMaxSizeEnabled:
		# Действие: сортируем оставшиеся файлы от самых старых к самым новым
		vGA_Remaining.sort_custom(func(a, b): return a["modified"] < b["modified"])
		var vGI_TotalBytes := 0
		# for: считаем суммарный размер всех оставшихся файлов
		for elGD_File in vGA_Remaining:
			vGI_TotalBytes += elGD_File["size"]

		var vGI_MaxBytes := vGI_MaxLogFolderSizeMb * 1024 * 1024
		var vGI_Index := 0
		# while: пока суммарный размер больше лимита И ещё остались файлы для удаления —
		# удаляем самый старый из оставшихся (список уже отсортирован по возрастанию времени)
		while vGI_TotalBytes > vGI_MaxBytes and vGI_Index < vGA_Remaining.size():
			vGI_TotalBytes -= vGA_Remaining[vGI_Index]["size"]
			DirAccess.remove_absolute(vGA_Remaining[vGI_Index]["path"])
			vGI_Index += 1


# ============================================================
# Ниже — без изменений, как было. Задел под будущую автоматизацию
# (автоматический разбор строки кода вместо ручных вызовов fC_Adding_Buffer_Cr).
# ============================================================

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
		var v_Bv_Continue = v__Result[0][0]		## Продолжать глобальный обход? при true -1< Уровень
		var v_Bv_ContinueFor = v__Result[0][1]	## Продолжать текущий цикл? при true 0< Уровень
		var v_Bv_GoDeeper = v__Result[0][2]		## Идти вглубь структуры? при true +1 Уровень

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

#Получения массива с указанием на симовлы с которых начинаетс комбинация в строке
func PlacesofTextLine (Descriptions: String, Set: String) -> Array:
	var ArrayOutputs = []
	if Descriptions.contains(Set):
		var whileflag1 = true
		while whileflag1:
			if ArrayOutputs == []:
				if Descriptions.contains(Set):
					ArrayOutputs.append(Descriptions.find(Set))
			else:
				var NextLocation = Descriptions.find(Set, ArrayOutputs[ArrayOutputs.size()-1])
				if NextLocation != -1:
					ArrayOutputs.append(NextLocation)
	return ArrayOutputs

#Вспомогательныая функция для fC_OvergrowthIf_Tr добовляет символы в
func New_PathOvergrowth (Parametrs):
	var Comments = Parametrs[0]

# ⚠️ Закомментировано — не используется и не компилируется как есть.
# Ошибка: `while CommentsSizeMax != CommentsSizeReall` без `:` в конце строки, и одинокое
# `is` без выражения после него. Из-за этого GDScript не может разобрать файл — ошибка
# парсинга в одной функции ломает компиляцию всего скрипта целиком, а не только её.
# Это недописанный черновик автоматического разбора строки кода (задел под будущую
# автоматизацию, см. Class_Logger.md) — оставлен закомментированным как история, а не
# исправлен и не удалён: логика внутри слишком не завершена, чтобы аккуратно починить
# синтаксис, не меняя смысл.
#ДОбовления перемещения по коду в буфер в формате (код, с значениями, результат)
#func New_Path (Descriptions: String, DictionaryVariables: Dictionary):
#	var Comments: String
#	var NumberOperationsс:= 1
#	if Descriptions.contains("if") or Descriptions.contains("while"):
#		#Сохраняем из коментария все базовые символы
#		var ArrayComparisonOperations := {
#			"==" = PlacesofTextLine(Descriptions,"=="),
#			"!=" = PlacesofTextLine(Descriptions,"!="),
#			">=" = PlacesofTextLine(Descriptions,">="),
#			"<=" = PlacesofTextLine(Descriptions,"<="),
#			">" = PlacesofTextLine(Descriptions,">"),
#			"<" = PlacesofTextLine(Descriptions,"<"),
#			"and" = PlacesofTextLine(Descriptions,"and"),
#			"or" = PlacesofTextLine(Descriptions,"or"),
#			"if" = PlacesofTextLine(Descriptions,"if"),
#			"while" = PlacesofTextLine(Descriptions,"while"),
#			"(" = PlacesofTextLine(Descriptions,"("),
#			")" = PlacesofTextLine(Descriptions,")"),
#			}
#		#Получаем все не базовые слова
#		var ResrtDescriptions = Descriptions.duplicate()
#		ResrtDescriptions
#		#Содаем
#		var CommentsSizeMax = length(ResrtDescriptions)
#		var CommentsSizeReall = 0
#		while CommentsSizeMax != CommentsSizeReall
#			fC_OvergrowthIf_Tr(ArrayComparisonOperations,{"func": New_PathOvergrowth,"Parametrs": [Comments]})
#			is
#
#	elif Descriptions.contains("for"):
#		pass

#Воспроизводства визульного состояния программы
func ReplayReader (FileLogger, TimePLay, TimeEnd, SeqPlay, SeqEnd):
	pass
