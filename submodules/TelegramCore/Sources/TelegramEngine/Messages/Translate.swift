import Foundation
import Postbox
import SwiftSignalKit
internal import TelegramApi
import MtProtoKit

// Account policy is hydrated by the canonical GhostBase settings owner on activation.
// Kept here because this source owner is already present in TelegramCore's build inputs.
public enum JerkgramTranslationSettings {
    public static let preferenceKey = "jerkgram.EnhancedTranslation"
    public static let policyVersion: Int32 = 2
    private static let masterObserver: NSObjectProtocol = NotificationCenter.default.addObserver(forName: JerkgramLocalPremiumPolicy.changed, object: nil, queue: nil) { _ in
        lock.lock()
        let accounts = Array(values.keys)
        for account in accounts {
            epoch &+= 1
            values[account] = (values[account]!.0, epoch)
            JerkgramTranslationAdmission.shared.cancel(accountPeerId: account)
        }
        lock.unlock()
        DispatchQueue.main.async {
            for account in accounts { NotificationCenter.default.post(name: Notification.Name("JerkgramTranslationPolicyChanged"), object: account) }
        }
    }
    private static let lock = NSLock()
    private static var values: [Int64: (Bool, UInt64)] = [:]
    private static var order: [Int64] = []
    private static var epoch: UInt64 = 1
    public static func scopedKey(accountPeerId: Int64) -> String { return "jerkgram.account.\(accountPeerId).setting.\(preferenceKey)" }
    public static func enabled(accountPeerId: Int64) -> Bool {
        _ = masterObserver
        lock.lock(); defer { lock.unlock() }
        return JerkgramLocalPremiumPolicy.effective(value(accountPeerId: accountPeerId).0)
    }
    public static func generation(accountPeerId: Int64) -> UInt64 {
        lock.lock(); defer { lock.unlock() }
        return value(accountPeerId: accountPeerId).1
    }
    // A bounded cache miss reads the canonical scoped value once. Rendering a
    // known account never performs settings I/O; eviction cannot turn OFF into ON.
    private static func value(accountPeerId: Int64) -> (Bool, UInt64) {
        if let current = values[accountPeerId] { return current }
        let enabled = UserDefaults.standard.object(forKey: scopedKey(accountPeerId: accountPeerId)) as? Bool ?? true
        epoch &+= 1
        values[accountPeerId] = (enabled, epoch)
        order.append(accountPeerId)
        trim()
        return (enabled, epoch)
    }
    private static func trim() {
        while order.count > 16 {
            let evicted = order.removeFirst()
            values.removeValue(forKey: evicted)
            JerkgramTranslationAdmission.shared.cancel(accountPeerId: evicted)
        }
    }
    public static func update(accountPeerId: Int64, enabled: Bool) {
        lock.lock()
        if value(accountPeerId: accountPeerId).0 == enabled { lock.unlock(); return }
        epoch &+= 1
        values[accountPeerId] = (enabled, epoch)
        order.removeAll(where: { $0 == accountPeerId }); order.append(accountPeerId)
        JerkgramTranslationAdmission.shared.cancel(accountPeerId: accountPeerId)
        trim()
        lock.unlock()
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: Notification.Name("JerkgramTranslationPolicyChanged"), object: accountPeerId)
        }
    }
}

private func jerkgramPolicyIsCurrent(account: Account, generation: UInt64) -> Bool {
    return JerkgramTranslationSettings.enabled(accountPeerId: account.peerId.toInt64()) && JerkgramTranslationSettings.generation(accountPeerId: account.peerId.toInt64()) == generation
}

private typealias JerkgramTranslatedTexts = [(String, [MessageTextEntity])]
// MessageTextEntity is Codable in the pinned Telegram owner. Encode the full
// entity graph so TextUrl/Pre/custom-emoji sticker-pack string payloads all count;
// a fixed per-entity estimate alone cannot bound retained source or cached output.
private func jerkgramTranslationPayloadBytes(_ texts: JerkgramTranslatedTexts) -> Int? {
    var bytes = 0
    for text in texts {
        guard let encodedEntities = try? JSONEncoder().encode(text.1) else { return nil }
        let (textBytes, textOverflow) = text.0.utf8.count.addingReportingOverflow(encodedEntities.count)
        let (entityOverhead, entityOverflow) = text.1.count.multipliedReportingOverflow(by: 64)
        let (itemBytes, itemOverflow) = textBytes.addingReportingOverflow(entityOverhead)
        let (total, totalOverflow) = bytes.addingReportingOverflow(itemBytes)
        guard !textOverflow, !entityOverflow, !itemOverflow, !totalOverflow else { return nil }
        bytes = total
    }
    return bytes
}

private func jerkgramValidTranslatedEntities(_ text: String, _ entities: [MessageTextEntity]) -> Bool {
    let utf16 = text as NSString
    let count = utf16.length
    func isBoundary(_ offset: Int) -> Bool {
        if offset == 0 || offset == count { return true }
        // Foundation range conversion can accept a UTF16-surrogate interior.
        // Scalar boundaries are allowed even inside a combining grapheme.
        return !((0xD800 ... 0xDBFF).contains(utf16.character(at: offset - 1)) && (0xDC00 ... 0xDFFF).contains(utf16.character(at: offset)))
    }
    return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && entities.allSatisfy {
        $0.range.lowerBound >= 0 && $0.range.upperBound <= count && $0.range.lowerBound < $0.range.upperBound && isBoundary($0.range.lowerBound) && isBoundary($0.range.upperBound)
    }
}

// Derive new ranges from translated output. Preserve hidden link destinations
// only when their original label survives exactly once; otherwise fail explicitly.
private func jerkgramLocalTranslatedEntities(source: (String, [MessageTextEntity]), translated: String) -> [MessageTextEntity]? {
    let nsText = translated as NSString
    let fullRange = NSRange(location: 0, length: nsText.length)
    var entities: [MessageTextEntity] = []
    if let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) {
        for match in detector.matches(in: translated, range: fullRange) {
            entities.append(MessageTextEntity(range: match.range.location ..< NSMaxRange(match.range), type: .Url))
        }
    }
    if let mentions = try? NSRegularExpression(pattern: "(?<![\\p{L}\\p{N}_])@[A-Za-z][A-Za-z0-9_]{4,31}\\b") {
        for match in mentions.matches(in: translated, range: fullRange) {
            let range = match.range.location ..< NSMaxRange(match.range)
            if !entities.contains(where: { $0.range.overlaps(range) }) { entities.append(MessageTextEntity(range: range, type: .Mention)) }
        }
    }
    for entity in source.1 {
        if case let .TextUrl(url) = entity.type {
            guard let originalRange = Range(NSRange(location: entity.range.lowerBound, length: entity.range.count), in: source.0) else { return nil }
            let label = String(source.0[originalRange])
            let match = nsText.range(of: label)
            guard match.location != NSNotFound, match.length > 0 else { return nil }
            let remainder = NSRange(location: NSMaxRange(match), length: nsText.length - NSMaxRange(match))
            guard nsText.range(of: label, range: remainder).location == NSNotFound else { return nil }
            let range = match.location ..< NSMaxRange(match)
            entities.removeAll(where: { $0.range.overlaps(range) })
            entities.append(MessageTextEntity(range: range, type: .TextUrl(url: url)))
        }
    }
    entities.sort { $0.range.lowerBound < $1.range.lowerBound }
    return jerkgramValidTranslatedEntities(translated, entities) ? entities : nil
}

// All enhanced cloud and fallback work shares this admission, including manual requests.
// State and physical request lifetime are owned by one serial queue.
private final class JerkgramTranslationAdmission {
    static let shared = JerkgramTranslationAdmission()
    private final class Job {
        let key: String; let count: Int; let bytes: Int
        let start: () -> Signal<JerkgramTranslatedTexts, TranslationError>
        var observers: [UUID: (JerkgramTranslatedTexts?, TranslationError?) -> Void] = [:]
        let transport = MetaDisposable()
        var running = false
        var timer: DispatchWorkItem?
        init(key: String, count: Int, bytes: Int, start: @escaping () -> Signal<JerkgramTranslatedTexts, TranslationError>) { self.key = key; self.count = count; self.bytes = bytes; self.start = start }
    }
    private let queue = DispatchQueue(label: "org.jerkgram.translation.admission")
    private var jobs: [String: Job] = [:]
    private var waiting: [String] = []
    private var active = 0
    private var items = 0
    private var bytes = 0
    private var cache: [String: (JerkgramTranslatedTexts, Int)] = [:]
    private var lru: [String] = []
    private var cacheBytes = 0
    func cancel(accountPeerId: Int64) {
        queue.async {
            let prefix = "\(accountPeerId):"
            let stale = self.jobs.values.filter { $0.key.hasPrefix(prefix) }
            for job in stale { self.finish(job, value: nil, error: .generic) }
            for key in self.lru.filter({ $0.hasPrefix(prefix) }) {
                if let old = self.cache.removeValue(forKey: key) { self.cacheBytes -= old.1 }
            }
            self.lru.removeAll(where: { $0.hasPrefix(prefix) })
        }
    }
    func request(key: String, count: Int, bytes: Int, start: @escaping () -> Signal<JerkgramTranslatedTexts, TranslationError>) -> Signal<JerkgramTranslatedTexts, TranslationError> {
        return Signal { [self] subscriber in
            let token = UUID()
            self.queue.async {
                if let cached = self.cache[key] {
                    self.lru.removeAll(where: { $0 == key }); self.lru.append(key)
                    subscriber.putNext(cached.0); subscriber.putCompletion(); return
                }
                let observer: (JerkgramTranslatedTexts?, TranslationError?) -> Void = { value, error in
                    if let error { subscriber.putError(error) } else if let value { subscriber.putNext(value); subscriber.putCompletion() }
                }
                if let job = self.jobs[key] {
                    guard job.observers.count < 64 else { subscriber.putError(.limitExceeded); return }
                    job.observers[token] = observer; return
                }
                guard count > 0, count <= 16, bytes <= 16 * 1024, self.items + count <= 64, self.bytes + bytes <= 128 * 1024 else { subscriber.putError(.limitExceeded); return }
                let job = Job(key: key, count: count, bytes: bytes, start: start)
                job.observers[token] = observer
                self.jobs[key] = job; self.waiting.append(key); self.items += count; self.bytes += bytes
                let timer = DispatchWorkItem { [weak self, weak job] in
                    guard let self, let job else { return }
                    self.finish(job, value: nil, error: .generic)
                }
                job.timer = timer; self.queue.asyncAfter(deadline: .now() + 30.0, execute: timer)
                self.pump()
            }
            return ActionDisposable {
                self.queue.async {
                    guard let job = self.jobs[key] else { return }
                    job.observers.removeValue(forKey: token)
                    if job.observers.isEmpty { self.finish(job, value: nil, error: nil) }
                }
            }
        }
    }
    private func pump() {
        while active < 2 && !waiting.isEmpty {
            let key = waiting.removeFirst()
            guard let job = jobs[key] else { continue }
            job.running = true; active += 1
            job.transport.set(job.start().start(next: { value in
                self.queue.async { self.finish(job, value: value, error: nil) }
            }, error: { error in
                self.queue.async { self.finish(job, value: nil, error: error) }
            }, completed: {
                self.queue.async { self.finish(job, value: nil, error: .generic) }
            }))
        }
    }
    private func finish(_ job: Job, value: JerkgramTranslatedTexts?, error: TranslationError?) {
        guard jobs[job.key] === job else { return }
        jobs.removeValue(forKey: job.key); waiting.removeAll(where: { $0 == job.key })
        job.timer?.cancel(); job.timer = nil
        job.transport.dispose()
        items -= job.count; bytes -= job.bytes
        if job.running { active -= 1 }
        if let value {
            if let size = jerkgramTranslationPayloadBytes(value), size <= 1024 * 1024 {
                cache[job.key] = (value, size); cacheBytes += size; lru.append(job.key)
                while lru.count > 256 || cacheBytes > 1024 * 1024 {
                    if let old = cache.removeValue(forKey: lru.removeFirst()) { cacheBytes -= old.1 }
                }
            }
        }
        for observer in job.observers.values { observer(value, error) }
        job.observers.removeAll(); pump()
    }
}

private func jerkgramEnhancedTexts(account: Account, texts: JerkgramTranslatedTexts, fromLang: String?, toLang: String, allowLocalDownloads: Bool, localOnly: Bool) -> Signal<JerkgramTranslatedTexts, TranslationError> {
    let generation = JerkgramTranslationSettings.generation(accountPeerId: account.peerId.toInt64())
    guard jerkgramPolicyIsCurrent(account: account, generation: generation) else { return .fail(.generic) }
    guard !texts.isEmpty, texts.count <= 16 else { return .fail(.textTooLong) }
    guard texts.allSatisfy({ jerkgramValidTranslatedEntities($0.0, $0.1) }) else { return .fail(.textIsEmpty) }
    guard let bytes = jerkgramTranslationPayloadBytes(texts), bytes <= 16 * 1024 else { return .fail(.textTooLong) }
    let encoder = PostboxEncoder()
    for (index, text) in texts.enumerated() { encoder.encodeString(text.0, forKey: "t\(index)"); encoder.encodeObjectArray(text.1, forKey: "e\(index)") }
    let digest = sha256Digest(encoder.makeData()).map { String(format: "%02x", $0) }.joined()
    let key = "\(account.peerId.toInt64()):\(generation):\(JerkgramTranslationSettings.policyVersion):\(toLang):\(fromLang ?? ""):\(localOnly):\(allowLocalDownloads):\(digest)"
    let local: () -> Signal<JerkgramTranslatedTexts, TranslationError> = {
        guard jerkgramPolicyIsCurrent(account: account, generation: generation) else { return .fail(.generic) }
        guard let service = engineExperimentalInternalTranslationService else { return .fail(.generic) }
        var mapped: [AnyHashable: String] = [:]
        for (index, text) in texts.enumerated() { mapped[AnyHashable(index)] = text.0 }
        // Existing explicit manual action owns model-download consent.
        // Automatic fallback detects this message's language rather than using
        // chat-majority prediction, and always passes allowDownloads: false.
        return service.translate(texts: mapped, fromLang: allowLocalDownloads ? (fromLang ?? "") : "", toLang: toLang, allowDownloads: allowLocalDownloads)
        |> castError(TranslationError.self)
        |> mapToSignal { result -> Signal<JerkgramTranslatedTexts, TranslationError> in
            guard let result, result.count == texts.count else { return .fail(.generic) }
            var values: JerkgramTranslatedTexts = []
            for index in texts.indices {
                guard let text = result[AnyHashable(index)], let entities = jerkgramLocalTranslatedEntities(source: texts[index], translated: text) else { return .fail(.generic) }
                values.append((text, entities))
            }
            return .single(values)
        }
    }
    return JerkgramTranslationAdmission.shared.request(key: key, count: texts.count, bytes: bytes, start: {
        guard jerkgramPolicyIsCurrent(account: account, generation: generation) else { return .fail(.generic) }
        if localOnly { return local() }
        return _internal_translateTexts(network: account.network, texts: texts, toLang: toLang)
        |> mapToSignal { results -> Signal<JerkgramTranslatedTexts, TranslationError> in
            guard results.count == texts.count, results.allSatisfy({ jerkgramValidTranslatedEntities($0.0, $0.1) }) else { return .fail(.generic) }
            return .single(results)
        }
        |> `catch` { error -> Signal<JerkgramTranslatedTexts, TranslationError> in
            switch error { case .generic, .tryAlternative: return local(); default: return .fail(error) }
        }
    })
    |> mapToSignal { results -> Signal<JerkgramTranslatedTexts, TranslationError> in
        guard jerkgramPolicyIsCurrent(account: account, generation: generation) else { return .fail(.generic) }
        return .single(results)
    }
}

func _internal_jerkgramEnhancedTranslate(account: Account, text: String, entities: [MessageTextEntity], fromLang: String?, toLang: String, allowLocalDownloads: Bool, localOnly: Bool) -> Signal<(String, [MessageTextEntity])?, TranslationError> {
    return jerkgramEnhancedTexts(account: account, texts: [(text, entities)], fromLang: fromLang, toLang: toLang, allowLocalDownloads: allowLocalDownloads, localOnly: localOnly)
    |> map { $0.first }
}

public enum ComposedRichMessage: Equatable {
    /// Structured content → a rich message (`RichTextMessageAttribute(instantPage:)`, sent with `text: ""`).
    case rich(instantPage: InstantPage)
    /// Entity-expressible content → a normal message (`text` + `TextEntitiesMessageAttribute`).
    case plain(text: String, entities: [MessageTextEntity])
    /// Nothing worth sending (empty / whitespace-only document).
    case empty
}

public enum TranslationError {
    case generic
    case invalidMessageId
    case textIsEmpty
    case textTooLong
    case invalidLanguage
    case limitExceeded
    case tryAlternative
}

public enum TranslationTone: String {
    case neutral
    case casual
    case formal
}

func _internal_translate(network: Network, text: String, toLang: String, entities: [MessageTextEntity] = [], tone: TranslationTone = .neutral, peer: Api.InputPeer? = nil, messageId: Int32? = nil) -> Signal<(String, [MessageTextEntity])?, TranslationError> {
    var flags: Int32 = 0

    if tone != .neutral {
        flags |= (1 << 2)
    }

    let apiText: [Api.TextWithEntities]?
    if peer != nil && messageId != nil {
        flags |= (1 << 0)
        apiText = nil
    } else {
        flags |= (1 << 1)
        apiText = [.textWithEntities(.init(text: text, entities: apiEntitiesFromMessageTextEntities(entities, associatedPeers: SimpleDictionary())))]
    }

    return network.request(Api.functions.messages.translateText(flags: flags, peer: peer, id: messageId.flatMap { [$0] }, text: apiText, toLang: toLang, tone: tone.rawValue))
    |> mapError { error -> TranslationError in
        if error.errorDescription.hasPrefix("FLOOD_WAIT") {
            return .limitExceeded
        } else if error.errorDescription == "MSG_ID_INVALID" {
            return .invalidMessageId
        } else if error.errorDescription == "INPUT_TEXT_EMPTY" {
            return .textIsEmpty
        } else if error.errorDescription == "INPUT_TEXT_TOO_LONG" {
            return .textTooLong
        } else if error.errorDescription == "TO_LANG_INVALID" {
            return .invalidLanguage
        } else if error.errorDescription == "TRANSLATIONS_DISABLED_ALT" {
            return .tryAlternative
        } else {
            return .generic
        }
    }
    |> mapToSignal { result -> Signal<(String, [MessageTextEntity])?, TranslationError> in
        switch result {
        case let .translateResult(translateResultData):
            let results = translateResultData.result
            if case let .textWithEntities(textWithEntitiesData) = results.first {
                let (text, entities) = (textWithEntitiesData.text, textWithEntitiesData.entities)
                return .single((text, messageTextEntitiesFromApiEntities(entities)))
            } else {
                return .single(nil)
            }
        }
    }
}

func _internal_composeMessageWithAI(account: Account, text: String, entities: [MessageTextEntity], proofread: Bool = false, translateToLang: String? = nil, changeStyle: TelegramComposeAIMessageMode.CloudStyle.Reference? = nil, emojify: Bool = false) -> Signal<(String, [MessageTextEntity]), TranslationError> {
    var flags: Int32 = 0
    if proofread {
        flags |= (1 << 0)
    }
    if translateToLang != nil {
        flags |= (1 << 1)
    }
    
    var changeTone: Api.InputAiComposeTone?
    if let changeStyle {
        flags |= (1 << 2)
        changeTone = changeStyle.apiInputStyle
    }
    if emojify {
        flags |= (1 << 3)
    }
    
    let apiText: Api.TextWithEntities = .textWithEntities(.init(text: text, entities: apiEntitiesFromMessageTextEntities(entities, associatedPeers: SimpleDictionary())))

    return account.network.request(Api.functions.messages.composeMessageWithAI(flags: flags, text: apiText, translateToLang: translateToLang, tone: changeTone))
    |> mapError { error -> TranslationError in
        if error.errorDescription.hasPrefix("FLOOD_WAIT") {
            return .limitExceeded
        } else if error.errorDescription == "INPUT_TEXT_EMPTY" {
            return .textIsEmpty
        } else if error.errorDescription == "INPUT_TEXT_TOO_LONG" {
            return .textTooLong
        } else if error.errorDescription.hasPrefix("AICOMPOSE_FLOOD_PREMIUM ") {
            return .limitExceeded
        } else {
            return .generic
        }
    }
    |> map { result -> (String, [MessageTextEntity]) in
        switch result {
        case let .composedMessageWithAI(data):
            switch data.resultText {
            case let .textWithEntities(textData):
                return (textData.text, messageTextEntitiesFromApiEntities(textData.entities))
            }
        }
    }
}

func _internal_composeRichMessageWithAI(account: Account, instantPage: InstantPage?, proofread: Bool = false, translateToLang: String? = nil, changeStyle: TelegramComposeAIMessageMode.CloudStyle.Reference? = nil, customPrompt: String? = nil, emojify: Bool = false) -> Signal<InstantPage, TranslationError> {
    var flags: Int32 = 0
    if proofread {
        flags |= (1 << 0)
    }
    if translateToLang != nil {
        flags |= (1 << 1)
    }

    var changeTone: Api.InputAiComposeTone?
    if let customPrompt {
        flags |= (1 << 2)
        changeTone = .inputAiComposeToneSingleUse(Api.InputAiComposeTone.Cons_inputAiComposeToneSingleUse(customPrompt: customPrompt))
    } else if let changeStyle {
        flags |= (1 << 2)
        changeTone = changeStyle.apiInputStyle
    }
    if emojify {
        flags |= (1 << 3)
    }

    var inputRichMessage: Api.InputRichMessage?
    if let instantPage {
        flags |= (1 << 4)
        // No `users`: this page is rewritten and handed back, not sent; the send that follows lists them.
        inputRichMessage = RichTextMessageAttribute(instantPage: instantPage, fullInstantPage: nil).apiInputRichMessage(users: [])
    }

    return account.network.request(Api.functions.messages.composeRichMessageWithAI(flags: flags, text: inputRichMessage, translateToLang: translateToLang, tone: changeTone))
    |> mapError { error -> TranslationError in
        if error.errorDescription.hasPrefix("FLOOD_WAIT") {
            return .limitExceeded
        } else if error.errorDescription == "INPUT_TEXT_EMPTY" {
            return .textIsEmpty
        } else if error.errorDescription == "INPUT_TEXT_TOO_LONG" {
            return .textTooLong
        } else if error.errorDescription.hasPrefix("AICOMPOSE_FLOOD_PREMIUM ") {
            return .limitExceeded
        } else {
            return .generic
        }
    }
    |> map { result -> InstantPage in
        switch result {
        case let .composedRichMessageWithAI(data):
            return RichTextMessageAttribute(apiRichMessage: data.result).instantPage
        }
    }
}

func _internal_translateTexts(network: Network, texts: [(String, [MessageTextEntity])], toLang: String, tone: TranslationTone = .neutral) -> Signal<[(String, [MessageTextEntity])], TranslationError> {
    var flags: Int32 = 0
    flags |= (1 << 1)
    
    if tone != .neutral {
        flags |= (1 << 2)
    }
    
    var apiTexts: [Api.TextWithEntities] = []
    for text in texts {
        apiTexts.append(.textWithEntities(.init(text: text.0, entities: apiEntitiesFromMessageTextEntities(text.1, associatedPeers: SimpleDictionary()))))
    }

    return network.request(Api.functions.messages.translateText(flags: flags, peer: nil, id: nil, text: apiTexts, toLang: toLang, tone: tone.rawValue))
    |> mapError { error -> TranslationError in
        if error.errorDescription.hasPrefix("FLOOD_WAIT") {
            return .limitExceeded
        } else if error.errorDescription == "MSG_ID_INVALID" {
            return .invalidMessageId
        } else if error.errorDescription == "INPUT_TEXT_EMPTY" {
            return .textIsEmpty
        } else if error.errorDescription == "INPUT_TEXT_TOO_LONG" {
            return .textTooLong
        } else if error.errorDescription == "TO_LANG_INVALID" {
            return .invalidLanguage
        } else {
            return .generic
        }
    }
    |> mapToSignal { result -> Signal<[(String, [MessageTextEntity])], TranslationError> in
        var texts: [(String, [MessageTextEntity])] = []
        switch result {
        case let .translateResult(translateResultData):
            let results = translateResultData.result
            for result in results {
                if case let .textWithEntities(textWithEntitiesData) = result {
                    let (text, entities) = (textWithEntitiesData.text, textWithEntitiesData.entities)
                    texts.append((text, messageTextEntitiesFromApiEntities(entities)))
                }
            }
        }
        return .single(texts)
    }
}

func _internal_translateMessages(account: Account, messageIds: [EngineMessage.Id], fromLang: String?, toLang: String, enableLocalIfPossible: Bool, enhanced: Bool = false, tone: TranslationTone = .neutral) -> Signal<Never, TranslationError> {
    var signals: [Signal<Void, TranslationError>] = []
    for (peerId, messageIds) in messagesIdsGroupedByPeerId(messageIds) {
        signals.append(_internal_translateMessagesByPeerId(account: account, peerId: peerId, messageIds: messageIds, fromLang: fromLang, toLang: toLang, enableLocalIfPossible: enableLocalIfPossible, enhanced: enhanced, tone: tone))
    }
    return combineLatest(signals)
    |> ignoreValues
}

public protocol ExperimentalInternalTranslationService: AnyObject {
    func translate(texts: [AnyHashable: String], fromLang: String, toLang: String) -> Signal<[AnyHashable: String]?, NoError>
    func translate(texts: [AnyHashable: String], fromLang: String, toLang: String, allowDownloads: Bool) -> Signal<[AnyHashable: String]?, NoError>
}

public extension ExperimentalInternalTranslationService {
    func translate(texts: [AnyHashable: String], fromLang: String, toLang: String, allowDownloads: Bool) -> Signal<[AnyHashable: String]?, NoError> {
        // Existing conformers without explicit download support stay installed-only.
        return self.translate(texts: texts, fromLang: fromLang, toLang: toLang)
    }
}

public var engineExperimentalInternalTranslationService: ExperimentalInternalTranslationService?

/// Translates rich messages (those carrying a `RichTextMessageAttribute`) by id via
/// `messages.translateRichMessage`, stores each result as a `TranslationMessageAttribute` with the
/// translated `InstantPage`, and returns the pages keyed by message id.
func _internal_translateRichMessages(account: Account, inputPeer: Api.InputPeer, messageIds: [EngineMessage.Id], toLang: String, tone: TranslationTone = .neutral) -> Signal<[EngineMessage.Id: InstantPage], TranslationError> {
    var flags: Int32 = 0
    flags |= (1 << 0)
    if tone != .neutral {
        flags |= (1 << 2)
    }
    return account.network.request(Api.functions.messages.translateRichMessage(flags: flags, peer: inputPeer, id: messageIds.map { $0.id }, text: nil, toLang: toLang, tone: tone != .neutral ? tone.rawValue : nil))
    |> mapError { error -> TranslationError in
        if error.errorDescription.hasPrefix("FLOOD_WAIT") {
            return .limitExceeded
        } else if error.errorDescription == "MSG_ID_INVALID" {
            return .invalidMessageId
        } else if error.errorDescription == "INPUT_TEXT_EMPTY" {
            return .textIsEmpty
        } else if error.errorDescription == "INPUT_TEXT_TOO_LONG" {
            return .textTooLong
        } else if error.errorDescription == "TO_LANG_INVALID" {
            return .invalidLanguage
        } else {
            return .generic
        }
    }
    |> mapToSignal { result -> Signal<[EngineMessage.Id: InstantPage], TranslationError> in
        var pages: [EngineMessage.Id: InstantPage] = [:]
        switch result {
        case let .translatedRichMessage(data):
            for (i, richMessage) in data.result.enumerated() where i < messageIds.count {
                pages[messageIds[i]] = RichTextMessageAttribute(apiRichMessage: richMessage).instantPage
            }
        }
        return account.postbox.transaction { transaction -> [EngineMessage.Id: InstantPage] in
            for (messageId, page) in pages {
                let updatedAttribute = TranslationMessageAttribute(text: "", entities: [], toLang: toLang, instantPage: page)
                transaction.updateMessage(messageId, update: { currentMessage in
                    let storeForwardInfo = currentMessage.forwardInfo.flatMap(StoreMessageForwardInfo.init)
                    var attributes = currentMessage.attributes.filter { !($0 is TranslationMessageAttribute) }
                    attributes.append(updatedAttribute)
                    return .update(StoreMessage(id: currentMessage.id, customStableId: nil, globallyUniqueId: currentMessage.globallyUniqueId, groupingKey: currentMessage.groupingKey, threadId: currentMessage.threadId, timestamp: currentMessage.timestamp, flags: StoreMessageFlags(currentMessage.flags), tags: currentMessage.tags, globalTags: currentMessage.globalTags, localTags: currentMessage.localTags, forwardInfo: storeForwardInfo, authorId: currentMessage.author?.id, text: currentMessage.text, attributes: attributes, media: currentMessage.media))
                })
            }
            return pages
        }
        |> castError(TranslationError.self)
    }
}

// JG174 source fingerprint begin
// Content-only identity; poll vote counters and unrelated message statistics do
// not invalidate a translation. The same key is checked after edits and reloads.
public func jerkgramTranslationSourceFingerprint(_ message: Message) -> String {
    let encoder = PostboxEncoder()
    encoder.encodeString(message.text, forKey: "text")
    encoder.encodeObjectArray(message.textEntitiesAttribute?.entities ?? [], forKey: "entities")
    encoder.encodeBool(message.attributes.contains(where: { $0 is RichTextMessageAttribute }), forKey: "rich")
    if let poll = message.media.first(where: { $0 is TelegramMediaPoll }) as? TelegramMediaPoll {
        encoder.encodeString(poll.text, forKey: "poll")
        encoder.encodeObjectArray(poll.textEntities, forKey: "pollEntities")
        encoder.encodeObjectArray(poll.options, forKey: "options")
        if let solution = poll.results.solution {
            encoder.encodeString(solution.text, forKey: "solution")
            encoder.encodeObjectArray(solution.entities, forKey: "solutionEntities")
        }
    }
    if let audio = message.attributes.first(where: { $0 is AudioTranscriptionMessageAttribute }) as? AudioTranscriptionMessageAttribute {
        encoder.encodeString(audio.text, forKey: "audio")
        encoder.encodeBool(audio.isPending, forKey: "pending")
    }
    encoder.encodeBool((message.attributes.first(where: { $0 is GhostBaseMessageAttribute }) as? GhostBaseMessageAttribute)?.isDeleted ?? false, forKey: "deleted")
    return "source-v2:" + sha256Digest(encoder.makeData()).map { String(format: "%02x", $0) }.joined()
}

public func jerkgramLocalTranslationIsCurrent(_ translation: TranslationMessageAttribute, message: Message, toLang: String, accountPeerId: Int64? = nil) -> Bool {
    return translation.toLang == toLang && !translation.jerkgramUnavailable && translation.jerkgramSourceFingerprint != nil && translation.isValidForMessage(message, accountPeerId: accountPeerId)
}
public func jerkgramLocalTranslationUnavailable(_ message: Message, toLang: String?, accountPeerId: Int64? = nil) -> Bool {
    guard let toLang,
          let translation = message.attributes.first(where: { $0 is TranslationMessageAttribute }) as? TranslationMessageAttribute else { return false }
    return translation.jerkgramUnavailable && translation.toLang == toLang && translation.isValidForMessage(message, accountPeerId: accountPeerId)
}
// JG174 source fingerprint end

private func jerkgramEnhancedMessageTexts(_ message: Message) -> JerkgramTranslatedTexts? {
    if message.attributes.contains(where: { $0 is RichTextMessageAttribute }) { return nil }
    if let poll = message.media.first(where: { $0 is TelegramMediaPoll }) as? TelegramMediaPoll {
        var texts: JerkgramTranslatedTexts = [(poll.text, poll.textEntities)] + poll.options.map { ($0.text, $0.entities) }
        if let solution = poll.results.solution { texts.append((solution.text, solution.entities)) }
        return texts
    }
    if let audio = message.attributes.first(where: { $0 is AudioTranscriptionMessageAttribute }) as? AudioTranscriptionMessageAttribute, !audio.isPending, !audio.text.isEmpty {
        guard message.text.isEmpty else { return nil }
        return [(audio.text, [])]
    }
    guard !message.text.isEmpty else { return nil }
    return [(message.text, message.textEntitiesAttribute?.entities ?? [])]
}

public func jerkgramTranslationSourceMatches(_ original: Message, _ current: Message) -> Bool {
    if original === current { return true }
    guard original.id == current.id, original.threadId == current.threadId else { return false }
    return jerkgramTranslationSourceFingerprint(original) == jerkgramTranslationSourceFingerprint(current)
}

private func jerkgramTranslateEnhancedMessages(account: Account, messages: [Message], fromLang: String?, toLang: String, localOnly: Bool) -> Signal<Void, TranslationError> {
    guard messages.count <= 64 else { return .fail(.textTooLong) }
    let generation = JerkgramTranslationSettings.generation(accountPeerId: account.peerId.toInt64())
    let signals: [Signal<Bool, NoError>] = messages.map { original in
        let cancelled = Atomic(value: false)
        let request: Signal<JerkgramTranslatedTexts?, NoError>
        if let texts = jerkgramEnhancedMessageTexts(original) {
            request = jerkgramEnhancedTexts(account: account, texts: texts, fromLang: fromLang, toLang: toLang, allowLocalDownloads: false, localOnly: localOnly)
            |> map(Optional.init)
            |> `catch` { _ -> Signal<JerkgramTranslatedTexts?, NoError> in .single(nil) }
        } else { request = .single(nil) }
        return request
        |> mapToSignal { translated -> Signal<Bool, NoError> in
            return account.postbox.transaction { transaction -> Bool in
                guard !cancelled.with({ $0 }), jerkgramPolicyIsCurrent(account: account, generation: generation) else { return false }
                var stored = false
                transaction.updateMessage(original.id, update: { current in
                    guard !cancelled.with({ $0 }), jerkgramPolicyIsCurrent(account: account, generation: generation), jerkgramTranslationSourceMatches(original, current) else { return .skip }
                    var additional: [TranslationMessageAttribute.Additional] = []
                    var solution: TranslationMessageAttribute.Additional?
                    if let translated, let poll = original.media.first(where: { $0 is TelegramMediaPoll }) as? TelegramMediaPoll {
                        for index in poll.options.indices { additional.append(.init(text: translated[index + 1].0, entities: translated[index + 1].1)) }
                        if poll.results.solution != nil, let last = translated.last { solution = .init(text: last.0, entities: last.1) }
                    }
                    var attributes = current.attributes.filter { !($0 is TranslationMessageAttribute) }
                    attributes.append(TranslationMessageAttribute(text: translated?.first?.0 ?? "", entities: translated?.first?.1 ?? [], additional: additional, pollSolution: solution, toLang: toLang, jerkgramSourceFingerprint: jerkgramTranslationSourceFingerprint(original), jerkgramUnavailable: translated == nil, jerkgramPolicyVersion: JerkgramTranslationSettings.policyVersion))
                    stored = translated != nil
                    return .update(StoreMessage(id: current.id, customStableId: nil, globallyUniqueId: current.globallyUniqueId, groupingKey: current.groupingKey, threadId: current.threadId, timestamp: current.timestamp, flags: StoreMessageFlags(current.flags), tags: current.tags, globalTags: current.globalTags, localTags: current.localTags, forwardInfo: current.forwardInfo.flatMap(StoreMessageForwardInfo.init), authorId: current.author?.id, text: current.text, attributes: attributes, media: current.media))
                })
                return stored
            }
        }
        |> afterDisposed { _ = cancelled.swap(true) }
    }
    if signals.isEmpty { return .single(Void()) }
    return combineLatest(signals)
    |> castError(TranslationError.self)
    |> mapToSignal { outcomes -> Signal<Void, TranslationError> in
        outcomes.allSatisfy({ $0 }) ? .single(Void()) : .fail(.generic)
    }
}


private func _internal_translateMessagesByPeerId(account: Account, peerId: EnginePeer.Id, messageIds: [EngineMessage.Id], fromLang: String?, toLang: String, enableLocalIfPossible: Bool, enhanced: Bool = false, tone: TranslationTone = .neutral) -> Signal<Void, TranslationError> {
    return account.postbox.transaction { transaction -> (Api.InputPeer?, [Message]) in
        return (transaction.getPeer(peerId).flatMap(apiInputPeer), messageIds.compactMap({ transaction.getMessage($0) }))
    }
    |> castError(TranslationError.self)
    |> mapToSignal { (inputPeer, messages) -> Signal<Void, TranslationError> in
        if enhanced {
            return jerkgramTranslateEnhancedMessages(account: account, messages: messages, fromLang: fromLang, toLang: toLang, localOnly: peerId.namespace == Namespaces.Peer.SecretChat)
        }
        guard let inputPeer = inputPeer else {
            return .never()
        }
        
        let polls = messages.compactMap { message in
            if let poll = message.media.first as? TelegramMediaPoll {
                return (poll, message.id)
            } else {
                return nil
            }
        }
        let pollSignals = polls.map { (poll, id) in
            var texts: [(String, [MessageTextEntity])] = []
            texts.append((poll.text, poll.textEntities))
            for option in poll.options {
                texts.append((option.text, option.entities))
            }
            if let solution = poll.results.solution {
                texts.append((solution.text, solution.entities))
            }
            return _internal_translateTexts(network: account.network, texts: texts, toLang: toLang)
        }
        
        let audioTranscriptions = messages.compactMap { message in
            if let audioTranscription = message.attributes.first(where: { $0 is AudioTranscriptionMessageAttribute }) as? AudioTranscriptionMessageAttribute, !audioTranscription.text.isEmpty && !audioTranscription.isPending {
                return (audioTranscription.text, message.id)
            } else {
                return nil
            }
        }
        let audioTranscriptionsSignals = audioTranscriptions.map { (text, id) in
            return _internal_translate(network: account.network, text: text, toLang: toLang)
        }
        
        var flags: Int32 = 0
        flags |= (1 << 0)
        if tone != .neutral {
            flags |= (1 << 2)
        }

        // Rich messages (a `RichTextMessageAttribute`) translate through `messages.translateRichMessage`
        // (per the layer-228 contract: pick translateText vs translateRichMessage by message type).
        let richMessageIds = messages.filter { $0.attributes.contains(where: { $0 is RichTextMessageAttribute }) }.map { $0.id }
        let plainMessageIds = messageIds.filter { !richMessageIds.contains($0) }

        let richSignal: Signal<Void, TranslationError>
        if richMessageIds.isEmpty {
            richSignal = .single(Void())
        } else {
            richSignal = _internal_translateRichMessages(account: account, inputPeer: inputPeer, messageIds: richMessageIds, toLang: toLang, tone: tone)
            |> map { _ in Void() }
        }

        let id: [Int32] = plainMessageIds.map { $0.id }

        let msgs: Signal<Api.messages.TranslatedText?, TranslationError>
        if id.isEmpty {
            msgs = .single(nil)
        } else {
            if enableLocalIfPossible, let engineExperimentalInternalTranslationService, let fromLang {
                msgs = account.postbox.transaction { transaction -> [MessageId: String] in
                    var texts: [MessageId: String] = [:]
                    for messageId in plainMessageIds {
                        if let message = transaction.getMessage(messageId) {
                            texts[message.id] = message.text
                        }
                    }
                    return texts
                }
                |> castError(TranslationError.self)
                |> mapToSignal { messageTexts -> Signal<Api.messages.TranslatedText?, TranslationError> in
                    var mappedTexts: [AnyHashable: String] = [:]
                    for (id, text) in messageTexts {
                        mappedTexts[AnyHashable(id)] = text
                    }
                    return engineExperimentalInternalTranslationService.translate(texts: mappedTexts, fromLang: fromLang, toLang: toLang)
                    |> castError(TranslationError.self)
                    |> mapToSignal { resultTexts -> Signal<Api.messages.TranslatedText?, TranslationError> in
                        guard let resultTexts else {
                            return .fail(.generic)
                        }
                        var result: [Api.TextWithEntities] = []
                        for messageId in plainMessageIds {
                            if let text = resultTexts[AnyHashable(messageId)] {
                                result.append(.textWithEntities(.init(text: text, entities: [])))
                            } else if let text = messageTexts[messageId] {
                                result.append(.textWithEntities(.init(text: text, entities: [])))
                            } else {
                                result.append(.textWithEntities(.init(text: "", entities: [])))
                            }
                        }
                        return .single(.translateResult(.init(result: result)))
                    }
                }
            } else {
                msgs = account.network.request(Api.functions.messages.translateText(flags: flags, peer: inputPeer, id: id, text: nil, toLang: toLang, tone: tone != .neutral ? tone.rawValue : nil))
                |> map(Optional.init)
                |> mapError { error -> TranslationError in
                    if error.errorDescription.hasPrefix("FLOOD_WAIT") {
                        return .limitExceeded
                    } else if error.errorDescription == "MSG_ID_INVALID" {
                        return .invalidMessageId
                    } else if error.errorDescription == "INPUT_TEXT_EMPTY" {
                        return .textIsEmpty
                    } else if error.errorDescription == "INPUT_TEXT_TOO_LONG" {
                        return .textTooLong
                    } else if error.errorDescription == "TO_LANG_INVALID" {
                        return .invalidLanguage
                    } else {
                        return .generic
                    }
                }
            }
        }
        
        return combineLatest(msgs, richSignal, combineLatest(pollSignals), combineLatest(audioTranscriptionsSignals))
        |> mapToSignal { (result, _, pollResults, audioTranscriptionsResults) -> Signal<Void, TranslationError> in
            return account.postbox.transaction { transaction in
                if case let .translateResult(translateResultData) = result {
                    let results = translateResultData.result
                    var index = 0
                    for result in results {
                        guard index < plainMessageIds.count else { break }
                        let messageId = plainMessageIds[index]
                        if case let .textWithEntities(textWithEntitiesData) = result {
                            let (text, entities) = (textWithEntitiesData.text, textWithEntitiesData.entities)
                            let updatedAttribute: TranslationMessageAttribute = TranslationMessageAttribute(text: text, entities: messageTextEntitiesFromApiEntities(entities), toLang: toLang)
                            transaction.updateMessage(messageId, update: { currentMessage in
                                let storeForwardInfo = currentMessage.forwardInfo.flatMap(StoreMessageForwardInfo.init)
                                var attributes = currentMessage.attributes.filter { !($0 is TranslationMessageAttribute) }
                                
                                attributes.append(updatedAttribute)
                                
                                return .update(StoreMessage(id: currentMessage.id, customStableId: nil, globallyUniqueId: currentMessage.globallyUniqueId, groupingKey: currentMessage.groupingKey, threadId: currentMessage.threadId, timestamp: currentMessage.timestamp, flags: StoreMessageFlags(currentMessage.flags), tags: currentMessage.tags, globalTags: currentMessage.globalTags, localTags: currentMessage.localTags, forwardInfo: storeForwardInfo, authorId: currentMessage.author?.id, text: currentMessage.text, attributes: attributes, media: currentMessage.media))
                            })
                        }
                        index += 1
                    }
                }
                
                if !pollResults.isEmpty {
                    for (i, poll) in polls.enumerated() {
                        let result = pollResults[i]
                        if !result.isEmpty {
                            transaction.updateMessage(poll.1, update: { currentMessage in
                                let storeForwardInfo = currentMessage.forwardInfo.flatMap(StoreMessageForwardInfo.init)
                                var attributes = currentMessage.attributes.filter { !($0 is TranslationMessageAttribute) }
                                var attrOptions: [TranslationMessageAttribute.Additional] = []
                                for (i, _) in poll.0.options.enumerated() {
                                    var translated = result.count > i + 1 ? result[i + 1] : (poll.0.options[i].text, poll.0.options[i].entities)
                                    if translated.0.isEmpty {
                                        translated = (poll.0.options[i].text, poll.0.options[i].entities)
                                    }
                                    attrOptions.append(TranslationMessageAttribute.Additional(text: translated.0, entities: translated.1))
                                }
                                
                                let solution: TranslationMessageAttribute.Additional?
                                if result.count > 1 + poll.0.options.count, !result[result.count - 1].0.isEmpty {
                                    solution = TranslationMessageAttribute.Additional(text: result[result.count - 1].0, entities: result[result.count - 1].1)
                                } else {
                                    solution = nil
                                }
                                
                                let title = result[0].0.isEmpty ? (poll.0.text, poll.0.textEntities) : result[0]
                                
                                let updatedAttribute: TranslationMessageAttribute = TranslationMessageAttribute(text: title.0, entities: title.1, additional: attrOptions, pollSolution: solution, toLang: toLang)
                                attributes.append(updatedAttribute)
                                
                                return .update(StoreMessage(id: currentMessage.id, customStableId: nil, globallyUniqueId: currentMessage.globallyUniqueId, groupingKey: currentMessage.groupingKey, threadId: currentMessage.threadId, timestamp: currentMessage.timestamp, flags: StoreMessageFlags(currentMessage.flags), tags: currentMessage.tags, globalTags: currentMessage.globalTags, localTags: currentMessage.localTags, forwardInfo: storeForwardInfo, authorId: currentMessage.author?.id, text: currentMessage.text, attributes: attributes, media: currentMessage.media))
                            })
                        }
                    }
                }
                
                if !audioTranscriptionsResults.isEmpty {
                    for (i, audioTranscription) in audioTranscriptions.enumerated() {
                        if let result = audioTranscriptionsResults[i] {
                            transaction.updateMessage(audioTranscription.1, update: { currentMessage in
                                let storeForwardInfo = currentMessage.forwardInfo.flatMap(StoreMessageForwardInfo.init)
                                var attributes = currentMessage.attributes.filter { !($0 is TranslationMessageAttribute) }
                                
                                let updatedAttribute: TranslationMessageAttribute = TranslationMessageAttribute(text: result.0, entities: result.1, additional: [], pollSolution: nil, toLang: toLang)
                                attributes.append(updatedAttribute)
                                
                                return .update(StoreMessage(id: currentMessage.id, customStableId: nil, globallyUniqueId: currentMessage.globallyUniqueId, groupingKey: currentMessage.groupingKey, threadId: currentMessage.threadId, timestamp: currentMessage.timestamp, flags: StoreMessageFlags(currentMessage.flags), tags: currentMessage.tags, globalTags: currentMessage.globalTags, localTags: currentMessage.localTags, forwardInfo: storeForwardInfo, authorId: currentMessage.author?.id, text: currentMessage.text, attributes: attributes, media: currentMessage.media))
                            })
                        }
                    }
                }
            }
            |> castError(TranslationError.self)
        }
    }
}

func _internal_togglePeerMessagesTranslationHidden(account: Account, peerId: EnginePeer.Id, hidden: Bool) -> Signal<Never, NoError> {
    return account.postbox.transaction { transaction -> Api.InputPeer? in
        transaction.updatePeerCachedData(peerIds: Set([peerId]), update: { _, cachedData -> CachedPeerData? in
            if let cachedData = cachedData as? CachedUserData {
                var updatedFlags = cachedData.flags
                if hidden {
                    updatedFlags.insert(.translationHidden)
                } else {
                    updatedFlags.remove(.translationHidden)
                }
                return cachedData.withUpdatedFlags(updatedFlags)
            } else if let cachedData = cachedData as? CachedGroupData {
                var updatedFlags = cachedData.flags
                if hidden {
                    updatedFlags.insert(.translationHidden)
                } else {
                    updatedFlags.remove(.translationHidden)
                }
                return cachedData.withUpdatedFlags(updatedFlags)
            } else if let cachedData = cachedData as? CachedChannelData {
                var updatedFlags = cachedData.flags
                if hidden {
                    updatedFlags.insert(.translationHidden)
                } else {
                    updatedFlags.remove(.translationHidden)
                }
                return cachedData.withUpdatedFlags(updatedFlags)
            } else {
                return cachedData
            }
        })
        return transaction.getPeer(peerId).flatMap(apiInputPeer)
    }
    |> mapToSignal { inputPeer -> Signal<Never, NoError> in
        guard let inputPeer = inputPeer else {
            return .never()
        }
        var flags: Int32 = 0
        if hidden {
            flags |= (1 << 0)
        }
        
        return account.network.request(Api.functions.messages.togglePeerTranslations(flags: flags, peer: inputPeer))
        |> map(Optional.init)
        |> `catch` { _ -> Signal<Api.Bool?, NoError> in
            return .single(nil)
        }
        |> ignoreValues
    }
}

public enum TelegramComposeAIMessageMode {
    public final class CloudStyle: Equatable, Codable {
        public enum Id: Hashable {
            case standard(String)
            case custom(Int64)
        }
        
        public enum Reference: Hashable {
            case standard(String)
            case custom(id: Int64, accessHash: Int64)
            
            public var id: Id {
                switch self {
                case let .standard(type):
                    return .standard(type)
                case let .custom(id, _):
                    return .custom(id)
                }
            }
        }
        
        public final class Standard: Codable, Equatable {
            private enum CodingKeys: String, CodingKey {
                case type
                case title
                case emojiFileId
            }
            
            public let type: String
            public let title: String
            public let emojiFileId: Int64?
            
            public init(type: String, title: String, emojiFileId: Int64?) {
                self.type = type
                self.title = title
                self.emojiFileId = emojiFileId
            }
            
            public init(from decoder: any Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                self.type = try container.decode(String.self, forKey: .type)
                self.title = try container.decode(String.self, forKey: .title)
                self.emojiFileId = try container.decodeIfPresent(Int64.self, forKey: .emojiFileId)
            }
            
            public func encode(to encoder: any Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                try container.encode(self.type, forKey: .type)
                try container.encode(self.title, forKey: .title)
                try container.encodeIfPresent(self.emojiFileId, forKey: .emojiFileId)
            }
            
            public static func ==(lhs: Standard, rhs: Standard) -> Bool {
                if lhs.type != rhs.type {
                    return false
                }
                if lhs.title != rhs.title {
                    return false
                }
                if lhs.emojiFileId != rhs.emojiFileId {
                    return false
                }
                return true
            }
        }
        
        public final class Custom: Codable, Equatable {
            private enum CodingKeys: String, CodingKey {
                case isCreator
                case id
                case accessHash
                case slug
                case emojiFileId
                case title
                case prompt
                case userCount
                case authorId
            }
            
            public let isCreator: Bool
            public let id: Int64
            public let accessHash: Int64
            public let slug: String
            public let emojiFileId: Int64?
            public let title: String
            public let prompt: String?
            public let userCount: Int?
            public let authorId: EnginePeer.Id?
            
            public init(isCreator: Bool, id: Int64, accessHash: Int64, slug: String, emojiFileId: Int64?, title: String, prompt: String?, userCount: Int?, authorId: EnginePeer.Id?) {
                self.isCreator = isCreator
                self.id = id
                self.accessHash = accessHash
                self.slug = slug
                self.emojiFileId = emojiFileId
                self.title = title
                self.prompt = prompt
                self.userCount = userCount
                self.authorId = authorId
            }
            
            public init(from decoder: any Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                
                self.isCreator = try container.decode(Bool.self, forKey: .isCreator)
                self.id = try container.decode(Int64.self, forKey: .id)
                self.accessHash = try container.decode(Int64.self, forKey: .accessHash)
                self.slug = try container.decode(String.self, forKey: .slug)
                self.emojiFileId = try container.decodeIfPresent(Int64.self, forKey: .emojiFileId)
                self.title = try container.decode(String.self, forKey: .title)
                self.prompt = try container.decodeIfPresent(String.self, forKey: .prompt)
                self.userCount = try container.decodeIfPresent(Int32.self, forKey: .userCount).flatMap(Int.init)
                self.authorId = try container.decodeIfPresent(EnginePeer.Id.self, forKey: .authorId)
            }
            
            public func encode(to encoder: any Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                
                try container.encode(self.isCreator, forKey: .isCreator)
                try container.encode(self.id, forKey: .id)
                try container.encode(self.accessHash, forKey: .accessHash)
                try container.encode(self.slug, forKey: .slug)
                try container.encodeIfPresent(self.emojiFileId, forKey: .emojiFileId)
                try container.encode(self.title, forKey: .title)
                try container.encodeIfPresent(self.prompt, forKey: .prompt)
                try container.encodeIfPresent(self.userCount.flatMap(Int32.init(clamping:)), forKey: .userCount)
                try container.encodeIfPresent(self.authorId, forKey: .authorId)
            }
            
            public static func ==(lhs: Custom, rhs: Custom) -> Bool {
                if lhs.isCreator != rhs.isCreator {
                    return false
                }
                if lhs.id != rhs.id {
                    return false
                }
                if lhs.accessHash != rhs.accessHash {
                    return false
                }
                if lhs.slug != rhs.slug {
                    return false
                }
                if lhs.emojiFileId != rhs.emojiFileId {
                    return false
                }
                if lhs.title != rhs.title {
                    return false
                }
                if lhs.prompt != rhs.prompt {
                    return false
                }
                if lhs.userCount != rhs.userCount {
                    return false
                }
                if lhs.authorId != rhs.authorId {
                    return false
                }
                return true
            }
        }
        
        public enum Content: Equatable, Codable {
            private enum CodingKeys: String, CodingKey {
                case discriminator = "d"
                case value = "v"
            }
            
            case standard(Standard)
            case custom(Custom)
            
            public init(from decoder: any Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                
                switch try container.decode(Int32.self, forKey: .discriminator) {
                case 0:
                    self = .standard(try container.decode(Standard.self, forKey: .value))
                case 1:
                    self = .custom(try container.decode(Custom.self, forKey: .value))
                default:
                    throw DecodingError.dataCorrupted(DecodingError.Context(codingPath: [], debugDescription: ""))
                }
            }
            
            public func encode(to encoder: any Encoder) throws {
                var container = encoder.container(keyedBy: CodingKeys.self)
                
                switch self {
                case let .standard(standard):
                    try container.encode(0 as Int32, forKey: .discriminator)
                    try container.encode(standard, forKey: .value)
                case let .custom(custom):
                    try container.encode(1 as Int32, forKey: .discriminator)
                    try container.encode(custom, forKey: .value)
                }
            }
        }
        
        public let content: Content
        
        public var id: StyleId {
            switch self.content {
            case let .standard(standard):
                return .style(.standard(standard.type))
            case let .custom(custom):
                return .style(.custom(custom.id))
            }
        }
        
        public var reference: Reference {
            switch self.content {
            case let .standard(standard):
                return .standard(standard.type)
            case let .custom(custom):
                return .custom(id: custom.id, accessHash: custom.accessHash)
            }
        }
        
        public init(content: Content) {
            self.content = content
        }
        
        public static func ==(lhs: CloudStyle, rhs: CloudStyle) -> Bool {
            if lhs.content != rhs.content {
                return false
            }
            return true
        }
    }
    
    public enum StyleId: Hashable {
        case neutral
        case prompt
        case style(CloudStyle.Id)
    }
    
    public enum StyleReference: Hashable {
        case neutral
        case prompt(String)
        case style(CloudStyle.Reference)
        
        public var id: StyleId {
            switch self {
            case .neutral:
                return .neutral
            case .prompt:
                return .prompt
            case let .style(style):
                return .style(style.id)
            }
        }
    }
    
    case translate(toLanguage: String, emojify: Bool, style: StyleReference)
    case stylize(emojify: Bool, style: StyleReference)
    case proofread
    case generate(prompt: String)
}

extension TelegramComposeAIMessageMode.CloudStyle {
    convenience init(apiTone: Api.AiComposeTone) {
        switch apiTone {
        case let .aiComposeTone(aiComposeTone):
            self.init(content: .custom(Custom(
                isCreator: (aiComposeTone.flags & (1 << 0)) != 0,
                id: aiComposeTone.id,
                accessHash: aiComposeTone.accessHash,
                slug: aiComposeTone.slug,
                emojiFileId: aiComposeTone.emojiId,
                title: aiComposeTone.title,
                prompt: aiComposeTone.prompt,
                userCount: aiComposeTone.installsCount.flatMap(Int.init),
                authorId: aiComposeTone.authorId.flatMap { id -> EnginePeer.Id in
                    return EnginePeer.Id(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt64Value(id))
                }
            )))
        case let .aiComposeToneDefault(aiComposeToneDefault):
            self.init(content: .standard(Standard(
                type: aiComposeToneDefault.tone,
                title: aiComposeToneDefault.title,
                emojiFileId: aiComposeToneDefault.emojiId
            )))
        }
    }
}

public final class TelegramAIComposeMessageResult {
    public let text: ComposedRichMessage
    public let diffRanges: [Range<Int>]
    
    public init(text: ComposedRichMessage, diffRanges: [Range<Int>]) {
        self.text = text
        self.diffRanges = diffRanges
    }
}

extension TextWithEntities {
    init(apiValue: Api.TextWithEntities) {
        switch apiValue {
        case let .textWithEntities(textWithEntities):
            self.init(text: textWithEntities.text, entities: messageTextEntitiesFromApiEntities(textWithEntities.entities))
        }
    }
}

extension TelegramComposeAIMessageMode.CloudStyle.Reference {
    var apiInputStyle: Api.InputAiComposeTone {
        switch self {
        case let .standard(type):
            return .inputAiComposeToneDefault(Api.InputAiComposeTone.Cons_inputAiComposeToneDefault(tone: type))
        case let .custom(id, accessHash):
            return .inputAiComposeToneID(Api.InputAiComposeTone.Cons_inputAiComposeToneID(id: id, accessHash: accessHash))
        }
    }
}

public enum TelegramAIComposeMessageError {
    case generic
    case nonPremiumFlood
}

func _internal_composeAIMessage(account: Account, text: ComposedRichMessage, mode: TelegramComposeAIMessageMode) -> Signal<TelegramAIComposeMessageResult, TelegramAIComposeMessageError> {
    var flags: Int32 = 0
    var translateToLang: String?
    var changeTone: Api.InputAiComposeTone?
    switch mode {
    case let .translate(toLanguage, emojify, style):
        translateToLang = toLanguage
        flags |= (1 << 1)
        
        if emojify {
            flags |= (1 << 3)
        }
        
        if case let .style(reference) = style {
            changeTone = reference.apiInputStyle
            flags |= (1 << 2)
        }
    case let .stylize(emojify, style):
        if emojify {
            flags |= (1 << 3)
        }
        
        if case let .style(reference) = style {
            changeTone = reference.apiInputStyle
            flags |= (1 << 2)
        } else if case let .prompt(prompt) = style {
            changeTone = .inputAiComposeToneSingleUse(Api.InputAiComposeTone.Cons_inputAiComposeToneSingleUse(customPrompt: prompt))
            flags |= (1 << 2)
        }
    case .proofread:
        flags |= (1 << 0)
    case let .generate(prompt):
        flags = 0
        flags |= (1 << 2)
        return account.network.request(Api.functions.messages.composeRichMessageWithAI(flags: flags, text: nil, translateToLang: nil, tone: .inputAiComposeToneSingleUse(Api.InputAiComposeTone.Cons_inputAiComposeToneSingleUse(customPrompt: prompt))))
        |> `catch` { error -> Signal<Api.messages.ComposedRichMessageWithAI, TelegramAIComposeMessageError> in
            if error.errorDescription == "AICOMPOSE_FLOOD_PREMIUM" {
                return .fail(.nonPremiumFlood)
            } else {
                return .fail(.generic)
            }
        }
        |> mapToSignal { result -> Signal<TelegramAIComposeMessageResult, TelegramAIComposeMessageError> in
            switch result {
            case let .composedRichMessageWithAI(composedMessageWithAI):
                let diffRanges: [Range<Int>] = []
                return .single(TelegramAIComposeMessageResult(
                    text: .rich(instantPage: RichTextMessageAttribute(apiRichMessage: composedMessageWithAI.result).instantPage),
                    diffRanges: diffRanges
                ))
            }
        }
    }
    
    switch text {
    case .empty, .plain:
        let inputText: Api.TextWithEntities
        if case let .plain(text, entities) = text {
            inputText = .textWithEntities(Api.TextWithEntities.Cons_textWithEntities(text: text, entities: apiEntitiesFromMessageTextEntities(entities, associatedPeers: SimpleDictionary())))
        } else {
            inputText = .textWithEntities(Api.TextWithEntities.Cons_textWithEntities(text: "", entities: []))
        }
        
        return account.network.request(Api.functions.messages.composeMessageWithAI(flags: flags, text: inputText, translateToLang: translateToLang, tone: changeTone))
        |> `catch` { error -> Signal<Api.messages.ComposedMessageWithAI, TelegramAIComposeMessageError> in
            if error.errorDescription == "AICOMPOSE_FLOOD_PREMIUM" {
                return .fail(.nonPremiumFlood)
            } else {
                return .fail(.generic)
            }
        }
        |> mapToSignal { result -> Signal<TelegramAIComposeMessageResult, TelegramAIComposeMessageError> in
            switch result {
            case let .composedMessageWithAI(composedMessageWithAI):
                var diffRanges: [Range<Int>] = []
                if let diffText = composedMessageWithAI.diffText {
                    switch diffText {
                    case let .textWithEntities(textWithEntities):
                        for entity in textWithEntities.entities {
                            switch entity {
                            case let .messageEntityDiffReplace(messageEntityDiffReplace):
                                if messageEntityDiffReplace.length >= 0 {
                                    diffRanges.append(Int(messageEntityDiffReplace.offset) ..< Int(messageEntityDiffReplace.offset + messageEntityDiffReplace.length))
                                }
                            case let .messageEntityDiffInsert(messageEntityDiffInsert):
                                if messageEntityDiffInsert.length >= 0 {
                                    diffRanges.append(Int(messageEntityDiffInsert.offset) ..< Int(messageEntityDiffInsert.offset + messageEntityDiffInsert.length))
                                }
                            default:
                                break
                            }
                        }
                    }
                }
                let resultText = TextWithEntities(apiValue: composedMessageWithAI.resultText)
                return .single(TelegramAIComposeMessageResult(
                    text: .plain(text: resultText.text, entities: resultText.entities),
                    diffRanges: diffRanges
                ))
            }
        }
    case let .rich(instantPage):
        flags |= (1 << 4)
        // No `users`: this page is rewritten and handed back, not sent; the send that follows lists them.
        let inputText = RichTextMessageAttribute(instantPage: instantPage, fullInstantPage: nil).apiInputRichMessage(users: [])
        return account.network.request(Api.functions.messages.composeRichMessageWithAI(flags: flags, text: inputText, translateToLang: translateToLang, tone: changeTone))
        |> `catch` { error -> Signal<Api.messages.ComposedRichMessageWithAI, TelegramAIComposeMessageError> in
            if error.errorDescription == "AICOMPOSE_FLOOD_PREMIUM" {
                return .fail(.nonPremiumFlood)
            } else {
                return .fail(.generic)
            }
        }
        |> mapToSignal { result -> Signal<TelegramAIComposeMessageResult, TelegramAIComposeMessageError> in
            switch result {
            case let .composedRichMessageWithAI(composedMessageWithAI):
                let diffRanges: [Range<Int>] = []
                return .single(TelegramAIComposeMessageResult(
                    text: .rich(instantPage: RichTextMessageAttribute(apiRichMessage: composedMessageWithAI.result).instantPage),
                    diffRanges: diffRanges
                ))
            }
        }
    }
}

public final class AIMessageStylePreview {
    public let from: ComposedRichMessage
    public let to: ComposedRichMessage
    public let index: Int?
    
    public init(from: ComposedRichMessage, to: ComposedRichMessage, index: Int?) {
        self.from = from
        self.to = to
        self.index = index
    }
}

extension AIMessageStylePreview {
    convenience init(apiPreview: Api.AiComposeToneExample, index: Int) {
        switch apiPreview {
        case let .aiComposeToneExample(aiComposeToneExample):
            let fromText = TextWithEntities(apiValue: aiComposeToneExample.from)
            let toText = TextWithEntities(apiValue: aiComposeToneExample.to)
            self.init(from: .plain(text: fromText.text, entities: fromText.entities), to: .plain(text: toText.text, entities: toText.entities), index: index)
        }
    }
}

public func _internal_requestAIMessageStylePreview(account: Account, reference: TelegramComposeAIMessageMode.CloudStyle.Reference, index: Int) -> Signal<AIMessageStylePreview?, NoError> {
    return account.network.request(Api.functions.aicompose.getToneExample(tone: reference.apiInputStyle, num: Int32(index)))
    |> map(Optional.init)
    |> `catch` { _ -> Signal<Api.AiComposeToneExample?, NoError> in
        return .single(nil)
    }
    |> map { result -> AIMessageStylePreview? in
        guard let result else {
            return nil
        }
        return AIMessageStylePreview(
            apiPreview: result,
            index: index
        )
    }
}

public enum CreateAITextStyleError {
    case generic
    case premiumRequired
}

func _internal_createAITextStyle(account: Account, displayAuthor: Bool, emojiFileId: Int64, title: String, prompt: String) -> Signal<TelegramComposeAIMessageMode.CloudStyle, CreateAITextStyleError> {
    var flags: Int32 = 0
    if displayAuthor {
        flags |= (1 << 0)
    }
    return account.network.request(Api.functions.aicompose.createTone(
        flags: flags,
        emojiId: emojiFileId,
        title: title,
        prompt: prompt
    ))
    |> mapError { error -> CreateAITextStyleError in
        if error.errorDescription == "TONES_SAVED_TOO_MANY" {
            return .premiumRequired
        }
        return .generic
    }
    |> mapToSignal { result -> Signal<TelegramComposeAIMessageMode.CloudStyle, CreateAITextStyleError> in
        return account.postbox.transaction { transaction -> TelegramComposeAIMessageMode.CloudStyle in
            let style = TelegramComposeAIMessageMode.CloudStyle(apiTone: result)
            
            let styles = _internal_cachedCloudAITextStyles(transaction: transaction)
            var items = styles?.items ?? []
            items.insert(style, at: 0)
            _internal_setCachedCloudAITextStyles(transaction: transaction, styles: CachedCloudAITextStyles(items: items, hash: 0))
            return style
        }
        |> castError(CreateAITextStyleError.self)
    }
}

public enum EditAITextStyleError {
    case generic
}

func _internal_editAITextStyle(account: Account, id: Int64, accessHash: Int64, displayAuthor: Bool, emojiFileId: Int64, title: String, prompt: String) -> Signal<TelegramComposeAIMessageMode.CloudStyle, EditAITextStyleError> {
    var flags: Int32 = 0
    flags |= (1 << 0)
    flags |= (1 << 1)
    flags |= (1 << 2)
    flags |= (1 << 3)
    return account.network.request(Api.functions.aicompose.updateTone(
        flags: flags,
        tone: .inputAiComposeToneID(Api.InputAiComposeTone.Cons_inputAiComposeToneID(id: id, accessHash: accessHash)),
        displayAuthor: displayAuthor ? .boolTrue : .boolFalse,
        emojiId: emojiFileId,
        title: title,
        prompt: prompt
    ))
    |> mapError { _ -> EditAITextStyleError in
        return .generic
    }
    |> mapToSignal { result -> Signal<TelegramComposeAIMessageMode.CloudStyle, EditAITextStyleError> in
        return account.postbox.transaction { transaction -> TelegramComposeAIMessageMode.CloudStyle in
            let style = TelegramComposeAIMessageMode.CloudStyle(apiTone: result)
            
            let styles = _internal_cachedCloudAITextStyles(transaction: transaction)
            var items = styles?.items ?? []
            if let index = items.firstIndex(where: { $0.id == .style(.custom(id)) }) {
                items[index] = style
            }
            _internal_setCachedCloudAITextStyles(transaction: transaction, styles: CachedCloudAITextStyles(items: items, hash: 0))
            return style
        }
        |> castError(EditAITextStyleError.self)
    }
}

public struct TelegramAIComposeToneExample: Equatable {
    public let from: TextWithEntities
    public let to: TextWithEntities
    public init(from: TextWithEntities, to: TextWithEntities) {
        self.from = from
        self.to = to
    }
}

private func _internal_mapToneExample(_ apiExample: Api.AiComposeToneExample) -> TelegramAIComposeToneExample {
    switch apiExample {
    case let .aiComposeToneExample(data):
        return TelegramAIComposeToneExample(from: TextWithEntities(apiValue: data.from), to: TextWithEntities(apiValue: data.to))
    }
}

func _internal_getAIComposeToneExample(network: Network, tone: TelegramComposeAIMessageMode.CloudStyle.Reference, num: Int32) -> Signal<TelegramAIComposeToneExample?, NoError> {
    return network.request(Api.functions.aicompose.getToneExample(tone: tone.apiInputStyle, num: num))
    |> map { apiExample -> TelegramAIComposeToneExample? in
        return _internal_mapToneExample(apiExample)
    }
    |> `catch` { _ -> Signal<TelegramAIComposeToneExample?, NoError> in
        return .single(nil)
    }
}

func _internal_getAIComposeToneExample(network: Network, slug: String, num: Int32) -> Signal<TelegramAIComposeToneExample?, NoError> {
    return network.request(Api.functions.aicompose.getToneExample(tone: .inputAiComposeToneSlug(Api.InputAiComposeTone.Cons_inputAiComposeToneSlug(slug: slug)), num: num))
    |> map { apiExample -> TelegramAIComposeToneExample? in
        return _internal_mapToneExample(apiExample)
    }
    |> `catch` { _ -> Signal<TelegramAIComposeToneExample?, NoError> in
        return .single(nil)
    }
}

public enum DeleteAITextStyleError {
    case generic
}

func _internal_deleteAITextStyle(account: Account, id: Int64, accessHash: Int64) -> Signal<Never, DeleteAITextStyleError> {
    return account.network.request(Api.functions.aicompose.deleteTone(tone: .inputAiComposeToneID(Api.InputAiComposeTone.Cons_inputAiComposeToneID(id: id, accessHash: accessHash))))
    |> mapError { _ -> DeleteAITextStyleError in
        return .generic
    }
    |> mapToSignal { result -> Signal<Never, DeleteAITextStyleError> in
        return account.postbox.transaction { transaction -> Void in
            let styles = _internal_cachedCloudAITextStyles(transaction: transaction)
            var items = styles?.items ?? []
            items.removeAll(where: { $0.id == .style(.custom(id)) })
            _internal_setCachedCloudAITextStyles(transaction: transaction, styles: CachedCloudAITextStyles(items: items, hash: 0))
        }
        |> castError(DeleteAITextStyleError.self)
        |> ignoreValues
    }
}

func _internal_unsaveAITextStyle(account: Account, id: Int64, accessHash: Int64) -> Signal<Never, DeleteAITextStyleError> {
    return account.network.request(Api.functions.aicompose.saveTone(tone: .inputAiComposeToneID(Api.InputAiComposeTone.Cons_inputAiComposeToneID(id: id, accessHash: accessHash)), unsave: .boolTrue))
    |> mapError { _ -> DeleteAITextStyleError in
        return .generic
    }
    |> mapToSignal { _ -> Signal<Never, DeleteAITextStyleError> in
        return account.postbox.transaction { transaction -> Void in
            let styles = _internal_cachedCloudAITextStyles(transaction: transaction)
            var items = styles?.items ?? []
            items.removeAll(where: { $0.id == .style(.custom(id)) })
            _internal_setCachedCloudAITextStyles(transaction: transaction, styles: CachedCloudAITextStyles(items: items, hash: 0))
        }
        |> castError(DeleteAITextStyleError.self)
        |> ignoreValues
    }
}

final class CachedCloudAITextStyles: Codable {
    let items: [TelegramComposeAIMessageMode.CloudStyle]
    let hash: Int64
    
    init(items: [TelegramComposeAIMessageMode.CloudStyle], hash: Int64) {
        self.items = items
        self.hash = hash
    }
}

func _internal_cachedCloudAITextStyles(postbox: Postbox) -> Signal<CachedCloudAITextStyles?, NoError> {
    return postbox.transaction { transaction -> CachedCloudAITextStyles? in
        return _internal_cachedCloudAITextStyles(transaction: transaction)
    }
}

func _internal_cachedCloudAITextStyles(transaction: Transaction) -> CachedCloudAITextStyles? {
    let key = ValueBoxKey(length: 8)
    key.setInt64(0, value: 0)
    
    let cached = transaction.retrieveItemCacheEntry(id: ItemCacheEntryId(collectionId: Namespaces.CachedItemCollection.cachedCloudAITextStyles, key: key))?.get(CachedCloudAITextStyles.self)
    if let cached {
        return cached
    } else {
        return nil
    }
}

func _internal_setCachedCloudAITextStyles(transaction: Transaction, styles: CachedCloudAITextStyles) {
    let key = ValueBoxKey(length: 8)
    key.setInt64(0, value: 0)
    
    if let entry = CodableEntry(styles) {
        transaction.putItemCacheEntry(id: ItemCacheEntryId(collectionId: Namespaces.CachedItemCollection.cachedCloudAITextStyles, key: key), entry: entry)
    }
}

func _internal_requestAIMessageStyle(account: Account, slug: String) -> Signal<(style: TelegramComposeAIMessageMode.CloudStyle, initialPreview: AIMessageStylePreview?)?, NoError> {
    return account.network.request(Api.functions.aicompose.getTone(tone: .inputAiComposeToneSlug(Api.InputAiComposeTone.Cons_inputAiComposeToneSlug(slug: slug))))
    |> map(Optional.init)
    |> `catch` { _ -> Signal<Api.aicompose.Tones?, NoError> in
        return .single(nil)
    }
    |> mapToSignal { result -> Signal<(style: TelegramComposeAIMessageMode.CloudStyle, initialPreview: AIMessageStylePreview?)?, NoError> in
        guard let result else {
            return .single(nil)
        }
        return account.postbox.transaction { transaction -> (style: TelegramComposeAIMessageMode.CloudStyle, initialPreview: AIMessageStylePreview?)? in
            switch result {
            case let .tones(tones):
                guard let tone = tones.tones.first else {
                    return nil
                }
                updatePeers(transaction: transaction, accountPeerId: account.peerId, peers: AccumulatedPeers(users: tones.users))
                return (TelegramComposeAIMessageMode.CloudStyle(apiTone: tone), nil)
            case .tonesNotModified:
                return nil
            }
        }
    }
}

public enum InstallAIMessageStyleError {
    case generic
}

func _internal_installAIMessageStyle(account: Account, style: TelegramComposeAIMessageMode.CloudStyle.Custom) -> Signal<Never, InstallAIMessageStyleError> {
    return account.network.request(Api.functions.aicompose.saveTone(tone: .inputAiComposeToneID(Api.InputAiComposeTone.Cons_inputAiComposeToneID(id: style.id, accessHash: style.accessHash)), unsave: .boolFalse))
    |> map(Optional.init)
    |> `catch` { _ -> Signal<Api.Bool?, NoError> in
        return .single(nil)
    }
    |> castError(InstallAIMessageStyleError.self)
    |> mapToSignal { result -> Signal<Never, InstallAIMessageStyleError> in
        if result != nil {
            return account.postbox.transaction { transaction -> Void in
                var items = _internal_cachedCloudAITextStyles(transaction: transaction)?.items ?? []
                if let index = items.firstIndex(where: { $0.id == .style(.custom(style.id)) }) {
                    items.remove(at: index)
                }
                items.insert(TelegramComposeAIMessageMode.CloudStyle(content: .custom(style)), at: 0)
                _internal_setCachedCloudAITextStyles(transaction: transaction, styles: CachedCloudAITextStyles(items: items, hash: 0))
            }
            |> ignoreValues
            |> castError(InstallAIMessageStyleError.self)
        } else {
            return .fail(.generic)
        }
    }
}

func managedSynchronizeCloudAITextStyles(postbox: Postbox, network: Network) -> Signal<Never, NoError> {
    let poll = Signal<Never, NoError> { subscriber in
        let signal: Signal<Never, NoError> = _internal_cachedCloudAITextStyles(postbox: postbox)
        |> mapToSignal { current in
            return (network.request(Api.functions.aicompose.getTones(hash: current?.hash ?? 0))
            |> map(Optional.init)
            |> `catch` { _ -> Signal<Api.aicompose.Tones?, NoError> in
                return .single(nil)
            }
            |> mapToSignal { result -> Signal<Never, NoError> in
                return postbox.transaction { transaction -> Signal<Never, NoError> in
                    guard let result = result else {
                        return .complete()
                    }
                    
                    switch result {
                    case let .tones(tones):
                        _internal_setCachedCloudAITextStyles(transaction: transaction, styles: CachedCloudAITextStyles(
                            items: tones.tones.map(TelegramComposeAIMessageMode.CloudStyle.init(apiTone:)),
                            hash: tones.hash
                        ))
                    case .tonesNotModified:
                        break
                    }
                    
                    return .complete()
                }
                |> switchToLatest
            })
        }
                
        return signal.start(completed: {
            subscriber.putCompletion()
        })
    }
    
    return (
        poll
        |> then(
            .complete()
            |> suspendAwareDelay(1.0 * 60.0 * 60.0, queue: Queue.concurrentDefaultQueue())
        )
    )
    |> restart
}
