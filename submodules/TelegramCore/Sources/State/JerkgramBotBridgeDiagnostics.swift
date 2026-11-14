import Foundation
import Postbox

// BEGIN BOTBRIDGE DIAGNOSTICS
// Every value accepted here is finite or generated locally. Neither API objects nor
// account identifiers cross the sink boundary. The registry's identifiers stay RAM only.
struct BotBridgeOperationFlags: OptionSet, Codable {
    let rawValue: Int
    static let text = Self(rawValue: 1)
    static let reply = Self(rawValue: 2)
    static let media = Self(rawValue: 4)
    static let post = Self(rawValue: 8)
}
struct BotBridgeOperationContext {
    let logicalId = UUID()
    let flags: BotBridgeOperationFlags
}
enum BotBridgeDiagnosticCategory: String, Codable {
    case text, media, forward, inline, reaction, edit, delete, mutation
    case stateRead = "state_read"
    case readAck = "read_ack"
    case unknown
    static func classify(_ method: String) -> Self {
        switch method {
        case "messages.sendMessage": return .text
        case "messages.sendMedia", "messages.sendMultiMedia": return .media
        case "messages.forwardMessages": return .forward
        case "messages.sendInlineBotResult": return .inline
        case "messages.sendReaction", "messages.sendPaidReaction": return .reaction
        case "messages.editMessage", "messages.editInlineBotMessage", "ephemeral.editMessage": return .edit
        case "messages.deleteMessages", "channels.deleteMessages", "channels.deleteHistory", "messages.deleteHistory", "channels.deleteParticipantHistory", "messages.deleteScheduledMessages", "messages.deleteQuickReplyMessages", "ephemeral.deleteMessage", "ephemeral.deleteWelcomeMessage", "messages.deleteTopicHistory", "messages.deleteSavedHistory", "messages.deleteQuickReplyShortcut", "channels.deleteChannel", "messages.deleteChat": return .delete
        case "messages.readHistory", "channels.readHistory", "messages.readMessageContents", "channels.readMessageContents", "messages.readMentions", "messages.readReactions", "messages.readDiscussion", "stories.readStories": return .readAck
        case "updates.getState", "updates.getDifference": return .stateRead
        case "messages.sendScreenshotNotification", "messages.sendVote", "messages.sendWebViewResultMessage", "channels.leaveChannel", "messages.deleteChatUser", "messages.reportSpam": return .mutation
        default: return .unknown
        }
    }
}
enum BotBridgeDiagnosticPhase: String, Codable { case submitted, acknowledged, result, rpcFailure, parseFailure, cancelled, snapshot, historyStart, historyPage, historyEnd, handoff, restoredTerminal }
enum BotBridgeDiagnosticLifecycle: String, Codable { case localLogout, remoteLogout, serverLogout, softReset, stateManagementReset, authKeyUnknown, removed, cleanupStart, cleanupResult, deletionScheduled, deinitialized }
struct BotBridgeDiagnosticTuple: Codable { let pts: Int32; let qts: Int32; let date: Int32; let seq: Int32 }
enum BotBridgeDiagnosticHistoryReason: String, Codable {
    case completed, noCandidate, tooLong, limit, deadline, clockChanged, corrupt
    case nonadvancing, rpcError, timeout, cancelled, replaced, loggedOut, softReset, interruptedState
}
enum BotBridgeDiagnosticCorrelation: String, Codable { case expired, historyLost = "history_lost", none, observedOrderOnly = "observed_order_only" }
struct BotBridgeDiagnosticHistory: Codable {
    let original: BotBridgeDiagnosticTuple?
    let candidate: BotBridgeDiagnosticTuple?
    let lastRetrieval: BotBridgeDiagnosticTuple?
    let observedLive: BotBridgeDiagnosticTuple?
    let reservedAttempts: Int
    let committedPages: Int
    let examinedMessages: Int
    let insertedMessages: Int
    let insertedPeers: Int
    let insertedChats: Int
    let insertedUsers: Int
    let skipped: Int
    let unsupported: Int
    let historicalDeletionObserved: Int
    let deleteIdsObserved: Int
    let missingReferences: Int
    let reason: BotBridgeDiagnosticHistoryReason?
    var deletionCoverageLimited = true
    var liveStateNeverReplaced = true
    let modernProcessingResumed: Bool
}
enum BotBridgeDiagnosticErrorClass: String, Codable { case auth, rateLimit, server, client, unknown }
struct BotBridgeDiagnosticFlight: Codable {
    let request: UUID
    let logical: UUID?
    let category: BotBridgeDiagnosticCategory
    let flags: BotBridgeOperationFlags
    let attempt: Int
    let submittedAt: Double
    var completion: BotBridgeDiagnosticPhase?
    var errorCode: Int32?
}
struct BotBridgeDiagnosticRecord: Codable {
    var schema = 1
    let session: UUID
    let epoch: UUID
    let sequence: UInt64
    let wall: Double
    let phase: BotBridgeDiagnosticPhase
    var request: UUID?
    var logical: UUID?
    var category: BotBridgeDiagnosticCategory = .unknown
    var flags: BotBridgeOperationFlags = []
    var attempt: Int = 0
    var errorCode: Int32?
    var errorClass: BotBridgeDiagnosticErrorClass?
    var lifecycle: BotBridgeDiagnosticLifecycle?
    var lastSubmitted: BotBridgeDiagnosticFlight?
    var lastCompleted: BotBridgeDiagnosticFlight?
    var inFlight: [BotBridgeDiagnosticFlight] = []
    var history: BotBridgeDiagnosticHistory?
    var evictedEvents: UInt64 = 0
    var lostContexts: UInt64 = 0
    var expiredContexts: UInt64 = 0
    var correlation: BotBridgeDiagnosticCorrelation?
}
private func botBridgeIncrement(_ value: inout UInt64) { if value < UInt64.max { value += 1 } }

final class BotBridgeDiagnosticScope {
    let epoch = UUID()
    let session: UUID
    let generation: String // Validated preference generation; never exported.
    private let lock = NSLock()
    private let sink: BotBridgeDiagnosticSink
    private let clock: () -> Double
    private let cancelHistory: (BotBridgeDiagnosticLifecycle) -> Void
    weak var registration: BotBridgeScopeRegistration?
    private var frozen = false
    private var sequence: UInt64 = 0
    private var ring: [BotBridgeDiagnosticRecord] = []
    private var snapshots: [BotBridgeDiagnosticRecord] = []
    private var active: [UUID: BotBridgeDiagnosticFlight] = [:]
    private var attempts: [UUID: (Int, Double)] = [:]
    private var lastSubmitted: BotBridgeDiagnosticFlight?
    private var lastHistory: BotBridgeDiagnosticHistory?
    private var lastCompleted: BotBridgeDiagnosticFlight?
    private var evicted: UInt64 = 0
    private var lost: UInt64 = 0
    private var expired: UInt64 = 0
    init(generation: String, sink: BotBridgeDiagnosticSink = .shared, clock: @escaping () -> Double = { Date().timeIntervalSince1970 }, cancelHistory: @escaping (BotBridgeDiagnosticLifecycle) -> Void) {
        self.generation = generation; self.session = UUID(uuidString: generation) ?? UUID(); self.sink = sink; self.clock = clock; self.cancelHistory = cancelHistory
    }
    var isFrozen: Bool { lock.lock(); defer { lock.unlock() }; return frozen }
    var activeCount: Int { lock.lock(); defer { lock.unlock() }; return active.count }
    func snapshotEvents() -> [BotBridgeDiagnosticRecord] { lock.lock(); defer { lock.unlock() }; return (ring + snapshots).sorted { $0.sequence < $1.sequence } }
    private func expire(_ now: Double) {
        let old = active.filter { now < $0.value.submittedAt || now - $0.value.submittedAt > 1800 }.map { $0.key }
        for id in old { active.removeValue(forKey: id); botBridgeIncrement(&expired) }
        attempts = attempts.filter { now >= $0.value.1 && now - $0.value.1 <= 1800 }
        if let value = lastSubmitted, now < value.submittedAt || now - value.submittedAt > 1800 { lastSubmitted = nil }
        if let value = lastCompleted, now < value.submittedAt || now - value.submittedAt > 1800 { lastCompleted = nil }
    }
    private func record(_ phase: BotBridgeDiagnosticPhase, now: Double) -> BotBridgeDiagnosticRecord {
        botBridgeIncrement(&sequence)
        return BotBridgeDiagnosticRecord(session: session, epoch: epoch, sequence: sequence, wall: now, phase: phase, evictedEvents: evicted, lostContexts: lost, expiredContexts: expired)
    }
    private func append(_ record: BotBridgeDiagnosticRecord, reserved: Bool = false) {
        var value = record
        if reserved {
            if snapshots.count == 8 { snapshots.removeFirst(); botBridgeIncrement(&evicted) }
            value.evictedEvents = evicted
            snapshots.append(value)
        } else {
            if ring.count == 248 { ring.removeFirst(); botBridgeIncrement(&evicted) }
            value.evictedEvents = evicted
            ring.append(value)
        }
        // Sink only takes a short bounded lock, schedules a single drain, and returns.
        sink.accept(value, reserved: reserved)
    }
    func begin(category: BotBridgeDiagnosticCategory, context: BotBridgeOperationContext?) -> BotBridgeRequestObservation? {
        lock.lock(); defer { lock.unlock() }
        guard !frozen else { return nil }
        let now = clock(); expire(now)
        guard active.count < 64 else {
            botBridgeIncrement(&lost)
            var value = record(.snapshot, now: now); value.correlation = .historyLost
            append(value, reserved: true)
            return nil
        }
        var attempt = 1
        if let context = context {
            if let previous = attempts[context.logicalId] { attempt = min(previous.0 + 1, Int(Int32.max)) }
            else if attempts.count == 64, let oldest = attempts.min(by: { $0.value.1 < $1.value.1 }) { attempts.removeValue(forKey: oldest.key); botBridgeIncrement(&lost) }
            attempts[context.logicalId] = (attempt, now)
        }
        let id = UUID()
        var flags = context?.flags ?? []
        if category == .text { flags.insert(.text) }
        if category == .media { flags.insert(.media) }
        let flight = BotBridgeDiagnosticFlight(request: id, logical: context?.logicalId, category: category, flags: flags, attempt: attempt, submittedAt: now)
        active[id] = flight; lastSubmitted = flight
        var value = record(.submitted, now: now)
        value.request = id; value.logical = flight.logical; value.category = category; value.flags = flags; value.attempt = attempt
        append(value)
        return BotBridgeRequestObservation(scope: self, id: id)
    }
    func observe(_ id: UUID, phase: BotBridgeDiagnosticPhase, errorCode: Int32? = nil) {
        lock.lock(); defer { lock.unlock() }
        let now = clock(); expire(now)
        guard !frozen, var flight = active[id] else { return }
        var value = record(phase, now: now)
        value.request = id; value.logical = flight.logical; value.category = flight.category; value.flags = flight.flags; value.attempt = flight.attempt
        value.errorCode = errorCode
        if let code = errorCode {
            value.errorClass = code == 401 ? .auth : (code == 420 ? .rateLimit : (code >= 500 ? .server : (code >= 400 ? .client : .unknown)))
        }
        if phase != .acknowledged {
            flight.completion = phase; flight.errorCode = errorCode
            active.removeValue(forKey: id); lastCompleted = flight
        }
        append(value)
    }
    func history(_ history: BotBridgeDiagnosticHistory, phase: BotBridgeDiagnosticPhase) {
        lock.lock(); defer { lock.unlock() }
        // Terminal manager callbacks may arrive after freeze; retain their typed result.
        lastHistory = history
        var value = record(phase, now: clock()); value.history = history
        append(value, reserved: phase == .historyEnd || phase == .handoff || phase == .restoredTerminal)
    }
    func lifecycle(_ kind: BotBridgeDiagnosticLifecycle, terminal: Bool = true) {
        precondition(kind != .stateManagementReset || !terminal)
        // Routine manager activation observes the existing history lifetime.
        // Genuine invalidation still happens before any snapshot or detach.
        if kind != .cleanupResult && kind != .deletionScheduled && kind != .stateManagementReset { cancelHistory(kind) }
        lock.lock()
        let now = clock(); expire(now)
        var value = record(.snapshot, now: now)
        value.history = lastHistory
        value.lifecycle = kind; value.lastSubmitted = lastSubmitted; value.lastCompleted = lastCompleted
        value.inFlight = Array(active.values).sorted { $0.submittedAt < $1.submittedAt }
        let correlation: BotBridgeDiagnosticCorrelation = expired > 0 ? .expired : (lost > 0 || evicted > 0 ? .historyLost : (lastSubmitted == nil ? .none : .observedOrderOnly))
        value.correlation = correlation
        if terminal { frozen = true; active.removeAll(); attempts.removeAll() }
        append(value, reserved: true)
        lock.unlock()
        if terminal { registration?.clear(epoch: epoch) }
    }
}
// Independent box: Signals capture this object, which owns neither Network nor Account.
final class BotBridgeScopeRegistration {
    private let lock = NSLock()
    private weak var scope: BotBridgeDiagnosticScope?
    func install(_ scope: BotBridgeDiagnosticScope) { scope.registration = self; lock.lock(); self.scope = scope; lock.unlock() }
    func clear(epoch: UUID) { lock.lock(); if scope?.epoch == epoch { scope = nil }; lock.unlock() }
    func begin(method: String, context: BotBridgeOperationContext?) -> BotBridgeRequestObservation? {
        lock.lock(); let scope = self.scope; lock.unlock()
        return scope?.begin(category: .classify(method), context: context)
    }
    func lifecycle(_ kind: BotBridgeDiagnosticLifecycle) {
        lock.lock(); let scope = self.scope; lock.unlock()
        scope?.lifecycle(kind, terminal: false)
    }
    func context(flags: BotBridgeOperationFlags) -> BotBridgeOperationContext? {
        lock.lock(); let scope = self.scope; lock.unlock()
        guard let scope = scope, !scope.isFrozen else { return nil }
        return BotBridgeOperationContext(flags: flags)
    }
}
final class BotBridgeRequestObservation {
    private weak var scope: BotBridgeDiagnosticScope?
    private let id: UUID
    private let lock = NSLock()
    private var terminal = false
    init(scope: BotBridgeDiagnosticScope, id: UUID) { self.scope = scope; self.id = id }
    func acknowledge() { lock.lock(); defer { lock.unlock() }; if !terminal { scope?.observe(id, phase: .acknowledged) } }
    func finish(_ phase: BotBridgeDiagnosticPhase, errorCode: Int32? = nil) {
        lock.lock(); defer { lock.unlock() }
        guard !terminal else { return }; terminal = true
        scope?.observe(id, phase: phase, errorCode: errorCode)
    }
    func cancel() { finish(.cancelled) }
}
// Immutable operation target. It keeps no Account, scope or manager alive and is
// never Codable. Delayed callbacks cannot re-resolve a replacement generation.
final class BotBridgeDiagnosticTarget {
    private(set) weak var namespace: AnyObject?
    let record: Int64
    let generation: UUID
    let epoch: UUID
    let directoryName: String?
    init(namespace: AnyObject, record: Int64, generation: UUID, epoch: UUID, directoryName: String?) {
        self.namespace = namespace; self.record = record; self.generation = generation
        self.epoch = epoch; self.directoryName = directoryName
    }
}
// Process-local aggregate only: no rejected account identifier or recorder is retained.
struct BotBridgeDiagnosticAdmissionLoss: Encodable {
    var capacity: UInt64 = 0
    var duplicateTarget: UInt64 = 0
    var invalidGeneration: UInt64 = 0
}
// Cancellation index only. No API hook, no polling, and no Account retention.
final class BotBridgeDiagnosticRegistry {
    static let shared = BotBridgeDiagnosticRegistry()
    private struct Entry {
        weak var namespace: AnyObject?
        let record: Int64
        let generation: UUID
        let epoch: UUID
        let directoryName: String?
        weak var scope: BotBridgeDiagnosticScope?
    }
    private let lock = NSLock()
    private var entries: [Entry] = []
    private var deniedAdmissions = BotBridgeDiagnosticAdmissionLoss()
    var admissionLoss: BotBridgeDiagnosticAdmissionLoss { lock.lock(); defer { lock.unlock() }; return deniedAdmissions }
    func register(namespace: AnyObject, record: Int64, scope: BotBridgeDiagnosticScope, directoryName: String? = nil) -> Bool {
        lock.lock(); defer { lock.unlock() }
        entries.removeAll { $0.namespace == nil || $0.scope == nil }
        // Never silently evict a still-live cancellation target (even a different epoch).
        guard let generation = UUID(uuidString: scope.generation) else { botBridgeIncrement(&deniedAdmissions.invalidGeneration); return false }
        guard !entries.contains(where: { $0.namespace === namespace && $0.record == record }) else { botBridgeIncrement(&deniedAdmissions.duplicateTarget); return false }
        guard entries.count < 32 else { botBridgeIncrement(&deniedAdmissions.capacity); return false }
        entries.append(Entry(namespace: namespace, record: record, generation: generation, epoch: scope.epoch, directoryName: directoryName, scope: scope)); return true
    }
    func unregister(namespace: AnyObject, record: Int64, epoch: UUID) {
        lock.lock(); entries.removeAll { $0.namespace == nil || $0.scope == nil || ($0.namespace === namespace && $0.record == record && $0.epoch == epoch) }; lock.unlock()
    }
    func targets(namespace: AnyObject) -> [BotBridgeDiagnosticTarget] {
        lock.lock(); defer { lock.unlock() }
        entries.removeAll { $0.namespace == nil || $0.scope == nil }
        return entries.filter { $0.namespace === namespace }.map {
            BotBridgeDiagnosticTarget(namespace: namespace, record: $0.record, generation: $0.generation, epoch: $0.epoch, directoryName: $0.directoryName)
        }
    }
    func target(namespace: AnyObject, record: Int64) -> BotBridgeDiagnosticTarget? {
        return targets(namespace: namespace).first { $0.record == record }
    }
    func notify(target: BotBridgeDiagnosticTarget?, kind: BotBridgeDiagnosticLifecycle) {
        guard let target = target, let namespace = target.namespace else { return }
        lock.lock(); entries.removeAll { $0.namespace == nil || $0.scope == nil }
        let value = entries.first { $0.namespace === namespace && $0.record == target.record && $0.generation == target.generation && $0.epoch == target.epoch }?.scope
        lock.unlock()
        guard let value = value else { return }
        if kind != .removed || !value.isFrozen { value.lifecycle(kind) }
    }
    // Immediate subscribed observations resolve once; delayed work captures target().
    func notify(namespace: AnyObject, record: Int64, kind: BotBridgeDiagnosticLifecycle) {
        notify(target: target(namespace: namespace, record: record), kind: kind)
    }
    func reconcile(namespace: AnyObject, records: Set<Int64>) {
        for target in targets(namespace: namespace) where !records.contains(target.record) {
            notify(target: target, kind: .removed)
        }
    }
}
// The original deletion predicate and its diagnostic observation share a boundary.
// Call immediately before the existing removal attempt on the utility queue.
func botBridgeScheduleAccountDirectoryDeletion(directoryName: String, validPaths: Set<String>, targets: [BotBridgeDiagnosticTarget]) -> Bool {
    guard directoryName.hasPrefix("account-"), !validPaths.contains(directoryName) else { return false }
    for target in targets where target.directoryName == directoryName {
        BotBridgeDiagnosticRegistry.shared.notify(target: target, kind: .deletionScheduled)
    }
    return true
}
// Account's lock makes admission race safely with logout before the first request.
final class BotBridgeDiagnosticOwner {
    private let lock = NSLock()
    private var closed = false
    private var scope: BotBridgeDiagnosticScope?
    func admit(namespace: AnyObject, record: Int64, generation: String, registration: BotBridgeScopeRegistration, directoryName: String? = nil, cancelHistory: @escaping (BotBridgeDiagnosticLifecycle) -> Void) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !closed, scope == nil, UUID(uuidString: generation) != nil else { return false }
        let value = BotBridgeDiagnosticScope(generation: generation, cancelHistory: cancelHistory)
        guard BotBridgeDiagnosticRegistry.shared.register(namespace: namespace, record: record, scope: value, directoryName: directoryName) else { return false }
        scope = value; value.registration = registration; registration.install(value); return true
    }
    func history(_ event: BotBridgeDiagnosticHistory, phase: BotBridgeDiagnosticPhase) { lock.lock(); let scope = self.scope; lock.unlock(); scope?.history(event, phase: phase) }
    func lifecycle(_ kind: BotBridgeDiagnosticLifecycle, terminal: Bool = true) {
        precondition(kind != .stateManagementReset || !terminal)
        lock.lock(); if terminal { closed = true }; let scope = self.scope; lock.unlock()
        scope?.lifecycle(kind, terminal: terminal)
    }
    func teardown(namespace: AnyObject, record: Int64, registration: BotBridgeScopeRegistration) {
        lifecycle(.deinitialized)
        lock.lock(); let scope = self.scope; self.scope = nil; lock.unlock()
        if let scope = scope { registration.clear(epoch: scope.epoch); BotBridgeDiagnosticRegistry.shared.unregister(namespace: namespace, record: record, epoch: scope.epoch) }
    }
}
public enum BotBridgeDiagnosticExportError: Error { case busy, storage }
private struct BotBridgeDiagnosticEnvelope: Encodable {
    let schema = 1
    let status: String
    let records: [BotBridgeDiagnosticRecord]
    let sinkDropped: UInt64
    let snapshotDropped: UInt64
    let storageFailures: UInt64
    let storageLossCountUnknown: Bool
    let exportTruncated: Int
    let retentionExpiredFiles: UInt64
    let rotationEvictedFiles: UInt64
    let malformedRecords: UInt64
    let retentionExpiredRecords: UInt64
    let admissionDenied: BotBridgeDiagnosticAdmissionLoss
    let internalRetriesUnobserved = true
    let uploadsUnobserved = true
    let localUpdateApplicationUnobserved = true
    let restartAndCrashDurabilityUnknown = true
    let snapshotPersistenceBestEffort = true
    let unknownMethodsAreCoverageGaps = true
    let cleanupResultMeansSignalCompletion = true
    let directoryDeletionIsScheduledOnly = true
}
final class BotBridgeDiagnosticSink {
    static let shared = BotBridgeDiagnosticSink(root: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Jerkgram/BotBridge1", isDirectory: true))
    private let root: URL
    private let queue: DispatchQueue
    private let listDirectory: (URL) throws -> [URL]
    private let lock = NSLock()
    private var pending: [BotBridgeDiagnosticRecord] = []
    private var reserved: [BotBridgeDiagnosticRecord] = []
    private var scheduled = false
    private var dropped: UInt64 = 0
    private var snapshotDropped: UInt64 = 0
    private var failures: UInt64 = 0 // sink queue only from here
    private var expiredFiles: UInt64 = 0
    private var evictedFiles: UInt64 = 0
    private var malformedRecords: UInt64 = 0
    private var expiredRecords: UInt64 = 0
    private var exportBusy = false // protected by lock, includes queued export preparation
    private var activeExport: URL?
    init(root: URL, queue: DispatchQueue = DispatchQueue(label: "Jerkgram.BotBridge1.sink", qos: .utility), listDirectory: @escaping (URL) throws -> [URL] = { url in
        try FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey])
    }) {
        self.root = root; self.queue = queue; self.listDirectory = listDirectory
        queue.async { self.prepare() }
    }
    func accept(_ record: BotBridgeDiagnosticRecord, reserved isReserved: Bool) {
        lock.lock()
        if isReserved {
            if reserved.count == 8 { reserved.removeFirst(); botBridgeIncrement(&snapshotDropped) }
            reserved.append(record)
        } else if pending.count < 248 { pending.append(record) }
        else { botBridgeIncrement(&dropped) }
        if !scheduled { scheduled = true; queue.async { self.drain() } }
        lock.unlock()
    }
    private func prepare() {
        do {
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try prune()
            try removeStaleExports()
        } catch { botBridgeIncrement(&failures) }
    }
    private func files() throws -> [URL] {
        return try listDirectory(root).filter { $0.lastPathComponent.hasPrefix("events-") && $0.pathExtension == "jsonl" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
    private func removeStaleExports() throws {
        for url in try listDirectory(root) where url.lastPathComponent.hasPrefix("BOTBRIDGE1-export-") && url.pathExtension == "json" {
            try FileManager.default.removeItem(at: url)
        }
    }
    private func prune() throws {
        let now = Date().timeIntervalSince1970
        var retained: [URL] = []
        for url in try files() {
            let values = try url.resourceValues(forKeys: [.contentModificationDateKey, .fileSizeKey])
            if now - (values.contentModificationDate?.timeIntervalSince1970 ?? 0) > 86400 || (values.fileSize ?? Int.max) > 256 * 1024 {
                try FileManager.default.removeItem(at: url); botBridgeIncrement(&expiredFiles)
            } else { retained.append(url) }
        }
        while retained.count > 8 {
            try FileManager.default.removeItem(at: retained.removeFirst()); botBridgeIncrement(&evictedFiles)
        }
        // Atomic appends refresh mtime. Inspect physical records on every lazy
        // access instead of allowing steady low-volume traffic to extend their TTL.
        // Enforce the file/byte caps first: at most eight 256 KiB files are decoded.
        let cutoff = now - 86400
        let decoder = JSONDecoder()
        for url in retained {
            let bytes = try Data(contentsOf: url)
            guard bytes.count <= 256 * 1024 else { throw CocoaError(.fileReadCorruptFile) }
            var kept = Data()
            var expired: UInt64 = 0
            var malformed: UInt64 = 0
            for line in bytes.split(separator: 10) {
                guard line.count <= 32 * 1024, let value = try? decoder.decode(BotBridgeDiagnosticRecord.self, from: Data(line)), value.schema == 1, value.inFlight.count <= 64, value.flags.rawValue >= 0, value.flags.rawValue <= 15 else { botBridgeIncrement(&malformed); continue }
                guard value.wall >= cutoff else { botBridgeIncrement(&expired); continue }
                kept.append(contentsOf: line); kept.append(10)
            }
            if kept != bytes {
                try kept.write(to: url, options: .atomic)
                // Count physical losses only after the replacement succeeds.
                self.expiredRecords += min(expired, UInt64.max - self.expiredRecords)
                self.malformedRecords += min(malformed, UInt64.max - self.malformedRecords)
            }
        }
    }
    private func take() -> [BotBridgeDiagnosticRecord] {
        lock.lock(); let values = (pending + reserved).sorted { $0.wall < $1.wall }; pending.removeAll(keepingCapacity: true); reserved.removeAll(keepingCapacity: true); scheduled = false; lock.unlock()
        return values
    }
    @discardableResult private func drain() -> Bool {
        let values = take(); guard !values.isEmpty else { return true }
        do {
            // No write is permitted until retention has actually been enumerated.
            try prune()
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            var urls = try files()
            var url = urls.last ?? newFile()
            var bytes = Data()
            if !urls.isEmpty { bytes = try Data(contentsOf: url) }
            for record in values {
                let encoded = try encoder.encode(record)
                guard encoded.count <= 32 * 1024 else { throw CocoaError(.fileWriteUnknown) }
                var line = encoded; line.append(10)
                if bytes.count + line.count > 256 * 1024 {
                    try bytes.write(to: url, options: .atomic)
                    url = newFile(); bytes = Data()
                    urls = try files()
                    while urls.count >= 8 {
                        try FileManager.default.removeItem(at: urls.removeFirst()); botBridgeIncrement(&evictedFiles)
                    }
                }
                bytes.append(line)
            }
            try bytes.write(to: url, options: .atomic)
            try prune()
            return true
        } catch { botBridgeIncrement(&failures); return false }
    }
    private func newFile() -> URL { return root.appendingPathComponent("events-\(String(format: "%020.0f", Date().timeIntervalSince1970 * 1000000))-\(UUID().uuidString).jsonl") }
    func export(completion: @escaping (Result<URL, BotBridgeDiagnosticExportError>) -> Void) {
        lock.lock()
        guard !exportBusy else { lock.unlock(); queue.async { completion(.failure(.busy)) }; return }
        exportBusy = true
        lock.unlock()
        queue.async {
            guard self.drain() else { self.unlockExport(); completion(.failure(.storage)); return }
            var records: [BotBridgeDiagnosticRecord] = []
            let cutoff = Date().timeIntervalSince1970 - 86400
            do {
                try self.prune()
                try self.removeStaleExports()
                for url in try self.files() {
                    let bytes = try Data(contentsOf: url)
                    guard bytes.count <= 256 * 1024 else { throw CocoaError(.fileReadCorruptFile) }
                    for line in bytes.split(separator: 10) {
                        guard line.count <= 32 * 1024, let value = try? JSONDecoder().decode(BotBridgeDiagnosticRecord.self, from: Data(line)), value.schema == 1, value.inFlight.count <= 64, value.flags.rawValue >= 0, value.flags.rawValue <= 15 else { botBridgeIncrement(&self.malformedRecords); continue }
                        guard value.wall >= cutoff else { botBridgeIncrement(&self.expiredRecords); continue }
                        records.append(value)
                    }
                }
            } catch { botBridgeIncrement(&self.failures); self.unlockExport(); completion(.failure(.storage)); return }
            self.lock.lock(); let dropped = self.dropped; let snapshotDropped = self.snapshotDropped; self.lock.unlock()
            let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
            let originalCount = records.count
            var output: Data?
            repeat {
                let envelope = BotBridgeDiagnosticEnvelope(status: records.isEmpty ? "no_captured_sessions" : "captured_sessions_with_explicit_coverage_limits", records: records, sinkDropped: dropped, snapshotDropped: snapshotDropped, storageFailures: self.failures, storageLossCountUnknown: self.failures > 0, exportTruncated: originalCount - records.count, retentionExpiredFiles: self.expiredFiles, rotationEvictedFiles: self.evictedFiles, malformedRecords: self.malformedRecords, retentionExpiredRecords: self.expiredRecords, admissionDenied: BotBridgeDiagnosticRegistry.shared.admissionLoss)
                output = try? encoder.encode(envelope)
                if let value = output, value.count <= 2 * 1024 * 1024 { break }
                if records.isEmpty { self.unlockExport(); completion(.failure(.storage)); return }
                records.removeFirst(min(records.count, 64))
            } while true
            let url = self.root.appendingPathComponent("BOTBRIDGE1-export-\(UUID().uuidString).json")
            do { try output!.write(to: url, options: .atomic); self.activeExport = url; completion(.success(url)) }
            catch { botBridgeIncrement(&self.failures); self.unlockExport(); completion(.failure(.storage)) }
        }
    }
    private func unlockExport() { lock.lock(); exportBusy = false; lock.unlock() }
    func release(_ url: URL) {
        queue.async { guard self.activeExport == url else { return }; try? FileManager.default.removeItem(at: url); self.activeExport = nil; self.unlockExport() }
    }
}
public func jerkgramExportBotBridgeDiagnostics(completion: @escaping (Result<URL, BotBridgeDiagnosticExportError>) -> Void) { BotBridgeDiagnosticSink.shared.export(completion: completion) }
public func jerkgramReleaseBotBridgeDiagnosticExport(_ url: URL) { BotBridgeDiagnosticSink.shared.release(url) }
// END BOTBRIDGE DIAGNOSTICS

// Typed adapter: no Codable progress object, owner/peer id, API payload, or error
// crosses into diagnostics. Tuple values are observations only.
private func botBridgeDiagnosticTuple(_ value: BotBridgeCursor?) -> BotBridgeDiagnosticTuple? {
    guard let value = value else { return nil }
    return BotBridgeDiagnosticTuple(pts: value.pts, qts: value.qts, date: value.date, seq: value.seq)
}
func botBridgeDiagnosticHistory(_ event: BotBridgeHistoryEvent) -> (history: BotBridgeDiagnosticHistory, phase: BotBridgeDiagnosticPhase) {
    let phase: BotBridgeDiagnosticPhase
    switch event.phase {
    case .started: phase = .historyStart
    case .reserved, .committed: phase = .historyPage
    case .terminal: phase = .historyEnd
    case .handoff: phase = .handoff
    case .restoredTerminal: phase = .restoredTerminal
    }
    let history = BotBridgeDiagnosticHistory(original: botBridgeDiagnosticTuple(event.original), candidate: botBridgeDiagnosticTuple(event.candidate), lastRetrieval: botBridgeDiagnosticTuple(event.retrieval), observedLive: botBridgeDiagnosticTuple(event.live), reservedAttempts: event.reservedRequests, committedPages: event.committedPages, examinedMessages: event.examinedMessages, insertedMessages: event.insertedMessages, insertedPeers: event.insertedPeers, insertedChats: event.insertedChats, insertedUsers: event.insertedUsers, skipped: event.skipped, unsupported: event.unsupported, historicalDeletionObserved: event.historicalDeletionObserved, deleteIdsObserved: event.deleteIdsObserved, missingReferences: event.missingReferences, reason: event.reason.flatMap { BotBridgeDiagnosticHistoryReason(rawValue: $0.rawValue) }, modernProcessingResumed: event.phase == .handoff || event.phase == .restoredTerminal)
    return (history, phase)
}
extension BotBridgeDiagnosticOwner {
    func history(_ event: BotBridgeHistoryEvent) {
        let adapted = botBridgeDiagnosticHistory(event)
        self.history(adapted.history, phase: adapted.phase)
    }
}
// Call only at a real modern worker request site, while resolved peer and explicit
// attributes are already available. Forum routing alone is never a user reply.
func botBridgeOperationContext(network: Network, peer: Peer, attributes: [MessageAttribute], hasText: Bool) -> BotBridgeOperationContext? {
    var flags: BotBridgeOperationFlags = []
    if hasText { flags.insert(.text) }
    if attributes.contains(where: { $0 is ReplyMessageAttribute || $0 is ReplyStoryAttribute }) { flags.insert(.reply) }
    if let channel = peer as? TelegramChannel, case .broadcast = channel.info { flags.insert(.post) }
    return network.botBridgeRegistration.context(flags: flags)
}
