import Foundation
import UIKit
import AsyncDisplayKit
import Display
import SwiftSignalKit
import Postbox
import TelegramCore
import TelegramPresentationData
import AccountContext
import PeerInfoPaneNode

// MARK: GhostBase v1.1G PROFILEHISTORYBOUNDED1
private struct GhostBaseObservedProfileSnapshotV11G: Codable, Equatable {
    let observedAt: Int64
    let displayName: String
    let username: String?
    let about: String?
    let avatarResourceId: String?
    let emojiStatus: String

    func hasSameContent(as other: GhostBaseObservedProfileSnapshotV11G) -> Bool {
        return self.displayName == other.displayName
            && self.username == other.username
            && self.about == other.about
            && self.avatarResourceId == other.avatarResourceId
            && self.emojiStatus == other.emojiStatus
    }
}

private struct GhostBaseObservedProfileHistoryV11G: Codable {
    var current: GhostBaseObservedProfileSnapshotV11G
    var events: [GhostBaseObservedProfileSnapshotV11G]
}

private struct GhostBasePersonalChannelObservationV11G: Codable, Equatable {
    let observedAt: Int64
    let channelPeerId: Int64?
    let title: String?
    let username: String?
    let link: String?
    let subscriberCount: Int?
    let topMessageId: Int32?

    func hasSameContent(as other: GhostBasePersonalChannelObservationV11G) -> Bool {
        return self.channelPeerId == other.channelPeerId
            && self.title == other.title
            && self.username == other.username
            && self.link == other.link
            && self.subscriberCount == other.subscriberCount
            && self.topMessageId == other.topMessageId
    }
}

private struct GhostBasePersonalChannelHistoryV11G: Codable {
    var current: GhostBasePersonalChannelObservationV11G
    var events: [GhostBasePersonalChannelObservationV11G]
}

private enum GhostBaseProfileReportStoreV11G {
    static let queue = DispatchQueue(
        label: "jerkgram.ProfileReportStore.V11G",
        qos: .utility
    )
    static let maximumEvents = 200

    static func afterPendingWrites(
        _ action: @escaping () -> Void
    ) {
        self.queue.async(
            execute: action
        )
    }

    // Queue-confined caches ensure repeated PeerInfoScreen data updates do not
    // decode and rewrite the same history over and over.
    private static var profileHistories: [String: GhostBaseObservedProfileHistoryV11G] = [:]
    private static var loadedProfileKeys: Set<String> = []
    private static var personalChannelHistories: [String: GhostBasePersonalChannelHistoryV11G] = [:]
    private static var loadedPersonalChannelKeys: Set<String> = []

    static func profileKey(accountPeerId: Int64, peerId: Int64) -> String {
        return "jerkgram.ProfileHistory.V11G.\(accountPeerId).\(peerId)"
    }

    static func personalChannelKey(accountPeerId: Int64, peerId: Int64) -> String {
        // Reuse the established PROFILEINTEL3 key so old observations survive.
        return "jerkgram.ProfileIntel3.PersonalChannel.\(accountPeerId).\(peerId)"
    }

    static func recordProfile(
        accountPeerId: Int64,
        peerId: Int64,
        snapshot: GhostBaseObservedProfileSnapshotV11G
    ) {
        self.queue.async {
            let defaults = UserDefaults.standard
            let key = self.profileKey(
                accountPeerId: accountPeerId,
                peerId: peerId
            )
            var history: GhostBaseObservedProfileHistoryV11G
            if self.loadedProfileKeys.contains(key) {
                history = self.profileHistories[key] ?? GhostBaseObservedProfileHistoryV11G(
                    current: snapshot,
                    events: []
                )
            } else {
                self.loadedProfileKeys.insert(key)
                if let data = defaults.data(forKey: key),
                   let value = try? JSONDecoder().decode(
                    GhostBaseObservedProfileHistoryV11G.self,
                    from: data
                   ) {
                    history = value
                } else {
                    history = GhostBaseObservedProfileHistoryV11G(
                        current: snapshot,
                        events: []
                    )
                }
                self.profileHistories[key] = history
            }

            if !history.events.isEmpty,
               history.current.hasSameContent(as: snapshot) {
                return
            }

            history.events.append(snapshot)
            if history.events.count > self.maximumEvents {
                history.events.removeFirst(
                    history.events.count - self.maximumEvents
                )
            }
            history.current = snapshot
            self.profileHistories[key] = history

            if let data = try? JSONEncoder().encode(history) {
                defaults.set(data, forKey: key)
            }
        }
    }

    static func recordPersonalChannel(
        accountPeerId: Int64,
        peerId: Int64,
        observation: GhostBasePersonalChannelObservationV11G
    ) {
        self.queue.async {
            let defaults = UserDefaults.standard
            let key = self.personalChannelKey(
                accountPeerId: accountPeerId,
                peerId: peerId
            )
            var history: GhostBasePersonalChannelHistoryV11G
            if self.loadedPersonalChannelKeys.contains(key) {
                history = self.personalChannelHistories[key] ?? GhostBasePersonalChannelHistoryV11G(
                    current: observation,
                    events: []
                )
            } else {
                self.loadedPersonalChannelKeys.insert(key)
                if let data = defaults.data(forKey: key),
                   let value = try? JSONDecoder().decode(
                    GhostBasePersonalChannelHistoryV11G.self,
                    from: data
                   ) {
                    history = value
                } else {
                    history = GhostBasePersonalChannelHistoryV11G(
                        current: observation,
                        events: []
                    )
                }
                self.personalChannelHistories[key] = history
            }

            if !history.events.isEmpty,
               history.current.hasSameContent(as: observation) {
                return
            }

            history.events.append(observation)
            if history.events.count > self.maximumEvents {
                history.events.removeFirst(
                    history.events.count - self.maximumEvents
                )
            }
            history.current = observation
            self.personalChannelHistories[key] = history

            if let data = try? JSONEncoder().encode(history) {
                defaults.set(data, forKey: key)
            }
        }
    }

    static func profileReport(accountPeerId: Int64, peerId: Int64) -> String? {
        let defaults = UserDefaults.standard

        let key = self.profileKey(
            accountPeerId: accountPeerId,
            peerId: peerId
        )

        var sections: [String] = []

        if let data = defaults.data(forKey: key),
           let history = try? JSONDecoder().decode(
            GhostBaseObservedProfileHistoryV11G.self,
            from: data
           ) {
            let formatter = DateFormatter()
            formatter.locale = Locale(
                identifier: "ru_RU"
            )
            formatter.dateFormat = "dd.MM.yyyy HH:mm"

            func value(_ value: String?) -> String {
                guard let value, !value.isEmpty else {
                    return "—"
                }
                return value
            }

            // MARK: Jerkgram v1.2G BUILD118_PROFILE_REPORT_SEMANTICS1
            func emojiStatusValue(_ raw: String) -> String {
                if raw == "nil" { return "—" }
                if let marker = raw.range(of: "fileId: ") {
                    let suffix = raw[marker.upperBound...]
                    let digits = suffix.prefix(while: { $0.isNumber })
                    if !digits.isEmpty { return "#" + digits }
                }
                if raw.localizedCaseInsensitiveContains("starGift") { return "🎁" }
                return "●"
            }

            var blocks: [String] = []
            var changeCount = 0

            if history.events.count >= 2 {
                for index in stride(
                    from: history.events.count - 1,
                    through: 1,
                    by: -1
                ) {
                    let previous = history.events[index - 1]
                    let current = history.events[index]

                    var changes: [String] = []

                    if previous.displayName != current.displayName {
                        changes.append(
                            "Имя: \(value(previous.displayName)) → \(value(current.displayName))"
                        )
                    }

                    if previous.username != current.username {
                        changes.append(
                            "Юзернейм: \(value(previous.username)) → \(value(current.username))"
                        )
                    }

                    if previous.about != current.about {
                        changes.append(
                            "Описание: \(value(previous.about)) → \(value(current.about))"
                        )
                    }

                    if previous.avatarResourceId != current.avatarResourceId {
                        let description: String

                        if previous.avatarResourceId == nil {
                            description = "Аватар: установлен"
                        } else if current.avatarResourceId == nil {
                            description = "Аватар: удалён"
                        } else {
                            description = "Аватар: изменён"
                        }

                        changes.append(
                            description
                        )
                    }

                    if previous.emojiStatus != current.emojiStatus {
                        changes.append(
                            "Эмодзи-статус: \(emojiStatusValue(previous.emojiStatus)) → \(emojiStatusValue(current.emojiStatus))"
                        )
                    }

                    guard !changes.isEmpty else {
                        continue
                    }

                    changeCount += changes.count

                    let date = formatter.string(
                        from: Date(
                            timeIntervalSince1970:
                                TimeInterval(
                                    current.observedAt
                                )
                        )
                    )

                    blocks.append(
                        (
                            [date]
                            + changes.map {
                                "• \($0)"
                            }
                        )
                        .joined(
                            separator: "\n"
                        )
                    )
                }
            }

            var lines: [String] = []

            lines.append(
                "История изменений профиля"
            )

            lines.append(
                "Зафиксировано изменений: \(changeCount)"
            )

            if let first = history.events.first {
                lines.append(
                    "Первое наблюдение: "
                    + formatter.string(
                        from: Date(
                            timeIntervalSince1970:
                                TimeInterval(
                                    first.observedAt
                                )
                        )
                    )
                )
            }

            if blocks.isEmpty {
                lines.append(
                    "Изменений после первого наблюдения пока нет."
                )
            } else {
                lines.append("")
                lines.append(
                    blocks.joined(
                        separator: "\n\n"
                    )
                )
            }

            sections.append(
                lines.joined(
                    separator: "\n"
                )
            )
        }

        // Preserve the old detailed logger instead of replacing
        // all historical information with a counter.
        let oldBase =
            "jerkgram.ProfileIntel2."
            + "\(accountPeerId)."
            + "\(peerId)."

        // V11M:
        // Keep legacy PROFILEINTEL2 persisted
        // for compatibility, but never render
        // raw debug/key=value text to the user.
        _ = defaults.string(
            forKey:
                oldBase + "History"
        )

        return sections.isEmpty
            ? nil
            : sections.joined(
                separator: "\n\n"
            )
    }

    // MARK: GhostBase v1.1I HISTORYCOMPILEFIX1
    static func personalChannelReport(
        accountPeerId: Int64,
        peerId: Int64
    ) -> String? {
        let key = self.personalChannelKey(
            accountPeerId: accountPeerId,
            peerId: peerId
        )

        guard
            let data = UserDefaults.standard.data(
                forKey: key
            ),
            let history = try? JSONDecoder().decode(
                GhostBasePersonalChannelHistoryV11G.self,
                from: data
            )
        else {
            return nil
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(
            identifier: "ru_RU"
        )
        formatter.dateFormat = "dd.MM.yyyy HH:mm"

        func stringValue(
            _ value: String?
        ) -> String {
            guard let value, !value.isEmpty else {
                return "—"
            }

            return value
        }

        func optionalValue<T>(
            _ value: T?
        ) -> String {
            guard let value else {
                return "—"
            }

            return String(
                describing: value
            )
        }

        var blocks: [String] = []
        var changeCount = 0

        if history.events.count >= 2 {
            for index in stride(
                from: history.events.count - 1,
                through: 1,
                by: -1
            ) {
                let previous =
                    history.events[index - 1]

                let current =
                    history.events[index]

                var changes: [String] = []

                if previous.channelPeerId
                    != current.channelPeerId {

                    if current.channelPeerId == nil {
                        changes.append(
                            "Личный канал: откреплён"
                        )
                    } else if previous.channelPeerId == nil {
                        changes.append(
                            "Личный канал: прикреплён"
                        )
                    } else {
                        let oldValue =
                            optionalValue(
                                previous.channelPeerId
                            )

                        let newValue =
                            optionalValue(
                                current.channelPeerId
                            )

                        changes.append(
                            "Канал ID: \(oldValue) → \(newValue)"
                        )
                    }
                }

                if previous.title
                    != current.title {

                    let oldValue =
                        stringValue(
                            previous.title
                        )

                    let newValue =
                        stringValue(
                            current.title
                        )

                    changes.append(
                        "Название: \(oldValue) → \(newValue)"
                    )
                }

                if previous.username
                    != current.username {

                    let oldValue =
                        stringValue(
                            previous.username
                        )

                    let newValue =
                        stringValue(
                            current.username
                        )

                    changes.append(
                        "Юзернейм: \(oldValue) → \(newValue)"
                    )
                }

                if previous.link
                    != current.link {

                    let oldValue =
                        stringValue(
                            previous.link
                        )

                    let newValue =
                        stringValue(
                            current.link
                        )

                    changes.append(
                        "Ссылка: \(oldValue) → \(newValue)"
                    )
                }

                if previous.subscriberCount
                    != current.subscriberCount {

                    let oldValue =
                        optionalValue(
                            previous.subscriberCount
                        )

                    let newValue =
                        optionalValue(
                            current.subscriberCount
                        )

                    changes.append(
                        "Подписчики: \(oldValue) → \(newValue)"
                    )
                }

                if previous.topMessageId
                    != current.topMessageId {

                    let oldValue =
                        optionalValue(
                            previous.topMessageId
                        )

                    let newValue =
                        optionalValue(
                            current.topMessageId
                        )

                    changes.append(
                        "Последний message ID: \(oldValue) → \(newValue)"
                    )
                }

                guard !changes.isEmpty else {
                    continue
                }

                changeCount += changes.count

                let timestamp =
                    TimeInterval(
                        current.observedAt
                    )

                let date =
                    formatter.string(
                        from: Date(
                            timeIntervalSince1970:
                                timestamp
                        )
                    )

                var lines: [String] = [
                    date
                ]

                for change in changes {
                    lines.append(
                        "• \(change)"
                    )
                }

                blocks.append(
                    lines.joined(
                        separator: "\n"
                    )
                )
            }
        }

        var lines: [String] = [
            "История личного канала",
            "Зафиксировано изменений: \(changeCount)"
        ]

        if let first = history.events.first {
            let timestamp =
                TimeInterval(
                    first.observedAt
                )

            let date =
                formatter.string(
                    from: Date(
                        timeIntervalSince1970:
                            timestamp
                    )
                )

            lines.append(
                "Первое наблюдение: \(date)"
            )
        }

        if blocks.isEmpty {
            lines.append(
                "Изменений после первого наблюдения пока нет."
            )
        } else {
            lines.append("")
            lines.append(
                blocks.joined(
                    separator: "\n\n"
                )
            )
        }

        return lines.joined(
            separator: "\n"
        )
    }

}

func ghostBaseRecordObservedProfileV11G(
    accountPeerId: EnginePeer.Id,
    peer: EnginePeer,
    cachedData: CachedPeerData?
) {
    let about = (cachedData as? CachedUserData)?.about
    let snapshot = GhostBaseObservedProfileSnapshotV11G(
        observedAt: Int64(Date().timeIntervalSince1970),
        displayName: peer.compactDisplayTitle,
        username: peer.addressName,
        about: about,
        avatarResourceId: peer.profileImageRepresentations.last?.resource.id.stringRepresentation,
        emojiStatus: String(describing: peer.emojiStatus)
    )
    GhostBaseProfileReportStoreV11G.recordProfile(
        accountPeerId: accountPeerId.toInt64(),
        peerId: peer.id.toInt64(),
        snapshot: snapshot
    )
}

func ghostBaseRecordPersonalChannelObservationV11G(
    accountPeerId: EnginePeer.Id,
    targetPeerId: EnginePeer.Id,
    personalChannel: PeerInfoPersonalChannelData?
) {
    let channelPeer = personalChannel?.peer.peer
    let username = channelPeer?.addressName
    let observation = GhostBasePersonalChannelObservationV11G(
        observedAt: Int64(Date().timeIntervalSince1970),
        channelPeerId: channelPeer?.id.toInt64(),
        title: channelPeer?.compactDisplayTitle,
        username: username,
        link: username.map { "https://t.me/\($0)" },
        subscriberCount: personalChannel?.subscriberCount,
        topMessageId: personalChannel?.topMessages.first?.id.id
    )
    GhostBaseProfileReportStoreV11G.recordPersonalChannel(
        accountPeerId: accountPeerId.toInt64(),
        peerId: targetPeerId.toInt64(),
        observation: observation
    )
}

// MARK: GhostBase v1.1R HISTORY_CARDS1
private final class GhostBaseProfileReportCardNode: ASDisplayNode {
    private let textNode = ImmediateTextNode()

    override init() {
        super.init()
        self.clipsToBounds = true
        self.layer.cornerRadius = 16.0
        self.textNode.displaysAsynchronously = false
        self.textNode.maximumNumberOfLines = 0
        self.addSubnode(self.textNode)
    }

    func update(
        text: String,
        presentationData: PresentationData,
        width: CGFloat
    ) -> CGSize {
        // MARK: JerkGram v1.1Y BUILD110_REPORT_CONTRAST1
        let isDark = presentationData.theme.overallDarkAppearance
        self.backgroundColor = UIColor(
            white: isDark ? 0.0 : 1.0,
            alpha: isDark ? 0.26 : 0.18
        )
        self.layer.borderWidth = 0.5
        self.layer.borderColor = presentationData.theme.list.itemPlainSeparatorColor
            .withAlphaComponent(isDark ? 0.30 : 0.20).cgColor

        let lines = text.components(separatedBy: "\n")
        let attributed = NSMutableAttributedString(string: "")
        for (index, line) in lines.enumerated() {
            if index != 0 {
                attributed.append(NSAttributedString(string: "\n"))
            }
            attributed.append(NSAttributedString(
                string: line,
                font: index == 0 ? Font.semibold(14.0) : Font.regular(14.0),
                textColor: index == 0
                    ? presentationData.theme.list.itemPrimaryTextColor
                    : presentationData.theme.list.itemSecondaryTextColor
            ))
        }
        self.textNode.attributedText = attributed
        let inset: CGFloat = 14.0
        let textSize = self.textNode.updateLayout(CGSize(
            width: max(1.0, width - inset * 2.0),
            height: .greatestFiniteMagnitude
        ))
        self.textNode.frame = CGRect(
            origin: CGPoint(x: inset, y: 12.0),
            size: textSize
        )
        return CGSize(width: width, height: textSize.height + 24.0)
    }
}

// MARK: GhostBase v1.1G NATIVEPANES1
final class GhostBaseProfileReportPaneNode: ASDisplayNode, PeerInfoPaneNode, UIScrollViewDelegate {
    enum Kind {
        case profileHistory
        case presence
        case giftHistory
        case personalChannel
    }

    weak var parentController: ViewController?

    private let accountPeerId: EnginePeer.Id
    private let peerId: EnginePeer.Id
    private let kind: Kind
    private let personalChannel: PeerInfoPersonalChannelData?

    private let scrollNode = ASScrollNode()
    private var cardNodes: [GhostBaseProfileReportCardNode] = []
    private var renderedReportSections: [String] = []
    private let readyPromise = ValuePromise<Bool>(true, ignoreRepeated: true)
    private let statusPromise = Promise<PeerInfoStatusData?>(nil)

    private var currentPresentationData: PresentationData?
    private var currentSize: CGSize?
    private var reportText: String?
    private var didStartLoading = false
    private var wasVisible = false
    private var isApplyingScrollClamp = false

    var isReady: Signal<Bool, NoError> {
        return self.readyPromise.get()
    }

    var status: Signal<PeerInfoStatusData?, NoError> {
        return self.statusPromise.get()
    }

    var tabBarOffsetUpdated: ((ContainedViewLayoutTransition) -> Void)?

    var tabBarOffset: CGFloat {
        // MARK: GhostBase v1.1O HISTORYSTATICHEADER1
        //
        // Text reports scroll only inside their clipped viewport.
        // They never drive PeerInfo header/tab collapsing.
        return 0.0
    }

    init(
        context: AccountContext,
        peerId: EnginePeer.Id,
        kind: Kind,
        personalChannel: PeerInfoPersonalChannelData?
    ) {
        self.accountPeerId = context.account.peerId
        self.peerId = peerId
        self.kind = kind
        self.personalChannel = personalChannel

        super.init()

        self.backgroundColor = .clear
        self.scrollNode.backgroundColor = .clear

        self.addSubnode(self.scrollNode)
    }

    override func didLoad() {
        super.didLoad()
        self.scrollNode.view.backgroundColor = .clear
        self.scrollNode.view.contentInsetAdjustmentBehavior = .never
        self.scrollNode.view.alwaysBounceVertical = false
        self.scrollNode.view.scrollsToTop = false
        self.scrollNode.view.delegate = self
    }

    private func startLoadingIfNeeded() {
        guard !self.didStartLoading else {
            return
        }

        self.didStartLoading = true

        let accountPeerId =
            self.accountPeerId

        let peerId =
            self.peerId

        let kind =
            self.kind

        let personalChannel =
            self.personalChannel

        let load: () -> Void = {
            [weak self] in

            let text =
                Self.loadReport(
                    accountPeerId:
                        accountPeerId,
                    peerId:
                        peerId,
                    kind:
                        kind,
                    personalChannel:
                        personalChannel
                )

            DispatchQueue.main.async {
                guard let self else {
                    return
                }

                self.reportText =
                    text

                self.updateTextLayout(
                    transition: .immediate
                )
            }
        }

        switch kind {
        case .profileHistory,
             .personalChannel:

            GhostBaseProfileReportStoreV11G
                .afterPendingWrites(
                    load
                )

        case .presence,
             .giftHistory:

            DispatchQueue.global(
                qos: .utility
            )
            .async(
                execute: load
            )
        }
    }

    // MARK: GhostBase v1.1M HISTORYPRESENTATION1
    private static func prettyGiftHistoryReport(
        _ raw: String
    ) -> String {
        let rawLines =
            raw.split(
                whereSeparator: {
                    $0.isNewline
                }
            )
            .map(
                String.init
            )

        guard !rawLines.isEmpty else {
            return "История подарков пока пуста."
        }

        var result: [String] = []

        let firstLine =
            rawLines[0]

        if let colon =
            firstLine.lastIndex(
                of: ":"
            ) {

            let count =
                firstLine[
                    firstLine.index(
                        after: colon
                    )...
                ]
                .trimmingCharacters(
                    in:
                        .whitespacesAndNewlines
                )

            result.append(
                "История подарков"
            )

            result.append(
                "Записей: \(count)"
            )
        } else {
            result.append(
                "История подарков"
            )
        }

        let labels: [String: String] = [
            "giftId":
                "ID подарка",
            "uniqueId":
                "Уникальный ID",
            "slug":
                "Slug",
            "number":
                "Номер",
            "sender":
                "Отправитель",
            "senderId":
                "ID отправителя",
            "username":
                "Username",
            "text":
                "Сообщение",
            "first":
                "Первое наблюдение",
            "lastVisible":
                "Последнее наблюдение",
            "last":
                "Последнее наблюдение"
        ]

        for rawLine
            in rawLines.dropFirst() {

            let parts =
                rawLine.components(
                    separatedBy:
                        " · "
                )

            var block: [String] = []

            for (
                index,
                originalPart
            ) in parts.enumerated() {

                let part =
                    originalPart
                        .trimmingCharacters(
                            in:
                                .whitespacesAndNewlines
                        )

                guard !part.isEmpty else {
                    continue
                }

                if index == 0 {
                    block.append(part)
                    continue
                }

                if (
                    part.lowercased()
                        == "видимый"
                    || part.lowercased()
                        == "visible"
                ) {
                    block.append(
                        "Статус: видимый"
                    )
                    continue
                }

                if part.hasPrefix(
                    "Подарок "
                ) {
                    block.insert(
                        part,
                        at: 0
                    )
                    continue
                }

                guard let equals =
                    part.firstIndex(
                        of: "="
                    )
                else {
                    block.append(part)
                    continue
                }

                let key =
                    String(
                        part[..<equals]
                    )
                    .trimmingCharacters(
                        in:
                            .whitespacesAndNewlines
                    )

                var value =
                    String(
                        part[
                            part.index(
                                after: equals
                            )...
                        ]
                    )
                    .trimmingCharacters(
                        in:
                            .whitespacesAndNewlines
                    )

                if (
                    value == "nil"
                    || value.isEmpty
                ) {
                    continue
                }

                if (
                    value.hasPrefix("'")
                    && value.hasSuffix("'")
                    && value.count >= 2
                ) {
                    value.removeFirst()
                    value.removeLast()
                }

                if (
                    key == "username"
                    && !value.hasPrefix("@")
                ) {
                    value =
                        "@" + value
                }

                let label =
                    labels[key]
                    ?? key

                block.append(
                    "\(label): \(value)"
                )
            }

            if !block.isEmpty {
                result.append("")

                result.append(
                    block.joined(
                        separator: "\n"
                    )
                )
            }
        }

        return result.joined(
            separator: "\n"
        )
    }

    private static func loadReport(
        accountPeerId: EnginePeer.Id,
        peerId: EnginePeer.Id,
        kind: Kind,
        personalChannel: PeerInfoPersonalChannelData?
    ) -> String {
        switch kind {
        case .presence:
            return ghostBasePresenceHistoryReport(
                accountPeerId: accountPeerId,
                peerId: peerId
            ) ?? "История присутствия пока пуста."

        case .giftHistory:
            let report =
                ghostBaseGiftHistoryReport(
                    accountPeerId:
                        accountPeerId,
                    peerId:
                        peerId
                )

            return report.isEmpty
                ? "История подарков пока пуста."
                : self.prettyGiftHistoryReport(
                    report
                )

        case .profileHistory:
            return GhostBaseProfileReportStoreV11G.profileReport(
                accountPeerId: accountPeerId.toInt64(),
                peerId: peerId.toInt64()
            ) ?? "История профиля пока пуста."

        case .personalChannel:
            if let report = GhostBaseProfileReportStoreV11G.personalChannelReport(
                accountPeerId: accountPeerId.toInt64(),
                peerId: peerId.toInt64()
            ) {
                return report
            }
            if let personalChannel {
                var lines: [String] = ["Личный канал"]
                if let peer = personalChannel.peer.chatOrMonoforumMainPeer {
                    lines.append("Название: \(peer.compactDisplayTitle)")
                    lines.append("ID: \(peer.id.toInt64())")
                } else {
                    lines.append("ID: \(personalChannel.peer.peerId.toInt64())")
                }
                if let subscriberCount = personalChannel.subscriberCount {
                    lines.append("Подписчики: \(subscriberCount)")
                }
                lines.append("Последние сообщения: \(personalChannel.topMessages.count)")
                return lines.joined(separator: "\n")
            }
            return "Личный канал не найден."
        }
    }

    private static func reportSections(_ text: String) -> [String] {
        let sections = text
            .components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return sections.isEmpty ? [text] : sections
    }

    private func updateTextLayout(transition: ContainedViewLayoutTransition) {
        guard let size = self.currentSize,
              let presentationData = self.currentPresentationData else {
            return
        }

        let strings = presentationData.strings.jerkgram
        let rawText = self.reportText ?? strings.profileReportLoading
        let text = strings.localizedProfileReport(rawText)
        let sections = Self.reportSections(text)

        if sections != self.renderedReportSections {
            for node in self.cardNodes {
                node.removeFromSupernode()
            }
            self.cardNodes.removeAll(keepingCapacity: true)
            self.renderedReportSections = sections
            for _ in sections {
                let node = GhostBaseProfileReportCardNode()
                self.cardNodes.append(node)
                self.scrollNode.addSubnode(node)
            }
        }

        let sideInset: CGFloat = 16.0
        let spacing: CGFloat = 10.0
        let cardWidth = max(1.0, size.width - sideInset * 2.0)
        var y: CGFloat = 16.0

        for index in 0 ..< min(sections.count, self.cardNodes.count) {
            let node = self.cardNodes[index]
            let cardSize = node.update(
                text: sections[index],
                presentationData: presentationData,
                width: cardWidth
            )
            transition.updateFrame(
                node: node,
                frame: CGRect(
                    origin: CGPoint(x: sideInset, y: y),
                    size: cardSize
                )
            )
            y += cardSize.height + spacing
        }

        let contentHeight = max(size.height + 1.0, y + 10.0)
        self.scrollNode.view.contentSize = CGSize(
            width: size.width,
            height: contentHeight
        )
    }

    func update(
        size: CGSize,
        topInset: CGFloat,
        sideInset: CGFloat,
        bottomInset: CGFloat,
        deviceMetrics: DeviceMetrics,
        visibleHeight: CGFloat,
        isScrollingLockedAtTop: Bool,
        expandProgress: CGFloat,
        navigationHeight: CGFloat,
        presentationData: PresentationData,
        synchronous: Bool,
        transition: ContainedViewLayoutTransition
    ) {
        // MARK: GhostBase v1.1N HISTORYVIEWPORT_FINAL1
        //
        // The report scroll view no longer exists underneath
        // the profile header/tab bar. Offset clamping alone
        // cannot prevent content from being rendered there.
        let viewportTop =
            max(
                0.0,
                topInset
            )

        let viewportSize =
            CGSize(
                width:
                    size.width,
                height:
                    max(
                        0.0,
                        size.height
                        - viewportTop
                    )
            )

        self.currentSize =
            viewportSize

        self.currentPresentationData =
            presentationData

        transition.updateFrame(
            node:
                self.scrollNode,
            frame:
                CGRect(
                    origin:
                        CGPoint(
                            x: 0.0,
                            y: viewportTop
                        ),
                    size:
                        viewportSize
                )
        )

        // MARK: GhostBase v1.1Q HISTORY_CLIP_HARDENING1
        self.clipsToBounds =
            true

        self.scrollNode.clipsToBounds =
            true

        self.scrollNode.view.clipsToBounds =
            true

        self.scrollNode.view.contentInset =
            UIEdgeInsets(
                top:
                    0.0,
                left:
                    0.0,
                bottom:
                    bottomInset,
                right:
                    0.0
            )

        self.scrollNode.view.scrollIndicatorInsets =
            self.scrollNode.view.contentInset
        self.updateTextLayout(transition: transition)

        let isVisible =
            visibleHeight > 0.0

        if isVisible
            && !self.wasVisible {

            self.didStartLoading =
                false

            self.startLoadingIfNeeded()
        }

        self.wasVisible =
            isVisible
    }

    func scrollViewDidScroll(
        _ scrollView: UIScrollView
    ) {
        if !self.isApplyingScrollClamp {
            let minimumY =
                -scrollView
                    .contentInset
                    .top

            let maximumY =
                max(
                    minimumY,
                    scrollView
                        .contentSize
                        .height
                    - scrollView
                        .bounds
                        .height
                    + scrollView
                        .contentInset
                        .bottom
                )

            let clampedY =
                min(
                    maximumY,
                    max(
                        minimumY,
                        scrollView
                            .contentOffset
                            .y
                    )
                )

            if abs(
                clampedY
                - scrollView
                    .contentOffset
                    .y
            ) > 0.5 {
                self.isApplyingScrollClamp =
                    true

                scrollView.setContentOffset(
                    CGPoint(
                        x: 0.0,
                        y: clampedY
                    ),
                    animated: false
                )

                self.isApplyingScrollClamp =
                    false
            }
        }

        // Report scrolling deliberately does not move PeerInfo tabs.
    }

    func scrollToTop() -> Bool {
        self.scrollNode.view.setContentOffset(
            CGPoint(x: 0.0, y: -self.scrollNode.view.contentInset.top),
            animated: true
        )
        return true
    }

    func transferVelocity(_ velocity: CGFloat) {
    }

    func cancelPreviewGestures() {
    }

    func findLoadedMessage(id: EngineMessage.Id) -> EngineMessage? {
        return nil
    }

    func transitionNodeForGallery(
        messageId: EngineMessage.Id,
        media: EngineMedia
    ) -> (ASDisplayNode, CGRect, () -> (UIView?, UIView?))? {
        return nil
    }

    func addToTransitionSurface(view: UIView) {
        self.view.addSubview(view)
    }

    func updateHiddenMedia() {
    }

    func updateSelectedMessages(animated: Bool) {
    }

    func ensureMessageIsVisible(id: EngineMessage.Id) {
    }
}
