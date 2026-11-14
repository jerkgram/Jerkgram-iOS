import Foundation
import Postbox

func _internal_localSavedTagsEligible(_ id: MessageId, selfPeerId: PeerId) -> Bool {
    return id.peerId == selfPeerId && id.namespace == Namespaces.Message.Cloud && id.id > 0
}
func _internal_localSavedTagsSelectionSummary(transaction: Transaction, selfPeerId: PeerId, messageIds: [MessageId]) -> Result<LocalSavedTagsSelectionSummary, LocalSavedTagsError> {
    guard messageIds.count <= 1000 else { return .failure(.batchLimit) }
    guard messageIds.allSatisfy({ _internal_localSavedTagsEligible($0, selfPeerId: selfPeerId) }) else { return .failure(.invalidMessage) }
    let unique = Set(messageIds)
    var counts: [String: Int] = [:]
    for id in unique {
        switch transaction.localSavedTagsForMessage(selfPeerId: selfPeerId, messageId: id) {
        case let .failure(error): return .failure(error)
        case let .success(tags): for tag in tags { counts[tag, default: 0] += 1 }
        }
    }
    return .success(LocalSavedTagsSelectionSummary(selectedCount: unique.count, assignedCounts: counts))
}
func _internal_setLocalSavedTag(transaction: Transaction, selfPeerId: PeerId, tagId: String, messageIds: [MessageId], assigned: Bool) -> Result<Int64, LocalSavedTagsError> {
    guard messageIds.count <= 1000 else { return .failure(.batchLimit) }
    guard messageIds.allSatisfy({ _internal_localSavedTagsEligible($0, selfPeerId: selfPeerId) }) else { return .failure(.invalidMessage) }
    var messages: [LocalSavedTagMessage] = []
    for id in Set(messageIds) {
        guard let message = transaction.getMessage(id) else { return .failure(.unavailable) }
        messages.append(LocalSavedTagMessage(id: id, timestamp: message.timestamp, threadId: message.threadId))
    }
    return transaction.setLocalSavedTag(selfPeerId: selfPeerId, tagId: tagId, messages: messages, assigned: assigned)
}
func _internal_removeLocalSavedTag(transaction: Transaction, selfPeerId: PeerId, tagId: String, entries: [LocalSavedTagMessage]) -> Result<Int64, LocalSavedTagsError> {
    guard entries.count <= 1000 else { return .failure(.batchLimit) }
    guard entries.allSatisfy({ _internal_localSavedTagsEligible($0.id, selfPeerId: selfPeerId) }) else { return .failure(.invalidMessage) }
    return transaction.setLocalSavedTag(selfPeerId: selfPeerId, tagId: tagId, messages: entries, assigned: false)
}
func _internal_localSavedTagsPage(transaction: Transaction, selfPeerId: PeerId, tagId: String, cursor: LocalSavedTagsCursor?, direction: LocalSavedTagsDirection) -> Result<(LocalSavedTagsPage, [Message]), LocalSavedTagsError> {
    switch transaction.localSavedTagsPage(selfPeerId: selfPeerId, tagId: tagId, cursor: cursor, direction: direction, limit: 45) {
    case let .failure(error): return .failure(error)
    case let .success(page):
        guard cursor == nil || cursor?.revision == page.revision else { return .failure(.invalidPage) }
        return .success((page, page.messages.compactMap { transaction.getMessage($0.id) }))
    }
}
