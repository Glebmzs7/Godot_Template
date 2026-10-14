extends Class_Internet

class_name Class_InternetClient

##Версия оформления: 0.3.0.0
##2026-08-24 - mzs7 - по просьбе пользователя добавлены: 1) опциональный TLS
##	(WSS) — если снаружи выставлено vG_TlsOptions_L, connect_to_url передаёт
##	его дальше, сам WebSocketPeer делает TLS-рукопожатие внутри себя (в
##	отличие от сервера, клиенту не нужен свой цикл ожидания — это делает
##	сам движок); 2) fC_RegisterAccount_Ch — самостоятельная регистрация
##	(логин/пароль), см. Class_InternetServer._fL_OnRegisterRequest_Ch. Ответ
##	("RegisterResult") новый case в match не добавлен НАРОЧНО — как и любой
##	другой прикладной Op, он проходит через default-ветку в
##	fC_ReceivingNotification_Ch и попадает в AppOpReceived_S (см. changelog
##	2026-08-23 ниже) — обрабатывается в Start_Program.gd.
##2026-08-22 - mzs7 - первая версия (см. историю в План проекта/Class_InternetClient.md).
##2026-08-23 - mzs7 - протокол доработан (см. changelog Class_Internet.gd —
##	fC_ReceivingNotification_Ch теперь принимает разобранный конверт одним
##	Dictionary, а не длинным списком параметров). Изменения по существу:
##	1) Hello теперь несёт явный IP в Messages (см. _fL_GetBestEffortLocalIP_Cr)
##		— ⚠️ это ЛУЧШАЯ ОЦЕНКА локального адреса клиента, не обязательно то,
##		что сервер реально увидит на своей стороне (через NAT они отличаются
##		— см. открытые вопросы в доке) — поле информационное/для логов, не
##		для маршрутизации.
##	2) Новое состояние ConnectionState.AUTHENTICATING — между "сокет открыт,
##		Hello отправлен" (CONNECTING) и "полностью готов" (CONNECTED), пока
##		идёт challenge-response (см. fC_SendCredentials_Ch/_fL_OnChallenge_Ch).
##	3) Хендшейк авторизации теперь трёхшаговый: AuthRequest (просим Challenge)
##		→ Challenge (сервер прислал случайное значение + соль) →
##		HelloConfirm (шлём хеш пароля+значения, НЕ сам пароль) → AuthSuccess/
##		AuthFailed. Пароль хранится в памяти (_vGS_PendingPassword_S) только
##		между fC_SendCredentials_Ch и отправкой ответа на Challenge — сразу
##		после стирается.
##	4) Токен (vGS_MyToken_S, унаследовано) выставляется из AuthSuccess и
##		дальше сам собой кладётся в каждое исходящее сообщение — Class_Internet
##		делает это автоматически, здесь ничего специально пересылать не нужно.
##	5) Добавлен таймаут "нет активности от сервера" (_vGF_KeepAliveTimeoutSeconds_F,
##		значение приходит от сервера в ответе на Hello/в AuthSuccess) —
##		отдельно от ForwardingTimeArray (тот про одно сообщение), этот про
##		полное молчание собеседника дольше объявленного времени.
##	⚠️ Код не запускался живьём в Godot.
##2026-08-23 - mzs7 - бывшая заглушка "TODO: ответы на операции трекера, когда
##	они появятся" в fC_ReceivingNotification_Ch заменена на
##	AppOpReceived_S.emit(...) (см. changelog Class_Internet.gd) — используется
##	для ответов на "CheckUpdate"/"CheckFiles" (см. Start_Program.gd
##	→ _fC_OnClientAppOpReceived_Ch, План проекта/Class_Internet.md → «После
##	установления соединения»).

## См. changelog — AUTHENTICATING новое; остальные три как в первом черновике
enum ConnectionState {DISCONNECTED, CONNECTING, AUTHENTICATING, CONNECTED, RECONNECTING}

var vGE_State: ConnectionState = ConnectionState.DISCONNECTED

const SERVER_RECIPIENT_ID := "Server"

var _vGS_ServerAddress_S: String = ""
var _vGL_Socket: WebSocketPeer = null
var _vGB_HelloSentThisConnection_Bv: bool = false

## 2026-08-24: опция TLS (WSS) — выставляется СНАРУЖИ (например Start_Program.gd,
## если адрес сервера начинается с "wss://") ДО вызова fxG_EstablishingConnection_CrTr.
## null — обычное нешифрованное соединение (по умолчанию, ничего не меняется).
## См. Class_InternetServer.fC_ConfigureTls_Bv — серверная сторона той же опции.
var vG_TlsOptions_L: TLSOptions = null

## Логин/пароль между fC_SendCredentials_Ch и отправкой ответа на Challenge —
## пароль стирается сразу после того, как посчитан хеш-ответ (см. _fL_OnChallenge_Ch)
var _vGS_PendingLogin_S: String = ""
var _vGS_PendingPassword_S: String = ""

var vGA_ReconnectDelayArray_A: Array = [1.0, 2.0, 4.0, 8.0, 16.0, 30.0]
var _vGI_ReconnectAttempt_I: int = 0
var _vGF_ReconnectRetryAtMsec_F: float = 0.0

## Сколько секунд можно не получать НИЧЕГО от сервера, прежде чем считать
## соединение мёртвым (объявляется сервером, см. _fL_OnHelloReply_Ch/_fL_OnAuthResult_Ch)
## 0.0 — сервер ещё не сообщил, проверка выключена
var _vGF_KeepAliveTimeoutSeconds_F: float = 0.0
var _vGF_LastActivityMsec_F: float = 0.0


##Функционал:
##	Клиентская сторона установки соединения — открывает WebSocket-транспорт
##	по известному адресу сервера (сервер игрока и глобальный сервер — просто
##	разные значения этого адреса, для функции разницы нет)
##Форматы данных:
##	Входные: vGS_ServerAddress_S: String — например "ws://127.0.0.1:9050"
##	Выходные: bool — true, если попытка подключения запущена
func fxG_EstablishingConnection_CrTr(vGS_ServerAddress_S: String) -> bool:
	_vGS_ServerAddress_S = vGS_ServerAddress_S
	_vGL_Socket = WebSocketPeer.new()
	_vGB_HelloSentThisConnection_Bv = false

	# vG_TlsOptions_L по умолчанию null — connect_to_url(url, null) работает
	# как обычное нешифрованное соединение, отдельная ветка не нужна
	var vGI_Err_I := _vGL_Socket.connect_to_url(vGS_ServerAddress_S, vG_TlsOptions_L)
	if vGI_Err_I != OK:
		push_warning("⚠️ Class_InternetClient: connect_to_url(%s) вернул ошибку %d" % [vGS_ServerAddress_S, vGI_Err_I])
		vGE_State = ConnectionState.DISCONNECTED
		return false

	vGE_State = ConnectionState.CONNECTING
	return true


##Функционал:
##	Служебная — лучшая оценка локального IP клиента для информационного поля
##	Hello.Messages.IP (см. changelog — НЕ авторитетный адрес, сервер видит
##	настоящий адрес соединения сам, это поле не для маршрутизации)
##Выходные: String — первый непетлевой IPv4-адрес или "" если не нашли
func _fL_GetBestEffortLocalIP_Cr() -> String:
	var vGA_Addresses_A: PackedStringArray = IP.get_local_addresses()
	for elGS_Addr_S in vGA_Addresses_A:
		if elGS_Addr_S.begins_with("127.") or elGS_Addr_S == "::1" or elGS_Addr_S.begins_with("169.254."):
			continue
		if elGS_Addr_S.find(":") != -1:
			continue # пропускаем IPv6 здесь — предпочитаем читаемый IPv4
		return elGS_Addr_S
	return ""


##Функционал:
##	Точка входа для входящего от сервера сообщения (переопределяет базовую
##	заглушку). Резолв-XOR-диспетч: либо это ответ на наш запрос (резолвится
##	через fC_TryResolveWaitingResponse_Bv и разбирается по Op ОРИГИНАЛА),
##	либо push от сервера (разбирается по Op самого входящего)
##Форматы данных: см. Class_Internet.fC_ReceivingNotification_Ch
func fC_ReceivingNotification_Ch(vGD_Envelope_D: Dictionary, vGF_ReceivedNowAt_F: float) -> void:
	_vGF_LastActivityMsec_F = Time.get_ticks_msec()

	var vGD_Resolved_D := fC_TryResolveWaitingResponse_Bv(vGD_Envelope_D.get("AnswerTo", {}))
	if not vGD_Resolved_D.is_empty():
		fC_UpdatePingFromReply_Ch(vGD_Resolved_D, vGD_Envelope_D, vGF_ReceivedNowAt_F)
		var vGS_OriginalOp_S: String = vGD_Resolved_D.get("Envelope", {}).get("Op", "")
		match vGS_OriginalOp_S:
			"Hello":
				_fL_OnHelloReply_Ch(vGD_Envelope_D)
			"AuthRequest":
				_fL_OnChallenge_Ch(vGD_Envelope_D)
			"HelloConfirm":
				_fL_OnAuthResult_Ch(vGD_Envelope_D)
			_:
				AppOpReceived_S.emit(vGS_OriginalOp_S, vGD_Envelope_D, vGF_ReceivedNowAt_F, SERVER_RECIPIENT_ID)
		return

	var vGS_Op_S: String = vGD_Envelope_D.get("Op", "")
	match vGS_Op_S:
		"Ping":
			pass # зарезервировано — см. открытый вопрос про отдельный heartbeat в доке
		_:
			push_warning("⚠️ Class_InternetClient: неизвестная операция от сервера Op=%s" % vGS_Op_S)

	if vGD_Envelope_D.get("AnswerNeeded", false):
		var vGD_AnswerTo_D := {
			"UserID": vGD_Envelope_D.get("UserID", ""),
			"Time": vGD_Envelope_D.get("Time", 0.0),
			"OperationNumber": vGD_Envelope_D.get("OperationNumber", -1),
		}
		fC_SendingMessage_Cr("Ack", {}, vGD_AnswerTo_D, SERVER_RECIPIENT_ID, false, 5.0, [1.0, 3.0, 7.0], "", vGF_ReceivedNowAt_F)


##Функционал:
##	Обрабатывает ответ сервера на первый Hello — узнаёт, нужен ли пароль, и
##	сохраняет объявленный таймаут "нет активности". Если пароль не нужен —
##	сразу шлёт пакет с информацией о пользователе (см. changelog Class_Internet.md
##	п.5 сценария подключения) и считается подключённым; если нужен — переходит
##	в AUTHENTICATING и ждёт fC_SendCredentials_Ch снаружи
func _fL_OnHelloReply_Ch(vGD_Envelope_D: Dictionary) -> void:
	var vC_RawMessages = vGD_Envelope_D.get("Messages", {})
	var vGD_ServerMessages_D: Dictionary = vC_RawMessages if vC_RawMessages is Dictionary else {}
	var vGB_RequireAuth_Bv: bool = vGD_ServerMessages_D.get("RequireAuth", false)
	_vGF_KeepAliveTimeoutSeconds_F = float(vGD_ServerMessages_D.get("KeepAliveTimeoutSeconds", 0.0))

	if not vGB_RequireAuth_Bv:
		vGE_State = ConnectionState.CONNECTED
		_vGI_ReconnectAttempt_I = 0
		fC_SendingMessage_Cr("UserInfo", _fL_BuildUserInfoPayload_Cr(), {}, SERVER_RECIPIENT_ID, false)
	else:
		vGE_State = ConnectionState.AUTHENTICATING
		push_warning("⚠️ Class_InternetClient: сервер требует авторизацию — вызови fC_SendCredentials_Ch(login, password)")


##Функционал:
##	Точка расширения для UI логина — этот класс намеренно не владеет экраном
##	ввода логина/пароля. Начинает хендшейк авторизации: запоминает данные,
##	просит у сервера Challenge
##Форматы данных: vGS_Login_S: String, vGS_Password_S: String
func fC_SendCredentials_Ch(vGS_Login_S: String, vGS_Password_S: String) -> void:
	if vGE_State != ConnectionState.AUTHENTICATING:
		push_warning("⚠️ Class_InternetClient: fC_SendCredentials_Ch вызвана вне AUTHENTICATING (сейчас %s)" % ConnectionState.keys()[vGE_State])
		return
	_vGS_PendingLogin_S = vGS_Login_S
	_vGS_PendingPassword_S = vGS_Password_S
	fC_SendingMessage_Cr("AuthRequest", {"Login": vGS_Login_S}, {}, SERVER_RECIPIENT_ID, true)


##Функционал:
##	2026-08-24: самостоятельная регистрация нового аккаунта (логин/пароль) —
##	по просьбе пользователя. Как и fC_SendCredentials_Ch, вызывается снаружи
##	(UI-экран регистрации в Start_Program.gd), пока клиент в AUTHENTICATING
##	(сервер уже прислал HelloReply с RequireAuth=true). Пароль уходит на
##	сервер напрямую (в отличие от логина через Challenge) — регистрация ещё
##	не установившийся сеанс, здесь нет общего секрета для челленджа, поэтому
##	этот единственный пакет должен идти по WSS (см. vG_TlsOptions_L/
##	Class_InternetServer.fC_ConfigureTls_Bv), иначе пароль виден в открытом
##	виде. Ответ ("RegisterResult": {Ok, Error}) приходит через AppOpReceived_S
##	— специального case здесь не нужно (см. changelog вверху файла)
##Форматы данных: vGS_Login_S: String, vGS_Password_S: String
func fC_RegisterAccount_Ch(vGS_Login_S: String, vGS_Password_S: String) -> void:
	if vGE_State != ConnectionState.AUTHENTICATING:
		push_warning("⚠️ Class_InternetClient: fC_RegisterAccount_Ch вызвана вне AUTHENTICATING (сейчас %s)" % ConnectionState.keys()[vGE_State])
		return
	fC_SendingMessage_Cr("Register", {"Login": vGS_Login_S, "Password": vGS_Password_S}, {}, SERVER_RECIPIENT_ID, true)


##Функционал:
##	Обрабатывает Challenge от сервера — считает хеш-ответ и НЕ передаёт пароль
##	по сети (см. План проекта/Class_Internet.md → «Авторизация: challenge-response + токен»)
##Принцип работы:
##	Intermediate = SHA256(Salt + Password) — та же величина, что сервер хранит
##	как PasswordHash; Response = SHA256(Intermediate + Challenge); отправляет
##	HelloConfirm с Response, AnswerTo указывает на само сообщение с Challenge
func _fL_OnChallenge_Ch(vGD_Envelope_D: Dictionary) -> void:
	var vC_RawMessages = vGD_Envelope_D.get("Messages", {})
	var vGD_ChallengeMessages_D: Dictionary = vC_RawMessages if vC_RawMessages is Dictionary else {}
	var vGS_Challenge_S: String = vGD_ChallengeMessages_D.get("Challenge", "")
	var vGS_Salt_S: String = vGD_ChallengeMessages_D.get("Salt", "")

	if vGS_Challenge_S == "" or _vGS_PendingPassword_S == "":
		push_warning("⚠️ Class_InternetClient: получен Challenge, но нечем на него ответить (нет пароля в памяти)")
		return

	var vGS_Intermediate_S := _fL_Sha256Hex_S(vGS_Salt_S + _vGS_PendingPassword_S)
	var vGS_Response_S := _fL_Sha256Hex_S(vGS_Intermediate_S + vGS_Challenge_S)
	_vGS_PendingPassword_S = "" # больше не нужен — не держим пароль в памяти дольше необходимого

	var vGD_AnswerToChallenge_D := {
		"UserID": vGD_Envelope_D.get("UserID", ""),
		"Time": vGD_Envelope_D.get("Time", 0.0),
		"OperationNumber": vGD_Envelope_D.get("OperationNumber", -1),
	}
	fC_SendingMessage_Cr("HelloConfirm", {"Response": vGS_Response_S}, vGD_AnswerToChallenge_D, SERVER_RECIPIENT_ID, true)


##Функционал:
##	Обрабатывает финальный ответ сервера на HelloConfirm — AuthSuccess (входим,
##	сохраняем Token) или AuthFailed (авторизация не удалась, сервер сам закроет соединение)
func _fL_OnAuthResult_Ch(vGD_Envelope_D: Dictionary) -> void:
	var vGS_Op_S: String = vGD_Envelope_D.get("Op", "")
	if vGS_Op_S != "AuthSuccess":
		push_warning("⚠️ Class_InternetClient: авторизация не удалась (Op=%s)" % vGS_Op_S)
		return

	var vC_RawMessages = vGD_Envelope_D.get("Messages", {})
	var vGD_Messages_D: Dictionary = vC_RawMessages if vC_RawMessages is Dictionary else {}
	vGS_MyToken_S = vGD_Messages_D.get("Token", "")
	_vGF_KeepAliveTimeoutSeconds_F = float(vGD_Messages_D.get("KeepAliveTimeoutSeconds", _vGF_KeepAliveTimeoutSeconds_F))

	vGE_State = ConnectionState.CONNECTED
	_vGI_ReconnectAttempt_I = 0
	fC_SendingMessage_Cr("UserInfo", _fL_BuildUserInfoPayload_Cr(), {}, SERVER_RECIPIENT_ID, false)


##Функционал:
##	Пакет с информацией о пользователе для работы приватного/локального
##	сервера (см. Class_Internet.md, шаг 5 сценария подключения). ⚠️ Точный
##	состав полей ещё не решён (зависит от того, что вообще нужно
##	трекеру/серверу) — сейчас заглушка, только UserID
func _fL_BuildUserInfoPayload_Cr() -> Dictionary:
	return {"UserID": vGS_UserID_S}


##Функционал:
##	Служебная — SHA-256 строки в hex, используется в challenge-response (см.
##	fC_ValidateChallengeResponse_Bv на сервере — тот же алгоритм, иначе не сойдётся)
func _fL_Sha256Hex_S(vGS_Input_S: String) -> String:
	var vGL_Ctx_L := HashingContext.new()
	vGL_Ctx_L.start(HashingContext.HASH_SHA256)
	vGL_Ctx_L.update(vGS_Input_S.to_utf8_buffer())
	return vGL_Ctx_L.finish().hex_encode()


##Функционал:
##	2026-08-24 (найдено при ревью интернет-кода по просьбе пользователя):
##	переопределяет базовое поведение (Class_Internet — просто предупреждение
##	в лог, ничего больше). Без этого переопределения, если сокет технически
##	ОТКРЫТ, но сервер так и не ответил на ключевой шаг рукопожатия (Hello/
##	AuthRequest/HelloConfirm) — ни после первой отправки, ни после всех
##	повторов ForwardingTimeArray — клиент оставался бы в CONNECTING/
##	AUTHENTICATING НАВСЕГДА: сам протокольный слой ничего не предпринимал
##	бы, кроме одной строчки в лог. Единственное, что раньше спасало —
##	независимый таймаут SERVER_CONNECT_TIMEOUT_SECONDS_F в Start_Program.gd
##	(показывает кнопки "Повторить"/"Продолжить без сервера"), но сам объект
##	Class_InternetClient оставался в этом зависшем состоянии — у сервера для
##	АНАЛОГИЧНОЙ ситуации (не пришёл ответ на его Challenge) такая защита уже
##	была (см. Class_InternetServer._fL_OnWaitingResponseFailed_Ch), у клиента
##	её не было. Теперь для трёх шагов рукопожатия клиент сам запускает
##	fC_Reconnect_Ch() — новую попытку с нуля, а не бесконечное молчание.
##	Для остального (прикладные запросы вроде CheckUpdate/CheckFiles) —
##	обычное поведение из Class_Internet (предупреждение, без реконнекта,
##	чтобы не рвать рабочее соединение из-за одного потерянного прикладного
##	ответа)
func _fL_OnWaitingResponseFailed_Ch(vGS_Key_S: String, vGD_Entry_D: Dictionary) -> void:
	var vGS_Op_S: String = vGD_Entry_D.get("Envelope", {}).get("Op", "")
	if vGS_Op_S == "Hello" or vGS_Op_S == "AuthRequest" or vGS_Op_S == "HelloConfirm":
		push_warning("⚠️ Class_InternetClient: не дождались ответа на %s — переподключаемся" % vGS_Op_S)
		fC_Reconnect_Ch()
	else:
		super._fL_OnWaitingResponseFailed_Ch(vGS_Key_S, vGD_Entry_D)


##Функционал:
##	Запускает полное переподключение (обрыв ВСЕГО транспорта, не одного
##	сообщения — то уже покрыто ForwardingTimeArray)
func fC_Reconnect_Ch() -> void:
	vGE_State = ConnectionState.RECONNECTING
	vGD_ActiveConnections_D.erase(SERVER_RECIPIENT_ID)
	vGS_MyToken_S = "" # токен привязан к конкретному соединению на сервере — после реконнекта нужен новый вход

	var vGF_DelayF_F: float
	if vGA_ReconnectDelayArray_A.is_empty():
		vGF_DelayF_F = 30.0
	elif _vGI_ReconnectAttempt_I < vGA_ReconnectDelayArray_A.size():
		vGF_DelayF_F = float(vGA_ReconnectDelayArray_A[_vGI_ReconnectAttempt_I])
	else:
		vGF_DelayF_F = float(vGA_ReconnectDelayArray_A[vGA_ReconnectDelayArray_A.size() - 1])

	_vGF_ReconnectRetryAtMsec_F = Time.get_ticks_msec() + vGF_DelayF_F * 1000.0
	_vGI_ReconnectAttempt_I += 1


##Функционал:
##	Физически отправляет конверт серверу (единственный адресат — RecipientID
##	фактически игнорируется, оставлен параметром ради единой сигнатуры)
func _fL_TransportSend_Ch(vGS_RecipientID_S: String, vGD_Envelope_D: Dictionary) -> void:
	if _vGL_Socket == null or _vGL_Socket.get_ready_state() != WebSocketPeer.STATE_OPEN:
		push_warning("⚠️ Class_InternetClient: попытка отправить сообщение при закрытом сокете (RecipientID=%s, Op=%s)" % [vGS_RecipientID_S, vGD_Envelope_D.get("Op", "?")])
		return
	_vGL_Socket.send_text(JSON.stringify(vGD_Envelope_D))


##Функционал:
##	Разбирает один входящий пакет в конверт и передаёт в fC_ReceivingNotification_Ch
##	вместе с моментом получения (см. changelog Class_Internet.gd)
func _fL_HandleIncomingPacket_Ch(vGA_PacketBytes_By: PackedByteArray) -> void:
	var vGV_Parsed = JSON.parse_string(vGA_PacketBytes_By.get_string_from_utf8())
	if not (vGV_Parsed is Dictionary):
		push_warning("⚠️ Class_InternetClient: пришёл пакет, не разбирающийся в JSON-словарь")
		return
	fC_ReceivingNotification_Ch(vGV_Parsed, Time.get_unix_time_from_system())


##Функционал:
##	Раз в кадр: опрашивает сокет, шлёт Hello один раз на открытие сокета,
##	вычитывает пакеты, следит за таймаутом отсутствия активности и за
##	переподключением. ОБЯЗАТЕЛЬНО зовёт super._process в конце
func _process(vGF_Delta_F: float) -> void:
	if vGE_State == ConnectionState.RECONNECTING:
		if Time.get_ticks_msec() >= _vGF_ReconnectRetryAtMsec_F:
			fxG_EstablishingConnection_CrTr(_vGS_ServerAddress_S)
		super._process(vGF_Delta_F)
		return

	if _vGL_Socket == null:
		super._process(vGF_Delta_F)
		return

	_vGL_Socket.poll()
	var vGE_ReadyState_I := _vGL_Socket.get_ready_state()

	match vGE_ReadyState_I:
		WebSocketPeer.STATE_OPEN:
			if not _vGB_HelloSentThisConnection_Bv:
				vGD_ActiveConnections_D[SERVER_RECIPIENT_ID] = _vGL_Socket
				_vGF_LastActivityMsec_F = Time.get_ticks_msec()
				fC_SendingMessage_Cr("Hello", {"IP": _fL_GetBestEffortLocalIP_Cr()}, {}, SERVER_RECIPIENT_ID, true)
				_vGB_HelloSentThisConnection_Bv = true
			while _vGL_Socket.get_available_packet_count() > 0:
				_fL_HandleIncomingPacket_Ch(_vGL_Socket.get_packet())

			# Таймаут "нет активности" — отдельная проверка ПОВЕРХ обычного
			# ForwardingTimeArray, только пока реально подключены (0.0 = сервер
			# ещё не сообщил таймаут, проверка выключена)
			if vGE_State == ConnectionState.CONNECTED and _vGF_KeepAliveTimeoutSeconds_F > 0.0:
				if Time.get_ticks_msec() - _vGF_LastActivityMsec_F > _vGF_KeepAliveTimeoutSeconds_F * 1000.0:
					push_warning("⚠️ Class_InternetClient: от сервера нет активности дольше %.1f сек — считаем соединение разорванным" % _vGF_KeepAliveTimeoutSeconds_F)
					fC_Reconnect_Ch()

		WebSocketPeer.STATE_CLOSED:
			if vGE_State != ConnectionState.DISCONNECTED:
				fC_Reconnect_Ch()

		WebSocketPeer.STATE_CONNECTING, WebSocketPeer.STATE_CLOSING:
			pass

	super._process(vGF_Delta_F)
