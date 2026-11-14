import Foundation

public struct JerkgramLocalAppearanceSettings: Codable, Equatable {
    public let schema: Int32
    public let owner: Int64
    public let peer: Int64
    public let testing: Bool
    public var revision: Int64 = 0
    public var enabled = false
    public var emojiEnabled = false
    public var emojiFileId: Int64?
    public var emojiExpiration: Int32?
    public var colorsEnabled = false
    public var nameColor: Int32?
    public var profileColor: Int32?
    public var replyEmoji: Int64?
    public var profileEmoji: Int64?

    public init(owner: Int64, peer: Int64, testing: Bool) {
        self.schema = 1; self.owner = owner; self.peer = peer; self.testing = testing
    }

    public var isValid: Bool {
        return schema == 1 && revision >= 0
            && (emojiFileId.map { $0 > 0 } ?? true)
            && (replyEmoji.map { $0 > 0 } ?? true)
            && (profileEmoji.map { $0 > 0 } ?? true)
            && (emojiExpiration.map { $0 >= 0 } ?? true)
            && (nameColor.map { $0 >= 0 } ?? true)
            && (profileColor.map { $0 >= 0 } ?? true)
    }

    public func permits(recordId: Int64, ownPeerId: Int64, testing: Bool, active: Bool, ownIsBot: Bool?, displayedPeerId: Int64, displayedIsBot: Bool) -> Bool {
        return isValid && active && ownIsBot == false && !displayedIsBot
            && owner == recordId && peer == ownPeerId && self.testing == testing
            && displayedPeerId == ownPeerId
    }

    public func currentEmoji(at timestamp: Int32) -> Int64? {
        guard emojiEnabled, let emojiFileId, emojiExpiration.map({ timestamp < $0 }) ?? true else { return nil }
        return emojiFileId
    }
}
