---
type: класс
status: работает
path: res://Godot_Template/Class_InternetServer.gd
extends: Class_Internet
depends: ["[[Class_Internet]]", "[[Class_Json]]"]
checked: 2026-09-26
journal: "[[Журнал Class_InternetServer]]"
---
# Class_InternetServer

## Назначение
Серверная сторона протокола [[Class_Internet]]:
- слушает TCP-порт, принимает WebSocket-подключения (опционально через TLS);
- ведёт маршрутизацию по подключениям;
- проверяет вход (challenge-response), выдаёт токены, регистрирует пользователей;
- следит за молчанием клиентов.

Прикладные операции (`CheckUpdate`, `CheckFiles` и т.п.) не обрабатывает сам — отдаёт их через сигнал `AppOpReceived_S` сцене ([[Сцена StartServer]]).

## Два режима
- **Сервер игрока** (`vGB_RequireAuth_Bv = false`, по умолчанию) — аккаунтов нет, заявленному `UserID` доверяем сразу.
- **Глобальный сервер** (`true`) — нужен логин/пароль. До успешного входа подключение адресуется внутренним `ConnectionId`, после — настоящим `UserID`. Прикладные сообщения принимаются только с действительным `Token`.

## Как подключать
```gdscript
var Class_InternetServer = load("res://Godot_Template/Class_InternetServer.gd").new()
add_child(Class_InternetServer)                           # обязательно — нужен _process
Class_InternetServer.AppOpReceived_S.connect(_on_app_op)
# опционально: Class_InternetServer.fC_ConfigureTls_Bv("cert.crt", "key.key")
Class_InternetServer.fxG_EstablishingConnection_CrTr(9050, false)
```

## Хранилище пользователей
`FileUsers_S = "res://Save/Server/Users.json"` — `{Login: {"Salt", "PasswordHash"}}`, где `PasswordHash = SHA256(Salt + Password)`, соль — 16 случайных байт. Файл не создаётся автоматически: папка `Save/Server/` должна существовать, см. [[Class_Json]].

## Переменные (основные)
| Имя | Значение | Смысл |
|---|---|---|
| `SERVER_SELF_USERID_S` | `"Server"` | Свой UserID; зарезервирован, зарегистрировать нельзя |
| `vGB_RequireAuth_Bv` | `false` | Режим (см. выше) |
| `vGB_UseTls_Bv` | `false` | TLS включается через `fC_ConfigureTls_Bv` |
| `vGF_KeepAliveTimeoutSeconds_F` | `20.0` | Сколько терпим молчание клиента; это же значение сообщается клиенту |
| `vGD_PendingTlsConnections_D` | — | Приняты по TCP, ждут TLS-рукопожатия |
| `vGD_PendingConnections_D` | — | Ждут WebSocket-рукопожатия |
| `vGD_LastActivityMsec_D` | — | Последняя активность по ключу маршрутизации |
| `vGD_PendingChallenges_D` | — | `{ConnId: {Login, Challenge}}` между `AuthRequest` и `HelloConfirm` |
| `vGD_ActiveTokens_D` | — | `{UserID: Token}` — один активный токен на пользователя |

## Функции
- **`fxG_EstablishingConnection_CrTr(port, requireAuth = false) -> bool`** — начать слушать порт.
- **`fC_ConfigureTls_Bv(certPath, keyPath) -> bool`** — загрузить сертификат и ключ, включить TLS (`wss://`). Вызывать **до** запуска.
- **`fC_ReceivingNotification_Ch(envelope, receivedNow, routingKey = "")`** — разбор входящего. Всегда пытается сопоставить ответ и всегда разбирает `Op`:
	- `Hello` → `_fL_OnHello_Ch`;
	- `AuthRequest` → `_fL_OnAuthRequest_Ch`;
	- `HelloConfirm` → `_fL_OnHelloConfirm_Ch`;
	- `Register` → `_fL_OnRegisterRequest_Ch`;
	- `UserInfo` → `_fL_OnUserInfo_Ch` (заглушка);
	- остальное — через `_fL_ResolveTrustedUserID_Cr`, затем в `AppOpReceived_S`.
- **`fC_RegisterUser_Ch(login, password)`** — завести пользователя (соль + хеш, сохранить в `Users.json`).
- **`fC_ValidateChallengeResponse_Bv(login, response, challenge) -> bool`** — `SHA256(PasswordHash + Challenge) == Response`.
- **`fC_ValidateToken_Bv(userID, token) -> bool`** — токен совпадает с выданным.
- **Служебные:**
	- `_fL_OnHello_Ch` — без авторизации сразу переносит подключение на UserID; отвечает `RequireAuth` + `KeepAliveTimeoutSeconds`;
	- `_fL_OnAuthRequest_Ch` — генерирует Challenge, отвечает `Challenge {Challenge, Salt}`;
	- `_fL_OnHelloConfirm_Ch` — проверяет ответ: успех → перенос на UserID (= Login) + `AuthSuccess {Token, ...}`; неуспех → `AuthFailed` и разрыв;
	- `_fL_OnRegisterRequest_Ch` — проверки: аккаунты вообще используются, логин не пуст, пароль ≥ 4 символов, логин не `"Server"` и не занят → `RegisterResult {Ok, Error}`;
	- `_fL_ResolveTrustedUserID_Cr` — без авторизации доверяет заявленному ID, с авторизацией — только при верном токене;
	- `_fL_RenameConnectionKey_Ch` — перенос живого подключения на новый ключ; если под этим UserID уже было подключение, старое закрывается (переподключение, смена IP);
	- `_fL_OnWaitingResponseFailed_Ch` — не дождались ответа на Challenge → сброс подключения;
	- `_fL_OnClientStreamAccepted_Ch`, `_fL_PromoteConnection_Ch`, `_fL_GenerateConnectionId_Cr`, `_fL_DropConnection_Ch`, `_fL_GetUserSalt_Cr`, `_fL_HashPassword_S`, `_fL_Sha256Hex_S`, `_fL_TransportSend_Ch`, `_fL_HandleIncomingPacket_Ch`;
	- `_process` — приём TCP, продвижение TLS/WS-рукопожатий, опрос пакетов и единая проверка молчания (покрывает и «подключился и не сказал Hello», и «замолчал позже»). Итерирует по снимку ключей. В конце вызывает `super._process`.

## Известные проблемы / открытые вопросы
- `UserInfo` — заглушка, состав полей не решён.
- `PasswordHash` фактически равнозначен паролю для входа (см. [[Class_Internet]]).
- Самоподписанный сертификат сервера игрока клиенту нужно явно доверить; системное хранилище доверяет только настоящим центрам сертификации.
- Токены живут только в памяти: после перезапуска сервера всем нужно войти заново.
- Имена функций в старом стиле, не по [[README]].

## Связи
- Родитель: [[Class_Internet]]; клиент: [[Class_InternetClient]]
- Используется: [[Сцена StartServer]]
- Планы: [[OAuth сторонние аккаунты]]
- История: [[Журнал Class_InternetServer]]
