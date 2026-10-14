---
type: класс
status: работает
path: res://Godot_Template/Class_Internet.gd
extends: Node
depends: []
checked: 2026-09-26
journal: "[[Журнал Class_Internet]]"
---
# Class_Internet

## Назначение
Родительский класс сетевого обмена — всё, что **одинаково** у клиента и сервера:
- сборка конверта сообщения и отправка;
- ожидание ответа с повторами по расписанию;
- сопоставление ответа с запросом;
- расчёт пинга и рассинхрона часов.

Разное у клиента и сервера (установка соединения, транспорт, разбор входящих) реализуют наследники [[Class_InternetClient]] и [[Class_InternetServer]].

Один протокол и для **сервера игрока** (поднимается прямо в клиентском процессе, «host and play»), и для будущего **глобального сервера** (headless-сборка того же кода). Отдельного стека под сервер нет — всё на GDScript.

## Как подключать
Напрямую не используется — только через наследников. Наследник — `Node` с `_process`, поэтому его **обязательно** добавляют в дерево (`add_child`). Наследники в своём `_process` обязаны вызывать `super._process(delta)`: здесь идут повторы и таймауты.

## Конверт сообщения
Каждое сообщение — словарь (передаётся как JSON):
| Поле | Смысл |
|---|---|
| `UserID` | Постоянный идентификатор отправителя (у сервера — `"Server"`) |
| `Op` | Тип операции. По нему получатель выбирает обработку |
| `Messages` | Содержимое. Формат зависит от `Op`, не обязательно словарь |
| `Time` | Когда отправлено (unix-время с дробной частью) |
| `OperationNumber` | Порядковый номер сообщения у отправителя (растущий счётчик). Не путать с `Op` |
| `AnswerTo` | Если это ответ — `{UserID, Time, OperationNumber}` оригинала; иначе `{}` |
| `AnswerNeeded` | Нужен ли ответ |
| `Token` | Токен после входа (добавляется автоматически из `vGS_MyToken_S`); пусто, если авторизации нет |
| `ReceivedAt` | Только в ответах: когда отвечающий получил оригинал (нужно для пинга) |

**Опознание сообщения** — составной ключ `UserID + Time + OperationNumber` (`fC_BuildAnswerKey_Cr`): три поля вместе, чтобы не зависеть только от точности `Time`.

## Переменные
| Имя | Что хранит |
|---|---|
| `vGS_UserID_S` | Свой UserID |
| `vGS_MyToken_S` | Выданный сервером токен (прикладывается ко всем исходящим) |
| `vGI_NextOperationNumber_I` | Счётчик `OperationNumber` |
| `vGD_WaitingResponses_D` | Ожидающие ответа: `{ключ: {"Envelope", "RecipientID", "ForwardingTimeArray", "ForwardIndex", "SentAtMsec", "WaitingUntilMsec", "MessageResponseCode", "WaitingTime"}}` |
| `vGD_ActiveConnections_D` | `{RecipientID: адрес/пир}` — кому можно отправить прямо сейчас |
| `vGD_LastPingInfo_D` | Последний `{"RTT", "Offset"}` |

## Сигнал
**`AppOpReceived_S(vGS_Op_S, vGD_Envelope_D, vGF_ReceivedNowAt_F, vGS_ReplyRoutingKey_S)`** — пришла **прикладная** операция, которую транспортный слой сам не обрабатывает. Через этот сигнал сцены подключают свою логику: сцены держат клиент/сервер как поле, а не наследуются от них.
- `vGS_Op_S` — если пришёл ответ на наш запрос, это `Op` **исходного запроса**; если новый запрос — `Op` самого входящего.
- `vGS_ReplyRoutingKey_S` — куда отвечать: у сервера — проверенный UserID, у клиента — `"Server"`.

## Функции
- **`fC_SendingMessage_Cr(Op, Messages, AnswerTo, RecipientID, AnswerNeeded = false, WaitingTime = 5.0, ForwardingTimeArray = [1.0, 3.0, 7.0], MessageResponseCode = "", ReceivedAt = -1.0) -> String`** — собрать конверт (номер, токен, `ReceivedAt`), отправить через `_fL_TransportSend_Ch`, при `AnswerNeeded` — зарегистрировать ожидание. Возвращает ключ сообщения.
- **`fC_WaitingResponse_Ch(...)`** — завести запись ожидания. Повторы и таймаут делает `_process`.
- **`_process(delta)`** — раз в кадр проверяет сроки ожидания. Если срок вышел, отправляет **тот же конверт** повторно по следующей отметке `ForwardingTimeArray` (например `[1.0, 3.0, 7.0]` с). Когда попытки кончились, вызывает `_fL_OnWaitingResponseFailed_Ch`.
- **`fC_TryResolveWaitingResponse_Bv(AnswerTo) -> Dictionary`** — если входящее — ответ на наше ожидание, снять запись и вернуть её; иначе `{}`.
- **`fC_UpdatePingFromReply_Ch(entry, envelope, receivedNow)`** — после успешного сопоставления пересчитать пинг, если собеседник указал `ReceivedAt`.
- **`fC_CalculatePingAndOffset_Cr(t0, t1, t2, t3) -> {"RTT", "Offset"}`** — формула на 4 метках (как в NTP):
	- t0 — мы отправили; t1 — собеседник получил; t2 — собеседник ответил; t3 — мы получили;
	- `RTT = (t3 − t0) − (t2 − t1)`;
	- `Offset = ((t1 − t0) + (t2 − t3)) / 2` — на сколько часы собеседника впереди.
	
	Устройства синхронизируются только с сервером — он источник истины по времени.
- **Переопределяются наследниками:**
	- `fC_ReceivingNotification_Ch(envelope, receivedNow)` — здесь заглушка с `push_error`, чтобы забытое переопределение было видно сразу;
	- `_fL_TransportSend_Ch(recipient, envelope)`;
	- `_fL_OnWaitingResponseFailed_Ch(key, entry)` — здесь просто предупреждение.
- `_fL_NextForwardDelayMsec_F` — служебная: задержка до следующей попытки.

## Протокол соединения (общая схема)
1. Клиент → `Hello` (`UserID` в конверте, IP — информационно в `Messages`).
2. Сервер отвечает `{RequireAuth, KeepAliveTimeoutSeconds}`.
3. Без авторизации — клиент сразу подключён, шлёт `UserInfo` (состав пока не решён, заглушка).
4. С авторизацией — **challenge-response + токен**:
	- клиент → `AuthRequest {Login}`;
	- сервер → `Challenge {Challenge, Salt}`;
	- клиент считает `Intermediate = SHA256(Salt + Password)`, `Response = SHA256(Intermediate + Challenge)` → `HelloConfirm {Response}`;
	- сервер сверяет со `SHA256(PasswordHash + Challenge)` → `AuthSuccess {Token, KeepAliveTimeoutSeconds}` или `AuthFailed` (соединение закрывается).
	
	Пароль по сети не передаётся.
5. **Регистрация** (только когда сервер требует авторизацию): `Register {Login, Password}` → `RegisterResult {Ok, Error}`. Здесь пароль идёт открытым текстом — поэтому по-хорошему только по WSS.
6. **Молчание дольше `KeepAliveTimeoutSeconds`** (у сервера по умолчанию 20 с) — соединение считается разорванным, даже если сокет формально открыт.
7. **Переподключение того же UserID** — сервер переносит маршрутизацию на новый сокет, старый закрывает («смена IP»).
8. На входящий запрос с `AnswerNeeded` без специального обработчика клиент отвечает `Ack`.

## Прикладные операции
Идут через сигнал `AppOpReceived_S`, обработчики — в сценах:
| Запрос (клиент → сервер) | Ответ (сервер → клиент) | Обработчики |
|---|---|---|
| `CheckUpdate {Version}` | `CheckUpdateResult {LatestVersion, UpToDate}` | [[Сцена Start_Program]] / [[Сцена StartServer]] |
| `CheckFiles {Files: [отпечаток...]}` | `CheckFilesResult {Ok, Mismatches, Unexpected, Missing}` | то же, отпечатки — [[Class_FileIntegrity]] |

## Известные проблемы / открытые вопросы
- **`WaitingTime` сохраняется, но нигде не используется** — повторы управляются только `ForwardingTimeArray`. Либо реализовать общий потолок ожидания, либо убрать параметр.
- **Название `OperationNumber`** легко спутать с `Op`. Предлагалось `SequenceNumber` — не решено.
- **Нет отдельного heartbeat/ping.** `Ping` зарезервирован в клиенте, но сервер его не шлёт. Живость соединения держится только за счёт обычного трафика.
- **Слабое место авторизации:** `PasswordHash` на сервере фактически равнозначен паролю для входа. Кража `Users.json` позволяет отвечать на Challenge. Осознанный компромисс, можно усилить позже.
- **NAT / сервер игрока вне локальной сети** — нужен проброс порта или ретрансляция через глобальный сервер. Не решено.
- Точность `Time` при JSON-сериализации теоретически может сорвать сопоставление ключей. На практике полный цикл Hello → CheckUpdate → CheckFiles работает.
- Имена функций в старом стиле, не по [[README]].

## Связи
- Наследники: [[Class_InternetClient]], [[Class_InternetServer]]
- Используют: [[Сцена Start_Program]], [[Сцена StartServer]]
- Планы: [[OAuth сторонние аккаунты]]
- История: [[Журнал Class_Internet]]
