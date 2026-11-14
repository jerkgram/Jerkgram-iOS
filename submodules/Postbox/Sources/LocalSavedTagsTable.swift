import Foundation

// The existing Settings owner persists these values. This is a bounded runtime
// projection shared with Postbox, not a second settings store. Known-account
// reads do no I/O; notifications are emitted after releasing the lock.
public enum JerkgramLocalPremiumPolicy {
    public static let preferenceKey = "jerkgram.LocalPremium.Enabled"
    public static let savedTagsKey = "jerkgram.LocalPremium.SavedTags"
    public static let changed = Notification.Name("JerkgramLocalPremiumPolicyChanged")
    private static let lock = NSLock()
    private static var master = UserDefaults.standard.bool(forKey: preferenceKey)
    private static var tags: [Int64: Bool] = [:]
    private static var revision: UInt64 = 0
    public static var enabled: Bool {
        lock.lock(); defer { lock.unlock() }; return master
    }
    public static var generation: UInt64 {
        lock.lock(); defer { lock.unlock() }; return revision
    }
    public static func effective(_ individual: Bool) -> Bool { enabled && individual }
    public static func scopedTagsKey(accountPeerId: Int64) -> String {
        "jerkgram.account.\(accountPeerId).setting.\(savedTagsKey)"
    }
    public static func storedTagsEnabled(accountPeerId: Int64) -> Bool {
        lock.lock(); defer { lock.unlock() }
        if let value = tags[accountPeerId] { return value }
        let value = UserDefaults.standard.object(forKey: scopedTagsKey(accountPeerId: accountPeerId)) as? Bool ?? true
        if tags.count >= 32 { tags.removeAll(keepingCapacity: true) }
        tags[accountPeerId] = value
        return value
    }
    public static func savedTagsEnabled(accountPeerId: Int64) -> Bool {
        effective(storedTagsEnabled(accountPeerId: accountPeerId))
    }
    public static func update(masterEnabled: Bool) {
        lock.lock()
        guard master != masterEnabled else { lock.unlock(); return }
        master = masterEnabled; revision &+= 1
        lock.unlock()
        NotificationCenter.default.post(name: changed, object: nil)
    }
    public static func invalidate() {
        lock.lock(); revision &+= 1; lock.unlock()
        NotificationCenter.default.post(name: changed, object: nil)
    }
    public static func updateTags(accountPeerId: Int64, enabled: Bool) {
        lock.lock(); tags[accountPeerId] = enabled; revision &+= 1; lock.unlock()
        NotificationCenter.default.post(name: changed, object: accountPeerId)
    }
}

// Account-local durable authority. No history/cache/reaction reads and no startup I/O.
public enum LocalSavedTagsError: Error, Equatable {
    case invalidName, duplicateName, invalidTag, tagNotFound, invalidMessage
    case wrongAccount, tagLimit, messageTagLimit, membershipLimit, batchLimit
    case invalidPage, corruptStore, unavailable
}

public struct LocalSavedTag: Equatable {
    public let id: String
    public let name: String
    public let order: Int32
    public let count: Int32
}

public struct LocalSavedTagMessage: Equatable {
    public let id: MessageId
    public let timestamp: Int32
    public let threadId: Int64?
    public init(id: MessageId, timestamp: Int32, threadId: Int64?) {
        self.id = id; self.timestamp = timestamp; self.threadId = threadId
    }
}

public struct LocalSavedTagsCatalogue {
    public let tags: [LocalSavedTag]
    public let totalMembershipCount: Int32
    public let revision: Int64
}

public enum LocalSavedTagsDirection: Equatable { case earlier, later }
public struct LocalSavedTagsCursor: Equatable {
    public let tagId: String
    public let message: LocalSavedTagMessage
    // Cursor construction is restricted to the store. Revision is an observed
    // snapshot token; callers restart visible windows when it changes.
    public let revision: Int64
}
public struct LocalSavedTagsPage {
    // Always ascending in .later and descending in .earlier.
    public let messages: [LocalSavedTagMessage]
    public let earlier: LocalSavedTagsCursor?
    public let later: LocalSavedTagsCursor?
    public let count: Int32
    public let revision: Int64
}

public struct LocalSavedTagsDeletionScope {
    public let threadId: Int64?
    public let minId: Int32
    public let maxId: Int32
    public let minTimestamp: Int32
    public let maxTimestamp: Int32
    // nil thread means every Saved dialog, not just unthreaded messages.
    // All endpoints inclusive. Namespace is always stable cloud (0).
    public init(threadId: Int64? = nil, minId: Int32 = 1, maxId: Int32 = Int32.max,
                minTimestamp: Int32 = Int32.min, maxTimestamp: Int32 = Int32.max) {
        self.threadId = threadId; self.minId = minId; self.maxId = maxId
        self.minTimestamp = minTimestamp; self.maxTimestamp = maxTimestamp
    }
}

public func localSavedTagsRevisionKey() -> ValueBoxKey {
    let key = ValueBoxKey(length: 4)
    key.setInt32(0, value: 0x4A470003)
    return key
}

// Only this scalar uses PreferencesEntry, for existing view/cross-process
// invalidation. Memberships never pass through Codable or preferences.
public struct LocalSavedTagsRevision: Codable, Equatable {
    public let revision: Int64
    public init(revision: Int64) { self.revision = revision }
    private enum CodingKeys: String, CodingKey { case schema, revision }
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        guard try c.decode(Int32.self, forKey: .schema) == 1 else { throw LocalSavedTagsError.corruptStore }
        let revision = try c.decode(Int64.self, forKey: .revision)
        guard revision >= 0 else { throw LocalSavedTagsError.corruptStore }
        self.revision = revision
    }
    public func encode(to encoder: Encoder) throws {
        guard revision >= 0 else { throw LocalSavedTagsError.corruptStore }
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(Int32(1), forKey: .schema)
        try c.encode(revision, forKey: .revision)
    }
}

// Explicit big-endian wire values; finite lengths checked before allocation or
// PeerId construction. No unaligned loads, native Int wire values or enums.
enum LocalSavedTagsCodec {
    static func name(_ value: String) throws -> String {
        let result = value.trimmingCharacters(in: .whitespacesAndNewlines).precomposedStringWithCanonicalMapping
        guard !result.isEmpty, result.count <= 64, result.utf8.count <= 256,
              !result.unicodeScalars.contains(where: { $0.properties.generalCategory == .control }),
              result.unicodeScalars.contains(where: { $0.properties.generalCategory != .format && !CharacterSet.whitespacesAndNewlines.contains($0) }) else {
            throw LocalSavedTagsError.invalidName
        }
        return result
    }
    static func uuid(_ value: String) throws -> Data {
        guard value.utf8.count == 36, let id = UUID(uuidString: value), id.uuidString.lowercased() == value else {
            throw LocalSavedTagsError.invalidTag
        }
        var bytes = id.uuid
        return withUnsafeBytes(of: &bytes) { Data($0) }
    }
    static func tagId(_ bytes: Data) throws -> String {
        guard bytes.count == 16 else { throw LocalSavedTagsError.corruptStore }
        let b = Array(bytes)
        return UUID(uuid: (b[0],b[1],b[2],b[3],b[4],b[5],b[6],b[7],b[8],b[9],b[10],b[11],b[12],b[13],b[14],b[15])).uuidString.lowercased()
    }
    static func i32(_ v: Int32) -> Data { var x = v.bigEndian; return withUnsafeBytes(of: &x) { Data($0) } }
    static func i64(_ v: Int64) -> Data { var x = v.bigEndian; return withUnsafeBytes(of: &x) { Data($0) } }
    static func read32(_ d: Data, _ o: Int) -> Int32 {
        var x: Int32 = 0; _ = withUnsafeMutableBytes(of: &x) { d.copyBytes(to: $0, from: o..<o+4) }; return Int32(bigEndian: x)
    }
    static func read64(_ d: Data, _ o: Int) -> Int64 {
        var x: Int64 = 0; _ = withUnsafeMutableBytes(of: &x) { d.copyBytes(to: $0, from: o..<o+8) }; return Int64(bigEndian: x)
    }
    static func definition(_ d: Data, id: String) throws -> LocalSavedTag {
        guard d.count >= 17, d.count <= 273, read32(d, 0) == 1 else { throw LocalSavedTagsError.corruptStore }
        let order = read32(d, 4), count = read32(d, 8), length = read32(d, 12)
        guard order >= 0, count >= 0, count <= 100000, length > 0, length <= 256,
              d.count == 16 + Int(length), let name = String(data: d.subdata(in: 16..<d.count), encoding: .utf8),
              (try? self.name(name)) == name else { throw LocalSavedTagsError.corruptStore }
        return LocalSavedTag(id: id, name: name, order: order, count: count)
    }
    static func definition(_ tag: LocalSavedTag) -> Data {
        return i32(1) + i32(tag.order) + i32(tag.count) + i32(Int32(tag.name.utf8.count)) + Data(tag.name.utf8)
    }
    static func message(_ d: Data, owner: PeerId) throws -> (LocalSavedTagMessage, Int32) {
        guard d.count == 37, read32(d, 0) == 1, read64(d, 4) == owner.toInt64(),
              read32(d, 12) == 0, read32(d, 16) > 0, d[24] <= 1 else { throw LocalSavedTagsError.corruptStore }
        let count = read32(d, 33)
        guard count > 0, count <= 16, d[24] != 0 || read64(d, 25) == 0 else { throw LocalSavedTagsError.corruptStore }
        return (LocalSavedTagMessage(id: MessageId(peerId: owner, namespace: 0, id: read32(d, 16)), timestamp: read32(d, 20), threadId: d[24] == 0 ? nil : read64(d, 25)), count)
    }
    static func message(_ m: LocalSavedTagMessage, count: Int32) -> Data {
        return i32(1) + i64(m.id.peerId.toInt64()) + i32(m.id.namespace) + i32(m.id.id) + i32(m.timestamp) + Data([m.threadId == nil ? 0 : 1]) + i64(m.threadId ?? 0) + i32(count)
    }
}

private struct LocalSavedTagsMetadata {
    var edges: Int32 = 0
    var revision: Int64 = 0
    var nextOrder: Int32 = 0
}

final class LocalSavedTagsTable: Table {
    static func tableSpec(_ id: Int32) -> ValueBoxTable { ValueBoxTable(id: id, keyType: .binary, compactValuesOnCreation: false) }
    private typealias C = LocalSavedTagsCodec
    private func key(_ d: Data) -> ValueBoxKey { let k = ValueBoxKey(length: d.count); k.setData(0, value: d); return k }
    private func read(_ d: Data) -> Data? {
        guard let value = self.valueBox.get(self.table, key: key(d)) else { return nil }
        // Invalid oversized values become a bounded invalid record for the codec.
        return value.length <= 273 ? value.makeData() : Data()
    }
    private func write(_ k: Data, _ d: Data) { self.valueBox.set(self.table, key: key(k), value: ReadBuffer(data: d)) }
    private func remove(_ k: Data) { self.valueBox.remove(self.table, key: key(k), secure: false) }
    private func definitionKey(_ id: String) throws -> Data { Data([1]) + (try C.uuid(id)) }
    private func primaryPrefix(_ id: Int32) -> Data { Data([2]) + C.i32(id) }
    private func messageKey(_ id: Int32) -> Data { Data([4]) + C.i32(id) }
    private func time(_ m: LocalSavedTagMessage) -> Data { C.i32(m.timestamp ^ Int32.min) + C.i32(m.id.namespace) + C.i32(m.id.id) }
    private func reversePrefix(_ id: String) throws -> Data { Data([3]) + (try C.uuid(id)) }
    private func reverseKey(_ tag: String, _ m: LocalSavedTagMessage) throws -> Data { (try reversePrefix(tag)) + time(m) }
    private func timeKey(_ m: LocalSavedTagMessage) -> Data { Data([5]) + time(m) }
    private func threadPrefix(_ t: Int64?) -> Data { Data([6, t == nil ? 0 : 1]) + C.i64((t ?? 0) ^ Int64.min) }
    private func threadKey(_ m: LocalSavedTagMessage) -> Data { threadPrefix(m.threadId) + C.i32(m.id.id) }
    private func threadTimePrefix(_ t: Int64) -> Data { Data([7]) + C.i64(t ^ Int64.min) }
    private func threadTimeKey(_ m: LocalSavedTagMessage) -> Data? { m.threadId.map { threadTimePrefix($0) + time(m) } }
    private func rows(start: ValueBoxKey, end: ValueBoxKey, limit: Int) -> [(Data, Data)] {
        var result: [(Data, Data)] = []
        self.valueBox.range(self.table, start: start, end: end, values: { k, v in
            result.append((k.length <= 29 ? k.getData(0, length: k.length) : Data(), v.length <= 273 ? v.makeData() : Data())); return true
        }, limit: limit)
        return result
    }
    private func rows(prefix: Data, limit: Int) -> [(Data, Data)] {
        let p = key(prefix); return rows(start: p, end: p.successor, limit: limit)
    }
    private func metadata(_ owner: PeerId) throws -> LocalSavedTagsMetadata {
        guard owner.namespace._internalGetInt32Value() == 0, owner.id._internalGetInt64Value() > 0 else { throw LocalSavedTagsError.wrongAccount }
        guard let d = read(Data([0])) else { return LocalSavedTagsMetadata() }
        guard d.count == 28, C.read32(d, 0) == 1 else { throw LocalSavedTagsError.corruptStore }
        guard C.read64(d, 4) == owner.toInt64() else { throw LocalSavedTagsError.wrongAccount }
        let m = LocalSavedTagsMetadata(edges: C.read32(d, 12), revision: C.read64(d, 16), nextOrder: C.read32(d, 24))
        guard m.edges >= 0, m.edges <= 100000, m.revision >= 0, m.revision < Int64.max, m.nextOrder >= 0 else { throw LocalSavedTagsError.corruptStore }
        return m
    }
    private func mutationMetadata(_ owner: PeerId) throws -> LocalSavedTagsMetadata {
        let result = try metadata(owner)
        // Reserve a readable post-mutation revision before any row is changed.
        guard result.revision < Int64.max - 1 else { throw LocalSavedTagsError.corruptStore }
        return result
    }
    private func finish(_ owner: PeerId, _ meta: inout LocalSavedTagsMetadata) {
        meta.revision += 1
        write(Data([0]), C.i32(1) + C.i64(owner.toInt64()) + C.i32(meta.edges) + C.i64(meta.revision) + C.i32(meta.nextOrder))
    }
    private func definitions() throws -> [LocalSavedTag] {
        let values = rows(prefix: Data([1]), limit: 257)
        guard values.count <= 256 else { throw LocalSavedTagsError.corruptStore }
        return try values.map { k, v in
            guard k.count == 17 else { throw LocalSavedTagsError.corruptStore }
            return try C.definition(v, id: C.tagId(k.subdata(in: 1..<17)))
        }.sorted { $0.order == $1.order ? $0.id < $1.id : $0.order < $1.order }
    }
    private func definition(_ id: String) throws -> LocalSavedTag {
        guard let d = read(try definitionKey(id)) else { throw LocalSavedTagsError.tagNotFound }
        return try C.definition(d, id: id)
    }
    private func message(_ id: Int32, owner: PeerId) throws -> (LocalSavedTagMessage, Int32)? {
        guard let d = read(messageKey(id)) else { return nil }
        let result = try C.message(d, owner: owner)
        guard result.0.id.id == id else { throw LocalSavedTagsError.corruptStore }
        return result
    }
    private func validate(_ id: MessageId, owner: PeerId) throws {
        guard id.peerId == owner, id.namespace == 0, id.id > 0 else { throw LocalSavedTagsError.invalidMessage }
    }
    private func relationTags(_ id: Int32) throws -> [String] {
        let values = rows(prefix: primaryPrefix(id), limit: 17)
        guard values.count <= 16 else { throw LocalSavedTagsError.corruptStore }
        return try values.map { k, v in
            guard k.count == 21, v == Data([1]) else { throw LocalSavedTagsError.corruptStore }
            return try C.tagId(k.subdata(in: 5..<21))
        }
    }
    func revision(selfPeerId: PeerId) throws -> Int64 { try metadata(selfPeerId).revision }
    func catalogue(selfPeerId: PeerId) throws -> LocalSavedTagsCatalogue {
        let m = try metadata(selfPeerId)
        return LocalSavedTagsCatalogue(tags: try definitions(), totalMembershipCount: m.edges, revision: m.revision)
    }
    func tags(selfPeerId: PeerId, messageId: MessageId) throws -> [String] {
        _ = try metadata(selfPeerId); try validate(messageId, owner: selfPeerId)
        return try relationTags(messageId.id)
    }
    func create(selfPeerId: PeerId, name: String) throws -> LocalSavedTag {
        var m = try mutationMetadata(selfPeerId); let name = try C.name(name); let tags = try definitions()
        guard !tags.contains(where: { $0.name == name }) else { throw LocalSavedTagsError.duplicateName }
        guard tags.count < 256 else { throw LocalSavedTagsError.tagLimit }
        // Order is bounded by current catalogue, avoiding a lifetime creation counter.
        if m.nextOrder == Int32.max {
            for (index, tag) in tags.enumerated() {
                write(try definitionKey(tag.id), C.definition(LocalSavedTag(id: tag.id, name: tag.name, order: Int32(index), count: tag.count)))
            }
            m.nextOrder = Int32(tags.count)
        }
        let tag = LocalSavedTag(id: UUID().uuidString.lowercased(), name: name, order: m.nextOrder, count: 0)
        m.nextOrder += 1
        write(try definitionKey(tag.id), C.definition(tag)); finish(selfPeerId, &m)
        return tag
    }
    func rename(selfPeerId: PeerId, tagId: String, name: String) throws -> Int64 {
        var m = try mutationMetadata(selfPeerId); let tag = try definition(tagId); let name = try C.name(name)
        guard !(try definitions()).contains(where: { $0.id != tagId && $0.name == name }) else { throw LocalSavedTagsError.duplicateName }
        if name == tag.name { return m.revision }
        write(try definitionKey(tagId), C.definition(LocalSavedTag(id: tagId, name: name, order: tag.order, count: tag.count)))
        finish(selfPeerId, &m); return m.revision
    }
    private func writeMessage(_ message: LocalSavedTagMessage, count: Int32) {
        write(messageKey(message.id.id), C.message(message, count: count))
        write(timeKey(message), C.i32(message.id.id)); write(threadKey(message), C.i32(message.id.id))
        if let k = threadTimeKey(message) { write(k, C.i32(message.id.id)) }
    }
    private func eraseMessage(_ message: LocalSavedTagMessage) {
        remove(messageKey(message.id.id)); remove(timeKey(message)); remove(threadKey(message))
        if let k = threadTimeKey(message) { remove(k) }
    }
    func set(selfPeerId: PeerId, tagId: String, messages: [LocalSavedTagMessage], assigned: Bool) throws -> Int64 {
        guard messages.count <= 1000 else { throw LocalSavedTagsError.batchLimit }
        var m = try mutationMetadata(selfPeerId); let tag = try definition(tagId); let uuid = try C.uuid(tagId)
        // Preflight the ENTIRE selection before writing, including its last ID.
        var unique: [Int32: LocalSavedTagMessage] = [:]
        for message in messages {
            try validate(message.id, owner: selfPeerId)
            if let old = unique[message.id.id], old != message { throw LocalSavedTagsError.invalidMessage }
            unique[message.id.id] = message
        }
        var changes: [(LocalSavedTagMessage, Int32)] = []
        for incoming in unique.values {
            let existing = try message(incoming.id.id, owner: selfPeerId)
            let relation = read(primaryPrefix(incoming.id.id) + uuid)
            guard relation == nil || relation == Data([1]) else { throw LocalSavedTagsError.corruptStore }
            let present = relation != nil
            if present == assigned { continue }
            if assigned && (existing?.1 ?? 0) >= 16 { throw LocalSavedTagsError.messageTagLimit }
            guard assigned || existing != nil else { throw LocalSavedTagsError.corruptStore }
            changes.append((existing?.0 ?? incoming, existing?.1 ?? 0))
        }
        let delta = Int32(changes.count) * (assigned ? 1 : -1)
        guard m.edges + delta <= 100000 else { throw LocalSavedTagsError.membershipLimit }
        guard m.edges + delta >= 0, tag.count + delta >= 0 else { throw LocalSavedTagsError.corruptStore }
        if changes.isEmpty { return m.revision }
        for (message, count) in changes {
            let p = primaryPrefix(message.id.id) + uuid
            if assigned {
                write(p, Data([1])); write(try reverseKey(tagId, message), C.message(message, count: 1))
                writeMessage(message, count: count + 1)
            } else {
                remove(p); remove(try reverseKey(tagId, message))
                if count == 1 { eraseMessage(message) } else { write(messageKey(message.id.id), C.message(message, count: count - 1)) }
            }
        }
        m.edges += delta
        write(try definitionKey(tagId), C.definition(LocalSavedTag(id: tagId, name: tag.name, order: tag.order, count: tag.count + delta)))
        finish(selfPeerId, &m); return m.revision
    }
    func updateMetadata(selfPeerId: PeerId, messages: [LocalSavedTagMessage]) throws -> Int64 {
        guard messages.count <= 1000 else { throw LocalSavedTagsError.batchLimit }
        var m = try mutationMetadata(selfPeerId)
        var unique: [Int32: LocalSavedTagMessage] = [:]
        for incoming in messages {
            try validate(incoming.id, owner: selfPeerId)
            if let old = unique[incoming.id.id], old != incoming { throw LocalSavedTagsError.invalidMessage }
            unique[incoming.id.id] = incoming
        }
        let tags = Dictionary(uniqueKeysWithValues: try definitions().map { ($0.id, $0) })
        var changes: [(LocalSavedTagMessage, LocalSavedTagMessage, Int32, [String])] = []
        for incoming in unique.values {
            if let (old, count) = try message(incoming.id.id, owner: selfPeerId), old != incoming {
                let ids = try checkedRelations(old, count: count, tags: tags)
                changes.append((old, incoming, count, ids))
            }
        }
        if changes.isEmpty { return m.revision }
        for (old, incoming, count, ids) in changes {
            eraseMessage(old); writeMessage(incoming, count: count)
            for id in ids {
                remove(try reverseKey(id, old)); write(try reverseKey(id, incoming), C.message(incoming, count: 1))
            }
        }
        finish(selfPeerId, &m); return m.revision
    }
    func page(selfPeerId: PeerId, tagId: String, cursor: LocalSavedTagsCursor?, direction: LocalSavedTagsDirection, limit: Int) throws -> LocalSavedTagsPage {
        guard limit > 0, limit <= 45 else { throw LocalSavedTagsError.invalidPage }
        let m = try metadata(selfPeerId); let tag = try definition(tagId); let prefix = key(try reversePrefix(tagId))
        if let cursor = cursor {
            guard cursor.tagId == tagId, cursor.message.id.peerId == selfPeerId else { throw LocalSavedTagsError.invalidPage }
        }
        let anchor = try cursor.map { key(try reverseKey(tagId, $0.message)) }
        let earlier = direction == .earlier
        let records = rows(start: anchor ?? (earlier ? prefix.successor : prefix), end: earlier ? prefix : prefix.successor, limit: limit + 1)
        let decoded = try records.prefix(limit).map { k, d -> LocalSavedTagMessage in
            let message = try C.message(d, owner: selfPeerId).0
            guard k == (try reverseKey(tagId, message)) else { throw LocalSavedTagsError.corruptStore }
            return message
        }
        // One additional row in the requested direction; one indexed probe in
        // the opposite direction. Empty pages after deletion have no cursors.
        var earlierCursor: LocalSavedTagsCursor?, laterCursor: LocalSavedTagsCursor?
        if let first = decoded.first, let last = decoded.last {
            let oldest = earlier ? last : first, newest = earlier ? first : last
            let hasEarlier = earlier ? records.count > limit : !rows(start: key(try reverseKey(tagId, oldest)), end: prefix, limit: 1).isEmpty
            let hasLater = earlier ? !rows(start: key(try reverseKey(tagId, newest)), end: prefix.successor, limit: 1).isEmpty : records.count > limit
            if hasEarlier { earlierCursor = LocalSavedTagsCursor(tagId: tagId, message: oldest, revision: m.revision) }
            if hasLater { laterCursor = LocalSavedTagsCursor(tagId: tagId, message: newest, revision: m.revision) }
        }
        return LocalSavedTagsPage(messages: decoded, earlier: earlierCursor, later: laterCursor, count: tag.count, revision: m.revision)
    }

    // Full semantic deletions are atomic in the enclosing Postbox transaction.
    // Two bounded streaming passes: validate all affected rows before any write,
    // then erase. At most128 index rows +16 tag IDs +256 definitions live here.
    // O(affected edges) queue work: bounded memory is NOT a latency guarantee.
    private func stream(start: ValueBoxKey, end: ValueBoxKey, _ body: (Data, Data) throws -> Void) throws {
        var cursor = start
        var visited = 0
        while true {
            let chunk = rows(start: cursor, end: end, limit: 128)
            if chunk.isEmpty { break }
            visited += chunk.count
            guard visited <= 100000 else { throw LocalSavedTagsError.corruptStore }
            for (k, v) in chunk { try body(k, v) }
            cursor = key(chunk[chunk.count - 1].0)
        }
    }
    func delete(selfPeerId: PeerId, tagId: String) throws -> Int64 {
        var m = try mutationMetadata(selfPeerId); let tag = try definition(tagId); let prefix = key(try reversePrefix(tagId)); let uuid = try C.uuid(tagId)
        var count: Int32 = 0
        try stream(start: prefix, end: prefix.successor) { k, d in
            let value = try C.message(d, owner: selfPeerId).0
            guard k == (try self.reverseKey(tagId, value)), let stored = try self.message(value.id.id, owner: selfPeerId), stored.0 == value,
                  self.read(self.primaryPrefix(value.id.id) + uuid) == Data([1]) else { throw LocalSavedTagsError.corruptStore }
            count += 1
        }
        guard count == tag.count, count <= m.edges else { throw LocalSavedTagsError.corruptStore }
        try stream(start: prefix, end: prefix.successor) { k, d in
            let value = try C.message(d, owner: selfPeerId).0
            guard let stored = try self.message(value.id.id, owner: selfPeerId) else { preconditionFailure("validated transaction changed") }
            self.remove(k); self.remove(self.primaryPrefix(value.id.id) + uuid)
            if stored.1 == 1 { self.eraseMessage(value) } else { self.write(self.messageKey(value.id.id), C.message(value, count: stored.1 - 1)) }
        }
        remove(try definitionKey(tagId)); m.edges -= count; finish(selfPeerId, &m); return m.revision
    }
    private func checkedRelations(_ message: LocalSavedTagMessage, count: Int32, tags: [String: LocalSavedTag]) throws -> [String] {
        let ids = try relationTags(message.id.id)
        guard ids.count == Int(count) else { throw LocalSavedTagsError.corruptStore }
        for id in ids {
            guard tags[id] != nil, let d = read(try reverseKey(id, message)), (try C.message(d, owner: message.id.peerId)).0 == message else { throw LocalSavedTagsError.corruptStore }
        }
        return ids
    }
    private func eraseRelations(_ message: LocalSavedTagMessage, tags: inout [String: LocalSavedTag]) throws -> Int32 {
        let ids = try relationTags(message.id.id)
        for id in ids {
            guard let tag = tags[id] else { preconditionFailure("validated transaction changed") }
            remove(primaryPrefix(message.id.id) + (try C.uuid(id))); remove(try reverseKey(id, message))
            tags[id] = LocalSavedTag(id: id, name: tag.name, order: tag.order, count: tag.count - 1)
        }
        eraseMessage(message); return Int32(ids.count)
    }
    private func finishDeletion(_ peer: PeerId, _ m: inout LocalSavedTagsMetadata, original: [String: LocalSavedTag], tags: [String: LocalSavedTag], removed: Int32) throws {
        if removed == 0 { return }
        for (id, tag) in tags where tag != original[id] { write(try definitionKey(id), C.definition(tag)) }
        m.edges -= removed; finish(peer, &m)
    }
    func removeMessages(selfPeerId: PeerId, ids: [MessageId]) throws -> Int64 {
        guard ids.count <= 1000 else { throw LocalSavedTagsError.batchLimit }
        var m = try mutationMetadata(selfPeerId); var tags = Dictionary(uniqueKeysWithValues: try definitions().map { ($0.id, $0) }); let original = tags
        var affected: [LocalSavedTagMessage] = []
        var decrements: [String: Int32] = [:]
        for id in Set(ids) {
            try validate(id, owner: selfPeerId)
            if let (message, count) = try message(id.id, owner: selfPeerId) {
                for tag in try checkedRelations(message, count: count, tags: tags) { decrements[tag, default: 0] += 1 }
                affected.append(message)
            }
        }
        guard decrements.values.reduce(0, +) <= m.edges,
              decrements.allSatisfy({ $0.value <= (tags[$0.key]?.count ?? 0) }) else { throw LocalSavedTagsError.corruptStore }
        var removed: Int32 = 0
        for message in affected { removed += try eraseRelations(message, tags: &tags) }
        try finishDeletion(selfPeerId, &m, original: original, tags: tags, removed: removed); return m.revision
    }
    func removeGlobalIds(selfPeerId: PeerId, ids: [Int32]) throws -> Int64 {
        guard ids.count <= 1000 else { throw LocalSavedTagsError.batchLimit }
        return try removeMessages(selfPeerId: selfPeerId, ids: ids.map { MessageId(peerId: selfPeerId, namespace: 0, id: $0) })
    }
    func removeRange(selfPeerId: PeerId, scope: LocalSavedTagsDeletionScope) throws -> Int64 {
        guard scope.minId > 0, scope.minId <= scope.maxId, scope.minTimestamp <= scope.maxTimestamp else { throw LocalSavedTagsError.invalidMessage }
        var m = try mutationMetadata(selfPeerId); var tags = Dictionary(uniqueKeysWithValues: try definitions().map { ($0.id, $0) }); let original = tags
        let timestampBounded = scope.minTimestamp != Int32.min || scope.maxTimestamp != Int32.max
        let prefix: Data
        let lower: Data, upper: Data
        if timestampBounded {
            prefix = scope.threadId.map { threadTimePrefix($0) } ?? Data([5])
            lower = prefix + C.i32(scope.minTimestamp ^ Int32.min)
            upper = prefix + C.i32(scope.maxTimestamp ^ Int32.min)
        } else {
            prefix = scope.threadId.map { threadPrefix($0) } ?? Data([4])
            lower = prefix + C.i32(scope.minId)
            upper = prefix + C.i32(scope.maxId)
        }
        // A key equal to the lower bound (direct-ID metadata) must be included.
        let start = key(lower).predecessor, end = key(upper).successor
        func resolve(_ k: Data, _ d: Data) throws -> (LocalSavedTagMessage, Int32)? {
            let value: (LocalSavedTagMessage, Int32)
            if prefix == Data([4]) { value = try C.message(d, owner: selfPeerId) }
            else {
                guard d.count == 4, let found = try self.message(C.read32(d, 0), owner: selfPeerId) else { throw LocalSavedTagsError.corruptStore }; value = found
            }
            let v = value.0
            // A secondary key must describe the resolved metadata exactly.
            // Otherwise duplicate/stale keys could pass validation then fail
            // halfway through the erase pass after deleting the same ID twice.
            let expectedKey: Data
            if timestampBounded {
                expectedKey = scope.threadId == nil ? self.timeKey(v) : (self.threadTimeKey(v) ?? Data())
            } else {
                expectedKey = scope.threadId == nil ? self.messageKey(v.id.id) : self.threadKey(v)
            }
            guard k == expectedKey else { throw LocalSavedTagsError.corruptStore }
            guard v.id.id >= scope.minId, v.id.id <= scope.maxId, v.timestamp >= scope.minTimestamp, v.timestamp <= scope.maxTimestamp,
                  scope.threadId == nil || scope.threadId == v.threadId else { return nil }
            return value
        }
        var expectedRemoved: Int32 = 0
        var decrements: [String: Int32] = [:]
        try stream(start: start, end: end) { k, d in
            if let (v, count) = try resolve(k, d) {
                for tag in try self.checkedRelations(v, count: count, tags: tags) { decrements[tag, default: 0] += 1 }
                expectedRemoved += count
            }
        }
        guard expectedRemoved <= m.edges, decrements.allSatisfy({ $0.value <= (tags[$0.key]?.count ?? 0) }) else { throw LocalSavedTagsError.corruptStore }
        var removed: Int32 = 0
        try stream(start: start, end: end) { k, d in
            if let (v, _) = try resolve(k, d) { removed += try self.eraseRelations(v, tags: &tags) }
        }
        try finishDeletion(selfPeerId, &m, original: original, tags: tags, removed: removed); return m.revision
    }
}
