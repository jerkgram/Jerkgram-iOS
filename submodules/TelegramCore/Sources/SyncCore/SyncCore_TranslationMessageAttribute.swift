import Foundation
import Postbox

public class TranslationMessageAttribute: MessageAttribute, Equatable {
    public struct Additional : PostboxCoding, Equatable {
        public let text: String
        public let entities: [MessageTextEntity]
        
        public init(text: String, entities: [MessageTextEntity]) {
            self.text = text
            self.entities = entities
        }
        
        public init(decoder: PostboxDecoder) {
            self.text = decoder.decodeStringForKey("text", orElse: "")
            self.entities = decoder.decodeObjectArrayWithDecoderForKey("entities")
        }
        
        public func encode(_ encoder: PostboxEncoder) {
            encoder.encodeString(self.text, forKey: "text")
            encoder.encodeObjectArray(self.entities, forKey: "entities")
        } 
    }
    
    public let text: String
    public let entities: [MessageTextEntity]
    public let toLang: String
    public let jerkgramPolicyVersion: Int32
    public let jerkgramUnavailable: Bool
    public let jerkgramSourceFingerprint: String?
    private let jerkgramSourceLock = NSLock()
    private weak var jerkgramCachedMessage: Message?
    private var jerkgramCachedValidity = false

    // One weak immutable-message cache avoids hashing on every bubble layout.
    public func isValidForMessage(_ message: Message, accountPeerId: Int64? = nil) -> Bool {
        guard let fingerprint = self.jerkgramSourceFingerprint else { return self.jerkgramPolicyVersion == 0 }
        // Policy must be checked on every read, before the immutable-message cache.
        guard let accountPeerId, JerkgramTranslationSettings.enabled(accountPeerId: accountPeerId), self.jerkgramPolicyVersion == JerkgramTranslationSettings.policyVersion else { return false }
        self.jerkgramSourceLock.lock()
        if self.jerkgramCachedMessage === message {
            let value = self.jerkgramCachedValidity
            self.jerkgramSourceLock.unlock()
            return value
        }
        self.jerkgramSourceLock.unlock()
        let value = fingerprint == jerkgramTranslationSourceFingerprint(message)
        self.jerkgramSourceLock.lock()
        self.jerkgramCachedMessage = message
        self.jerkgramCachedValidity = value
        self.jerkgramSourceLock.unlock()
        return value
    }

    public let additional: [Additional]
    public let pollSolution: Additional?
    /// The translated rich content, for messages carrying a `RichTextMessageAttribute` (translated via
    /// `messages.translateRichMessage`). `text`/`entities` stay empty for those.
    public let instantPage: InstantPage?

    public var associatedPeerIds: [PeerId] {
        return []
    }

    public init(
        text: String,
        entities: [MessageTextEntity],
        additional:[Additional] = [],
        pollSolution: Additional? = nil,
        toLang: String,
        instantPage: InstantPage? = nil,
        jerkgramSourceFingerprint: String? = nil,
        jerkgramUnavailable: Bool = false,
        jerkgramPolicyVersion: Int32 = 0
    ) {
        self.text = text
        self.entities = entities
        self.toLang = toLang
        self.jerkgramSourceFingerprint = jerkgramSourceFingerprint
        self.jerkgramPolicyVersion = jerkgramPolicyVersion
        self.jerkgramUnavailable = jerkgramUnavailable
        self.additional = additional
        self.pollSolution = pollSolution
        self.instantPage = instantPage
    }

    required public init(decoder: PostboxDecoder) {
        self.text = decoder.decodeStringForKey("text", orElse: "")
        self.entities = decoder.decodeObjectArrayWithDecoderForKey("entities")
        self.additional = decoder.decodeObjectArrayWithDecoderForKey("additional")
        self.toLang = decoder.decodeStringForKey("toLang", orElse: "")
        self.jerkgramSourceFingerprint = decoder.decodeOptionalStringForKey("jg174source")
        self.jerkgramPolicyVersion = decoder.decodeInt32ForKey("jgPolicy", orElse: 0)
        self.jerkgramUnavailable = decoder.decodeBoolForKey("jg174unavailable", orElse: false)
        self.pollSolution = decoder.decodeObjectForKey("pollSolution") as? Additional
        self.instantPage = decoder.decodeObjectForKey("ipage", decoder: { InstantPage(decoder: $0) }) as? InstantPage
    }

    public func encode(_ encoder: PostboxEncoder) {
        encoder.encodeString(self.text, forKey: "text")
        encoder.encodeObjectArray(self.entities, forKey: "entities")
        encoder.encodeString(self.toLang, forKey: "toLang")
        encoder.encodeInt32(self.jerkgramPolicyVersion, forKey: "jgPolicy")
        encoder.encodeBool(self.jerkgramUnavailable, forKey: "jg174unavailable")
        if let fingerprint = self.jerkgramSourceFingerprint { encoder.encodeString(fingerprint, forKey: "jg174source") }
        else { encoder.encodeNil(forKey: "jg174source") }
        encoder.encodeObjectArray(self.additional, forKey: "additional")

        if let pollSolution {
            encoder.encodeObject(pollSolution, forKey: "pollSolution")
        } else {
            encoder.encodeNil(forKey: "pollSolution")
        }
        if let instantPage {
            encoder.encodeObject(instantPage, forKey: "ipage")
        } else {
            encoder.encodeNil(forKey: "ipage")
        }
    }

    public static func ==(lhs: TranslationMessageAttribute, rhs: TranslationMessageAttribute) -> Bool {
        if lhs.jerkgramPolicyVersion != rhs.jerkgramPolicyVersion { return false }
        if lhs.jerkgramUnavailable != rhs.jerkgramUnavailable { return false }
        if lhs.jerkgramSourceFingerprint != rhs.jerkgramSourceFingerprint { return false }
        if lhs.text != rhs.text {
            return false
        }
        if lhs.entities != rhs.entities {
            return false
        }
        if lhs.toLang != rhs.toLang {
            return false
        }
        if lhs.additional != rhs.additional {
            return false
        }
        if lhs.pollSolution != rhs.pollSolution {
            return false
        }
        if lhs.instantPage != rhs.instantPage {
            return false
        }
        return true
    }
}
