import Foundation
import Postbox
import SwiftSignalKit
import TelegramApi

public final class MessageReadStats {
    public let reactionCount: Int
    public let peers: [EnginePeer]
    public let readTimestamps: [EnginePeer.Id: Int32]

    public init(reactionCount: Int, peers: [EnginePeer], readTimestamps: [EnginePeer.Id: Int32]) {
        self.reactionCount = reactionCount
        self.peers = peers
        self.readTimestamps = readTimestamps
    }
}

func _internal_messageReadStats(account: Account, id: MessageId) -> Signal<MessageReadStats?, NoError> {
    UserDefaults.standard.set(id.peerId.toInt64(), forKey: "jerkgram.READ3.LastPeerIdRaw")
    UserDefaults.standard.set(id.id, forKey: "jerkgram.READ3.LastMessageId")
    UserDefaults.standard.set(Int(Date().timeIntervalSince1970), forKey: "jerkgram.READ3.LastRequestAt")
    UserDefaults.standard.set("started", forKey: "jerkgram.READ3.FinalVerdict")
    return account.postbox.transaction { transaction -> Peer? in
        return transaction.getPeer(id.peerId)
    }
    |> mapToSignal { peer -> Signal<MessageReadStats?, NoError> in
        guard let peer, let inputPeer = apiInputPeer(peer) else {
            return .single(nil)
        }
        if id.namespace != Namespaces.Message.Cloud {
            return .single(nil)
        }
        
        if id.peerId.namespace == Namespaces.Peer.CloudUser {
            return account.network.request(Api.functions.messages.getOutboxReadDate(peer: inputPeer, msgId: id.id))
            |> map(Optional.init)
            |> `catch` { _ -> Signal<Api.OutboxReadDate?, NoError> in
                return .single(nil)
            }
            |> map { result -> MessageReadStats? in
                guard let result else {
                    return MessageReadStats(reactionCount: 0, peers: [], readTimestamps: [:])
                }
                switch result {
                case let .outboxReadDate(outboxReadDateData):
                    let date = outboxReadDateData.date
                    return MessageReadStats(reactionCount: 0, peers: [EnginePeer(peer)], readTimestamps: [peer.id: date])
                }
            }
        } else {
            UserDefaults.standard.set("getMessageReadParticipants", forKey: "jerkgram.READ3.LastApi")
            UserDefaults.standard.set("requesting", forKey: "jerkgram.READ3.FinalVerdict")

            let readPeers: Signal<[(Int64, Int32)]?, NoError> = account.network.request(Api.functions.messages.getMessageReadParticipants(peer: inputPeer, msgId: id.id))
            |> map { result -> [(Int64, Int32)]? in
                UserDefaults.standard.set(result.count, forKey: "jerkgram.READ3.ForcedApiRawCount")
                UserDefaults.standard.set("response", forKey: "jerkgram.READ3.LastResponse")
                var items: [(Int64, Int32)] = []
                for item in result {
                    switch item {
                    case let .readParticipantDate(readParticipantDateData):
                        let (userId, date) = (readParticipantDateData.userId, readParticipantDateData.date)
                        items.append((userId, date))
                    }
                }
                UserDefaults.standard.set(items.count, forKey: "jerkgram.READ3.ForcedCount")
                if let first = items.first {
                    UserDefaults.standard.set(first.0, forKey: "jerkgram.READ3.FirstUserId")
                    UserDefaults.standard.set(first.1, forKey: "jerkgram.READ3.FirstReadDate")
                }
                if items.isEmpty {
                    UserDefaults.standard.set("MESSAGE_NOT_READ_OR_EMPTY", forKey: "jerkgram.READ3.FinalVerdict")
                } else {
                    UserDefaults.standard.set("EXACT_READERS_FOUND", forKey: "jerkgram.READ3.FinalVerdict")
                }
                return items
            }
            |> `catch` { error -> Signal<[(Int64, Int32)]?, NoError> in
                UserDefaults.standard.set("\(error)", forKey: "jerkgram.READ3.LastErrorRaw")
                UserDefaults.standard.set("RESTRICTED_BY_TELEGRAM_API_OR_ERROR", forKey: "jerkgram.READ3.FinalVerdict")
                return .single(nil)
            }
            
            let reactionCount: Signal<Int, NoError> = account.network.request(Api.functions.messages.getMessageReactionsList(flags: 0, peer: inputPeer, id: id.id, reaction: nil, offset: nil, limit: 1))
            |> map { result -> Int in
                switch result {
                case let .messageReactionsList(messageReactionsListData):
                    let count = messageReactionsListData.count
                    return Int(count)
                }
            }
            |> `catch` { _ -> Signal<Int, NoError> in
                return .single(0)
            }
            
            return combineLatest(readPeers, reactionCount)
            |> mapToSignal { result, reactionCount -> Signal<MessageReadStats?, NoError> in
                return account.postbox.transaction { transaction -> (peerIds: [PeerId], readTimestamps: [PeerId: Int32], missingPeerIds: [PeerId]) in
                    var peerIds: [PeerId] = []
                    var readTimestamps: [PeerId: Int32] = [:]
                    var missingPeerIds: [PeerId] = []

                    let authorId = transaction.getMessage(id)?.author?.id

                    if let result = result {
                        for (id, timestamp) in result {
                            let peerId = PeerId(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt64Value(id))
                            readTimestamps[peerId] = timestamp
                            if peerId == account.peerId {
                                continue
                            }
                            if peerId == authorId {
                                continue
                            }
                            peerIds.append(peerId)
                            if transaction.getPeer(peerId) == nil {
                                missingPeerIds.append(peerId)
                            }
                        }
                    }

                    return (peerIds: peerIds, readTimestamps: readTimestamps, missingPeerIds: missingPeerIds)
                }
                |> mapToSignal { peerIds, readTimestamps, missingPeerIds -> Signal<MessageReadStats?, NoError> in
                    if missingPeerIds.isEmpty || id.peerId.namespace != Namespaces.Peer.CloudChannel {
                        return account.postbox.transaction { transaction -> MessageReadStats? in
                            return MessageReadStats(reactionCount: reactionCount, peers: peerIds.compactMap { peerId -> EnginePeer? in
                                return transaction.getPeer(peerId).flatMap(EnginePeer.init)
                            }, readTimestamps: readTimestamps)
                        }
                    } else {
                        return _internal_channelMembers(postbox: account.postbox, network: account.network, accountPeerId: account.peerId, peerId: id.peerId, category: .recent(.all), offset: 0, limit: 50, hash: 0)
                        |> mapToSignal { _ -> Signal<MessageReadStats?, NoError> in
                            return account.postbox.transaction { transaction -> MessageReadStats? in
                                return MessageReadStats(reactionCount: reactionCount, peers: peerIds.compactMap { peerId -> EnginePeer? in
                                    return transaction.getPeer(peerId).flatMap(EnginePeer.init)
                                }, readTimestamps: readTimestamps)
                            }
                        }
                    }
                }
            }
        }
    }
}
