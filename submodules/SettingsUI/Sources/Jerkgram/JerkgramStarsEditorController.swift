import Foundation
import Dispatch
import Display
import SwiftSignalKit
import TelegramPresentationData
import ItemListUI
import AccountContext

private let jerkgramStarsEnabledKey = "jerkgram.Stars.LocalBalance.Enabled"
private let jerkgramStarsAmountKey = "jerkgram.Stars.LocalBalance.Amount"

private struct JerkgramStarsDraftState: Equatable {
    var enabled: Bool
    var amount: String
}

private final class JerkgramStarsEditorArguments {
    let setEnabled: (Bool) -> Void
    let setAmount: (String) -> Void
    let applyPreset: (Int64) -> Void

    init(setEnabled: @escaping (Bool) -> Void, setAmount: @escaping (String) -> Void, applyPreset: @escaping (Int64) -> Void) {
        self.setEnabled = setEnabled
        self.setAmount = setAmount
        self.applyPreset = applyPreset
    }
}

private enum JerkgramStarsEditorEntry: ItemListNodeEntry {
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
        let arguments = arguments as! JerkgramStarsEditorArguments
        switch self {
        case let .preview(_, amount, status):
            return ItemListDisclosureItem(
                presentationData: presentationData, systemStyle: .glass,
                title: "⭐  \(amount)", label: status, labelStyle: .text,
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
                textUpdated: { arguments.setAmount(jerkgramSanitizeStarsDraft($0)) },
                shouldUpdateText: { jerkgramIsValidStarsDraft($0) }, action: {}
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

private func jerkgramIsValidStarsDraft(_ text: String) -> Bool {
    let value = text.replacingOccurrences(of: ",", with: ".")
    guard value.count <= 20, value.filter({ $0 == "." }).count <= 1 else { return false }
    return value.allSatisfy { ("0"..."9").contains(String($0)) || $0 == "." || $0 == " " || $0 == "\u{00a0}" }
}

private func jerkgramSanitizeStarsDraft(_ text: String) -> String {
    return text.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "\u{00a0}", with: "").replacingOccurrences(of: ",", with: ".")
}

private func jerkgramSavedStarsAmount(_ text: String) -> String? {
    let value = text.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "\u{00a0}", with: "").replacingOccurrences(of: ",", with: ".")
    guard !value.isEmpty, value.count <= 20, !value.hasSuffix("."),
        value.allSatisfy({ ("0"..."9").contains(String($0)) || $0 == "." }) else { return nil }
    let parts = value.split(separator: ".", omittingEmptySubsequences: false)
    guard parts.count <= 2, let whole = Int64(parts[0].isEmpty ? "0" : String(parts[0])), whole >= 0 else { return nil }
    return String(whole) + (parts.count == 2 ? "." + String(parts[1].prefix(9)) : "")
}

private func jerkgramStarsPreset(_ current: String, delta: Int64) -> String {
    let whole = current.split(separator: ".", maxSplits: 1).first.flatMap { Int64($0) } ?? 0
    let (next, overflow) = whole.addingReportingOverflow(delta)
    return String(overflow ? (delta >= 0 ? Int64.max : 0) : max(0, next))
}

private final class JerkgramStarsAutosave {
    private var saved: JerkgramStarsDraftState
    private var latest: JerkgramStarsDraftState
    private var cancelPending: (() -> Void)?
    private var generation: UInt64 = 0
    private let commit: (JerkgramStarsDraftState) -> Void
    private let schedule: (@escaping () -> Void) -> (() -> Void)

    init(initial: JerkgramStarsDraftState, commit: @escaping (JerkgramStarsDraftState) -> Void, schedule: @escaping (@escaping () -> Void) -> (() -> Void) = { action in
        let item = DispatchWorkItem(block: action)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: item)
        return { item.cancel() }
    }) {
        self.saved = initial
        self.latest = initial
        self.commit = commit
        self.schedule = schedule
    }

    func update(_ draft: JerkgramStarsDraftState) {
        let next = JerkgramStarsDraftState(enabled: draft.enabled, amount: jerkgramSavedStarsAmount(draft.amount) ?? self.latest.amount)
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

private func jerkgramCommitStarsDraft(accountPeerId: Int64, state: JerkgramStarsDraftState) {
    let defaults = UserDefaults.standard
    let amount = jerkgramSanitizeStarsDraft(state.amount)
    defaults.set(state.enabled, forKey: jerkgramStarsEnabledKey)
    defaults.set(amount, forKey: jerkgramStarsAmountKey)
    defaults.set(state.enabled, forKey: "jerkgram.account.\(accountPeerId).setting.\(jerkgramStarsEnabledKey)")
    defaults.set(amount, forKey: "jerkgram.account.\(accountPeerId).setting.\(jerkgramStarsAmountKey)")
}

public func jerkgramStarsEditorController(context: AccountContext) -> ViewController {
    let accountPeerId = context.account.peerId.toInt64()
    let scopedEnabled = "jerkgram.account.\(accountPeerId).setting.\(jerkgramStarsEnabledKey)"
    let scopedAmount = "jerkgram.account.\(accountPeerId).setting.\(jerkgramStarsAmountKey)"
    let defaults = UserDefaults.standard
    let initial = JerkgramStarsDraftState(
        enabled: (defaults.object(forKey: scopedEnabled) as? Bool) ?? defaults.bool(forKey: jerkgramStarsEnabledKey),
        amount: (defaults.string(forKey: scopedAmount) ?? defaults.string(forKey: jerkgramStarsAmountKey)).flatMap(jerkgramSavedStarsAmount) ?? "0"
    )
    let autosave = JerkgramStarsAutosave(initial: initial, commit: { value in
        jerkgramCommitStarsDraft(accountPeerId: accountPeerId, state: value)
    })
    let stateValue = Atomic(value: initial)
    let statePromise = ValuePromise(initial, ignoreRepeated: true)
    var controller: ItemListController?

    func update(_ transform: (inout JerkgramStarsDraftState) -> Void) {
        let value = stateValue.modify { current in
            var current = current
            transform(&current)
            return current
        }
        statePromise.set(value)
        autosave.update(value)
    }

    let arguments = JerkgramStarsEditorArguments(
        setEnabled: { value in update { $0.enabled = value } },
        setAmount: { value in update { $0.amount = value } },
        applyPreset: { value in update { $0.amount = jerkgramStarsPreset($0.amount, delta: value) } }
    )

    let signal = combineLatest(context.sharedContext.presentationData, statePromise.get())
    |> deliverOnMainQueue
    |> map { presentationData, state -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let strings = presentationData.strings.jerkgram
        let amount = jerkgramSanitizeStarsDraft(state.amount)
        let status = strings.starsOverrideSummary(state.enabled, amount)
        let entries: [JerkgramStarsEditorEntry] = [
            .preview(1, amount, status),
            .toggle(2, strings.localStarsBalance, state.enabled),
            .input(3, strings.starsBalance, state.amount),
            .preset(4, "+ 100 ⭐", 100),
            .preset(5, "+ 1 000 ⭐", 1000),
            .preset(6, "+ 10 000 ⭐", 10000),
            .info(7, strings.starsEditorHint)
        ]
        return (
            ItemListControllerState(
                presentationData: ItemListPresentationData(presentationData), title: .text(strings.starsBalance),
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
