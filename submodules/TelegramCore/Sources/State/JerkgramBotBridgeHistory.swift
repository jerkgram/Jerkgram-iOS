import Foundation
import Postbox
import SwiftSignalKit
internal import TelegramApi

// BEGIN BOTBRIDGE POLICY
// Foundation-only policy is also compiled verbatim by the focused native fixtures.
struct BotBridgeCursor: Codable, Equatable {
    let pts: Int32
    let qts: Int32
    let date: Int32
    let seq: Int32

    var isValid: Bool { return pts >= 0 && qts >= 0 && date >= 0 && seq >= 0 }

    func candidate(unread: Int32) -> BotBridgeCursor? {
        guard isValid, unread > 0, pts > 1 else { return nil }
        return BotBridgeCursor(pts: Int32(max(1, Int64(pts) - Int64(unread))), qts: qts, date: date, seq: seq)
    }

    func advances(_ previous: BotBridgeCursor) -> Bool {
        return isValid && self != previous && pts >= previous.pts && qts >= previous.qts && date >= previous.date && seq >= previous.seq
    }
}

enum BotBridgeHistoryReason: String, Codable {
    case completed, noCandidate, tooLong, limit, deadline, clockChanged, corrupt
    case nonadvancing, rpcError, timeout, cancelled, replaced, loggedOut, softReset, interruptedState
}

enum BotBridgeHistoryRequest: Equatable {
    case state
    case difference(BotBridgeCursor)
}

struct BotBridgeHistoryProgress: Codable, Equatable {
    static let maxDeleteIdsPerPage = 20000
    let schema: Int
    let owner: Int64
    let peer: Int64
    let testing: Bool
    let generation: String
    var started: Double?
    var deadline: Double?
    var lastWall: Double?
    var original: BotBridgeCursor?
    var candidate: BotBridgeCursor?
    var next: BotBridgeCursor?
    var softResetRecoveryVersion: Int32 = 0
    var historyPolicyVersion: Int32 = JerkgramBotReplayPolicy.version
    var historyWindow: Int32 = 0
    var historyWindowStart: BotBridgeCursor?
    var reservedState = false
    var reservedPages = 0
    var committedPages = 0
    var examined = 0
    var inserted = 0
    var insertedPeers = 0
    var insertedUsers = 0
    var insertedChats = 0
    var deleteIdsObserved = 0
    var skipped = 0
    var unsupported = 0
    var deletions = 0
    var missingReferences = 0
    var terminal: BotBridgeHistoryReason?

    init(owner: Int64, peer: Int64, testing: Bool, generation: String) {
        self.schema = 1
        self.owner = owner
        self.peer = peer
        self.testing = testing
        self.generation = generation
    }

    // Postbox supports keyed Int32 primitives, but not Codable Int or raw enums.
    private enum CodingKeys: String, CodingKey {
        case schema
        case owner
        case peer
        case testing
        case generation
        case started
        case deadline
        case lastWall
        case original
        case candidate
        case next
        case softResetRecoveryVersion
        case historyPolicyVersion
        case historyWindow
        case historyWindowStart
        case reservedState
        case reservedPages
        case committedPages
        case examined
        case inserted
        case insertedPeers
        case insertedUsers
        case insertedChats
        case deleteIdsObserved
        case skipped
        case unsupported
        case deletions
        case missingReferences
        case terminal
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        schema = Int(try container.decode(Int32.self, forKey: .schema))
        owner = try container.decode(Int64.self, forKey: .owner)
        peer = try container.decode(Int64.self, forKey: .peer)
        testing = try container.decode(Bool.self, forKey: .testing)
        generation = try container.decode(String.self, forKey: .generation)
        started = try container.decodeIfPresent(Double.self, forKey: .started)
        deadline = try container.decodeIfPresent(Double.self, forKey: .deadline)
        lastWall = try container.decodeIfPresent(Double.self, forKey: .lastWall)
        original = try container.decodeIfPresent(BotBridgeCursor.self, forKey: .original)
        candidate = try container.decodeIfPresent(BotBridgeCursor.self, forKey: .candidate)
        next = try container.decodeIfPresent(BotBridgeCursor.self, forKey: .next)
        softResetRecoveryVersion = try container.decodeIfPresent(Int32.self, forKey: .softResetRecoveryVersion) ?? 0
        historyPolicyVersion = try container.decodeIfPresent(Int32.self, forKey: .historyPolicyVersion) ?? 1
        historyWindow = try container.decodeIfPresent(Int32.self, forKey: .historyWindow) ?? 0
        historyWindowStart = try container.decodeIfPresent(BotBridgeCursor.self, forKey: .historyWindowStart)
        reservedState = try container.decode(Bool.self, forKey: .reservedState)
        reservedPages = Int(try container.decode(Int32.self, forKey: .reservedPages))
        committedPages = Int(try container.decode(Int32.self, forKey: .committedPages))
        examined = Int(try container.decode(Int32.self, forKey: .examined))
        inserted = Int(try container.decode(Int32.self, forKey: .inserted))
        insertedPeers = Int(try container.decode(Int32.self, forKey: .insertedPeers))
        insertedUsers = Int(try container.decode(Int32.self, forKey: .insertedUsers))
        insertedChats = Int(try container.decode(Int32.self, forKey: .insertedChats))
        deleteIdsObserved = Int(try container.decode(Int32.self, forKey: .deleteIdsObserved))
        skipped = Int(try container.decode(Int32.self, forKey: .skipped))
        unsupported = Int(try container.decode(Int32.self, forKey: .unsupported))
        deletions = Int(try container.decode(Int32.self, forKey: .deletions))
        missingReferences = Int(try container.decode(Int32.self, forKey: .missingReferences))
        if let rawValue = try container.decodeIfPresent(String.self, forKey: .terminal) {
            guard let reason = BotBridgeHistoryReason(rawValue: rawValue) else {
                throw DecodingError.dataCorruptedError(forKey: .terminal, in: container, debugDescription: "Unknown bot bridge terminal reason")
            }
            terminal = reason
        } else {
            terminal = nil
        }
        guard isValid else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Invalid bot bridge progress"))
        }
    }

    func encode(to encoder: Encoder) throws {
        guard isValid else {
            throw EncodingError.invalidValue(self, .init(codingPath: encoder.codingPath, debugDescription: "Invalid bot bridge progress"))
        }
        func wireInt32(_ value: Int, key: CodingKeys) throws -> Int32 {
            guard let result = Int32(exactly: value) else {
                throw EncodingError.invalidValue(value, .init(codingPath: encoder.codingPath + [key], debugDescription: "Bot bridge counter exceeds Int32"))
            }
            return result
        }
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(try wireInt32(schema, key: .schema), forKey: .schema)
        try container.encode(owner, forKey: .owner)
        try container.encode(peer, forKey: .peer)
        try container.encode(testing, forKey: .testing)
        try container.encode(generation, forKey: .generation)
        try container.encodeIfPresent(started, forKey: .started)
        try container.encodeIfPresent(deadline, forKey: .deadline)
        try container.encodeIfPresent(lastWall, forKey: .lastWall)
        try container.encodeIfPresent(original, forKey: .original)
        try container.encodeIfPresent(candidate, forKey: .candidate)
        try container.encodeIfPresent(next, forKey: .next)
        try container.encode(softResetRecoveryVersion, forKey: .softResetRecoveryVersion)
        try container.encode(historyPolicyVersion, forKey: .historyPolicyVersion)
        try container.encode(historyWindow, forKey: .historyWindow)
        try container.encodeIfPresent(historyWindowStart, forKey: .historyWindowStart)
        try container.encode(reservedState, forKey: .reservedState)
        try container.encode(try wireInt32(reservedPages, key: .reservedPages), forKey: .reservedPages)
        try container.encode(try wireInt32(committedPages, key: .committedPages), forKey: .committedPages)
        try container.encode(try wireInt32(examined, key: .examined), forKey: .examined)
        try container.encode(try wireInt32(inserted, key: .inserted), forKey: .inserted)
        try container.encode(try wireInt32(insertedPeers, key: .insertedPeers), forKey: .insertedPeers)
        try container.encode(try wireInt32(insertedUsers, key: .insertedUsers), forKey: .insertedUsers)
        try container.encode(try wireInt32(insertedChats, key: .insertedChats), forKey: .insertedChats)
        try container.encode(try wireInt32(deleteIdsObserved, key: .deleteIdsObserved), forKey: .deleteIdsObserved)
        try container.encode(try wireInt32(skipped, key: .skipped), forKey: .skipped)
        try container.encode(try wireInt32(unsupported, key: .unsupported), forKey: .unsupported)
        try container.encode(try wireInt32(deletions, key: .deletions), forKey: .deletions)
        try container.encode(try wireInt32(missingReferences, key: .missingReferences), forKey: .missingReferences)
        try container.encodeIfPresent(terminal?.rawValue, forKey: .terminal)
    }

    // Postbox uses try! around Encodable. Validate before crossing that boundary,
    // including failure paths which may have marked an invalid value corrupt.
    var validatedForStorage: BotBridgeHistoryProgress {
        if isValid { return self }
        let validGeneration = !generation.isEmpty && generation.utf8.count <= 64
        var fallback = BotBridgeHistoryProgress(owner: owner, peer: peer, testing: testing, generation: validGeneration ? generation : UUID().uuidString)
        // A failed write must never make a consumed/unknown recovery eligible again.
        fallback.softResetRecoveryVersion = 1
        fallback.terminal = .corrupt
        return fallback
    }

    var isValid: Bool {
        guard schema == 1, (1...2).contains(historyPolicyVersion), historyWindow >= 0,
            (0...1).contains(softResetRecoveryVersion), !generation.isEmpty, generation.utf8.count <= 64,
            reservedPages >= 0, reservedPages <= 32, committedPages >= 0, committedPages <= reservedPages,
            examined >= 0, examined <= historyMessageLimit, inserted >= 0, inserted <= examined,
            insertedPeers >= 0, insertedPeers <= 320000, insertedUsers >= 0, insertedUsers <= 320000, insertedChats >= 0, insertedChats <= 320000, insertedUsers + insertedChats == insertedPeers,
            deleteIdsObserved >= 0, deleteIdsObserved <= 640001,
            skipped >= 0, skipped <= examined, unsupported >= 0, unsupported <= 800000,
            deletions >= 0, deletions <= 320000, missingReferences >= 0, missingReferences <= 3200000 else { return false }
        if let started = started {
            guard started.isFinite, let deadline = deadline, deadline.isFinite, deadline == started + 120,
                let lastWall = lastWall, lastWall.isFinite, lastWall >= started, reservedState else { return false }
        } else if deadline != nil || lastWall != nil || reservedState || original != nil || candidate != nil || next != nil || reservedPages != 0 || committedPages != 0 {
            return false
        }
        if let original = original {
            guard original.isValid, reservedState else { return false }
            if let candidate = candidate {
                guard candidate.isValid, candidate.pts >= 1, candidate.pts <= original.pts,
                    historyPolicyVersion != 2 || candidate == JerkgramBotReplayPolicy.seed(original),
                    historyPolicyVersion == 2 || (candidate.qts == original.qts && candidate.date == original.date && candidate.seq == original.seq),
                    let next = next, next.isValid, next.pts >= candidate.pts,
                    next.qts >= candidate.qts, next.date >= candidate.date, next.seq >= candidate.seq else { return false }
            } else if next != nil || terminal != .noCandidate { return false }
        } else if candidate != nil || next != nil || reservedPages != 0 || committedPages != 0 { return false }
        if let start = historyWindowStart {
            guard historyPolicyVersion == 2, start.isValid, let next,
                next.pts >= start.pts, next.qts >= start.qts, next.date >= start.date, next.seq >= start.seq else { return false }
        } else if historyWindow != 0 { return false }
        return true
    }

    mutating func checkTime(now: Double) -> Bool {
        guard terminal == nil else { return false }
        guard isValid, now.isFinite else { terminal = .corrupt; return false }
        if let lastWall = lastWall, now < lastWall { terminal = .clockChanged; return false }
        if let deadline = deadline, now >= deadline { terminal = .deadline; return false }
        if started != nil { lastWall = now }
        return true
    }

    // Called only inside the preference transaction, before subscribing to Network.
    // A reservation survives a crash; page commits are a different counter.
    mutating func reserve(now: Double) -> BotBridgeHistoryRequest? {
        let _ = resumeHistoryWindow(now: now)
        guard checkTime(now: now) else { return nil }
        if original == nil {
            guard !reservedState else { terminal = .interruptedState; return nil }
            started = now
            deadline = now + 120
            lastWall = now
            reservedState = true
            return .state
        }
        guard let next = next else { terminal = .corrupt; return nil }
        guard reservedPages < 32 else { terminal = .limit; return nil }
        reservedPages += 1
        return .difference(next)
    }

    mutating func acceptState(_ cursor: BotBridgeCursor, unread: Int32, now: Double) -> Bool {
        guard checkTime(now: now), original == nil, reservedState, cursor.isValid, unread >= 0 else {
            if terminal == nil { terminal = .corrupt }
            return false
        }
        original = cursor
        candidate = historyPolicyVersion == 2 ? JerkgramBotReplayPolicy.seed(cursor) : cursor.candidate(unread: unread)
        historyWindowStart = historyPolicyVersion == 2 ? candidate : nil
        next = candidate
        if candidate == nil { terminal = .noCandidate }
        return true
    }

    static func withinPageBounds(messages: Int, peers: Int, updates: Int, examined: Int, limit: Int = 20000) -> Bool {
        return messages >= 0 && messages <= 5000 && peers >= 0 && peers <= 10000 && updates >= 0 && updates <= 10000 && examined >= 0 && examined <= limit && messages <= limit - examined
    }

    mutating func commit(next cursor: BotBridgeCursor, final: Bool, examined pageExamined: Int, inserted pageInserted: Int, peers: Int, users: Int = 0, skipped pageSkipped: Int, unsupported pageUnsupported: Int, deletions pageDeletions: Int, missing: Int, now: Double) -> Bool {
        guard checkTime(now: now), let previous = next, committedPages < reservedPages else {
            if terminal == nil { terminal = .corrupt }
            return false
        }
        guard cursor.isValid, cursor.pts >= previous.pts, cursor.qts >= previous.qts, cursor.date >= previous.date, cursor.seq >= previous.seq,
            final || cursor.advances(previous) else { terminal = .nonadvancing; return false }
        guard Self.withinPageBounds(messages: pageExamined, peers: peers, updates: 0, examined: examined, limit: historyMessageLimit),
            pageInserted >= 0, pageInserted <= pageExamined, users >= 0, users <= peers, pageSkipped >= 0, pageSkipped <= pageExamined,
            pageUnsupported >= 0, pageUnsupported <= 25000, pageDeletions >= 0, pageDeletions <= 10000,
            missing >= 0, missing <= 100000 else { terminal = .limit; return false }
        next = cursor
        committedPages += 1
        examined += pageExamined
        inserted += pageInserted
        insertedPeers += peers
        insertedUsers += users
        insertedChats += peers - users
        skipped += pageSkipped
        unsupported += pageUnsupported
        deletions += pageDeletions
        missingReferences += missing
        if final { terminal = .completed }
        return true
    }
}

// One repair for the exact retained initial-state interruption seen in Build 179.
// The old generation consumed one request; this new generation grants at most 33
// more requests (34 cumulative) and its normal fresh 120-second wall window.
func botBridgeRecoverInitialSoftReset(_ progress: BotBridgeHistoryProgress, owner: Int64, accountPeerId: Int64, testing: Bool) -> BotBridgeHistoryProgress {
    guard progress.isValid, progress.owner == owner, progress.peer == accountPeerId, progress.testing == testing,
        progress.terminal == .softReset, progress.softResetRecoveryVersion == 0,
        progress.reservedState, progress.original == nil, progress.candidate == nil, progress.next == nil,
        progress.reservedPages == 0, progress.committedPages == 0,
        progress.examined == 0, progress.inserted == 0, progress.insertedPeers == 0,
        progress.insertedUsers == 0, progress.insertedChats == 0, progress.deleteIdsObserved == 0,
        progress.skipped == 0, progress.unsupported == 0, progress.deletions == 0, progress.missingReferences == 0 else { return progress }
    var recovered = BotBridgeHistoryProgress(owner: owner, peer: accountPeerId, testing: testing, generation: UUID().uuidString)
    recovered.softResetRecoveryVersion = 1
    return recovered
}

// Transactions use this token too: queue teardown cannot admit a stale page.
final class BotBridgeLifetime {
    private let lock = NSLock()
    private var active = true
    var isActive: Bool { lock.lock(); defer { lock.unlock() }; return active }
    func cancel() { lock.lock(); active = false; lock.unlock() }
}

final class BotBridgeOnceGate {
    private let lock = NSLock()
    private var open = true
    var isOpen: Bool { lock.lock(); defer { lock.unlock() }; return open }
    @discardableResult func finish() -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard open else { return false }
        open = false
        return true
    }
}
// END BOTBRIDGE POLICY

// Task 2 receives only finite reasons, numeric state/counters; never an account,
// message, API object, token, peer identifier, or raw RPC error.
struct BotBridgeHistoryEvent {
    enum Phase { case started, reserved, committed, terminal, handoff, restoredTerminal }
    let phase: Phase
    let original: BotBridgeCursor?
    let candidate: BotBridgeCursor?
    let retrieval: BotBridgeCursor?
    let live: BotBridgeCursor?
    let reservedRequests: Int
    let committedPages: Int
    let examinedMessages: Int
    let insertedMessages: Int
    let insertedPeers: Int
    let insertedUsers: Int
    let insertedChats: Int
    let deleteIdsObserved: Int
    let skipped: Int
    let unsupported: Int
    let historicalDeletionObserved: Int
    let missingReferences: Int
    let reason: BotBridgeHistoryReason?
    // Physical preexisting deletions without tombstones are never fully covered.
    let deletionCoverageLimited = true
}

private let botBridgeHistoryKey: ValueBoxKey = {
    let key = ValueBoxKey(length: 4)
    key.setInt32(0, value: 0x4A470002)
    return key
}()

// Called only from the successful, confirmed bot authorization transaction.
func jerkgramRenewBotBridgeGeneration(transaction: Transaction, recordId: Int64, user: TelegramUser, testing: Bool) {
    guard user.botInfo != nil else { return }
    let progress = BotBridgeHistoryProgress(owner: recordId, peer: user.id.toInt64(), testing: testing, generation: UUID().uuidString)
    botBridgeWriteProgress(progress, transaction: transaction)
}

private func botBridgeValidatedAccount(transaction: Transaction, accountPeerId: PeerId, testing: Bool) -> Bool {
    guard let authorized = transaction.getState() as? AuthorizedAccountState,
        authorized.peerId == accountPeerId, authorized.isTestingEnvironment == testing,
        let user = transaction.getPeer(accountPeerId) as? TelegramUser, user.botInfo != nil else { return false }
    return true
}

private func botBridgeReadProgress(transaction: Transaction, owner: Int64, accountPeerId: PeerId, testing: Bool) -> BotBridgeHistoryProgress {
    if let entry = transaction.getPreferencesEntry(key: botBridgeHistoryKey) {
        if let progress = entry.get(BotBridgeHistoryProgress.self), progress.owner == owner,
            progress.peer == accountPeerId.toInt64(), progress.testing == testing, progress.isValid {
            return progress
        }
        // Fail closed for an unreadable or different owner's record. A successful
        // authorization transaction is the only path that grants a new generation.
        var invalid = BotBridgeHistoryProgress(owner: owner, peer: accountPeerId.toInt64(), testing: testing, generation: UUID().uuidString)
        invalid.softResetRecoveryVersion = 1
        invalid.terminal = .corrupt
        return invalid
    }
    // Existing bots initialize once, after validation of this Account record.
    return BotBridgeHistoryProgress(owner: owner, peer: accountPeerId.toInt64(), testing: testing, generation: UUID().uuidString)
}

func jerkgramPrepareBotBridgeHistory(transaction: Transaction, owner: Int64, accountPeerId: PeerId, lifetime: BotBridgeLifetime) -> BotBridgeHistoryProgress? {
    guard lifetime.isActive, let authorized = transaction.getState() as? AuthorizedAccountState,
        botBridgeValidatedAccount(transaction: transaction, accountPeerId: accountPeerId, testing: authorized.isTestingEnvironment) else { return nil }
    let retained = botBridgeReadProgress(transaction: transaction, owner: owner, accountPeerId: accountPeerId, testing: authorized.isTestingEnvironment)
    let recovered = botBridgeRecoverInitialSoftReset(retained, owner: owner, accountPeerId: accountPeerId.toInt64(), testing: authorized.isTestingEnvironment)
    let progress = JerkgramBotReplayPolicy.upgrade(recovered, owner: owner, peer: accountPeerId.toInt64(), testing: authorized.isTestingEnvironment)
    // Persist the one-time marker in this transaction before admission/dispatch.
    botBridgeWriteProgress(progress, transaction: transaction)
    return progress
}

// Observation only, from the same bounded existing Postbox transactions.
func botBridgeObservedLive(transaction: Transaction) -> BotBridgeCursor? {
    guard let state = (transaction.getState() as? AuthorizedAccountState)?.state else { return nil }
    return BotBridgeCursor(pts: state.pts, qts: state.qts, date: state.date, seq: state.seq)
}

private func botBridgeWriteProgress(_ progress: BotBridgeHistoryProgress, transaction: Transaction) {
    transaction.updatePreferencesEntry(key: botBridgeHistoryKey, { _ in PreferencesEntry(progress.validatedForStorage) })
}

private func botBridgeCursor(_ state: Api.updates.State) -> (BotBridgeCursor, Int32) {
    switch state {
    case let .state(data):
        return (BotBridgeCursor(pts: data.pts, qts: data.qts, date: data.date, seq: data.seq), data.unreadCount)
    }
}

private struct BotBridgeHistoryPage {
    let cursor: BotBridgeCursor
    let final: Bool
    let messages: [Api.Message]
    let users: [Api.User]
    let chats: [Api.Chat]
    let updates: [Api.Update]
    let encryptedCount: Int
}

// Decoding already happened in Network. Bounds below precede new working arrays.
private func botBridgePage(_ difference: Api.updates.Difference, previous: BotBridgeCursor) -> BotBridgeHistoryPage? {
    switch difference {
    case let .difference(data):
        return BotBridgeHistoryPage(cursor: botBridgeCursor(data.state).0, final: true, messages: data.newMessages, users: data.users, chats: data.chats, updates: data.otherUpdates, encryptedCount: data.newEncryptedMessages.count)
    case let .differenceSlice(data):
        return BotBridgeHistoryPage(cursor: botBridgeCursor(data.intermediateState).0, final: false, messages: data.newMessages, users: data.users, chats: data.chats, updates: data.otherUpdates, encryptedCount: data.newEncryptedMessages.count)
    case let .differenceEmpty(data):
        return BotBridgeHistoryPage(cursor: BotBridgeCursor(pts: previous.pts, qts: previous.qts, date: data.date, seq: data.seq), final: true, messages: [], users: [], chats: [], updates: [], encryptedCount: 0)
    case .differenceTooLong:
        return nil
    }
}

private func botBridgeReplyPeerIds(_ message: Api.Message) -> Set<PeerId> {
    let reply: Api.MessageReplyHeader?
    switch message {
    case let .message(data): reply = data.replyTo
    case let .messageService(data): reply = data.replyTo
    default: reply = nil
    }
    var result = Set<PeerId>()
    if let reply = reply {
        switch reply {
        case let .messageReplyHeader(data):
            if let peer = data.replyToPeerId { result.insert(peer.peerId) }
            if let header = data.replyFrom, case let .messageFwdHeader(forward) = header {
                if let peer = forward.fromId { result.insert(peer.peerId) }
                if let peer = forward.savedFromPeer { result.insert(peer.peerId) }
                if let peer = forward.savedFromId { result.insert(peer.peerId) }
            }
        case let .messageReplyStoryHeader(data): result.insert(data.peer.peerId)
        }
    }
    return result
}

// Replay is older than live peer metadata. Fill only a missing personal user
// hash required by apiInputPeer; never copy old names, flags or permissions over
// a current peer. Minimal/generic public hashes cannot authorize modern writes.
func botBridgeMergeHistoricalPeer(_ current: Peer?, _ proposed: Peer) -> Peer {
    guard let current else { return proposed }
    guard current.id == proposed.id,
        let currentUser = current as? TelegramUser, currentUser.accessHash == nil,
        let proposedUser = proposed as? TelegramUser, let accessHash = proposedUser.accessHash,
        case .personal = accessHash, accessHash.value != 0 else { return current }
    return currentUser.withUpdatedAccessHash(accessHash)
}

// This is storage-only. It neither constructs mutable live state nor replays updates.
// Progress and messages are committed by the same caller-owned Postbox transaction.
private func importBotBridgeHistoryPage(transaction: Transaction, page: BotBridgeHistoryPage, expected: BotBridgeHistoryProgress, accountPeerId: PeerId, removed: MessagesRemovedContext, now: Double, lifetime: BotBridgeLifetime, requestGate: BotBridgeOnceGate) -> BotBridgeHistoryProgress? {
    guard lifetime.isActive, requestGate.isOpen,
        botBridgeValidatedAccount(transaction: transaction, accountPeerId: accountPeerId, testing: expected.testing),
        let current = transaction.getPreferencesEntry(key: botBridgeHistoryKey)?.get(BotBridgeHistoryProgress.self), current == expected else { return nil }
    var progress = current
    guard progress.checkTime(now: now) else { botBridgeWriteProgress(progress, transaction: transaction); return progress }
    guard BotBridgeHistoryProgress.withinPageBounds(messages: page.messages.count, peers: page.users.count + page.chats.count, updates: page.updates.count, examined: progress.examined, limit: progress.historyMessageLimit), page.encryptedCount <= 10000 else {
        progress.terminal = .limit; botBridgeWriteProgress(progress, transaction: transaction); return progress
    }
    guard let previous = progress.next, page.cursor.isValid,
        page.cursor.pts >= previous.pts, page.cursor.qts >= previous.qts, page.cursor.date >= previous.date, page.cursor.seq >= previous.seq,
        page.final || page.cursor.advances(previous) else {
        progress.terminal = .nonadvancing; botBridgeWriteProgress(progress, transaction: transaction); return progress
    }
    // Inspect vector lengths before allocating sets; a single Update may contain
    // arbitrarily many IDs. Parent-approved refinement: 20,000 IDs per page.
    var deleteIdCount = 0
    for update in page.updates {
        let count: Int
        switch update {
        case let .updateDeleteMessages(data): count = data.messages.count
        case let .updateDeleteChannelMessages(data): count = data.messages.count
        default: count = 0
        }
        if count > BotBridgeHistoryProgress.maxDeleteIdsPerPage - deleteIdCount {
            progress.deleteIdsObserved += BotBridgeHistoryProgress.maxDeleteIdsPerPage + 1
            progress.terminal = .limit
            botBridgeWriteProgress(progress, transaction: transaction)
            return progress
        }
        deleteIdCount += count
    }
    guard deleteIdCount <= BotBridgeHistoryProgress.maxDeleteIdsPerPage else { return nil }
    progress.deleteIdsObserved += deleteIdCount
    var deletedGlobalIds = Set<Int32>()
    var deletedChannelIds = Set<MessageId>()
    for update in page.updates {
        switch update {
        case let .updateDeleteMessages(data): deletedGlobalIds.formUnion(data.messages)
        case let .updateDeleteChannelMessages(data):
            let peerId = PeerId(namespace: Namespaces.Peer.CloudChannel, id: PeerId.Id._internalFromInt64Value(data.channelId))
            for id in data.messages { deletedChannelIds.insert(MessageId(peerId: peerId, namespace: Namespaces.Message.Cloud, id: id)) }
        default: break
        }
    }
    // Historical mutation updates only exclude absent candidates; never replay them.
    // Parse the bounded chat vector once. Current transaction metadata still wins;
    // absent user destinations do not repeatedly scan/convert unrelated chats.
    var responseChatsById: [PeerId: Peer] = [:]
    var responseChats: [Peer] = []
    for chat in page.chats {
        if let parsed = parseTelegramGroupOrChannel(chat: chat), responseChatsById[parsed.id] == nil {
            responseChatsById[parsed.id] = parsed
            responseChats.append(parsed)
        }
    }
    var candidates: [StoreMessage] = []
    var references = Set<PeerId>()
    var seen = Set<MessageId>()
    var skipped = 0
    var unsupported = page.encryptedCount
    var deletions = 0
    for apiMessage in page.messages {
        let peerIds = apiMessagePeerIds(apiMessage)
        // Current peer metadata determines forum conversion; response data is used
        // only when the peer is absent, and can never replace an existing peer.
        let peerId: PeerId?
        switch apiMessage {
        case let .message(data): peerId = data.peerId.peerId
        case let .messageService(data): peerId = data.peerId.peerId
        default: peerId = nil
        }
        let peer = peerId.flatMap { transaction.getPeer($0) ?? responseChatsById[$0] }
        let forum = (peer as? TelegramChannel)?.flags.contains(.isForum) ?? false
        guard let message = StoreMessage(apiMessage: apiMessage, accountPeerId: accountPeerId, peerIsForum: forum),
            case let .Id(id) = message.id, id.namespace == Namespaces.Message.Cloud, id.id > 0 else { unsupported += 1; continue }
        references.formUnion(peerIds)
        references.insert(id.peerId)
        guard seen.insert(id).inserted, !transaction.messageExists(id: id) else { skipped += 1; continue }
        guard removed.synchronouslyIsMessageDeletedInteractively(ids: [id]).isEmpty,
            removed.synchronouslyIsMessageDeletedRemotely(ids: [id]).isEmpty else { skipped += 1; continue }
        let isGlobal = id.peerId.namespace == Namespaces.Peer.CloudUser || id.peerId.namespace == Namespaces.Peer.CloudGroup
        if (isGlobal && deletedGlobalIds.contains(id.id)) || deletedChannelIds.contains(id) { skipped += 1; continue }
        candidates.append(message)
        references.formUnion(peerIds)
        references.formUnion(botBridgeReplyPeerIds(apiMessage))
        references.insert(id.peerId)
        if let author = message.authorId { references.insert(author) }
        if let forward = message.forwardInfo {
            if let id = forward.authorId { references.insert(id) }
            if let id = forward.sourceId { references.insert(id) }
            if let id = forward.sourceMessageId { references.insert(id.peerId) }
        }
        for attribute in message.attributes {
            references.formUnion(attribute.associatedPeerIds)
            for id in attribute.associatedMessageIds { references.insert(id.peerId) }
            for id in attribute.associatedStoryIds { references.insert(id.peerId) }
            if let reply = attribute as? ReplyMessageAttribute { references.insert(reply.messageId.peerId) }
        }
    }
    // Only count update constructors; a vector may be huge even with one update.
    for update in page.updates {
        switch update {
        case .updateDeleteMessages, .updateDeleteChannelMessages: deletions += 1
        default: unsupported += 1
        }
    }
    var peers: [Peer] = []
    var provided = Set<PeerId>()
    for user in page.users {
        let peer = TelegramUser(user: user)
        if references.contains(peer.id), provided.insert(peer.id).inserted {
            if let current = transaction.getPeer(peer.id) {
                let merged = botBridgeMergeHistoricalPeer(current, peer)
                if !merged.isEqual(current) { peers.append(merged) }
            } else { peers.append(peer) }
        }
    }
    for peer in responseChats {
        if references.contains(peer.id), transaction.getPeer(peer.id) == nil, provided.insert(peer.id).inserted { peers.append(peer) }
    }
    var missing = 0
    for id in references { if transaction.getPeer(id) == nil && !provided.contains(id) { missing += 1 } }
    // Validate every prospective progress change before mutating the transaction.
    let users = peers.reduce(0) { count, peer in count + (peer is TelegramUser ? 1 : 0) }
    guard progress.commit(next: page.cursor, final: page.final, examined: page.messages.count, inserted: candidates.count, peers: peers.count, users: users, skipped: skipped, unsupported: unsupported, deletions: deletions, missing: missing, now: now) else {
        botBridgeWriteProgress(progress, transaction: transaction); return progress
    }
    guard lifetime.isActive, requestGate.isOpen else { return nil }
    transaction.updatePeersInternal(peers, update: { current, proposed in botBridgeMergeHistoricalPeer(current, proposed) })
    let _ = transaction.addHistoricalMessagesWithoutInteractiveActions(candidates)
    jerkgramIncludeBotMessagePeers(transaction: transaction, accountPeerId: accountPeerId, messages: candidates)
    botBridgeWriteProgress(progress, transaction: transaction)
    return progress
}

// Each queued custom operation has independent disposal. Generic addCustomOperation
// subscription disposal does not cancel its underlying work and is not used here.
private final class BotBridgePageLease {
    let gate = BotBridgeOnceGate()
    let work = MetaDisposable()
    var timer: SwiftSignalKit.Timer?
    private let completion: () -> Void
    init(completion: @escaping () -> Void) { self.completion = completion }
    func finish() {
        guard gate.finish() else { return }
        timer?.invalidate()
        timer = nil
        work.dispose()
        completion()
    }
    deinit { timer?.invalidate(); work.dispose() }
}

final class BotBridgeHistoryController {
    private let queue: Queue
    private let postbox: Postbox
    private let network: Network
    private let accountPeerId: PeerId
    private let owner: Int64
    private let testing: Bool
    private let removed: MessagesRemovedContext
    private let lifetime: BotBridgeLifetime
    private let wall: () -> Double
    private let monotonic: () -> Double
    private let event: (BotBridgeHistoryEvent) -> Void
    private var started = false
    private var active: BotBridgePageLease?
    private var progress: BotBridgeHistoryProgress?
    private var monotonicDeadline: Double?
    private let terminalWrite = MetaDisposable()

    init(queue: Queue, postbox: Postbox, network: Network, accountPeerId: PeerId, initialProgress: BotBridgeHistoryProgress, removed: MessagesRemovedContext, lifetime: BotBridgeLifetime, wall: @escaping () -> Double = { Date().timeIntervalSince1970 }, monotonic: @escaping () -> Double = { ProcessInfo.processInfo.systemUptime }, event: @escaping (BotBridgeHistoryEvent) -> Void = { _ in }) {
        self.queue = queue; self.postbox = postbox; self.network = network
        self.accountPeerId = accountPeerId; self.owner = initialProgress.owner; self.testing = initialProgress.testing
        self.progress = initialProgress
        self.removed = removed; self.lifetime = lifetime
        self.wall = wall; self.monotonic = monotonic; self.event = event
    }

    func observeLive(_ value: BotBridgeCursor?) { observedLive = value }

    func start() {
        assert(queue.isCurrent())
        guard !started, lifetime.isActive else { return }
        started = true
        if let progress = progress, progress.terminal != nil {
            var resumable = progress
            if !resumable.resumeHistoryWindow(now: wall()) {
                emit(.restoredTerminal, progress: progress)
                return
            }
        }
        if let progress = progress { emit(.started, progress: progress) }
        schedulePage()
    }

    func cancel(reason: BotBridgeHistoryReason) {
        // The manager invalidates lifetime synchronously at its public boundary.
        lifetime.cancel()
        active?.finish()
        active = nil
        persistTerminal(reason)
    }

    private var observedLive: BotBridgeCursor?

    private func emit(_ phase: BotBridgeHistoryEvent.Phase, progress p: BotBridgeHistoryProgress, live: BotBridgeCursor? = nil) {
        event(BotBridgeHistoryEvent(phase: phase, original: p.original, candidate: p.candidate, retrieval: p.next, live: live ?? observedLive, reservedRequests: (p.reservedState ? 1 : 0) + p.reservedPages, committedPages: p.committedPages, examinedMessages: p.examined, insertedMessages: p.inserted, insertedPeers: p.insertedPeers, insertedUsers: p.insertedUsers, insertedChats: p.insertedChats, deleteIdsObserved: p.deleteIdsObserved, skipped: p.skipped, unsupported: p.unsupported, historicalDeletionObserved: p.deletions, missingReferences: p.missingReferences, reason: p.terminal))
    }

    private func persistTerminal(_ reason: BotBridgeHistoryReason) {
        guard let expected = progress, expected.terminal == nil else { return }
        let accountPeerId = self.accountPeerId
        // The write may outlive the controller, but is bound to this exact progress
        // and authorization. It cannot mark a later generation terminal.
        terminalWrite.set((postbox.transaction { transaction -> (BotBridgeHistoryProgress, BotBridgeCursor?)? in
            guard botBridgeValidatedAccount(transaction: transaction, accountPeerId: accountPeerId, testing: expected.testing),
                var current = transaction.getPreferencesEntry(key: botBridgeHistoryKey)?.get(BotBridgeHistoryProgress.self),
                current.generation == expected.generation, current.terminal == nil else { return nil }
            current.terminal = reason
            botBridgeWriteProgress(current, transaction: transaction)
            return (current, botBridgeObservedLive(transaction: transaction))
        } |> deliverOn(queue)).start(next: { [weak self] result in
            guard let self = self, let (current, live) = result else { return }
            self.observedLive = live
            self.progress = current; self.emit(.terminal, progress: current); self.emit(.handoff, progress: current)
            self.scheduleHistoryContinuation(current)
        }))
    }

    private func scheduleHistoryContinuation(_ expected: BotBridgeHistoryProgress) {
        var probe = expected
        guard lifetime.isActive, probe.resumeHistoryWindow(now: wall()) else { return }
        monotonicDeadline = nil
        queue.after(1.0, { [weak self] in
            guard let self, self.lifetime.isActive, self.active == nil, self.progress == expected else { return }
            self.schedulePage()
        })
    }

    private func schedulePage() {
        guard lifetime.isActive, active == nil else { return }
        // Historical Network I/O must never occupy the live state manager's
        // custom-operation slot. Postbox serializes each guarded storage commit.
        let lease = BotBridgePageLease(completion: {})
        active = lease
        armWatchdog(lease)
        if lease.gate.isOpen { reserveAndDispatch(lease) }
    }

    private func armWatchdog(_ lease: BotBridgePageLease) {
        guard let progress = progress else { fail(.corrupt, lease: lease); return }
        let now = wall()
        var checked = progress
        if checked.resumeHistoryWindow(now: now) { monotonicDeadline = nil }
        guard checked.checkTime(now: now) else { fail(checked.terminal ?? .corrupt, lease: lease); return }
        let wallRemaining = (checked.deadline ?? (now + 120)) - now
        if monotonicDeadline == nil {
            monotonicDeadline = monotonic() + min(120, max(0, wallRemaining))
        }
        let remaining = min(wallRemaining, (monotonicDeadline ?? 0) - monotonic())
        guard remaining > 0 else { fail(.deadline, lease: lease); return }
        lease.timer = SwiftSignalKit.Timer(timeout: min(10, remaining), repeat: false, completion: { [weak self, weak lease] in
            guard let self = self, let lease = lease else { return }
            self.fail(remaining <= 10 ? .deadline : .timeout, lease: lease)
        }, queue: queue)
        lease.timer?.start()
    }

    private func reserveAndDispatch(_ lease: BotBridgePageLease) {
        let lifetime = self.lifetime; let owner = self.owner; let accountPeerId = self.accountPeerId; let testing = self.testing
        let now = wall(); let gate = lease.gate; let generation = progress?.generation
        let reservation = postbox.transaction { transaction -> (BotBridgeHistoryProgress, BotBridgeHistoryRequest?, BotBridgeCursor?)? in
            guard lifetime.isActive, gate.isOpen, botBridgeValidatedAccount(transaction: transaction, accountPeerId: accountPeerId, testing: testing) else { return nil }
            var progress = botBridgeReadProgress(transaction: transaction, owner: owner, accountPeerId: accountPeerId, testing: testing)
            guard progress.generation == generation else { return nil }
            let request = progress.reserve(now: now)
            botBridgeWriteProgress(progress, transaction: transaction)
            return (progress, request, botBridgeObservedLive(transaction: transaction))
        }
        // Reserve has its own disposable so a synchronous completion cannot replace
        // and dispose the subsequently installed Network request.
        let reservationWork = MetaDisposable()
        lease.work.set(reservationWork)
        reservationWork.set((reservation |> deliverOn(queue)).start(next: { [weak self, weak lease] result in
            guard let self = self, let lease = lease, lease.gate.isOpen, self.lifetime.isActive else { return }
            guard let (progress, request, live) = result else { lease.finish(); return }
            self.observedLive = live
            self.progress = progress
            guard let request = request else {
                self.emit(.terminal, progress: progress); self.emit(.handoff, progress: progress)
                lease.finish(); self.active = nil
                self.scheduleHistoryContinuation(progress)
                return
            }
            self.emit(.reserved, progress: progress)
            var dispatchProgress = progress
            guard dispatchProgress.checkTime(now: self.wall()) else { self.fail(dispatchProgress.terminal ?? .corrupt, lease: lease); return }
            let remaining = min((progress.deadline ?? 0) - self.wall(), (self.monotonicDeadline ?? 0) - self.monotonic())
            guard remaining > 0 else { self.fail(.deadline, lease: lease); return }
            // The activation watchdog remains armed; a delayed reservation never
            // grants a second timeout window or revives a closed request gate.
            self.dispatch(request, expected: progress, lease: lease)
        }))
    }

    private func dispatch(_ request: BotBridgeHistoryRequest, expected: BotBridgeHistoryProgress, lease: BotBridgePageLease) {
        // Single existing Network. No bridge retry/flood-wait policy or second poller.
        switch request {
        case .state:
            lease.work.set((network.request(Api.functions.updates.getState(), automaticFloodWait: false)
            |> deliverOn(queue)).start(next: { [weak self, weak lease] state in
                guard let self = self, let lease = lease, lease.gate.isOpen, self.lifetime.isActive else { return }
                let (cursor, unread) = botBridgeCursor(state)
                self.storeState(cursor, unread: unread, expected: expected, lease: lease)
            }, error: { [weak self, weak lease] _ in
                guard let self = self, let lease = lease else { return }; self.fail(.rpcError, lease: lease)
            }))
        case let .difference(cursor):
            lease.work.set((network.request(Api.functions.updates.getDifference(flags: 0, pts: cursor.pts, ptsLimit: nil, ptsTotalLimit: nil, date: cursor.date, qts: cursor.qts, qtsLimit: nil), automaticFloodWait: false)
            |> deliverOn(queue)).start(next: { [weak self, weak lease] difference in
                guard let self = self, let lease = lease, lease.gate.isOpen, self.lifetime.isActive else { return }
                // The first response is consumed here, never discarded or replayed
                // through a final-state builder, and never seeds the live cursor.
                guard let page = botBridgePage(difference, previous: cursor) else { self.fail(.tooLong, lease: lease); return }
                self.storePage(page, expected: expected, lease: lease)
            }, error: { [weak self, weak lease] _ in
                guard let self = self, let lease = lease else { return }; self.fail(.rpcError, lease: lease)
            }))
        }
    }

    private func storeState(_ cursor: BotBridgeCursor, unread: Int32, expected: BotBridgeHistoryProgress, lease: BotBridgePageLease) {
        let lifetime = self.lifetime; let accountPeerId = self.accountPeerId; let now = wall(); let gate = lease.gate
        lease.work.set((postbox.transaction { transaction -> (BotBridgeHistoryProgress, BotBridgeCursor?)? in
            guard lifetime.isActive, gate.isOpen, botBridgeValidatedAccount(transaction: transaction, accountPeerId: accountPeerId, testing: expected.testing),
                let current = transaction.getPreferencesEntry(key: botBridgeHistoryKey)?.get(BotBridgeHistoryProgress.self), current == expected else { return nil }
            var updated = current
            let _ = updated.acceptState(cursor, unread: unread, now: now)
            botBridgeWriteProgress(updated, transaction: transaction)
            return (updated, botBridgeObservedLive(transaction: transaction))
        } |> deliverOn(queue)).start(next: { [weak self, weak lease] progress in
            guard let self = self, let lease = lease else { return }
            self.didStore(progress, lease: lease)
        }))
    }

    private func storePage(_ page: BotBridgeHistoryPage, expected: BotBridgeHistoryProgress, lease: BotBridgePageLease) {
        let lifetime = self.lifetime; let accountPeerId = self.accountPeerId; let removed = self.removed; let now = wall(); let gate = lease.gate
        lease.work.set((postbox.transaction { transaction -> (BotBridgeHistoryProgress, BotBridgeCursor?)? in
            guard let progress = importBotBridgeHistoryPage(transaction: transaction, page: page, expected: expected, accountPeerId: accountPeerId, removed: removed, now: now, lifetime: lifetime, requestGate: gate) else { return nil }
            return (progress, botBridgeObservedLive(transaction: transaction))
        } |> deliverOn(queue)).start(next: { [weak self, weak lease] progress in
            guard let self = self, let lease = lease else { return }
            self.didStore(progress, lease: lease)
        }))
    }

    private func didStore(_ result: (BotBridgeHistoryProgress, BotBridgeCursor?)?, lease: BotBridgePageLease) {
        guard lease.gate.isOpen, lifetime.isActive else { lease.finish(); return }
        guard let (progress, live) = result else { fail(.replaced, lease: lease); return }
        self.observedLive = live
        self.progress = progress
        emit(progress.terminal == nil ? .committed : .terminal, progress: progress)
        if progress.terminal != nil { emit(.handoff, progress: progress) }
        lease.finish()
        active = nil
        guard progress.terminal == nil else {
            scheduleHistoryContinuation(progress)
            return
        }
        // Yield the account queue between historical pages; live polling stays
        // independent while the next bounded request waits for Network.
        queue.async { [weak self] in self?.schedulePage() }
    }

    private func fail(_ reason: BotBridgeHistoryReason, lease: BotBridgePageLease) {
        guard lease.gate.isOpen else { return }
        lease.finish()
        active = nil
        persistTerminal(reason)
    }

    deinit {
        lifetime.cancel()
        active?.finish()
        terminalWrite.dispose()
    }
}
