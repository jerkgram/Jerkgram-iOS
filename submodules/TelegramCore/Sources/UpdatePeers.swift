import Foundation
import Postbox
import TelegramApi


// MARK: GhostBase v1.1G PRESENCEBOUNDED1
public struct GhostBasePresenceHistoryEvent: Codable, Equatable {
    public var eventId: String?
    public let observedAt: Int64
    public let status: String
    public let until: Int32?
    public let lastActivity: Int32
    public let isHidden: Bool
}

public struct GhostBaseKnownUser: Codable, Equatable {
    public let peerId: Int64
    public var title: String
    public var username: String?
    public var isBot: Bool
    public var firstSeen: Int64
    public var lastSeen: Int64
}

private enum GhostBasePresenceStoreV11G {
    static let queue = DispatchQueue(
        label: "jerkgram.PresenceStore.V11G",
        qos: .utility
    )
    static let maximumEvents = 500
    static let maximumKnownUsers = 5000
    static let minimumKnownUserWriteInterval: Int64 = 6 * 60 * 60

    // Queue-confined caches prevent repeated JSON decoding on every update.
    private static var histories: [String: [GhostBasePresenceHistoryEvent]] = [:]
    private static var loadedHistoryKeys: Set<String> = []
    private static var knownUsers: [String: GhostBaseKnownUser] = [:]
    private static var loadedKnownUserKeys: Set<String> = []

    static func historyKey(accountPeerId: PeerId, peerId: PeerId) -> String {
        return "jerkgram.PresenceHistory1.\(accountPeerId.toInt64()).\(peerId.toInt64())"
    }

    static func knownUserIdsKey(_ accountPeerId: PeerId) -> String {
        return "jerkgram.PresenceGlobal1.KnownUserIds.\(accountPeerId.toInt64())"
    }

    static func knownUserKey(accountPeerId: PeerId, peerId: PeerId) -> String {
        return "jerkgram.PresenceGlobal1.KnownUser.\(accountPeerId.toInt64()).\(peerId.toInt64())"
    }

    static func event(_ presence: TelegramUserPresence) -> GhostBasePresenceHistoryEvent? {
        let status: String
        let until: Int32?
        let isHidden: Bool
        switch presence.status {
        case .none:
            return nil
        case let .present(value):
            status = "онлайн"
            until = value
            isHidden = false
        case let .recently(hidden):
            status = "был недавно"
            until = nil
            isHidden = hidden
        case let .lastWeek(hidden):
            status = "был на этой неделе"
            until = nil
            isHidden = hidden
        case let .lastMonth(hidden):
            status = "был в этом месяце"
            until = nil
            isHidden = hidden
        }
        return GhostBasePresenceHistoryEvent(
            eventId: UUID().uuidString.lowercased(),
            observedAt: Int64(Date().timeIntervalSince1970),
            status: status,
            until: until,
            lastActivity: presence.lastActivity,
            isHidden: isHidden
        )
    }

    static func structuralKey(_ event: GhostBasePresenceHistoryEvent) -> String {
        return "\(event.observedAt)|\(event.status)|\(event.until.map(String.init) ?? "-")|\(event.lastActivity)|\(event.isHidden)"
    }

    static func migratedEventId(_ event: GhostBasePresenceHistoryEvent, index: Int) -> String {
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in "\(index)|\(self.structuralKey(event))".utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 1_099_511_628_211
        }
        return "presence-v1-" + String(hash, radix: 16)
    }

    static func compact(_ source: [GhostBasePresenceHistoryEvent]) -> [GhostBasePresenceHistoryEvent] {
        var result: [GhostBasePresenceHistoryEvent] = []
        result.reserveCapacity(min(source.count, self.maximumEvents))
        var identities = Set<String>()
        for (index, sourceEvent) in source.enumerated() {
            var event = sourceEvent
            if event.status == "нет данных" {
                continue
            }
            if event.eventId == nil {
                // Stable migration identity uses structural fields and the
                // stored ordinal, never localized display text alone.
                event.eventId = self.migratedEventId(event, index: index)
            }
            guard let eventId = event.eventId,
                  identities.insert(eventId).inserted else {
                continue
            }
            result.append(event)
        }
        if result.count > self.maximumEvents {
            result.removeFirst(result.count - self.maximumEvents)
        }
        return result
    }

    static func recordPresence(
        accountPeerId: PeerId,
        peerId: PeerId,
        presence: TelegramUserPresence
    ) {
        guard let event = self.event(presence) else {
            return
        }
        self.queue.async {
            let key = self.historyKey(
                accountPeerId: accountPeerId,
                peerId: peerId
            )
            let defaults = UserDefaults.standard
            var events: [GhostBasePresenceHistoryEvent]
            if self.loadedHistoryKeys.contains(key) {
                events = self.histories[key] ?? []
            } else {
                self.loadedHistoryKeys.insert(key)
                if let data = defaults.data(forKey: key),
                   let decoded = try? JSONDecoder().decode(
                    [GhostBasePresenceHistoryEvent].self,
                    from: data
                   ) {
                    events = self.compact(decoded)
                } else {
                    events = []
                }
                self.histories[key] = events
            }
            if let previous = events.last,
               previous.status == event.status,
               previous.until == event.until,
               previous.lastActivity == event.lastActivity,
               previous.isHidden == event.isHidden,
               event.observedAt - previous.observedAt <= 2 {
                return
            }
            events.append(event)
            events = self.compact(events)
            self.histories[key] = events
            if let data = try? JSONEncoder().encode(events) {
                defaults.set(data, forKey: key)
                defaults.set(
                    "История присутствия: \(events.count) переходов",
                    forKey: "jerkgram.Runtime.PresenceSummary.V11G"
                )
            }
        }
    }

    static func registerKnownUser(
        accountPeerId: PeerId,
        user: TelegramUser
    ) {
        let peerId = user.id
        let title = user.nameOrPhone
        let username = user.addressName
        let isBot = user.botInfo != nil

        self.queue.async {
            let defaults = UserDefaults.standard
            let key = self.knownUserKey(
                accountPeerId: accountPeerId,
                peerId: peerId
            )
            let now = Int64(Date().timeIntervalSince1970)
            let previous: GhostBaseKnownUser?
            if self.loadedKnownUserKeys.contains(key) {
                previous = self.knownUsers[key]
            } else {
                self.loadedKnownUserKeys.insert(key)
                if let data = defaults.data(forKey: key) {
                    previous = try? JSONDecoder().decode(
                        GhostBaseKnownUser.self,
                        from: data
                    )
                } else {
                    previous = nil
                }
                if let previous {
                    self.knownUsers[key] = previous
                }
            }

            if let previous,
               previous.title == title,
               previous.username == username,
               previous.isBot == isBot,
               now - previous.lastSeen < self.minimumKnownUserWriteInterval {
                return
            }

            let record = GhostBaseKnownUser(
                peerId: peerId.toInt64(),
                title: title,
                username: username,
                isBot: isBot,
                firstSeen: previous?.firstSeen ?? now,
                lastSeen: now
            )
            self.knownUsers[key] = record
            if let data = try? JSONEncoder().encode(record) {
                defaults.set(data, forKey: key)
            }

            if previous == nil {
                let idsKey = self.knownUserIdsKey(accountPeerId)
                var ids = (defaults.array(forKey: idsKey) as? [NSNumber])?
                    .map { $0.int64Value } ?? []
                if !ids.contains(record.peerId) {
                    ids.append(record.peerId)
                }
                if ids.count > self.maximumKnownUsers {
                    let removed = ids.prefix(ids.count - self.maximumKnownUsers)
                    for rawId in removed {
                        let oldPeerId = PeerId(
                            namespace: Namespaces.Peer.CloudUser,
                            id: PeerId.Id._internalFromInt64Value(rawId)
                        )
                        defaults.removeObject(
                            forKey: self.knownUserKey(
                                accountPeerId: accountPeerId,
                                peerId: oldPeerId
                            )
                        )
                    }
                    ids.removeFirst(ids.count - self.maximumKnownUsers)
                }
                defaults.set(
                    ids.map { NSNumber(value: $0) },
                    forKey: idsKey
                )
                defaults.set(
                    "Известные пользователи: \(ids.count)",
                    forKey: "jerkgram.Runtime.KnownUsersSummary.V11G"
                )
            }
        }
    }
}

private func ghostBaseRecordPresence(
    accountPeerId: PeerId,
    peerId: PeerId,
    presence: TelegramUserPresence
) {
    GhostBasePresenceStoreV11G.recordPresence(
        accountPeerId: accountPeerId,
        peerId: peerId,
        presence: presence
    )
}

private func ghostBaseRegisterKnownUser(
    accountPeerId: PeerId,
    user: TelegramUser
) {
    GhostBasePresenceStoreV11G.registerKnownUser(
        accountPeerId: accountPeerId,
        user: user
    )
}

public func ghostBasePresenceHistoryEvents(
    accountPeerId: PeerId,
    peerId: PeerId
) -> [GhostBasePresenceHistoryEvent] {
    let key = GhostBasePresenceStoreV11G.historyKey(
        accountPeerId: accountPeerId,
        peerId: peerId
    )
    guard let data = UserDefaults.standard.data(forKey: key),
          let decoded = try? JSONDecoder().decode(
            [GhostBasePresenceHistoryEvent].self,
            from: data
          ) else {
        return []
    }
    return GhostBasePresenceStoreV11G.compact(decoded)
}

public func ghostBasePresenceHistoryReport(
    accountPeerId: PeerId,
    peerId: PeerId
) -> String? {
    let events = ghostBasePresenceHistoryEvents(
        accountPeerId: accountPeerId,
        peerId: peerId
    )
    guard !events.isEmpty else {
        return nil
    }

    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "ru_RU")
    formatter.dateFormat = "dd.MM.yyyy HH:mm:ss"

    var lines = ["История присутствия: \(events.count) переходов"]
    for event in events.reversed() {
        var details: [String] = []
        if event.status == "онлайн", let until = event.until,
           Int64(until) >= event.observedAt {
            details.append(
                "до \(formatter.string(from: Date(timeIntervalSince1970: TimeInterval(until))))"
            )
        }
        if event.isHidden {
            details.append("скрытый статус")
        }
        let suffix = details.isEmpty
            ? ""
            : " · " + details.joined(separator: " · ")
        lines.append(
            "\(formatter.string(from: Date(timeIntervalSince1970: TimeInterval(event.observedAt)))) · \(event.status)\(suffix)"
        )
    }
    return lines.joined(separator: "\n")
}

public func ghostBaseKnownUsers(
    accountPeerId: PeerId
) -> [GhostBaseKnownUser] {
    let defaults = UserDefaults.standard
    let ids = (defaults.array(
        forKey: GhostBasePresenceStoreV11G.knownUserIdsKey(accountPeerId)
    ) as? [NSNumber])?.map { $0.int64Value } ?? []

    var result: [GhostBaseKnownUser] = []
    result.reserveCapacity(min(ids.count, GhostBasePresenceStoreV11G.maximumKnownUsers))
    for rawId in ids.suffix(GhostBasePresenceStoreV11G.maximumKnownUsers) {
        let peerId = PeerId(
            namespace: Namespaces.Peer.CloudUser,
            id: PeerId.Id._internalFromInt64Value(rawId)
        )
        let key = GhostBasePresenceStoreV11G.knownUserKey(
            accountPeerId: accountPeerId,
            peerId: peerId
        )
        if let data = defaults.data(forKey: key),
           let user = try? JSONDecoder().decode(
            GhostBaseKnownUser.self,
            from: data
           ) {
            result.append(user)
        }
    }
    return result.sorted { $0.lastSeen > $1.lastSeen }
}

public func ghostBaseKnownUsersReport(accountPeerId: PeerId) -> String {
    let users = ghostBaseKnownUsers(accountPeerId: accountPeerId)
    var lines = ["Известные пользователи: \(users.count)"]
    for user in users.prefix(200) {
        lines.append(
            "\(user.title) · id=\(user.peerId) · username=\(user.username ?? "nil") · bot=\(user.isBot)"
        )
    }
    return lines.joined(separator: "\n")
}

func isPeerHiddenByCollapsedCommunity(transaction: Transaction, peerId: PeerId, peer: Peer? = nil) -> Bool {
    if let channel = (peer ?? transaction.getPeer(peerId)) as? TelegramChannel, let linkedCommunityId = channel.linkedCommunityId {
        if let community = transaction.getPeer(linkedCommunityId) as? TelegramCommunity, community.collapsedInDialogs == true {
            return true
        }
    }

    return false
}

func shouldExcludePeerFromChatList(transaction: Transaction, peerId: PeerId, peer: Peer? = nil) -> Bool {
    guard let peer = peer ?? transaction.getPeer(peerId) else {
        return false
    }

    if let group = peer as? TelegramGroup {
        if group.flags.contains(.deactivated) {
            return true
        }
        switch group.membership {
        case .Member:
            return false
        default:
            return true
        }
    } else if let channel = peer as? TelegramChannel {
        switch channel.participationStatus {
        case .member:
            return isPeerHiddenByCollapsedCommunity(transaction: transaction, peerId: peerId, peer: channel)
        default:
            return true
        }
    } else if let community = peer as? TelegramCommunity {
        return community.participationStatus != .member || community.collapsedInDialogs != true
    } else {
        return false
    }
}

func updatePeerChatInclusionWithMinTimestamp(transaction: Transaction, id: PeerId, minTimestamp: Int32, forceRootGroupIfNotExists: Bool, peer: Peer? = nil) {
    if shouldExcludePeerFromChatList(transaction: transaction, peerId: id, peer: peer) {
        transaction.updatePeerChatListInclusion(id, inclusion: .notIncluded)
        return
    }
    
    let currentInclusion = transaction.getPeerChatListInclusion(id)
    var updatedInclusion: PeerChatListInclusion?
    switch currentInclusion {
        case let .ifHasMessagesOrOneOf(groupId, pinningIndex, currentMinTimestamp):
            let updatedMinTimestamp: Int32
            if let currentMinTimestamp = currentMinTimestamp {
                if minTimestamp > currentMinTimestamp {
                    updatedMinTimestamp = minTimestamp
                } else {
                    updatedMinTimestamp = currentMinTimestamp
                }
            } else {
                updatedMinTimestamp = minTimestamp
            }
            updatedInclusion = .ifHasMessagesOrOneOf(groupId: groupId, pinningIndex: pinningIndex, minTimestamp: updatedMinTimestamp)
        default:
            if forceRootGroupIfNotExists {
                updatedInclusion = .ifHasMessagesOrOneOf(groupId: .root, pinningIndex: nil, minTimestamp: minTimestamp)
            }
    }
    if let updatedInclusion = updatedInclusion {
        transaction.updatePeerChatListInclusion(id, inclusion: updatedInclusion)
    }
}

func minTimestampForPeerInclusion(_ peer: Peer) -> Int32? {
    if let group = peer as? TelegramGroup {
        return group.creationDate
    } else if let channel = peer as? TelegramChannel {
        return channel.creationDate
    } else if let community = peer as? TelegramCommunity {
        return community.creationDate
    } else {
        return nil
    }
}

func updateCommunityChatListInclusion(transaction: Transaction, communityId: EnginePeer.Id, collapsedInDialogs: Bool, minTimestamp: Int32?) {
    if !collapsedInDialogs {
        if transaction.getPeerChatListInclusion(communityId) != .notIncluded {
            transaction.updatePeerChatListInclusion(communityId, inclusion: .notIncluded)
        }
        return
    }
    
    guard let community = transaction.getPeer(communityId) else {
        return
    }

    let currentInclusion = transaction.getPeerChatListInclusion(communityId)
    let effectiveMinTimestamp = minTimestamp ?? minTimestampForPeerInclusion(community)
    guard let effectiveMinTimestamp else {
        return
    }
    switch currentInclusion {
    case let .ifHasMessagesOrOneOf(groupId, pinningIndex, currentMinTimestamp):
        let updatedMinTimestamp: Int32
        if let currentMinTimestamp = currentMinTimestamp {
            if effectiveMinTimestamp > currentMinTimestamp {
                updatedMinTimestamp = effectiveMinTimestamp
            } else {
                updatedMinTimestamp = currentMinTimestamp
            }
        } else {
            updatedMinTimestamp = effectiveMinTimestamp
        }
        transaction.updatePeerChatListInclusion(communityId, inclusion: .ifHasMessagesOrOneOf(groupId: groupId, pinningIndex: pinningIndex, minTimestamp: updatedMinTimestamp))
    default:
        transaction.updatePeerChatListInclusion(communityId, inclusion: .ifHasMessagesOrOneOf(
            groupId: .root,
            pinningIndex: transaction.getPeerChatListIndex(communityId)?.1.pinningIndex,
            minTimestamp: effectiveMinTimestamp
        ))
    }
}

func shouldKeepUserStoriesInFeed(peerId: PeerId, isContactOrMember: Bool) -> Bool {
    if peerId.namespace == Namespaces.Peer.CloudUser && (peerId.id._internalGetInt64Value() == 777000 || peerId.id._internalGetInt64Value() == 333000) {
        return true
    }
    return isContactOrMember
}

func updatePeers(transaction: Transaction, accountPeerId: PeerId, peers: AccumulatedPeers) {
    var parsedPeers: [Peer] = []
    for (_, user) in peers.users {
        if let telegramUser = TelegramUser.merge(transaction.getPeer(user.peerId) as? TelegramUser, rhs: user) {
            // MARK: GhostBase v1.1A PRESENCEGLOBAL1 register every received user
            ghostBaseRegisterKnownUser(
                accountPeerId: accountPeerId,
                user: telegramUser
            )
            parsedPeers.append(telegramUser)
            switch user {
            case let .user(userData):
                let (flags, flags2, storiesMaxId) = (userData.flags, userData.flags2, userData.storiesMaxId)
                let isMin = (flags & (1 << 20)) != 0
                let storiesUnavailable = (flags2 & (1 << 4)) != 0
                
                if let storiesMaxId {
                    switch storiesMaxId {
                    case let .recentStory(recentStoryData):
                        let (flags, maxId) = (recentStoryData.flags, recentStoryData.maxId)
                        if let maxId {
                            transaction.setStoryItemsInexactMaxId(peerId: user.peerId, id: maxId, hasLiveItems: (flags & (1 << 0)) != 0)
                        } else {
                            if !isMin && storiesUnavailable {
                                transaction.clearStoryItemsInexactMaxId(peerId: user.peerId)
                            }
                        }
                    }
                } else if !isMin && storiesUnavailable {
                    transaction.clearStoryItemsInexactMaxId(peerId: user.peerId)
                }
                
                if !isMin {
                    let isContact = (flags & (1 << 11)) != 0
                    _internal_updatePeerIsContact(transaction: transaction, user: telegramUser, isContact: isContact)
                }
            case .userEmpty:
                break
            }
        }
    }
    for (_, chat) in peers.chats {
        switch chat {
        case let .channel(channelData):
            let (flags, flags2, storiesMaxId) = (channelData.flags, channelData.flags2, channelData.storiesMaxId)
            let isMin = (flags & (1 << 12)) != 0
            let storiesUnavailable = (flags2 & (1 << 3)) != 0
            
            if let storiesMaxId {
                switch storiesMaxId {
                case let .recentStory(recentStoryData):
                    let (flags, maxId) = (recentStoryData.flags, recentStoryData.maxId)
                    if let maxId {
                        transaction.setStoryItemsInexactMaxId(peerId: chat.peerId, id: maxId, hasLiveItems: (flags & (1 << 0)) != 0)
                    } else {
                        if !isMin && storiesUnavailable {
                            transaction.clearStoryItemsInexactMaxId(peerId: chat.peerId)
                        }
                    }
                }
            } else if !isMin && storiesUnavailable {
                transaction.clearStoryItemsInexactMaxId(peerId: chat.peerId)
            }
        default:
            break
        }
    }
    for (_, peer) in peers.peers {
        parsedPeers.append(peer)
    }
    updatePeersCustom(transaction: transaction, peers: parsedPeers, update: { _, updated in updated })
    
    updatePeerPresences(transaction: transaction, accountPeerId: accountPeerId, peerPresences: peers.users)
}

func _internal_updatePeerIsContact(transaction: Transaction, user: TelegramUser, isContact: Bool) {
    let previousValue = shouldKeepUserStoriesInFeed(peerId: user.id, isContactOrMember: transaction.isPeerContact(peerId: user.id))
    let updatedValue = shouldKeepUserStoriesInFeed(peerId: user.id, isContactOrMember: isContact)
    
    if previousValue != updatedValue, let storiesHidden = user.storiesHidden {
        if updatedValue {
            if storiesHidden {
                if transaction.storySubscriptionsContains(key: .filtered, peerId: user.id) {
                    var (state, peerIds) = transaction.getAllStorySubscriptions(key: .filtered)
                    peerIds.removeAll(where: { $0 == user.id })
                    transaction.replaceAllStorySubscriptions(key: .filtered, state: state, peerIds: peerIds)
                }
                if !transaction.storySubscriptionsContains(key: .hidden, peerId: user.id) {
                    var (state, peerIds) = transaction.getAllStorySubscriptions(key: .hidden)
                    if !peerIds.contains(user.id) {
                        peerIds.append(user.id)
                        transaction.replaceAllStorySubscriptions(key: .hidden, state: state, peerIds: peerIds)
                    }
                }
            } else {
                if transaction.storySubscriptionsContains(key: .hidden, peerId: user.id) {
                    var (state, peerIds) = transaction.getAllStorySubscriptions(key: .hidden)
                    peerIds.removeAll(where: { $0 == user.id })
                    transaction.replaceAllStorySubscriptions(key: .hidden, state: state, peerIds: peerIds)
                }
                if !transaction.storySubscriptionsContains(key: .filtered, peerId: user.id) {
                    var (state, peerIds) = transaction.getAllStorySubscriptions(key: .filtered)
                    if !peerIds.contains(user.id) {
                        peerIds.append(user.id)
                        transaction.replaceAllStorySubscriptions(key: .filtered, state: state, peerIds: peerIds)
                    }
                }
            }
        } else {
            if transaction.storySubscriptionsContains(key: .filtered, peerId: user.id) {
                var (state, peerIds) = transaction.getAllStorySubscriptions(key: .filtered)
                peerIds.removeAll(where: { $0 == user.id })
                transaction.replaceAllStorySubscriptions(key: .filtered, state: state, peerIds: peerIds)
            }
            if transaction.storySubscriptionsContains(key: .hidden, peerId: user.id) {
                var (state, peerIds) = transaction.getAllStorySubscriptions(key: .hidden)
                peerIds.removeAll(where: { $0 == user.id })
                transaction.replaceAllStorySubscriptions(key: .hidden, state: state, peerIds: peerIds)
            }
        }
    }
}

private func _internal_updateChannelMembership(transaction: Transaction, channel: TelegramChannel, isMember: Bool, justJoined: Bool) {
    if isMember, let storiesHidden = channel.storiesHidden {
        if storiesHidden {
            if transaction.storySubscriptionsContains(key: .filtered, peerId: channel.id) {
                var (state, peerIds) = transaction.getAllStorySubscriptions(key: .filtered)
                peerIds.removeAll(where: { $0 == channel.id })
                transaction.replaceAllStorySubscriptions(key: .filtered, state: state, peerIds: peerIds)
            }
            if !transaction.storySubscriptionsContains(key: .hidden, peerId: channel.id) {
                var (state, peerIds) = transaction.getAllStorySubscriptions(key: .hidden)
                if !peerIds.contains(channel.id) {
                    peerIds.append(channel.id)
                    transaction.replaceAllStorySubscriptions(key: .hidden, state: state, peerIds: peerIds)
                }
            }
        } else {
            if transaction.storySubscriptionsContains(key: .hidden, peerId: channel.id) {
                var (state, peerIds) = transaction.getAllStorySubscriptions(key: .hidden)
                peerIds.removeAll(where: { $0 == channel.id })
                transaction.replaceAllStorySubscriptions(key: .hidden, state: state, peerIds: peerIds)
            }
            if !transaction.storySubscriptionsContains(key: .filtered, peerId: channel.id) {
                var (state, peerIds) = transaction.getAllStorySubscriptions(key: .filtered)
                if !peerIds.contains(channel.id) {
                    peerIds.append(channel.id)
                    transaction.replaceAllStorySubscriptions(key: .filtered, state: state, peerIds: peerIds)
                }
            }
        }
        
        if justJoined {
            _internal_addSynchronizePeerStoriesOperation(peerId: channel.id, transaction: transaction)
        }
    } else {
        if transaction.storySubscriptionsContains(key: .filtered, peerId: channel.id) {
            var (state, peerIds) = transaction.getAllStorySubscriptions(key: .filtered)
            peerIds.removeAll(where: { $0 == channel.id })
            transaction.replaceAllStorySubscriptions(key: .filtered, state: state, peerIds: peerIds)
        }
        if transaction.storySubscriptionsContains(key: .hidden, peerId: channel.id) {
            var (state, peerIds) = transaction.getAllStorySubscriptions(key: .hidden)
            peerIds.removeAll(where: { $0 == channel.id })
            transaction.replaceAllStorySubscriptions(key: .hidden, state: state, peerIds: peerIds)
        }
    }
}

public func updatePeersCustom(transaction: Transaction, peers: [Peer], update: (Peer?, Peer) -> Peer?) {
    transaction.updatePeersInternal(peers, update: { previous, updated in
        let peerId = updated.id
        
        var updated = updated
        
        if let previous = previous as? TelegramUser, let updatedUser = updated as? TelegramUser {
            updated = TelegramUser.merge(lhs: previous, rhs: updatedUser)
        }
        
        if let updatedChannel = updated as? TelegramChannel {
            var wasMember = false
            var wasHidden: Bool?
            if let previous = previous as? TelegramChannel {
                wasMember = previous.participationStatus == .member
                wasHidden = previous.storiesHidden
                updated = mergeChannel(lhs: previous, rhs: updatedChannel)
            }
            
            if let updated = updated as? TelegramChannel {
                let isMember = updated.participationStatus == .member
                if isMember != wasMember || updated.storiesHidden != wasHidden {
                    _internal_updateChannelMembership(transaction: transaction, channel: updated, isMember: isMember, justJoined: previous == nil || wasHidden == nil)
                }
            }
        }
        if let updatedCommunity = updated as? TelegramCommunity {
            updated = mergeCommunity(lhs: previous as? TelegramCommunity, rhs: updatedCommunity)
        }
        
        switch peerId.namespace {
            case Namespaces.Peer.CloudUser:
                if let updated = updated as? TelegramUser, let previous = previous as? TelegramUser {
                    if let storiesHidden = updated.storiesHidden, storiesHidden != previous.storiesHidden {
                        if storiesHidden {
                            if transaction.storySubscriptionsContains(key: .filtered, peerId: updated.id) {
                                var (state, peerIds) = transaction.getAllStorySubscriptions(key: .filtered)
                                peerIds.removeAll(where: { $0 == updated.id })
                                transaction.replaceAllStorySubscriptions(key: .filtered, state: state, peerIds: peerIds)
                                
                                if !transaction.storySubscriptionsContains(key: .hidden, peerId: updated.id) {
                                    var (state, peerIds) = transaction.getAllStorySubscriptions(key: .hidden)
                                    if !peerIds.contains(updated.id) {
                                        peerIds.append(updated.id)
                                        transaction.replaceAllStorySubscriptions(key: .hidden, state: state, peerIds: peerIds)
                                    }
                                }
                            }
                        } else {
                            if transaction.storySubscriptionsContains(key: .hidden, peerId: updated.id) {
                                var (state, peerIds) = transaction.getAllStorySubscriptions(key: .hidden)
                                peerIds.removeAll(where: { $0 == updated.id })
                                transaction.replaceAllStorySubscriptions(key: .hidden, state: state, peerIds: peerIds)
                                
                                if !transaction.storySubscriptionsContains(key: .filtered, peerId: updated.id) {
                                    var (state, peerIds) = transaction.getAllStorySubscriptions(key: .filtered)
                                    if !peerIds.contains(updated.id) {
                                        peerIds.append(updated.id)
                                        transaction.replaceAllStorySubscriptions(key: .filtered, state: state, peerIds: peerIds)
                                    }
                                }
                            }
                        }
                    }
                }
            case Namespaces.Peer.CloudGroup:
                if let group = updated as? TelegramGroup {
                    if group.flags.contains(.deactivated) {
                        transaction.updatePeerChatListInclusion(peerId, inclusion: .notIncluded)
                    } else {
                        switch group.membership {
                            case .Member:
                                updatePeerChatInclusionWithMinTimestamp(transaction: transaction, id: peerId, minTimestamp: group.creationDate, forceRootGroupIfNotExists: false, peer: group)
                            default:
                                transaction.updatePeerChatListInclusion(peerId, inclusion: .notIncluded)
                        }
                    }
                } else {
                    assertionFailure()
                }
            case Namespaces.Peer.CloudChannel:
                if let channel = updated as? TelegramChannel {
                    if case .personal = channel.accessHash {
                        switch channel.participationStatus {
                        case .member:
                            updatePeerChatInclusionWithMinTimestamp(transaction: transaction, id: peerId, minTimestamp: channel.creationDate, forceRootGroupIfNotExists: true, peer: channel)
                        case .left:
                            transaction.updatePeerChatListInclusion(peerId, inclusion: .notIncluded)
                        case .kicked where channel.creationDate == 0:
                            transaction.updatePeerChatListInclusion(peerId, inclusion: .notIncluded)
                        default:
                            transaction.updatePeerChatListInclusion(peerId, inclusion: .notIncluded)
                        }
                    }
                } else if let community = updated as? TelegramCommunity {
                    if case .personal = community.accessHash {
                        switch community.participationStatus {
                        case .member:
                            break
                        case .left:
                            transaction.updatePeerChatListInclusion(peerId, inclusion: .notIncluded)
                        case .kicked where community.creationDate == 0:
                            transaction.updatePeerChatListInclusion(peerId, inclusion: .notIncluded)
                        default:
                            transaction.updatePeerChatListInclusion(peerId, inclusion: .notIncluded)
                        }
                    }
                } else {
                    assertionFailure()
                }
            case Namespaces.Peer.SecretChat:
                if let secretChat = updated as? TelegramSecretChat {
                    let isActive: Bool
                    switch secretChat.embeddedState {
                        case .active, .handshake:
                            isActive = true
                        case .terminated:
                            isActive = false
                    }
                    updatePeerChatInclusionWithMinTimestamp(transaction: transaction, id: peerId, minTimestamp: secretChat.creationDate, forceRootGroupIfNotExists: isActive, peer: secretChat)
                } else {
                    assertionFailure()
                }
            default:
                assertionFailure()
                break
        }
        
        return update(previous, updated)
    })
}

func updatePeerPresences(transaction: Transaction, accountPeerId: PeerId, peerPresences: [PeerId: Api.User]) {
    var parsedPresences: [PeerId: PeerPresence] = [:]
    for (peerId, user) in peerPresences {
        guard let presence = TelegramUserPresence(apiUser: user) else {
            continue
        }
        ghostBaseRecordPresence(
            accountPeerId: accountPeerId,
            peerId: peerId,
            presence: presence
        )
        switch presence.status {
        case .present:
            parsedPresences[peerId] = presence
        default:
            switch user {
            case let .user(userData):
                let flags = userData.flags
                let isMin = (flags & (1 << 20)) != 0
                if isMin, let _ = transaction.getPeerPresence(peerId: peerId) {
                } else {
                    parsedPresences[peerId] = presence
                }
            default:
                break
            }
        }
    }
        
    parsedPresences.removeValue(forKey: accountPeerId)
        
    transaction.updatePeerPresencesInternal(presences: parsedPresences, merge: { previous, updated in
        if let previous = previous as? TelegramUserPresence, let updated = updated as? TelegramUserPresence, previous.lastActivity != updated.lastActivity {
            return TelegramUserPresence(status: updated.status, lastActivity: max(previous.lastActivity, updated.lastActivity))
        }
        return updated
    })
}

func updatePeerPresencesClean(transaction: Transaction, accountPeerId: PeerId, peerPresences: [PeerId: UpdatedApiPresence]) {
    var parsedPresences: [PeerId: PeerPresence] = [:]
    for (peerId, status) in peerPresences {
        let presence = TelegramUserPresence(apiStatus: status.status)
        ghostBaseRecordPresence(
            accountPeerId: accountPeerId,
            peerId: peerId,
            presence: presence
        )
        switch presence.status {
        case .present:
            parsedPresences[peerId] = presence
        default:
            if status.isMin, let _ = transaction.getPeerPresence(peerId: peerId) {
            } else {
                parsedPresences[peerId] = presence
            }
        }
    }
    
    if parsedPresences[accountPeerId] != nil {
        parsedPresences.removeValue(forKey: accountPeerId)
    }
    
    transaction.updatePeerPresencesInternal(presences: parsedPresences, merge: { previous, updated in
        if let previous = previous as? TelegramUserPresence, let updated = updated as? TelegramUserPresence, previous.lastActivity != updated.lastActivity {
            return TelegramUserPresence(status: updated.status, lastActivity: max(previous.lastActivity, updated.lastActivity))
        }
        return updated
    })
}

func updatePeerPresenceLastActivities(transaction: Transaction, accountPeerId: PeerId, activities: [PeerId: Int32]) {
    var activities = activities
    if activities[accountPeerId] != nil {
        activities.removeValue(forKey: accountPeerId)
    }
    for (peerId, timestamp) in activities {
        transaction.updatePeerPresenceInternal(peerId: peerId, update: { previous in
            if let previous = previous as? TelegramUserPresence, previous.lastActivity < timestamp {
                var updatedStatus = previous.status
                switch updatedStatus {
                    case let .present(until):
                        if until < timestamp {
                            updatedStatus = .present(until: timestamp)
                        }
                    default:
                        break
                }
                let updatedPresence = TelegramUserPresence(
                    status: updatedStatus,
                    lastActivity: timestamp
                )
                ghostBaseRecordPresence(
                    accountPeerId: accountPeerId,
                    peerId: peerId,
                    presence: updatedPresence
                )
                return updatedPresence
            }
            return previous
        })
    }
}

func updateContacts(transaction: Transaction, apiUsers: [Api.User]) {
    if apiUsers.isEmpty {
        return
    }
    var contactIds = transaction.getContactPeerIds()
    var updated = false
    for user in apiUsers {
        var isContact: Bool?
        switch user {
        case let .user(userData):
            let flags = userData.flags
            if (flags & (1 << 20)) == 0 {
                isContact = (flags & (1 << 11)) != 0
            }
        case .userEmpty:
            isContact = false
        }
        if let isContact = isContact {
            if isContact {
                if !contactIds.contains(user.peerId) {
                    contactIds.insert(user.peerId)
                    updated = true
                }
            } else {
                if contactIds.contains(user.peerId) {
                    contactIds.remove(user.peerId)
                    updated = true
                }
            }
        }
    }
    if updated {
        transaction.replaceContactPeerIds(contactIds)
    }
}
