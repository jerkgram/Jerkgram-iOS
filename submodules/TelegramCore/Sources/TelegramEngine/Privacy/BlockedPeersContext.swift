import Foundation
import TelegramApi
import Postbox
import SwiftSignalKit
import MtProtoKit

public struct BlockedPeersContextState: Equatable {
    public var isLoadingMore: Bool
    public var canLoadMore: Bool
    public var totalCount: Int?
    public var peers: [RenderedPeer]
}

public enum BlockedPeersContextAddError {
    case generic
}

public enum BlockedPeersContextRemoveError {
    case generic
}



// A single per-account O(1) presentation cache. The server/Postbox reaction
// attributes remain untouched; only presentation owners consult this policy.
public enum JerkgramBlockedReactionPolicy {
    public static let hideBlockedReactionsKey = "jerkgram.Messages.HideBlockedReactions"
    public static let hideBlockedMessagesKey = "jerkgram.Messages.HideBlockedMessages"

    private static let blockedPeerIdsByAccount = Atomic(value: [PeerId: Set<PeerId>]())

    private struct JerkgramBuild137BlockedSettings {
        let hideReactions: Bool
        let hideMessages: Bool
    }
    private static let settingsByAccount = Atomic(value: [PeerId: JerkgramBuild137BlockedSettings]())

    private static func settings(accountPeerId: PeerId) -> JerkgramBuild137BlockedSettings {
        let result = self.settingsByAccount.modify { current in
            if current[accountPeerId] != nil { return current }
            let defaults = UserDefaults.standard
            func value(_ key: String) -> Bool {
                let scopedKey = "jerkgram.account.\(accountPeerId.toInt64()).setting.\(key)"
                if let value = defaults.object(forKey: scopedKey) as? Bool { return value }
                if let value = defaults.object(forKey: key) as? Bool { return value }
                return true
            }
            let loaded = JerkgramBuild137BlockedSettings(
                hideReactions: value(self.hideBlockedReactionsKey),
                hideMessages: value(self.hideBlockedMessagesKey)
            )
            var current = current
            current[accountPeerId] = loaded
            return current
        }
        // Every closure path returns a dictionary containing this account.
        return result[accountPeerId]!
    }
    private static let presentationRevision = Atomic(value: Int32(0))
    private static let presentationRevisionPromise = ValuePromise<Int32>(0, ignoreRepeated: false)

    public static var presentationUpdates: Signal<Int32, NoError> {
        return self.presentationRevisionPromise.get()
    }

    public static var presentationRevisionValue: Int32 {
        return self.presentationRevision.with { value in value }
    }

    private static func notifyPresentationChanged() {
        let revision = self.presentationRevision.modify { current in
            return current == Int32.max ? 0 : current + 1
        }
        self.presentationRevisionPromise.set(revision)
    }

    public static func notifySettingsChanged() {
        let _ = self.settingsByAccount.modify { _ in [:] }
        self.notifyPresentationChanged()
    }

    public static func replaceBlockedPeerIds(accountPeerId: PeerId, peerIds: Set<PeerId>) {
        let previous = self.blockedPeerIdsByAccount.with { current in
            return current[accountPeerId] ?? Set()
        }
        if previous == peerIds {
            return
        }
        let _ = self.blockedPeerIdsByAccount.modify { current in
            var current = current
            current[accountPeerId] = peerIds
            return current
        }
        self.notifyPresentationChanged()
    }

    public static func blockedPeerIds(accountPeerId: PeerId) -> Set<PeerId> {
        return self.blockedPeerIdsByAccount.with { current in
            return current[accountPeerId] ?? Set()
        }
    }

    public static func isBlocked(accountPeerId: PeerId, peerId: PeerId) -> Bool {
        return self.blockedPeerIdsByAccount.with { current in
            return current[accountPeerId]?.contains(peerId) ?? false
        }
    }

    public static func isGroupChat(_ peer: Peer?) -> Bool {
        if peer is TelegramGroup {
            return true
        }
        if let channel = peer as? TelegramChannel, case .group = channel.info {
            return true
        }
        return false
    }

    public static func isGroupMessage(_ message: Message) -> Bool {
        return self.isGroupChat(message.peers[message.id.peerId])
    }

    public static func hideBlockedReactions(accountPeerId: PeerId) -> Bool {
        return self.settings(accountPeerId: accountPeerId).hideReactions
    }

    public static func hideBlockedMessages(accountPeerId: PeerId) -> Bool {
        return self.settings(accountPeerId: accountPeerId).hideMessages
    }

    public static func isMessageHidden(accountPeerId: PeerId, message: Message) -> Bool {
        return self.isMessageHidden(
            accountPeerId: accountPeerId,
            chatPeer: message.peers[message.id.peerId],
            message: message
        )
    }

    public static func isMessageHidden(
        accountPeerId: PeerId,
        chatPeer: Peer?,
        message: Message
    ) -> Bool {
        guard self.isGroupChat(chatPeer) else {
            return false
        }
        guard self.hideBlockedMessages(accountPeerId: accountPeerId) else {
            return false
        }
        let authorId = message.author?.id
        guard let authorId, authorId != accountPeerId else {
            return false
        }
        return self.isBlocked(accountPeerId: accountPeerId, peerId: authorId)
    }

    public static func updateBlockedPeer(
        accountPeerId: PeerId,
        peerId: PeerId,
        isBlocked: Bool
    ) {
        let previous = self.isBlocked(accountPeerId: accountPeerId, peerId: peerId)
        if previous == isBlocked {
            return
        }
        let _ = self.blockedPeerIdsByAccount.modify { current in
            var current = current
            var peerIds = current[accountPeerId] ?? Set()
            if isBlocked {
                peerIds.insert(peerId)
            } else {
                peerIds.remove(peerId)
            }
            current[accountPeerId] = peerIds
            return current
        }
        self.notifyPresentationChanged()
    }

    public static func hasVisibleUnseenReactionInGroup(
        accountPeerId: PeerId,
        attribute: ReactionsMessageAttribute
    ) -> Bool {
        guard attribute.hasUnseen else {
            return false
        }
        guard self.hideBlockedReactions(accountPeerId: accountPeerId) else {
            return true
        }

        var sawUnseen = false
        for recentPeer in attribute.recentPeers where recentPeer.isUnseen {
            sawUnseen = true
            if recentPeer.isMy || recentPeer.peerId == accountPeerId {
                return true
            }
            if !self.isBlocked(accountPeerId: accountPeerId, peerId: recentPeer.peerId) {
                return true
            }
        }

        if !sawUnseen {
            return true
        }
        return false
    }

    public static func hasVisibleUnseenReaction(
        accountPeerId: PeerId,
        message: Message,
        attribute: ReactionsMessageAttribute
    ) -> Bool {
        guard self.isGroupMessage(message) else {
            return attribute.hasUnseen
        }
        return self.hasVisibleUnseenReactionInGroup(
            accountPeerId: accountPeerId,
            attribute: attribute
        )
    }
}

// Retained once per live AccountContext. It owns the normal Telegram
// BlockedPeersContext and drains all pages; there is no request per message.
public final class JerkgramBlockedPeersObserver {
    private let context: BlockedPeersContext
    private let disposable = MetaDisposable()

    public init(account: Account) {
        assert(Queue.mainQueue().isCurrent())
        let context = BlockedPeersContext(account: account, subject: .blocked)
        self.context = context
        self.disposable.set((context.state
        |> deliverOnMainQueue).start(next: { state in
            JerkgramBlockedReactionPolicy.replaceBlockedPeerIds(
                accountPeerId: account.peerId,
                peerIds: Set(state.peers.map { $0.peerId })
            )
            if state.canLoadMore && !state.isLoadingMore {
                Queue.mainQueue().async {
                    context.loadMore()
                }
            }
        }))
    }

    deinit {
        self.disposable.dispose()
    }
}

public final class BlockedPeersContext {
    public enum Subject {
        case blocked
        case stories
    }
    
    private let account: Account
    private let subject: Subject
    private var _state: BlockedPeersContextState {
        didSet {
            if self._state != oldValue {
                self._statePromise.set(.single(self._state))
                if case .blocked = self.subject {
                    JerkgramBlockedReactionPolicy.replaceBlockedPeerIds(
                        accountPeerId: self.account.peerId,
                        peerIds: Set(self._state.peers.map { $0.peerId })
                    )
                }
            }
        }
    }
    private let _statePromise = Promise<BlockedPeersContextState>()
    public var state: Signal<BlockedPeersContextState, NoError> {
        return self._statePromise.get()
    }
    
    private let disposable = MetaDisposable()
    
    public init(account: Account, subject: Subject) {
        assert(Queue.mainQueue().isCurrent())
        
        self.account = account
        self.subject = subject
        
        self._state = BlockedPeersContextState(isLoadingMore: false, canLoadMore: true, totalCount: nil, peers: [])
        self._statePromise.set(.single(self._state))
        
        self.loadMore()
    }
    
    deinit {
        self.disposable.dispose()
    }
    
    public func loadMore() {
        assert(Queue.mainQueue().isCurrent())
        
        if self._state.isLoadingMore || !self._state.canLoadMore {
            return
        }
        self._state = BlockedPeersContextState(isLoadingMore: true, canLoadMore: self._state.canLoadMore, totalCount: self._state.totalCount, peers: self._state.peers)
        let postbox = self.account.postbox
        let accountPeerId = self.account.peerId
        
        var flags: Int32 = 0
        if case .stories = self.subject {
            flags |= 1 << 0
        }
        
        var limit: Int32 = 200
        if self._state.peers.count > 0 {
            limit = 100
        }
        
        self.disposable.set((self.account.network.request(Api.functions.contacts.getBlocked(flags: flags, offset: Int32(self._state.peers.count), limit: limit))
        |> retryRequestIfNotFrozen
        |> mapToSignal { result -> Signal<(peers: [RenderedPeer], canLoadMore: Bool, totalCount: Int?), NoError> in
            guard let result else {
                return .single((peers: [], canLoadMore: false, totalCount: 0))
            }
            return postbox.transaction { transaction -> (peers: [RenderedPeer], canLoadMore: Bool, totalCount: Int?) in
                switch result {
                    case let .blocked(blockedData):
                        let (blocked, chats, users) = (blockedData.blocked, blockedData.chats, blockedData.users)
                        let parsedPeers = AccumulatedPeers(transaction: transaction, chats: chats, users: users)
                        updatePeers(transaction: transaction, accountPeerId: accountPeerId, peers: parsedPeers)
                            
                        var renderedPeers: [RenderedPeer] = []
                        for blockedPeer in blocked {
                            switch blockedPeer {
                            case let .peerBlocked(peerBlockedData):
                                let peerId = peerBlockedData.peerId
                                if let peer = transaction.getPeer(peerId.peerId) {
                                    renderedPeers.append(RenderedPeer(peer: peer))
                                }
                            }
                        }

                        return (renderedPeers, false, nil)
                    case let .blockedSlice(blockedSliceData):
                        let (count, blocked, chats, users) = (blockedSliceData.count, blockedSliceData.blocked, blockedSliceData.chats, blockedSliceData.users)
                        let parsedPeers = AccumulatedPeers(transaction: transaction, chats: chats, users: users)
                        updatePeers(transaction: transaction, accountPeerId: accountPeerId, peers: parsedPeers)
                        
                        var renderedPeers: [RenderedPeer] = []
                        for blockedPeer in blocked {
                            switch blockedPeer {
                            case let .peerBlocked(peerBlockedData):
                                let peerId = peerBlockedData.peerId
                                if let peer = transaction.getPeer(peerId.peerId) {
                                    renderedPeers.append(RenderedPeer(peer: peer))
                                }
                            }
                        }

                        return (renderedPeers, true, Int(count))
                }
            }
        }
        |> deliverOnMainQueue).start(next: { [weak self] (peers, canLoadMore, totalCount) in
            guard let strongSelf = self else {
                return
            }
            
            var mergedPeers = strongSelf._state.peers
            var existingPeerIds = Set(mergedPeers.map { $0.peerId })
            for peer in peers {
                if !existingPeerIds.contains(peer.peerId) {
                    existingPeerIds.insert(peer.peerId)
                    mergedPeers.append(peer)
                }
            }
            
            let updatedTotalCount: Int?
            if !canLoadMore {
                updatedTotalCount = mergedPeers.count
            } else if let totalCount = totalCount {
                updatedTotalCount = totalCount
            } else {
                updatedTotalCount = strongSelf._state.totalCount
            }
            
            strongSelf._state = BlockedPeersContextState(isLoadingMore: false, canLoadMore: canLoadMore, totalCount: updatedTotalCount, peers: mergedPeers)
        }))
    }
    
    public func updatePeerIds(_ peerIds: [EnginePeer.Id]) -> Signal<Never, BlockedPeersContextAddError> {
        assert(Queue.mainQueue().isCurrent())
        
        let network = self.account.network
        let subject = self.subject
        let currentPeers = self._state.peers
        
        var flags: Int32 = 0
        if case .stories = self.subject {
            flags |= 1 << 0
        }
        
        return self.account.postbox.transaction { transaction -> [Peer] in
            var peers: [Peer] = []
            
            var removedPeerIds = Set<EnginePeer.Id>()
            var validPeerIds = Set<EnginePeer.Id>()
            var allPeerIds = Set<EnginePeer.Id>()
            
            for peerId in peerIds {
                if let peer = transaction.getPeer(peerId) {
                    peers.append(peer)
                }
                validPeerIds.insert(peerId)
                allPeerIds.insert(peerId)
            }
            for peer in currentPeers {
                if !validPeerIds.contains(peer.peerId) {
                    removedPeerIds.insert(peer.peerId)
                    allPeerIds.insert(peer.peerId)
                }
            }
            
            transaction.updatePeerCachedData(peerIds: allPeerIds, update: { peerId, current in
                let previous: CachedUserData
                if let current = current as? CachedUserData {
                    previous = current
                } else {
                    previous = CachedUserData()
                }
                if case .stories = subject {
                    var userFlags = previous.flags
                    if validPeerIds.contains(peerId) {
                        userFlags.insert(.isBlockedFromStories)
                    } else if removedPeerIds.contains(peerId) {
                        userFlags.remove(.isBlockedFromStories)
                    }
                    return previous.withUpdatedFlags(userFlags)
                } else {
                    if validPeerIds.contains(peerId) {
                        return previous.withUpdatedIsBlocked(true)
                    } else if removedPeerIds.contains(peerId) {
                        return previous.withUpdatedIsBlocked(false)
                    } else {
                        return previous
                    }
                }
            })
            
            return peers
        }
        |> castError(BlockedPeersContextAddError.self)
        |> mapToSignal { [weak self] peers -> Signal<Never, BlockedPeersContextAddError> in
            Queue.mainQueue().async {
                if let strongSelf = self {
                    strongSelf._state = BlockedPeersContextState(isLoadingMore: strongSelf._state.isLoadingMore, canLoadMore: strongSelf._state.canLoadMore, totalCount: peers.count, peers: peers.map(RenderedPeer.init))
                }
            }
            let inputPeers = peers.compactMap { apiInputPeer($0) }
            return network.request(Api.functions.contacts.setBlocked(flags: flags, id: inputPeers, limit: Int32(max(currentPeers.count, peers.count))))
            |> mapError { _ -> BlockedPeersContextAddError in
                return .generic
            }
            |> mapToSignal { _ -> Signal<Never, BlockedPeersContextAddError> in
                return .complete()
            }
        }
    }
    
    public func add(peerId: PeerId) -> Signal<Never, BlockedPeersContextAddError> {
        assert(Queue.mainQueue().isCurrent())
        
        let postbox = self.account.postbox
        let network = self.account.network
        let subject = self.subject
        
        var flags: Int32 = 0
        if case .stories = self.subject {
            flags |= 1 << 0
        }
    
        return self.account.postbox.transaction { transaction -> Api.InputPeer? in
            return transaction.getPeer(peerId).flatMap(apiInputPeer)
        }
        |> castError(BlockedPeersContextAddError.self)
        |> mapToSignal { [weak self] inputPeer -> Signal<Never, BlockedPeersContextAddError> in
            guard let inputPeer = inputPeer else {
                return .fail(.generic)
            }
            return network.request(Api.functions.contacts.block(flags: flags, id: inputPeer))
            |> mapError { _ -> BlockedPeersContextAddError in
                return .generic
            }
            |> mapToSignal { _ -> Signal<Peer?, BlockedPeersContextAddError> in
                return postbox.transaction { transaction -> Peer? in
                    if peerId.namespace == Namespaces.Peer.CloudUser {
                        transaction.updatePeerCachedData(peerIds: Set([peerId]), update: { _, current in
                            let previous: CachedUserData
                            if let current = current as? CachedUserData {
                                previous = current
                            } else {
                                previous = CachedUserData()
                            }
                            if case .stories = subject {
                                var userFlags = previous.flags
                                userFlags.insert(.isBlockedFromStories)
                                return previous.withUpdatedFlags(userFlags)
                            } else {
                                return previous.withUpdatedIsBlocked(true)
                            }
                        })
                    }
                    
                    return transaction.getPeer(peerId)
                }
                |> castError(BlockedPeersContextAddError.self)
            }
            |> deliverOnMainQueue
            |> mapToSignal { peer -> Signal<Never, BlockedPeersContextAddError> in
                guard let strongSelf = self, let peer = peer else {
                    return .complete()
                }
                
                var mergedPeers = strongSelf._state.peers
                let existingPeerIds = Set(mergedPeers.map { $0.peerId })
                if !existingPeerIds.contains(peer.id) {
                    mergedPeers.insert(RenderedPeer(peer: peer), at: 0)
                }
                
                let updatedTotalCount: Int?
                if let totalCount = strongSelf._state.totalCount {
                    updatedTotalCount = totalCount + 1
                } else {
                    updatedTotalCount = nil
                }
                
                strongSelf._state = BlockedPeersContextState(isLoadingMore: strongSelf._state.isLoadingMore, canLoadMore: strongSelf._state.canLoadMore, totalCount: updatedTotalCount, peers: mergedPeers)
                return .complete()
            }
        }
    }
    
    public func remove(peerId: PeerId) -> Signal<Never, BlockedPeersContextRemoveError> {
        assert(Queue.mainQueue().isCurrent())
        let postbox = self.account.postbox
        let network = self.account.network
        let subject = self.subject
        
        var flags: Int32 = 0
        if case .stories = self.subject {
            flags |= 1 << 0
        }
        
        return self.account.postbox.transaction { transaction -> Api.InputPeer? in
            return transaction.getPeer(peerId).flatMap(apiInputPeer)
        }
        |> castError(BlockedPeersContextRemoveError.self)
        |> mapToSignal { [weak self] inputPeer -> Signal<Never, BlockedPeersContextRemoveError> in
            guard let inputPeer = inputPeer else {
                return .fail(.generic)
            }
            return network.request(Api.functions.contacts.unblock(flags: flags, id: inputPeer))
            |> mapError { _ -> BlockedPeersContextRemoveError in
                return .generic
            }
            |> mapToSignal { value in
                return postbox.transaction { transaction -> Peer? in
                    if peerId.namespace == Namespaces.Peer.CloudUser {
                        transaction.updatePeerCachedData(peerIds: Set([peerId]), update: { _, current in
                            let previous: CachedUserData
                            if let current = current as? CachedUserData {
                                previous = current
                            } else {
                                previous = CachedUserData()
                            }
                            if case .stories = subject {
                                var userFlags = previous.flags
                                userFlags.remove(.isBlockedFromStories)
                                return previous.withUpdatedFlags(userFlags)
                            } else {
                                return previous.withUpdatedIsBlocked(false)
                            }
                        })
                    }
                    return transaction.getPeer(peerId)
                }
                |> castError(BlockedPeersContextRemoveError.self)
            }
            |> deliverOnMainQueue
            |> mapToSignal { _ -> Signal<Never, BlockedPeersContextRemoveError> in
                guard let strongSelf = self else {
                    return .complete()
                }
                
                var mergedPeers = strongSelf._state.peers
                var found = false
                for i in 0 ..< mergedPeers.count {
                    if mergedPeers[i].peerId == peerId {
                        found = true
                        mergedPeers.remove(at: i)
                        break
                    }
                }
                
                let updatedTotalCount: Int?
                if let totalCount = strongSelf._state.totalCount {
                    if found {
                        updatedTotalCount = totalCount - 1
                    } else {
                        updatedTotalCount = totalCount
                    }
                } else {
                    updatedTotalCount = nil
                }
                
                strongSelf._state = BlockedPeersContextState(isLoadingMore: strongSelf._state.isLoadingMore, canLoadMore: strongSelf._state.canLoadMore, totalCount: updatedTotalCount, peers: mergedPeers)
                return .complete()
            }
        }
    }
}
