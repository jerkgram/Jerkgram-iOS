import Foundation

// TelegramCore has no presentation-layer dependency. Keep semantic labels here;
// resolve them once at send time using the account's selected app language.
enum JerkgramDeletedReplyLabel {
    case poll, todo, contact, location, dice, album, photo, sticker, voice
    case videoMessage, gif, video, audio, file, attachment, invoice, deletedMessage
    case tasksCompleted, tasksIncomplete, tasksAdded, pollOptionAdded, pollOptionDeleted, task
    case freshPollSnapshot, freshTodoSnapshot, pollOpen, pollClosed, votes, selected

    func text(languageCode: String) -> String {
        let russian = languageCode.lowercased().split(whereSeparator: { $0 == "-" || $0 == "_" }).first == "ru"
        switch self {
        case .tasksCompleted: return russian ? "Завершены задачи" : "Tasks completed"
        case .tasksIncomplete: return russian ? "Задачи отмечены незавершёнными" : "Tasks marked incomplete"
        case .tasksAdded: return russian ? "Добавлены задачи" : "Tasks added"
        case .pollOptionAdded: return russian ? "Добавлен вариант опроса" : "Poll option added"
        case .pollOptionDeleted: return russian ? "Удалён вариант опроса" : "Poll option deleted"
        case .task: return russian ? "Задача" : "Task"
        case .freshPollSnapshot: return russian ? "Снимок исходного опроса (вложен новый опрос)" : "Original poll snapshot (new poll attached)"
        case .freshTodoSnapshot: return russian ? "Снимок исходных задач (вложен новый список)" : "Original task snapshot (new list attached)"
        case .pollOpen: return russian ? "Открыт" : "Open"
        case .pollClosed: return russian ? "Закрыт" : "Closed"
        case .votes: return russian ? "Голоса" : "Votes"
        case .selected: return russian ? "Выбран" : "Selected"
        case .poll: return russian ? "Опрос" : "Poll"
        case .todo: return russian ? "Список задач" : "Task List"
        case .contact: return russian ? "👤 Контакт" : "👤 Contact"
        case .location: return russian ? "📍 Местоположение" : "📍 Location"
        case .dice: return russian ? "Результат" : "Result"
        case .album: return russian ? "Альбом" : "Album"
        case .photo: return russian ? "📷 Фото" : "📷 Photo"
        case .sticker: return russian ? "Стикер" : "Sticker"
        case .voice: return russian ? "🎙 Голосовое сообщение" : "🎙 Voice Message"
        case .videoMessage: return russian ? "🎥 Видеосообщение" : "🎥 Video Message"
        case .gif: return "GIF"
        case .video: return russian ? "🎬 Видео" : "🎬 Video"
        case .audio: return russian ? "🎵 Аудио" : "🎵 Audio"
        case .file: return russian ? "📎 Файл" : "📎 File"
        case .attachment: return russian ? "Вложение" : "Attachment"
        case .invoice: return russian ? "Счёт" : "Invoice"
        case .deletedMessage: return russian ? "Удалённое сообщение" : "Deleted Message"
        }
    }
}

struct JerkgramDeletedReplyText {
    private(set) var text = ""
    private var utf16Length = 0

    static func fittedQuote(_ quote: String, reply: String, limit: Int, languageCode: String) -> (text: String, retainedLength: Int) {
        let original = quote as NSString
        let separatorLength = reply.isEmpty ? 0 : 2
        let available = max(0, limit - (reply as NSString).length - separatorLength)
        guard original.length > available else { return (quote, original.length) }
        // If the user's text occupies the whole limit, even a notice cannot fit.
        // Preserve their text exactly; never add messages or trim their input.
        guard available > 0 else { return ("", 0) }
        let russian = languageCode.lowercased().split(whereSeparator: { $0 == "-" || $0 == "_" }).first == "ru"
        let fullMarker = russian ? "\n[Контекст сокращён]" : "\n[Context shortened]"
        let marker = (fullMarker as NSString).length <= available ? fullMarker : "…"
        var retained = min(original.length, available - (marker as NSString).length)
        if retained > 0 && retained < original.length {
            let sequence = original.rangeOfComposedCharacterSequence(at: retained - 1)
            if NSMaxRange(sequence) > retained {
                retained = sequence.location
            }
        }
        return (original.substring(to: retained) + marker, retained)
    }

    // Return the UTF-16 start of the original chunk, after a generated prefix.
    // Telegram entity ranges use UTF-16, not Swift Character counts.
    mutating func append(_ value: String, prefix: String = "") -> Int? {
        guard !value.isEmpty else { return nil }
        if !self.text.isEmpty {
            self.text += "\n"
            self.utf16Length += 1
        }
        let start = self.utf16Length + (prefix as NSString).length
        self.text += prefix + value
        self.utf16Length = start + (value as NSString).length
        return start
    }
}
