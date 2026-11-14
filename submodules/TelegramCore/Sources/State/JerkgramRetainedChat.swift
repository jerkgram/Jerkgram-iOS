import Foundation
import Postbox
import JerkgramCore

public func jerkgramIsRetainedExcludedChat(_ peer: Peer?) -> Bool {
    if let peer = peer as? TelegramChannel {
        return peer.participationStatus == .kicked && peer.flags.contains(.jerkgramRetainedExcluded)
    }
    if let peer = peer as? TelegramGroup {
        return peer.membership == .Removed && peer.flags.contains(.jerkgramRetainedExcluded)
    }
    return false
}

func jerkgramRetainExcludedPeer(previous: Peer?, updated: Peer, enabled: Bool) -> Peer {
    if let previous = previous as? TelegramChannel, let updated = updated as? TelegramChannel,
       JerkgramRetainedChatPolicy.keep(excluded: updated.participationStatus == .kicked, wasMember: previous.participationStatus == .member, wasRetained: jerkgramIsRetainedExcludedChat(previous), enabled: enabled) {
        var flags = previous.flags
        flags.insert(.jerkgramRetainedExcluded)
        flags.remove(.isCreator)
        flags.remove(.hasVoiceChat)
        flags.remove(.hasActiveVoiceChat)
        return TelegramChannel(id: previous.id, accessHash: previous.accessHash, title: updated.title.isEmpty ? previous.title : updated.title, username: previous.username, photo: previous.photo, creationDate: previous.creationDate, version: updated.version, participationStatus: updated.participationStatus, info: previous.info, flags: flags, restrictionInfo: updated.restrictionInfo ?? previous.restrictionInfo, adminRights: nil, bannedRights: updated.bannedRights, defaultBannedRights: previous.defaultBannedRights, usernames: previous.usernames, storiesHidden: previous.storiesHidden, nameColor: previous.nameColor, backgroundEmojiId: previous.backgroundEmojiId, profileColor: previous.profileColor, profileBackgroundEmojiId: previous.profileBackgroundEmojiId, emojiStatus: previous.emojiStatus, approximateBoostLevel: previous.approximateBoostLevel, subscriptionUntilDate: previous.subscriptionUntilDate, verificationIconFileId: previous.verificationIconFileId, sendPaidMessageStars: previous.sendPaidMessageStars, linkedMonoforumId: previous.linkedMonoforumId, linkedCommunityId: previous.linkedCommunityId)
    }
    if let previous = previous as? TelegramGroup, let updated = updated as? TelegramGroup,
       JerkgramRetainedChatPolicy.keep(excluded: updated.membership == .Removed && !updated.flags.contains(.deactivated), wasMember: previous.membership == .Member, wasRetained: jerkgramIsRetainedExcludedChat(previous), enabled: enabled) {
        var flags = previous.flags
        flags.insert(.jerkgramRetainedExcluded)
        flags.remove(.hasVoiceChat)
        flags.remove(.hasActiveVoiceChat)
        return TelegramGroup(id: updated.id, title: updated.title.isEmpty ? previous.title : updated.title, photo: previous.photo, participantCount: previous.participantCount, role: .member, membership: updated.membership, flags: flags, defaultBannedRights: updated.defaultBannedRights, migrationReference: previous.migrationReference, creationDate: previous.creationDate, version: updated.version)
    }
    return updated
}

func jerkgramClearRetainedExcludedChat(transaction: Transaction, peer: Peer) {
    let cleared: Peer
    if let channel = peer as? TelegramChannel {
        var flags = channel.flags
        flags.remove(.jerkgramRetainedExcluded)
        cleared = channel.withUpdatedFlags(flags)
    } else if let group = peer as? TelegramGroup {
        var flags = group.flags
        flags.remove(.jerkgramRetainedExcluded)
        cleared = group.updateFlags(flags: flags, version: group.version)
    } else { return }
    transaction.removeItemCacheEntry(id: jerkgramRetainedMembersKey(peerId: peer.id))
    // The explicit update result clears the bit even while normal merge preserves it.
    updatePeersCustom(transaction: transaction, peers: [cleared], update: { _, _ in cleared })
}

private struct JerkgramRetainedMembersSnapshot: Codable {
    let data: Data
}

func jerkgramRetainedMembersKey(peerId: PeerId) -> ItemCacheEntryId {
    let key = ValueBoxKey(length: 8)
    key.setInt64(0, value: peerId.toInt64())
    return ItemCacheEntryId(collectionId: Namespaces.CachedItemCollection.jerkgramRetainedChatMembers, key: key)
}

private func jerkgramSavedMembers(transaction: Transaction, peerId: PeerId) -> [ChannelParticipant] {
    guard let entry = transaction.retrieveItemCacheEntry(id: jerkgramRetainedMembersKey(peerId: peerId))?.get(JerkgramRetainedMembersSnapshot.self) else { return [] }
    return CachedChannelParticipants(decoder: PostboxDecoder(buffer: MemoryBuffer(data: entry.data))).participants
}

func jerkgramSaveKnownChannelMembers(transaction: Transaction, accountPeerId: PeerId, peerId: PeerId, participants: [ChannelParticipant]) {
    guard JerkgramRetentionRuntime.shouldRetainExcludedHistory(accountPeerId: accountPeerId.toInt64(), chatPeerId: peerId.toInt64()),
          let channel = transaction.getPeer(peerId) as? TelegramChannel, channel.participationStatus == .member else { return }
    var known = jerkgramSavedMembers(transaction: transaction, peerId: peerId)
    let incomingIds = Set(participants.map { $0.peerId })
    known.removeAll { incomingIds.contains($0.peerId) }
    known.append(contentsOf: participants)
    // Keep a bounded snapshot of members actually loaded, not a fabricated full roster.
    let encoder = PostboxEncoder()
    CachedChannelParticipants(participants: Array(known.suffix(4096))).encode(encoder)
    if let entry = CodableEntry(JerkgramRetainedMembersSnapshot(data: encoder.makeData())) {
        transaction.putItemCacheEntry(id: jerkgramRetainedMembersKey(peerId: peerId), entry: entry)
    }
}

func jerkgramRetainedChannelMembers(transaction: Transaction, peerId: PeerId, offset: Int32, limit: Int32) -> [RenderedChannelParticipant] {
    let participants = jerkgramSavedMembers(transaction: transaction, peerId: peerId)
    let page = participants.dropFirst(max(0, Int(offset))).prefix(max(0, Int(limit)))
    return page.compactMap { participant in
        guard let peer = transaction.getPeer(participant.peerId) else { return nil }
        return RenderedChannelParticipant(participant: participant, peer: EnginePeer(peer), peers: [peer.id: EnginePeer(peer)], presences: [:])
    }
}
