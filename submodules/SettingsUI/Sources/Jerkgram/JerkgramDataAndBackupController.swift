import Foundation
import Display
import SwiftSignalKit
import TelegramPresentationData
import ItemListUI
import AccountContext
import JerkgramCore

// MARK: Jerkgram v1.2G BUILD118_DATA_BACKUP_UI1
// MARK: Jerkgram v1.2H BUILD119_DATA_SUMMARY1
// MARK: Jerkgram v1.2M BUILD124_DATA_REDESIGN1
private struct JerkgramDataUIState: Equatable {
    var configuration: JerkgramRetentionConfiguration
}

private final class JerkgramDataUIArguments {
    let action: (String) -> Void
    let toggle: (String, Bool) -> Void
    init(action: @escaping (String) -> Void, toggle: @escaping (String, Bool) -> Void) {
        self.action = action
        self.toggle = toggle
    }
}

private enum JerkgramDataUIEntry: ItemListNodeEntry {
    case header(Int32, String)
    case summary(Int32, Int32, String, String)
    case action(Int32, Int32, String, String, String)
    case toggle(Int32, Int32, String, String, Bool)
    case info(Int32, String)

    var section: ItemListSectionId {
        switch self {
        case let .header(section, _), let .summary(section, _, _, _), let .action(section, _, _, _, _), let .toggle(section, _, _, _, _), let .info(section, _): return section
        }
    }
    var stableId: Int32 {
        switch self {
        case let .header(section, _): return section * 1000
        case let .summary(section, index, _, _): return section * 1000 + index
        case let .action(section, index, _, _, _), let .toggle(section, index, _, _, _): return section * 1000 + index
        case let .info(section, _): return section * 1000 + 999
        }
    }
    static func == (lhs: Self, rhs: Self) -> Bool { return lhs.stableId == rhs.stableId && String(describing: lhs) == String(describing: rhs) }
    static func < (lhs: Self, rhs: Self) -> Bool { return lhs.stableId < rhs.stableId }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! JerkgramDataUIArguments
        switch self {
        case let .header(_, title):
            return ItemListSectionHeaderItem(presentationData: presentationData, text: title, sectionId: self.section)
        case let .summary(_, _, title, value):
            return ItemListDisclosureItem(
                presentationData: presentationData, systemStyle: .glass,
                title: title, label: value, labelStyle: .text,
                sectionId: self.section, style: .blocks,
                disclosureStyle: .none, action: nil
            )
        // MARK: Jerkgram v1.2K BUILD122_DATA_ACTIONS1
        case let .action(_, _, title, value, action):
            if action == "export" || action == "import" || action == "cleanup" {
                return ItemListActionItem(
                    presentationData: presentationData, title: title,
                    kind: .generic, alignment: .center,
                    sectionId: self.section, style: .blocks,
                    action: { arguments.action(action) }
                )
            }
            return ItemListDisclosureItem(
                presentationData: presentationData, systemStyle: .glass,
                title: title, label: value, labelStyle: .text,
                sectionId: self.section, style: .blocks,
                disclosureStyle: action == "perChat" ? .arrow : .none,
                action: { arguments.action(action) }
            )
        case let .toggle(_, _, title, action, value):
            return ItemListSwitchItem(
                presentationData: presentationData, systemStyle: .glass,
                title: title, value: value, sectionId: self.section,
                style: .blocks, updated: { arguments.toggle(action, $0) }
            )
        case let .info(_, text):
            return ItemListTextItem(presentationData: presentationData, text: .plain(text), sectionId: self.section)
        }
    }
}

private func jerkgramDurationTitle(_ value: JerkgramHistoryDuration, strings: JerkgramStrings) -> String {
    switch value {
    case .disabled: return strings.disabled
    case .days7: return strings.days(7)
    case .days30: return strings.days(30)
    case .days90: return strings.days(90)
    case .forever: return strings.forever
    }
}

private func jerkgramMediaLimitTitle(_ value: JerkgramMediaByteLimit, strings: JerkgramStrings) -> String {
    switch value {
    case .disabled: return strings.disabled
    case .megabytes250: return "250 MB"
    case .megabytes500: return "500 MB"
    case .gigabytes1: return "1 GB"
    case .gigabytes2: return "2 GB"
    case .gigabytes5: return "5 GB"
    case .unlimited: return strings.unlimited
    }
}

private func jerkgramDataEntries(state: JerkgramDataUIState, strings: JerkgramStrings) -> [JerkgramDataUIEntry] {
    let policy = state.configuration.accountPolicy
    let summary = strings.build124DataSummary(
        jerkgramDurationTitle(policy.historyDuration, strings: strings),
        jerkgramMediaLimitTitle(policy.mediaByteLimit, strings: strings),
        state.configuration.accountPeerId
    )
    var entries: [JerkgramDataUIEntry] = [
        .summary(0, 1, strings.dataAndBackup, summary),
        .header(1, strings.retentionRules),
        .action(1, 1, strings.historyDuration, jerkgramDurationTitle(policy.historyDuration, strings: strings), "duration"),
        .action(1, 2, strings.recoveredMediaLimit, jerkgramMediaLimitTitle(policy.mediaByteLimit, strings: strings), "media"),
        .toggle(1, 3, strings.archiveSecretChats, "secretChats", policy.archiveSecretChats),
        .action(1, 4, strings.perChatRules, "", "perChat"),
        .action(1, 5, strings.cleanupExpired, "", "cleanup"),
    ]
    if policy.historyDuration == .forever && policy.mediaByteLimit == .unlimited {
        entries.append(.info(1, strings.foreverUnlimitedWarning + " (Forever + Unlimited)"))
    }
    entries.append(contentsOf: [
        .header(2, strings.backup),
        .action(2, 1, strings.exportArchive, "Build124 Canary", "export"),
        .action(2, 2, strings.importArchive, "Archive v2", "import"),
        .info(2, strings.backupAccountHint(state.configuration.accountPeerId)),
    ])
    return entries
}

public func jerkgramDataAndBackupController(context: AccountContext) -> ViewController {
    let accountPeerId = context.account.peerId.toInt64()
    let initial = JerkgramDataUIState(
        configuration: JerkgramRetentionRuntime.configuration(accountPeerId: accountPeerId)
    )
    let stateValue = Atomic(value: initial)
    let statePromise = ValuePromise(initial, ignoreRepeated: true)
    var controller: ItemListController?

    func update(_ transform: (inout JerkgramRetentionConfiguration) -> Void) {
        let value = stateValue.modify { current in
            var current = current
            transform(&current.configuration)
            try? JerkgramRetentionRuntime.save(current.configuration)
            return current
        }
        statePromise.set(value)
    }

    let durations: [JerkgramHistoryDuration] = [.disabled, .days7, .days30, .days90, .forever]
    let mediaLimits: [JerkgramMediaByteLimit] = [.disabled, .megabytes250, .megabytes500, .gigabytes1, .gigabytes2, .gigabytes5, .unlimited]
    let arguments = JerkgramDataUIArguments(action: { action in
        switch action {
        case "duration":
            update { configuration in
                let current = configuration.accountPolicy.historyDuration
                configuration.accountPolicy.historyDuration = durations[(durations.firstIndex(of: current)! + 1) % durations.count]
            }
        case "media":
            update { configuration in
                let current = configuration.accountPolicy.mediaByteLimit
                configuration.accountPolicy.mediaByteLimit = mediaLimits[(mediaLimits.firstIndex(of: current)! + 1) % mediaLimits.count]
            }
        case "export":
            if let controller { jerkgramPresentArchiveExport(context: context, controller: controller) }
        case "import":
            if let controller { jerkgramPresentArchiveImport(context: context, controller: controller) }
        case "perChat":
            let strings = context.sharedContext.currentPresentationData.with { $0.strings.jerkgram }
            let picker = context.sharedContext.makePeerSelectionController(
                PeerSelectionControllerParams(
                    context: context,
                    filter: [.removeSearchHeader, .excludeRecent, .doNotSearchMessages],
                    title: strings.perChatRules
                )
            )
            picker.peerSelected = { [weak picker, weak controller] peer, _ in
                picker?.dismiss()
                controller?.push(jerkgramChatRetentionController(
                    context: context,
                    chatPeerId: peer.id.toInt64()
                ))
            }
            controller?.push(picker)
        case "cleanup":
            Queue.concurrentDefaultQueue().async {
                let store = JerkgramJSONLEventStore(rootURL: jerkgramDataCoreRootURL())
                if let events = try? store.events(accountPeerId: accountPeerId, chatPeerId: nil) {
                    let configuration = JerkgramRetentionRuntime.configuration(accountPeerId: accountPeerId)
                    let plan = JerkgramRetentionEngine.cleanupPlan(
                        events: events,
                        policy: configuration.accountPolicy,
                        nowMs: Int64(Date().timeIntervalSince1970 * 1000.0)
                    )
                    try? JerkgramRetentionEngine.applyCleanup(
                        accountPeerId: accountPeerId,
                        originalEvents: events,
                        plan: plan,
                        mediaRootURL: jerkgramDataCoreRootURL(),
                        eventStore: store
                    )
                }
            }
        default:
            break
        }
    }, toggle: { action, value in
        if action == "secretChats" {
            update { $0.accountPolicy.archiveSecretChats = value }
        }
    })

    let signal = combineLatest(context.sharedContext.presentationData, statePromise.get())
    |> deliverOnMainQueue
    |> map { presentationData, state -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let strings = presentationData.strings.jerkgram
        return (
            ItemListControllerState(
                presentationData: ItemListPresentationData(presentationData),
                title: .text(strings.dataAndBackup),
                leftNavigationButton: nil, rightNavigationButton: nil,
                backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
            ),
            (ItemListNodeState(
                presentationData: ItemListPresentationData(presentationData),
                entries: jerkgramDataEntries(state: state, strings: strings),
                style: .blocks, animateChanges: false
            ), arguments as Any)
        )
    }
    controller = ItemListController(context: context, state: signal)
    return controller!
}

private func jerkgramDataCoreRootURL() -> URL {
    return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Jerkgram", isDirectory: true)
}

private func jerkgramChatRetentionController(
    context: AccountContext,
    chatPeerId: Int64
) -> ViewController {
    let accountPeerId = context.account.peerId.toInt64()
    let initial = JerkgramDataUIState(
        configuration: JerkgramRetentionRuntime.configuration(accountPeerId: accountPeerId)
    )
    let stateValue = Atomic(value: initial)
    let statePromise = ValuePromise(initial, ignoreRepeated: true)

    func update(_ transform: (inout JerkgramChatRetentionOverride) -> Void) {
        let value = stateValue.modify { current in
            var current = current
            var override = current.configuration.chatOverrides.first(where: { $0.chatPeerId == chatPeerId })
                ?? JerkgramChatRetentionOverride(chatPeerId: chatPeerId)
            transform(&override)
            current.configuration.chatOverrides.removeAll(where: { $0.chatPeerId == chatPeerId })
            current.configuration.chatOverrides.append(override)
            try? JerkgramRetentionRuntime.save(current.configuration)
            return current
        }
        statePromise.set(value)
    }

    let durations: [JerkgramHistoryDuration] = [.days7, .days30, .days90, .forever]
    let mediaLimits: [JerkgramMediaByteLimit] = [.disabled, .megabytes250, .megabytes500, .gigabytes1, .gigabytes2, .gigabytes5, .unlimited]
    let arguments = JerkgramDataUIArguments(action: { action in
        if action == "chatDuration" {
            update { value in
                let current = value.historyDuration ?? .days30
                value.historyDuration = durations[(durations.firstIndex(of: current) ?? 0) + 1 == durations.count ? 0 : (durations.firstIndex(of: current) ?? 0) + 1]
            }
        } else if action == "chatMedia" {
            update { value in
                let current = value.mediaByteLimit ?? .gigabytes1
                value.mediaByteLimit = mediaLimits[((mediaLimits.firstIndex(of: current) ?? 0) + 1) % mediaLimits.count]
            }
        }
    }, toggle: { action, enabled in
        if action == "chatCapture" { update { $0.captureEnabled = enabled } }
    })

    let signal = combineLatest(context.sharedContext.presentationData, statePromise.get())
    |> deliverOnMainQueue
    |> map { presentationData, state -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let strings = presentationData.strings.jerkgram
        let override = state.configuration.chatOverrides.first(where: { $0.chatPeerId == chatPeerId })
            ?? JerkgramChatRetentionOverride(chatPeerId: chatPeerId)
        let policy = state.configuration.effectivePolicy(chatPeerId: chatPeerId).1
        let entries: [JerkgramDataUIEntry] = [
            .header(0, strings.perChatRules),
            .toggle(0, 1, strings.saveThisChat, "chatCapture", override.captureEnabled ?? true),
            .action(0, 2, strings.historyDuration, jerkgramDurationTitle(policy.historyDuration, strings: strings), "chatDuration"),
            .action(0, 3, strings.recoveredMediaLimit, jerkgramMediaLimitTitle(policy.mediaByteLimit, strings: strings), "chatMedia"),
            .info(0, strings.chatRuleHint(chatPeerId)),
        ]
        return (
            ItemListControllerState(
                presentationData: ItemListPresentationData(presentationData),
                title: .text(strings.perChatRules), leftNavigationButton: nil,
                rightNavigationButton: nil,
                backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
            ),
            (ItemListNodeState(
                presentationData: ItemListPresentationData(presentationData),
                entries: entries, style: .blocks, animateChanges: false
            ), arguments as Any)
        )
    }
    return ItemListController(context: context, state: signal)
}
