import Foundation
import Postbox

public enum JerkgramDownloadBoostMode: String, CaseIterable {
    case off
    case medium
    case maximum
}

// Uses the same per-account namespace as GhostBaseSettingsState; no per-part I/O.
public enum JerkgramDownloadBoostSettings {
    public static let preferenceKey = "jerkgram.DownloadBoost.Mode"
    private static let lock = NSLock()
    private static var modes: [Int64: JerkgramDownloadBoostMode] = [:]
    private static var remainingDebugLogs = 32

    static func takeDebugLogSlot() -> Bool {
        self.lock.lock()
        defer { self.lock.unlock() }
        guard self.remainingDebugLogs > 0 else { return false }
        self.remainingDebugLogs -= 1
        return true
    }

    public static func scopedKey(accountPeerId: Int64) -> String {
        return "jerkgram.account.\(accountPeerId).setting.\(self.preferenceKey)"
    }

    public static func readStoredMode(accountPeerId: Int64) -> JerkgramDownloadBoostMode {
        let raw = UserDefaults.standard.string(forKey: self.scopedKey(accountPeerId: accountPeerId)) ?? "off"
        return JerkgramDownloadBoostMode(rawValue: raw) ?? .off
    }

    public static func mode(accountPeerId: Int64) -> JerkgramDownloadBoostMode {
        guard JerkgramLocalPremiumPolicy.enabled else { return .off }
        self.lock.lock()
        defer { self.lock.unlock() }
        if let mode = self.modes[accountPeerId] { return mode }
        let mode = self.readStoredMode(accountPeerId: accountPeerId)
        if self.modes.count >= 32 { self.modes.removeAll(keepingCapacity: true) }
        self.modes[accountPeerId] = mode
        return mode
    }

    public static func update(accountPeerId: Int64, rawValue: String) {
        self.lock.lock()
        defer { self.lock.unlock() }
        if self.modes.count >= 32 && self.modes[accountPeerId] == nil { self.modes.removeAll(keepingCapacity: true) }
        self.modes[accountPeerId] = JerkgramDownloadBoostMode(rawValue: rawValue) ?? .off
    }
}

enum JerkgramDownloadBoostPolicy {
    struct Parameters {
        let mode: JerkgramDownloadBoostMode
        let partSize: Int64
        let maxPendingParts: Int
        let initialWindow: Int
        let adaptiveLargePartSize: Int64
    }

    static func parameters(mode: JerkgramDownloadBoostMode, size: Int64?, isStory: Bool, fastDownloads: Bool, encrypted: Bool, isCdn: Bool = false) -> Parameters {
        let stockPart: Int64 = isCdn ? 128 * 1024 : (isStory ? 512 * 1024 : 128 * 1024)
        let stockPending = fastDownloads ? (isCdn ? 32 : 16) : 6
        // Small, unknown-size, encrypted and CDN paths retain the exact stock policy.
        guard !isCdn, !encrypted, let size, size > 1024 * 1024, mode != .off else {
            return Parameters(mode: .off, partSize: stockPart, maxPendingParts: stockPending, initialWindow: 6, adaptiveLargePartSize: 512 * 1024)
        }
        switch mode {
        case .off:
            return Parameters(mode: .off, partSize: stockPart, maxPendingParts: stockPending, initialWindow: 6, adaptiveLargePartSize: 512 * 1024)
        case .medium:
            return Parameters(mode: mode, partSize: 512 * 1024, maxPendingParts: max(stockPending, 8), initialWindow: fastDownloads ? 8 : 6, adaptiveLargePartSize: 512 * 1024)
        case .maximum:
            return Parameters(mode: mode, partSize: 1024 * 1024, maxPendingParts: max(stockPending, 12), initialWindow: fastDownloads ? 12 : 6, adaptiveLargePartSize: 1024 * 1024)
        }
    }
}
