## 🇬🇧 Jerkgram 1.2.0

Jerkgram moves to Telegram 13.2 with local profile customization, a unified Local Premium section and the option to keep chats after removal from groups.

This release also reworks translation, improves bot-account history and expands transparent settings.

Changes below are relative to Jerkgram 1.1.0.

### ⚠️ Important: bot accounts

Bot-account login and use remain experimental and may be unstable. Reading or sending messages may result in deletion of the bot account.

Do not use this feature with important bots. We need further observation and feedback to investigate these issues.

Report problems in [Jerkgram Community](https://t.me/JerkgramCommunity). Include the build number, what you did and what happened. Never share bot tokens or other credentials.

### Telegram 13.2

- Updated the Telegram codebase from 13.0 to 13.2.
- Adapted existing Jerkgram features to the new version.
- Fixed compatibility issues in settings, profiles and message history.

### Local Premium

- Added a single section for managing local Premium features.
- Added a master switch. Turning it off preserves your individual settings.
- Added access to Premium app icons through Telegram’s native icon picker.
- Added Download Boost with Off, Medium and Maximum modes.
- Added an option to hide supported sponsored messages and sponsored search results.

These features do not change your actual Telegram Premium status.

Download Boost adjusts how eligible files are downloaded. Speed still depends on your connection and Telegram servers; server-side limits remain.

Ad suppression does not remove ordinary promotional posts, all recommendations or every Premium offer.

### Local profile customization

- Added local emoji status with an expiration setting.
- Added local name, profile and reply colors, plus background emoji.
- Integrated these options into Telegram’s native profile controls.
- Improved behavior when switching accounts or when a status expires.
- Prevented an outdated picker from applying changes after its settings have changed.

Profile customization is visible only on your device. It does not change how other people see your profile.

Bot accounts are excluded. Local profile settings are not included in existing backups.

### Translation

- Reworked enhanced translation and added an account-specific switch.
- Kept the native Telegram translation path for actual Premium accounts.
- Added Telegram text translation with a system fallback for supported cloud messages.
- Kept secret content on a separate local-only path.
- Improved support for text, captions, replies, polls and completed audio transcripts.
- Improved formatting and link handling in supported results.
- Prevented outdated results from replacing edited messages or appearing after a language or account change.
- Improved cancellation, error handling and retry behavior.
- Prevented failed requests from saving the original text as a successful translation.
- Limited automatic language-model downloads to explicit manual actions.

Some complex messages and caption/transcript combinations remain unsupported. Translation availability depends on Telegram and system capabilities.

### Keep chats after removal

- Added an option to keep supported chats in the normal chat list after removal from a group.
- Retained already-loaded messages and available local chat information.
- Replaced the message composer with a removal notice.
- Added local read-state updates for retained messages.
- Kept selection, copying and forwarding of accessible content available.
- Kept sending, reactions and voting into inaccessible chats disabled.
- Added cleanup when the chat is explicitly deleted.
- Restored normal behavior after rejoining.

Enable this option before removal. It cannot recover messages or media that were never available locally, and it does not restore access to the group.

### Bot accounts

- Improved dialog visibility after incoming messages.
- Reworked loading and display of locally available history.
- Fixed cases where a dialog appeared but its messages or composer remained unavailable.
- Improved text, media, album and forwarding request handling.
- Prevented long history requests from blocking live-update processing.
- Fixed a saved-state issue that could cause repeated launch crashes in intermediate builds.
- Removed inapplicable Ghost Mode and Calls controls.
- Fixed bot labels and account-header formatting.

Telegram controls how much past history is available. These changes do not guarantee complete history or remove the risks described above.

### Interface

- Expanded transparent styling across nested settings.
- Improved background consistency during navigation and after returning to the app.
- Reused the original animated-avatar player for nested backgrounds.
- Fixed profile-editing cards, rounded corners and field backgrounds.
- Improved text and placeholder contrast.
- Refined device, web-session and connected-bot detail screens.
- Fixed backgrounds in wallet and gift screens.
- Prevented the profile’s gift grid from showing through an open gift’s information area.
- Improved opaque backgrounds when Reduce Transparency is enabled.

### Profile information

- Added mutual-contact information for eligible users.
- Added an approximate registration-time estimate where supported.
- Kept valid registration information from Telegram as the preferred source.
- Added region labels for known avatar-storage DCs.
- Added native long-press copying for ID, DC and registration information.

Registration estimates are approximate. The displayed DC does not identify a user’s country of residence.

### Stars and Gram

- Fixed the local Stars override affecting Gram balance displays.
- Added a separate local Gram display setting.
- Added decimal values, explicit zero, autosave and separate values for each account.
- Updated supported wallet, balance and gift-store screens to show the selected local value.
- Improved Stars-editor autosave and invalid-input handling.

These settings change display only. Actual balances, purchases, transfers, fees and withdrawals are unchanged.

### Protected content

- Extended the existing screenshot and screen-recording settings to supported protected profiles and video avatars.
- Improved video handling when capture settings change.

### Performance

- Reduced duplicate text processing during typing.
- Reduced repeated settings checks while displaying message history.
- Cancelled archive checks that were no longer needed after leaving a chat.
- Removed unnecessary preference writes when opening settings.
- Combined visual updates and delayed full refreshes for hidden screens.
- Reduced unnecessary background creation and subscriptions.
- Made local archive range queries avoid scanning and sorting the entire chat’s records.

These changes address specific sources of extra work. They do not mean every performance issue has been resolved.

### Localization

- Improved Russian and English labels, explanations and errors.
- Improved support for regional Russian language packs.
- Made Time Machine dates follow the Telegram interface language.

### Download and feedback

Download the IPA from **Assets** below and install it using your preferred signing method.

[Website](https://jerkgram.app) · [iOS channel](https://t.me/JerkgramiOS) · [Community](https://t.me/JerkgramCommunity)

---

## 🇷🇺 Jerkgram 1.2.0

Jerkgram переходит на Telegram 13.2. В обновлении появились локальное оформление профиля, единый раздел локальных Premium-возможностей и сохранение чатов после исключения из групп.

Также переработан перевод, улучшена история бот-аккаунтов и расширено прозрачное оформление настроек.

Ниже перечислены изменения относительно Jerkgram 1.1.0.

### ⚠️ Важно: бот-аккаунты

Вход в бот-аккаунт и его использование остаются экспериментальными и могут работать нестабильно. Чтение или отправка сообщений могут привести к удалению аккаунта бота.

Не используйте эту функцию с важными ботами. Для изучения проблемы нужны дальнейшее наблюдение и обратная связь.

О проблемах сообщайте в [Jerkgram Community](https://t.me/JerkgramCommunity). Укажите номер сборки, свои действия и результат. Не публикуйте токены ботов и другие данные доступа.

### Telegram 13.2

- Кодовая база Telegram обновлена с 13.0 до 13.2.
- Существующие возможности Jerkgram адаптированы к новой версии.
- Исправлены проблемы совместимости в настройках, профилях и истории сообщений.

### Локальные Premium-возможности

- Добавлен единый раздел для управления локальными Premium-возможностями.
- Добавлен общий переключатель. При его выключении индивидуальные настройки сохраняются.
- Добавлена разблокировка Premium-иконок через стандартный экран выбора Telegram.
- Добавлен буст загрузки с выключенным, средним и максимальным режимами.
- Добавлено скрытие поддерживаемых спонсируемых сообщений и рекламных результатов поиска.

Эти возможности не меняют настоящий статус Telegram Premium.

Буст меняет порядок загрузки подходящих файлов. Скорость по-прежнему зависит от соединения и серверов Telegram; серверные ограничения сохраняются.

Скрытие рекламы не удаляет обычные рекламные публикации, все рекомендации или каждое предложение подписки.

### Локальное оформление профиля

- Добавлен локальный эмодзи-статус с выбором срока действия.
- Добавлены локальные цвета имени, профиля и ответов, а также фоновые эмодзи.
- Настройки встроены в стандартные средства оформления профиля Telegram.
- Доработано поведение при смене аккаунтов и истечении срока статуса.
- Устаревшее окно выбора больше не должно применять изменения после смены соответствующих настроек.

Оформление видно только на вашем устройстве. Оно не меняет отображение профиля у других пользователей.

Для бот-аккаунтов функция недоступна. Локальное оформление не включено в существующие резервные копии.

### Перевод

- Переработан улучшенный перевод и добавлен отдельный переключатель для аккаунта.
- Для настоящего Premium сохранён стандартный перевод Telegram.
- Для поддерживаемых облачных сообщений добавлен текстовый перевод Telegram с резервным системным переводом.
- Секретное содержимое использует отдельный локальный путь.
- Улучшена поддержка текста, подписей, ответов, опросов и готовых расшифровок аудио.
- Доработаны форматирование и ссылки в поддерживаемых результатах.
- Устаревший перевод не должен заменять отредактированное сообщение или появляться после смены языка и аккаунта.
- Улучшены отмена запросов, обработка ошибок и повторные попытки.
- При ошибке оригинал не сохраняется как успешный перевод.
- Запрос скачивания языковых моделей ограничен явными ручными действиями.

Некоторые сложные сообщения и сочетания подписи с расшифровкой пока не поддерживаются. Доступность перевода зависит от Telegram и возможностей системы.

### Сохранение чатов после исключения

- Добавлена возможность оставлять поддерживаемые чаты в обычном списке после исключения из группы.
- Сохраняются уже загруженные сообщения и доступные локальные сведения о чате.
- Вместо поля ввода показывается уведомление об исключении.
- Просмотр обновляет локальное состояние прочтения.
- Остаются доступны выделение, копирование и пересылка доступного содержимого.
- Отправка, реакции и голосование в недоступном чате остаются заблокированы.
- Явное удаление чата очищает локальное сохранение.
- После повторного вступления возвращается обычное поведение.

Настройку нужно включить до исключения. Она не возвращает доступ к группе и не восстанавливает сообщения или медиа, которых не было на устройстве.

### Бот-аккаунты

- Улучшена видимость диалогов после получения сообщений.
- Переработаны загрузка и отображение доступной локальной истории.
- Исправлены случаи, когда диалог был виден, но сообщения или поле ввода оставались недоступны.
- Доработаны отправка текста, медиа, альбомов и пересылка.
- Длительная загрузка истории больше не должна блокировать обработку новых обновлений.
- Исправлена ошибка сохранённого состояния, которая могла вызывать повторные сбои запуска в промежуточных сборках.
- Убраны неприменимые для ботов элементы режима призрака и звонков.
- Исправлены подписи ботов и оформление заголовка аккаунта.

Объём доступной прошлой истории определяет Telegram. Эти изменения не гарантируют полную историю и не отменяют предупреждение о рисках выше.

### Интерфейс

- Расширено прозрачное оформление вложенных настроек.
- Улучшена согласованность фонов при переходах и возвращении в приложение.
- Для вложенных фонов используется исходный проигрыватель анимированного аватара.
- Исправлены карточки редактирования профиля, скругления и фоны полей.
- Улучшен контраст текста и подсказок.
- Доработаны экраны устройств, веб-сеансов и подключённых ботов.
- Исправлены фоны кошелька и экранов подарков.
- Устранено просвечивание сетки подарков через область сведений открытого подарка.
- Улучшены непрозрачные фоны при включённом уменьшении прозрачности.

### Сведения профиля

- Добавлено отображение взаимного контакта для подходящих пользователей.
- Добавлена приблизительная оценка времени регистрации там, где она поддерживается.
- Достоверные сведения от Telegram имеют приоритет.
- Добавлены подписи регионов известных DC хранения аватара.
- ID, DC и сведения о регистрации можно копировать через стандартное меню по удержанию.

Оценка регистрации приблизительная. Отображаемый DC не определяет страну проживания пользователя.

### Звёзды и грамы

- Исправлено влияние локального количества звёзд на отображение баланса грамов.
- Добавлена отдельная настройка локального отображения грамов.
- Поддерживаются дробные значения, ноль, автоматическое сохранение и отдельные значения для аккаунтов.
- Выбранное локальное значение отображается в поддерживаемых экранах кошелька, баланса и магазина подарков.
- Доработаны автоматическое сохранение и обработка ошибочного ввода в редакторе звёзд.

Настройки меняют только отображение. Настоящий баланс, покупки, переводы, комиссии и вывод остаются без изменений.

### Защищённый контент

- Расширено применение существующих настроек скриншотов и записи экрана к поддерживаемым защищённым профилям и видеоаватарам.
- Доработана обработка видео при изменении настроек захвата.

### Производительность

- Уменьшена повторная обработка текста при вводе.
- Сокращены повторные проверки настроек при отображении истории.
- Проверки архива отменяются, когда после ухода из чата они больше не нужны.
- Убраны лишние записи настроек при открытии разделов.
- Объединены визуальные обновления; скрытые экраны откладывают полное обновление до появления.
- Сокращено количество лишних фоновых объектов и подписок.
- Запросы к локальному архиву больше не требуют полного просмотра и сортировки всех записей чата.

Эти изменения устраняют конкретную лишнюю работу. Они не означают полного решения всех проблем производительности.

### Локализация

- Уточнены русские и английские подписи, объяснения и ошибки.
- Улучшена поддержка региональных русских языковых пакетов.
- Даты в «Машине времени» следуют языку интерфейса Telegram.

### Загрузка и обратная связь

Скачайте IPA из раздела **Assets** ниже и установите приложение удобным способом подписи.

[Сайт](https://jerkgram.app) · [Канал iOS](https://t.me/JerkgramiOS) · [Сообщество](https://t.me/JerkgramCommunity)