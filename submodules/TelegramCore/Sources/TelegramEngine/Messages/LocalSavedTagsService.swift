import Foundation
import Postbox
import SwiftSignalKit

public struct LocalSavedTagsSelectionSummary {
    public let selectedCount: Int
    public let assignedCounts: [String: Int]
}
public struct LocalSavedTagsContentRow {
    public let entry: LocalSavedTagMessage
    // nil means unavailable; the indexed entry remains selectable and retryable.
    public let message: Message?
}
public struct LocalSavedTagsContentPage {
    public let page: LocalSavedTagsPage
    public let rows: [LocalSavedTagsContentRow]
    public let windows: [[LocalSavedTagsContentRow]]
    // Cursors for the OUTER retained window boundaries; page is the most
    // recent request and may no longer describe both boundaries after reversal.
    public let earlier: LocalSavedTagsCursor?
    public let later: LocalSavedTagsCursor?
}
public enum LocalSavedTagsPageEvent {
    case progress
    case result(LocalSavedTagsContentPage)
    case failure(LocalSavedTagsError)
}

// One serial delivery domain is shared by the service and every provider.
// Invalidation is a synchronous fence against publication. A callback may
// reenter inline; it must never synchronously wait for teardown on another
// thread. No external callback executes under a state lock.
final class LocalSavedTagsDelivery {
    private let queue = DispatchQueue(label: "LocalSavedTagsService.delivery")
    private let key = DispatchSpecificKey<UInt8>()
    init() { self.queue.setSpecific(key: self.key, value: 1) }
    func sync<T>(_ body: () -> T) -> T {
        if DispatchQueue.getSpecific(key: self.key) != nil { return body() }
        return self.queue.sync(execute: body)
    }
    func async(_ body: @escaping () -> Void) { self.queue.async(execute: body) }
}

// Create only for an active Saved Messages surface. Cold operations run on
// Postbox's queue; all publication is serialized on this private service queue.
public final class LocalSavedTagsService {
    public let accountId: AccountRecordId
    public let testingEnvironment: Bool
    public let selfPeerId: PeerId
    fileprivate let account: Account
    fileprivate let delivery = LocalSavedTagsDelivery()
    private var generation: UInt64 = 0
    private var disposed = false
    private var subscriptions: [UUID: MetaDisposable] = [:]

    public init(account: Account) {
        self.account = account
        self.accountId = account.id
        self.testingEnvironment = account.testingEnvironment
        self.selfPeerId = account.peerId
    }
    deinit { self.dispose() }
    public func dispose() {
        let subscriptions: [MetaDisposable] = self.delivery.sync {
            self.disposed = true
            self.generation &+= 1
            let subscriptions = Array(self.subscriptions.values)
            self.subscriptions.removeAll()
            return subscriptions
        }
        for disposable in subscriptions { disposable.dispose() }
    }
    // Explicit service generation plus subscriber cancellation reject delayed
    // Postbox/network completions even when the underlying work already began.
    fileprivate func bind<T>(_ signal: Signal<T, NoError>) -> Signal<T, NoError> {
        return Signal { subscriber in
            let id = UUID()
            let policyGeneration = JerkgramLocalPremiumPolicy.generation
            let disposable = MetaDisposable()
            let generation: UInt64? = self.delivery.sync {
                guard !self.disposed else { return nil }
                self.subscriptions[id] = disposable
                return self.generation
            }
            guard let generation = generation else {
                subscriber.putCompletion()
                return EmptyDisposable
            }
            disposable.set(signal.start(next: { value in
                self.delivery.async {
                    guard !self.disposed && self.generation == generation && self.subscriptions[id] != nil,
                        JerkgramLocalPremiumPolicy.generation == policyGeneration else { return }
                    subscriber.putNext(value)
                }
            }, completed: {
                self.delivery.async {
                    guard !self.disposed && self.generation == generation && self.subscriptions.removeValue(forKey: id) != nil else { return }
                    subscriber.putCompletion()
                }
            }))
            return ActionDisposable {
                self.delivery.sync { _ = self.subscriptions.removeValue(forKey: id) }
                disposable.dispose()
            }
        }
    }
    fileprivate func transaction<T>(_ body: @escaping (Transaction) -> Result<T, LocalSavedTagsError>) -> Signal<Result<T, LocalSavedTagsError>, NoError> {
        return self.bind(self.account.postbox.transaction { transaction in
            let active = self.delivery.sync { !self.disposed }
            guard active, JerkgramLocalPremiumPolicy.savedTagsEnabled(accountPeerId: self.selfPeerId.toInt64()) else { return .failure(.unavailable) }
            guard let state = transaction.getState() as? AuthorizedAccountState,
                  state.peerId == self.selfPeerId, state.isTestingEnvironment == self.testingEnvironment else { return .failure(.wrongAccount) }
            return body(transaction)
        })
    }
    public func catalogue() -> Signal<Result<LocalSavedTagsCatalogue, LocalSavedTagsError>, NoError> {
        return self.transaction { $0.localSavedTagsCatalogue(selfPeerId: self.selfPeerId) }
    }
    public func catalogueUpdates() -> Signal<Result<LocalSavedTagsCatalogue, LocalSavedTagsError>, NoError> {
        // Existing scalar preferences view is subscribed only by this cold signal.
        let policy: Signal<UInt64, NoError> = Signal { subscriber in
            subscriber.putNext(JerkgramLocalPremiumPolicy.generation)
            let observer = NotificationCenter.default.addObserver(forName: JerkgramLocalPremiumPolicy.changed, object: nil, queue: nil) { _ in subscriber.putNext(JerkgramLocalPremiumPolicy.generation) }
            return ActionDisposable { NotificationCenter.default.removeObserver(observer) }
        }
        return combineLatest(policy, self.account.postbox.preferencesView(keys: [localSavedTagsRevisionKey()])
        |> map { view -> Int64 in
            return view.values[localSavedTagsRevisionKey()]?.get(LocalSavedTagsRevision.self)?.revision ?? 0
        }
        |> distinctUntilChanged)
        |> mapToSignal { _ in self.catalogue() }
    }
    public func tags(messageId: MessageId) -> Signal<Result<[String], LocalSavedTagsError>, NoError> {
        return self.transaction { $0.localSavedTagsForMessage(selfPeerId: self.selfPeerId, messageId: messageId) }
    }
    public func create(name: String) -> Signal<Result<LocalSavedTag, LocalSavedTagsError>, NoError> {
        return self.transaction { $0.createLocalSavedTag(selfPeerId: self.selfPeerId, name: name) }
    }
    public func rename(tagId: String, name: String) -> Signal<Result<Int64, LocalSavedTagsError>, NoError> {
        return self.transaction { $0.renameLocalSavedTag(selfPeerId: self.selfPeerId, tagId: tagId, name: name) }
    }
    public func delete(tagId: String) -> Signal<Result<Int64, LocalSavedTagsError>, NoError> {
        return self.transaction { $0.deleteLocalSavedTag(selfPeerId: self.selfPeerId, tagId: tagId) }
    }
    public func selectionSummary(messageIds: [MessageId]) -> Signal<Result<LocalSavedTagsSelectionSummary, LocalSavedTagsError>, NoError> {
        return self.transaction { _internal_localSavedTagsSelectionSummary(transaction: $0, selfPeerId: self.selfPeerId, messageIds: messageIds) }
    }
    public func set(tagId: String, messageIds: [MessageId], assigned: Bool) -> Signal<Result<Int64, LocalSavedTagsError>, NoError> {
        return self.transaction { _internal_setLocalSavedTag(transaction: $0, selfPeerId: self.selfPeerId, tagId: tagId, messageIds: messageIds, assigned: assigned) }
    }
    // Removal-only entry point permits unavailable indexed rows to be untagged.
    // Store uses its existing index metadata; caller metadata never creates edges.
    public func remove(tagId: String, entries: [LocalSavedTagMessage]) -> Signal<Result<Int64, LocalSavedTagsError>, NoError> {
        return self.transaction { _internal_removeLocalSavedTag(transaction: $0, selfPeerId: self.selfPeerId, tagId: tagId, entries: entries) }
    }
    public func makePageProvider(tagId: String) -> LocalSavedTagsPageProvider {
        return LocalSavedTagsPageProvider(service: self, tagId: tagId)
    }
    fileprivate func page(tagId: String, cursor: LocalSavedTagsCursor?, direction: LocalSavedTagsDirection) -> Signal<LocalSavedTagsPageEvent, NoError> {
        return self.transaction { transaction in
            _internal_localSavedTagsPage(transaction: transaction, selfPeerId: self.selfPeerId, tagId: tagId, cursor: cursor, direction: direction)
        }
        |> mapToSignal { result -> Signal<LocalSavedTagsPageEvent, NoError> in
            switch result {
            case let .failure(error): return .single(.failure(error))
            case let .success((page, cached)):
                let cachedIds = Set(cached.map { $0.id })
                let missing = page.messages.map { $0.id }.filter { !cachedIds.contains($0) }
                let load: Signal<GetMessagesResult, NoError>
                // The ordinary loader indexes messageIds[0]. Empty pages and fully
                // cached pages MUST bypass it, including an empty tag catalogue.
                guard !missing.isEmpty else { return self.finish(page: page) }
                load = _internal_getMessagesLoadIfNecessary(missing, postbox: self.account.postbox, network: self.account.network, accountPeerId: self.selfPeerId)
                |> `catch` { _ -> Signal<GetMessagesResult, NoError> in .single(.result([])) }
                return load |> mapToSignal { result -> Signal<LocalSavedTagsPageEvent, NoError> in
                    switch result {
                    case .progress: return .single(.progress)
                    case .result: return self.finish(page: page)
                    }
                }
            }
        }
    }
    private func finish(page: LocalSavedTagsPage) -> Signal<LocalSavedTagsPageEvent, NoError> {
        // Confirmed refetch may change the actual index. Update tagged metadata
        // only when different, then reject the old revision and restart paging.
        return self.transaction { transaction -> Result<[LocalSavedTagsContentRow], LocalSavedTagsError> in
            var byId: [MessageId: Message] = [:]
            for entry in page.messages {
                if let message = transaction.getMessage(entry.id) { byId[entry.id] = message }
            }
            var changed: [LocalSavedTagMessage] = []
            for entry in page.messages {
                if let message = byId[entry.id], entry.timestamp != message.timestamp || entry.threadId != message.threadId {
                    changed.append(LocalSavedTagMessage(id: message.id, timestamp: message.timestamp, threadId: message.threadId))
                }
            }
            if !changed.isEmpty {
                if case let .failure(error) = transaction.updateLocalSavedTagsMetadata(selfPeerId: self.selfPeerId, messages: changed) { return .failure(error) }
            }
            switch transaction.localSavedTagsCatalogue(selfPeerId: self.selfPeerId) {
            case let .failure(error): return .failure(error)
            case let .success(catalogue):
                guard catalogue.revision == page.revision else { return .failure(.invalidPage) }
                return .success(page.messages.map { LocalSavedTagsContentRow(entry: $0, message: byId[$0.id]) })
            }
        }
        |> map { result in
            switch result {
            case let .failure(error): return .failure(error)
            case let .success(rows): return .result(LocalSavedTagsContentPage(page: page, rows: rows, windows: [], earlier: page.earlier, later: page.later))
            }
        }
    }
}

public final class LocalSavedTagsPageProvider {
    private let service: LocalSavedTagsService
    public let tagId: String
    private var generation: UInt64 = 0
    private var disposed = false
    private var active: MetaDisposable?
    private var revision: Int64?
    private var windows: [[LocalSavedTagsContentRow]] = []
    private var windowPages: [LocalSavedTagsPage] = []
    fileprivate init(service: LocalSavedTagsService, tagId: String) { self.service = service; self.tagId = tagId }
    deinit { self.dispose() }
    public func reset() {
        let active: MetaDisposable? = self.service.delivery.sync {
            self.generation &+= 1
            let active = self.active; self.active = nil
            self.windows.removeAll(); self.windowPages.removeAll(); self.revision = nil
            return active
        }
        active?.dispose()
    }
    public func dispose() {
        self.service.delivery.sync {
            self.disposed = true
            self.reset()
        }
    }
    public func request(cursor: LocalSavedTagsCursor? = nil, direction: LocalSavedTagsDirection = .earlier) -> Signal<LocalSavedTagsPageEvent, NoError> {
        return Signal { subscriber in
            return self.service.delivery.sync { () -> Disposable in
                guard !self.disposed else { subscriber.putCompletion(); return EmptyDisposable }
                self.generation &+= 1
                let generation = self.generation
                let previous = self.active
                let active = MetaDisposable(); self.active = active
                let boundary = direction == .earlier ? self.windowPages.last?.earlier : self.windowPages.first?.later
                if cursor == nil || cursor != boundary {
                    self.windows.removeAll(); self.windowPages.removeAll(); self.revision = nil
                }
                previous?.dispose()
                active.set(self.service.bind(self.service.page(tagId: self.tagId, cursor: cursor, direction: direction)).start(next: { event in
                    self.service.delivery.sync {
                        guard !self.disposed && self.generation == generation else { return }
                        let output: LocalSavedTagsPageEvent
                        switch event {
                        case let .result(content):
                            if self.revision != content.page.revision { self.windows.removeAll(); self.windowPages.removeAll() }
                            self.revision = content.page.revision
                            let ids = Set(content.rows.map { $0.entry.id })
                            for index in self.windows.indices.reversed() where self.windows[index].contains(where: { ids.contains($0.entry.id) }) {
                                self.windows.remove(at: index); self.windowPages.remove(at: index)
                            }
                            if !content.rows.isEmpty {
                                if direction == .earlier {
                                    self.windows.append(content.rows); self.windowPages.append(content.page)
                                } else {
                                    self.windows.insert(content.rows, at: 0); self.windowPages.insert(content.page, at: 0)
                                }
                            }
                            while self.windows.count > 3 {
                                let index = direction == .earlier ? 0 : self.windows.count - 1
                                self.windows.remove(at: index); self.windowPages.remove(at: index)
                            }
                            output = .result(LocalSavedTagsContentPage(page: content.page, rows: content.rows, windows: self.windows, earlier: self.windowPages.isEmpty ? content.page.earlier : self.windowPages[self.windowPages.count - 1].earlier, later: self.windowPages.isEmpty ? content.page.later : self.windowPages[0].later))
                        case .failure(.invalidPage):
                            self.windows.removeAll(); self.windowPages.removeAll(); self.revision = nil
                            output = event
                        default: output = event
                        }
                        subscriber.putNext(output)
                    }
                }, completed: {
                    self.service.delivery.sync {
                        guard self.generation == generation && !self.disposed else { return }
                        self.active = nil
                        subscriber.putCompletion()
                    }
                }))
                return ActionDisposable {
                    self.service.delivery.sync {
                        if self.generation == generation { self.generation &+= 1; self.active = nil }
                    }
                    active.dispose()
                }
            }
        }
    }
}
