import Foundation

// MARK: Jerkgram v1.2G BUILD118_CORE_MODELS1
public struct JerkgramEventId: RawRepresentable, Codable, Hashable, Comparable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    public static func < (lhs: JerkgramEventId, rhs: JerkgramEventId) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }

    public static func random() -> JerkgramEventId {
        return JerkgramEventId(rawValue: UUID().uuidString.lowercased())
    }

    public static func migrated(
        accountPeerId: Int64,
        chatPeerId: Int64,
        messageNamespace: Int32?,
        messageId: Int32?,
        kind: JerkgramEventKind,
        observedAtMs: Int64,
        discriminator: String
    ) -> JerkgramEventId {
        let structuralValue = [
            String(accountPeerId),
            String(chatPeerId),
            messageNamespace.map(String.init) ?? "-",
            messageId.map(String.init) ?? "-",
            kind.rawValue,
            String(observedAtMs),
            discriminator,
        ].joined(separator: ":")
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in structuralValue.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
        return JerkgramEventId(rawValue: "m1-" + String(hash, radix: 16))
    }
}

public enum JerkgramEventKind: String, Codable, CaseIterable, Hashable {
    case deletedMessage
    case editedMessage
    case deletedReply
    case recoveredMedia
    case profileSnapshot
    case presence
    case gift
    case personalChannel
}

public struct JerkgramEventPayload: Codable, Equatable {
    public var text: String?
    public var previousText: String?
    public var mediaKind: String?
    public var mediaRelativePath: String?
    public var mediaByteCount: Int64?
    public var metadata: [String: String]

    public init(
        text: String? = nil,
        previousText: String? = nil,
        mediaKind: String? = nil,
        mediaRelativePath: String? = nil,
        mediaByteCount: Int64? = nil,
        metadata: [String: String] = [:]
    ) {
        self.text = text
        self.previousText = previousText
        self.mediaKind = mediaKind
        self.mediaRelativePath = mediaRelativePath
        self.mediaByteCount = mediaByteCount
        self.metadata = metadata
    }
}

public struct JerkgramCanonicalEvent: Codable, Equatable {
    public let schemaVersion: Int
    public let accountPeerId: Int64
    public let chatPeerId: Int64
    public let eventId: JerkgramEventId
    public let sequence: Int64
    public let kind: JerkgramEventKind
    public let senderPeerId: Int64?
    public let messageNamespace: Int32?
    public let messageId: Int32?
    public let observedAtMs: Int64
    public let payload: JerkgramEventPayload

    public init(
        accountPeerId: Int64,
        chatPeerId: Int64,
        eventId: JerkgramEventId,
        sequence: Int64,
        kind: JerkgramEventKind,
        senderPeerId: Int64?,
        messageNamespace: Int32?,
        messageId: Int32?,
        observedAtMs: Int64,
        payload: JerkgramEventPayload
    ) {
        self.schemaVersion = 1
        self.accountPeerId = accountPeerId
        self.chatPeerId = chatPeerId
        self.eventId = eventId
        self.sequence = sequence
        self.kind = kind
        self.senderPeerId = senderPeerId
        self.messageNamespace = messageNamespace
        self.messageId = messageId
        self.observedAtMs = observedAtMs
        self.payload = payload
    }
}

public enum JerkgramCoreError: Error, Equatable {
    case unsupportedSchemaVersion(Int)
    case duplicateEvent(JerkgramEventId)
    case conflictingEvent(JerkgramEventId)
    case invalidRelativePath(String)
    case accountScopeMismatch(expected: Int64, actual: Int64)
    case incompleteRead(expected: Int, actual: Int)
    case invalidIndexRange
    case indexNotReady(Int64)
}
