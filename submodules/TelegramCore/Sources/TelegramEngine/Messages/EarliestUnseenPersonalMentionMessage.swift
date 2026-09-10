import Foundation
import Postbox
import SwiftSignalKit
import MtProtoKit


public enum EarliestUnseenPersonalMentionMessageResult: Equatable {
    case loading
    case result(MessageId?)
}


private enum JerkgramBuild133UnseenTargetKind {
    case mention
    case reaction
}

private func jerkgramBuild133IsNavigableUnseenTarget(
    accountPeerId: PeerId,
    message: Message,
    kind: JerkgramBuild133UnseenTargetKind
) -> Bool {
    if JerkgramBlockedReactionPolicy.isMessageHidden(
        accountPeerId: accountPeerId,
        message: message
    ) {
        return false
    }

    switch kind {
    case .mention:
        return true
    case .reaction:
        guard let attribute = message.attributes.first(where: { $0 is ReactionsMessageAttribute }) as? ReactionsMessageAttribute else {
            return true
        }
        return JerkgramBlockedReactionPolicy.hasVisibleUnseenReaction(
            accountPeerId: accountPeerId,
            message: message,
            attribute: attribute
        )
    }
}

private func jerkgramBuild133FirstNavigableUnseenTarget(
    accountPeerId: PeerId,
    entries: [MessageHistoryEntry],
    kind: JerkgramBuild133UnseenTargetKind
) -> Message? {
    for entry in entries {
        if jerkgramBuild133IsNavigableUnseenTarget(
            accountPeerId: accountPeerId,
            message: entry.message,
            kind: kind
        ) {
            return entry.message
        }
    }
    return nil
}

func _internal_earliestUnseenPersonalMentionMessage(account: Account, peerId: PeerId, threadId: Int64?) -> Signal<EarliestUnseenPersonalMentionMessageResult, NoError> {
    return account.viewTracker.aroundMessageHistoryViewForLocation(.peer(peerId: peerId, threadId: threadId), index: .lowerBound, anchorIndex: .lowerBound, count: 64, fixedCombinedReadStates: nil, tag: .tag(.unseenPersonalMessage), additionalData: [.peerChatState(peerId)])
    |> mapToSignal { view -> Signal<EarliestUnseenPersonalMentionMessageResult, NoError> in
        if view.0.isLoading {
            return .single(.loading)
        }
        if case .FillHole = view.1 {
            return _internal_earliestUnseenPersonalMentionMessage(account: account, peerId: peerId, threadId: threadId)
        }
        if let message = jerkgramBuild133FirstNavigableUnseenTarget(
            accountPeerId: account.peerId,
            entries: view.0.entries,
            kind: .mention
        ) {
            if peerId.namespace == Namespaces.Peer.CloudChannel {
                var invalidatedPts: Int32?
                for data in view.0.additionalData {
                    switch data {
                        case let .peerChatState(_, state):
                            if let state = state as? ChannelState {
                                invalidatedPts = state.invalidatedPts
                            }
                        default:
                            break
                    }
                }
                if let invalidatedPts = invalidatedPts {
                    var messagePts: Int32?
                    for attribute in message.attributes {
                        if let attribute = attribute as? ChannelMessageStateVersionAttribute {
                            messagePts = attribute.pts
                            break
                        }
                    }
                    
                    if let messagePts = messagePts {
                        if messagePts < invalidatedPts {
                            return .single(.loading)
                        }
                    }
                }
                return .single(.result(message.id))
            } else {
                return .single(.result(message.id))
            }
        } else if !view.0.entries.isEmpty {
            return .single(.result(nil))
        } else {
            return account.postbox.transaction { transaction -> EarliestUnseenPersonalMentionMessageResult in
                if let topId = transaction.getTopPeerMessageId(peerId: peerId, namespace: Namespaces.Message.Cloud) {
                    transaction.replaceMessageTagSummary(peerId: peerId, threadId: threadId, tagMask: .unseenPersonalMessage, namespace: Namespaces.Message.Cloud, customTag: nil, count: 0, maxId: topId.id)
                    
                    transaction.removeHole(peerId: peerId, threadId: threadId, namespace: Namespaces.Message.Cloud, space: .tag(.unseenPersonalMessage), range: 1 ... (Int32.max - 1))
                    let ids = transaction.getMessageIndicesWithTag(peerId: peerId, threadId: threadId, namespace: Namespaces.Message.Cloud, tag: .unseenPersonalMessage).map({ $0.id })
                    for id in ids {
                        markUnseenPersonalMessage(transaction: transaction, id: id, addSynchronizeAction: false)
                    }
                }
                
                return .result(nil)
            }
        }
    }
    |> distinctUntilChanged
    |> take(until: { value in
        if case .result = value {
            return SignalTakeAction(passthrough: true, complete: true)
        } else {
            return SignalTakeAction(passthrough: true, complete: false)
        }
    })
}

func _internal_earliestUnseenPersonalReactionMessage(account: Account, peerId: PeerId, threadId: Int64?) -> Signal<EarliestUnseenPersonalMentionMessageResult, NoError> {
    return account.viewTracker.aroundMessageHistoryViewForLocation(.peer(peerId: peerId, threadId: threadId), index: .lowerBound, anchorIndex: .lowerBound, count: 64, fixedCombinedReadStates: nil, tag: .tag(.unseenReaction), additionalData: [.peerChatState(peerId)])
    |> mapToSignal { view -> Signal<EarliestUnseenPersonalMentionMessageResult, NoError> in
        if view.0.isLoading {
            return .single(.loading)
        }
        if case .FillHole = view.1 {
            return _internal_earliestUnseenPersonalReactionMessage(account: account, peerId: peerId, threadId: threadId)
        }
        if let message = jerkgramBuild133FirstNavigableUnseenTarget(
            accountPeerId: account.peerId,
            entries: view.0.entries,
            kind: .reaction
        ) {
            if peerId.namespace == Namespaces.Peer.CloudChannel {
                var invalidatedPts: Int32?
                for data in view.0.additionalData {
                    switch data {
                        case let .peerChatState(_, state):
                            if let state = state as? ChannelState {
                                invalidatedPts = state.invalidatedPts
                            }
                        default:
                            break
                    }
                }
                if let invalidatedPts = invalidatedPts {
                    var messagePts: Int32?
                    for attribute in message.attributes {
                        if let attribute = attribute as? ChannelMessageStateVersionAttribute {
                            messagePts = attribute.pts
                            break
                        }
                    }
                    
                    if let messagePts = messagePts {
                        if messagePts < invalidatedPts {
                            return .single(.loading)
                        }
                    }
                }
                return .single(.result(message.id))
            } else {
                return .single(.result(message.id))
            }
        } else if !view.0.entries.isEmpty {
            return .single(.result(nil))
        } else {
            return account.postbox.transaction { transaction -> EarliestUnseenPersonalMentionMessageResult in
                if let topId = transaction.getTopPeerMessageId(peerId: peerId, namespace: Namespaces.Message.Cloud) {
                    transaction.replaceMessageTagSummary(peerId: peerId, threadId: threadId, tagMask: .unseenReaction, namespace: Namespaces.Message.Cloud, customTag: nil, count: 0, maxId: topId.id)
                    
                    transaction.removeHole(peerId: peerId, threadId: threadId, namespace: Namespaces.Message.Cloud, space: .tag(.unseenReaction), range: 1 ... (Int32.max - 1))
                    let ids = transaction.getMessageIndicesWithTag(peerId: peerId, threadId: threadId, namespace: Namespaces.Message.Cloud, tag: .unseenReaction).map({ $0.id })
                    for id in ids {
                        markUnseenReactionOrPollVotesMessage(transaction: transaction, id: id, addSynchronizeAction: false)
                    }
                }
                
                return .result(nil)
            }
        }
    }
    |> distinctUntilChanged
    |> take(until: { value in
        if case .result = value {
            return SignalTakeAction(passthrough: true, complete: true)
        } else {
            return SignalTakeAction(passthrough: true, complete: false)
        }
    })
}

func _internal_earliestUnseenPollVoteMessage(account: Account, peerId: PeerId, threadId: Int64?) -> Signal<EarliestUnseenPersonalMentionMessageResult, NoError> {
    return account.viewTracker.aroundMessageHistoryViewForLocation(.peer(peerId: peerId, threadId: threadId), index: .lowerBound, anchorIndex: .lowerBound, count: 4, fixedCombinedReadStates: nil, tag: .tag(.unseenPollVote), additionalData: [.peerChatState(peerId)])
    |> mapToSignal { view -> Signal<EarliestUnseenPersonalMentionMessageResult, NoError> in
        if view.0.isLoading {
            return .single(.loading)
        }
        if case .FillHole = view.1 {
            return _internal_earliestUnseenPollVoteMessage(account: account, peerId: peerId, threadId: threadId)
        }
        if let message = view.0.entries.first?.message {
            if peerId.namespace == Namespaces.Peer.CloudChannel {
                var invalidatedPts: Int32?
                for data in view.0.additionalData {
                    switch data {
                        case let .peerChatState(_, state):
                            if let state = state as? ChannelState {
                                invalidatedPts = state.invalidatedPts
                            }
                        default:
                            break
                    }
                }
                if let invalidatedPts = invalidatedPts {
                    var messagePts: Int32?
                    for attribute in message.attributes {
                        if let attribute = attribute as? ChannelMessageStateVersionAttribute {
                            messagePts = attribute.pts
                            break
                        }
                    }
                    
                    if let messagePts = messagePts {
                        if messagePts < invalidatedPts {
                            return .single(.loading)
                        }
                    }
                }
                return .single(.result(message.id))
            } else {
                return .single(.result(message.id))
            }
        } else {
            return account.postbox.transaction { transaction -> EarliestUnseenPersonalMentionMessageResult in
                if let topId = transaction.getTopPeerMessageId(peerId: peerId, namespace: Namespaces.Message.Cloud) {
                    transaction.replaceMessageTagSummary(peerId: peerId, threadId: threadId, tagMask: .unseenPollVote, namespace: Namespaces.Message.Cloud, customTag: nil, count: 0, maxId: topId.id)
                    
                    transaction.removeHole(peerId: peerId, threadId: threadId, namespace: Namespaces.Message.Cloud, space: .tag(.unseenPollVote), range: 1 ... (Int32.max - 1))
                    let ids = transaction.getMessageIndicesWithTag(peerId: peerId, threadId: threadId, namespace: Namespaces.Message.Cloud, tag: .unseenPollVote).map({ $0.id })
                    for id in ids {
                        markUnseenReactionOrPollVotesMessage(transaction: transaction, id: id, addSynchronizeAction: false)
                    }
                }
                
                return .result(nil)
            }
        }
    }
    |> distinctUntilChanged
    |> take(until: { value in
        if case .result = value {
            return SignalTakeAction(passthrough: true, complete: true)
        } else {
            return SignalTakeAction(passthrough: true, complete: false)
        }
    })
}
