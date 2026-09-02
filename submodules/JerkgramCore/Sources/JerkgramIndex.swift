import Foundation

// MARK: Jerkgram v1.2G BUILD118_REFERENCE_INDEX1
public struct JerkgramCanonicalLocator: Codable, Equatable {
    public let kind: JerkgramEventKind
    public let relativeFile: String
    public let eventId: JerkgramEventId

    public init(kind: JerkgramEventKind, relativeFile: String, eventId: JerkgramEventId) throws {
        guard !relativeFile.hasPrefix("/"), !relativeFile.split(separator: "/").contains("..") else {
            throw JerkgramCoreError.invalidRelativePath(relativeFile)
        }
        self.kind = kind
        self.relativeFile = relativeFile
        self.eventId = eventId
    }
}

public struct JerkgramTimeMachineIndexRecord: Codable, Equatable {
    public let accountPeerId: Int64
    public let chatPeerId: Int64
    public let eventId: JerkgramEventId
    public let sequence: Int64
    public let kind: JerkgramEventKind
    public let senderPeerId: Int64?
    public let observedAtMs: Int64
    public let byteOffset: UInt64
    public let byteLength: UInt64
    public let messageNamespace: Int32?
    public let messageId: Int32?
    public let locator: JerkgramCanonicalLocator

    public init(
        accountPeerId: Int64,
        chatPeerId: Int64,
        eventId: JerkgramEventId,
        sequence: Int64,
        kind: JerkgramEventKind,
        senderPeerId: Int64?,
        observedAtMs: Int64,
        byteOffset: UInt64 = 0,
        byteLength: UInt64 = 0,
        messageNamespace: Int32? = nil,
        messageId: Int32? = nil,
        locator: JerkgramCanonicalLocator
    ) {
        self.accountPeerId = accountPeerId
        self.chatPeerId = chatPeerId
        self.eventId = eventId
        self.sequence = sequence
        self.kind = kind
        self.senderPeerId = senderPeerId
        self.observedAtMs = observedAtMs
        self.byteOffset = byteOffset
        self.byteLength = byteLength
        self.messageNamespace = messageNamespace
        self.messageId = messageId
        self.locator = locator
    }
}
