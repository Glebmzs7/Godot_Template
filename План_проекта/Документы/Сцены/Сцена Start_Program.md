---
type: сцена
status: работает
path: res://Scenes/Start_Program/Start_Program.tscn
extends: Node
depends: ["[[Class_UI]]", "[[Class_Logger]]", "[[Class_Json]]", "[[Class_Localization]]", "[[Class_InternetClient]]", "[[Class_FileIntegrity]]"]
checked: 2026-09-27
journal: "[[Журнал Сцена Start_Program]]"
---
# Сцена Start_Program

## Назначение
Точка входа программы (главная сцена в `project.godot`). Стартовый экран с чек-листом из 5 предзапусковых проверок, выбором аккаунта, подключением к серверу, окнами Поддержка/Настройки. Когда проверки пройдены, кнопка «Войти» ведёт на [[Сцена Home]].

- Сцена: корневая `Control`-нода `StartProgram` на весь экран, скрипт `Start_Program.gd` (~5100 строк, из них ~1000 — changelog в начале файла).
- **Весь экран собирается кодом** через [[Class_UI]] из конфига `_fC_BuildScreenConfig_Cr`. В `.tscn` ничего, кроме корня, нет.

## Порядок запуска (`_ready`)
1. `add_child(Class_UI)` — без этого не работает `get_tree()` внутри [[Class_UI]].
2. Загрузка переводов ([[Class_Localization]]), настроек (`Save/Settings.json`), списка аккаунтов (`Save/AccountsList.json`). Применение языка и размера окна / полноэкранного режима.
3. `Logger.fxG_StartingLogger_CrTr()` + поток `"StartProgram"`. **Проверка «Logger»** — создан ли файл лога. Провал — нативное окно ОС с ошибкой (`_fC_FatalStartupError_Ch`), дальше программа не идёт.
4. Сборка экрана (`_fC_BuildScreen_Ch` → `Class_UI.fC_MassCreatingNode_0001`). **Проверка «Interface»** — число созданных нод равно числу нод в конфиге. Провал — то же фатальное окно.
5. **Проверка «Server»** начинается с окна выбора аккаунта.
6. Подписка на изменение размера окна — живой пересчёт размеров шрифтов.
7. Ошибка локализации (если была) показывается в окне информации и пишется в лог; программа продолжает работать.

## Экран (блоки конфига)
| Блок | Что это |
|---|---|
| `CheckListPanel` | Чек-лист: 5 строк со статусом `–` ожидает, `…` проверяется, `✓` пройдено, `✗` провал (цвета — `vGD_StatusColors_D`) |
| `CompanyIconRect` | Иконка |
| `InfoBoxPanel` | Окно информации под проверками: статусный текст, **окно выбора аккаунта**, кнопки «Повторить подключение» / «Продолжить без сервера» / «Войти» |
| `TopButtonsHBox` | Кнопки «Поддержка» и «Настройки» |
| `ModalOverlay` | Модальное окно Поддержка/Настройки с размытием фона (`Shaders/ModalOverlayBlur.gdshader`) |
| `ScreenInfoPopupVBox`, `ScreenApplyConfirmVBox`, `LoggerInfoPopupVBox` | Маленькие окна-уведомления поверх настроек |

- **Ориентация:** `Vertical` (по умолчанию) и `Horizontal`. Позиции — в долях экрана (anchor без пиксельных отступов). `fC_SwitchOrientation_Ch()` пересобирает экран через `Class_UI.fC_SyncingNodesWithConfig_1111`. Переключателя в интерфейсе пока нет.
- **Шрифты** масштабируются от размера окна и множителя `FontScale` (базовые размеры — `vGD_BaseFontSizes_D`).
- **Надписи** — ключи локализации (`"SETTINGS_TITLE"` и т.п.). Часть служебных сообщений — русские строки прямо в коде.

## Чек-лист проверок
Порядок `vLA_CheckOrder_A`: `Logger` → `Interface` → `Server` → `Update` → `ThirdPartyFiles`. Статус меняется через публичный `fC_SetCheckStatus_Ch(ключ, "waiting"|"checking"|"passed"|"failed", сообщение)`. Когда все `passed` — появляется «Войти» (`_fC_UpdateOverallProgress_Ch`).

### Server — выбор аккаунта и подключение
1. В `InfoBoxPanel` показывается список аккаунтов из `AccountsList.json` (`{Ник: {"ID", "Password"}}`, с прокруткой) и кнопка «+».
2. «+» открывает форму Ник/ID/Пароль с кнопками «Применить», «Зарегистрироваться», «Отмена». После сохранения список обновляется на лету (`_fC_RefreshScreenAfterDataChange_Ch`).
3. Кнопки OAuth (ВК/Google/Яндекс) — заглушки, см. [[OAuth сторонние аккаунты]].
4. **Выбран реальный аккаунт** — `Class_InternetClient` подключается к `SERVER_ADDRESS_S = "ws://127.0.0.1:9050"`:
	- если сервер требует пароль, отправляются сохранённые данные аккаунта;
	- в режиме регистрации вместо этого отправляется `Register`;
	- пока идёт подключение, в окне тикает таймер.
5. **Выбрано техническое значение `"Server"`** — сцена переключается на [[Сцена StartServer]], этот экземпляр программы становится сервером.
6. **Не удалось за `SERVER_CONNECT_TIMEOUT_SECONDS_F` (8 с)** — или провалилась любая из трёх сетевых проверок — появляются кнопки:
	- «Повторить подключение» — перезапускает только проверку Server;
	- «Продолжить без сервера» — **автономный режим**: `Server`/`Update`/`ThirdPartyFiles` помечаются `✗`, но «Войти» всё равно появляется (исключение `AUTONOMOUS_SKIPPED_CHECKS_A`).

### Update и ThirdPartyFiles
После подключения (`_fC_OnServerConnected_Ch`):
- **Update:** `CheckUpdate {Version: APP_VERSION_S}` → `CheckUpdateResult`. Совпадение версии — `✓`, иначе `✗` с сообщением об обновлении (скачивания нет).
- **ThirdPartyFiles:** отпечатки всех проверяемых файлов ([[Class_FileIntegrity]]) → `CheckFiles` → `CheckFilesResult`. `✓`, только если нет изменённых, посторонних и отсутствующих файлов.

Ответы приходят через `AppOpReceived_S` → `_fC_OnClientAppOpReceived_Ch`. Протокол — [[Class_Internet]].

## Окно Настройки / Поддержка
Одно модальное окно на два источника (`_fC_OpenModal_Ch`). Закрывается крестиком, кликом по затемнению или Esc. Настройки сохраняются в `Save/Settings.json` сразу при изменении. Категории:
| Категория | Что настраивается |
|---|---|
| Язык | Список языков с поиском (фильтр по алфавиту ввода, [[Class_Localization]]); смена мгновенная |
| Экран | Ширина/высота, пресеты по соотношениям сторон, полноэкранный режим, масштаб шрифта. Размер **не применяется сразу**: при закрытии настроек появляется окно «Применить/Отмена» |
| Звук | Громкость музыки и интерфейса. Только сохраняется, к звуку пока не подключено |
| Подтверждения | Включение окон-уведомлений; параметры защиты от автонажатия |
| Логи и реплеи | 6 лимитов (количество/возраст/объём для логов и для реплеев) с галочками включения. Применяются после перезапуска — об этом предупреждает окно |

**Защита от автонажатия** на окне «Применить/Отмена»: первые `AutoClickProtectionSeconds` секунд кнопка «Применить» не срабатывает. Вместо этого она «убегает» в случайное место (не больше `AutoClickDodgeLimit` раз), рядом показан обратный отсчёт.

## Ключи `Settings.json`
`Locale`, `ScreenWidth`, `ScreenHeight`, `Fullscreen`, `FontScale`, `MusicVolume`, `InterfaceVolume`, `Log/Replay Max Count/Age/Size (+Enabled)`, `ShowScreenChangeInfoPopup`, `ShowScreenApplyConfirmPopup`, `ShowLoggerRestartInfoPopup`, `AutoClickProtectionSeconds`, `AutoClickDodgeLimit`. Отсутствующие ключи достраиваются значениями по умолчанию (`_fC_LoadSettings_Cr`).

## Константы, которые стоит вынести в настройки
`APP_VERSION_S = "0.1.0.0"`, `SERVER_ADDRESS_S`, `SERVER_CONNECT_TIMEOUT_SECONDS_F`, `vSV2_Scene_size_V2i = 540×900` (размер дизайн-холста).

## Функции (группы)
Всего ~95 функций, подробные описания — в `##`-комментариях над каждой в коде.
- **Запуск:** `_ready`, `_process` (опрос состояния клиента, таймер подключения), `_unhandled_input` (Esc).
- **Конфиг и экран:** `_fC_NodeCfg`, `_fC_MergeInspector_Cr`, `_fC_BuildScreenConfig_Cr`, `_fC_BuildModalChrome_Cr`, `_fC_BuildConfirmOverlay_Cr`, `_fC_BuildScreen_Ch`, `fC_SwitchOrientation_Ch`, `_fC_RefreshScreenAfterDataChange_Ch`, `_fC_CountNodeConfigs_I`, `_fC_VerifyInterfaceBuilt_Bv`.
- **Шрифты и стили:** `_fC_FontSize_I`, `_fC_CollectFontSizeUpdates_Cr`, `_fC_RescaleFonts_Ch`, `_fC_ModalOverlayBlurMaterial_Cr`, `_fC_ModalCardStyle_Cr`.
- **Данные:** `_fC_LoadSettings_Cr`, `_fC_SaveSettings_Ch`, `_fC_LoadAccountsList_Cr`, `_fC_SaveAccountsList_Ch`.
- **Чек-лист и сообщения:** `fC_SetCheckStatus_Ch`, `_fC_UpdateOverallProgress_Ch`, `_fC_ShowInfo_Ch`, `_fC_ReportError_Ch`, `_fC_FatalStartupError_Ch`, `_fC_OnProceedPressed_Ch`.
- **Аккаунты и сервер:** `_fC_ShowAccountPicker_Ch`, `_fC_OnAccountOptionPressed_Ch`, `_fC_RunServerCheck_Ch`, `_fC_StartClientConnection_Ch`, `_fC_SendStoredCredentials_Ch`, `_fC_SendRegistrationRequest_Ch`, `_fC_OnServerConnected_Ch`, `_fC_SendUpdateCheckRequest_Ch`, `_fC_SendFileIntegrityCheckRequest_Ch`, `_fC_OnClientAppOpReceived_Ch`, `_fC_HandleUpdateCheckResult_Ch`, `_fC_HandleFileIntegrityResult_Ch`, `_fC_HandleRegisterResult_Ch`, `_fC_OfferAutonomousMode_Ch`, `_fC_ShowAutonomousModeButton_Ch`, `_fC_OnRetryConnectionPressed_Ch`, `_fC_OnAutonomousModePressed_Ch`, `_fC_UpdateConnectingTimerLabel_Ch`, `_fC_OnOAuthButtonPressed_Ch`.
- **Форма аккаунта:** `_fC_OnAccountAddButtonPressed_Ch`, `_fC_OnAccountAddCancelPressed_Ch`, `_fC_OnAccountAddSavePressed_Ch`, `_fC_OnAccountAddRegisterPressed_Ch`, `_fL_ReadAndValidateAccountAddForm_Cr`, `_fC_ClearAccountAddForm_Ch`, `_fC_ShowAccountPickerMessage_Ch`.
- **Модальное окно и категории:** `_fC_ToggleModal_Ch`, `_fC_OpenModal_Ch`, `_fC_CloseModal_Ch`, `_fC_OnOverlayGuiInput_Ch`, `_fC_ApplySettingsToUI_Ch`, `_fC_UpdateModalContentVisibility_Ch`, `_fC_OnSettingsCategoryToggled_Ch`.
- **Язык:** `_fC_RebuildLanguageList_Ch` (единственное место, где ноды создаются напрямую `Button.new()`, а не через конфиг), `_fC_OnLanguageSearchChanged_Ch`, `_fC_OnLanguageOptionPressed_Ch`.
- **Экран:** `_fC_OnScreenSizeChanged_Ch`, `_fC_OnFontScaleSubmitted_Ch`, `_fC_OnScreenPresetPressed_Ch`, `_fC_OnPresetGroupToggled_Ch`, `_fC_OnFullscreenToggled_Ch`, `_fC_QueueScreenSizeChange_Ch`, `_fC_QueueFullscreenChange_Ch`, `_fC_MarkScreenSizeDirty_Ch`, `_fC_ApplyScreenSize_Ch`, `_fC_CommitScreenSizeChange_Ch`, окна `_fC_ShowScreenInfoPopup_Ch` / `_fC_ShowScreenApplyConfirm_Ch` и их обработчики, защита `_fC_OnApplyCountdownTick_Ch`, `_fC_UpdateApplyCountdownDisplay_Ch`, `_fC_OnScreenApplyButtonPressed_Ch`, `_fC_DodgeApplyButton_Ch`.
- **Подтверждения:** `_fC_OnConfirmationToggle_Ch`, `_fC_UpdateConfirmToggleVisual_Ch`, `_fC_OnConfirmSourceToggled_Ch`, `_fC_UpdateConfirmSourceVisibility_Ch`, `_fC_OnAutoClickProtectionSubmitted_Ch`, `_fC_OnAutoClickDodgeLimitSubmitted_Ch`.
- **Звук, логи:** `_fC_OnSoundSliderChanged_Ch`, `_fC_OnLoggerLimitToggled_Ch`, `_fC_UpdateLoggerCheckVisual_Ch`, `_fC_OnLoggerLimitSubmitted_Ch`, `_fC_ShowLoggerInfoPopup_Ch` и обработчики.

⚠️ Программная синхронизация чекбоксов/переключателей с настройками использует `set_pressed_no_signal()`, а не `button_pressed = …`: иначе сигнал `toggled` срабатывает сам и вызывает лишние окна.

## Как проверить клиент + сервер на одном компьютере
В редакторе Godot — «Run Instances» (рядом с Play) → 2 экземпляра. В одном выбрать `"Server"`, в другом — реальный аккаунт.

## Известные проблемы / открытые вопросы
- Файл очень большой (~5100 строк, из них ~1000 — changelog). Стоит подумать о разбиении: экран, настройки, аккаунты, сеть.
- Пароли аккаунтов хранятся открытым текстом в `AccountsList.json`.
- Часть сообщений — русские литералы, а не ключи локализации.
- При первой неудачной попытке подключения автоматического повтора нет, только кнопка.
- Звук не подключён. Переключателя ориентации в интерфейсе нет.
- Лог этой сцены — поток `"StartProgram"`. Сборка экрана через [[Class_UI]] в него не пишет (поток `Class_UI` не регистрируется).
- Имена функций в старом стиле, не по [[README]].

## Связи
- Использует: [[Class_UI]], [[Class_Logger]], [[Class_Json]], [[Class_Localization]], [[Class_InternetClient]], [[Class_FileIntegrity]]
- Ведёт на: [[Сцена Home]], [[Сцена StartServer]]
- Планы: [[OAuth сторонние аккаунты]]
- История: [[Журнал Сцена Start_Program]]
