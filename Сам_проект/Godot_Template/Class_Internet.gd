extends Node

class_name Class_Internet

##Версия оформления: 0.2.0.0
##2026-08-22 - mzs7 - первая версия (см. историю в План проекта/Class_Internet.md).
##2026-08-23 - mzs7 - протокол доработан по итогам разбора кода и уточняющих
##	вопросов (см. changelog правок 2026-08-23 в План проекта/Class_Internet.md):
##	1) Добавлены поля конверта "Token" (текущий токен этой стороны, кладётся
##		АВТОМАТИЧЕСКИ в каждое исходящее сообщение из vGS_MyToken_S — не нужно
##		передавать отдельным параметром на каждый вызов fC_SendingMessage_Cr)
##		и "ReceivedAt" (когда МЫ получили оригинал, если это сообщение — ответ;
##		нужно для полной 4-меточной формулы пинга, см. ниже).
##	2) fC_CalculatePingAndOffset_Cr переписана под полную формулу на 4 метках
##		(NTP-стиль t0..t3) вместо прежней упрощённой на 2 метках — теперь
##		возможна, т.к. появилось поле "ReceivedAt".
##	3) ⚠️ АРХИТЕКТУРНОЕ РЕШЕНИЕ: fC_ReceivingNotification_Ch за три раунда
##		правок обросла бы 10-11 позиционными параметрами (UserID, Op, Messages,
##		Time, OperationNumber, AnswerTo, AnswerNeeded, ReceivedAt, Token, и
##		ещё ConnId только у сервера) — это уже само по себе запах, что пора
##		остановиться и передавать РАЗОБРАННЫЙ КОНВЕРТ ЦЕЛИКОМ одним Dictionary,
##		а не длинным списком позиционных аргументов. Новая сигнатура:
##		fC_ReceivingNotification_Ch(vGD_Envelope_D, vGF_ReceivedNowAt_F) —
##		симметрично тому, что fC_SendingMessage_Cr тоже собирает конверт как
##		Dictionary. Новые поля добавлять дальше — это просто новый ключ в
##		словаре, а не новая правка сигнатуры везде. vGF_ReceivedNowAt_F — это
##		НЕ поле конверта, а локальный факт "когда МЫ прямо сейчас разобрали
##		этот пакет" (Time.get_unix_time_from_system() в момент разбора) —
##		передаётся отдельно, чтобы если обработчик решит ответить, он мог
##		вставить это же значение в "ReceivedAt" исходящего ответа.
##	4) Добавлена fC_UpdatePingFromReply_Ch — общий хелпер: как только
##		fC_TryResolveWaitingResponse_Bv нашла, что входящее — ответ на наше
##		сообщение, здесь же можно честно посчитать RTT/Offset по всем 4
##		меткам, раз все они теперь есть в конверте.
##	⚠️ Транспорт — WebSocketPeer, код не запускался живьём в Godot. Второй
##	черновик по итогам "проработаем техническую часть" — многое может
##	измениться при первом реальном тестировании.
##2026-08-23 - mzs7 - добавлен AppOpReceived_S (см. ниже) — точка расширения
##	для прикладных проверок (Update/ThirdPartyFiles, см. changelog
##	Class_InternetClient.gd/Class_InternetServer.gd и План проекта/Class_Internet.md
##	→ «После установления соединения»). Раньше на месте её вызова у обоих
##	наследников были TODO-заглушки ("ответы на операции трекера, когда они
##	появятся" / "диспетчер операций трекера — появится по ходу дела") —
##	теперь это реализовано через сигнал, а не через переопределение метода,
##	потому что Start_Program.gd/test.gd ДЕРЖАТ Class_InternetClient/Server как
##	обычное поле (composition), а не наследуются от них — переопределить
##	fC_ReceivingNotification_Ch снаружи в этой архитектуре невозможно.

## Сигнал уровня "трекера" — эмитится, когда конверт несёт операцию, которую
## транспортный слой сам не обрабатывает (не Hello/AuthRequest/HelloConfirm/
## Ping) — общая точка подключения прикладной логики поверх
## Class_InternetClient/Class_InternetServer извне (см. changelog выше)
##Форматы данных:
##	vGS_Op_S: String — если конверт оказался ОТВЕТОМ на наш запрос, это Op
##		ИСХОДНОГО запроса (чтобы разбирать по тому, "на что" пришёл ответ);
##		если это НОВЫЙ запрос от собеседника — Op самого этого конверта
##	vGD_Envelope_D: Dictionary — конверт целиком, как получен (для ответа —
##		это конверт ОТВЕТА, его Messages несут результат)
##	vGF_ReceivedNowAt_F: float — когда МЫ получили этот пакет
##	vGS_ReplyRoutingKey_S: String — куда отвечать через fC_SendingMessage_Cr,
##		если нужен ответ (у сервера — проверенный UserID, у клиента — Server)
signal AppOpReceived_S(vGS_Op_S: String, vGD_Envelope_D: Dictionary, vGF_ReceivedNowAt_F: float, vGS_ReplyRoutingKey_S: String)

## Фиксированный идентификатор игрока/пользователя — см. Class_InternetClient/Server
var vGS_UserID_S: String = ""

## Токен, выданный сервером после успешного входа (см. changelog выше и
## fC_ValidateChallengeResponse_Bv/fC_ValidateToken_Bv в Class_InternetServer) —
## пусто, если авторизация не пройдена/не нужна. Кладётся АВТОМАТИЧЕСКИ в
## КАЖДОЕ исходящее сообщение этой стороны (fC_SendingMessage_Cr), поэтому
## отдельно передавать его на каждый вызов не нужно
var vGS_MyToken_S: String = ""

## Счётчик для генерации OperationNumber — растёт на каждое отправленное сообщение
var vGI_NextOperationNumber_I := 0

## Таблица отправленных сообщений, ожидающих ответа — {СоставнойКлюч: ЗаписьОжидания}
## (см. fC_BuildAnswerKey_Cr). Одна запись:
## {"Envelope": Dictionary (оригинал целиком, при повторе шлётся байт-в-байт),
##  "RecipientID": String, "ForwardingTimeArray": Array, "ForwardIndex": int,
##  "SentAtMsec": float, "WaitingUntilMsec": float, "MessageResponseCode": String,
##  "WaitingTime": float}
var vGD_WaitingResponses_D := {}

## {RecipientID: адрес/пир} — "кому я могу физически отправить прямо сейчас"
var vGD_ActiveConnections_D := {}

## Последний посчитанный {"RTT": float, "Offset": float} — обновляется в
## fC_UpdatePingFromReply_Ch при каждом успешно распознанном ответе
var vGD_LastPingInfo_D := {}


##Функционал:
##	Строит составной ключ, однозначно опознающий одно сообщение
##Форматы данных:
##	Входные: vGS_UserID_S/vGF_Time_F/vGI_OperationNumber_I — тройка оригинала
##	Выходные: String — ключ для vGD_WaitingResponses_D
func fC_BuildAnswerKey_Cr(vGS_UserID_S: String, vGF_Time_F: float, vGI_OperationNumber_I: int) -> String:
	return "%s|%f|%d" % [vGS_UserID_S, vGF_Time_F, vGI_OperationNumber_I]


##Функционал:
##	Физически отправляет сообщение адресату и, если нужен ответ, регистрирует
##	ожидание через fC_WaitingResponse_Ch. Общая для клиента и сервера
##Форматы данных:
##	Входные:
##		vGS_Op_S: String — тип операции, отдельный параметр (не ключ внутри vC_Messages)
##		vC_Messages — содержимое, формат — дело конкретной vGS_Op_S
##		vGD_AnswerTo_D: Dictionary — {"UserID","Time","OperationNumber"} оригинала,
##			если это ответ; {} — если новый запрос
##		vGS_RecipientID_S: String — кому (ключ в vGD_ActiveConnections_D)
##		vGB_AnswerNeeded_Bv: bool — нужно ли ждать ответа
##		vGF_WaitingTime_F/vGA_ForwardingTimeArray_A/vGS_MessageResponseCode_S —
##			см. fC_WaitingResponse_Ch, используются только если vGB_AnswerNeeded_Bv
##		vGF_ReceivedAt_F: float — если ЭТО сообщение само является ответом,
##			здесь — когда МЫ получили оригинал (см. changelog, "ReceivedAt" в
##			конверте, нужно получателю для честного расчёта пинга по 4 меткам).
##			-1.0 (по умолчанию) — не является ответом/неприменимо
##	Выходные: String — составной ключ ЭТОГО отправленного сообщения
##Принцип работы:
##	1. Назначает OperationNumber, собирает конверт (включая свой текущий
##		vGS_MyToken_S и переданный vGF_ReceivedAt_F)
##	2. Отправляет через _fL_TransportSend_Ch (переопределяется у наследников)
##	3. Если vGB_AnswerNeeded_Bv — регистрирует ожидание через fC_WaitingResponse_Ch
func fC_SendingMessage_Cr(
	vGS_Op_S: String,
	vC_Messages,
	vGD_AnswerTo_D: Dictionary,
	vGS_RecipientID_S: String,
	vGB_AnswerNeeded_Bv: bool = false,
	vGF_WaitingTime_F: float = 5.0,
	vGA_ForwardingTimeArray_A: Array = [1.0, 3.0, 7.0],
	vGS_MessageResponseCode_S: String = "",
	vGF_ReceivedAt_F: float = -1.0
) -> String:
	var vGI_OperationNumber_I := vGI_NextOperationNumber_I
	vGI_NextOperationNumber_I += 1
	var vGF_Time_F := Time.get_unix_time_from_system()

	var vGD_Envelope_D := {
		"UserID": vGS_UserID_S,
		"Op": vGS_Op_S,
		"Messages": vC_Messages,
		"Time": vGF_Time_F,
		"OperationNumber": vGI_OperationNumber_I,
		"AnswerTo": vGD_AnswerTo_D,
		"AnswerNeeded": vGB_AnswerNeeded_Bv,
		"Token": vGS_MyToken_S,
		"ReceivedAt": vGF_ReceivedAt_F,
	}

	_fL_TransportSend_Ch(vGS_RecipientID_S, vGD_Envelope_D)

	var vGS_Key_S := fC_BuildAnswerKey_Cr(vGS_UserID_S, vGF_Time_F, vGI_OperationNumber_I)
	if vGB_AnswerNeeded_Bv:
		fC_WaitingResponse_Ch(vGS_Key_S, vGD_Envelope_D, vGF_WaitingTime_F, vGA_ForwardingTimeArray_A, vGS_RecipientID_S, vGS_MessageResponseCode_S)

	return vGS_Key_S


##Функционал:
##	Регистрирует ожидание ответа — заводит запись в vGD_WaitingResponses_D,
##	сам повтор/таймаут делает _process (см. ниже)
func fC_WaitingResponse_Ch(
	vGS_Key_S: String,
	vGD_Envelope_D: Dictionary,
	vGF_WaitingTime_F: float,
	vGA_ForwardingTimeArray_A: Array,
	vGS_RecipientID_S: String,
	vGS_MessageResponseCode_S: String
) -> void:
	if vGA_ForwardingTimeArray_A.is_empty():
		push_warning("⚠️ fC_WaitingResponse_Ch: пустой ForwardingTimeArray — повторной отправки не будет, только один финальный таймаут")

	vGD_WaitingResponses_D[vGS_Key_S] = {
		"Envelope": vGD_Envelope_D,
		"RecipientID": vGS_RecipientID_S,
		"ForwardingTimeArray": vGA_ForwardingTimeArray_A,
		"ForwardIndex": 0,
		"SentAtMsec": Time.get_ticks_msec(),
		"WaitingUntilMsec": Time.get_ticks_msec() + _fL_NextForwardDelayMsec_F(vGA_ForwardingTimeArray_A, 0),
		"MessageResponseCode": vGS_MessageResponseCode_S,
		"WaitingTime": vGF_WaitingTime_F,
	}


##Функционал:
##	Служебная — задержка (мс) до следующей отметки ForwardingTimeArray, 0.0 если исчерпан
func _fL_NextForwardDelayMsec_F(vGA_ForwardingTimeArray_A: Array, vGI_Index_I: int) -> float:
	if vGI_Index_I >= vGA_ForwardingTimeArray_A.size():
		return 0.0
	return float(vGA_ForwardingTimeArray_A[vGI_Index_I]) * 1000.0


##Функционал:
##	Проверяет, является ли входящее сообщение ответом на что-то из
##	vGD_WaitingResponses_D — если да, снимает запись (повторов больше не будет)
##	и возвращает её; иначе — {}
func fC_TryResolveWaitingResponse_Bv(vGD_AnswerTo_D: Dictionary) -> Dictionary:
	if vGD_AnswerTo_D.is_empty():
		return {}
	var vGS_Key_S := fC_BuildAnswerKey_Cr(
		vGD_AnswerTo_D.get("UserID", ""),
		vGD_AnswerTo_D.get("Time", 0.0),
		vGD_AnswerTo_D.get("OperationNumber", -1)
	)
	if not vGD_WaitingResponses_D.has(vGS_Key_S):
		return {}
	var vGD_Entry_D: Dictionary = vGD_WaitingResponses_D[vGS_Key_S]
	vGD_WaitingResponses_D.erase(vGS_Key_S)
	return vGD_Entry_D


##Функционал:
##	Если только что снятая запись (см. fC_TryResolveWaitingResponse_Bv) —
##	действительно ответ, для которого собеседник честно указал "ReceivedAt" —
##	пересчитывает пинг/рассинхрон по полной 4-меточной формуле и сохраняет в
##	vGD_LastPingInfo_D. Общая для клиента и сервера — вызывать сразу после
##	успешного fC_TryResolveWaitingResponse_Bv
##Форматы данных:
##	Входные:
##		vGD_ResolvedEntry_D: Dictionary — то, что вернула fC_TryResolveWaitingResponse_Bv
##		vGD_IncomingEnvelope_D: Dictionary — весь входящий (уже разобранный) конверт
##		vGF_ReceivedNowAt_F: float — когда МЫ получили этот входящий пакет (t3)
##	Выходные: нет (пишет в vGD_LastPingInfo_D)
func fC_UpdatePingFromReply_Ch(vGD_ResolvedEntry_D: Dictionary, vGD_IncomingEnvelope_D: Dictionary, vGF_ReceivedNowAt_F: float) -> void:
	if vGD_ResolvedEntry_D.is_empty():
		return
	var vGF_RemoteReceivedAt_F: float = vGD_IncomingEnvelope_D.get("ReceivedAt", -1.0)
	if vGF_RemoteReceivedAt_F < 0.0:
		return # собеседник не проставил ReceivedAt (старый узел/не ответ) — считать нечестно, пропускаем

	var vGF_LocalSentAt_F: float = vGD_ResolvedEntry_D.get("Envelope", {}).get("Time", 0.0)
	var vGF_RemoteRespondedAt_F: float = vGD_IncomingEnvelope_D.get("Time", 0.0)
	vGD_LastPingInfo_D = fC_CalculatePingAndOffset_Cr(vGF_LocalSentAt_F, vGF_RemoteReceivedAt_F, vGF_RemoteRespondedAt_F, vGF_ReceivedNowAt_F)


##Функционал:
##	Точка входа для входящего сообщения — форма ОБЩАЯ, реализация РАЗНАЯ (см.
##	Class_InternetClient/Class_InternetServer). Заглушка с push_error, чтобы
##	забытое переопределение было сразу заметно
##Форматы данных:
##	Входные:
##		vGD_Envelope_D: Dictionary — весь разобранный входящий конверт как есть
##			(UserID/Op/Messages/Time/OperationNumber/AnswerTo/AnswerNeeded/Token/ReceivedAt)
##		vGF_ReceivedNowAt_F: float — когда МЫ получили этот пакет (не поле
##			конверта — локальный факт, см. changelog); пригодится, если
##			обработчик решит ответить и должен проставить "ReceivedAt" ответа
##	Выходные: нет
func fC_ReceivingNotification_Ch(vGD_Envelope_D: Dictionary, vGF_ReceivedNowAt_F: float) -> void:
	push_error("⚠️ fC_ReceivingNotification_Ch не переопределена — вызвана прямо на Class_Internet вместо наследника (Op=%s)" % vGD_Envelope_D.get("Op", "?"))


##Функционал:
##	Полная 4-меточная формула пинга/рассинхрона часов (NTP-стиль)
##Форматы данных:
##	Входные:
##		vGF_LocalSentAt_F (t0) — когда МЫ отправили запрос
##		vGF_RemoteReceivedAt_F (t1) — когда собеседник ПОЛУЧИЛ наш запрос
##		vGF_RemoteRespondedAt_F (t2) — когда собеседник ОТПРАВИЛ ответ
##		vGF_LocalReceivedAt_F (t3) — когда МЫ получили ответ
##	Выходные:
##		Dictionary — {"RTT": float, "Offset": float}; Offset — на сколько часы
##			собеседника впереди наших
##Принцип работы:
##	RTT = (t3-t0) - (t2-t1) — вычитаем время обработки на стороне собеседника
##	Offset = ((t1-t0) + (t2-t3)) / 2
func fC_CalculatePingAndOffset_Cr(vGF_LocalSentAt_F: float, vGF_RemoteReceivedAt_F: float, vGF_RemoteRespondedAt_F: float, vGF_LocalReceivedAt_F: float) -> Dictionary:
	var vGF_Rtt_F: float = (vGF_LocalReceivedAt_F - vGF_LocalSentAt_F) - (vGF_RemoteRespondedAt_F - vGF_RemoteReceivedAt_F)
	var vGF_Offset_F: float = ((vGF_RemoteReceivedAt_F - vGF_LocalSentAt_F) + (vGF_RemoteRespondedAt_F - vGF_LocalReceivedAt_F)) / 2.0
	return {"RTT": vGF_Rtt_F, "Offset": vGF_Offset_F}


##Функционал:
##	Физически отправляет байты конверта — переопределяется у наследников
func _fL_TransportSend_Ch(vGS_RecipientID_S: String, vGD_Envelope_D: Dictionary) -> void:
	push_error("⚠️ _fL_TransportSend_Ch не переопределена (RecipientID=%s)" % vGS_RecipientID_S)


##Функционал:
##	Вызывается, когда сообщение так и не получило ответ после всех попыток.
##	Базовое поведение — предупреждение; наследники переопределяют для реальной
##	обработки (например Class_InternetServer сбрасывает неподтверждённое подключение)
func _fL_OnWaitingResponseFailed_Ch(vGS_Key_S: String, vGD_Entry_D: Dictionary) -> void:
	push_warning("⚠️ Сообщение не получило ответа после всех попыток из ForwardingTimeArray (ключ %s, Op=%s)" % [vGS_Key_S, vGD_Entry_D.get("Envelope", {}).get("Op", "?")])


##Функционал:
##	Раз в кадр проверяет дедлайны в vGD_WaitingResponses_D — повторяет отправку
##	ТОГО ЖЕ конверта или, если попытки исчерпаны, вызывает _fL_OnWaitingResponseFailed_Ch.
##	⚠️ Наследники обязаны вызывать super._process(delta) в конце своего _process
func _process(_vGF_Delta_F: float) -> void:
	var vGF_NowMsec_F := Time.get_ticks_msec()
	var vGA_ExpiredKeys_A := []

	for elGS_Key_S in vGD_WaitingResponses_D:
		var vGD_Entry_D: Dictionary = vGD_WaitingResponses_D[elGS_Key_S]
		if vGF_NowMsec_F < vGD_Entry_D["WaitingUntilMsec"]:
			continue

		var vGI_NextIndex_I: int = vGD_Entry_D["ForwardIndex"] + 1
		if vGI_NextIndex_I >= vGD_Entry_D["ForwardingTimeArray"].size():
			vGA_ExpiredKeys_A.append(elGS_Key_S)
			continue

		_fL_TransportSend_Ch(vGD_Entry_D["RecipientID"], vGD_Entry_D["Envelope"])
		vGD_Entry_D["ForwardIndex"] = vGI_NextIndex_I
		vGD_Entry_D["WaitingUntilMsec"] = vGF_NowMsec_F + _fL_NextForwardDelayMsec_F(vGD_Entry_D["ForwardingTimeArray"], vGI_NextIndex_I)

	for elGS_Key_S in vGA_ExpiredKeys_A:
		_fL_OnWaitingResponseFailed_Ch(elGS_Key_S, vGD_WaitingResponses_D[elGS_Key_S])
		vGD_WaitingResponses_D.erase(elGS_Key_S)
