import Foundation
import Postbox
import TelegramCore
import SwiftSignalKit
import Display
import TelegramUIPreferences
import AccountContext

public enum ChatListNodeLocation: Equatable {
    case initial(count: Int, filter: ChatListFilter?)
    case navigation(index: EngineChatList.Item.Index, filter: ChatListFilter?)
    case scroll(index: EngineChatList.Item.Index, sourceIndex: EngineChatList.Item.Index, scrollPosition: ListViewScrollPosition, animated: Bool, filter: ChatListFilter?)
    
    public var filter: ChatListFilter? {
        switch self {
        case let .initial(_, filter):
            return filter
        case let .navigation(_, filter):
            return filter
        case let .scroll(_, _, _, _, filter):
            return filter
        }
    }
}

public struct ChatListNodeViewUpdate {
    public let list: EngineChatList
    public let type: ViewUpdateType
    public let scrollPosition: ChatListNodeViewScrollPosition?
    
    public init(list: EngineChatList, type: ViewUpdateType, scrollPosition: ChatListNodeViewScrollPosition?) {
        self.list = list
        self.type = type
        self.scrollPosition = scrollPosition
    }
}

private func communityPeerId(item: EngineChatList.Item) -> EnginePeer.Id? {
    guard case let .chatList(peerId) = item.id else {
        return nil
    }
    if let peer = item.renderedPeer.peer, case let .community(community) = peer, community.collapsedInDialogs == true {
        return peerId
    } else {
        return nil
    }
}

private func filteredCommunityChatListItems(_ items: [EngineChatList.Item]) -> [EngineChatList.Item] {
    return items.filter { item in
        if let peer = item.renderedPeer.peer, case let .community(community) = peer {
            return community.collapsedInDialogs == true
        } else {
            return true
        }
    }
}

private func chatListNodeViewUpdateWithCommunitySummaries(account: Account, update: ChatListNodeViewUpdate) -> Signal<ChatListNodeViewUpdate, NoError> {
    let baseItems = filteredCommunityChatListItems(update.list.items)
    let baseList = EngineChatList(
        items: baseItems,
        groupItems: update.list.groupItems,
        additionalItems: update.list.additionalItems,
        hasEarlier: update.list.hasEarlier,
        hasLater: update.list.hasLater,
        isLoading: update.list.isLoading
    )
    let baseUpdate = ChatListNodeViewUpdate(list: baseList, type: update.type, scrollPosition: update.scrollPosition)

    let communityIds = baseItems.compactMap { item in
        return communityPeerId(item: item)
    }
    if communityIds.isEmpty {
        return .single(baseUpdate)
    }

    var isFirstSummary = true
    return communityChatListItemSummaries(postbox: account.postbox, communityIds: communityIds)
    |> map { summaries -> ChatListNodeViewUpdate in
        let updatedType: ViewUpdateType
        let updatedScrollPosition: ChatListNodeViewScrollPosition?
        if isFirstSummary {
            updatedType = update.type
            updatedScrollPosition = update.scrollPosition
            isFirstSummary = false
        } else {
            updatedType = .Generic
            updatedScrollPosition = nil
        }

        let items = baseItems.map { item -> EngineChatList.Item in
            guard let communityId = communityPeerId(item: item), let summary = summaries[communityId], summary.hasLinkedPeers else {
                return item
            }
            let messages = summary.topMessage.map { [$0] } ?? item.messages
            return item.withUpdatedCommunitySummary(messages: messages, readCounters: summary.readCounters ?? item.readCounters)
        }

        let list = EngineChatList(
            items: items,
            groupItems: baseList.groupItems,
            additionalItems: baseList.additionalItems,
            hasEarlier: baseList.hasEarlier,
            hasLater: baseList.hasLater,
            isLoading: baseList.isLoading
        )
        return ChatListNodeViewUpdate(list: list, type: updatedType, scrollPosition: updatedScrollPosition)
    }
}

public func chatListFilterPredicate(filter: ChatListFilterData, accountPeerId: EnginePeer.Id) -> ChatListFilterPredicate {
    var includePeers = Set(filter.includePeers.peers)
    var excludePeers = Set(filter.excludePeers)
    
    if !filter.includePeers.pinnedPeers.isEmpty {
        includePeers.subtract(filter.includePeers.pinnedPeers)
        excludePeers.subtract(filter.includePeers.pinnedPeers)
    }
    
    var includeAdditionalPeerGroupIds: [PeerGroupId] = []
    if !filter.excludeArchived {
        includeAdditionalPeerGroupIds.append(Namespaces.PeerGroup.archive)
    }
    
    var messageTagSummary: ChatListMessageTagSummaryResultCalculation?
    if filter.excludeRead || filter.excludeMuted {
        messageTagSummary = ChatListMessageTagSummaryResultCalculation(addCount: ChatListMessageTagSummaryResultComponent(tag: .unseenPersonalMessage, namespace: Namespaces.Message.Cloud), subtractCount: ChatListMessageTagActionsSummaryResultComponent(type: PendingMessageActionType.consumeUnseenPersonalMessage, namespace: Namespaces.Message.Cloud))
    }
    return ChatListFilterPredicate(includePeerIds: includePeers, excludePeerIds: excludePeers, pinnedPeerIds: filter.includePeers.pinnedPeers, messageTagSummary: messageTagSummary, includeAdditionalPeerGroupIds: includeAdditionalPeerGroupIds, include: { peer, isMuted, isUnread, isContact, messageTagSummaryResult in
        if filter.excludeRead {
            var effectiveUnread = isUnread
            if let messageTagSummaryResult = messageTagSummaryResult, messageTagSummaryResult {
                effectiveUnread = true
            }
            if !effectiveUnread {
                return false
            }
        }
        if filter.excludeMuted {
            if isMuted {
                if let messageTagSummaryResult = messageTagSummaryResult, messageTagSummaryResult {
                } else {
                    return false
                }
            }
        }
        if !filter.categories.contains(.contacts) && isContact {
            if let user = peer as? TelegramUser {
                if user.botInfo == nil && !user.flags.contains(.isSupport) {
                    return false
                }
            } else if let _ = peer as? TelegramSecretChat {
                return false
            }
        }
        if !filter.categories.contains(.nonContacts) && (!isContact && peer.id != accountPeerId) {
            if let user = peer as? TelegramUser {
                if user.botInfo == nil {
                    return false
                }
            } else if let _ = peer as? TelegramSecretChat {
                return false
            }
        }
        if filter.categories.contains(.nonContacts) && peer.id == accountPeerId {
            return false
        }
        if !filter.categories.contains(.bots) {
            if let user = peer as? TelegramUser {
                if user.botInfo != nil || user.flags.contains(.isSupport) {
                    return false
                }
            }
        }
        if !filter.categories.contains(.groups) {
            if let _ = peer as? TelegramGroup {
                return false
            } else if let channel = peer as? TelegramChannel {
                if case .group = channel.info {
                    return false
                }
            } else if let _ = peer as? TelegramCommunity {
                return false
            }
        }
        if !filter.categories.contains(.channels) {
            if let channel = peer as? TelegramChannel {
                if case .broadcast = channel.info {
                    return false
                }
            }
        }
        return true
    })
}


private func jerkgramBuild134ChatListPresentationUpdates<T>(
    _ signal: Signal<T, NoError>
) -> Signal<T, NoError> {
    return combineLatest(
        signal,
        JerkgramBlockedReactionPolicy.presentationUpdates
    )
    |> map { value, _ in
        return value
    }
}


private struct JerkgramBuild136VisibilityCacheKey: Hashable {
    let accountPeerId: PeerId
    let peerId: PeerId
}

private struct JerkgramBuild136VisibilityCacheEntry {
    let sourceIndex: EngineChatList.Item.Index
    let stockUnreadCount: Int
    let presentationRevision: Int32
    let fallbackMessage: EngineMessage?
    let hiddenUnreadCount: Int32
}

private struct JerkgramBuild136VisibilityCacheState {
    var entries: [JerkgramBuild136VisibilityCacheKey: JerkgramBuild136VisibilityCacheEntry] = [:]
    var insertionOrder: [JerkgramBuild136VisibilityCacheKey] = []
}

private let jerkgramBuild136VisibilityCache = Atomic(
    value: JerkgramBuild136VisibilityCacheState()
)

private let jerkgramBuild136VisibilityCacheLimit = 256

private func jerkgramBuild136ClearVisibilityCache(accountPeerId: PeerId) {
    let _ = jerkgramBuild136VisibilityCache.modify { current in
        var current = current
        let keys = current.entries.keys.filter { key in key.accountPeerId == accountPeerId }
        guard !keys.isEmpty else {
            return current
        }
        let removed = Set(keys)
        for key in keys {
            current.entries.removeValue(forKey: key)
        }
        current.insertionOrder.removeAll(where: { removed.contains($0) })
        return current
    }
}

private func jerkgramBuild136StoreVisibilityCache(
    _ additions: [JerkgramBuild136VisibilityCacheKey: JerkgramBuild136VisibilityCacheEntry],
    removing removals: Set<JerkgramBuild136VisibilityCacheKey>
) {
    guard !additions.isEmpty || !removals.isEmpty else {
        return
    }
    let _ = jerkgramBuild136VisibilityCache.modify { current in
        var current = current
        for key in removals {
            current.entries.removeValue(forKey: key)
        }
        if !removals.isEmpty {
            current.insertionOrder.removeAll(where: { removals.contains($0) })
        }
        for (key, value) in additions {
            if current.entries[key] == nil {
                current.insertionOrder.append(key)
            }
            current.entries[key] = value
        }
        while current.insertionOrder.count > jerkgramBuild136VisibilityCacheLimit {
            let removed = current.insertionOrder.removeFirst()
            current.entries.removeValue(forKey: removed)
        }
        return current
    }
}

private func jerkgramBuild136ReadCounters(
    _ counters: EnginePeerReadCounters?,
    subtracting hiddenUnreadCount: Int32
) -> EnginePeerReadCounters? {
    guard hiddenUnreadCount > 0, let counters, let state = counters._asReadCounters() else {
        return counters
    }
    var remaining = hiddenUnreadCount
    let states = state.states.map { namespace, value -> (MessageId.Namespace, PeerReadState) in
        guard namespace == Namespaces.Message.Cloud, remaining > 0 else {
            return (namespace, value)
        }
        switch value {
        case let .idBased(maxIncomingReadId, maxOutgoingReadId, maxKnownId, count, markedUnread):
            let removed = min(count, remaining)
            remaining -= removed
            return (namespace, .idBased(
                maxIncomingReadId: maxIncomingReadId,
                maxOutgoingReadId: maxOutgoingReadId,
                maxKnownId: maxKnownId,
                count: max(0, count - removed),
                markedUnread: markedUnread
            ))
        case let .indexBased(maxIncomingReadIndex, maxOutgoingReadIndex, count, markedUnread):
            let removed = min(count, remaining)
            remaining -= removed
            return (namespace, .indexBased(
                maxIncomingReadIndex: maxIncomingReadIndex,
                maxOutgoingReadIndex: maxOutgoingReadIndex,
                count: max(0, count - removed),
                markedUnread: markedUnread
            ))
        }
    }
    return EnginePeerReadCounters(state: CombinedPeerReadState(states: states), isMuted: counters.isMuted)
}

private func jerkgramBuild136PresentationIndex(
    sourceIndex: EngineChatList.Item.Index,
    cached: JerkgramBuild136VisibilityCacheEntry?
) -> EngineChatList.Item.Index? {
    guard let cached,
          cached.sourceIndex == sourceIndex,
          let message = cached.fallbackMessage,
          case let .chatList(index) = sourceIndex,
          index.pinningIndex == nil,
          message.id != index.messageIndex.id else {
        return nil
    }
    return .chatList(EngineChatList.Item.Index.ChatList(
        pinningIndex: nil,
        messageIndex: message.index
    ))
}

private func jerkgramBuild136Applying(
    _ cached: JerkgramBuild136VisibilityCacheEntry,
    to item: EngineChatList.Item
) -> EngineChatList.Item {
    var messages = item.messages
    if messages.isEmpty, let fallbackMessage = cached.fallbackMessage {
        messages = [fallbackMessage]
    }
    return item.withUpdatedCommunitySummary(
        messages: messages,
        readCounters: jerkgramBuild136ReadCounters(
            item.readCounters,
            subtracting: cached.hiddenUnreadCount
        ),
        jerkgramPresentationIndex: jerkgramBuild136PresentationIndex(
            sourceIndex: item.index,
            cached: cached
        )
    )
}

private func jerkgramBuild136VisibleChatListUpdate(
    account: Account,
    update: ChatListNodeViewUpdate
) -> Signal<ChatListNodeViewUpdate, NoError> {
    guard JerkgramBlockedReactionPolicy.hideBlockedMessages(accountPeerId: account.peerId) else {
        jerkgramBuild136ClearVisibilityCache(accountPeerId: account.peerId)
        return .single(update)
    }
    let blockedPeerIds = JerkgramBlockedReactionPolicy.blockedPeerIds(accountPeerId: account.peerId)
    guard !blockedPeerIds.isEmpty else {
        jerkgramBuild136ClearVisibilityCache(accountPeerId: account.peerId)
        return .single(update)
    }

    let presentationRevision = JerkgramBlockedReactionPolicy.presentationRevisionValue
    let cachedEntries = jerkgramBuild136VisibilityCache.with { current in current.entries }
    var reusable: [PeerId: JerkgramBuild136VisibilityCacheEntry] = [:]
    var missingPeerIds = Set<PeerId>()
    for item in update.list.items {
        guard case let .chatList(peerId) = item.id,
              let peer = item.renderedPeer.peer,
              JerkgramBlockedReactionPolicy.isGroupChat(peer._asPeer()),
              item.messages.isEmpty || (item.readCounters?.count ?? 0) > 0 else {
            continue
        }
        let key = JerkgramBuild136VisibilityCacheKey(accountPeerId: account.peerId, peerId: peerId)
        let stockUnreadCount = Int(item.readCounters?.count ?? 0)
        let mustRefreshFallback: Bool
        if item.messages.isEmpty {
            switch update.type {
            case .Generic, .FillHole:
                mustRefreshFallback = true
            default:
                mustRefreshFallback = false
            }
        } else {
            mustRefreshFallback = false
        }
        if let cached = cachedEntries[key],
           cached.sourceIndex == item.index,
           cached.stockUnreadCount == stockUnreadCount,
           cached.presentationRevision == presentationRevision,
           !mustRefreshFallback {
            reusable[peerId] = cached
        } else {
            missingPeerIds.insert(peerId)
        }
    }

    let buildUpdate: ([PeerId: JerkgramBuild136VisibilityCacheEntry]) -> ChatListNodeViewUpdate = { resolved in
        let items = update.list.items.map { item -> EngineChatList.Item in
            guard case let .chatList(peerId) = item.id,
                  let cached = resolved[peerId] else {
                return item
            }
            return jerkgramBuild136Applying(cached, to: item)
        }.sorted { lhs, rhs in
            let lhsIndex = lhs.jerkgramPresentationIndex ?? lhs.index
            let rhsIndex = rhs.jerkgramPresentationIndex ?? rhs.index
            return lhsIndex < rhsIndex
        }
        return ChatListNodeViewUpdate(
            list: EngineChatList(
                items: items,
                groupItems: update.list.groupItems,
                additionalItems: update.list.additionalItems,
                hasEarlier: update.list.hasEarlier,
                hasLater: update.list.hasLater,
                isLoading: update.list.isLoading
            ),
            type: update.type,
            scrollPosition: update.scrollPosition
        )
    }

    guard !missingPeerIds.isEmpty else {
        return .single(buildUpdate(reusable))
    }

    return account.postbox.transaction { transaction -> ChatListNodeViewUpdate in
        var resolved = reusable
        var newCacheEntries: [JerkgramBuild136VisibilityCacheKey: JerkgramBuild136VisibilityCacheEntry] = [:]
        var removedCacheKeys = Set<JerkgramBuild136VisibilityCacheKey>()
        for item in update.list.items {
            guard case let .chatList(peerId) = item.id,
                  missingPeerIds.contains(peerId),
                  let chatPeer = transaction.getPeer(peerId),
                  JerkgramBlockedReactionPolicy.isGroupChat(chatPeer) else {
                continue
            }

            let stockUnreadCount = Int(item.readCounters?.count ?? 0)
            let requestedCount = min(512, max(64, stockUnreadCount + 32))
            let historyView = transaction.getMessagesHistoryViewState(
                input: .single(peerId: peerId, threadId: nil),
                ignoreMessagesInTimestampRange: nil,
                ignoreMessageIds: Set(),
                count: requestedCount,
                clipHoles: true,
                anchor: .upperBound,
                namespaces: .just(Set([Namespaces.Message.Cloud]))
            )
            let cacheKey = JerkgramBuild136VisibilityCacheKey(
                accountPeerId: account.peerId,
                peerId: peerId
            )
            if historyView.isLoading {
                removedCacheKeys.insert(cacheKey)
                resolved.removeValue(forKey: peerId)
                continue
            }
            var hiddenUnreadCount: Int32 = 0
            for entry in historyView.entries where !entry.isRead && entry.message.flags.contains(.Incoming) {
                if JerkgramBlockedReactionPolicy.isMessageHidden(
                    accountPeerId: account.peerId,
                    chatPeer: chatPeer,
                    message: entry.message
                ) {
                    hiddenUnreadCount += 1
                }
            }
            let fallbackMessage = historyView.entries.reversed().first(where: { entry in
                !JerkgramBlockedReactionPolicy.isMessageHidden(
                    accountPeerId: account.peerId,
                    chatPeer: chatPeer,
                    message: entry.message
                )
            }).map { EngineMessage($0.message) }
            let cached = JerkgramBuild136VisibilityCacheEntry(
                sourceIndex: item.index,
                stockUnreadCount: stockUnreadCount,
                presentationRevision: presentationRevision,
                fallbackMessage: fallbackMessage,
                hiddenUnreadCount: hiddenUnreadCount
            )
            resolved[peerId] = cached
            if !item.messages.isEmpty || fallbackMessage != nil {
                newCacheEntries[cacheKey] = cached
            } else {
                removedCacheKeys.insert(cacheKey)
                resolved.removeValue(forKey: peerId)
            }
        }
        jerkgramBuild136StoreVisibilityCache(newCacheEntries, removing: removedCacheKeys)
        return buildUpdate(resolved)
    }
}

public func chatListViewForLocation(chatListLocation: ChatListControllerLocation, location: ChatListNodeLocation, account: Account, shouldLoadCanMessagePeer: Bool) -> Signal<ChatListNodeViewUpdate, NoError> {
    let accountPeerId = account.peerId
    
    switch chatListLocation {
    case let .chatList(groupId):
        let filterPredicate: ChatListFilterPredicate?
        if let filter = location.filter, case let .filter(_, _, _, data) = filter {
            filterPredicate = chatListFilterPredicate(filter: data, accountPeerId: account.peerId)
        } else {
            filterPredicate = nil
        }
        
        switch location {
        case let .initial(count, _):
            let signal: Signal<(ChatListView, ViewUpdateType), NoError>
            signal = account.viewTracker.tailChatListView(groupId: groupId._asGroup(), filterPredicate: filterPredicate, count: count, shouldLoadCanMessagePeer: shouldLoadCanMessagePeer)
            return jerkgramBuild134ChatListPresentationUpdates(signal)
            |> map { view, updateType -> ChatListNodeViewUpdate in
                return ChatListNodeViewUpdate(list: EngineChatList(view, accountPeerId: accountPeerId), type: updateType, scrollPosition: nil)
            }
            |> mapToSignal { update -> Signal<ChatListNodeViewUpdate, NoError> in
                return chatListNodeViewUpdateWithCommunitySummaries(account: account, update: update)
                |> mapToSignal { summarized in
                    return jerkgramBuild136VisibleChatListUpdate(account: account, update: summarized)
                }
            }
        case let .navigation(index, _):
            guard case let .chatList(index) = index else {
                return .never()
            }
            var first = true
            return jerkgramBuild134ChatListPresentationUpdates(
                account.viewTracker.aroundChatListView(groupId: groupId._asGroup(), filterPredicate: filterPredicate, index: index, count: 80, shouldLoadCanMessagePeer: shouldLoadCanMessagePeer)
            )
            |> map { view, updateType -> ChatListNodeViewUpdate in
                let genericType: ViewUpdateType
                if first {
                    first = false
                    genericType = ViewUpdateType.UpdateVisible
                } else {
                    genericType = updateType
                }
                return ChatListNodeViewUpdate(list: EngineChatList(view, accountPeerId: accountPeerId), type: genericType, scrollPosition: nil)
            }
            |> mapToSignal { update -> Signal<ChatListNodeViewUpdate, NoError> in
                return chatListNodeViewUpdateWithCommunitySummaries(account: account, update: update)
                |> mapToSignal { summarized in
                    return jerkgramBuild136VisibleChatListUpdate(account: account, update: summarized)
                }
            }
        case let .scroll(index, sourceIndex, scrollPosition, animated, _):
            guard case let .chatList(index) = index else {
                return .never()
            }
            
            let directionHint: ListViewScrollToItemDirectionHint = sourceIndex > .chatList(index) ? .Down : .Up
            let chatScrollPosition: ChatListNodeViewScrollPosition = .index(index: index, position: scrollPosition, directionHint: directionHint, animated: animated)
            var first = true
            return jerkgramBuild134ChatListPresentationUpdates(
                account.viewTracker.aroundChatListView(groupId: groupId._asGroup(), filterPredicate: filterPredicate, index: index, count: 80, shouldLoadCanMessagePeer: shouldLoadCanMessagePeer)
            )
            |> map { view, updateType -> ChatListNodeViewUpdate in
                let genericType: ViewUpdateType
                let scrollPosition: ChatListNodeViewScrollPosition? = first ? chatScrollPosition : nil
                if first {
                    first = false
                    genericType = ViewUpdateType.UpdateVisible
                } else {
                    genericType = updateType
                }
                return ChatListNodeViewUpdate(list: EngineChatList(view, accountPeerId: accountPeerId), type: genericType, scrollPosition: scrollPosition)
            }
            |> mapToSignal { update -> Signal<ChatListNodeViewUpdate, NoError> in
                return chatListNodeViewUpdateWithCommunitySummaries(account: account, update: update)
                |> mapToSignal { summarized in
                    return jerkgramBuild136VisibleChatListUpdate(account: account, update: summarized)
                }
            }
        }
    case let .forum(peerId):
        let viewKey: PostboxViewKey = .messageHistoryThreadIndex(
            id: peerId,
            summaryComponents: ChatListEntrySummaryComponents(
                components: [
                    ChatListEntryMessageTagSummaryKey(
                        tag: .unseenPersonalMessage,
                        actionType: PendingMessageActionType.consumeUnseenPersonalMessage
                    ): ChatListEntrySummaryComponents.Component(
                        tagSummary: ChatListEntryMessageTagSummaryComponent(namespace: Namespaces.Message.Cloud),
                        actionsSummary: ChatListEntryPendingMessageActionsSummaryComponent(namespace: Namespaces.Message.Cloud)
                    ),
                    ChatListEntryMessageTagSummaryKey(
                        tag: .unseenReaction,
                        actionType: PendingMessageActionType.readReactionOrPollVote
                    ): ChatListEntrySummaryComponents.Component(
                        tagSummary: ChatListEntryMessageTagSummaryComponent(namespace: Namespaces.Message.Cloud),
                        actionsSummary: ChatListEntryPendingMessageActionsSummaryComponent(namespace: Namespaces.Message.Cloud)
                    ),
                    ChatListEntryMessageTagSummaryKey(
                        tag: .unseenPollVote,
                        actionType: PendingMessageActionType.readReactionOrPollVote
                    ): ChatListEntrySummaryComponents.Component(
                        tagSummary: ChatListEntryMessageTagSummaryComponent(namespace: Namespaces.Message.Cloud),
                        actionsSummary: ChatListEntryPendingMessageActionsSummaryComponent(namespace: Namespaces.Message.Cloud)
                    )
                ]
            )
        )
        
        let readStateKey: PostboxViewKey = .combinedReadState(peerId: peerId, handleThreads: false)
        
        var isFirst = false
        return account.postbox.combinedView(keys: [viewKey, readStateKey])
        |> map { views -> ChatListNodeViewUpdate in
            guard let view = views.views[viewKey] as? MessageHistoryThreadIndexView else {
                preconditionFailure()
            }
            guard let readStateView = views.views[readStateKey] as? CombinedReadStateView else {
                preconditionFailure()
            }
            
            var maxReadId: Int32 = 0
            if let state = readStateView.state?.states.first(where: { $0.0 == Namespaces.Message.Cloud }) {
                if case let .idBased(maxIncomingReadId, _, _, _, _) = state.1 {
                    maxReadId = maxIncomingReadId
                }
            }
            
            var items: [EngineChatList.Item] = []
            for item in view.items {
                guard let peer = view.peer else {
                    continue
                }
                guard let data = item.info.get(MessageHistoryThreadData.self) else {
                    continue
                }
                
                let defaultPeerNotificationSettings: TelegramPeerNotificationSettings = (view.peerNotificationSettings as? TelegramPeerNotificationSettings) ?? .defaultSettings
                
                var hasUnseenMentions = false
                
                var isMuted = false
                switch data.notificationSettings.muteState {
                case .muted:
                    isMuted = true
                case .unmuted:
                    isMuted = false
                case .default:
                    if case .default = data.notificationSettings.muteState {
                        if case .muted = defaultPeerNotificationSettings.muteState {
                            isMuted = true
                        }
                    }
                }
                
                if let info = item.tagSummaryInfo[ChatListEntryMessageTagSummaryKey(
                    tag: .unseenPersonalMessage,
                    actionType: PendingMessageActionType.consumeUnseenPersonalMessage
                )] {
                    hasUnseenMentions = (info.tagSummaryCount ?? 0) > (info.actionsSummaryCount ?? 0)
                }
                
                var hasUnseenReactions = false
                if let info = item.tagSummaryInfo[ChatListEntryMessageTagSummaryKey(
                    tag: .unseenReaction,
                    actionType: PendingMessageActionType.readReactionOrPollVote
                )] {
                    hasUnseenReactions = (info.tagSummaryCount ?? 0) != 0
                }
                
                var hasUnseenPollVotes = false
                if let info = item.tagSummaryInfo[ChatListEntryMessageTagSummaryKey(
                    tag: .unseenPollVote,
                    actionType: PendingMessageActionType.readReactionOrPollVote
                )] {
                    hasUnseenPollVotes = (info.tagSummaryCount ?? 0) != 0
                }
                
                let pinnedIndex: EngineChatList.Item.PinnedIndex
                if let index = item.pinnedIndex {
                    pinnedIndex = .index(index)
                } else {
                    pinnedIndex = .none
                }
                
                var topicMaxIncomingReadId = data.maxIncomingReadId
                if data.maxIncomingReadId == 0 && maxReadId != 0 && Int64(maxReadId) <= item.id {
                    topicMaxIncomingReadId = max(topicMaxIncomingReadId, maxReadId)
                }
                
                let readCounters = EnginePeerReadCounters(state: CombinedPeerReadState(states: [(Namespaces.Message.Cloud, .idBased(maxIncomingReadId: topicMaxIncomingReadId, maxOutgoingReadId: data.maxOutgoingReadId, maxKnownId: 1, count: data.incomingUnreadCount, markedUnread: false))]), isMuted: false)
                
                var draft: EngineChatList.Draft?
                if let embeddedState = item.embeddedInterfaceState, let _ = embeddedState.overrideChatTimestamp {
                    if let opaqueState = _internal_decodeStoredChatInterfaceState(state: embeddedState) {
                        if let text = opaqueState.synchronizeableInputState?.text {
                            draft = EngineChatList.Draft(text: text, entities: opaqueState.synchronizeableInputState?.entities ?? [])
                        }
                    }
                }
                
                items.append(EngineChatList.Item(
                    id: .forum(item.id),
                    index: .forum(pinnedIndex: pinnedIndex, timestamp: item.index.timestamp, threadId: item.id, namespace: item.index.id.namespace, id: item.index.id.id),
                    messages: item.topMessage.flatMap { [EngineMessage($0)] } ?? [],
                    readCounters: readCounters,
                    isMuted: isMuted,
                    draft: draft,
                    threadData: data,
                    renderedPeer: EngineRenderedPeer(peer: EnginePeer(peer)),
                    presence: nil,
                    hasUnseenMentions: hasUnseenMentions,
                    hasUnseenReactions: hasUnseenReactions,
                    hasUnseenPollVotes: hasUnseenPollVotes,
                    forumTopicData: nil,
                    topForumTopicItems: [],
                    hasFailed: false,
                    isContact: false,
                    autoremoveTimeout: nil,
                    storyStats: nil,
                    displayAsTopicList: false,
                    isPremiumRequiredToMessage: false,
                    mediaDraftContentType: nil
                ))
            }
            
            let list = EngineChatList(
                items: items.reversed(),
                groupItems: [],
                additionalItems: [],
                hasEarlier: false,
                hasLater: false,
                isLoading: view.isLoading
            )
            
            let type: ViewUpdateType
            if isFirst {
                type = .Initial
            } else {
                type = .Generic
            }
            isFirst = false
            return ChatListNodeViewUpdate(list: list, type: type, scrollPosition: nil)
        }
    case let .savedMessagesChats(peerId):
        let viewKey: PostboxViewKey = .savedMessagesIndex(peerId: peerId)
        let interfaceStateKey: PostboxViewKey = .chatInterfaceState(peerId: peerId)
        
        var isFirst = true
        return account.postbox.combinedView(keys: [viewKey, interfaceStateKey])
        |> map { views -> ChatListNodeViewUpdate in
            guard let view = views.views[viewKey] as? MessageHistorySavedMessagesIndexView else {
                preconditionFailure()
            }
            
            var draft: EngineChatList.Draft?
            if let interfaceStateView = views.views[interfaceStateKey] as? ChatInterfaceStateView {
                if let embeddedState = interfaceStateView.value, let _ = embeddedState.overrideChatTimestamp {
                    if let opaqueState = _internal_decodeStoredChatInterfaceState(state: embeddedState) {
                        if let text = opaqueState.synchronizeableInputState?.text {
                            draft = EngineChatList.Draft(text: text, entities: opaqueState.synchronizeableInputState?.entities ?? [])
                        }
                    }
                }
            }
             
            var items: [EngineChatList.Item] = []
            for item in view.items {
                guard let sourcePeer = item.peer else {
                    continue
                }
                
                let sourceId = PeerId(item.id)
                
                var messages: [EngineMessage] = []
                if let topMessage = item.topMessage {
                    messages.append(EngineMessage(topMessage))
                }
                
                let mappedMessageIndex = MessageIndex(id: MessageId(peerId: sourceId, namespace: item.index.id.namespace, id: item.index.id.id), timestamp: item.index.timestamp)
                
                let readCounters = EnginePeerReadCounters(state: CombinedPeerReadState(states: [(Namespaces.Message.Cloud, .idBased(maxIncomingReadId: 0, maxOutgoingReadId: 0, maxKnownId: 0, count: Int32(item.unreadCount), markedUnread: item.markedUnread))]), isMuted: false)
                
                var itemDraft: EngineChatList.Draft?
                if let embeddedState = item.embeddedInterfaceState, let _ = embeddedState.overrideChatTimestamp {
                    if let opaqueState = _internal_decodeStoredChatInterfaceState(state: embeddedState) {
                        if let text = opaqueState.synchronizeableInputState?.text {
                            itemDraft = EngineChatList.Draft(text: text, entities: opaqueState.synchronizeableInputState?.entities ?? [])
                        }
                    }
                }
                
                items.append(EngineChatList.Item(
                    id: .chatList(sourceId),
                    index: .chatList(ChatListIndex(pinningIndex: item.pinnedIndex.flatMap(UInt16.init), messageIndex: mappedMessageIndex)),
                    messages: messages,
                    readCounters: readCounters,
                    isMuted: false,
                    draft: sourceId == accountPeerId ? draft : itemDraft,
                    threadData: nil,
                    renderedPeer: EngineRenderedPeer(peer: EnginePeer(sourcePeer)),
                    presence: nil,
                    hasUnseenMentions: false,
                    hasUnseenReactions: false,
                    hasUnseenPollVotes: false,
                    forumTopicData: nil,
                    topForumTopicItems: [],
                    hasFailed: false,
                    isContact: false,
                    autoremoveTimeout: nil,
                    storyStats: nil,
                    displayAsTopicList: false,
                    isPremiumRequiredToMessage: false,
                    mediaDraftContentType: nil
                ))
            }
            
            let list = EngineChatList(
                items: items.reversed(),
                groupItems: [],
                additionalItems: [],
                hasEarlier: false,
                hasLater: false,
                isLoading: view.isLoading
            )
            
            let type: ViewUpdateType
            if isFirst {
                type = .Initial
            } else {
                type = .Generic
            }
            isFirst = false
            return ChatListNodeViewUpdate(list: list, type: type, scrollPosition: nil)
        }
    }
}
