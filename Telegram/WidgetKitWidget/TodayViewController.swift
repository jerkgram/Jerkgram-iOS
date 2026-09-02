#if arch(arm64) || arch(x86_64)

import UIKit
import NotificationCenter
import BuildConfig
import WidgetItems
import AppLockState
import SwiftUI
import WidgetKit
import Intents

import OpenSSLEncryptionProvider
import SwiftSignalKit
import Postbox
import TelegramCore
import OpenSSLEncryptionProvider
import WidgetItemsUtils

import GeneratedSources


// MARK: Jerkgram v1.2C BUILD114_SIGNER_APPGROUP1
private func jerkgramResolvedApplicationGroupIdentifier(
    fallback: String
) -> String {
    let bundleURL = Bundle.main.bundleURL

    var profileURLs: [URL] = [
        bundleURL.appendingPathComponent(
            "embedded.mobileprovision"
        )
    ]

    // For an extension:
    //
    // Foo.app/PlugIns/Bar.appex
    //                 ↓
    // Foo.app/embedded.mobileprovision
    //
    // Some signers embed a profile in every .appex,
    // others only keep the main-app profile. Support both.
    let possibleContainingAppURL =
        bundleURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()

    if possibleContainingAppURL.pathExtension == "app" {
        profileURLs.append(
            possibleContainingAppURL
                .appendingPathComponent(
                    "embedded.mobileprovision"
                )
        )
    }

    var visited = Set<String>()

    for profileURL in profileURLs {
        if visited.contains(profileURL.path) {
            continue
        }

        visited.insert(profileURL.path)

        guard let profileData =
            try? Data(contentsOf: profileURL)
        else {
            continue
        }

        // A .mobileprovision is CMS-wrapped, but the plist
        // payload itself is embedded as XML. We only read
        // that plist; no private Security API is required.
        let profileText = String(
            decoding: profileData,
            as: UTF8.self
        )

        guard
            let plistStart = profileText.range(
                of: "<plist"
            ),
            let plistEnd = profileText.range(
                of: "</plist>",
                options: [.backwards]
            ),
            plistStart.lowerBound
                < plistEnd.upperBound
        else {
            continue
        }

        let plistText = String(
            profileText[
                plistStart.lowerBound
                ..< plistEnd.upperBound
            ]
        )

        guard
            let plistData = plistText.data(
                using: .utf8
            ),
            let root = try?
                PropertyListSerialization
                    .propertyList(
                        from: plistData,
                        options: [],
                        format: nil
                    ) as? [String: Any],
            let entitlements =
                root["Entitlements"]
                    as? [String: Any],
            let groups =
                entitlements[
                    "com.apple.security.application-groups"
                ] as? [String]
        else {
            continue
        }

        // BUILD115_SHARED_APPGROUP_ROLE1
        //
        // Never trust entitlement array ordering.
        //
        // 1. Prefer the normal Telegram-derived fallback
        //    when the signer actually grants it.
        //
        // 2. GhostBase historically stores shared state in
        //    the signer-provided App Group whose role suffix
        //    is ".1".
        //
        // 3. A single granted group is unambiguous.
        //
        // 4. For an ambiguous multi-group profile with no
        //    matching role, do not select an arbitrary first
        //    entry. Try the containing-app profile and then
        //    fall back to the normal Telegram derivation.
        let allowedGroups = groups.filter {
            !$0.isEmpty
        }

        if allowedGroups.contains(fallback) {
            return fallback
        }

        let roleOneGroups = allowedGroups.filter {
            $0.hasSuffix(".1")
        }

        if roleOneGroups.count == 1 {
            return roleOneGroups[0]
        }

        if allowedGroups.count == 1 {
            return allowedGroups[0]
        }
    }

    return fallback
}

struct ParsedPeer {
    var accountId: Int64
    var accountPeerId: Int64
    var peer: WidgetDataPeer
}

struct ParsedPeers {
    var peers: [ParsedPeer]
    var updateTimestamp: Int32
}

private extension ParsedPeers {
    init(accountId: Int64, peers: WidgetDataPeers) {
        self.init(peers: peers.peers.map { peer -> ParsedPeer in
            return ParsedPeer(
                accountId: accountId,
                accountPeerId: peers.accountPeerId,
                peer: peer
            )
        }, updateTimestamp: peers.updateTimestamp)
    }
}

private var installedSharedLogger = false

private func setupSharedLogger(rootPath: String, path: String) {
    if !installedSharedLogger {
        installedSharedLogger = true
        Logger.setSharedLogger(Logger(rootPath: rootPath, basePath: path))
    }
}

private let accountAuxiliaryMethods = AccountAuxiliaryMethods(fetchResource: { account, resource, ranges, _ in
    return nil
}, fetchResourceMediaReferenceHash: { resource in
    return .single(nil)
}, prepareSecretThumbnailData: { _ in
    return nil
}, backgroundUpload: { _, _, _ in
    return .single(nil)
})

private func rootPathForBasePath(_ appGroupPath: String) -> String {
    return appGroupPath + "/telegram-data"
}

@available(iOS 14.0, *)
private func getCommonTimeline(friends: [Friend]?, in context: TimelineProviderContext, completion: @escaping (Timeline<SimpleEntry>) -> ()) {
    if context.isPreview {
        completion(Timeline(entries: [SimpleEntry(date: Date(), contents: .preview)], policy: .atEnd))
        return
    }
    
    let currentDate = Date()
    let entryDate = Calendar.current.date(byAdding: .hour, value: 0, to: currentDate)!
    
    guard let appBundleIdentifier = Bundle.main.bundleIdentifier, let lastDotRange = appBundleIdentifier.range(of: ".", options: [.backwards]) else {
        completion(Timeline(entries: [SimpleEntry(date: entryDate, contents: .recent)], policy: .atEnd))
        return
    }
    _ = lastDotRange
    
    let baseAppBundleId = String(appBundleIdentifier[..<lastDotRange.lowerBound])
    
    
    let appGroupName = jerkgramResolvedApplicationGroupIdentifier(fallback: "group.\(baseAppBundleId)")
// MARK: Jerkgram v1.2E BUILD116_EXTENSION_STAGE1
BuildConfig.jerkgramRecordExtensionDiagnostic(
    process: "widget",
    stage: "profile",
    appGroupIdentifier: appGroupName,
    sharedContainerPath: nil,
    detail: "selected app-group identifier"
)
    
    let maybeAppGroupUrl = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupName)
BuildConfig.jerkgramRecordExtensionDiagnostic(
    process: "widget",
    stage: "container",
    appGroupIdentifier: appGroupName,
    sharedContainerPath: maybeAppGroupUrl?.path,
    detail: "containerURL resolved"
)
    
    guard let appGroupUrl = maybeAppGroupUrl else {
        let message = BuildConfig.jerkgramExtensionBoundarySummary(
            process: "Widget", stage: "container", path: nil
        )
        completion(Timeline(entries: [SimpleEntry(date: entryDate, contents: .diagnostic(message))], policy: .atEnd))
        return
    }
    let classification = BuildConfig.jerkgramExtensionContainerClassification(path: appGroupUrl.path)
    if classification != "shared" {
        let message = BuildConfig.jerkgramExtensionBoundarySummary(
            process: "Widget", stage: "account", path: appGroupUrl.path
        )
        completion(Timeline(entries: [SimpleEntry(date: entryDate, contents: .diagnostic(message))], policy: .atEnd))
        return
    }
    
    let rootPath = rootPathForBasePath(appGroupUrl.path)
    
    TempBox.initializeShared(basePath: rootPath, processType: "widget", launchSpecificId: Int64.random(in: Int64.min ... Int64.max))
    
    let logsPath = rootPath + "/logs/widget-logs"
    let _ = try? FileManager.default.createDirectory(atPath: logsPath, withIntermediateDirectories: true, attributes: nil)
    
    setupSharedLogger(rootPath: logsPath, path: logsPath)
    
    initializeAccountManagement()
    
    let deviceSpecificEncryptionParameters = BuildConfig.deviceSpecificEncryptionParameters(rootPath, baseAppBundleId: baseAppBundleId)
BuildConfig.jerkgramRecordExtensionDiagnostic(
    process: "widget",
    stage: "root",
    appGroupIdentifier: appGroupName,
    sharedContainerPath: appGroupUrl.path,
    detail: "telegram-data root ready"
)
BuildConfig.jerkgramRecordExtensionDiagnostic(
    process: "widget",
    stage: "encryption",
    appGroupIdentifier: appGroupName,
    sharedContainerPath: appGroupUrl.path,
    detail: "encryption parameters ready"
)
    let encryptionParameters = ValueBoxEncryptionParameters(forceEncryptionIfNoSet: false, key: ValueBoxEncryptionParameters.Key(data: deviceSpecificEncryptionParameters.key)!, salt: ValueBoxEncryptionParameters.Salt(data: deviceSpecificEncryptionParameters.salt)!)
    
    BuildConfig.jerkgramRecordExtensionDiagnostic(
        process: "widget",
        stage: "account",
        appGroupIdentifier: appGroupName,
        sharedContainerPath: appGroupUrl.path,
        detail: "account-backed implementation initialization"
    )
    var itemsByAccount: [Int64: [(Int64, Friend)]] = [:]
    var itemOrder: [(Int64, Int64)] = []
    if let friends = friends {
        for item in friends {
            guard let identifier = item.identifier else {
                continue
            }
            guard let index = identifier.firstIndex(of: ":") else {
                continue
            }
            guard let accountId = Int64(identifier[identifier.startIndex ..< index]) else {
                continue
            }
            guard let peerId = Int64(identifier[identifier.index(after: index)...]) else {
                continue
            }
            if itemsByAccount[accountId] == nil {
                itemsByAccount[accountId] = []
            }
            itemsByAccount[accountId]?.append((peerId, item))
            itemOrder.append((accountId, peerId))
        }
    }
    
    var friendsByAccount: [Signal<[ParsedPeer], NoError>] = []
    for (accountId, items) in itemsByAccount {
        friendsByAccount.append(accountTransaction(rootPath: rootPath, id: AccountRecordId(rawValue: accountId), encryptionParameters: encryptionParameters, isReadOnly: true, useCopy: false, transaction: { postbox, transaction -> [ParsedPeer] in
            guard let state = transaction.getState() as? AuthorizedAccountState else {
                return []
            }
            
            var result: [ParsedPeer] = []
            
            for (peerId, _) in items {
                guard let peer = transaction.getPeer(PeerId(peerId)) else {
                    continue
                }
                
                var name: String = ""
                var lastName: String?
                
                if let user = peer as? TelegramUser {
                    if let firstName = user.firstName {
                        name = firstName
                        lastName = user.lastName
                    } else if let lastName = user.lastName {
                        name = lastName
                    } else if let phone = user.phone, !phone.isEmpty {
                        name = phone
                    }
                } else {
                    name = peer.debugDisplayTitle
                }
                
                var badge: WidgetDataPeer.Badge?
                
                if let readState = transaction.getCombinedPeerReadState(peer.id), readState.count > 0 {
                    var isMuted = false
                    if let notificationSettings = transaction.getPeerNotificationSettings(id: peer.id) as? TelegramPeerNotificationSettings {
                        isMuted = notificationSettings.isRemovedFromTotalUnreadCount(default: false)
                    }
                    badge = WidgetDataPeer.Badge(
                        count: Int(readState.count),
                        isMuted: isMuted
                    )
                }
                
                var mappedMessage: WidgetDataPeer.Message?
                if let index = transaction.getTopPeerMessageIndex(peerId: peer.id) {
                    if let message = transaction.getMessage(index.id) {
                        mappedMessage = WidgetDataPeer.Message(accountPeerId: state.peerId, message: EngineMessage(message))
                    }
                }
                
                var isForum = false
                if let peer = peer as? TelegramChannel, peer.isForumOrMonoForum {
                    isForum = true
                }
                
                let widgetPeer = WidgetDataPeer(id: peer.id.toInt64(), name: name, lastName: lastName, letters: peer.displayLetters, avatarPath: smallestImageRepresentation(peer.profileImageRepresentations).flatMap { representation in
                    return postbox.mediaBox.resourcePath(representation.resource)
                }, badge: badge, message: mappedMessage, isForum: isForum)
                
                result.append(ParsedPeer(accountId: accountId, accountPeerId: state.peerId.toInt64(), peer: widgetPeer))
            }
            
            return result
        })
        |> `catch` { _ -> Signal<[ParsedPeer], NoError> in
            return .single([])
        })
    }
    
    let _ = combineLatest(friendsByAccount).start(next: { allPeers in
        var orderedPeers: [ParsedPeer] = []
        
        outer: for (accountId, peerId) in itemOrder {
            for peerSet in allPeers {
                for peer in peerSet {
                    if peer.accountId == accountId && peer.peer.id == peerId {
                        orderedPeers.append(peer)
                        continue outer
                    }
                }
            }
        }
        
        let result = ParsedPeers(peers: orderedPeers, updateTimestamp: Int32(Date().timeIntervalSince1970))
        completion(Timeline(entries: [SimpleEntry(date: entryDate, contents: .peers(result))], policy: .atEnd))
    })
}

@available(iOSApplicationExtension 14.0, iOS 14.0, *)
struct Provider: IntentTimelineProvider {
    public typealias Entry = SimpleEntry
    
    func placeholder(in context: Context) -> SimpleEntry {
        return SimpleEntry(date: Date(), contents: .recent)
    }

    func getSnapshot(for configuration: SelectFriendsIntent, in context: Context, completion: @escaping (SimpleEntry) -> ()) {
        let entry = SimpleEntry(date: Date(), contents: context.isPreview ? .preview : .peers(ParsedPeers(accountId: 0, peers: WidgetDataPeers(accountPeerId: 0, peers: [], updateTimestamp: 0))))
        completion(entry)
    }

    func getTimeline(for configuration: SelectFriendsIntent, in context: Context, completion: @escaping (Timeline<Entry>) -> ()) {
        getCommonTimeline(friends: configuration.friends, in: context, completion: completion)
    }
}

@available(iOSApplicationExtension 14.0, iOS 14.0, *)
struct AvatarsProvider: IntentTimelineProvider {
    public typealias Entry = SimpleEntry
    
    func placeholder(in context: Context) -> SimpleEntry {
        return SimpleEntry(date: Date(), contents: .recent)
    }

    func getSnapshot(for configuration: SelectAvatarFriendsIntent, in context: Context, completion: @escaping (SimpleEntry) -> ()) {
        let entry = SimpleEntry(date: Date(), contents: context.isPreview ? .preview : .peers(ParsedPeers(accountId: 0, peers: WidgetDataPeers(accountPeerId: 0, peers: [], updateTimestamp: 0))))
        completion(entry)
    }

    func getTimeline(for configuration: SelectAvatarFriendsIntent, in context: Context, completion: @escaping (Timeline<Entry>) -> ()) {
        getCommonTimeline(friends: configuration.friends, in: context, completion: completion)
    }
}

@available(iOSApplicationExtension 14.0, iOS 14.0, *)
struct SimpleEntry: TimelineEntry {
    enum Contents {
        case recent
        case preview
        case peers(ParsedPeers)
        case diagnostic(String)
    }
    
    let date: Date
    let contents: Contents
}

enum PeersWidgetData {
    case empty
    case preview
    case peers(ParsedPeers)
    case diagnostic(String)
}

@available(iOSApplicationExtension 14.0, iOS 14.0, *)
struct AvatarItemView: View {
    var peer: ParsedPeer?
    var itemSize: CGFloat
    var placeholderColor: Color
    
    var body: some View {
        return ZStack {
            if let peer = peer {
                Image(uiImage: avatarImage(accountPeerId: peer.accountPeerId, peer: peer.peer, size: CGSize(width: itemSize, height: itemSize), style: peer.peer.isForum ? .roundedRect : .round))
                    .mask(peer.peer.isForum ? AnyView(RoundedRectangle(cornerRadius: itemSize * 0.25)) : AnyView(Circle()))
            } else {
                Circle()
                    .fill(placeholderColor)
                    .frame(width: itemSize, height: itemSize)
            }
        }
    }
}

// MARK: Jerkgram v1.2F BUILD117_WIDGET_VISIBLE_DIAGNOSTIC1
@available(iOSApplicationExtension 14.0, iOS 14.0, *)
private struct JerkgramWidgetDiagnosticView: View {
    let message: String
    var body: some View {
        VStack(spacing: 8.0) {
            Image(systemName: "exclamationmark.triangle")
            Text("Jerkgram")
                .font(.headline)
            Text(String(message.prefix(240)))
                .font(.caption)
                .multilineTextAlignment(.center)
        }
        .padding(12.0)
    }
}

@available(iOSApplicationExtension 14.0, iOS 14.0, *)
struct WidgetView: View {
    @Environment(\.widgetFamily) private var widgetFamily
    @Environment(\.colorScheme) private var colorScheme
    let data: PeersWidgetData
    let presentationData: WidgetPresentationData
    
    private func linkForPeer(accountId: Int64, id: Int64) -> String {
        switch self.widgetFamily {
        case .systemSmall:
            return "\(buildConfig.appSpecificUrlScheme)://"
        default:
            return "\(buildConfig.appSpecificUrlScheme)://localpeer?id=\(id)&accountId=\(accountId)"
        }
    }
    
    func chatTopLine(_ content: ChatContent) -> some View {
        let dateText: String
        
        let chatTitle: AnyView
        let date: Text
        var isPlaceholder = false
        
        switch content {
        case let .peer(peer):
            if let message = peer.peer.message {
                dateText = DateFormatter.localizedString(from: Date(timeIntervalSince1970: Double(message.timestamp)), dateStyle: .none, timeStyle: .short)
            } else {
                dateText = ""
            }
            var formattedName = peer.peer.name
            if peer.accountPeerId == peer.peer.id {
                formattedName = self.presentationData.chatSavedMessages
            } else if let lastName = peer.peer.lastName {
                formattedName.append(" \(lastName)")
            }
            chatTitle = AnyView(Text(formattedName)
                .lineLimit(1)
                .font(Font.system(size: 16.0, weight: .medium, design: .default))
                .foregroundColor(.primary))
            date = Text(dateText)
            .font(Font.system(size: 14.0, weight: .regular, design: .default)).foregroundColor(.secondary)
        case let .preview(index):
            let titleText = index == 0 ? "News Channel" : "Duck"
            dateText = index == 0 ? "9:00" : "8:42"
            chatTitle = AnyView(Text(titleText)
                .lineLimit(1)
                .font(Font.system(size: 16.0, weight: .medium, design: .default))
                .foregroundColor(.primary))
            date = Text(dateText)
            .font(Font.system(size: 14.0, weight: .regular, design: .default)).foregroundColor(.secondary)
        case .placeholder:
            isPlaceholder = true
            dateText = "         "
            chatTitle = AnyView(Text(" ").font(Font.system(size: 16.0, weight: .medium, design: .default)).foregroundColor(.primary))
            date = Text(dateText)
            .font(Font.system(size: 16.0, weight: .regular, design: .default)).foregroundColor(.secondary)
        }
        return HStack(alignment: .center, spacing: 0.0, content: {
            if !isPlaceholder {
                chatTitle
            } else {
                chatTitle
                    .frame(minWidth: 48.0)
                    .background(GeometryReader { geometry in
                        RoundedRectangle(cornerRadius: 4.0)
                            .fill(getPlaceholderColor())
                            .frame(width: geometry.size.width, height: 8.0, alignment: .center)
                            .offset(x: 0.0, y: (geometry.size.height - 8.0) / 2.0 + 1.0)
                        }
                    )
            }
            Spacer()
            if !isPlaceholder {
                date
            } else {
                date
                    .background(GeometryReader { geometry in
                        RoundedRectangle(cornerRadius: 4.0)
                            .fill(getPlaceholderColor())
                            .frame(width: geometry.size.width, height: 8.0, alignment: .center)
                            .offset(x: 0.0, y: (geometry.size.height - 8.0) / 2.0)
                        }
                    )
            }
        })
        .padding(0.0)
    }
    
    func chatBottomLine(_ content: ChatContent) -> AnyView {
        var text = ""
        var isPlaceholder = false
        switch content {
        case let .peer(peer):
            if let message = peer.peer.message {
                text = message.text
                switch message.content {
                case .text:
                    break
                case .image:
                    if !message.text.isEmpty {
                        text = "🖼 \(message.text)"
                    } else {
                        text = "🖼 \(self.presentationData.messagePhoto)"
                    }
                case .video:
                    if !message.text.isEmpty {
                        text = "📹 \(message.text)"
                    } else {
                        text = "📹 \(self.presentationData.messageVideo)"
                    }
                case .gif:
                    if !message.text.isEmpty {
                        text = "\(message.text)"
                    } else {
                        text = "\(self.presentationData.messageAnimation)"
                    }
                case let .file(file):
                    if !message.text.isEmpty {
                        text = "📹 \(message.text)"
                    } else {
                        text = "📎 \(file.name)"
                    }
                case let .music(music):
                    if !music.title.isEmpty && !music.artist.isEmpty {
                        text = "\(music.artist) — \(music.title)"
                    } else if !music.title.isEmpty {
                        text = music.title
                    } else if !music.artist.isEmpty {
                        text = music.artist
                    } else {
                        text = "Unknown Artist"
                    }
                case .voiceMessage:
                    text = "🎤 \(self.presentationData.messageVoice)"
                case .videoMessage:
                    text = "\(self.presentationData.messageVideoMessage)"
                case let .sticker(sticker):
                    text = "\(sticker.altText) \(presentationData.messageSticker)"
                case let .call(call):
                    if call.isVideo {
                        text = "\(self.presentationData.messageVideoCall)"
                    } else {
                        text = "\(self.presentationData.messageVoiceCall)"
                    }
                case .mapLocation:
                    text = "\(self.presentationData.messageLocation)"
                case let .game(game):
                    text = "🎮 \(game.title)"
                case let .poll(poll):
                    text = "📊 \(poll.title)"
                case let .autodeleteTimer(value):
                    if value.value != nil {
                        text = self.presentationData.autodeleteTimerUpdated
                    } else {
                        text = self.presentationData.autodeleteTimerRemoved
                    }
                }
                
                if let author = message.author {
                    if author.isMe {
                        text = "\(presentationData.messageAuthorYou): \(text)"
                    } else {
                        text = "\(author.title): \(text)"
                    }
                }
            }
            text += "\n"
        case let .preview(index):
            if index == 0 {
                text = "☀️ 23 °C\n☁️ Passing Clouds"
            } else {
                text = "😂 \(presentationData.messageSticker)"
                text += "\n"
            }
        case .placeholder:
            isPlaceholder = true
        }
        
        let textView = Text(text)
            .lineLimit(2)
            .font(Font.system(size: 15.0, weight: .regular, design: .default))
            .foregroundColor(.secondary)
            .multilineTextAlignment(.leading)
            .padding(0.0)
        
        if !isPlaceholder {
            return AnyView(textView)
        } else {
            return AnyView(
                VStack(alignment: .leading, spacing: 0.0, content: {
                    Text(" ")
                        .lineLimit(1)
                        .font(Font.system(size: 15.0, weight: .regular, design: .default))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                        .padding(0.0)
                        .frame(minWidth: 182.0)
                    .background(GeometryReader { geometry in
                        RoundedRectangle(cornerRadius: 4.0)
                            .fill(getPlaceholderColor())
                            .frame(width: geometry.size.width, height: 8.0, alignment: .center)
                            .offset(x: 0.0, y: (geometry.size.height - 8.0) / 2.0 - 1.0)
                        }
                    )
                    Text(" ")
                        .lineLimit(1)
                        .font(Font.system(size: 15.0, weight: .regular, design: .default))
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.leading)
                        .padding(0.0)
                        .frame(minWidth: 96.0)
                    .background(GeometryReader { geometry in
                        RoundedRectangle(cornerRadius: 4.0)
                            .fill(getPlaceholderColor())
                            .frame(width: geometry.size.width, height: 8.0, alignment: .center)
                            .offset(x: 0.0, y: (geometry.size.height - 8.0) / 2.0 - 1.0)
                        }
                    )
                })
            )
        }
    }
    
    enum ChatContent {
        case peer(ParsedPeer)
        case preview(Int)
        case placeholder
    }
    
    func chatContent(_ content: ChatContent) -> some View {
        return VStack(alignment: .leading, spacing: 0.0, content: {
            chatTopLine(content)
            chatBottomLine(content)
        })
    }
    
    func chatContentView(_ index: Int, size: CGSize) -> AnyView {
        let peers: ParsedPeers?
        var isPlaceholder = false
        var isPreview = false
        switch data {
        case let .peers(peersValue):
            if peersValue.peers.count <= index {
                isPlaceholder = peersValue.peers.count != 0
                peers = nil
            } else {
                peers = peersValue
            }
        case .preview:
            peers = nil
            isPreview = true
        default:
            peers = nil
        }
        
        let itemHeight = (size.height - 22.0) / 2.0
        
        if isPlaceholder {
            return AnyView(Spacer()
                .frame(width: size.width, height: itemHeight, alignment: .leading)
            )
        }
        
        if isPreview {
            return AnyView(
                HStack(alignment: .center, spacing: 0.0, content: {
                    Image("Widget/Avatar\(index == 0 ? "Channel" : "1")")
                        .aspectRatio(1.0, contentMode: .fit)
                        .clipShape(Circle())
                        .frame(width: 54.0, height: 54.0, alignment: .leading)
                        .padding(EdgeInsets(top: 0.0, leading: 10.0, bottom: 0.0, trailing: 10.0))
                    chatContent(.preview(index)).frame(maxWidth: .infinity).padding(EdgeInsets(top: 0.0, leading: 0.0, bottom: 0.0, trailing: 10.0))
                })
                .frame(width: size.width, height: itemHeight, alignment: .leading)
            )
        }
        
        let url: URL
        if let peers = peers {
            url = URL(string: linkForPeer(accountId: peers.peers[index].accountId, id: peers.peers[index].peer.id))!
        } else {
            url = URL(string: "\(buildConfig.appSpecificUrlScheme)://")!
        }
        
        let content: ChatContent
        if let peer = peers?.peers[index] {
            content = .peer(peer)
        } else {
            content = .placeholder
        }
        
        let avatarView: AvatarItemView
        avatarView = AvatarItemView(peer: peers?.peers[index], itemSize: 54.0, placeholderColor: getPlaceholderColor())
        
        return AnyView(
            Link(destination: url, label: {
                HStack(alignment: .center, spacing: 0.0, content: {
                    avatarView
                        .frame(width: 54.0, height: 54.0, alignment: .leading)
                        .padding(EdgeInsets(top: 0.0, leading: 10.0, bottom: 0.0, trailing: 10.0))
                    chatContent(content).frame(maxWidth: .infinity).padding(EdgeInsets(top: 0.0, leading: 0.0, bottom: 0.0, trailing: 10.0))
                })
            })
            .frame(width: size.width, height: itemHeight, alignment: .leading)
        )
    }
    
    func chatSeparatorView(size: CGSize) -> some View {
        return HStack(alignment: .center, spacing: 0.0, content: {
            Spacer()
            Rectangle()
                .foregroundColor(getSeparatorColor())
                .frame(width: size.width - 54.0 - 20.0, height: 0.5, alignment: .leading)
        })
        .frame(width: size.width, height: 1.0, alignment: .leading)
    }
    
    func chatsUpdateBackgroundView(size: CGSize) -> some View {
        return Rectangle().foregroundColor(getUpdatedBackgroundColor())
            //.position(x: size.width / 2.0, y: size.height - 11.0)
            .frame(width: size.width, height: 22.0, alignment: .center)
    }
    
    func chatUpdateView(size: CGSize) -> some View {
        return ZStack(alignment: Alignment(horizontal: .center, vertical: .center), content: {
            Rectangle().foregroundColor(getUpdatedBackgroundColor())
            chatsUpdateTimestampView(size: size)
        })
        .frame(width: size.width, height: 22.0 - 1.0, alignment: .center)
    }
    
    func chatsUpdateTimestampView(size: CGSize) -> some View {
        let text: String
        switch data {
        case let .peers(peersValue):
            if peersValue.peers.isEmpty {
                text = self.presentationData.widgetLongTapToEdit
            } else {
                let date = Date(timeIntervalSince1970: Double(peersValue.updateTimestamp))
                let calendar = Calendar.current
                if !calendar.isDate(Date(), inSameDayAs: date) {
                    let formatter = DateFormatter()
                    formatter.dateStyle = .short
                    formatter.timeStyle = .none
                    text = self.presentationData.widgetUpdatedAt.replacingOccurrences(of: "{}", with: formatter.string(from: date))
                } else {
                    let formatter = DateFormatter()
                    formatter.dateStyle = .none
                    formatter.timeStyle = .short
                    text = self.presentationData.widgetUpdatedTodayAt.replacingOccurrences(of: "{}", with: formatter.string(from: date))
                }
            }
        case .preview:
            let date = Date()
            let calendar = Calendar.current
            if !calendar.isDate(Date(), inSameDayAs: date) {
                let formatter = DateFormatter()
                formatter.dateStyle = .short
                formatter.timeStyle = .none
                text = self.presentationData.widgetUpdatedAt.replacingOccurrences(of: "{}", with: formatter.string(from: date))
            } else {
                let formatter = DateFormatter()
                formatter.dateStyle = .none
                formatter.timeStyle = .short
                text = self.presentationData.widgetUpdatedTodayAt.replacingOccurrences(of: "{}", with: formatter.string(from: date))
            }
        default:
            text = self.presentationData.widgetLongTapToEdit
        }
        
        return Text(text)
            .font(Font.system(size: 12.0))
            .foregroundColor(getUpdatedTextColor())
    }
    
    func getBackgroundColor() -> Color {
        switch colorScheme {
        case .light:
            return .white
        case .dark:
            return Color(.sRGB, red: 28.0 / 255.0, green: 28.0 / 255.0, blue: 30.0 / 255.0, opacity: 1.0)
        @unknown default:
            return .secondary
        }
    }
    
    func getSeparatorColor() -> Color {
        switch colorScheme {
        case .light:
            return Color(.sRGB, red: 216.0 / 255.0, green: 216.0 / 255.0, blue: 216.0 / 255.0, opacity: 1.0)
        case .dark:
            return Color(.sRGB, red: 0.0 / 255.0, green: 0.0 / 255.0, blue: 0.0 / 255.0, opacity: 1.0)
        @unknown default:
            return .secondary
        }
    }
    
    func getUpdatedBackgroundColor() -> Color {
        switch colorScheme {
        case .light:
            return Color(.sRGB, red: 242.0 / 255.0, green: 242.0 / 255.0, blue: 247.0 / 255.0, opacity: 1.0)
        case .dark:
            return Color(.sRGB, red: 21.0 / 255.0, green: 21.0 / 255.0, blue: 21.0 / 255.0, opacity: 1.0)
        @unknown default:
            return .secondary
        }
    }
    
    func getUpdatedTextColor() -> Color {
        switch colorScheme {
        case .light:
            return Color(.sRGB, red: 142.0 / 255.0, green: 142.0 / 255.0, blue: 146.0 / 255.0, opacity: 1.0)
        case .dark:
            return Color(.sRGB, red: 142.0 / 255.0, green: 142.0 / 255.0, blue: 146.0 / 255.0, opacity: 1.0)
        @unknown default:
            return .secondary
        }
    }
    
    func getPlaceholderColor() -> Color {
        switch colorScheme {
        case .light:
            return Color(.sRGB, red: 235.0 / 255.0, green: 235.0 / 255.0, blue: 241.0 / 255.0, opacity: 1.0)
        case .dark:
            return Color(.sRGB, red: 38.0 / 255.0, green: 38.0 / 255.0, blue: 41.0 / 255.0, opacity: 1.0)
        @unknown default:
            return .secondary
        }
    }
    
    var body: some View {
        GeometryReader(content: { geometry in
            if case let .diagnostic(message) = data {
                JerkgramWidgetDiagnosticView(message: message)
            } else {
                VStack(alignment: .center, spacing: 0.0, content: {
                chatContentView(0, size: geometry.size)
                chatSeparatorView(size: geometry.size)
                chatContentView(1, size: geometry.size)
                chatUpdateView(size: geometry.size)
                })
            }
        })
        .padding(0.0)
        .unredacted()
        .widgetBackground(Rectangle().foregroundColor(getBackgroundColor()))
    }
}

@available(iOSApplicationExtension 14.0, iOS 14.0, *)
extension View {
    func widgetBackground(_ backgroundView: some View) -> some View {
        if #available(iOSApplicationExtension 17.0, iOS 17.0, *) {
            return containerBackground(for: .widget) {
                backgroundView
            }
        } else {
            return background(backgroundView)
        }
    }
}

@available(iOSApplicationExtension 14.0, iOS 14.0, *)
struct AvatarsWidgetView: View {
    @Environment(\.widgetFamily) private var widgetFamily
    @Environment(\.colorScheme) private var colorScheme
    let data: PeersWidgetData
    let presentationData: WidgetPresentationData
    
    func placeholder(geometry: GeometryProxy) -> some View {
        return Spacer()
    }
    
    private func linkForPeer(accountId: Int64, id: Int64) -> String {
        switch self.widgetFamily {
        case .systemSmall:
            return "\(buildConfig.appSpecificUrlScheme)://"
        default:
            return "\(buildConfig.appSpecificUrlScheme)://localpeer?id=\(id)&accountId=\(accountId)"
        }
    }
    
    func getPlaceholderColor() -> Color {
        switch colorScheme {
        case .light:
            return Color(.sRGB, red: 235.0 / 255.0, green: 235.0 / 255.0, blue: 241.0 / 255.0, opacity: 1.0)
        case .dark:
            return Color(.sRGB, red: 38.0 / 255.0, green: 38.0 / 255.0, blue: 41.0 / 255.0, opacity: 1.0)
        @unknown default:
            return .secondary
        }
    }
    
    func getBackgroundColor() -> Color {
        switch colorScheme {
        case .light:
            return .white
        case .dark:
            return Color(.sRGB, red: 28.0 / 255.0, green: 28.0 / 255.0, blue: 30.0 / 255.0, opacity: 1.0)
        @unknown default:
            return .secondary
        }
    }
    
    func itemView(index: Int) -> some View {
        let peers: ParsedPeers?
        var isPlaceholder = false
        var isPreview = false
        switch data {
        case let .peers(peersValue):
            if peersValue.peers.count <= index {
                isPlaceholder = peersValue.peers.count != 0
                peers = nil
            } else {
                peers = peersValue
            }
        case .preview:
            peers = nil
            isPreview = true
        default:
            peers = nil
        }
        
        if let peers = peers {
            return AnyView(Link(destination: URL(string: linkForPeer(accountId: peers.peers[index].accountId, id: peers.peers[index].peer.id))!, label: {
                GeometryReader(content: { geometry in
                    AvatarItemView(peer: peers.peers[index], itemSize: geometry.size.height, placeholderColor: getPlaceholderColor())
                })
            }).aspectRatio(1.0, contentMode: .fit))
        } else if isPlaceholder {
            return AnyView(Circle().aspectRatio(1.0, contentMode: .fit).foregroundColor(getPlaceholderColor()))
        } else if isPreview {
            return AnyView(Image("Widget/Avatar\(index + 1)").aspectRatio(1.0, contentMode: .fit).clipShape(Circle()))
        } else {
            return AnyView(Circle().aspectRatio(1.0, contentMode: .fit).foregroundColor(getPlaceholderColor()))
        }
    }
    
    var body: some View {
        Group {
            if case let .diagnostic(message) = data {
                JerkgramWidgetDiagnosticView(message: message)
            } else {
                VStack(alignment: .center, spacing: 18.0, content: {
            HStack(alignment: .center, spacing: nil, content: {
                ForEach(0 ..< 4, id: \.self) { index in
                    itemView(index: index)
                    if index != 3 {
                        Spacer()
                    }
                }
            })
            HStack(alignment: .center, spacing: nil, content: {
                ForEach(0 ..< 4, id: \.self) { index in
                    itemView(index: 4 + index)
                    if index != 3 {
                        Spacer()
                    }
                }
            })
                })
                .padding(EdgeInsets(top: 10.0, leading: 10.0, bottom: 10.0, trailing: 10.0))
            }
        }
        .unredacted()
        .widgetBackground(Rectangle().foregroundColor(getBackgroundColor()))
    }
}

private let buildConfig: BuildConfig = {
    let appBundleIdentifier = Bundle.main.bundleIdentifier!
    guard let lastDotRange = appBundleIdentifier.range(of: ".", options: [.backwards]) else {
        preconditionFailure()
    }
    _ = lastDotRange
    let baseAppBundleId = String(appBundleIdentifier[..<lastDotRange.lowerBound])
    
    let buildConfig = BuildConfig(baseAppBundleId: baseAppBundleId)
    return buildConfig
}()

@available(iOSApplicationExtension 14.0, iOS 14.0, *)
func getWidgetData(contents: SimpleEntry.Contents) -> PeersWidgetData {
    switch contents {
    case .recent:
        return .empty
    case .preview:
        return .preview
    case let .peers(peers):
        return .peers(peers)
    case let .diagnostic(message):
        return .diagnostic(message)
    }
}

@available(iOSApplicationExtension 14.0, iOS 14.0, *)
struct Static_Widget: Widget {
    private let kind: String = "Static_Widget"

    public var body: some WidgetConfiguration {
        let presentationData = WidgetPresentationData.getForExtension()
        
        if #available(iOSApplicationExtension 15.0, iOS 15.0, *) {
            return IntentConfiguration(kind: kind, intent: SelectFriendsIntent.self, provider: Provider(), content: { entry in
                WidgetView(data: getWidgetData(contents: entry.contents), presentationData: presentationData)
            })
            .supportedFamilies([.systemMedium])
            .configurationDisplayName(presentationData.widgetChatsGalleryTitle)
            .contentMarginsDisabled()
            .description(presentationData.widgetChatsGalleryDescription)
        } else {
            return IntentConfiguration(kind: kind, intent: SelectFriendsIntent.self, provider: Provider(), content: { entry in
                WidgetView(data: getWidgetData(contents: entry.contents), presentationData: presentationData)
            })
            .supportedFamilies([.systemMedium])
            .configurationDisplayName(presentationData.widgetChatsGalleryTitle)
            .description(presentationData.widgetChatsGalleryDescription)
        }
    }
}

@available(iOSApplicationExtension 14.0, iOS 14.0, *)
struct Static_AvatarsWidget: Widget {
    private let kind: String = "Static_AvatarsWidget"

    public var body: some WidgetConfiguration {
        let presentationData = WidgetPresentationData.getForExtension()
        
        if #available(iOSApplicationExtension 15.0, iOS 15.0, *) {
            return IntentConfiguration(kind: kind, intent: SelectAvatarFriendsIntent.self, provider: AvatarsProvider(), content: { entry in
                AvatarsWidgetView(data: getWidgetData(contents: entry.contents), presentationData: presentationData)
            })
            .supportedFamilies([.systemMedium])
            .configurationDisplayName(presentationData.widgetShortcutsGalleryTitle)
            .contentMarginsDisabled()
            .description(presentationData.widgetShortcutsGalleryDescription)
        } else {
            return IntentConfiguration(kind: kind, intent: SelectAvatarFriendsIntent.self, provider: AvatarsProvider(), content: { entry in
                AvatarsWidgetView(data: getWidgetData(contents: entry.contents), presentationData: presentationData)
            })
            .supportedFamilies([.systemMedium])
            .configurationDisplayName(presentationData.widgetShortcutsGalleryTitle)
            .description(presentationData.widgetShortcutsGalleryDescription)
        }
    }
}

@main
struct AllWidgetsEntryPoint {
    static func main() {
        if #available(iOS 14.0, *) {
            AllWidgets.main()
        } else {
            preconditionFailure()
        }
    }
}

@available(iOSApplicationExtension 14.0, iOS 14.0, *)
struct AllWidgets: WidgetBundle {
   var body: some Widget {
        Static_Widget()
        Static_AvatarsWidget()
   }
}

#else

@main
class MyApp {
    static func main() {
        preconditionFailure("Not supported")
    }
}

#endif
