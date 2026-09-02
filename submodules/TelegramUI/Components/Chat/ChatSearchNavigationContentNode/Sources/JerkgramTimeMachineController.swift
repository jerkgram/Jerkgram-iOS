import Foundation
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import PresentationDataUtils
import ItemListUI
import AccountContext
import AlertUI
import JerkgramCore

// MARK: Jerkgram v1.2G BUILD118_TIME_MACHINE_UI1
// MARK: Jerkgram v1.2H BUILD119_TIME_MACHINE_SUMMARY1
// MARK: Jerkgram v1.2M BUILD124_TIME_MACHINE_REDESIGN1
private struct JerkgramTimeMachineUIState: Equatable {
    var kinds: Set<JerkgramEventKind>
    var senderPeerId: Int64?
}

private struct JerkgramTimeMachinePageState: Equatable {
    var events: [JerkgramCanonicalEvent]
    var hasMore: Bool
}

private final class JerkgramTimeMachineUIArguments {
    let toggleKind: (JerkgramEventKind) -> Void
    let selectSender: () -> Void
    let selectEvent: (JerkgramCanonicalEvent) -> Void
    let loadMore: () -> Void
    init(
        toggleKind: @escaping (JerkgramEventKind) -> Void,
        selectSender: @escaping () -> Void,
        selectEvent: @escaping (JerkgramCanonicalEvent) -> Void,
        loadMore: @escaping () -> Void
    ) {
        self.toggleKind = toggleKind
        self.selectSender = selectSender
        self.selectEvent = selectEvent
        self.loadMore = loadMore
    }
}

private enum JerkgramTimeMachineUIEntry: ItemListNodeEntry {
    case header(Int32, String)
    case summary(Int32, Int32, String, String)
    case filter(Int32, Int32, String, String, JerkgramEventKind?)
    case result(Int32, Int32, String, String, JerkgramCanonicalEvent)
    case info(Int32, String)
    case loadMore(Int32, String)

    var section: ItemListSectionId {
        switch self {
        case let .header(section, _), let .summary(section, _, _, _), let .filter(section, _, _, _, _), let .result(section, _, _, _, _), let .info(section, _), let .loadMore(section, _): return section
        }
    }
    var stableId: Int32 {
        switch self {
        case let .header(section, _): return section * 1000
        case let .summary(section, index, _, _): return section * 1000 + index
        case let .filter(section, index, _, _, _), let .result(section, index, _, _, _): return section * 1000 + index
        case .info: return Int32.max - 1
        case .loadMore: return Int32.max
        }
    }
    static func == (lhs: Self, rhs: Self) -> Bool { return lhs.stableId == rhs.stableId && String(describing: lhs) == String(describing: rhs) }
    static func < (lhs: Self, rhs: Self) -> Bool { return lhs.stableId < rhs.stableId }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! JerkgramTimeMachineUIArguments
        switch self {
        case let .header(_, text):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)
        case let .summary(_, _, title, value):
            return ItemListDisclosureItem(
                presentationData: presentationData, systemStyle: .glass,
                title: title, label: value, labelStyle: .text,
                sectionId: self.section, style: .blocks,
                disclosureStyle: .none, action: nil
            )
        // MARK: Jerkgram v1.2K BUILD122_TIME_MACHINE_POLISH1
        // MARK: Jerkgram v1.2M BUILD124_TIME_MACHINE_FINAL_UI1
case let .filter(_, _, title, value, kind):
    if let kind {
        return ItemListSwitchItem(
            presentationData: presentationData, systemStyle: .glass,
            title: title, value: value == "✓",
            sectionId: self.section, style: .blocks,
            updated: { _ in arguments.toggleKind(kind) }
        )
    } else {
        return ItemListDisclosureItem(
            presentationData: presentationData, systemStyle: .glass,
            title: title, label: value, labelStyle: .text,
            sectionId: self.section, style: .blocks,
            disclosureStyle: .none,
            action: { arguments.selectSender() }
        )
    }
        case let .result(_, _, title, value, event):
            return ItemListDisclosureItem(
                presentationData: presentationData, systemStyle: .glass,
                title: title, label: value, labelStyle: .text,
                sectionId: self.section, style: .blocks,
                disclosureStyle: .arrow, action: { arguments.selectEvent(event) }
            )
        case let .info(_, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        case let .loadMore(_, title):
            return ItemListActionItem(
                presentationData: presentationData, title: title,
                kind: .generic, alignment: .center,
                sectionId: self.section, style: .blocks,
                action: { arguments.loadMore() }
            )
        }
    }
}

// MARK: Jerkgram v1.2L BUILD123_TIME_MACHINE_UI1
private func jerkgramTimeMachineDateText(_ timestampMs: Int64, dateTimeFormat: PresentationDateTimeFormat) -> String {
    let _ = dateTimeFormat
    let timestamp = TimeInterval(timestampMs) / 1000.0
    guard timestamp > 0.0 else { return "" }
    let formatter = DateFormatter()
    formatter.locale = Locale.current
    formatter.dateStyle = .medium
    formatter.timeStyle = .short
    return formatter.string(from: Date(timeIntervalSince1970: timestamp))
}

private func jerkgramTimeMachineRootURL() -> URL {
    return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Jerkgram", isDirectory: true)
}

private func jerkgramEventKindTitle(_ kind: JerkgramEventKind, strings: JerkgramStrings) -> String {
    switch kind {
    case .deletedMessage, .deletedReply: return strings.timeMachineDeleted
    case .editedMessage: return strings.timeMachineEdited
    case .recoveredMedia: return strings.timeMachineMedia
    default: return kind.rawValue
    }
}

private func jerkgramDiffText(_ event: JerkgramCanonicalEvent) -> String {
    guard event.kind == .editedMessage,
          let old = event.payload.previousText,
          let new = event.payload.text else {
        return event.payload.text ?? event.payload.previousText ?? event.eventId.rawValue
    }
    return JerkgramTextDiff.diff(old: old, new: new).map { operation in
        switch operation {
        case let .equal(value): return value
        case let .insert(value): return "[+\(value)]"
        case let .delete(value): return "[-\(value)]"
        case let .replace(old, new): return "[-\(old)] [+\(new)]"
        }
    }.joined()
}

public func jerkgramTimeMachineController(
    context: AccountContext,
    chatPeerId: Int64,
    initialQuery: String,
    eventIds: Set<JerkgramEventId>? = nil,
    navigateToMessage: @escaping (EngineMessage.Id) -> Void
) -> ViewController {
    let accountPeerId = context.account.peerId.toInt64()
    let eventsValue = Atomic<[JerkgramCanonicalEvent]>(value: [])
    let eventsPromise = ValuePromise(
        JerkgramTimeMachinePageState(events: [], hasMore: true),
        ignoreRepeated: true
    )
    let pageLock = NSLock()
    var beforeSequence: Int64?
    var beforeEventId: JerkgramEventId?
    var hasMore = true
    var isLoading = false
    let loadNextPage: () -> Void = {
        pageLock.lock()
        guard hasMore && !isLoading else {
            pageLock.unlock()
            return
        }
        isLoading = true
        let cursorSequence = beforeSequence
        let cursorEventId = beforeEventId
        pageLock.unlock()
        Queue.concurrentDefaultQueue().async {
            let store = JerkgramJSONLEventStore(rootURL: jerkgramTimeMachineRootURL())
            let page = (try? store.eventPage(
                accountPeerId: accountPeerId,
                chatPeerId: chatPeerId,
                beforeSequence: cursorSequence,
                beforeEventId: cursorEventId,
                limit: 250
            )) ?? []
            let events = eventsValue.modify { $0 + page }
            pageLock.lock()
            if let last = page.last {
                beforeSequence = last.sequence
                beforeEventId = last.eventId
            }
            hasMore = page.count == 250
            isLoading = false
            let pageHasMore = hasMore
            pageLock.unlock()
            eventsPromise.set(JerkgramTimeMachinePageState(events: events, hasMore: pageHasMore))
        }
    }
    loadNextPage()
    let initial = JerkgramTimeMachineUIState(
        kinds: [.deletedMessage, .deletedReply, .editedMessage, .recoveredMedia],
        senderPeerId: nil
    )
    let stateValue = Atomic(value: initial)
    let statePromise = ValuePromise(initial, ignoreRepeated: true)
    var controller: ItemListController?

    let arguments = JerkgramTimeMachineUIArguments(toggleKind: { kind in
        let value = stateValue.modify { current in
            var current = current
            if current.kinds.contains(kind) { current.kinds.remove(kind) } else { current.kinds.insert(kind) }
            return current
        }
        statePromise.set(value)
    }, selectSender: {
        let senders = Array(Set(eventsValue.with { $0.compactMap(\.senderPeerId) })).sorted()
        let value = stateValue.modify { current in
            var current = current
            if let sender = current.senderPeerId, let index = senders.firstIndex(of: sender), index + 1 < senders.count {
                current.senderPeerId = senders[index + 1]
            } else if current.senderPeerId == nil {
                current.senderPeerId = senders.first
            } else {
                current.senderPeerId = nil
            }
            return current
        }
        statePromise.set(value)
    }, selectEvent: { event in
        if let namespace = event.messageNamespace, let id = event.messageId {
            navigateToMessage(EngineMessage.Id(
                peerId: EnginePeer.Id(event.chatPeerId),
                namespace: namespace,
                id: id
            ))
            controller?.dismiss()
        } else {
            let presentationData = context.sharedContext.currentPresentationData.with { $0 }
            let localDetail = jerkgramDiffText(event)
            controller?.present(textAlertController(
                context: context,
                title: presentationData.strings.jerkgram.timeMachine,
                text: localDetail,
                actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})]
            ), in: .window(.root), with: nil)
        }
    }, loadMore: loadNextPage)

    let signal = combineLatest(context.sharedContext.presentationData, statePromise.get(), eventsPromise.get())
    |> deliverOnMainQueue
    |> map { presentationData, state, page -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let strings = presentationData.strings.jerkgram
        let needle = initialQuery.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let results = page.events.filter { event in
            if let eventIds, !eventIds.contains(event.eventId) { return false }
            guard state.kinds.contains(event.kind) else { return false }
            if let senderPeerId = state.senderPeerId, event.senderPeerId != senderPeerId { return false }
            if !needle.isEmpty {
                let search = [event.payload.text, event.payload.previousText]
                    .compactMap { $0 }.joined(separator: " ").lowercased()
                if !search.contains(needle) { return false }
            }
            return true
        }.sorted { lhs, rhs in
            if lhs.sequence != rhs.sequence { return lhs.sequence > rhs.sequence }
            return lhs.eventId > rhs.eventId
        }
        var entries: [JerkgramTimeMachineUIEntry] = [
            
            .header(1, strings.timeMachineFilters),
            .filter(1, 1, strings.timeMachineDeleted, state.kinds.contains(.deletedMessage) ? "✓" : "", .deletedMessage),
            .filter(1, 2, strings.timeMachineEdited, state.kinds.contains(.editedMessage) ? "✓" : "", .editedMessage),
            .filter(1, 3, strings.timeMachineMedia, state.kinds.contains(.recoveredMedia) ? "✓" : "", .recoveredMedia),
            .filter(1, 4, strings.timeMachineAuthor, state.senderPeerId.map(String.init) ?? strings.timeMachineAllAuthors, nil),
            .header(2, strings.timeMachineResults),
        ]
        for (index, event) in results.enumerated() {
            let text = event.payload.text ?? event.payload.previousText ?? event.eventId.rawValue
            let date = jerkgramTimeMachineDateText(event.observedAtMs, dateTimeFormat: presentationData.dateTimeFormat)
            let kind = jerkgramEventKindTitle(event.kind, strings: strings)
            let detail = date.isEmpty ? kind : "\(kind) · \(date)"
            entries.append(.result(2, Int32(index + 1), String(text.prefix(120)), detail, event))
        }
        if results.isEmpty { entries.append(.info(2, strings.timeMachineEmpty)) }
        if page.hasMore { entries.append(.loadMore(2, strings.timeMachineLoadMore)) }
        return (
            ItemListControllerState(
                presentationData: ItemListPresentationData(presentationData),
                title: .text(strings.timeMachine),
                leftNavigationButton: ItemListNavigationButton(
                    content: .text("‹ " + presentationData.strings.Common_Back),
                    style: .regular,
                    enabled: true,
                    action: { controller?.dismiss() }
                ),
                rightNavigationButton: nil,
                backNavigationButton: nil
            ),
            (ItemListNodeState(
                presentationData: ItemListPresentationData(presentationData),
                entries: entries, style: .blocks, animateChanges: false
            ), arguments as Any)
        )
    }
    controller = ItemListController(context: context, state: signal)
    return controller!
}
