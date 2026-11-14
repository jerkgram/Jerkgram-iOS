import Foundation
import Postbox

// A local per-account capability. Never modifies Telegram Premium or API flags.
public enum JerkgramSponsoredContentPolicy {
    public static let preferenceKey = "jerkgram.SponsoredContent.Remove"
    private static let lock = NSLock()
    private static var accounts: [Int64: Bool] = [:]

    public static func scopedKey(accountPeerId: Int64) -> String {
        return "jerkgram.account.\(accountPeerId).setting.\(self.preferenceKey)"
    }

    public static func readStoredValue(accountPeerId: Int64) -> Bool {
        // A new account must not inherit another account's active projection.
        return UserDefaults.standard.bool(forKey: self.scopedKey(accountPeerId: accountPeerId))
    }

    public static func removeSponsored(accountPeerId: Int64) -> Bool {
        guard JerkgramLocalPremiumPolicy.enabled else { return false }
        self.lock.lock()
        defer { self.lock.unlock() }
        if let value = self.accounts[accountPeerId] { return value }
        let value = self.readStoredValue(accountPeerId: accountPeerId)
        if self.accounts.count >= 32 { self.accounts.removeAll(keepingCapacity: true) }
        self.accounts[accountPeerId] = value
        return value
    }

    public static func update(accountPeerId: Int64, enabled: Bool) {
        self.lock.lock()
        if self.accounts.count >= 32 && self.accounts[accountPeerId] == nil { self.accounts.removeAll(keepingCapacity: true) }
        self.accounts[accountPeerId] = enabled
        self.lock.unlock()
        JerkgramLocalPremiumPolicy.invalidate()
    }

    static func shouldDisplay(isSponsored: Bool, removeSponsored: Bool) -> Bool {
        return !isSponsored || !removeSponsored
    }
}
