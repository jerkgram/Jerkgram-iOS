import Foundation
import Postbox

func ghostBaseIsBotAccount(_ accountPeerId: PeerId) -> Bool {
    return UserDefaults.standard.bool(
        forKey: "jerkgram.BotAccount.\(accountPeerId.toInt64())"
    )
}

// JG174 bot persistence begin
// Actual account peer wins over the legacy login marker when it is available.
func jerkgramIsBotAccount(accountPeerId: PeerId, peer: Peer?) -> Bool {
    if let user = peer as? TelegramUser { return user.botInfo != nil }
    return ghostBaseIsBotAccount(accountPeerId)
}

func jerkgramIncludeBotMessagePeers(transaction: Transaction, accountPeerId: PeerId, messages: [StoreMessage]) {
    guard jerkgramIsBotAccount(accountPeerId: accountPeerId, peer: transaction.getPeer(accountPeerId)) else { return }
    var visited = Set<PeerId>()
    for message in messages {
        guard case let .Id(id) = message.id, id.namespace == Namespaces.Message.Cloud,
              transaction.messageExists(id: id),
              let peer = transaction.getPeer(id.peerId),
              !shouldExcludePeerFromChatList(transaction: transaction, peerId: id.peerId, peer: peer),
              visited.insert(id.peerId).inserted else { continue }
        // Existing archive, pins and history boundary must remain byte-for-byte
        // unchanged. Never advance a minTimestamp on each delivered message.
        if case .notIncluded = transaction.getPeerChatListInclusion(id.peerId) {
            transaction.updatePeerChatListInclusion(id.peerId, inclusion: .ifHasMessagesOrOneOf(groupId: .root, pinningIndex: nil, minTimestamp: nil))
        }
    }
}
// JG174 bot persistence end
