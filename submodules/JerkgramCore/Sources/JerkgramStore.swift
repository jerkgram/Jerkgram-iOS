import Foundation

// MARK: Jerkgram v1.2G BUILD118_EVENT_STORE1
public protocol JerkgramEventStore {
    func append(_ event: JerkgramCanonicalEvent) throws
    func events(accountPeerId: Int64, chatPeerId: Int64?) throws -> [JerkgramCanonicalEvent]
    func replaceAtomically(accountPeerId: Int64, events: [JerkgramCanonicalEvent]) throws
}

public final class JerkgramJSONLEventStore: JerkgramEventStore {
    private struct AccountIndexState {
        var records: [JerkgramTimeMachineIndexRecord]
        var recordsByEventId: [JerkgramEventId: JerkgramTimeMachineIndexRecord]
        var recordsByChat: [Int64: [JerkgramTimeMachineIndexRecord]]
        var canonicalLength: UInt64
    }

    private static let sharedLock = NSLock()
    private static var sharedIndexStates: [String: AccountIndexState] = [:]
    private let rootURL: URL
    private let decoder = JSONDecoder()
    private let encoder: JSONEncoder

    public init(rootURL: URL) {
        self.rootURL = rootURL
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        self.encoder = encoder
    }

    public func append(_ event: JerkgramCanonicalEvent) throws {
        try self.appendBatch([event])
    }

    public func appendBatch(_ events: [JerkgramCanonicalEvent]) throws {
        try self.appendBatch(events, allowExistingIdentical: false)
    }

    public func appendBatchRecovering(_ events: [JerkgramCanonicalEvent]) throws {
        try self.appendBatch(events, allowExistingIdentical: true)
    }

    private func appendBatch(
        _ events: [JerkgramCanonicalEvent],
        allowExistingIdentical: Bool
    ) throws {
        guard !events.isEmpty else { return }
        Self.sharedLock.lock()
        defer { Self.sharedLock.unlock() }

        var accountOrder: [Int64] = []
        var grouped: [Int64: [JerkgramCanonicalEvent]] = [:]
        for event in events {
            if grouped[event.accountPeerId] == nil {
                accountOrder.append(event.accountPeerId)
            }
            grouped[event.accountPeerId, default: []].append(event)
        }
        for accountPeerId in accountOrder {
            guard let accountEvents = grouped[accountPeerId] else { continue }
            try self.appendLocked(
                accountPeerId: accountPeerId,
                events: accountEvents,
                allowExistingIdentical: allowExistingIdentical
            )
        }
    }

    public func indexRecords(
        accountPeerId: Int64,
        chatPeerId: Int64,
        afterSequence: Int64? = nil,
        throughSequence: Int64? = nil
    ) throws -> [JerkgramTimeMachineIndexRecord] {
        Self.sharedLock.lock()
        defer { Self.sharedLock.unlock() }
        let state = try self.ensureIndexLocked(accountPeerId)
        return self.filteredRecords(
            state.records,
            chatPeerId: chatPeerId,
            afterSequence: afterSequence,
            throughSequence: throughSequence
        )
    }

    public func readyIndexRecords(
        accountPeerId: Int64,
        chatPeerId: Int64,
        afterSequence: Int64? = nil,
        throughSequence: Int64? = nil
    ) throws -> [JerkgramTimeMachineIndexRecord] {
        Self.sharedLock.lock()
        defer { Self.sharedLock.unlock() }
        guard let state = try self.readyIndexLocked(accountPeerId) else {
            throw JerkgramCoreError.indexNotReady(accountPeerId)
        }
        return self.filteredRecords(
            state.records,
            chatPeerId: chatPeerId,
            afterSequence: afterSequence,
            throughSequence: throughSequence
        )
    }

    private func filteredRecords(
        _ records: [JerkgramTimeMachineIndexRecord],
        chatPeerId: Int64,
        afterSequence: Int64?,
        throughSequence: Int64?
    ) -> [JerkgramTimeMachineIndexRecord] {
        return records.lazy.filter { record in
            guard record.chatPeerId == chatPeerId else { return false }
            if let afterSequence, record.sequence <= afterSequence { return false }
            if let throughSequence, record.sequence > throughSequence { return false }
            return true
        }.sorted { lhs, rhs in
            if lhs.sequence != rhs.sequence { return lhs.sequence < rhs.sequence }
            return lhs.eventId < rhs.eventId
        }
    }

    public func events(accountPeerId: Int64, chatPeerId: Int64?) throws -> [JerkgramCanonicalEvent] {
        Self.sharedLock.lock()
        defer { Self.sharedLock.unlock() }
        if let chatPeerId {
            let state = try self.ensureIndexLocked(accountPeerId)
            let handle = try FileHandle(forReadingFrom: self.accountURL(accountPeerId))
            defer { try? handle.close() }
            return try state.records.lazy.filter { $0.chatPeerId == chatPeerId }.map {
                try self.readEvent(handle: handle, record: $0)
            }.sorted { lhs, rhs in
                if lhs.sequence != rhs.sequence { return lhs.sequence < rhs.sequence }
                return lhs.eventId < rhs.eventId
            }
        }
        return try self.loadAccount(accountPeerId).sorted { lhs, rhs in
            if lhs.sequence != rhs.sequence { return lhs.sequence < rhs.sequence }
            return lhs.eventId < rhs.eventId
        }
    }

    public func eventPage(
        accountPeerId: Int64,
        chatPeerId: Int64,
        beforeSequence: Int64? = nil,
        beforeEventId: JerkgramEventId? = nil,
        limit: Int = 250
    ) throws -> [JerkgramCanonicalEvent] {
        Self.sharedLock.lock()
        defer { Self.sharedLock.unlock() }
        guard limit > 0 else { return [] }
        let state = try self.ensureIndexLocked(accountPeerId)
        let chatRecords = state.recordsByChat[chatPeerId] ?? []
        let upperBound = self.pageUpperBound(
            records: chatRecords,
            beforeSequence: beforeSequence,
            beforeEventId: beforeEventId
        )
        let lowerBound = max(0, upperBound - limit)
        let records = chatRecords[lowerBound..<upperBound].reversed()
        guard !records.isEmpty else { return [] }
        let handle = try FileHandle(forReadingFrom: self.accountURL(accountPeerId))
        defer { try? handle.close() }
        return try records.map { try self.readEvent(handle: handle, record: $0) }
    }

    public func replaceAtomically(accountPeerId: Int64, events: [JerkgramCanonicalEvent]) throws {
        Self.sharedLock.lock()
        defer { Self.sharedLock.unlock() }
        precondition(events.allSatisfy { $0.accountPeerId == accountPeerId })
        var identities = Set<JerkgramEventId>()
        for event in events {
            guard identities.insert(event.eventId).inserted else {
                throw JerkgramCoreError.duplicateEvent(event.eventId)
            }
        }
        let ordered = events.sorted { lhs, rhs in
            if lhs.sequence != rhs.sequence { return lhs.sequence < rhs.sequence }
            return lhs.eventId < rhs.eventId
        }
        let data = try self.canonicalData(events: ordered)
        let url = self.accountURL(accountPeerId)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        // The index is disposable. Invalidate it before replacing canonical
        // data so a crash can never pair new JSONL bytes with old metadata.
        Self.sharedIndexStates.removeValue(forKey: self.stateKey(accountPeerId))
        try? FileManager.default.removeItem(at: self.indexURL(accountPeerId))
        try data.write(to: url, options: .atomic)
        let state = try self.buildIndexState(accountPeerId: accountPeerId, canonicalData: data)
        try self.publishIndexLocked(accountPeerId: accountPeerId, records: state.records)
        Self.sharedIndexStates[self.stateKey(accountPeerId)] = state
    }

    private func appendLocked(
        accountPeerId: Int64,
        events: [JerkgramCanonicalEvent],
        allowExistingIdentical: Bool
    ) throws {
        let readyState = try self.readyIndexLocked(accountPeerId)
        var state: AccountIndexState
        let maintainsIndex: Bool
        if let readyState {
            state = readyState
            maintainsIndex = true
        } else if allowExistingIdentical {
            state = AccountIndexState(
                records: [],
                recordsByEventId: [:],
                recordsByChat: [:],
                canonicalLength: try self.completeCanonicalLength(accountPeerId: accountPeerId)
            )
            maintainsIndex = false
            Self.sharedIndexStates.removeValue(forKey: self.stateKey(accountPeerId))
            try? FileManager.default.removeItem(at: self.indexURL(accountPeerId))
        } else {
            state = try self.ensureIndexLocked(accountPeerId)
            maintainsIndex = true
        }
        var pendingIds = Set<JerkgramEventId>()
        var newEvents: [JerkgramCanonicalEvent] = []
        for event in events {
            precondition(event.accountPeerId == accountPeerId)
            guard pendingIds.insert(event.eventId).inserted else {
                throw JerkgramCoreError.duplicateEvent(event.eventId)
            }
            if let existingRecord = state.recordsByEventId[event.eventId] {
                let existing = try self.readEvent(accountPeerId: accountPeerId, record: existingRecord)
                if existing == event {
                    if allowExistingIdentical { continue }
                    throw JerkgramCoreError.duplicateEvent(event.eventId)
                } else {
                    throw JerkgramCoreError.conflictingEvent(event.eventId)
                }
            }
            newEvents.append(event)
        }
        guard !newEvents.isEmpty else { return }

        let canonicalURL = self.accountURL(accountPeerId)
        try FileManager.default.createDirectory(
            at: canonicalURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if !FileManager.default.fileExists(atPath: canonicalURL.path) {
            _ = FileManager.default.createFile(atPath: canonicalURL.path, contents: nil)
        }
        let existingLength = self.fileSize(canonicalURL)
        if state.canonicalLength < existingLength {
            // A crash can leave one incomplete final JSONL line. Preserve all
            // complete records and discard only that uncommitted tail before
            // appending the next complete batch.
            do {
                let repairHandle = try FileHandle(forWritingTo: canonicalURL)
                defer { try? repairHandle.close() }
                try repairHandle.truncate(atOffset: state.canonicalLength)
            }
        }

        var canonicalAppend = Data()
        var newRecords: [JerkgramTimeMachineIndexRecord] = []
        var nextOffset = state.canonicalLength
        for event in newEvents {
            var line = try self.encoder.encode(event)
            line.append(0x0a)
            let record = try self.indexRecord(
                event: event,
                byteOffset: nextOffset,
                byteLength: UInt64(line.count)
            )
            canonicalAppend.append(line)
            newRecords.append(record)
            nextOffset += UInt64(line.count)
        }

        do {
            let canonicalHandle = try FileHandle(forWritingTo: canonicalURL)
            defer { try? canonicalHandle.close() }
            if #available(iOS 13.4, *) {
                _ = try canonicalHandle.seekToEnd()
                try canonicalHandle.write(contentsOf: canonicalAppend)
            } else {
                canonicalHandle.seekToEndOfFile()
                canonicalHandle.write(canonicalAppend)
            }
        } catch {
            if let rollbackHandle = try? FileHandle(forWritingTo: canonicalURL) {
                try? rollbackHandle.truncate(atOffset: state.canonicalLength)
                try? rollbackHandle.close()
            }
            throw error
        }

        guard maintainsIndex else { return }

        do {
            try self.appendIndexLocked(accountPeerId: accountPeerId, records: newRecords)
            state.records.append(contentsOf: newRecords)
            for record in newRecords {
                state.recordsByEventId[record.eventId] = record
            }
            for (chatPeerId, unsortedAdditions) in Dictionary(
                grouping: newRecords,
                by: { $0.chatPeerId }
            ) {
                let additions = unsortedAdditions.sorted { self.recordComesEarlier($0, $1) }
                if let first = additions.first,
                   let last = state.recordsByChat[chatPeerId]?.last,
                   self.recordComesEarlier(first, last) {
                    state.recordsByChat[chatPeerId] = self.mergeAscending(
                        state.recordsByChat[chatPeerId] ?? [],
                        additions
                    )
                } else {
                    state.recordsByChat[chatPeerId, default: []].append(contentsOf: additions)
                }
            }
            state.canonicalLength = nextOffset
            Self.sharedIndexStates[self.stateKey(accountPeerId)] = state
        } catch {
            Self.sharedIndexStates.removeValue(forKey: self.stateKey(accountPeerId))
            try? FileManager.default.removeItem(at: self.indexURL(accountPeerId))
            if !allowExistingIdentical { throw error }
        }
    }

    private func ensureIndexLocked(_ accountPeerId: Int64) throws -> AccountIndexState {
        let canonicalURL = self.accountURL(accountPeerId)
        let canonicalLength = self.fileSize(canonicalURL)
        let key = self.stateKey(accountPeerId)
        if let state = Self.sharedIndexStates[key], state.canonicalLength == canonicalLength {
            return state
        }
        Self.sharedIndexStates.removeValue(forKey: key)
        if let state = try self.readyIndexLocked(accountPeerId) {
            return state
        }

        let data = FileManager.default.fileExists(atPath: canonicalURL.path)
            ? try Data(contentsOf: canonicalURL, options: .mappedIfSafe)
            : Data()
        let state = try self.buildIndexState(accountPeerId: accountPeerId, canonicalData: data)
        try self.publishIndexLocked(accountPeerId: accountPeerId, records: state.records)
        Self.sharedIndexStates[key] = state
        return state
    }

    private func readyIndexLocked(_ accountPeerId: Int64) throws -> AccountIndexState? {
        let canonicalLength = self.fileSize(self.accountURL(accountPeerId))
        let key = self.stateKey(accountPeerId)
        if let state = Self.sharedIndexStates[key], state.canonicalLength == canonicalLength {
            return state
        }
        Self.sharedIndexStates.removeValue(forKey: key)
        guard let records = try? self.loadIndex(accountPeerId: accountPeerId),
           self.isCompleteIndex(records, canonicalLength: canonicalLength),
           records.allSatisfy({ $0.accountPeerId == accountPeerId }),
           Set(records.map(\.eventId)).count == records.count else {
            return nil
        }
        let state = AccountIndexState(
            records: records,
            recordsByEventId: Dictionary(uniqueKeysWithValues: records.map { ($0.eventId, $0) }),
            recordsByChat: self.groupedRecordsByChat(records),
            canonicalLength: canonicalLength
        )
        Self.sharedIndexStates[key] = state
        return state
    }

    private func buildIndexState(accountPeerId: Int64, canonicalData: Data) throws -> AccountIndexState {
        var records: [JerkgramTimeMachineIndexRecord] = []
        var identities: [JerkgramEventId: JerkgramTimeMachineIndexRecord] = [:]
        var completeLength: UInt64 = 0
        for range in self.completeLineRanges(canonicalData) {
            let line = canonicalData.subdata(in: range)
            let event = try self.decoder.decode(JerkgramCanonicalEvent.self, from: line)
            guard event.schemaVersion == 1 else {
                throw JerkgramCoreError.unsupportedSchemaVersion(event.schemaVersion)
            }
            guard event.accountPeerId == accountPeerId else {
                throw JerkgramCoreError.accountScopeMismatch(
                    expected: accountPeerId,
                    actual: event.accountPeerId
                )
            }
            let record = try self.indexRecord(
                event: event,
                byteOffset: UInt64(range.lowerBound),
                byteLength: UInt64(range.count)
            )
            if identities[event.eventId] != nil {
                throw JerkgramCoreError.duplicateEvent(event.eventId)
            }
            records.append(record)
            identities[event.eventId] = record
            completeLength = UInt64(range.upperBound)
        }
        return AccountIndexState(
            records: records,
            recordsByEventId: identities,
            recordsByChat: self.groupedRecordsByChat(records),
            canonicalLength: completeLength
        )
    }

    private func groupedRecordsByChat(
        _ records: [JerkgramTimeMachineIndexRecord]
    ) -> [Int64: [JerkgramTimeMachineIndexRecord]] {
        var result: [Int64: [JerkgramTimeMachineIndexRecord]] = [:]
        for record in records {
            result[record.chatPeerId, default: []].append(record)
        }
        for chatPeerId in Array(result.keys) {
            result[chatPeerId]?.sort { self.recordComesEarlier($0, $1) }
        }
        return result
    }

    private func mergeAscending(
        _ lhs: [JerkgramTimeMachineIndexRecord],
        _ rhs: [JerkgramTimeMachineIndexRecord]
    ) -> [JerkgramTimeMachineIndexRecord] {
        var result: [JerkgramTimeMachineIndexRecord] = []
        result.reserveCapacity(lhs.count + rhs.count)
        var lhsIndex = 0
        var rhsIndex = 0
        while lhsIndex < lhs.count && rhsIndex < rhs.count {
            if self.recordComesEarlier(rhs[rhsIndex], lhs[lhsIndex]) {
                result.append(rhs[rhsIndex])
                rhsIndex += 1
            } else {
                result.append(lhs[lhsIndex])
                lhsIndex += 1
            }
        }
        if lhsIndex < lhs.count { result.append(contentsOf: lhs[lhsIndex...]) }
        if rhsIndex < rhs.count { result.append(contentsOf: rhs[rhsIndex...]) }
        return result
    }

    private func pageUpperBound(
        records: [JerkgramTimeMachineIndexRecord],
        beforeSequence: Int64?,
        beforeEventId: JerkgramEventId?
    ) -> Int {
        guard let beforeSequence else { return records.count }
        var lowerBound = 0
        var upperBound = records.count
        while lowerBound < upperBound {
            let middle = lowerBound + (upperBound - lowerBound) / 2
            let record = records[middle]
            let isBefore: Bool
            if record.sequence != beforeSequence {
                isBefore = record.sequence < beforeSequence
            } else if let beforeEventId {
                isBefore = record.eventId < beforeEventId
            } else {
                isBefore = false
            }
            if isBefore {
                lowerBound = middle + 1
            } else {
                upperBound = middle
            }
        }
        return lowerBound
    }

    private func recordComesEarlier(
        _ lhs: JerkgramTimeMachineIndexRecord,
        _ rhs: JerkgramTimeMachineIndexRecord
    ) -> Bool {
        if lhs.sequence != rhs.sequence { return lhs.sequence < rhs.sequence }
        return lhs.eventId < rhs.eventId
    }

    private func completeLineRanges(_ data: Data) -> [Range<Data.Index>] {
        var result: [Range<Data.Index>] = []
        var lineStart = data.startIndex
        var index = data.startIndex
        while index < data.endIndex {
            if data[index] == 0x0a {
                let next = data.index(after: index)
                if lineStart < index {
                    result.append(lineStart..<next)
                }
                lineStart = next
            }
            index = data.index(after: index)
        }
        return result
    }

    private func indexRecord(
        event: JerkgramCanonicalEvent,
        byteOffset: UInt64,
        byteLength: UInt64
    ) throws -> JerkgramTimeMachineIndexRecord {
        return JerkgramTimeMachineIndexRecord(
            accountPeerId: event.accountPeerId,
            chatPeerId: event.chatPeerId,
            eventId: event.eventId,
            sequence: event.sequence,
            kind: event.kind,
            senderPeerId: event.senderPeerId,
            observedAtMs: event.observedAtMs,
            byteOffset: byteOffset,
            byteLength: byteLength,
            messageNamespace: event.messageNamespace,
            messageId: event.messageId,
            locator: try JerkgramCanonicalLocator(
                kind: event.kind,
                relativeFile: "accounts/\(event.accountPeerId)/events.jsonl",
                eventId: event.eventId
            )
        )
    }

    private func readEvent(
        accountPeerId: Int64,
        record: JerkgramTimeMachineIndexRecord
    ) throws -> JerkgramCanonicalEvent {
        let handle = try FileHandle(forReadingFrom: self.accountURL(accountPeerId))
        defer { try? handle.close() }
        return try self.readEvent(handle: handle, record: record)
    }

    private func readEvent(
        handle: FileHandle,
        record: JerkgramTimeMachineIndexRecord
    ) throws -> JerkgramCanonicalEvent {
        guard record.byteLength <= UInt64(Int.max) else {
            throw JerkgramCoreError.invalidIndexRange
        }
        try handle.seek(toOffset: record.byteOffset)
        let data: Data
        if #available(iOS 13.4, *) {
            data = try handle.read(upToCount: Int(record.byteLength)) ?? Data()
        } else {
            data = handle.readData(ofLength: Int(record.byteLength))
        }
        guard data.count == Int(record.byteLength) else {
            throw JerkgramCoreError.incompleteRead(
                expected: Int(record.byteLength),
                actual: data.count
            )
        }
        let event = try self.decoder.decode(JerkgramCanonicalEvent.self, from: data)
        guard event.schemaVersion == 1 else {
            throw JerkgramCoreError.unsupportedSchemaVersion(event.schemaVersion)
        }
        return event
    }

    private func loadAccount(_ accountPeerId: Int64) throws -> [JerkgramCanonicalEvent] {
        let url = self.accountURL(accountPeerId)
        guard FileManager.default.fileExists(atPath: url.path) else { return [] }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        return try self.completeLineRanges(data).map { range in
            let event = try self.decoder.decode(JerkgramCanonicalEvent.self, from: data.subdata(in: range))
            guard event.schemaVersion == 1 else {
                throw JerkgramCoreError.unsupportedSchemaVersion(event.schemaVersion)
            }
            return event
        }
    }

    private func loadIndex(accountPeerId: Int64) throws -> [JerkgramTimeMachineIndexRecord] {
        let url = self.indexURL(accountPeerId)
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        return try self.completeLineRanges(data).map { range in
            try self.decoder.decode(JerkgramTimeMachineIndexRecord.self, from: data.subdata(in: range))
        }
    }

    private func appendIndexLocked(accountPeerId: Int64, records: [JerkgramTimeMachineIndexRecord]) throws {
        let url = self.indexURL(accountPeerId)
        if !FileManager.default.fileExists(atPath: url.path) {
            _ = FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        var data = Data()
        for record in records {
            data.append(try self.encoder.encode(record))
            data.append(0x0a)
        }
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        if #available(iOS 13.4, *) {
            _ = try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } else {
            handle.seekToEndOfFile()
            handle.write(data)
        }
    }

    private func publishIndexLocked(accountPeerId: Int64, records: [JerkgramTimeMachineIndexRecord]) throws {
        let url = self.indexURL(accountPeerId)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var data = Data()
        for record in records {
            data.append(try self.encoder.encode(record))
            data.append(0x0a)
        }
        try data.write(to: url, options: .atomic)
    }

    private func canonicalData(events: [JerkgramCanonicalEvent]) throws -> Data {
        var data = Data()
        for event in events {
            data.append(try self.encoder.encode(event))
            data.append(0x0a)
        }
        return data
    }

    private func isCompleteIndex(
        _ records: [JerkgramTimeMachineIndexRecord],
        canonicalLength: UInt64
    ) -> Bool {
        var nextOffset: UInt64 = 0
        for record in records.sorted(by: { $0.byteOffset < $1.byteOffset }) {
            guard nextOffset <= canonicalLength,
                  record.byteLength > 0,
                  record.byteOffset == nextOffset,
                  record.byteLength <= canonicalLength - nextOffset else {
                return false
            }
            nextOffset += record.byteLength
        }
        return nextOffset == canonicalLength
    }

    private func fileSize(_ url: URL) -> UInt64 {
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let size = attributes[.size] as? NSNumber else { return 0 }
        return size.uint64Value
    }

    private func completeCanonicalLength(accountPeerId: Int64) throws -> UInt64 {
        let url = self.accountURL(accountPeerId)
        let length = self.fileSize(url)
        guard length > 0 else { return 0 }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let chunkSize: UInt64 = 65_536
        var upperBound = length
        while upperBound > 0 {
            let lowerBound = upperBound > chunkSize ? upperBound - chunkSize : 0
            try handle.seek(toOffset: lowerBound)
            let count = Int(upperBound - lowerBound)
            let data: Data
            if #available(iOS 13.4, *) {
                data = try handle.read(upToCount: count) ?? Data()
            } else {
                data = handle.readData(ofLength: count)
            }
            if let newline = data.lastIndex(of: 0x0a) {
                return lowerBound + UInt64(data.distance(from: data.startIndex, to: newline)) + 1
            }
            upperBound = lowerBound
        }
        return 0
    }

    private func accountDirectoryURL(_ accountPeerId: Int64) -> URL {
        return self.rootURL.appendingPathComponent("accounts", isDirectory: true)
            .appendingPathComponent(String(accountPeerId), isDirectory: true)
    }

    private func stateKey(_ accountPeerId: Int64) -> String {
        return self.rootURL.standardizedFileURL.path + ":" + String(accountPeerId)
    }

    private func accountURL(_ accountPeerId: Int64) -> URL {
        return self.accountDirectoryURL(accountPeerId)
            .appendingPathComponent("events.jsonl", isDirectory: false)
    }

    private func indexURL(_ accountPeerId: Int64) -> URL {
        return self.accountDirectoryURL(accountPeerId)
            .appendingPathComponent("events.index.jsonl", isDirectory: false)
    }
}

// Transaction boundaries call this lightweight serial recorder. The event id
// is generated once before enqueueing; equal text never participates in identity.
public enum JerkgramCaptureRecorder {
    private static let queueKey = DispatchSpecificKey<Void>()
    private static let queue: DispatchQueue = {
        let queue = DispatchQueue(label: "jerkgram.capture.recorder", qos: .utility)
        queue.setSpecific(key: JerkgramCaptureRecorder.queueKey, value: ())
        return queue
    }()
    private static let maximumBatchSize = 32
    private static let maximumBatchDelay: Double = 0.25
    private static let maximumPendingEvents = 4_096
    private static let rootURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Jerkgram", isDirectory: true)
    private static let store = JerkgramJSONLEventStore(rootURL: rootURL)
    private static var sequenceCounter: Int64 = 0
    private static var pendingEvents: [JerkgramCanonicalEvent] = []
    private static var flushScheduled = false
    private static var retryBackoffActive = false
    private static var retryDelay: Double = 1.0
    // MARK: Jerkgram v1.2M BUILD124_NONBLOCKING_LIFECYCLE_FLUSH1
    // UIKit lifecycle notifications are normally posted on the main thread.
    // Never wait there for JSONL/index disk I/O: the capture queue can be busy
    // rebuilding or appending its index and a queue.sync here freezes the whole UI.
    private static let lifecycleObservers: [NSObjectProtocol] = [
        NotificationCenter.default.addObserver(
            forName: Notification.Name("UIApplicationDidEnterBackgroundNotification"),
            object: nil,
            queue: nil,
            using: { _ in JerkgramCaptureRecorder.requestLifecycleFlush() }
        ),
        NotificationCenter.default.addObserver(
            forName: Notification.Name("UIApplicationWillTerminateNotification"),
            object: nil,
            queue: nil,
            using: { _ in JerkgramCaptureRecorder.requestLifecycleFlush() }
        ),
    ]

    // MARK: Jerkgram v1.2M BUILD124_COOPERATIVE_LIFECYCLE_DRAIN1
    private static func requestLifecycleFlush() {
        _ = self.lifecycleObservers
        self.queue.async {
            // Do one normal bounded batch only. `flush()` schedules a later
            // continuation when necessary; draining the complete backlog in
            // one lifecycle task monopolises disk I/O during app resume.
            guard !self.pendingEvents.isEmpty, !self.flushScheduled else { return }
            self.flushScheduled = true
            _ = self.flush()
        }
    }

    public static func readyIndexRecords(
        accountPeerId: Int64,
        chatPeerId: Int64,
        afterSequence: Int64? = nil,
        throughSequence: Int64? = nil
    ) throws -> [JerkgramTimeMachineIndexRecord] {
        return try self.queue.sync {
            try self.store.readyIndexRecords(
                accountPeerId: accountPeerId,
                chatPeerId: chatPeerId,
                afterSequence: afterSequence,
                throughSequence: throughSequence
            )
        }
    }

    public static func record(
        accountPeerId: Int64,
        chatPeerId: Int64,
        kind: JerkgramEventKind,
        senderPeerId: Int64?,
        messageNamespace: Int32?,
        messageId: Int32?,
        observedAtMs: Int64,
        payload: JerkgramEventPayload
    ) {
        let eventId = JerkgramEventId.random()
        _ = self.lifecycleObservers
        self.queue.async {
            self.sequenceCounter += 1
            let sequence = max(observedAtMs * 1_000, observedAtMs * 1_000 + self.sequenceCounter)
            self.pendingEvents.append(JerkgramCanonicalEvent(
                accountPeerId: accountPeerId,
                chatPeerId: chatPeerId,
                eventId: eventId,
                sequence: sequence,
                kind: kind,
                senderPeerId: senderPeerId,
                messageNamespace: messageNamespace,
                messageId: messageId,
                observedAtMs: observedAtMs,
                payload: payload
            ))
            if self.pendingEvents.count > self.maximumPendingEvents {
                let overflow = self.pendingEvents.count - self.maximumPendingEvents
                self.pendingEvents.removeFirst(overflow)
                NSLog("[Jerkgram capture] dropped %d oldest events after persistent storage failure", overflow)
            }
            if self.pendingEvents.count >= self.maximumBatchSize && !self.retryBackoffActive {
                self.flush()
            } else if !self.flushScheduled && !self.retryBackoffActive {
                self.flushScheduled = true
                self.queue.asyncAfter(deadline: .now() + self.maximumBatchDelay) {
                    self.flush()
                }
            }
        }
    }

    @discardableResult
    private static func flush(scheduleContinuation: Bool = true) -> Bool {
        self.flushScheduled = false
        guard !self.pendingEvents.isEmpty else { return true }
        let count = min(self.maximumBatchSize, self.pendingEvents.count)
        let events = Array(self.pendingEvents.prefix(count))
        self.pendingEvents.removeFirst(count)
        let eventsByAccount = Dictionary(grouping: events, by: { $0.accountPeerId })
        var failedEvents: [JerkgramCanonicalEvent] = []
        for accountEvents in eventsByAccount.values {
            do {
                try self.store.appendBatchRecovering(accountEvents)
            } catch {
                failedEvents.append(contentsOf: accountEvents)
                NSLog("[Jerkgram capture] account append failed: %@", String(describing: error))
            }
        }
        if failedEvents.isEmpty {
            self.retryDelay = 1.0
            self.retryBackoffActive = false
            if scheduleContinuation && !self.pendingEvents.isEmpty && !self.flushScheduled {
                self.flushScheduled = true
                self.queue.async {
                    self.flush()
                }
            }
            return true
        } else {
            self.pendingEvents.insert(contentsOf: failedEvents, at: 0)
            if !self.flushScheduled {
                self.retryBackoffActive = true
                self.flushScheduled = true
                let delay = self.retryDelay
                self.retryDelay = min(self.retryDelay * 2.0, 30.0)
                self.queue.asyncAfter(deadline: .now() + delay) {
                    self.retryBackoffActive = false
                    self.flush()
                }
            }
            return false
        }
    }

    public static func flushSynchronously() {
        _ = self.lifecycleObservers
        let drain: () -> Void = {
            while !self.pendingEvents.isEmpty {
                guard self.flush(scheduleContinuation: false) else { break }
            }
        }
        if DispatchQueue.getSpecific(key: self.queueKey) != nil {
            drain()
        } else {
            self.queue.sync(execute: drain)
        }
    }
}
