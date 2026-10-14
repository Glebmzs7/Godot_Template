extends Class_Internet

class_name Class_InternetServer

##Версия оформления: 0.3.0.0
##2026-08-22 - mzs7 - первая версия (см. историю в План проекта/Class_InternetServer.md).
##2026-08-24 - mzs7 - по просьбе пользователя добавлены: (1) WSS как опция —
##	fC_ConfigureTls_Bv/vGB_UseTls_Bv/vGD_PendingTlsConnections_D, TLS-рукопожатие
##	перед WS-рукопожатием, ничего не меняет для тех, кто TLS не настраивал;
##	(2) самостоятельная регистрация — Op "Register"/_fL_OnRegisterRequest_Ch,
##	использует уже существовавший fC_RegisterUser_Ch. Подробности — changelog
##	у самих функций ниже и План проекта/Class_Internet.md
##2026-08-23 - mzs7 - протокол доработан по итогам разбора кода и уточняющих
##	вопросов (см. changelog Class_Internet.gd и Class_InternetClient.gd —
##	fC_ReceivingNotification_Ch теперь принимает разобранный конверт одним
##	Dictionary + третий параметр vGS_RoutingKey_S, а не длинный список полей).
##	Изменения по существу:
##	1) ⚠️ ФЛОУ ПЕРЕВЁРНУТ: раньше СЕРВЕР первым слал Hello после WS-рукопожатия.
##		Теперь по новому ТЗ клиент первым шлёт Hello (с явным IP в Messages) —
##		сервер только отвечает (RequireAuth+KeepAliveTimeoutSeconds). Значит,
##		сервер больше не может полагаться на "наш собственный Hello не
##		дождался ответа — сбросить" (WaitingResponse на Hello) для отлова
##		"подключился и молчит" — вместо этого единая проверка активности в
##		_process (см. п.5) покрывает и это тоже.
##	2) Пароль в открытом виде на сервер больше НЕ передаётся — challenge-response:
##		AuthRequest → Challenge → HelloConfirm(Response) → AuthSuccess/AuthFailed
##		(см. fC_ValidateChallengeResponse_Bv и План проекта/Class_Internet.md
##		→ «Авторизация: challenge-response + токен», включая честно описанное
##		ограничение схемы — PasswordHash в базе фактически равнозначен паролю).
##	3) UserID больше не подменяется ConnId вслепую на транспортном уровне —
##		конверт передаётся в fC_ReceivingNotification_Ch как есть (заявленный
##		UserID виден), но ключ МАРШРУТИЗАЦИИ (vGS_RoutingKey_S) остаётся
##		ConnId, пока подключение не "промоутировано" на настоящий UserID —
##		см. _fL_RenameConnectionKey_Ch. Без авторизации (RequireAuth=false) —
##		промоушен сразу при первом Hello (доверять некому мешать, аккаунтов нет).
##		С авторизацией — только после успешного challenge-response. Это и
##		есть решение "смены IP при переподключении": повторный вход того же
##		UserID переименовывает ключ заново, старое соединение под этим же
##		ключом закрывается.
##	4) ⚠️ НАЙДЕНА И ПОЧИНЕНА ОШИБКА ПРИ НАПИСАНИИ: в _process нельзя менять
##		ключи vGD_ActiveConnections_D (через _fL_RenameConnectionKey_Ch)
##		ПРЯМО ВНУТРИ цикла `for x in vGD_ActiveConnections_D` по этому же
##		словарю — структурная модификация словаря во время итерации по нему
##		небезопасна. Исправлено: цикл идёт по СНИМКУ ключей (.keys()), и
##		после обработки пакета (которая могла вызвать переименование)
##		проверяется .has() перед дальнейшим использованием ключа.
##	5) Единый механизм молчания вместо ручного счётчика попыток: vGF_KeepAliveTimeoutSeconds_F
##		— и то, что сообщается клиенту, и то, чем сам сервер проверяет каждое
##		активное подключение (включая ещё не сказавшее Hello) на молчание.
##	⚠️ Логин трактуется как UserID один-в-один (см. _fL_OnHelloConfirm_Ch) —
##		упрощение для первого прохода, см. открытые вопросы.
##	⚠️ Код не запускался живьём в Godot.
##2026-08-23 - mzs7 - бывший TODO "диспетчер операций трекера — появится по
##	ходу дела" в fC_ReceivingNotification_Ch (последняя ветка match) заменён
##	на AppOpReceived_S.emit(...) (см. changelog Class_Internet.gd) — раньше
##	ЛЮБАЯ незнакомая транспорту операция считалась ошибкой клиента (Error/
##	UnknownOp), теперь такие операции считаются ПРИКЛАДНЫМИ (обрабатываются
##	снаружи, см. test.gd → _fC_OnServerAppOpReceived_Ch, используется для
##	"CheckUpdate"/"CheckFiles") — если и там операция окажется незнакомой,
##	ответственность сообщить об этом клиенту теперь на слушателе сигнала, а
##	не на этом транспортном уровне.

## Собственный UserID сервера при отправке сообщений
const SERVER_SELF_USERID_S := "Server"

var _vGL_Json_L = load("res://Godot_Template/Class_Json.gd").new()
const FileUsers_S := "res://Save/Server/Users.json"

var _vGL_TcpServer: TCPServer = null

## true — глобальный сервер (нужны логин/пароль), false — сервер игрока (по умолчанию)
var vGB_RequireAuth_Bv: bool = false

## 2026-08-24 (по просьбе пользователя "добавим шифрование" — WSS как опция
## на стороне сервера, см. changelog у fC_ConfigureTls_Bv/_process ниже): true
## — принятые TCP-потоки сначала проходят TLS-рукопожатие (wss://), false
## (по умолчанию) — как раньше, сырой WebSocket без шифрования (ws://).
## Включается через fC_ConfigureTls_Bv ДО fxG_EstablishingConnection_CrTr —
## именно поэтому "опция", а не обязательный шаг: без сертификата сервер
## продолжает работать как раньше, никакого поведения не меняется
var vGB_UseTls_Bv: bool = false
var _vGL_TlsOptions_L: TLSOptions = null

## {ConnectionId: {"Tls": StreamPeerTLS, "IP": String}} — приняты по TCP, но
## ещё не завершили TLS-рукопожатие (см. changelog vGB_UseTls_Bv выше). Пока
## это не пройдено, WS-рукопожатие (vGD_PendingConnections_D) не начинается
var vGD_PendingTlsConnections_D: Dictionary = {}

## Сколько секунд молчания от собеседника терпим, прежде чем считать
## подключение мёртвым — и то, что сообщается клиенту, и то, чем сервер сам
## проверяет КАЖДОЕ активное подключение в _process (см. changelog п.5)
var vGF_KeepAliveTimeoutSeconds_F: float = 20.0

## {ConnectionId: {"Peer": WebSocketPeer, "IP": String}} — ещё не завершили WS-рукопожатие
var vGD_PendingConnections_D: Dictionary = {}

## {RoutingKey (ConnId ДО промоушена / UserID ПОСЛЕ): Time.get_ticks_msec()
## последней полученной активности} — единая проверка молчания, см. changelog п.5
var vGD_LastActivityMsec_D: Dictionary = {}

## {RoutingKey (ConnId): {"Login": String, "Challenge": String}} — между
## AuthRequest и HelloConfirm, недолго
var vGD_PendingChallenges_D: Dictionary = {}

## {UserID: Token} — текущий выданный токен на пользователя (новый вход
## перезаписывает старый — только один активный токен на UserID одновременно)
var vGD_ActiveTokens_D: Dictionary = {}

var _vGI_NextConnectionId_I: int = 0


##Функционал:
##	Серверная сторона установки соединения — начинает слушать порт
##Форматы данных:
##	Входные: vGI_Port_I: int; vGB_RequireAuth_Param_Bv: bool — нужна ли авторизация
##	Выходные: bool — true, если удалось начать слушать порт
func fxG_EstablishingConnection_CrTr(vGI_Port_I: int, vGB_RequireAuth_Param_Bv: bool = false) -> bool:
	vGS_UserID_S = SERVER_SELF_USERID_S
	vGB_RequireAuth_Bv = vGB_RequireAuth_Param_Bv

	_vGL_TcpServer = TCPServer.new()
	var vGI_Err_I := _vGL_TcpServer.listen(vGI_Port_I)
	if vGI_Err_I != OK:
		push_warning("⚠️ Class_InternetServer: не удалось начать слушать порт %d (err=%d)" % [vGI_Port_I, vGI_Err_I])
		return false
	return true


##Функционал:
##	Служебная — новый уникальный ConnectionId для только что принятого TCP-подключения
func _fL_GenerateConnectionId_Cr() -> String:
	var vGS_Id_S := "Conn%d" % _vGI_NextConnectionId_I
	_vGI_NextConnectionId_I += 1
	return vGS_Id_S


##Функционал:
##	2026-08-24 (по просьбе пользователя "добавим шифрование"): включает WSS —
##	загружает сертификат+ключ с диска и готовит серверные TLSOptions. Вызывать
##	ДО fxG_EstablishingConnection_CrTr (сам порт слушать ещё не начат — это
##	только настройка). Если не вызвать вообще — сервер работает как раньше,
##	без шифрования (vGB_UseTls_Bv остаётся false, см. её changelog)
##Форматы данных:
##	Входные:
##		vGS_CertPath_S: String — путь к файлу сертификата (например .crt/.pem)
##		vGS_KeyPath_S: String — путь к файлу приватного ключа
##	Выходные: bool — true, если сертификат и ключ успешно загружены
##Принцип работы:
##	CryptoKey.load/X509Certificate.load читают файлы с диска;
##	TLSOptions.server(key, cert) собирает готовый объект для
##	StreamPeerTLS.accept_stream (см. _process — TLS-рукопожатие для КАЖДОГО
##	нового подключения использует один и тот же _vGL_TlsOptions_L)
##	⚠️ Самоподписанный сертификат для локального сервера игрока клиент должен
##	будет явно доверять на своей стороне (см. Class_InternetClient.vG_TlsOptions_L)
##	— system trust store доверяет только сертификатам от настоящих
##	удостоверяющих центров, что подходит для будущего глобального сервера с
##	доменом, но не для локального самоподписанного
func fC_ConfigureTls_Bv(vGS_CertPath_S: String, vGS_KeyPath_S: String) -> bool:
	var vGL_Key_L := CryptoKey.new()
	if vGL_Key_L.load(vGS_KeyPath_S) != OK:
		push_warning("⚠️ Class_InternetServer: не удалось загрузить TLS-ключ %s" % vGS_KeyPath_S)
		return false

	var vGL_Cert_L := X509Certificate.new()
	if vGL_Cert_L.load(vGS_CertPath_S) != OK:
		push_warning("⚠️ Class_InternetServer: не удалось загрузить TLS-сертификат %s" % vGS_CertPath_S)
		return false

	_vGL_TlsOptions_L = TLSOptions.server(vGL_Key_L, vGL_Cert_L)
	vGB_UseTls_Bv = true
	return true


##Функционал:
##	Оборачивает сырой TCP-поток либо СРАЗУ в серверный WebSocketPeer
##	(vGB_UseTls_Bv=false, поведение как раньше), либо сначала в
##	StreamPeerTLS для TLS-рукопожатия (vGB_UseTls_Bv=true, см.
##	fC_ConfigureTls_Bv) — само HTTP/WS- или TLS-рукопожатие доделывает
##	.poll() на следующих кадрах, см. _process
func _fL_OnClientStreamAccepted_Ch(vGL_Stream_L: StreamPeerTCP) -> void:
	var vGS_IP_S := vGL_Stream_L.get_connected_host()

	if vGB_UseTls_Bv:
		var vGL_TlsStream_L := StreamPeerTLS.new()
		var vGI_TlsErr_I := vGL_TlsStream_L.accept_stream(vGL_Stream_L, _vGL_TlsOptions_L)
		if vGI_TlsErr_I != OK:
			push_warning("⚠️ Class_InternetServer: не удалось начать TLS-рукопожатие (err=%d)" % vGI_TlsErr_I)
			return
		var vGS_TlsConnId_S := _fL_GenerateConnectionId_Cr()
		vGD_PendingTlsConnections_D[vGS_TlsConnId_S] = {"Tls": vGL_TlsStream_L, "IP": vGS_IP_S}
		return

	var vGL_Peer_L := WebSocketPeer.new()
	var vGI_Err_I := vGL_Peer_L.accept_stream(vGL_Stream_L)
	if vGI_Err_I != OK:
		push_warning("⚠️ Class_InternetServer: не удалось принять входящий поток как WebSocket (err=%d)" % vGI_Err_I)
		return

	var vGS_ConnId_S := _fL_GenerateConnectionId_Cr()
	vGD_PendingConnections_D[vGS_ConnId_S] = {
		"Peer": vGL_Peer_L,
		"IP": vGS_IP_S,
	}


##Функционал:
##	Переводит подключение из "ждёт WS-рукопожатия" в "активно". Сервер БОЛЬШЕ
##	НЕ шлёт Hello первым (см. changelog п.1) — просто ждём Hello от клиента;
##	если не дождёмся вовремя, единая проверка активности в _process уберёт
##	это подключение сама (см. vGD_LastActivityMsec_D)
func _fL_PromoteConnection_Ch(vGS_ConnId_S: String, vGD_Pending_D: Dictionary) -> void:
	vGD_ActiveConnections_D[vGS_ConnId_S] = vGD_Pending_D["Peer"]
	vGD_LastActivityMsec_D[vGS_ConnId_S] = Time.get_ticks_msec()


##Функционал:
##	Переносит ЖИВОЕ подключение с одного ключа маршрутизации на другой (ConnId
##	→ настоящий UserID при промоушене; см. changelog п.3). Если под новым
##	ключом уже была ДРУГАЯ активная запись (реконнект — тот же UserID зашёл
##	с нового сокета) — старая закрывается перед заменой, это и есть решение
##	«смена IP при переподключении»
func _fL_RenameConnectionKey_Ch(vGS_OldKey_S: String, vGS_NewKey_S: String) -> void:
	if not vGD_ActiveConnections_D.has(vGS_OldKey_S) or vGS_OldKey_S == vGS_NewKey_S:
		return

	if vGD_ActiveConnections_D.has(vGS_NewKey_S) and vGD_ActiveConnections_D[vGS_NewKey_S] != vGD_ActiveConnections_D[vGS_OldKey_S]:
		var vGL_OldPeer_L: WebSocketPeer = vGD_ActiveConnections_D[vGS_NewKey_S]
		vGL_OldPeer_L.close()

	vGD_ActiveConnections_D[vGS_NewKey_S] = vGD_ActiveConnections_D[vGS_OldKey_S]
	vGD_ActiveConnections_D.erase(vGS_OldKey_S)
	vGD_LastActivityMsec_D[vGS_NewKey_S] = vGD_LastActivityMsec_D.get(vGS_OldKey_S, Time.get_ticks_msec())
	vGD_LastActivityMsec_D.erase(vGS_OldKey_S)


##Функционал:
##	Точка входа для входящего от клиента сообщения (переопределяет базовую
##	заглушку). У сервера, в отличие от клиента, ВСЕГДА пробует резолвить
##	(вдруг это ответ на наш Challenge) И ВСЕГДА разбирает Op — HelloConfirm
##	одновременно и то, и другое
##Форматы данных:
##	Входные:
##		vGD_Envelope_D/vGF_ReceivedNowAt_F — см. Class_Internet.fC_ReceivingNotification_Ch
##		vGS_RoutingKey_S: String — ТЕКУЩИЙ ключ маршрутизации этого подключения
##			(ConnId до промоушена, настоящий UserID после — см. _fL_RenameConnectionKey_Ch).
##			⚠️ Заявленный UserID внутри vGD_Envelope_D может ОТЛИЧАТЬСЯ от этого
##			ключа — доверять ему для маршрутизации/операций трекера можно
##			только через _fL_ResolveTrustedUserID_Cr, не напрямую. ⚠️ 2026-08-23,
##			НАЙДЕНА И ПОЧИНЕНА ОШИБКА: этот параметр — третий, а у базовой
##			`Class_Internet.fC_ReceivingNotification_Ch` их всего два
##			(Dictionary, float) — Godot требует, чтобы переопределение было
##			СОВМЕСТИМО с сигнатурой родителя, а "лишний" параметр без значения
##			по умолчанию — уже несовместимо ("The function signature doesn't
##			match the parent"). У параметра появилось значение по умолчанию
##			("" — реально никогда не используется, при обычном вызове его
##			всегда передают явно из _fL_HandleIncomingPacket_Ch) — этого
##			достаточно, чтобы сигнатура считалась совместимой, поведение не
##			меняется
func fC_ReceivingNotification_Ch(vGD_Envelope_D: Dictionary, vGF_ReceivedNowAt_F: float, vGS_RoutingKey_S: String = "") -> void:
	vGD_LastActivityMsec_D[vGS_RoutingKey_S] = Time.get_ticks_msec()

	var vGD_Resolved_D := fC_TryResolveWaitingResponse_Bv(vGD_Envelope_D.get("AnswerTo", {}))
	if not vGD_Resolved_D.is_empty():
		fC_UpdatePingFromReply_Ch(vGD_Resolved_D, vGD_Envelope_D, vGF_ReceivedNowAt_F)

	var vGS_ClaimedUserID_S: String = vGD_Envelope_D.get("UserID", "")
	var vGS_Op_S: String = vGD_Envelope_D.get("Op", "")

	match vGS_Op_S:
		"Hello":
			_fL_OnHello_Ch(vGS_RoutingKey_S, vGS_ClaimedUserID_S, vGD_Envelope_D)
		"AuthRequest":
			_fL_OnAuthRequest_Ch(vGS_RoutingKey_S, vGD_Envelope_D)
		"HelloConfirm":
			_fL_OnHelloConfirm_Ch(vGS_RoutingKey_S, vGD_Envelope_D)
		"Register":
			_fL_OnRegisterRequest_Ch(vGS_RoutingKey_S, vGD_Envelope_D)
		"UserInfo":
			var vGS_TrustedUserID_S := _fL_ResolveTrustedUserID_Cr(vGS_RoutingKey_S, vGS_ClaimedUserID_S, vGD_Envelope_D.get("Token", ""))
			if vGS_TrustedUserID_S != "":
				_fL_OnUserInfo_Ch(vGS_TrustedUserID_S, vGD_Envelope_D.get("Messages", {}))
		_:
			var vGS_TrustedUserID_S := _fL_ResolveTrustedUserID_Cr(vGS_RoutingKey_S, vGS_ClaimedUserID_S, vGD_Envelope_D.get("Token", ""))
			if vGS_TrustedUserID_S == "":
				push_warning("⚠️ Class_InternetServer: %s прислал Op=%s без действительного Token — игнорируется" % [vGS_RoutingKey_S, vGS_Op_S])
				return
			AppOpReceived_S.emit(vGS_Op_S, vGD_Envelope_D, vGF_ReceivedNowAt_F, vGS_TrustedUserID_S)


##Функционал:
##	Проверяет, можно ли доверять заявленному UserID прямо сейчас — без
##	авторизации доверяем сразу (аккаунтов нет, терять нечего), с авторизацией —
##	только если присланный Token совпадает с выданным этому UserID
func _fL_ResolveTrustedUserID_Cr(_vGS_RoutingKey_S: String, vGS_ClaimedUserID_S: String, vGS_Token_S: String) -> String:
	if not vGB_RequireAuth_Bv:
		return vGS_ClaimedUserID_S
	if vGS_ClaimedUserID_S != "" and fC_ValidateToken_Bv(vGS_ClaimedUserID_S, vGS_Token_S):
		return vGS_ClaimedUserID_S
	return ""


##Функционал:
##	Первый Hello от клиента (несёт заявленный UserID на верхнем уровне
##	конверта + IP информационно в Messages, см. changelog Class_InternetClient.gd).
##	Без авторизации — сразу промоутирует соединение на настоящий UserID
##	(доверяем, аккаунтов нет — см. _fL_RenameConnectionKey_Ch, это же чинит
##	реконнект/смену IP); с авторизацией — оставляет ConnId-маршрутизацию до
##	успешного challenge-response. Отвечает RequireAuth+KeepAliveTimeoutSeconds
func _fL_OnHello_Ch(vGS_RoutingKey_S: String, vGS_ClaimedUserID_S: String, vGD_Envelope_D: Dictionary) -> void:
	var vC_RawMessages = vGD_Envelope_D.get("Messages", {})
	var vGD_ClientMessages_D: Dictionary = vC_RawMessages if vC_RawMessages is Dictionary else {}
	var _vGS_ClaimedIP_S: String = vGD_ClientMessages_D.get("IP", "") # информационно/для логов — не авторитетный адрес, см. changelog Class_InternetClient.gd

	var vGS_ReplyRoutingKey_S := vGS_RoutingKey_S
	if not vGB_RequireAuth_Bv and vGS_ClaimedUserID_S != "":
		_fL_RenameConnectionKey_Ch(vGS_RoutingKey_S, vGS_ClaimedUserID_S)
		vGS_ReplyRoutingKey_S = vGS_ClaimedUserID_S

	var vGD_AnswerToHello_D := {"UserID": vGS_ClaimedUserID_S, "Time": vGD_Envelope_D.get("Time", 0.0), "OperationNumber": vGD_Envelope_D.get("OperationNumber", -1)}
	fC_SendingMessage_Cr("Hello", {"RequireAuth": vGB_RequireAuth_Bv, "KeepAliveTimeoutSeconds": vGF_KeepAliveTimeoutSeconds_F}, vGD_AnswerToHello_D, vGS_ReplyRoutingKey_S, false)


##Функционал:
##	Начало входа с паролем — клиент прислал Login, сервер генерирует Challenge
##	(случайное значение) и просит клиента ответить (см. changelog п.2)
func _fL_OnAuthRequest_Ch(vGS_RoutingKey_S: String, vGD_Envelope_D: Dictionary) -> void:
	if not vGB_RequireAuth_Bv:
		push_warning("⚠️ Class_InternetServer: AuthRequest на сервере без RequireAuth — игнорируется")
		return

	var vC_RawMessages = vGD_Envelope_D.get("Messages", {})
	var vGD_Messages_D: Dictionary = vC_RawMessages if vC_RawMessages is Dictionary else {}
	var vGS_Login_S: String = vGD_Messages_D.get("Login", "")
	var vGS_Salt_S := _fL_GetUserSalt_Cr(vGS_Login_S) # "" если логин неизвестен — см. открытые вопросы (утечка через это поле)
	var vGS_Challenge_S := Crypto.new().generate_random_bytes(16).hex_encode()

	vGD_PendingChallenges_D[vGS_RoutingKey_S] = {"Login": vGS_Login_S, "Challenge": vGS_Challenge_S}

	var vGD_AnswerTo_D := {"UserID": vGD_Envelope_D.get("UserID", ""), "Time": vGD_Envelope_D.get("Time", 0.0), "OperationNumber": vGD_Envelope_D.get("OperationNumber", -1)}
	fC_SendingMessage_Cr("Challenge", {"Challenge": vGS_Challenge_S, "Salt": vGS_Salt_S}, vGD_AnswerTo_D, vGS_RoutingKey_S, true)


##Функционал:
##	Финальный шаг входа — проверяет Response на ранее выданный Challenge; при
##	успехе промоутирует соединение на настоящий UserID (=Login, см. changelog)
##	и выдаёт Token, при неуспехе отвечает AuthFailed и закрывает соединение
func _fL_OnHelloConfirm_Ch(vGS_RoutingKey_S: String, vGD_Envelope_D: Dictionary) -> void:
	if not vGB_RequireAuth_Bv:
		return # в этом режиме HelloConfirm не ожидается — авторизации нет

	if not vGD_PendingChallenges_D.has(vGS_RoutingKey_S):
		push_warning("⚠️ Class_InternetServer: HelloConfirm без предшествующего AuthRequest/Challenge от %s" % vGS_RoutingKey_S)
		return

	var vGD_Pending_D: Dictionary = vGD_PendingChallenges_D[vGS_RoutingKey_S]
	vGD_PendingChallenges_D.erase(vGS_RoutingKey_S)

	var vC_RawMessages = vGD_Envelope_D.get("Messages", {})
	var vGD_Messages_D: Dictionary = vC_RawMessages if vC_RawMessages is Dictionary else {}
	var vGS_Response_S: String = vGD_Messages_D.get("Response", "")
	var vGD_AnswerTo_D := {"UserID": vGD_Envelope_D.get("UserID", ""), "Time": vGD_Envelope_D.get("Time", 0.0), "OperationNumber": vGD_Envelope_D.get("OperationNumber", -1)}

	if not fC_ValidateChallengeResponse_Bv(vGD_Pending_D["Login"], vGS_Response_S, vGD_Pending_D["Challenge"]):
		push_warning("⚠️ Class_InternetServer: неверный ответ на Challenge от %s (Login=%s) — соединение закрывается" % [vGS_RoutingKey_S, vGD_Pending_D["Login"]])
		fC_SendingMessage_Cr("AuthFailed", {}, vGD_AnswerTo_D, vGS_RoutingKey_S, false)
		_fL_DropConnection_Ch(vGS_RoutingKey_S)
		return

	var vGS_RealUserID_S: String = vGD_Pending_D["Login"] # Login трактуется как UserID — упрощение, см. открытые вопросы
	_fL_RenameConnectionKey_Ch(vGS_RoutingKey_S, vGS_RealUserID_S)

	var vGS_Token_S := Crypto.new().generate_random_bytes(24).hex_encode()
	vGD_ActiveTokens_D[vGS_RealUserID_S] = vGS_Token_S

	fC_SendingMessage_Cr("AuthSuccess", {"Token": vGS_Token_S, "KeepAliveTimeoutSeconds": vGF_KeepAliveTimeoutSeconds_F}, vGD_AnswerTo_D, vGS_RealUserID_S, false)


##Функционал:
##	2026-08-24 (по просьбе пользователя "добавим самостоятельную регистрацию
##	для входа"): создаёт нового пользователя по запросу клиента — до этого
##	fC_RegisterUser_Ch был единственным способом появления записи в
##	FileUsers_S (только вручную, см. её changelog), теперь клиент может
##	вызвать это сам через Op "Register". Отвечает "RegisterResult"
##Форматы данных:
##	Входные:
##		vGS_RoutingKey_S: String — на этом этапе это ещё ConnId (регистрация
##			происходит ДО промоушена — своего UserID у подключения ещё нет)
##		vGD_Envelope_D: Dictionary — Messages: {"Login": String, "Password": String}
##	Ответ ("RegisterResult"): Messages: {"Ok": bool, "Error": String} — Error
##		непустой только при Ok=false, готовое сообщение для показа пользователю
##Принцип работы:
##	Проверяет: сервер вообще использует аккаунты (vGB_RequireAuth_Bv); логин
##	не пуст, пароль не короче 4 символов (тот же порядок величины, что и
##	другие проверки в проекте — не строгая политика паролей, просто защита от
##	пустого/однобуквенного); логин не совпадает с зарезервированным
##	SERVER_SELF_USERID_S; логин ещё не занят (та же проверка, что использует
##	_fL_GetUserSalt_Cr). При успехе — fC_RegisterUser_Ch как раньше (вручную)
func _fL_OnRegisterRequest_Ch(vGS_RoutingKey_S: String, vGD_Envelope_D: Dictionary) -> void:
	var vGD_AnswerTo_D := {"UserID": vGD_Envelope_D.get("UserID", ""), "Time": vGD_Envelope_D.get("Time", 0.0), "OperationNumber": vGD_Envelope_D.get("OperationNumber", -1)}

	if not vGB_RequireAuth_Bv:
		fC_SendingMessage_Cr("RegisterResult", {"Ok": false, "Error": "Регистрация не поддерживается этим сервером."}, vGD_AnswerTo_D, vGS_RoutingKey_S, false)
		return

	var vC_RawMessages = vGD_Envelope_D.get("Messages", {})
	var vGD_Messages_D: Dictionary = vC_RawMessages if vC_RawMessages is Dictionary else {}
	var vGS_Login_S: String = String(vGD_Messages_D.get("Login", "")).strip_edges()
	var vGS_Password_S: String = String(vGD_Messages_D.get("Password", ""))

	if vGS_Login_S == "" or vGS_Password_S.length() < 4:
		fC_SendingMessage_Cr("RegisterResult", {"Ok": false, "Error": "Логин не может быть пустым, пароль — короче 4 символов."}, vGD_AnswerTo_D, vGS_RoutingKey_S, false)
		return
	if vGS_Login_S == SERVER_SELF_USERID_S:
		fC_SendingMessage_Cr("RegisterResult", {"Ok": false, "Error": "Этот логин зарезервирован."}, vGD_AnswerTo_D, vGS_RoutingKey_S, false)
		return

	var vGD_Users_D: Dictionary = _vGL_Json_L.fxG_LoadJson_Cr(FileUsers_S)
	if vGD_Users_D.has(vGS_Login_S):
		fC_SendingMessage_Cr("RegisterResult", {"Ok": false, "Error": "Логин уже занят."}, vGD_AnswerTo_D, vGS_RoutingKey_S, false)
		return

	fC_RegisterUser_Ch(vGS_Login_S, vGS_Password_S)
	fC_SendingMessage_Cr("RegisterResult", {"Ok": true, "Error": ""}, vGD_AnswerTo_D, vGS_RoutingKey_S, false)


##Функционал:
##	Пакет с информацией о пользователе от клиента (см. Class_InternetClient
##	._fL_BuildUserInfoPayload_Cr) — состав полей ещё не решён, заглушка
func _fL_OnUserInfo_Ch(_vGS_UserID_S: String, _vC_Messages) -> void:
	pass # TODO: сохранение информации о пользователе для приватного сервера


##Функционал:
##	Переопределяет базовое поведение: если неотвеченным остался именно наш
##	Challenge — вход так и не завершился, сбрасываем соединение; для
##	остального — обычное поведение из Class_Internet (предупреждение)
func _fL_OnWaitingResponseFailed_Ch(vGS_Key_S: String, vGD_Entry_D: Dictionary) -> void:
	var vGS_Op_S: String = vGD_Entry_D.get("Envelope", {}).get("Op", "")
	var vGS_RoutingKey_S: String = vGD_Entry_D.get("RecipientID", "")

	if vGS_Op_S == "Challenge":
		push_warning("⚠️ Class_InternetServer: %s не ответил на Challenge — сбрасывается" % vGS_RoutingKey_S)
		_fL_DropConnection_Ch(vGS_RoutingKey_S)
	else:
		super._fL_OnWaitingResponseFailed_Ch(vGS_Key_S, vGD_Entry_D)


##Функционал:
##	Закрывает и полностью забывает подключение по ТЕКУЩЕМУ ключу маршрутизации
func _fL_DropConnection_Ch(vGS_RoutingKey_S: String) -> void:
	if vGD_ActiveConnections_D.has(vGS_RoutingKey_S):
		var vGL_Peer_L: WebSocketPeer = vGD_ActiveConnections_D[vGS_RoutingKey_S]
		vGL_Peer_L.close()
		vGD_ActiveConnections_D.erase(vGS_RoutingKey_S)
	vGD_LastActivityMsec_D.erase(vGS_RoutingKey_S)
	vGD_PendingChallenges_D.erase(vGS_RoutingKey_S)
	vGD_PendingConnections_D.erase(vGS_RoutingKey_S)
	vGD_ActiveTokens_D.erase(vGS_RoutingKey_S) # безопасно, даже если ключ был ConnId, а не UserID


##Функционал:
##	Соль пользователя для Challenge — "" если логин неизвестен
func _fL_GetUserSalt_Cr(vGS_Login_S: String) -> String:
	var vGD_Users_D: Dictionary = _vGL_Json_L.fxG_LoadJson_Cr(FileUsers_S)
	if not vGD_Users_D.has(vGS_Login_S):
		return ""
	return vGD_Users_D[vGS_Login_S].get("Salt", "")


##Функционал:
##	Проверяет Response на Challenge — заменяет прежнюю fC_ValidateCredentials_Bv
##	(пароль в открытом виде на вход больше не подаётся, см. changelog п.2)
##Принцип работы:
##	Expected = SHA256(PasswordHash этого Login + Challenge); сравнивает с
##	присланным Response. Работает, потому что PasswordHash — та же величина
##	SHA256(Salt+Password), что клиент тоже способен посчитать локально (знает
##	Salt из ответа Challenge и свой пароль) — см. План проекта/Class_Internet.md
func fC_ValidateChallengeResponse_Bv(vGS_Login_S: String, vGS_Response_S: String, vGS_Challenge_S: String) -> bool:
	var vGD_Users_D: Dictionary = _vGL_Json_L.fxG_LoadJson_Cr(FileUsers_S)
	if not vGD_Users_D.has(vGS_Login_S):
		return false
	var vGS_PasswordHash_S: String = vGD_Users_D[vGS_Login_S].get("PasswordHash", "")
	return _fL_Sha256Hex_S(vGS_PasswordHash_S + vGS_Challenge_S) == vGS_Response_S


##Функционал:
##	Проверяет, что присланный Token соответствует тому, что выдан этому UserID
func fC_ValidateToken_Bv(vGS_UserID_S: String, vGS_Token_S: String) -> bool:
	if vGS_Token_S == "":
		return false
	return vGD_ActiveTokens_D.get(vGS_UserID_S, "") == vGS_Token_S


##Функционал:
##	Заводит нового пользователя — генерирует Salt, хеширует пароль, сохраняет
##	через Class_Json. ⚠️ Сейчас единственный способ появления записи —
##	вручную (см. changelog в доке) — сам хендшейк новых пользователей не заводит
func fC_RegisterUser_Ch(vGS_Login_S: String, vGS_Password_S: String) -> void:
	var vGD_Users_D: Dictionary = _vGL_Json_L.fxG_LoadJson_Cr(FileUsers_S)
	var vGS_Salt_S := Crypto.new().generate_random_bytes(16).hex_encode()
	vGD_Users_D[vGS_Login_S] = {
		"PasswordHash": _fL_HashPassword_S(vGS_Password_S, vGS_Salt_S),
		"Salt": vGS_Salt_S,
		"CreatedAt": Time.get_unix_time_from_system(),
	}
	_vGL_Json_L.fxG_SaveJson_Ch(FileUsers_S, vGD_Users_D)


##Функционал:
##	Служебная — солёный SHA-256 пароля (та же величина, что клиент считает
##	как Intermediate в challenge-response, см. fC_ValidateChallengeResponse_Bv)
func _fL_HashPassword_S(vGS_Password_S: String, vGS_Salt_S: String) -> String:
	return _fL_Sha256Hex_S(vGS_Salt_S + vGS_Password_S)


##Функционал:
##	Служебная — общий SHA-256(строка) в hex, переиспользуется и для хеша
##	пароля, и для проверки Response на Challenge
func _fL_Sha256Hex_S(vGS_Input_S: String) -> String:
	var vGL_Ctx_L := HashingContext.new()
	vGL_Ctx_L.start(HashingContext.HASH_SHA256)
	vGL_Ctx_L.update(vGS_Input_S.to_utf8_buffer())
	return vGL_Ctx_L.finish().hex_encode()


##Функционал:
##	Физически отправляет конверт конкретному подключённому клиенту по
##	ТЕКУЩЕМУ ключу маршрутизации
func _fL_TransportSend_Ch(vGS_RecipientID_S: String, vGD_Envelope_D: Dictionary) -> void:
	if not vGD_ActiveConnections_D.has(vGS_RecipientID_S):
		push_warning("⚠️ Class_InternetServer: попытка отправить сообщение неизвестному/отключённому RecipientID=%s (Op=%s)" % [vGS_RecipientID_S, vGD_Envelope_D.get("Op", "?")])
		return
	var vGL_Peer_L: WebSocketPeer = vGD_ActiveConnections_D[vGS_RecipientID_S]
	vGL_Peer_L.send_text(JSON.stringify(vGD_Envelope_D))


##Функционал:
##	Разбирает один входящий пакет в конверт и передаёт в fC_ReceivingNotification_Ch
##	вместе с моментом получения и ТЕКУЩИМ ключом маршрутизации этого подключения
func _fL_HandleIncomingPacket_Ch(vGS_RoutingKey_S: String, vGA_PacketBytes_By: PackedByteArray) -> void:
	var vGV_Parsed = JSON.parse_string(vGA_PacketBytes_By.get_string_from_utf8())
	if not (vGV_Parsed is Dictionary):
		push_warning("⚠️ Class_InternetServer: пришёл пакет не JSON-словарь от %s" % vGS_RoutingKey_S)
		return
	fC_ReceivingNotification_Ch(vGV_Parsed, Time.get_unix_time_from_system(), vGS_RoutingKey_S)


##Функционал:
##	Раз в кадр: принимает новые TCP-подключения, продвигает WS-рукопожатие у
##	ожидающих, опрашивает активные подключения на пакеты и на молчание дольше
##	vGF_KeepAliveTimeoutSeconds_F (единая проверка — покрывает и "подключился
##	и не сказал Hello", и "замолчал позже", см. changelog п.1/5). ОБЯЗАТЕЛЬНО
##	зовёт super._process. ⚠️ Итерирует по СНИМКУ ключей (.keys()), не по
##	живому словарю — см. changelog п.4 про самостоятельно найденную ошибку
func _process(vGF_Delta_F: float) -> void:
	if _vGL_TcpServer != null:
		while _vGL_TcpServer.is_connection_available():
			var vGL_Stream_L: StreamPeerTCP = _vGL_TcpServer.take_connection()
			_fL_OnClientStreamAccepted_Ch(vGL_Stream_L)

	# 2026-08-24 (по просьбе пользователя "добавим шифрование" — WSS): продвигает
	# TLS-рукопожатие у ждущих (см. vGD_PendingTlsConnections_D/fC_ConfigureTls_Bv
	# выше). Как только TLS готов (STATUS_CONNECTED) — TLS-поток передаётся в
	# WebSocketPeer.accept_stream ТОЧНО ТАК ЖЕ, как раньше передавался сырой TCP
	# (StreamPeerTLS сам по себе тоже StreamPeer — WebSocketPeer этого не
	# замечает), и подключение переходит в ОБЫЧНЫЙ vGD_PendingConnections_D —
	# дальше WS-рукопожатие идёт существующим циклом ниже без изменений. Если
	# vGB_UseTls_Bv=false, этот словарь всегда пуст, цикл — no-op
	var vGA_SettledTlsIds_A := []
	for elGS_ConnId_S in vGD_PendingTlsConnections_D.keys():
		var vGD_TlsPending_D: Dictionary = vGD_PendingTlsConnections_D[elGS_ConnId_S]
		var vGL_TlsStream_L: StreamPeerTLS = vGD_TlsPending_D["Tls"]
		vGL_TlsStream_L.poll()
		match vGL_TlsStream_L.get_status():
			StreamPeerTLS.STATUS_CONNECTED:
				var vGL_Peer_L := WebSocketPeer.new()
				var vGI_Err_I := vGL_Peer_L.accept_stream(vGL_TlsStream_L)
				vGA_SettledTlsIds_A.append(elGS_ConnId_S)
				if vGI_Err_I != OK:
					push_warning("⚠️ Class_InternetServer: TLS готов, но не удалось начать WS-рукопожатие поверх него (err=%d)" % vGI_Err_I)
					continue
				vGD_PendingConnections_D[elGS_ConnId_S] = {"Peer": vGL_Peer_L, "IP": vGD_TlsPending_D["IP"]}
			StreamPeerTLS.STATUS_ERROR, StreamPeerTLS.STATUS_ERROR_HOSTNAME_MISMATCH, StreamPeerTLS.STATUS_DISCONNECTED:
				push_warning("⚠️ Class_InternetServer: TLS-рукопожатие не удалось (%s)" % vGD_TlsPending_D["IP"])
				vGA_SettledTlsIds_A.append(elGS_ConnId_S)
			_:
				pass # STATUS_HANDSHAKING — ждём дальше, следующий кадр
	for elGS_ConnId_S in vGA_SettledTlsIds_A:
		vGD_PendingTlsConnections_D.erase(elGS_ConnId_S)

	var vGA_SettledPendingIds_A := []
	for elGS_ConnId_S in vGD_PendingConnections_D.keys():
		var vGD_Pending_D: Dictionary = vGD_PendingConnections_D[elGS_ConnId_S]
		var vGL_PendingPeer_L: WebSocketPeer = vGD_Pending_D["Peer"]
		vGL_PendingPeer_L.poll()
		match vGL_PendingPeer_L.get_ready_state():
			WebSocketPeer.STATE_OPEN:
				_fL_PromoteConnection_Ch(elGS_ConnId_S, vGD_Pending_D)
				vGA_SettledPendingIds_A.append(elGS_ConnId_S)
			WebSocketPeer.STATE_CLOSED:
				vGA_SettledPendingIds_A.append(elGS_ConnId_S)
			_:
				pass
	for elGS_ConnId_S in vGA_SettledPendingIds_A:
		vGD_PendingConnections_D.erase(elGS_ConnId_S)

	var vGA_DeadKeys_A := []
	var vGF_NowMsec_F := Time.get_ticks_msec()
	for elGS_Key_S in vGD_ActiveConnections_D.keys():
		if not vGD_ActiveConnections_D.has(elGS_Key_S):
			continue # переименовано более ранним элементом этого же тика (см. _fL_RenameConnectionKey_Ch)

		var vGL_ActivePeer_L: WebSocketPeer = vGD_ActiveConnections_D[elGS_Key_S]
		vGL_ActivePeer_L.poll()
		if vGL_ActivePeer_L.get_ready_state() != WebSocketPeer.STATE_OPEN:
			vGA_DeadKeys_A.append(elGS_Key_S)
			continue

		while vGL_ActivePeer_L.get_available_packet_count() > 0:
			_fL_HandleIncomingPacket_Ch(elGS_Key_S, vGL_ActivePeer_L.get_packet())

		if not vGD_ActiveConnections_D.has(elGS_Key_S):
			continue # переименовалось В ПРОЦЕССЕ обработки пакета (Hello/HelloConfirm) — новый ключ проверится в своём следующем тике
		if vGF_NowMsec_F - vGD_LastActivityMsec_D.get(elGS_Key_S, vGF_NowMsec_F) > vGF_KeepAliveTimeoutSeconds_F * 1000.0:
			vGA_DeadKeys_A.append(elGS_Key_S)

	for elGS_Key_S in vGA_DeadKeys_A:
		_fL_DropConnection_Ch(elGS_Key_S)

	super._process(vGF_Delta_F)
