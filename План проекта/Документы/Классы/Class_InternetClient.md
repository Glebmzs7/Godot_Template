---
type: класс
status: работает
path: res://Godot_Template/Class_InternetClient.gd
extends: Class_Internet
depends: ["[[Class_Internet]]"]
checked: 2026-09-26
journal: "[[Журнал Class_InternetClient]]"
---
# Class_InternetClient

## Назначение
Клиентская сторона протокола [[Class_Internet]]: WebSocket-подключение к серверу по адресу (сервер игрока и глобальный сервер — просто разные адреса), рукопожатие `Hello`, вход по challenge-response, переподключение при обрыве, контроль молчания сервера.

Экраном ввода логина/пароля класс **намеренно не владеет**: данные передаёт снаружи сцена ([[Сцена Start_Program]]).

## Как подключать
```gdscript
var Class_InternetClient = load("res://Godot_Template/Class_InternetClient.gd").new()
add_child(Class_InternetClient)                      # обязательно — нужен _process
Class_InternetClient.vGS_UserID_S = "..."
Class_InternetClient.AppOpReceived_S.connect(_on_app_op)
Class_InternetClient.fxG_EstablishingConnection_CrTr("ws://127.0.0.1:9050")
```
Наружу класс не шлёт сигнал о смене состояния. Сцена сама опрашивает `vGE_State` в своём `_process`.

## Состояния
`enum ConnectionState {DISCONNECTED, CONNECTING, AUTHENTICATING, CONNECTED, RECONNECTING}` → `vGE_State`.
- `CONNECTING` — сокет открывается, отправлен `Hello`.
- `AUTHENTICATING` — сервер требует пароль. Ждём `fC_SendCredentials_Ch` или `fC_RegisterAccount_Ch` снаружи.
- `CONNECTED` — вход выполнен (или не нужен).
- `RECONNECTING` — обрыв, идёт переподключение с растущей задержкой.

## Переменные (основные)
| Имя | Значение | Смысл |
|---|---|---|
| `SERVER_RECIPIENT_ID` | `"Server"` | Единственный адресат |
| `vG_TlsOptions_L` | `null` | TLS-опции для `wss://`. Выставить **до** подключения; `null` — без шифрования. Самоподписанному сертификату сервера игрока нужно явно доверять здесь |
| `vGA_ReconnectDelayArray_A` | `[1, 2, 4, 8, 16, 30]` с | Задержки переподключения |
| `_vGF_KeepAliveTimeoutSeconds_F` | от сервера | Сколько терпим молчание сервера; `0` — проверка выключена |

## Функции
- **`fxG_EstablishingConnection_CrTr(vGS_ServerAddress_S) -> bool`** — открыть WebSocket; `true`, если попытка запущена. Попытка одна: повторы включаются, только если соединение уже было открыто и потом оборвалось.
- **`fC_SendCredentials_Ch(login, password)`** — начать вход: `AuthRequest {Login}`. Пароль хранится, пока не посчитан ответ на Challenge, затем стирается.
- **`fC_RegisterAccount_Ch(login, password)`** — самостоятельная регистрация: `Register {Login, Password}`. Работает только в `AUTHENTICATING`. Ответ `RegisterResult` приходит через `AppOpReceived_S`. ⚠️ Пароль в этом пакете идёт открытым текстом — нужен WSS.
- **`fC_Reconnect_Ch()`** — полное переподключение (обрыв всего транспорта, а не одного сообщения).
- **`fC_ReceivingNotification_Ch(envelope, receivedNow)`** — разбор входящего:
	- если это ответ на наш запрос — разбор по `Op` **оригинала**: `Hello` → `_fL_OnHelloReply_Ch`, `AuthRequest` → `_fL_OnChallenge_Ch`, `HelloConfirm` → `_fL_OnAuthResult_Ch`, остальное → сигнал `AppOpReceived_S`;
	- если это push от сервера — по его `Op` (`Ping` зарезервирован); при `AnswerNeeded` отвечает `Ack`.
- **Служебные:**
	- `_fL_OnHelloReply_Ch` — читает `RequireAuth`/`KeepAliveTimeoutSeconds`; без пароля → `CONNECTED` + `UserInfo`;
	- `_fL_OnChallenge_Ch` — считает `Response = SHA256(SHA256(Salt+Password) + Challenge)`, шлёт `HelloConfirm`;
	- `_fL_OnAuthResult_Ch` — `AuthSuccess` → сохраняет `Token`, `CONNECTED`; `AuthFailed` → сервер сам закроет соединение;
	- `_fL_OnWaitingResponseFailed_Ch` — нет ответа на шаг рукопожатия → `fC_Reconnect_Ch()` (раньше клиент мог зависнуть навсегда);
	- `_fL_BuildUserInfoPayload_Cr` — пакет `UserInfo`, сейчас только `UserID`;
	- `_fL_GetBestEffortLocalIP_Cr` — локальный IP для информационного поля `Hello`;
	- `_fL_Sha256Hex_S`, `_fL_TransportSend_Ch`, `_fL_HandleIncomingPacket_Ch`;
	- `_process` — опрос сокета, отправка `Hello`, приём пакетов, контроль молчания и переподключения; в конце вызывает `super._process`.

## Известные проблемы / открытые вопросы
- При первой неудачной попытке подключения автоматического повтора нет: повторы запускает сцена кнопкой «Повторить подключение».
- Состав `UserInfo` не решён (заглушка).
- `Register` отправляет пароль открытым текстом, если TLS не включён.
- Имена функций в старом стиле, не по [[README]].

## Связи
- Родитель: [[Class_Internet]]; сервер: [[Class_InternetServer]]
- Используется: [[Сцена Start_Program]]
- История: [[Журнал Class_InternetClient]]
