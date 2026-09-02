import Foundation
import PresentationStrings

// MARK: Jerkgram v1.2D BUILD115_LOCALIZATION_FOUNDATION1
//
// Jerkgram user-facing text follows Telegram's selected interface language,
// never the device locale. English is the canonical source and universal
// fallback. Persisted Jerkgram data stores semantic values, not translations.
public enum JerkgramStringKey: String, CaseIterable {
    case settingsTitle
    case basicFunctions
    case ghostMode
    case messages
    case protectedContent
    case mediaAndStories
    case appearance
    case debugResearch
    case about

    case profileCard
    case showIds
    case showDcs
    case registrationDate
    case localStarsBalance
    case starsBalance
    case currentVisualBalance

    case readGhost
    case typing
    case recording
    case uploading
    case choosingSticker
    case gameActivity
    case choosingEmoji
    case hideOnline
    case scheduledSend

    case deletedMessages
    case saveDeletedMessages
    case showDeletedMessages
    case editHistory
    case saveEditHistory
    case showEditHistory
    case savedDataHint
    case textSending
    case sendStyle
    case sendStyleHint
    case deletedReplies
    case portableReply
    case saveDeletedMedia
    case portableReplyHint

    case protectionEnabled
    case shareFromGallery
    case saveFromGallery
    case copyFromGallery
    case saveFromChat
    case copyFromChat
    case forwardFromChat
    case allowScreenshots
    case allowScreenRecording

    case oneTimeScreenshots
    case oneTimeScreenRecording
    case oneTimeSave
    case oneTimeMedia
    case storySave
    case appearancePlaceholder
    case profileBackground
    case profileBackgroundEffect
    case blurProfileAvatar
    case preferAvatarAsBackground
    case animatedBackground
    case colorTint
    case reducedBlur
    case animatedBackgroundHint
    case profileEffectDisabledHint
    case other
    case interface
    case messageSeconds
    case hideMyPhone
    case showRamUnderClock
    case hidePhoneHint
    case presenceHistoryEmpty
    case knownUsersNoData
    case recentEvents
    case eventsEmpty
    case diagnosticsBufferHint

    case information
    case telegramId
    case rawIdNamespace
    case profile
    case mainMenu

    case deletedMessage
    case editedMessage
    case sticker
    case photo
    case video
    case gif
    case audio
    case voiceMessage
    case videoMessage
    case document
    case attachment
    case album
    case poll
    case location
    case contact
    case dice
    case taskList
    case user

    case importSettings
    case exportSettings
    case importArchive
    case exportArchive

    case sendStyleNormal
    case sendStyleBold
    case sendStyleItalic
    case sendStyleMonospace
    case sendStyleStrikethrough
    case sendStyleUnderline
    case sendStyleSpoiler
    case sendStyleExamplePrefix
    case sendStyleExampleBody
    case community
    case communityHint
    case copyExtensionDiagnostics
    case communityLoading
    case communityUnavailable
    case communityNoPosts
    case profileHistoryTab
    case presenceHistoryTab
    case giftHistoryTab
    case personalChannelTab
    case profileReportLoading
}

public struct JerkgramStrings {
    public let languageCode: String

    public init(baseLanguageCode: String) {
        var value = baseLanguageCode.lowercased()

        let rawSuffix = "-raw"
        if value.hasSuffix(rawSuffix) {
            value = String(value.dropLast(rawSuffix.count))
        }

        if let separator = value.firstIndex(where: { character in
            character == "-" || character == "_"
        }) {
            value = String(value[..<separator])
        }

        self.languageCode = value
    }

    public func text(_ key: JerkgramStringKey) -> String {
        if self.languageCode == "ru",
           let value = Self.russian[key] {
            return value
        }

        return Self.english[key]!
    }

    public var settingsTitle: String { self.text(.settingsTitle) }
    public var basicFunctions: String { self.text(.basicFunctions) }
    public var ghostMode: String { self.text(.ghostMode) }
    public var messages: String { self.text(.messages) }
    public var protectedContent: String { self.text(.protectedContent) }
    public var mediaAndStories: String { self.text(.mediaAndStories) }
    public var appearance: String { self.text(.appearance) }
    public var debugResearch: String { self.text(.debugResearch) }
    public var about: String { self.text(.about) }

    public var profileCard: String { self.text(.profileCard) }
    public var showIds: String { self.text(.showIds) }
    public var showDcs: String { self.text(.showDcs) }
    public var registrationDate: String { self.text(.registrationDate) }
    public var localStarsBalance: String { self.text(.localStarsBalance) }
    public var starsBalance: String { self.text(.starsBalance) }
    public func currentVisualBalance(_ balance: String) -> String {
        return self.text(.currentVisualBalance).replacingOccurrences(
            of: "{balance}",
            with: balance
        )
    }

    public var readGhost: String { self.text(.readGhost) }
    public var typing: String { self.text(.typing) }
    public var recording: String { self.text(.recording) }
    public var uploading: String { self.text(.uploading) }
    public var choosingSticker: String { self.text(.choosingSticker) }
    public var gameActivity: String { self.text(.gameActivity) }
    public var choosingEmoji: String { self.text(.choosingEmoji) }
    public var hideOnline: String { self.text(.hideOnline) }
    public var scheduledSend: String { self.text(.scheduledSend) }

    public var deletedMessages: String { self.text(.deletedMessages) }
    public var saveDeletedMessages: String { self.text(.saveDeletedMessages) }
    public var showDeletedMessages: String { self.text(.showDeletedMessages) }
    public var editHistory: String { self.text(.editHistory) }
    public var saveEditHistory: String { self.text(.saveEditHistory) }
    public var showEditHistory: String { self.text(.showEditHistory) }
    public var savedDataHint: String { self.text(.savedDataHint) }
    public var textSending: String { self.text(.textSending) }
    public var sendStyle: String { self.text(.sendStyle) }
    public var sendStyleHint: String { self.text(.sendStyleHint) }
    public var deletedReplies: String { self.text(.deletedReplies) }
    public var portableReply: String { self.text(.portableReply) }
    public var saveDeletedMedia: String { self.text(.saveDeletedMedia) }
    public var portableReplyHint: String { self.text(.portableReplyHint) }

    public var protectionEnabled: String { self.text(.protectionEnabled) }
    public var shareFromGallery: String { self.text(.shareFromGallery) }
    public var saveFromGallery: String { self.text(.saveFromGallery) }
    public var copyFromGallery: String { self.text(.copyFromGallery) }
    public var saveFromChat: String { self.text(.saveFromChat) }
    public var copyFromChat: String { self.text(.copyFromChat) }
    public var forwardFromChat: String { self.text(.forwardFromChat) }
    public var allowScreenshots: String { self.text(.allowScreenshots) }
    public var allowScreenRecording: String { self.text(.allowScreenRecording) }

    public var oneTimeScreenshots: String { self.text(.oneTimeScreenshots) }
    public var oneTimeScreenRecording: String { self.text(.oneTimeScreenRecording) }
    public var oneTimeSave: String { self.text(.oneTimeSave) }
    public var oneTimeMedia: String { self.text(.oneTimeMedia) }
    public var storySave: String { self.text(.storySave) }
    public var appearancePlaceholder: String { self.text(.appearancePlaceholder) }
    public var profileBackground: String { self.text(.profileBackground) }
    public var profileBackgroundEffect: String { self.text(.profileBackgroundEffect) }
    public var blurProfileAvatar: String { self.text(.blurProfileAvatar) }
    public var preferAvatarAsBackground: String { self.text(.preferAvatarAsBackground) }
    public var animatedBackground: String { self.text(.animatedBackground) }
    public var colorTint: String { self.text(.colorTint) }
    public var reducedBlur: String { self.text(.reducedBlur) }
    public var animatedBackgroundHint: String { self.text(.animatedBackgroundHint) }
    public var profileEffectDisabledHint: String { self.text(.profileEffectDisabledHint) }
    public var other: String { self.text(.other) }
    public var interface: String { self.text(.interface) }
    public var messageSeconds: String { self.text(.messageSeconds) }
    public var hideMyPhone: String { self.text(.hideMyPhone) }
    public var showRamUnderClock: String { self.text(.showRamUnderClock) }
    public var hidePhoneHint: String { self.text(.hidePhoneHint) }
    public var presenceHistoryEmpty: String { self.text(.presenceHistoryEmpty) }
    public var knownUsersNoData: String { self.text(.knownUsersNoData) }
    public var recentEvents: String { self.text(.recentEvents) }
    public var eventsEmpty: String { self.text(.eventsEmpty) }
    public var diagnosticsBufferHint: String { self.text(.diagnosticsBufferHint) }

    public var information: String { self.text(.information) }
    public var telegramId: String { self.text(.telegramId) }
    public var rawIdNamespace: String { self.text(.rawIdNamespace) }
    public var profile: String { self.text(.profile) }
    public var mainMenu: String { self.text(.mainMenu) }

    public var deletedMessage: String { self.text(.deletedMessage) }
    public var editedMessage: String { self.text(.editedMessage) }
    public var sticker: String { self.text(.sticker) }
    public var photo: String { self.text(.photo) }
    public var video: String { self.text(.video) }
    public var gif: String { self.text(.gif) }
    public var audio: String { self.text(.audio) }
    public var voiceMessage: String { self.text(.voiceMessage) }
    public var videoMessage: String { self.text(.videoMessage) }
    public var document: String { self.text(.document) }
    public var attachment: String { self.text(.attachment) }
    public var album: String { self.text(.album) }
    public var poll: String { self.text(.poll) }
    public var location: String { self.text(.location) }
    public var contact: String { self.text(.contact) }
    public var dice: String { self.text(.dice) }
    public var taskList: String { self.text(.taskList) }
    public var user: String { self.text(.user) }

    public var importSettings: String { self.text(.importSettings) }
    public var exportSettings: String { self.text(.exportSettings) }
    public var importArchive: String { self.text(.importArchive) }
    public var exportArchive: String { self.text(.exportArchive) }

    public var sendStyleNormal: String { self.text(.sendStyleNormal) }
    public var sendStyleBold: String { self.text(.sendStyleBold) }
    public var sendStyleItalic: String { self.text(.sendStyleItalic) }
    public var sendStyleMonospace: String { self.text(.sendStyleMonospace) }
    public var sendStyleStrikethrough: String { self.text(.sendStyleStrikethrough) }
    public var sendStyleUnderline: String { self.text(.sendStyleUnderline) }
    public var sendStyleSpoiler: String { self.text(.sendStyleSpoiler) }
    public var sendStyleExamplePrefix: String { self.text(.sendStyleExamplePrefix) }
    public var sendStyleExampleBody: String { self.text(.sendStyleExampleBody) }
    public var community: String { self.text(.community) }
    public var communityHint: String { self.text(.communityHint) }
    public var copyExtensionDiagnostics: String { self.text(.copyExtensionDiagnostics) }
    public var communityLoading: String { self.text(.communityLoading) }
    public var communityUnavailable: String { self.text(.communityUnavailable) }
    public var communityNoPosts: String { self.text(.communityNoPosts) }
    public var profileHistoryTab: String { self.text(.profileHistoryTab) }
    public var presenceHistoryTab: String { self.text(.presenceHistoryTab) }
    public var giftHistoryTab: String { self.text(.giftHistoryTab) }
    public var personalChannelTab: String { self.text(.personalChannelTab) }
    public var profileReportLoading: String { self.text(.profileReportLoading) }

    // MARK: Jerkgram v1.2F BUILD117_PROFILE_REPORT_LOCALIZATION1
    public func localizedProfileReport(_ raw: String) -> String {
        guard self.languageCode != "ru" else {
            return raw
        }

        let exact: [String: String] = [
            "История изменений профиля": "Profile change history",
            "Изменений после первого наблюдения пока нет.": "No changes since first observation.",
            "История личного канала": "Personal channel history",
            "История подарков пока пуста.": "Gift history is empty.",
            "История подарков": "Gift history",
            "История присутствия пока пуста.": "Presence history is empty.",
            "История профиля пока пуста.": "Profile history is empty.",
            "Личный канал": "Personal channel",
            "Личный канал не найден.": "Personal channel was not found.",
            "онлайн": "online",
            "был недавно": "last seen recently",
            "был на этой неделе": "last seen within a week",
            "был в этом месяце": "last seen within a month",
            "скрытый статус": "hidden status",
            "видимый": "visible",
            "исчез из публичного профиля": "removed from public profile",
            "скрытый владельцем": "hidden by owner",
            "анонимно": "anonymous",
            "Мишка": "Teddy Bear"
        ]
        let prefixes: [(String, String)] = [
            ("История присутствия:", "Presence history:"),
            ("Зафиксировано изменений:", "Recorded changes:"),
            ("Первое наблюдение:", "First observed:"),
            ("Последнее наблюдение:", "Last observed:"),
            ("Последние сообщения:", "Latest messages:"),
            ("Имя:", "Name:"),
            ("Юзернейм:", "Username:"),
            ("Описание:", "Bio:"),
            ("Эмодзи-статус:", "Emoji status:"),
            ("Аватар: установлен", "Avatar: set"),
            ("Аватар: удалён", "Avatar: removed"),
            ("Аватар: изменён", "Avatar: changed"),
            ("Личный канал: откреплён", "Personal channel: detached"),
            ("Личный канал: прикреплён", "Personal channel: attached"),
            ("Канал ID:", "Channel ID:"),
            ("Название:", "Title:"),
            ("Ссылка:", "Link:"),
            ("Подписчики:", "Subscribers:"),
            ("Последний message ID:", "Latest message ID:"),
            ("Записей:", "Entries:"),
            ("ID подарка:", "Gift ID:"),
            ("Уникальный ID:", "Unique ID:"),
            ("Номер:", "Number:"),
            ("Отправитель:", "Sender:"),
            ("ID отправителя:", "Sender ID:"),
            ("Сообщение:", "Message:"),
            ("Статус: видимый", "Status: visible"),
            ("Подарок ", "Gift "),
            ("до ", "until ")
        ]

        func translateSegment(_ segment: String) -> String {
            if let value = exact[segment] {
                return value
            }
            for (source, target) in prefixes where segment.hasPrefix(source) {
                return target + String(segment.dropFirst(source.count))
            }
            return segment
        }

        return raw.components(separatedBy: "\n").map { line in
            let bullet = line.hasPrefix("• ") ? "• " : ""
            let content = bullet.isEmpty ? line : String(line.dropFirst(2))
            let translated = content.components(separatedBy: " · ")
                .map(translateSegment)
                .joined(separator: " · ")
            return bullet + translated
        }.joined(separator: "\n")
    }

    private static let english: [JerkgramStringKey: String] = [
        .settingsTitle: "Jerkgram",
        .basicFunctions: "Basic Functions",
        .ghostMode: "Ghost Mode",
        .messages: "Messages",
        .protectedContent: "Protected Content",
        .mediaAndStories: "Media & Stories",
        .appearance: "Appearance",
        .debugResearch: "Debug / Research",
        .about: "About",

        .profileCard: "Profile Card",
        .showIds: "Show IDs",
        .showDcs: "Show DCs",
        .registrationDate: "Registration Date",
        .localStarsBalance: "Local Stars Balance",
        .starsBalance: "Stars Balance",
        .currentVisualBalance: "Current visual balance: {balance} ⭐",

        .readGhost: "Don't Mark as Read",
        .typing: "Typing",
        .recording: "Recording",
        .uploading: "Uploading",
        .choosingSticker: "Choosing Sticker",
        .gameActivity: "Game Activity",
        .choosingEmoji: "Choosing Emoji",
        .hideOnline: "Online Status",
        .scheduledSend: "Scheduled Send",

        .deletedMessages: "Deleted Messages",
        .saveDeletedMessages: "Save Deleted",
        .showDeletedMessages: "Show Deleted Messages",
        .editHistory: "Edit History",
        .saveEditHistory: "Save Edit History",
        .showEditHistory: "Show Edit History",
        .savedDataHint: "Disabling these features does not remove already saved data.",
        .textSending: "Text Sending",
        .sendStyle: "Send Style",
        .sendStyleHint: "The style is applied after tapping the send button.",
        .deletedReplies: "Deleted Replies",
        .portableReply: "Portable Reply",
        .saveDeletedMedia: "Save Deleted Media",
        .portableReplyHint: "The reply is materialized only after Send. Media is kept only in Jerkgram's internal cache: up to 1 GB for 30 days; if bytes are unavailable, a text fallback is used.",

        .protectionEnabled: "Bypass Protection",
        .shareFromGallery: "Share from Gallery",
        .saveFromGallery: "Save from Gallery",
        .copyFromGallery: "Copy from Gallery",
        .saveFromChat: "Save from Chat",
        .copyFromChat: "Copy from Chat",
        .forwardFromChat: "Forward from Chat",
        .allowScreenshots: "Allow Screenshots",
        .allowScreenRecording: "Allow Screen Recording",

        .oneTimeScreenshots: "One-Time Media Screenshots",
        .oneTimeScreenRecording: "One-Time Media Screen Recording",
        .oneTimeSave: "Save One-Time Media",
        .oneTimeMedia: "One-Time Media",
        .storySave: "Save Stories",
        .appearancePlaceholder: "Jerkgram appearance settings will be added here.",
        .profileBackground: "Profile Background",
        .profileBackgroundEffect: "Profile Background Effect",
        .blurProfileAvatar: "Blur Profile Avatar",
        .preferAvatarAsBackground: "Prefer Avatar as Background",
        .animatedBackground: "Animated Background",
        .colorTint: "Color Tint",
        .reducedBlur: "Reduced Blur",
        .animatedBackgroundHint: "The video avatar loops and uses Telegram's cache. In Low Power Mode or with Reduced Blur, a static frame is used.",
        .profileEffectDisabledHint: "When the main effect is disabled, Jerkgram creates no additional profile views, observers, or image/palette pipeline. New values apply the next time the profile opens.",
        .other: "Other",
        .interface: "Interface",
        .messageSeconds: "Message Seconds",
        .hideMyPhone: "Hide My Phone Number",
        .showRamUnderClock: "Show RAM Under Clock",
        .hidePhoneHint: "Your phone number is hidden only locally in Jerkgram. Profile editing and number changing remain available.",
        .presenceHistoryEmpty: "Presence history is empty",
        .knownUsersNoData: "Known users: no data",
        .recentEvents: "Recent Events",
        .eventsEmpty: "No events yet",
        .diagnosticsBufferHint: "The buffer is limited to 200 lines. Collection does not start when this page opens.",

        .information: "Information",
        .telegramId: "Telegram ID",
        .rawIdNamespace: "Raw ID / Namespace",
        .profile: "Profile",
        .mainMenu: "Main Menu",

        .deletedMessage: "Deleted Message",
        .editedMessage: "Edited Message",
        .sticker: "Sticker",
        .photo: "Photo",
        .video: "Video",
        .gif: "GIF",
        .audio: "Audio",
        .voiceMessage: "Voice Message",
        .videoMessage: "Video Message",
        .document: "Document",
        .attachment: "Attachment",
        .album: "Album",
        .poll: "Poll",
        .location: "Location",
        .contact: "Contact",
        .dice: "Dice",
        .taskList: "Task List",
        .user: "User",

        .importSettings: "Import Settings",
        .exportSettings: "Export Settings",
        .importArchive: "Import Jerkgram Archive",
        .exportArchive: "Export Jerkgram Archive",

        .sendStyleNormal: "Normal",
        .sendStyleBold: "Bold",
        .sendStyleItalic: "Italic",
        .sendStyleMonospace: "Monospace",
        .sendStyleStrikethrough: "Strikethrough",
        .sendStyleUnderline: "Underline",
        .sendStyleSpoiler: "Spoiler",
        .sendStyleExamplePrefix: "Example: ",
        .sendStyleExampleBody: "this is how your text will look",
        .community: "Jerkgram Community",
        .communityHint: "News, builds and updates",
        .copyExtensionDiagnostics: "Copy Extension Diagnostics",
        .communityLoading: "Loading channel…",
        .communityUnavailable: "Channel information is temporarily unavailable",
        .communityNoPosts: "No posts yet",
        .profileHistoryTab: "History",
        .presenceHistoryTab: "Presence",
        .giftHistoryTab: "Gift History",
        .personalChannelTab: "Channel",
        .profileReportLoading: "Loading…"
    ]

    private static let russian: [JerkgramStringKey: String] = [
        .settingsTitle: "Jerkgram",
        .basicFunctions: "Основные функции",
        .ghostMode: "Режим призрака",
        .messages: "Сообщения",
        .protectedContent: "Защищённый контент",
        .mediaAndStories: "Медиа и истории",
        .appearance: "Оформление",
        .debugResearch: "Отладка / Исследования",
        .about: "О Jerkgram",

        .profileCard: "Карточка профиля",
        .showIds: "Показывать ID",
        .showDcs: "Показывать DC",
        .registrationDate: "Дата регистрации",
        .localStarsBalance: "Локальный баланс Stars",
        .starsBalance: "Баланс Stars",
        .currentVisualBalance: "Текущий визуальный баланс: {balance} ⭐",

        .readGhost: "Не отмечать прочитанным",
        .typing: "Набор текста",
        .recording: "Запись",
        .uploading: "Загрузка",
        .choosingSticker: "Выбор стикера",
        .gameActivity: "Игровая активность",
        .choosingEmoji: "Выбор эмодзи",
        .hideOnline: "Онлайн-статус",
        .scheduledSend: "Отложенная отправка",

        .deletedMessages: "Удалённые сообщения",
        .saveDeletedMessages: "Сохранять удалённые",
        .showDeletedMessages: "Показывать удалённые сообщения",
        .editHistory: "История изменений",
        .saveEditHistory: "Сохранять историю изменений",
        .showEditHistory: "Показывать историю изменений",
        .savedDataHint: "Выключение функций не удаляет уже сохранённые данные.",
        .textSending: "Отправка текста",
        .sendStyle: "Стиль отправки",
        .sendStyleHint: "Стиль применяется после нажатия кнопки отправки.",
        .deletedReplies: "Удалённые ответы",
        .portableReply: "Переносимый ответ",
        .saveDeletedMedia: "Сохранять удалённые медиа",
        .portableReplyHint: "Ответ материализуется только после Send. Медиа хранится только во внутреннем кэше Jerkgram: до 1 ГБ, 30 дней; если bytes недоступны, используется текстовый fallback.",

        .protectionEnabled: "Включить обход защиты",
        .shareFromGallery: "Поделиться из галереи",
        .saveFromGallery: "Сохранить из галереи",
        .copyFromGallery: "Копировать из галереи",
        .saveFromChat: "Сохранить из чата",
        .copyFromChat: "Копировать из чата",
        .forwardFromChat: "Переслать из чата",
        .allowScreenshots: "Разрешить скриншоты",
        .allowScreenRecording: "Разрешить запись экрана",

        .oneTimeScreenshots: "Скриншоты одноразовых медиа",
        .oneTimeScreenRecording: "Запись одноразовых медиа",
        .oneTimeSave: "Сохранение одноразовых медиа",
        .oneTimeMedia: "Одноразовые медиа",
        .storySave: "Сохранение историй",
        .appearancePlaceholder: "Настройки оформления Jerkgram будут добавляться в этот раздел.",
        .profileBackground: "Фон профиля",
        .profileBackgroundEffect: "Эффект фона профиля",
        .blurProfileAvatar: "Размывать аватар в профиле",
        .preferAvatarAsBackground: "Предпочитать аватар как фон",
        .animatedBackground: "Анимированный фон",
        .colorTint: "Цветовой оттенок",
        .reducedBlur: "Облегчённое размытие",
        .animatedBackgroundHint: "Видеоаватар зацикливается и использует кэш Telegram. В режиме энергосбережения или облегчённого размытия используется статический кадр.",
        .profileEffectDisabledHint: "Когда главный эффект выключен, Jerkgram не создаёт дополнительные profile views, observers или image/palette pipeline. Новые значения применяются при следующем открытии профиля.",
        .other: "Прочее",
        .interface: "Интерфейс",
        .messageSeconds: "Секунды в сообщениях",
        .hideMyPhone: "Скрывать мой номер",
        .showRamUnderClock: "Показывать RAM под часами",
        .hidePhoneHint: "Номер скрывается только локально в интерфейсе Jerkgram. Экран изменения профиля и смены номера остаётся доступен.",
        .presenceHistoryEmpty: "История присутствия пока пуста",
        .knownUsersNoData: "Известные пользователи: нет данных",
        .recentEvents: "Последние события",
        .eventsEmpty: "Событий пока нет",
        .diagnosticsBufferHint: "Буфер ограничен 200 строками. Сбор не запускается при открытии этой страницы.",

        .information: "Сведения",
        .telegramId: "Telegram ID",
        .rawIdNamespace: "Raw ID / Namespace",
        .profile: "Профиль",
        .mainMenu: "Главное меню",

        .deletedMessage: "Удалённое сообщение",
        .editedMessage: "Изменённое сообщение",
        .sticker: "Стикер",
        .photo: "Фото",
        .video: "Видео",
        .gif: "GIF",
        .audio: "Аудио",
        .voiceMessage: "Голосовое сообщение",
        .videoMessage: "Видеосообщение",
        .document: "Документ",
        .attachment: "Вложение",
        .album: "Альбом",
        .poll: "Опрос",
        .location: "Геолокация",
        .contact: "Контакт",
        .dice: "Бросок кубика",
        .taskList: "Список задач",
        .user: "Пользователь",

        .importSettings: "Импорт настроек",
        .exportSettings: "Экспорт настроек",
        .importArchive: "Импорт архива Jerkgram",
        .exportArchive: "Экспорт архива Jerkgram",

        .sendStyleNormal: "Обычный",
        .sendStyleBold: "Жирный",
        .sendStyleItalic: "Курсив",
        .sendStyleMonospace: "Моноширинный",
        .sendStyleStrikethrough: "Зачёркнутый",
        .sendStyleUnderline: "Подчёркнутый",
        .sendStyleSpoiler: "Спойлер",
        .sendStyleExamplePrefix: "Пример: ",
        .sendStyleExampleBody: "так будет выглядеть ваш текст",
        .community: "Сообщество Jerkgram",
        .communityHint: "Новости, сборки и обновления",
        .copyExtensionDiagnostics: "Копировать диагностику расширений",
        .communityLoading: "Загрузка канала…",
        .communityUnavailable: "Информация о канале временно недоступна",
        .communityNoPosts: "Публикаций пока нет",
        .profileHistoryTab: "История",
        .presenceHistoryTab: "Присутствие",
        .giftHistoryTab: "Подарки · история",
        .personalChannelTab: "Канал",
        .profileReportLoading: "Загрузка…"
    ]
}

public extension PresentationStrings {
    var jerkgram: JerkgramStrings {
        return JerkgramStrings(
            baseLanguageCode: self.baseLanguageCode
        )
    }
}


// MARK: Jerkgram v1.2G BUILD118_DATA_STRINGS1
public extension JerkgramStrings {
    var dataAndBackup: String { self.languageCode == "ru" ? "Данные и резервная копия" : "Data and Backup" }
    var retentionRules: String { self.languageCode == "ru" ? "Правила хранения" : "Retention Rules" }
    var historyDuration: String { self.languageCode == "ru" ? "Хранить историю" : "Keep History" }
    var recoveredMediaLimit: String { self.languageCode == "ru" ? "Лимит восстановленных медиа" : "Recovered Media Limit" }
    var archiveSecretChats: String { self.languageCode == "ru" ? "Архивировать Secret Chats" : "Archive Secret Chats" }
    var perChatRules: String { self.languageCode == "ru" ? "Правила по чатам" : "Per-Chat Rules" }
    var cleanupExpired: String { self.languageCode == "ru" ? "Очистить истёкшие данные" : "Clean Up Expired Data" }
    var backup: String { self.languageCode == "ru" ? "Резервная копия" : "Backup" }
    var disabled: String { self.languageCode == "ru" ? "Не сохранять" : "Do Not Save" }
    var forever: String { self.languageCode == "ru" ? "Бессрочно" : "Forever" }
    var unlimited: String { self.languageCode == "ru" ? "Без лимита" : "Unlimited" }
    var foreverUnlimitedWarning: String { self.languageCode == "ru" ? "Бессрочное хранение без лимита может занять всё свободное место." : "Forever with no size limit can use all available storage." }
    func days(_ value: Int) -> String { self.languageCode == "ru" ? "\(value) дней" : "\(value) days" }
    func backupAccountHint(_ accountPeerId: Int64) -> String { self.languageCode == "ru" ? "Архив относится только к аккаунту Telegram ID \(accountPeerId)." : "This archive belongs only to Telegram account ID \(accountPeerId)." }
    func importSettingsConfirmation(_ accountPeerId: Int64) -> String { self.languageCode == "ru" ? "Применить тумблеры и правила хранения для Telegram ID \(accountPeerId)?" : "Apply toggles and retention rules for Telegram ID \(accountPeerId)?" }
    var saveThisChat: String { self.languageCode == "ru" ? "Сохранять этот чат" : "Save This Chat" }
    func chatRuleHint(_ chatPeerId: Int64) -> String { self.languageCode == "ru" ? "Правило относится только к чату ID \(chatPeerId) текущего аккаунта." : "This rule applies only to chat ID \(chatPeerId) in the current account." }
}


// MARK: Jerkgram v1.2G BUILD118_TIME_MACHINE_STRINGS1
public extension JerkgramStrings {
    var timeMachine: String { self.languageCode == "ru" ? "Машина времени" : "Time Machine" }
    var timeMachineFilters: String { self.languageCode == "ru" ? "Фильтры" : "Filters" }
    var timeMachineDeleted: String { self.languageCode == "ru" ? "Удалённые" : "Deleted" }
    var timeMachineEdited: String { self.languageCode == "ru" ? "Отредактированные" : "Edited" }
    var timeMachineMedia: String { self.languageCode == "ru" ? "Восстановленные медиа" : "Recovered Media" }
    var timeMachineAuthor: String { self.languageCode == "ru" ? "Автор" : "Author" }
    var timeMachineAllAuthors: String { self.languageCode == "ru" ? "Все" : "All" }
    var timeMachineResults: String { self.languageCode == "ru" ? "Результаты" : "Results" }
    var timeMachineEmpty: String { self.languageCode == "ru" ? "Локальных изменений не найдено." : "No local changes found." }
    var timeMachineLoadMore: String { self.languageCode == "ru" ? "Загрузить ещё" : "Load More" }
}


// MARK: Jerkgram v1.2G BUILD118_SINCE_LAST_OPEN_STRINGS1
public extension JerkgramStrings {
    func changesSinceLastOpening(_ deleted: Int, _ edited: Int, _ media: Int) -> String {
        if self.languageCode == "ru" {
            return "С прошлого посещения: удалено \(deleted), изменено \(edited), медиа \(media)"
        } else {
            return "Since your last visit: \(deleted) deleted, \(edited) edited, \(media) media"
        }
    }
}


// MARK: Jerkgram v1.2H BUILD119_HYBRID_STRINGS1
public extension JerkgramStrings {
    var build119Summary: String {
        self.languageCode == "ru"
            ? "Build 119 · Official Telegram 12.9.2"
            : "Build 119 · Official Telegram 12.9.2"
    }
    var features: String {
        self.languageCode == "ru" ? "Функции" : "Features"
    }
    var change: String {
        self.languageCode == "ru" ? "Изменить" : "Change"
    }
    func starsOverrideSummary(_ enabled: Bool, _ balance: String) -> String {
        if self.languageCode == "ru" {
            return enabled ? "Локально · \(balance) ⭐" : "Выключено · \(balance) ⭐"
        } else {
            return enabled ? "Local · \(balance) ⭐" : "Off · \(balance) ⭐"
        }
    }
    var starsEditorHint: String {
        self.languageCode == "ru"
            ? "Это только локальное отображение баланса. Реальный баланс Telegram не изменяется."
            : "This changes only the local displayed balance. Your real Telegram balance is not modified."
    }
    var aboutBuild119Summary: String {
        "Jerkgram\nOfficial Telegram 12.9.2\nBuild 119"
    }
    func build119DataSummary(_ duration: String, _ mediaLimit: String, _ accountPeerId: Int64) -> String {
        if self.languageCode == "ru" {
            return "\(duration) · \(mediaLimit) · ID \(accountPeerId)"
        } else {
            return "\(duration) · \(mediaLimit) · ID \(accountPeerId)"
        }
    }
    func build119TimeMachineSummary(_ loaded: Int, _ activeKinds: Int, _ authorScoped: Bool) -> String {
        if self.languageCode == "ru" {
            let author = authorScoped ? "автор выбран" : "все авторы"
            return "Загружено \(loaded) · фильтров \(activeKinds) · \(author)"
        } else {
            let author = authorScoped ? "author selected" : "all authors"
            return "\(loaded) loaded · \(activeKinds) filters · \(author)"
        }
    }
}


// MARK: Jerkgram v1.2M BUILD124_SETTINGS_REDESIGN_STRINGS1
public extension JerkgramStrings {
    private func build124StateWord(_ enabled: Bool) -> String {
        if self.languageCode == "ru" {
            return enabled ? "вкл." : "выкл."
        } else {
            return enabled ? "on" : "off"
        }
    }

    func build124HomeSummary(_ profile: Bool, _ glass: Bool, _ stars: Bool) -> String {
        if self.languageCode == "ru" {
            return "Профиль: \(build124StateWord(profile)) · Glass: \(build124StateWord(glass)) · Stars: \(build124StateWord(stars))"
        } else {
            return "Profile: \(build124StateWord(profile)) · Glass: \(build124StateWord(glass)) · Stars: \(build124StateWord(stars))"
        }
    }

    func build124GhostSummary(_ read: Bool, _ typing: Bool, _ presence: Bool, _ scheduled: Bool) -> String {
        let active = [read, typing, presence, scheduled].filter { $0 }.count
        if self.languageCode == "ru" {
            return "Активно базовых режимов: \(active) из 4"
        } else {
            return "Core privacy modes active: \(active) of 4"
        }
    }

    func build124MessagesSummary(_ deleted: Bool, _ edits: Bool, _ media: Bool) -> String {
        if self.languageCode == "ru" {
            return "Удалённые: \(build124StateWord(deleted)) · Правки: \(build124StateWord(edits)) · Медиа: \(build124StateWord(media))"
        } else {
            return "Deleted: \(build124StateWord(deleted)) · Edits: \(build124StateWord(edits)) · Media: \(build124StateWord(media))"
        }
    }

    func build124ProtectedSummary(_ enabled: Bool, _ oneTime: Bool) -> String {
        if self.languageCode == "ru" {
            return "Защита: \(build124StateWord(enabled)) · Одноразовые медиа: \(build124StateWord(oneTime))"
        } else {
            return "Protection: \(build124StateWord(enabled)) · One-time media: \(build124StateWord(oneTime))"
        }
    }

    func build124MediaSummary(_ oneTime: Bool, _ stories: Bool) -> String {
        if self.languageCode == "ru" {
            return "Одноразовые медиа: \(build124StateWord(oneTime)) · Истории: \(build124StateWord(stories))"
        } else {
            return "One-time media: \(build124StateWord(oneTime)) · Stories: \(build124StateWord(stories))"
        }
    }

    func build124AppearanceSummary(_ glass: Bool, _ ram: Bool, _ seconds: Bool) -> String {
        if self.languageCode == "ru" {
            return "Glass: \(build124StateWord(glass)) · RAM: \(build124StateWord(ram)) · Секунды: \(build124StateWord(seconds))"
        } else {
            return "Glass: \(build124StateWord(glass)) · RAM: \(build124StateWord(ram)) · Seconds: \(build124StateWord(seconds))"
        }
    }

    var build124DiagnosticsSummary: String {
        if self.languageCode == "ru" {
            return "Диагностика и исследовательские инструменты Jerkgram"
        } else {
            return "Jerkgram diagnostics and research tools"
        }
    }

    var build124AboutSummary: String {
        return "Jerkgram · Official Telegram 12.9.2 · Build 124 Canary"
    }

    func build124DataSummary(_ duration: String, _ mediaLimit: String, _ accountPeerId: Int64) -> String {
        if self.languageCode == "ru" {
            return "\(duration) · \(mediaLimit) · аккаунт \(accountPeerId)"
        } else {
            return "\(duration) · \(mediaLimit) · account \(accountPeerId)"
        }
    }

    func build124TimeMachineSummary(_ loaded: Int, _ activeKinds: Int, _ authorScoped: Bool) -> String {
        if self.languageCode == "ru" {
            let author = authorScoped ? "автор выбран" : "все авторы"
            return "Загружено \(loaded) · фильтров \(activeKinds) · \(author)"
        } else {
            let author = authorScoped ? "author selected" : "all authors"
            return "\(loaded) loaded · \(activeKinds) filters · \(author)"
        }
    }
}

// MARK: Jerkgram v1.2N BUILD125_AUTH_GHOST_LOCALIZATION1
// Login controls must follow Telegram's selected interface language before an
// account session exists. `strings` is supplied by the authorization flow and
// therefore tracks PresentationStrings.baseLanguageCode rather than iOS Locale.
public extension JerkgramStrings {
    private var authGhostIsRussian: Bool { self.languageCode == "ru" }

    func authGhostModeStatus(enabled: Bool) -> String {
        if self.authGhostIsRussian {
            return enabled ? "👻 Режим призрака: ВКЛ" : "👻 Режим призрака: ВЫКЛ"
        } else {
            return enabled ? "👻 Ghost Mode: ON" : "👻 Ghost Mode: OFF"
        }
    }

    var authGhostModeHint: String {
        return self.authGhostIsRussian
            ? "Включите до входа, чтобы оставаться невидимым с первой сессии."
            : "Enable before login to stay invisible from the first session."
    }
}

// MARK: Jerkgram v1.2N BUILD125_AUTH_BOT_LOGIN_STRINGS2
// This probe does not materialize the older Build124 bot-localization overlay,
// so the visible phone-entry control owns its small selected-language contract.
public extension JerkgramStrings {
    private var authBotIsRussian: Bool { self.languageCode == "ru" }

    var botLoginButton: String {
        return self.authBotIsRussian ? "Войти как бот" : "Log in as Bot"
    }

    var botLoginAccessibility: String {
        return self.authBotIsRussian ? "Войти как бот" : "Log in as Bot"
    }
}

// MARK: Jerkgram v1.2M BUILD124_BOT_LOCALIZATION1
// Bot-account UI follows Telegram's selected interface language through the
// same JerkgramStrings owner as the rest of Jerkgram. Persisted diagnostic
// status values remain semantic English tokens and are translated only here.
public extension JerkgramStrings {
    private var botIsRussian: Bool { self.languageCode == "ru" }

    var botLoginTitle: String { self.botIsRussian ? "Вход как бот" : "Bot Login" }
    var botTokenNotice: String { self.botIsRussian ? "Введите токен, выданный BotFather. Токен не сохраняется." : "Enter the token issued by BotFather. The token is not stored." }

    var botInvalidToken: String { self.botIsRussian ? "Токен бота недействителен." : "The bot token is invalid." }
    var botFloodWait: String { self.botIsRussian ? "Слишком много попыток. Попробуйте позже." : "Too many attempts. Try again later." }
    var botApiIdInvalid: String { self.botIsRussian ? "Telegram отклонил API ID клиента." : "Telegram rejected this client's API ID." }
    var botMethodInvalid: String { self.botIsRussian ? "Сервер не разрешил авторизацию бота." : "The server did not allow bot authorization." }
    var botSignUpRequired: String { self.botIsRussian ? "Сервер запросил регистрацию вместо входа." : "The server requested registration instead of login." }
    func botRpcRejected(_ code: String) -> String { self.botIsRussian ? "Сервер отклонил вход: \(code)" : "The server rejected login: \(code)" }
    var botGenericLoginError: String { self.botIsRussian ? "Не удалось войти в аккаунт бота." : "Couldn't log in to the bot account." }
    var botAlreadyAdded: String { self.botIsRussian ? "Этот бот уже добавлен в Jerkgram." : "This bot is already added to Jerkgram." }

    var botLogoutTitle: String { self.botIsRussian ? "Выйти из аккаунта бота?" : "Log out of the bot account?" }
    var botLogoutText: String { self.botIsRussian ? "Аккаунт будет удалён только из Jerkgram. Сам бот и его токен в BotFather не удаляются." : "The account will be removed only from Jerkgram. The bot itself and its BotFather token are not deleted." }
    var botLogoutAction: String { self.botIsRussian ? "Выйти" : "Log Out" }

    var botCapabilityTitle: String { self.botIsRussian ? "Возможности бот-аккаунта" : "Bot Account Capabilities" }
    var botCapabilityAction: String { self.botIsRussian ? "Проверить RPC бот-аккаунта" : "Check Bot Account RPC" }
    var botDifferenceAction: String { self.botIsRussian ? "Проверить updates.getDifference" : "Check updates.getDifference" }
    var botNoResults: String { self.botIsRussian ? "Результатов пока нет." : "No results yet." }

    func botDiagnosticReport(status: String, updated: String, report: String) -> String {
        let localizedStatus: String
        switch status {
        case "not tested": localizedStatus = self.botIsRussian ? "не проверено" : "not tested"
        case "running": localizedStatus = self.botIsRussian ? "выполняется" : "running"
        case "completed": localizedStatus = self.botIsRussian ? "завершено" : "completed"
        default: localizedStatus = status
        }
        let localizedUpdated = updated == "none" ? (self.botIsRussian ? "нет" : "none") : updated
        let statusLabel = self.botIsRussian ? "Статус" : "Status"
        let updatedLabel = self.botIsRussian ? "Обновлено" : "Updated"
        return "\(statusLabel): \(localizedStatus)\n\(updatedLabel): \(localizedUpdated)\n\n\(report)"
    }
}



// MARK: Jerkgram v1.2T BUILD130_RELEASE_STRINGS1
public extension JerkgramStrings {
    var version: String { self.languageCode == "ru" ? "ВЕРСИЯ" : "VERSION" }
    var privacy: String { self.languageCode == "ru" ? "КОНФИДЕНЦИАЛЬНОСТЬ" : "PRIVACY" }
    var jerkgramVersion: String { self.languageCode == "ru" ? "Версия Jerkgram" : "Jerkgram Version" }
    var build: String { self.languageCode == "ru" ? "Сборка" : "Build" }
    var telegramBase: String { self.languageCode == "ru" ? "База Telegram" : "Telegram Base" }
    var anonymousAnalytics: String { self.languageCode == "ru" ? "Анонимная аналитика" : "Anonymous Analytics" }
    var anonymousAnalyticsDescription: String {
        if self.languageCode == "ru" {
            return "Помогайте улучшать Jerkgram, отправляя анонимную статистику использования: версию Jerkgram, версию iOS и регион устройства. Аккаунты Telegram, сообщения, имена пользователей и номера телефонов никогда не собираются."
        } else {
            return "Help improve Jerkgram by sharing anonymous usage statistics such as Jerkgram version, iOS version and device region. Telegram accounts, messages, usernames and phone numbers are never collected."
        }
    }
}
