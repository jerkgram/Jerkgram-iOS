import Foundation
import Postbox

// Semantic deletion only. Authorization comes from the enclosing transaction;
// uncached IDs are resolved by the local index, never by message history.
func _internal_removeLocalSavedTagsMessages(transaction: Transaction, ids: [MessageId]) {
    guard let state = transaction.getState() as? AuthorizedAccountState else { return }
    var batch: [MessageId] = []
    for id in ids where id.peerId == state.peerId && id.namespace == Namespaces.Message.Cloud && id.id > 0 {
        batch.append(id)
        if batch.count == 1000 {
            _ = transaction.removeLocalSavedTagsMessages(selfPeerId: state.peerId, ids: batch)
            batch.removeAll(keepingCapacity: true)
        }
    }
    if !batch.isEmpty { _ = transaction.removeLocalSavedTagsMessages(selfPeerId: state.peerId, ids: batch) }
}

func _internal_removeLocalSavedTagsGlobalIds(transaction: Transaction, ids: [Int32]) {
    guard let state = transaction.getState() as? AuthorizedAccountState else { return }
    var batch: [Int32] = []
    for id in ids where id > 0 {
        batch.append(id)
        if batch.count == 1000 {
            _ = transaction.removeLocalSavedTagsGlobalIds(selfPeerId: state.peerId, ids: batch)
            batch.removeAll(keepingCapacity: true)
        }
    }
    if !batch.isEmpty { _ = transaction.removeLocalSavedTagsGlobalIds(selfPeerId: state.peerId, ids: batch) }
}

func _internal_removeLocalSavedTagsRange(transaction: Transaction, peerId: PeerId, namespaces: MessageIdNamespaces, scope: LocalSavedTagsDeletionScope) {
    guard let state = transaction.getState() as? AuthorizedAccountState,
          peerId == state.peerId, namespaces.contains(Namespaces.Message.Cloud) else { return }
    _ = transaction.removeLocalSavedTagsRange(selfPeerId: state.peerId, scope: scope)
}
