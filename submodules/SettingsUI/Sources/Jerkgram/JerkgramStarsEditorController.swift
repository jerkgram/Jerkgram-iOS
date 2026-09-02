import Foundation
import Display
import SwiftSignalKit
import TelegramPresentationData
import ItemListUI
import AccountContext

// MARK: Jerkgram v1.2K BUILD122_STARS_DRAFT_EDITOR1
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
        // MARK: Jerkgram v1.2M BUILD124_STARS_REDESIGN1
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
    return value.allSatisfy { $0.isNumber || $0 == "." || $0 == " " || $0 == "\u{00a0}" }
}

private func jerkgramSanitizeStarsDraft(_ text: String) -> String {
    let compact = text.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "\u{00a0}", with: "").replacingOccurrences(of: ",", with: ".")
    guard jerkgramIsValidStarsDraft(compact) else { return "0" }
    return compact.isEmpty ? "0" : compact
}

private func jerkgramStarsPreset(_ current: String, delta: Int64) -> String {
    let whole = current.split(separator: ".", maxSplits: 1).first.flatMap { Int64($0) } ?? 0
    return String(max(0, whole + delta))
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
        amount: (defaults.string(forKey: scopedAmount) ?? defaults.string(forKey: jerkgramStarsAmountKey)).map(jerkgramSanitizeStarsDraft) ?? "0"
    )
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
        let dirty = state != initial
        let leftNavigationButton = ItemListNavigationButton(content: .text(presentationData.strings.Common_Cancel), style: .regular, enabled: true, action: {
            let _ = (controller?.navigationController as? NavigationController)?.popViewController(animated: true)
        })
        let rightNavigationButton = ItemListNavigationButton(content: .text(presentationData.strings.Common_Save), style: .bold, enabled: dirty, action: {
            jerkgramCommitStarsDraft(accountPeerId: accountPeerId, state: stateValue.with { $0 })
            let _ = (controller?.navigationController as? NavigationController)?.popViewController(animated: true)
        })
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
                leftNavigationButton: leftNavigationButton, rightNavigationButton: rightNavigationButton,
                backNavigationButton: nil
            ),
            (ItemListNodeState(
                presentationData: ItemListPresentationData(presentationData), entries: entries,
                style: .blocks, animateChanges: false
            ), arguments as Any)
        )
    }
    controller = ItemListController(context: context, state: signal)
    return controller!
}
