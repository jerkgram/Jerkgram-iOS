import Foundation
import UIKit
import Dispatch
import Display
import SwiftSignalKit
import TelegramPresentationData
import ItemListUI
import AccountContext
import TelegramCore
import TelegramStringFormatting

private struct JerkgramGramDraftState: Equatable {
    var enabled: Bool
    var amount: String
}

private final class JerkgramGramEditorArguments {
    let setEnabled: (Bool) -> Void
    let setAmount: (String) -> Void
    let applyPreset: (Int64) -> Void

    init(setEnabled: @escaping (Bool) -> Void, setAmount: @escaping (String) -> Void, applyPreset: @escaping (Int64) -> Void) {
        self.setEnabled = setEnabled
        self.setAmount = setAmount
        self.applyPreset = applyPreset
    }
}

private enum JerkgramGramEditorEntry: ItemListNodeEntry {
    case preview(Int32, String, String)
    case toggle(Int32, String, Bool)
    case input(Int32, String, String)
    case preset(Int32, String, Int64)
    case info(Int32, String)

    var section: ItemListSectionId {
        switch self {
        case .preview: return 0
        case .toggle, .input: return 1
        case .preset: return 2
        case .info: return 3
        }
    }

    var stableId: Int32 {
        switch self {
        case let .preview(id, _, _), let .toggle(id, _, _), let .input(id, _, _), let .preset(id, _, _), let .info(id, _): return id
        }
    }

    static func == (lhs: Self, rhs: Self) -> Bool {
        return lhs.stableId == rhs.stableId && String(describing: lhs) == String(describing: rhs)
    }
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.stableId < rhs.stableId }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! JerkgramGramEditorArguments
        switch self {
        case let .preview(_, amount, status):
            return ItemListDisclosureItem(
                presentationData: presentationData, systemStyle: .glass,
                icon: UIImage(bundleImageName: "Wallet/TopGram"),
                title: amount, label: status, labelStyle: .text,
                sectionId: self.section, style: .blocks,
                disclosureStyle: .none, action: nil
            )
        case let .toggle(_, title, value):
            return ItemListSwitchItem(
                presentationData: presentationData, systemStyle: .glass, title: title, value: value,
                sectionId: self.section, style: .blocks,
                updated: { arguments.setEnabled($0) }
            )
        case let .input(_, title, value):
            return ItemListSingleLineInputItem(
                presentationData: presentationData,
                title: NSAttributedString(string: title, textColor: presentationData.theme.list.itemPrimaryTextColor),
                text: value, placeholder: "0", type: .regular(capitalization: false, autocorrection: false),
                returnKeyType: .done, alignment: .right, spacing: 16.0,
                clearType: .onFocus, maxLength: 20, selectAllOnFocus: true,
                sectionId: self.section,
                textUpdated: { arguments.setAmount(jerkgramSanitizeGramDraft($0)) },
                shouldUpdateText: { jerkgramIsValidGramDraft($0) }, action: {}
            )
        case let .preset(_, title, value):
            return ItemListActionItem(
                presentationData: presentationData, title: title, kind: .generic,
                alignment: .center, sectionId: self.section, style: .blocks,
                action: { arguments.applyPreset(value) }
            )
        case let .info(_, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

private func jerkgramIsValidGramDraft(_ text: String) -> Bool {
    let value = text.replacingOccurrences(of: ",", with: ".")
    guard value.count <= 20, value.filter({ $0 == "." }).count <= 1 else { return false }
    return value.allSatisfy { ("0"..."9").contains(String($0)) || $0 == "." || $0 == " " || $0 == "\u{00a0}" }
}

private func jerkgramSanitizeGramDraft(_ text: String) -> String {
    return text.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "\u{00a0}", with: "").replacingOccurrences(of: ",", with: ".")
}

private func jerkgramSavedGramAmount(_ text: String) -> String? {
    return JerkgramLocalGramBalance.savedAmount(text)
}

private func jerkgramGramPreset(_ current: String, delta: Int64) -> String {
    let whole = current.split(separator: ".", maxSplits: 1).first.flatMap { Int64($0) } ?? 0
    let (next, overflow) = whole.addingReportingOverflow(delta)
    return String(overflow ? 9_223_372_036 : min(9_223_372_036, max(0, next)))
}

private final class JerkgramGramAutosave {
    private var saved: JerkgramGramDraftState
    private var latest: JerkgramGramDraftState
    private var cancelPending: (() -> Void)?
    private var generation: UInt64 = 0
    private let commit: (JerkgramGramDraftState) -> Void
    private let schedule: (@escaping () -> Void) -> (() -> Void)

    init(initial: JerkgramGramDraftState, commit: @escaping (JerkgramGramDraftState) -> Void, schedule: @escaping (@escaping () -> Void) -> (() -> Void) = { action in
        let item = DispatchWorkItem(block: action)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: item)
        return { item.cancel() }
    }) {
        self.saved = initial
        self.latest = initial
        self.commit = commit
        self.schedule = schedule
    }

    func update(_ draft: JerkgramGramDraftState) {
        let next = JerkgramGramDraftState(enabled: draft.enabled, amount: jerkgramSavedGramAmount(draft.amount) ?? self.latest.amount)
        guard next != self.latest else { return }
        self.latest = next
        self.generation &+= 1
        self.cancelPending?()
        self.cancelPending = nil
        guard next != self.saved else { return }
        let generation = self.generation
        self.cancelPending = self.schedule { [weak self] in
            guard let self, self.generation == generation else { return }
            self.flush()
        }
    }

    func flush() {
        self.generation &+= 1
        self.cancelPending?()
        self.cancelPending = nil
        guard self.latest != self.saved else { return }
        self.saved = self.latest
        self.commit(self.saved)
    }

    deinit {
        self.flush()
    }
}

private func jerkgramCommitGramDraft(accountPeerId: Int64, state: JerkgramGramDraftState) {
    JerkgramLocalGramBalance.commit(accountPeerId: accountPeerId, enabled: state.enabled, amount: state.amount)
}

public func jerkgramGramEditorController(context: AccountContext) -> ViewController {
    let accountPeerId = context.account.peerId.toInt64()
    let initial = JerkgramGramDraftState(
        enabled: JerkgramLocalGramBalance.enabled(accountPeerId: accountPeerId),
        amount: JerkgramLocalGramBalance.amount(accountPeerId: accountPeerId)
    )
    let autosave = JerkgramGramAutosave(initial: initial, commit: { value in
        jerkgramCommitGramDraft(accountPeerId: accountPeerId, state: value)
    })
    let stateValue = Atomic(value: initial)
    let statePromise = ValuePromise(initial, ignoreRepeated: true)
    var controller: ItemListController?

    func update(_ transform: (inout JerkgramGramDraftState) -> Void) {
        let value = stateValue.modify { current in
            var current = current
            transform(&current)
            return current
        }
        statePromise.set(value)
        autosave.update(value)
    }

    let arguments = JerkgramGramEditorArguments(
        setEnabled: { value in
            update { $0.enabled = value }
            autosave.flush() // Toggle affects already-open balance surfaces immediately.
        },
        setAmount: { value in update { $0.amount = value } },
        applyPreset: { value in update { $0.amount = jerkgramGramPreset($0.amount, delta: value) } }
    )

    let nativeBalance: Signal<Int64?, NoError>
    if let tonContext = context.tonContext {
        nativeBalance = tonContext.state |> map { $0?.balance.value }
    } else {
        nativeBalance = .single(nil)
    }
    let signal = combineLatest(context.sharedContext.presentationData, statePromise.get(), nativeBalance)
    |> deliverOnMainQueue
    |> map { presentationData, state, nativeBalance -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let strings = presentationData.strings.jerkgram
        let amount: String
        if state.enabled {
            amount = jerkgramSanitizeGramDraft(state.amount)
        } else if let nativeBalance {
            amount = formatTonAmountText(nativeBalance, dateTimeFormat: presentationData.dateTimeFormat)
        } else {
            amount = "…" // Native balance not available yet; never substitute the saved zero.
        }
        let status = strings.gramOverrideSummary(state.enabled, amount)
        let entries: [JerkgramGramEditorEntry] = [
            .preview(1, amount, status),
            .toggle(2, strings.localGramBalance, state.enabled),
            .input(3, strings.gramBalance, state.amount),
            .preset(4, "+ 100 GRAM", 100),
            .preset(5, "+ 1 000 GRAM", 1000),
            .preset(6, "+ 10 000 GRAM", 10000),
            .info(7, strings.gramEditorHint)
        ]
        return (
            ItemListControllerState(
                presentationData: ItemListPresentationData(presentationData), title: .text(strings.gramBalance),
                leftNavigationButton: nil, rightNavigationButton: nil,
                backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
            ),
            (ItemListNodeState(
                presentationData: ItemListPresentationData(presentationData), entries: entries,
                style: .blocks, animateChanges: false
            ), arguments as Any)
        )
    }
    controller = ItemListController(context: context, state: signal)
    controller?.willDisappear = { _ in autosave.flush() }
    return controller!
}
