extends RefCounted

class_name Class_FileIntegrity

##Версия оформления: 0.1.1.0
##2026-08-23 - mzs7 - первая версия — общая логика для проверки "ThirdPartyFiles"
##	(см. План проекта/Class_Internet.md → «После установления соединения»).
##	Переиспользуется и клиентом (Start_Program.gd — строит отпечатки, что
##	слать серверу), и сервером (test.gd — строит manifest И проверяет
##	присланные отпечатки). Все функции static — вызывать как
##	Class_FileIntegrity.fC_..., без load(...).new().
##	⚠️ Отпечаток — размер + первый/последний БАЙТ + один случайный байт (со
##	своим индексом, выбирается заново при каждом вызове fC_BuildFingerprint_Cr —
##	спот-проверка, а не полный хеш, см. постановку задачи от пользователя).
##	Байты, а не символы: PackedByteArray индексируется по байтам, а один байт
##	многобайтовой UTF-8-последовательности — не самостоятельный символ. Раз обе
##	стороны читают одни и те же СЫРЫЕ байты одним и тем же способом, для
##	сравнения (не для отображения текста!) это ничем не хуже символов и проще.
##	⚠️ Код не запускался живьём в Godot.
##2026-08-24 - mzs7 - найден и починен баг при ревью интернет-кода (по
##	просьбе пользователя "давай создадим проверку кода для интернет
##	соединения"): fC_BuildFingerprint_Cr/fC_BuildManifestEntry_Cr отличали
##	"файл не удалось прочитать" от "файл существует, но пустой (0 байт)" ПО
##	ОДНОМУ И ТОМУ ЖЕ признаку — is_empty() у прочитанных байт, — хотя
##	FileAccess.get_file_as_bytes() возвращает пустой PackedByteArray в ОБОИХ
##	случаях. Оба случая раньше возвращали {} → отпечаток такого файла
##	просто ВЫПАДАЛ из списка, отправляемого на проверку (см.
##	Start_Program._fC_SendFileIntegrityCheckRequest_Ch — берёт только
##	непустые словари). Итог: если посторонний ОПУСТОШИТ (усечёт до 0 байт)
##	уже отслеживаемый файл — вместо честного "Mismatch" (несовпадение
##	размера с manifest) файл просто ПЕРЕСТАВАЛ ПОПАДАТЬ в список
##	отправляемых клиентом путей — то есть исчезал из проверки целиком,
##	вместо того чтобы быть пойманным как изменённый. Теперь функции сперва
##	проверяют FileAccess.file_exists() — {} возвращается ТОЛЬКО если файла
##	действительно нет; для пустого-но-существующего файла возвращается
##	честная запись с Size=0 (Byte-поля — сентинел -1, т.к. индексировать
##	нечего) — такой файл снова участвует в сравнении и корректно ловится как
##	Mismatch, если manifest ожидал ненулевой размер

## Папки, которые НЕ считаются частью проверяемого набора — индивидуальные/
## пер-инсталляционные данные (Settings/AccountsList/логи/серверная БД
## пользователей и т.п., см. Save/) + служебные папки, которых нет в собранной
## игре, но которые видны через res://, пока проект запущен НЕ из экспорта
const EXCLUDED_PREFIXES_A := ["res://Save/", "res://.godot/", "res://.import/", "res://.git/"]


##Функционал:
##	Рекурсивно обходит res:// (или указанный корень) и возвращает список путей
##	файлов, которые ПОДЛЕЖАТ проверке целостности (см. EXCLUDED_PREFIXES_A).
##	⚠️ "Все не индивидуальные" — сегодняшний охват (см. открытый вопрос в
##	План проекта/Class_Internet.md про сужение до "известных серверу" позже)
##Форматы данных:
##	Входные: vGS_Root_S: String — с чего начать (по умолчанию "res://")
##	Выходные: Array — res://-пути (String)
static func fC_ListCheckableFiles_Cr(vGS_Root_S: String = "res://") -> Array:
	var vGA_Result_A: Array = []
	_fL_WalkDirectory_Ch(vGS_Root_S, vGA_Result_A)
	return vGA_Result_A


##Функционал:
##	Служебная — рекурсивный обход одной директории (см. fC_ListCheckableFiles_Cr)
static func _fL_WalkDirectory_Ch(vGS_Path_S: String, vGA_Result_A: Array) -> void:
	var vGL_Dir_L := DirAccess.open(vGS_Path_S)
	if vGL_Dir_L == null:
		return

	vGL_Dir_L.list_dir_begin()
	var vGS_Name_S := vGL_Dir_L.get_next()
	while vGS_Name_S != "":
		if vGS_Name_S == "." or vGS_Name_S == "..":
			vGS_Name_S = vGL_Dir_L.get_next()
			continue

		var vGS_FullPath_S := vGS_Path_S.path_join(vGS_Name_S)
		if vGL_Dir_L.current_is_dir():
			if not _fL_IsExcluded_Bv(vGS_FullPath_S + "/"):
				_fL_WalkDirectory_Ch(vGS_FullPath_S, vGA_Result_A)
		else:
			if not _fL_IsExcluded_Bv(vGS_FullPath_S):
				vGA_Result_A.append(vGS_FullPath_S)

		vGS_Name_S = vGL_Dir_L.get_next()
	vGL_Dir_L.list_dir_end()


##Функционал:
##	Служебная — проверяет префиксы-исключения (см. EXCLUDED_PREFIXES_A)
static func _fL_IsExcluded_Bv(vGS_Path_S: String) -> bool:
	for elGS_Prefix_S in EXCLUDED_PREFIXES_A:
		if vGS_Path_S.begins_with(elGS_Prefix_S):
			return true
	return false


##Функционал:
##	Читает файл целиком и строит его "отпечаток" для отправки на проверку —
##	размер, первый/последний байт и ОДИН случайный байт (со своим индексом,
##	выбирается заново при каждом вызове — см. changelog выше)
##Форматы данных:
##	Выходные: Dictionary — {"Path","Size","FirstByte","LastByte","RandomIndex",
##		"RandomByte"} или {} ТОЛЬКО если файла реально нет (см. changelog
##		2026-08-24 — пустой-но-существующий файл больше не путается с
##		отсутствующим). Для пустого файла Size=0, Byte-поля = -1 (сентинел,
##		индексировать нечего, см. fC_ReadByteAt_I ниже)
static func fC_BuildFingerprint_Cr(vGS_Path_S: String) -> Dictionary:
	if not FileAccess.file_exists(vGS_Path_S):
		return {}

	var vGA_Bytes_By := FileAccess.get_file_as_bytes(vGS_Path_S)
	var vGI_Size_I := vGA_Bytes_By.size()
	if vGI_Size_I == 0:
		return {"Path": vGS_Path_S, "Size": 0, "FirstByte": -1, "LastByte": -1, "RandomIndex": -1, "RandomByte": -1}

	var vGI_RandomIndex_I := randi() % vGI_Size_I
	return {
		"Path": vGS_Path_S,
		"Size": vGI_Size_I,
		"FirstByte": vGA_Bytes_By[0],
		"LastByte": vGA_Bytes_By[vGI_Size_I - 1],
		"RandomIndex": vGI_RandomIndex_I,
		"RandomByte": vGA_Bytes_By[vGI_RandomIndex_I],
	}


##Функционал:
##	Строит статическую запись manifest'а для одного файла — БЕЗ случайного
##	байта (тот выбирается заново каждой проверкой на стороне клиента, см.
##	fC_BuildFingerprint_Cr) — только размер + первый/последний байт, для
##	быстрой базовой сверки "по таблице" (см. постановку задачи от пользователя).
##	{} ТОЛЬКО если файла реально нет — см. тот же changelog 2026-08-24, что и
##	у fC_BuildFingerprint_Cr выше
static func fC_BuildManifestEntry_Cr(vGS_Path_S: String) -> Dictionary:
	if not FileAccess.file_exists(vGS_Path_S):
		return {}
	var vGA_Bytes_By := FileAccess.get_file_as_bytes(vGS_Path_S)
	var vGI_Size_I := vGA_Bytes_By.size()
	if vGI_Size_I == 0:
		return {"Size": 0, "FirstByte": -1, "LastByte": -1}
	return {
		"Size": vGI_Size_I,
		"FirstByte": vGA_Bytes_By[0],
		"LastByte": vGA_Bytes_By[vGI_Size_I - 1],
	}


##Функционал:
##	Серверная сторона — читает РЕАЛЬНЫЙ файл (в текущей dev-схеме сервер
##	работает из того же проекта, что и клиент, см. changelog test.gd) и
##	возвращает байт по указанному индексу — для проверки случайного байта,
##	присланного клиентом ("нахождение символов" из постановки задачи).
##	-1, если индекс вне диапазона/файл не прочитать (никогда не совпадёт с
##	настоящим байтом 0..255 — безопасное значение "точно не совпало")
static func fC_ReadByteAt_I(vGS_Path_S: String, vGI_Index_I: int) -> int:
	var vGA_Bytes_By := FileAccess.get_file_as_bytes(vGS_Path_S)
	if vGI_Index_I < 0 or vGI_Index_I >= vGA_Bytes_By.size():
		return -1
	return vGA_Bytes_By[vGI_Index_I]
