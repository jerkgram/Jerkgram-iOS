import Foundation

// MARK: Jerkgram v1.2G BUILD118_TIME_MACHINE_INDEX1
public enum JerkgramTimeMachineFilter: String, Codable, CaseIterable {
    case deleted
    case edited
    case recoveredMedia
}

public struct JerkgramTimeMachineQuery: Equatable {
    public let accountPeerId: Int64
    public let chatPeerId: Int64
    public let kinds: Set<JerkgramEventKind>
    public let senderPeerId: Int64?
    public let eventIds: Set<JerkgramEventId>?

    public init(
        accountPeerId: Int64,
        chatPeerId: Int64,
        kinds: Set<JerkgramEventKind> = [],
        senderPeerId: Int64? = nil,
        eventIds: Set<JerkgramEventId>? = nil
    ) {
        self.accountPeerId = accountPeerId
        self.chatPeerId = chatPeerId
        self.kinds = kinds
        self.senderPeerId = senderPeerId
        self.eventIds = eventIds
    }
}

public struct JerkgramTimeMachineResult: Equatable {
    public let eventId: JerkgramEventId
    public let sequence: Int64
    public let kind: JerkgramEventKind
    public let senderPeerId: Int64?
    public let observedAtMs: Int64
    public let locator: JerkgramCanonicalLocator
}

public final class JerkgramTimeMachineIndex {
    private let records: [JerkgramTimeMachineIndexRecord]

    public init(records: [JerkgramTimeMachineIndexRecord]) {
        // Identity is (accountPeerId, eventId). Equal text is intentionally
        // irrelevant and therefore never used as a deduplication key.
        var identities = Set<String>()
        self.records = records.filter { record in
            identities.insert("\(record.accountPeerId):\(record.eventId.rawValue)").inserted
        }
    }

    public func query(_ query: JerkgramTimeMachineQuery) -> [JerkgramTimeMachineResult] {
        return self.records.lazy.filter { record in
            guard record.accountPeerId == query.accountPeerId,
                  record.chatPeerId == query.chatPeerId else {
                return false
            }
            if !query.kinds.isEmpty && !query.kinds.contains(record.kind) { return false }
            if let senderPeerId = query.senderPeerId, record.senderPeerId != senderPeerId { return false }
            if let eventIds = query.eventIds, !eventIds.contains(record.eventId) { return false }
            return true
        }.sorted { lhs, rhs in
            if lhs.sequence != rhs.sequence { return lhs.sequence > rhs.sequence }
            return lhs.eventId > rhs.eventId
        }.map { record in
            JerkgramTimeMachineResult(
                eventId: record.eventId,
                sequence: record.sequence,
                kind: record.kind,
                senderPeerId: record.senderPeerId,
                observedAtMs: record.observedAtMs,
                locator: record.locator
            )
        }
    }
}

public struct JerkgramChangesSinceLastOpening: Equatable {
    public let upperSequence: Int64
    public let deletedCount: Int
    public let editedCount: Int
    public let recoveredMediaCount: Int
    public let eventIds: [JerkgramEventId]
}

public final class JerkgramVisitWatermarkStore {
    private let rootURL: URL
    private let lock = NSLock()

    public init(rootURL: URL) {
        self.rootURL = rootURL
    }

    public func previousSequence(accountPeerId: Int64, chatPeerId: Int64) -> Int64? {
        self.lock.lock()
        defer { self.lock.unlock() }
        return (try? String(
            contentsOf: self.url(accountPeerId: accountPeerId, chatPeerId: chatPeerId),
            encoding: .utf8
        )).flatMap(Int64.init)
    }

    public func snapshotChangesSinceLastOpening(
        accountPeerId: Int64,
        chatPeerId: Int64,
        records: [JerkgramTimeMachineIndexRecord]
    ) throws -> JerkgramChangesSinceLastOpening {
        self.lock.lock()
        defer { self.lock.unlock() }
        let url = self.url(accountPeerId: accountPeerId, chatPeerId: chatPeerId)
        let previousValue = (try? String(contentsOf: url, encoding: .utf8)).flatMap(Int64.init)
        let previous = previousValue ?? 0
        let matching = records.filter {
            $0.accountPeerId == accountPeerId &&
            $0.chatPeerId == chatPeerId &&
            $0.sequence > previous
        }
        let upperSequence = matching.map(\.sequence).max() ?? previous
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try String(upperSequence).data(using: .utf8)?.write(to: url, options: .atomic)
        if previousValue == nil {
            return JerkgramChangesSinceLastOpening(
                upperSequence: upperSequence,
                deletedCount: 0,
                editedCount: 0,
                recoveredMediaCount: 0,
                eventIds: []
            )
        }
        return JerkgramChangesSinceLastOpening(
            upperSequence: upperSequence,
            deletedCount: matching.filter { $0.kind == .deletedMessage || $0.kind == .deletedReply }.count,
            editedCount: matching.filter { $0.kind == .editedMessage }.count,
            recoveredMediaCount: matching.filter { $0.kind == .recoveredMedia }.count,
            eventIds: matching.sorted { $0.sequence < $1.sequence }.map(\.eventId)
        )
    }

    public func snapshotChangesSinceLastOpening(
        accountPeerId: Int64,
        chatPeerId: Int64,
        events: [JerkgramCanonicalEvent]
    ) throws -> JerkgramChangesSinceLastOpening {
        let records = events.compactMap { event -> JerkgramTimeMachineIndexRecord? in
            guard event.accountPeerId == accountPeerId, event.chatPeerId == chatPeerId,
                  let locator = try? JerkgramCanonicalLocator(
                    kind: event.kind,
                    relativeFile: "accounts/\(accountPeerId)/events.jsonl",
                    eventId: event.eventId
                  ) else { return nil }
            return JerkgramTimeMachineIndexRecord(
                accountPeerId: event.accountPeerId,
                chatPeerId: event.chatPeerId,
                eventId: event.eventId,
                sequence: event.sequence,
                kind: event.kind,
                senderPeerId: event.senderPeerId,
                observedAtMs: event.observedAtMs,
                locator: locator
            )
        }
        return try self.snapshotChangesSinceLastOpening(
            accountPeerId: accountPeerId,
            chatPeerId: chatPeerId,
            records: records
        )
    }

    private func url(accountPeerId: Int64, chatPeerId: Int64) -> URL {
        // Visit watermarks are local UI state and intentionally live outside
        // Archive v2 account payloads.
        return self.rootURL.appendingPathComponent("visit-watermarks", isDirectory: true)
            .appendingPathComponent(String(accountPeerId), isDirectory: true)
            .appendingPathComponent("\(chatPeerId).txt", isDirectory: false)
    }
}
