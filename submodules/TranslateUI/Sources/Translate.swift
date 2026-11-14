import Foundation
import UIKit
import Display
import SwiftSignalKit
import AccountContext
import NaturalLanguage
import TelegramCore
import SwiftUI
import Translation
import Combine

// Incuding at least one Objective-C class in a swift file ensures that it doesn't get stripped by the linker
private final class LinkHelperClass: NSObject {
}

public var supportedTranslationLanguages = [
    "af",
    "sq",
    "am",
    "ar",
    "hy",
    "az",
    "eu",
    "be",
    "bn",
    "bs",
    "bg",
    "ca",
    "ceb",
    "zh",
    "co",
    "hr",
    "cs",
    "da",
    "nl",
    "en",
    "eo",
    "et",
    "fi",
    "fr",
    "fy",
    "gl",
    "ka",
    "de",
    "el",
    "gu",
    "ht",
    "ha",
    "haw",
    "he",
    "hi",
    "hmn",
    "hu",
    "is",
    "ig",
    "id",
    "ga",
    "it",
    "ja",
    "jv",
    "kn",
    "kk",
    "km",
    "rw",
    "ko",
    "ku",
    "ky",
    "lo",
    "lv",
    "lt",
    "lb",
    "mk",
    "mg",
    "ms",
    "ml",
    "mt",
    "mi",
    "mr",
    "mn",
    "my",
    "ne",
    "no",
    "ny",
    "or",
    "ps",
    "fa",
    "pl",
    "pt",
    "pt-BR",
    "pa",
    "ro",
    "ru",
    "sm",
    "gd",
    "sr",
    "st",
    "sn",
    "sd",
    "si",
    "sk",
    "sl",
    "so",
    "es",
    "su",
    "sw",
    "sv",
    "tl",
    "tg",
    "ta",
    "tt",
    "te",
    "th",
    "tr",
    "tk",
    "uk",
    "ur",
    "ug",
    "uz",
    "vi",
    "cy",
    "xh",
    "yi",
    "yo",
    "zu"
]

public var popularTranslationLanguages = [
    "en",
    "ar",
    "zh",
    "fr",
    "de",
    "it",
    "ja",
    "ko",
    "pt-BR",
    "ru",
    "es",
    "uk"
]



public func effectiveIgnoredTranslationLanguages(context: AccountContext, ignoredLanguages: [String]?) -> Set<String> {
    var baseLang = context.sharedContext.currentPresentationData.with { $0 }.strings.baseLanguageCode
    let rawSuffix = "-raw"
    if baseLang.hasSuffix(rawSuffix) {
        baseLang = String(baseLang.dropLast(rawSuffix.count))
    }
    
    var dontTranslateLanguages = Set<String>()
    if let ignoredLanguages = ignoredLanguages {
        dontTranslateLanguages = Set(ignoredLanguages)
    } else {
        dontTranslateLanguages.insert(baseLang)
        for language in systemLanguageCodes() {
            dontTranslateLanguages.insert(language)
        }
    }
    return dontTranslateLanguages
}

public func normalizeTranslationLanguage(_ code: String) -> String {
    var code = code
    if code.contains("-") {
        code = code.components(separatedBy: "-").first ?? code
    }
    if code == "nb" {
        code = "no"
    }
    return code
}

public func canTranslateChats(context: AccountContext) -> Bool {
    if jerkgramEnhancedTranslationEnabled(context: context) { return true }
    let translationConfiguration = TranslationConfiguration.with(appConfiguration: context.currentAppConfiguration.with { $0 })
    var chatTranslationAvailable = true
    switch translationConfiguration.auto {
    case .system:
        if #available(iOS 18.0, *) {
        } else {
            chatTranslationAvailable = false
        }
    case .alternative, .disabled:
        chatTranslationAvailable = false
    default:
        break
    }
    return chatTranslationAvailable
}

public func canTranslateText(context: AccountContext, text: String, showTranslate: Bool, showTranslateIfTopical: Bool = false, ignoredLanguages: [String]?) -> (canTranslate: Bool, language: String?) {
    guard showTranslate || showTranslateIfTopical, text.count > 0 else {
        return (false, nil)
    }

    let translationConfiguration = TranslationConfiguration.with(appConfiguration: context.currentAppConfiguration.with { $0 })
    var translateButtonAvailable = false
    switch translationConfiguration.manual {
    case .enabled, .alternative:
        translateButtonAvailable = true
    case .system:
        if #available(iOS 18.0, *) {
            translateButtonAvailable = true
        }
    default:
        break
    }
    
    let showTranslate = showTranslate && (translateButtonAvailable || jerkgramEnhancedTranslationEnabled(context: context))
        
    if #available(iOS 12.0, *) {
        if context.sharedContext.immediateExperimentalUISettings.disableLanguageRecognition {
            return (true, nil)
        }
                
        let dontTranslateLanguages = effectiveIgnoredTranslationLanguages(context: context, ignoredLanguages: ignoredLanguages)
        
        let text = String(text.prefix(64))
        let languageRecognizer = NLLanguageRecognizer()
        languageRecognizer.processString(text)
        let hypotheses = languageRecognizer.languageHypotheses(withMaximum: 3)
        languageRecognizer.reset()
        
        var supportedTranslationLanguages = supportedTranslationLanguages
        if !showTranslate && showTranslateIfTopical {
            supportedTranslationLanguages = ["uk", "ru"]
        }
                
        let filteredLanguages = hypotheses.filter { supportedTranslationLanguages.contains(normalizeTranslationLanguage($0.key.rawValue)) }.sorted(by: { $0.value > $1.value })
        if let language = filteredLanguages.first {
            let languageCode = normalizeTranslationLanguage(language.key.rawValue)
            return (!dontTranslateLanguages.contains(languageCode), languageCode)
        } else {
            return (false, nil)
        }
    } else {
        return (false, nil)
    }
}

public func systemLanguageCodes() -> [String] {
    var languages: [String] = []
    for language in Locale.preferredLanguages.prefix(2) {
        let language = language.components(separatedBy: "-").first ?? language
        languages.append(language)
    }
    if languages.count == 2 && languages != ["en", "ru"] {
        languages = Array(languages.prefix(1))
    }
    return languages
}

@available(iOS 13.0, *)
class ExternalTranslationTrigger: ObservableObject {
    @Published var shouldInvalidate: Int = 0
}

// JG174 translation queue begin
// Main-queue coordinator. Physical work remains active until the framework returns,
// even when all subscribers cancel. Keys stay in-process; Apple sees opaque indices.
private final class JerkgramTranslationQueue {
    final class Job {
        let id: Int
        let texts: [AnyHashable: String]
        let fromLang: String
        let toLang: String
        let byteCount: Int
        let allowDownloads: Bool
        var subscribers: [Int: ([AnyHashable: String]?) -> Void] = [:]
        init(id: Int, texts: [AnyHashable: String], fromLang: String, toLang: String, allowDownloads: Bool) {
            self.id = id; self.texts = texts; self.fromLang = fromLang; self.toLang = toLang
            self.byteCount = texts.values.reduce(0) { $0 + $1.utf8.count }
            self.allowDownloads = allowDownloads
        }
        func matches(_ texts: [AnyHashable: String], _ from: String, _ to: String, _ allowDownloads: Bool) -> Bool {
            return self.texts == texts && self.fromLang == from && self.toLang == to && self.allowDownloads == allowDownloads
        }
    }
    private struct Cached {
        let texts: [AnyHashable: String]
        let from: String
        let to: String
        let result: [AnyHashable: String]
        let bytes: Int
    }
    private var nextId = 0
    private(set) var pending: [Job] = []
    private(set) var active: Job?
    private var cache: [Cached] = []
    private(set) var cacheBytes = 0
    private(set) var cacheItems = 0
    private(set) var workBytes = 0
    private(set) var workItems = 0

    // nil callback payload is an explicit failure, never original-as-success.
    func enqueue(texts: [AnyHashable: String], from: String, to: String, allowDownloads: Bool = false, completion: @escaping ([AnyHashable: String]?) -> Void) -> (Int, Int)? {
        guard !texts.isEmpty, texts.count <= 16, !to.isEmpty,
              texts.values.allSatisfy({ !$0.isEmpty }),
              texts.values.reduce(0, { $0 + $1.utf8.count }) <= 16 * 1024 else {
            completion(nil); return nil
        }
        self.nextId += 1
        let subscriber = self.nextId
        if let index = self.cache.firstIndex(where: { $0.texts == texts && $0.from == from && $0.to == to }) {
            let cached = self.cache.remove(at: index)
            self.cache.append(cached)
            completion(cached.result)
            return nil
        }
        if let job = ([self.active].compactMap { $0 } + self.pending).first(where: { $0.matches(texts, from, to, allowDownloads) && !$0.subscribers.isEmpty }) {
            job.subscribers[subscriber] = completion
            return (job.id, subscriber)
        }
        let bytes = texts.values.reduce(0) { $0 + $1.utf8.count }
        guard self.workItems + texts.count <= 64, self.workBytes + bytes <= 128 * 1024 else {
            completion(nil); return nil
        }
        let job = Job(id: subscriber, texts: texts, fromLang: from, toLang: to, allowDownloads: allowDownloads)
        job.subscribers[subscriber] = completion
        self.pending.append(job)
        self.workItems += texts.count; self.workBytes += bytes
        return (job.id, subscriber)
    }

    var nextLanguagePair: (String, String)? {
        guard self.active == nil, let job = self.pending.first else { return nil }
        return (job.fromLang, job.toLang)
    }

    func begin() -> Job? {
        guard self.active == nil, !self.pending.isEmpty else { return nil }
        let job = self.pending.removeFirst()
        self.active = job
        return job
    }

    // Rechecked after async availability: cancelled/expired work cannot open UI.
    func canTranslate(jobId: Int, installed: Bool) -> Bool {
        guard let job = self.active, job.id == jobId, !job.subscribers.isEmpty,
              !job.fromLang.isEmpty else { return false }
        return installed || job.allowDownloads
    }

    func cancel(jobId: Int, subscriberId: Int) {
        if let job = self.active, job.id == jobId {
            job.subscribers.removeValue(forKey: subscriberId)
            // Do not release the physical slot while TranslationSession is running.
            return
        }
        guard let index = self.pending.firstIndex(where: { $0.id == jobId }) else { return }
        let job = self.pending[index]
        job.subscribers.removeValue(forKey: subscriberId)
        if job.subscribers.isEmpty {
            self.pending.remove(at: index)
            self.workItems -= job.texts.count; self.workBytes -= job.byteCount
        }
    }

    func expire(jobId: Int) -> [() -> Void] {
        guard let job = self.active, job.id == jobId else { return [] }
        let callbacks = job.subscribers.values.map { callback in { callback(nil) } }
        job.subscribers.removeAll()
        // A user-visible timeout is logical cancellation. Keep the physical
        // slot until the framework finishes; never start concurrent sessions.
        return callbacks
    }

    func finish(jobId: Int, result: [AnyHashable: String]?) -> [() -> Void] {
        guard let job = self.active, job.id == jobId else { return [] }
        self.active = nil
        self.workItems -= job.texts.count; self.workBytes -= job.byteCount
        let validated: [AnyHashable: String]?
        if let result, result.count == job.texts.count,
           job.texts.keys.allSatisfy({ result[$0]?.isEmpty == false }) {
            validated = result
        } else { validated = nil }
        if let validated, !job.subscribers.isEmpty {
            let bytes = job.byteCount + validated.values.reduce(0) { $0 + $1.utf8.count }
            if bytes <= 1024 * 1024 {
                self.cache.append(Cached(texts: job.texts, from: job.fromLang, to: job.toLang, result: validated, bytes: bytes))
                self.cacheBytes += bytes; self.cacheItems += job.texts.count
                while self.cacheItems > 256 || self.cacheBytes > 1024 * 1024 {
                    let evicted = self.cache.removeFirst()
                    self.cacheBytes -= evicted.bytes; self.cacheItems -= evicted.texts.count
                }
            }
        }
        let callbacks = job.subscribers.values.map { callback in { callback(validated) } }
        job.subscribers.removeAll()
        return callbacks
    }
}
// JG174 translation queue end

@available(iOS 18.0, *)
private struct TranslationViewImpl: View {
    @State private var configuration: TranslationSession.Configuration?
    @ObservedObject var externalCondition: ExternalTranslationTrigger
    private let taskContainer: Atomic<JerkgramTranslationQueue>

    init(externalCondition: ExternalTranslationTrigger, taskContainer: Atomic<JerkgramTranslationQueue>) {
        self.externalCondition = externalCondition; self.taskContainer = taskContainer
    }

    private func scheduleNext() {
        guard let pair = self.taskContainer.with({ $0.nextLanguagePair }) else { return }
        if let configuration = self.configuration,
           configuration.source?.languageCode?.identifier == (pair.0.isEmpty ? nil : pair.0),
           configuration.target?.languageCode?.identifier == pair.1 {
            self.configuration?.invalidate()
        } else {
            self.configuration = .init(source: pair.0.isEmpty ? nil : Locale.Language(identifier: pair.0), target: Locale.Language(identifier: pair.1))
        }
    }

    var body: some View {
        Text("").hidden()
        .onChange(of: self.externalCondition.shouldInvalidate) { _ in self.scheduleNext() }
        .translationTask(self.configuration, action: { session in
            guard let job = self.taskContainer.with({ $0.begin() }) else { return }
            let jobId = job.id
            // A generous bound includes possible system language downloads.
            // Closing the native screen cancels its subscriber immediately.
            let timeout = SwiftSignalKit.Timer(timeout: 300.0, repeat: false, completion: {
                let callbacks = self.taskContainer.with { $0.expire(jobId: jobId) }
                for callback in callbacks { callback() }
            }, queue: .mainQueue())
            timeout.start()
            defer { timeout.invalidate() }
            var result: [AnyHashable: String]?
            do {
                let ordered = Array(job.texts)
                let requests = ordered.enumerated().map { index, entry in
                    TranslationSession.Request(sourceText: entry.value, clientIdentifier: String(index))
                }
                let source = Locale.Language(identifier: job.fromLang)
                let target = Locale.Language(identifier: job.toLang)
                let status = await LanguageAvailability().status(from: source, to: target)
                guard !Task.isCancelled, self.taskContainer.with({ $0.canTranslate(jobId: job.id, installed: status == .installed) }) else {
                    let callbacks = self.taskContainer.with { $0.finish(jobId: job.id, result: nil) }
                    for callback in callbacks { callback() }
                    self.scheduleNext()
                    return
                }
                let translationSession: TranslationSession
                if #available(iOS 26.0, *), !job.allowDownloads {
                    // This session cannot request downloads even if models disappear
                    // between availability and translation. Automatic work stays silent.
                    translationSession = TranslationSession(installedSource: source, target: target)
                } else {
                    translationSession = session
                }
                let responses = try await translationSession.translations(from: requests)
                if !Task.isCancelled {
                    var values: [AnyHashable: String] = [:]
                    for response in responses {
                        if let identifier = response.clientIdentifier, let index = Int(identifier), ordered.indices.contains(index) {
                            values[ordered[index].key] = response.targetText
                        }
                    }
                    result = values
                }
            } catch { result = nil }
            let callbacks = self.taskContainer.with { $0.finish(jobId: job.id, result: result) }
            for callback in callbacks { callback() }
            // Configuration changes only after the physical request has returned.
            self.scheduleNext()
        })
    }
}

@available(iOS 18.0, *)
public final class ExperimentalInternalTranslationServiceImpl: ExperimentalInternalTranslationService {
    private final class Impl {
        private let hostingController: UIViewController
        private let taskContainer = Atomic(value: JerkgramTranslationQueue())
        private let taskTrigger = ExternalTranslationTrigger()

        init(view: UIView) {
            self.hostingController = UIHostingController(rootView: TranslationViewImpl(externalCondition: self.taskTrigger, taskContainer: self.taskContainer))
            self.hostingController.view.isUserInteractionEnabled = false
            self.hostingController.view.backgroundColor = .clear
            self.hostingController.view.frame = CGRect(x: 0, y: 0, width: 1, height: 1)
            view.addSubview(self.hostingController.view)
        }

        func translate(texts: [AnyHashable: String], fromLang: String, toLang: String, allowDownloads: Bool, onResult: @escaping ([AnyHashable: String]?) -> Void) -> Disposable {
            let source: String
            if fromLang.isEmpty {
                let recognizer = NLLanguageRecognizer()
                recognizer.processString(String(texts.values.joined(separator: " ").prefix(512)))
                source = recognizer.dominantLanguage?.rawValue ?? ""
            } else { source = fromLang }
            let identity = self.taskContainer.with { queue in
                queue.enqueue(texts: texts, from: source, to: toLang, allowDownloads: allowDownloads, completion: { result in
                    Queue.mainQueue().async { onResult(result) }
                })
            }
            if identity != nil { self.taskTrigger.shouldInvalidate += 1 }
            return ActionDisposable { [weak self] in
                Queue.mainQueue().async {
                    guard let self, let identity else { return }
                    self.taskContainer.with { $0.cancel(jobId: identity.0, subscriberId: identity.1) }
                }
            }
        }
    }
    private let impl: QueueLocalObject<Impl>
    public init(view: UIView) {
        self.impl = QueueLocalObject(queue: .mainQueue(), generate: { Impl(view: view) })
    }
    public func translate(texts: [AnyHashable: String], fromLang: String, toLang: String) -> Signal<[AnyHashable: String]?, NoError> {
        return self.translate(texts: texts, fromLang: fromLang, toLang: toLang, allowDownloads: false)
    }
    public func translate(texts: [AnyHashable: String], fromLang: String, toLang: String, allowDownloads: Bool) -> Signal<[AnyHashable: String]?, NoError> {
        return self.impl.signalWith { impl, subscriber in
            impl.translate(texts: texts, fromLang: fromLang, toLang: toLang, allowDownloads: allowDownloads, onResult: { result in
                subscriber.putNext(result); subscriber.putCompletion()
            })
        }
    }
}

public func jerkgramEnhancedTranslationEnabled(context: AccountContext) -> Bool {
    return JerkgramTranslationSettings.enabled(accountPeerId: context.account.peerId.toInt64())
}

public func jerkgramTranslationPolicyChanges(context: AccountContext) -> Signal<UInt64, NoError> {
    return Signal { subscriber in
        let accountPeerId = context.account.peerId.toInt64()
        let observer = NotificationCenter.default.addObserver(forName: Notification.Name("JerkgramTranslationPolicyChanged"), object: nil, queue: nil) { notification in
            guard notification.object as? Int64 == accountPeerId else { return }
            subscriber.putNext(JerkgramTranslationSettings.generation(accountPeerId: accountPeerId))
        }
        subscriber.putNext(JerkgramTranslationSettings.generation(accountPeerId: accountPeerId))
        return ActionDisposable { NotificationCenter.default.removeObserver(observer) }
    }
}

// Selection translation uses the same bounded route as chat translation. Real
// Premium remains on the native compose path at the caller.
public func jerkgramTranslateText(context: AccountContext, text: String, entities: [MessageTextEntity] = [], fromLang: String?, toLang: String, localOnly: Bool = false) -> Signal<(String, [MessageTextEntity])?, TelegramCore.TranslationError> {
    // A manual screen can open before any chat has installed the system host.
    // Subscribe on main so host creation is idempotent across all entry points;
    // the engine still owns bounded asynchronous backend work and cancellation.
    return Signal<(String, [MessageTextEntity])?, TelegramCore.TranslationError> { subscriber in
        if #available(iOS 18.0, *) {
            if engineExperimentalInternalTranslationService == nil, let hostView = context.sharedContext.mainWindow?.hostView {
                engineExperimentalInternalTranslationService = ExperimentalInternalTranslationServiceImpl(view: hostView.containerView)
            }
        }
        return context.engine.messages.enhancedTranslate(text: text, entities: entities, fromLang: fromLang, toLang: toLang, allowLocalDownloads: true, localOnly: localOnly).start(next: { result in
            subscriber.putNext(result)
        }, error: { error in
            subscriber.putError(error)
        }, completed: {
            subscriber.putCompletion()
        })
    }
    |> runOn(Queue.mainQueue())
}

func alternativeTranslateText(text: String, fromLang: String?, toLang: String) -> Signal<(String, [MessageTextEntity])?, TelegramCore.TranslationError> {
    return Signal { subscriber in
        var task: URLSessionTask?
        Queue.concurrentDefaultQueue().async {
            let effectiveFromLang: String
            if let fromLang {
                effectiveFromLang = fromLang
            } else {
                let languageRecognizer = NLLanguageRecognizer()
                languageRecognizer.processString(text)
                let hypotheses = languageRecognizer.languageHypotheses(withMaximum: 3)
                languageRecognizer.reset()
                
                let filteredLanguages = hypotheses.filter { supportedTranslationLanguages.contains(normalizeTranslationLanguage($0.key.rawValue)) }.sorted(by: { $0.value > $1.value })
                if let language = filteredLanguages.first {
                    let languageCode = normalizeTranslationLanguage(language.key.rawValue)
                    effectiveFromLang = languageCode
                } else {
                    effectiveFromLang = "en"
                }
            }
            
            var uri = "https://translate.goo"
            uri += "gleapis.com/transl"
            uri += "ate_a"
            uri += "/singl"
            uri += "e?client=gtx&sl=\(effectiveFromLang.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
            uri += "&tl=\(toLang.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
            uri += "&dt=t&ie=UTF-8&oe=UTF-8&otf=1&ssel=0&tsel=0&kc=7&dt=at&dt=bd&dt=ex&dt=ld&dt=md&dt=qca&dt=rw&dt=rm&dt=ss&q="
            uri += text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ""
            
            guard let url = URL(string: uri) else {
                subscriber.putError(.generic)
                return
            }
            
            var request = URLRequest(url: url)
            request.httpMethod = "GET"
            request.setValue(getRandomUserAgent(), forHTTPHeaderField: "User-Agent")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            
            task = URLSession.shared.dataTask(with: request) { data, response, error in
                if let error = error {
                    print("Translation failed: \(error.localizedDescription)")
                    subscriber.putError(.generic)
                    return
                }
                
                guard let httpResponse = response as? HTTPURLResponse else {
                    subscriber.putError(.generic)
                    return
                }
                
                if httpResponse.statusCode != 200 {
                    print("Translation failed with status code: \(httpResponse.statusCode)")
                    let isRateLimit = httpResponse.statusCode == 429
                    subscriber.putError(isRateLimit ? .limitExceeded : .generic)
                    return
                }
                
                guard let data = data else {
                    subscriber.putError(.generic)
                    return
                }
                
                do {
                    guard let jsonArray = try JSONSerialization.jsonObject(with: data) as? [Any] else {
                        subscriber.putError(.generic)
                        return
                    }
                    
                    guard let translationArray = jsonArray.first as? [Any] else {
                        subscriber.putError(.generic)
                        return
                    }
                    
                    var result = ""
                    for element in translationArray {
                        if let translationBlock = element as? [Any],
                           translationBlock.count > 0,
                           let blockText = translationBlock[0] as? String,
                           blockText != "null" && !blockText.isEmpty {
                            result += blockText
                        }
                    }
                    
                    if text.hasPrefix("\n") {
                        result = "\n" + result
                    }
                    
                    subscriber.putNext((result, []))
                    subscriber.putCompletion()
                } catch {
                    print("JSON parsing error: \(error)")
                    subscriber.putError(.generic)
                }
            }
            task?.resume()
        }
        return ActionDisposable {
            task?.cancel()
        }
    }
}

func getRandomUserAgent() -> String {
    let userAgents = [
        "Mozilla/5.0 (iPhone; CPU iPhone OS 18_4_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.4 Mobile/15E148 Safari/604.1"
    ]
    return userAgents.randomElement() ?? userAgents[0]
}
