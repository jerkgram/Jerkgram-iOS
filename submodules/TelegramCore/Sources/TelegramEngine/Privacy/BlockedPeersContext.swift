import Foundation
internal import TelegramApi
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

    // A history transformation takes one immutable account-scoped value snapshot.
    // It retains no controller, subscription, or cross-mapping cache.
    public struct MessageFilterSnapshot {
        public let accountPeerId: PeerId
        public let blockedPeerIds: Set<PeerId>

        public init(accountPeerId: PeerId, blockedPeerIds: Set<PeerId>) {
            self.accountPeerId = accountPeerId
            self.blockedPeerIds = blockedPeerIds
        }

        public func isHidden(authorId: PeerId?) -> Bool {
            guard let authorId, authorId != self.accountPeerId else {
                return false
            }
            return self.blockedPeerIds.contains(authorId)
        }
    }
    // Build175 snapshot end

    public static func messageFilterSnapshot(accountPeerId: PeerId, chatPeer: Peer?) -> MessageFilterSnapshot? {
        guard self.isGroupChat(chatPeer), self.hideBlockedMessages(accountPeerId: accountPeerId) else {
            return nil
        }
        return MessageFilterSnapshot(accountPeerId: accountPeerId, blockedPeerIds: self.blockedPeerIds(accountPeerId: accountPeerId))
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
    private var nextOffset: Int32 = 0
    private var requestGeneration: UInt64 = 0

    private struct Page {
        let peers: [RenderedPeer]
        let count: Int
        let rawCount: Int32
        let canLoadMore: Bool
    }
    
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
        guard !self._state.isLoadingMore, self._state.canLoadMore else { return }
        self.requestGeneration &+= 1
        let generation = self.requestGeneration
        let offset = self.nextOffset
        let requestDisposable = MetaDisposable()
        self.disposable.set(requestDisposable)
        guard self.requestGeneration == generation else { return }
        self._state = BlockedPeersContextState(isLoadingMore: true, canLoadMore: self._state.canLoadMore, totalCount: self._state.totalCount, peers: self._state.peers)
        guard self.requestGeneration == generation else { return }
        let postbox = self.account.postbox
        let accountPeerId = self.account.peerId
        var flags: Int32 = 0
        if case .stories = self.subject { flags |= 1 << 0 }
        let limit: Int32 = offset == 0 ? 200 : 100
        var receivedResult = false
        requestDisposable.set((self.account.network.request(Api.functions.contacts.getBlocked(flags: flags, offset: offset, limit: limit))
        |> retryRequestIfNotFrozen
        |> mapToSignal { result -> Signal<Page?, NoError> in
            guard let result else { return .single(nil) }
            return postbox.transaction { transaction -> Page? in
                let blocked: [Api.PeerBlocked]
                let chats: [Api.Chat]
                let users: [Api.User]
                let count: Int
                let isSlice: Bool
                switch result {
                case let .blocked(data):
                    blocked = data.blocked
                    chats = data.chats
                    users = data.users
                    count = Int(offset) + blocked.count
                    isSlice = false
                case let .blockedSlice(data):
                    blocked = data.blocked
                    chats = data.chats
                    users = data.users
                    count = max(0, Int(data.count))
                    isSlice = true
                }
                let parsedPeers = AccumulatedPeers(transaction: transaction, chats: chats, users: users)
                updatePeers(transaction: transaction, accountPeerId: accountPeerId, peers: parsedPeers)
                var renderedPeers: [RenderedPeer] = []
                for blockedPeer in blocked {
                    switch blockedPeer {
                    case let .peerBlocked(data):
                        if let peer = transaction.getPeer(data.peerId.peerId) {
                            renderedPeers.append(RenderedPeer(peer: peer))
                        }
                    }
                }
                return Page(peers: renderedPeers, count: count, rawCount: Int32(clamping: blocked.count), canLoadMore: isSlice && !blocked.isEmpty && Int(offset) + blocked.count < count)
            }
        }
        |> deliverOnMainQueue).start(next: { [weak self] page in
            guard let self, self.requestGeneration == generation else { return }
            receivedResult = true
            guard let page else {
                self._state = BlockedPeersContextState(isLoadingMore: false, canLoadMore: false, totalCount: self._state.totalCount, peers: self._state.peers)
                return
            }
            self.nextOffset = Int32(clamping: Int64(offset) + Int64(page.rawCount))
            var mergedPeers: [RenderedPeer] = []
            var indices: [PeerId: Int] = [:]
            for peer in (offset == 0 ? [] : self._state.peers) + page.peers {
                if let index = indices[peer.peerId] {
                    mergedPeers[index] = peer
                } else {
                    indices[peer.peerId] = mergedPeers.count
                    mergedPeers.append(peer)
                }
            }
            self._state = BlockedPeersContextState(isLoadingMore: false, canLoadMore: page.canLoadMore, totalCount: max(mergedPeers.count, page.count), peers: mergedPeers)
        }, completed: { [weak self] in
            guard let self, self.requestGeneration == generation, !receivedResult else { return }
            self._state = BlockedPeersContextState(isLoadingMore: false, canLoadMore: true, totalCount: self._state.totalCount, peers: self._state.peers)
        }))
    }

    private func applyUpdatedPeers(_ peers: [RenderedPeer], totalCount: Int?) {
        self.requestGeneration &+= 1
        let generation = self.requestGeneration
        self.nextOffset = 0
        self.disposable.set(nil)
        guard self.requestGeneration == generation else { return }
        self._state = BlockedPeersContextState(isLoadingMore: false, canLoadMore: true, totalCount: totalCount.map { max(peers.count, $0) }, peers: peers)
        guard self.requestGeneration == generation else { return }
        self.loadMore()
    }

    public func updatePeerIds(_ peerIds: [EnginePeer.Id]) -> Signal<Never, BlockedPeersContextAddError> {
        assert(Queue.mainQueue().isCurrent())
        let postbox = self.account.postbox
        let network = self.account.network
        let subject = self.subject
        let currentPeerIds = Set(self._state.peers.map { $0.peerId })
        var flags: Int32 = 0
        if case .stories = subject { flags |= 1 << 0 }
        return postbox.transaction { transaction -> ([Peer], [Api.InputPeer])? in
            var peers: [Peer] = []
            var inputs: [Api.InputPeer] = []
            var seen = Set<PeerId>()
            for peerId in peerIds where seen.insert(peerId).inserted {
                guard let peer = transaction.getPeer(peerId), let input = apiInputPeer(peer) else { return nil }
                peers.append(peer)
                inputs.append(input)
            }
            return (peers, inputs)
        }
        |> castError(BlockedPeersContextAddError.self)
        |> mapToSignal { [weak self] result -> Signal<Never, BlockedPeersContextAddError> in
            guard let (peers, inputs) = result else { return .fail(.generic) }
            return network.request(Api.functions.contacts.setBlocked(flags: flags, id: inputs, limit: Int32(clamping: inputs.count)))
            |> mapError { _ -> BlockedPeersContextAddError in .generic }
            |> deliverOnMainQueue
            |> mapToSignal { [weak self] result -> Signal<[Peer], BlockedPeersContextAddError> in
                guard case .boolTrue = result else { return .fail(.generic) }
                let previousPeerIds = currentPeerIds.union(self?._state.peers.map { $0.peerId } ?? [])
                return postbox.transaction { transaction -> [Peer] in
                    let validPeerIds = Set(peers.map { $0.id })
                    let allPeerIds = previousPeerIds.union(validPeerIds).filter { $0.namespace == Namespaces.Peer.CloudUser }
                    transaction.updatePeerCachedData(peerIds: Set(allPeerIds), update: { peerId, current in
                        let previous = current as? CachedUserData ?? CachedUserData()
                        if case .stories = subject {
                            var userFlags = previous.flags
                            if validPeerIds.contains(peerId) {
                                userFlags.insert(.isBlockedFromStories)
                            } else {
                                userFlags.remove(.isBlockedFromStories)
                            }
                            return previous.withUpdatedFlags(userFlags)
                        } else {
                            return previous.withUpdatedIsBlocked(validPeerIds.contains(peerId))
                        }
                    })
                    return peers
                }
                |> castError(BlockedPeersContextAddError.self)
            }
            |> deliverOnMainQueue
            |> mapToSignal { [weak self] peers -> Signal<Never, BlockedPeersContextAddError> in
                self?.applyUpdatedPeers(peers.map(RenderedPeer.init), totalCount: peers.count)
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
            |> mapToSignal { result -> Signal<Peer?, BlockedPeersContextAddError> in
                guard case .boolTrue = result else { return .fail(.generic) }
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
                    updatedTotalCount = max(mergedPeers.count, totalCount + (existingPeerIds.contains(peer.id) ? 0 : 1))
                } else {
                    updatedTotalCount = nil
                }
                
                strongSelf.applyUpdatedPeers(mergedPeers, totalCount: updatedTotalCount)
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
            |> mapToSignal { result -> Signal<Peer?, BlockedPeersContextRemoveError> in
                guard case .boolTrue = result else { return .fail(.generic) }
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
                        updatedTotalCount = max(mergedPeers.count, totalCount - 1)
                    } else {
                        updatedTotalCount = totalCount
                    }
                } else {
                    updatedTotalCount = nil
                }
                
                strongSelf.applyUpdatedPeers(mergedPeers, totalCount: updatedTotalCount)
                return .complete()
            }
        }
    }
}
