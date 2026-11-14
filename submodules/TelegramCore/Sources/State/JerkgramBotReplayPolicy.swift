import Foundation

// Historical retrieval is separate from AuthorizedAccountState. The earliest
// non-empty seed is used only by isolated replay, never by the live poller.
enum JerkgramBotReplayPolicy {
    static let version: Int32 = 2
    static let windowMessages = 160000

    static func seed(_ live: BotBridgeCursor) -> BotBridgeCursor? {
        guard live.isValid, live.pts >= 1, live.date >= 1 else { return nil }
        return BotBridgeCursor(pts: 1, qts: 0, date: 1, seq: 0)
    }

    static func upgrade(_ previous: BotBridgeHistoryProgress, owner: Int64, peer: Int64, testing: Bool, now: Double = Date().timeIntervalSince1970) -> BotBridgeHistoryProgress {
        guard previous.isValid, previous.owner == owner, previous.peer == peer,
            previous.testing == testing,
            previous.terminal != .corrupt, previous.terminal != .loggedOut,
            previous.terminal != .replaced else { return previous }
        if previous.historyPolicyVersion == 1 {
            return BotBridgeHistoryProgress(owner: owner, peer: peer, testing: testing, generation: UUID().uuidString)
        }
        var resumed = previous
        if resumed.resumeHistoryWindow(now: now, allowTransient: true) { return resumed }
        let transient = previous.terminal == .cancelled || previous.terminal == .timeout || previous.terminal == .rpcError || previous.terminal == .interruptedState
        if previous.original == nil, transient {
            return BotBridgeHistoryProgress(owner: owner, peer: peer, testing: testing, generation: UUID().uuidString)
        }
        return previous
    }
}

extension BotBridgeHistoryProgress {
    var historyMessageLimit: Int { historyPolicyVersion == 2 ? JerkgramBotReplayPolicy.windowMessages : 20000 }

    // Bound work per window, retain the server cursor between windows. Only
    // successful advancing work can renew a window; errors never retry forever.
    mutating func resumeHistoryWindow(now: Double, allowTransient: Bool = false) -> Bool {
        let transient = allowTransient && (terminal == .cancelled || terminal == .timeout || terminal == .rpcError)
        guard isValid, historyPolicyVersion == 2, now.isFinite,
            terminal == .limit || terminal == .deadline || transient,
            let next, let start = historyWindowStart ?? candidate,
            transient || (committedPages > 0 && next.advances(start)),
            historyWindow < Int32.max, let lastWall, now >= lastWall else { return false }
        historyWindow += 1
        terminal = nil
        started = now; deadline = now + 120; self.lastWall = now
        reservedPages = 0; committedPages = 0
        examined = 0; inserted = 0; insertedPeers = 0; insertedUsers = 0; insertedChats = 0
        deleteIdsObserved = 0; skipped = 0; unsupported = 0; deletions = 0; missingReferences = 0
        // Each renewed window must advance from its own starting cursor.
        self.historyWindowStart = next
        return true
    }
}
