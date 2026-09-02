import Foundation
import JerkgramCore
import AsyncDisplayKit
import ContextUI
import UIKit
import Display
import SwiftSignalKit
import TelegramCore
import Postbox
import TelegramPresentationData
import ItemListUI
import AccountContext
import ItemListPeerItem
import BuildConfig

private enum GhostBaseKey {
    // MARK: GhostBase v1.1G PROFILEMETRICS1
    static let profileEnabled = "jerkgram.Profile.Enabled"
    static let showIds = "jerkgram.Profile.ShowIds"
    static let showDCs = "jerkgram.Profile.ShowDCs"
    static let showRegistration = "jerkgram.Profile.ShowRegistration"

    static let readMessages = "jerkgram.GhostMode.ReadMessages"
    static let typingActions = "jerkgram.GhostMode.TypingActions"
    static let recordingActions = "jerkgram.GhostMode.HideRecording"
    static let uploadingActions = "jerkgram.GhostMode.HideUploading"
    static let stickerActivity = "jerkgram.GhostMode.HideStickerActivity"
    static let gameActivity = "jerkgram.GhostMode.HideGameActivity"
    static let emojiActivity = "jerkgram.GhostMode.HideEmojiActivity"
    static let presence = "jerkgram.GhostMode.Presence"
    static let scheduledSend = "jerkgram.GhostMode.ScheduledSend"

    static let saveDeleted = "jerkgram.Messages.SaveDeleted"
    static let showDeleted = "jerkgram.Messages.ShowDeleted"
    static let saveEditHistory = "jerkgram.Messages.SaveEditHistory"
    static let showEditHistory = "jerkgram.Messages.ShowEditHistory"

    // MARK: GhostBase v1.0U appearance settings
    // MARK: GhostBase v1.1C SETTINGSGLASS1
    // MARK: GhostBase v1.1F PROFILEBLURSETTINGS1
    static let glassEnabled = "jerkgram.Glass.Enabled"
    static let profileAvatarBlur = "jerkgram.ProfileBlur.Avatar"
    static let profileAnimatedBackground = "jerkgram.ProfileBlur.Animated"
    static let profileBlurTint = "jerkgram.ProfileBlur.Tint"
    static let profileBlurReduced = "jerkgram.ProfileBlur.Reduced"
    // MARK: GhostBase v1.1R RAM_SETTING1
    // MARK: GhostBase v1.1T DELETED_PORTABLE_SETTINGS1
    static let deletedPortableReplies = "jerkgram.Messages.DeletedPortableReplies"
    static let preserveDeletedMedia = "jerkgram.Messages.PreserveDeletedMedia"
    static let deletedMediaCacheLimit = "jerkgram.Messages.DeletedMediaCacheLimit"
    static let deletedMediaRetentionDays = "jerkgram.Messages.DeletedMediaRetentionDays"
    static let showRamUnderClock = "jerkgram.Appearance.ShowRamUnderClock"
    static let messageSeconds = "jerkgram.Appearance.MessageSeconds"
    static let hideOwnPhone = "jerkgram.Appearance.HideOwnPhone"

    static let protectedEnabled = "jerkgram.ProtectedContent.Enabled"
    static let protectedGalleryShare = "jerkgram.ProtectedContent.GalleryShare"
    static let protectedGallerySave = "jerkgram.ProtectedContent.GallerySave"
    static let protectedGalleryCopy = "jerkgram.ProtectedContent.GalleryCopy"
    static let chatSave = "jerkgram.ProtectedContent.ChatSave"
    static let chatCopy = "jerkgram.ProtectedContent.ChatCopy"
    static let chatForward = "jerkgram.ProtectedContent.ChatForward"
    static let allowScreenshots = "jerkgram.ProtectedContent.AllowScreenshots"
    static let allowScreenRecording = "jerkgram.ProtectedContent.AllowScreenRecording"
    static let oneTimeScreenshots = "jerkgram.ProtectedContent.OneTimeScreenshots"
    static let oneTimeScreenRecording = "jerkgram.ProtectedContent.OneTimeScreenRecording"
    static let oneTimeSave = "jerkgram.ProtectedContent.OneTimeSave"
    static let storySave = "jerkgram.Stories.Save"
    static let localStarsEnabled = "jerkgram.Stars.LocalBalance.Enabled"
    static let localStarsAmount = "jerkgram.Stars.LocalBalance.Amount"
    static let localStarsBaseAmount = "jerkgram.Stars.LocalBalance.BaseAmount"
}

private func ghostBaseBool(_ key: String, defaultValue: Bool) -> Bool {
    if let value = UserDefaults.standard.object(forKey: key) as? Bool {
        return value
    }
    return defaultValue
}

private func ghostBaseString(_ key: String, defaultValue: String) -> String {
    if let value = UserDefaults.standard.object(forKey: key) as? String {
        return value
    }
    return defaultValue
}

// MARK: GhostBase v0.9D Stars input parser
private func ghostBaseIsValidStarsAmountInput(_ text: String) -> Bool {
    var hasSeparator = false

    for (index, ch) in text.enumerated() {
        if ch == "-" || ch == "+" {
            if index != 0 {
                return false
            }
        } else if ch >= "0" && ch <= "9" {
            continue
        } else if ch == "," || ch == "." {
            if hasSeparator {
                return false
            }
            hasSeparator = true
        } else if ch == " " || ch == "\u{00a0}" {
            continue
        } else {
            return false
        }
    }

    return true
}

private func ghostBaseSanitizeStarsAmount(_ text: String) -> String {
    var result = ""
    var hasSeparator = false
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

    for (index, ch) in trimmed.enumerated() {
        if ch == "-" && result.isEmpty && index == 0 {
            result.append(ch)
        } else if ch == "+" && result.isEmpty && index == 0 {
            continue
        } else if ch >= "0" && ch <= "9" {
            result.append(ch)
        } else if (ch == "," || ch == ".") && !hasSeparator {
            result.append(".")
            hasSeparator = true
        } else if ch == " " || ch == "\u{00a0}" {
            continue
        }
    }

    if result == "." || result == "-." {
        return ""
    }

    return result
}
private func ghostBaseStarsInt64(_ text: String) -> Int64 {
    return Int64(ghostBaseSanitizeStarsAmount(text)) ?? 0
}

private func ghostBaseStarsTransactionPreview(baseAmount: String, targetAmount: String) -> String {
    let base = ghostBaseStarsInt64(baseAmount)
    let target = ghostBaseStarsInt64(targetAmount)
    let delta = target - base
    let sign = delta >= 0 ? "+" : ""
    return "Transaction Preview: GhostBase \(sign)\(delta)"
}

// MARK: GhostBase v1.0T send style state
private let ghostBaseSendTextStyleKey =
    "jerkgram.Messages.SendTextStyle"

// MARK: JerkGram v1.1Y BUILD110_SHORT_TOGGLE_TITLES1
private enum GhostBaseSettingsEntryTag:
    Equatable, ItemListItemTag
{
    case sendTextStyle

    func isEqual(to other: ItemListItemTag) -> Bool {
        guard let other = other as? GhostBaseSettingsEntryTag else {
            return false
        }
        return self == other
    }
}

// MARK: GhostBase v1.0T send style menu helpers
// MARK: GhostBase v1.0U styled send text preview
private func ghostBaseSendStyleAttributedText(
    style: String,
    text: String,
    color: UIColor,
    size: CGFloat
) -> NSAttributedString {
    var visibleText = text

    if style == "spoiler" {
        visibleText = text.unicodeScalars.map { scalar in
            CharacterSet.alphanumerics.contains(scalar)
                ? "#"
                : String(scalar)
        }.joined()
    }

    var attributes: [NSAttributedString.Key: Any] = [
        .font: UIFont.systemFont(ofSize: size),
        .foregroundColor: color
    ]

    switch style {
    case "bold":
        attributes[.font] = UIFont.boldSystemFont(ofSize: size)
    case "italic":
        attributes[.font] = UIFont.italicSystemFont(ofSize: size)
    case "monospace":
        attributes[.font] = UIFont.monospacedSystemFont(
            ofSize: size,
            weight: .regular
        )
    case "strikethrough":
        attributes[.strikethroughStyle] =
            NSUnderlineStyle.single.rawValue
    case "underline":
        attributes[.underlineStyle] =
            NSUnderlineStyle.single.rawValue
    default:
        break
    }

    return NSAttributedString(
        string: visibleText,
        attributes: attributes
    )
}

// MARK: Jerkgram v1.2E BUILD116_STYLE_LOCALIZATION1
private func ghostBaseSendTextStyleTitle(
    _ value: String,
    strings: JerkgramStrings
) -> String {
    switch value {
    case "bold":
        return strings.sendStyleBold
    case "italic":
        return strings.sendStyleItalic
    case "monospace":
        return strings.sendStyleMonospace
    case "strikethrough":
        return strings.sendStyleStrikethrough
    case "underline":
        return strings.sendStyleUnderline
    case "spoiler":
        return strings.sendStyleSpoiler
    default:
        return strings.sendStyleNormal
    }
}

// MARK: GhostBase v1.0T send style context source
private final class GhostBaseSendStyleContextSource:
    ContextControllerContentSource
{
    let controller: ViewController
    let navigationController: NavigationController? = nil
    let passthroughTouches: Bool = false

    weak var sourceNode: ASDisplayNode?

    init(
        controller: ViewController,
        sourceNode: ASDisplayNode
    ) {
        self.controller = controller
        self.sourceNode = sourceNode
    }

    // MARK: GhostBase v1.0U correct context source
    func transitionInfo() -> ContextControllerTakeControllerInfo? {
        let sourceNode = self.sourceNode

        return ContextControllerTakeControllerInfo(
            contentAreaInScreenSpace: CGRect(
                origin: CGPoint(),
                size: CGSize(width: 10.0, height: 10.0)
            ),
            sourceNode: { [weak sourceNode] in
                if let sourceNode = sourceNode {
                    return (
                        sourceNode.view,
                        sourceNode.bounds
                    )
                } else {
                    return nil
                }
            }
        )
    }

    func animatedIn() {
    }
}

// MARK: GhostBase v1.0T send style menu items
private func ghostBaseSendStyleMenuItems(
    selected: String,
    strings: JerkgramStrings,
    select: @escaping (String) -> Void
) -> [ContextMenuItem] {
    let styles = [
        ("normal", strings.sendStyleNormal),
        ("bold", strings.sendStyleBold),
        ("italic", strings.sendStyleItalic),
        ("monospace", strings.sendStyleMonospace),
        ("strikethrough", strings.sendStyleStrikethrough),
        ("underline", strings.sendStyleUnderline),
        ("spoiler", strings.sendStyleSpoiler)
    ]

    return styles.map { value, title in
        let prefix = value == selected ? "✓ " : ""
        var displayText = prefix + title
        var entities: [MessageTextEntity] = []

        let menuFont: ContextMenuActionItemFont
        switch value {
        case "bold":
            menuFont = .custom(
                font: UIFont.boldSystemFont(ofSize: 17.0),
                height: nil,
                verticalOffset: nil
            )
        case "italic":
            menuFont = .custom(
                font: UIFont.italicSystemFont(ofSize: 17.0),
                height: nil,
                verticalOffset: nil
            )
        case "monospace":
            menuFont = .custom(
                font: UIFont.monospacedSystemFont(
                    ofSize: 17.0,
                    weight: .regular
                ),
                height: nil,
                verticalOffset: nil
            )
        default:
            menuFont = .regular
        }

        let start = (prefix as NSString).length
        let end = start + (title as NSString).length
        let titleRange = start ..< end

        switch value {
        case "bold":
            entities.append(
                MessageTextEntity(range: titleRange, type: .Bold)
            )
        case "italic":
            entities.append(
                MessageTextEntity(range: titleRange, type: .Italic)
            )
        case "monospace":
            entities.append(
                MessageTextEntity(range: titleRange, type: .Code)
            )
        case "strikethrough":
            entities.append(
                MessageTextEntity(
                    range: titleRange,
                    type: .Strikethrough
                )
            )
        case "underline":
            entities.append(
                MessageTextEntity(range: titleRange, type: .Underline)
            )
        case "spoiler":
            displayText += "  пример"

            let range = (displayText as NSString).range(
                of: "пример",
                options: .backwards
            )

            entities.append(
                MessageTextEntity(
                    range: range.location ..< NSMaxRange(range),
                    type: .Spoiler
                )
            )
        default:
            break
        }

        return .action(
            ContextMenuActionItem(
                text: displayText,
                entities: entities,
                textLayout: .singleLine,
                textFont: menuFont,
                icon: { _ in nil },
                action: { _, dismiss in
                    select(value)
                    dismiss(.default)
                }
            )
        )
    }
}

// MARK: Jerkgram v1.2G BUILD118_ACCOUNT_SETTINGS_SCOPE1
private func jerkgramScopedSettingsKey(accountPeerId: Int64, key: String) -> String {
    return "jerkgram.account.\(accountPeerId).setting.\(key)"
}

private func jerkgramScopedBool(
    accountPeerId: Int64,
    key: String,
    defaultValue: Bool
) -> Bool {
    let scopedKey = jerkgramScopedSettingsKey(accountPeerId: accountPeerId, key: key)
    if let value = UserDefaults.standard.object(forKey: scopedKey) as? Bool {
        return value
    }
    let migrated = ghostBaseBool(key, defaultValue: defaultValue)
    UserDefaults.standard.set(migrated, forKey: scopedKey)
    return migrated
}

private func jerkgramScopedString(
    accountPeerId: Int64,
    key: String,
    defaultValue: String
) -> String {
    let scopedKey = jerkgramScopedSettingsKey(accountPeerId: accountPeerId, key: key)
    if let value = UserDefaults.standard.object(forKey: scopedKey) as? String {
        return value
    }
    let migrated = ghostBaseString(key, defaultValue: defaultValue)
    UserDefaults.standard.set(migrated, forKey: scopedKey)
    return migrated
}

// MARK: Jerkgram v1.2L BUILD123_ACCOUNT_SETTINGS_OWNER1
private enum JerkgramSettingValue: Equatable {
    case bool(Bool)
    case string(String)

    func write(to defaults: UserDefaults, key: String) {
        switch self {
        case let .bool(value): defaults.set(value, forKey: key)
        case let .string(value): defaults.set(value, forKey: key)
        }
    }
}

private enum JerkgramSettingsCommitQueue {
    private static let queue = Queue(name: "JerkgramSettingsCommitQueue", qos: .utility)
    static func enqueue(_ work: @escaping () -> Void) {
        self.queue.async(work)
    }
}

private func jerkgramStateValues(_ state: GhostBaseSettingsState) -> [String: JerkgramSettingValue] {
    return [
        GhostBaseKey.profileEnabled: .bool(state.profileEnabled),
        GhostBaseKey.showIds: .bool(state.showIds),
        GhostBaseKey.showDCs: .bool(state.showDCs),
        GhostBaseKey.showRegistration: .bool(state.showRegistration),
        GhostBaseKey.glassEnabled: .bool(state.glassEnabled),
        GhostBaseKey.profileAvatarBlur: .bool(state.profileAvatarBlur),
        GhostBaseKey.profileAnimatedBackground: .bool(state.profileAnimatedBackground),
        GhostBaseKey.profileBlurTint: .bool(state.profileBlurTint),
        GhostBaseKey.profileBlurReduced: .bool(state.profileBlurReduced),
        GhostBaseKey.readMessages: .bool(state.readMessages),
        GhostBaseKey.typingActions: .bool(state.typingActions),
        GhostBaseKey.recordingActions: .bool(state.recordingActions),
        GhostBaseKey.uploadingActions: .bool(state.uploadingActions),
        GhostBaseKey.stickerActivity: .bool(state.stickerActivity),
        GhostBaseKey.gameActivity: .bool(state.gameActivity),
        GhostBaseKey.emojiActivity: .bool(state.emojiActivity),
        GhostBaseKey.presence: .bool(state.presence),
        GhostBaseKey.scheduledSend: .bool(state.scheduledSend),
        GhostBaseKey.saveDeleted: .bool(state.saveDeleted),
        GhostBaseKey.showDeleted: .bool(state.showDeleted),
        GhostBaseKey.saveEditHistory: .bool(state.saveEditHistory),
        GhostBaseKey.showEditHistory: .bool(state.showEditHistory),
        ghostBaseSendTextStyleKey: .string(state.sendTextStyle),
        GhostBaseKey.deletedPortableReplies: .bool(state.deletedPortableReplies),
        GhostBaseKey.preserveDeletedMedia: .bool(state.preserveDeletedMedia),
        GhostBaseKey.showRamUnderClock: .bool(state.showRamUnderClock),
        GhostBaseKey.messageSeconds: .bool(state.messageSeconds),
        GhostBaseKey.hideOwnPhone: .bool(state.hideOwnPhone),
        GhostBaseKey.protectedEnabled: .bool(state.protectedEnabled),
        GhostBaseKey.protectedGalleryShare: .bool(state.protectedGalleryShare),
        GhostBaseKey.protectedGallerySave: .bool(state.protectedGallerySave),
        GhostBaseKey.protectedGalleryCopy: .bool(state.protectedGalleryCopy),
        GhostBaseKey.chatSave: .bool(state.chatSave),
        GhostBaseKey.chatCopy: .bool(state.chatCopy),
        GhostBaseKey.chatForward: .bool(state.chatForward),
        GhostBaseKey.allowScreenshots: .bool(state.allowScreenshots),
        GhostBaseKey.allowScreenRecording: .bool(state.allowScreenRecording),
        GhostBaseKey.oneTimeScreenshots: .bool(state.oneTimeScreenshots),
        GhostBaseKey.oneTimeScreenRecording: .bool(state.oneTimeScreenRecording),
        GhostBaseKey.oneTimeSave: .bool(state.oneTimeSave),
        GhostBaseKey.storySave: .bool(state.storySave),
        GhostBaseKey.localStarsEnabled: .bool(state.localStarsEnabled),
        GhostBaseKey.localStarsAmount: .string(state.localStarsAmount),
        GhostBaseKey.localStarsBaseAmount: .string(state.localStarsBaseAmount)
    ]
}

private func jerkgramPersistChangedSettings(
    accountPeerId: Int64,
    previous: GhostBaseSettingsState?,
    current: GhostBaseSettingsState
) {
    let oldValues = previous.map(jerkgramStateValues) ?? [:]
    let newValues = jerkgramStateValues(current)
    let changes = newValues.filter { oldValues[$0.key] != $0.value }
    guard !changes.isEmpty else { return }

    // MARK: Jerkgram v1.2M BUILD124_SENSITIVE_SETTINGS_SYNC1
    // These values are consumed synchronously outside Settings immediately
    // before user-visible side effects. Leaving them behind the utility queue
    // creates a real stale-state window: Scheduled Send can remain active after
    // OFF, and protected one-time media can be replaced with expired content
    // immediately after One-Time Save was switched ON.
    //
    // UserDefaults.set updates the in-process defaults domain; deliberately
    // avoid any forced defaults/filesystem synchronization here.
    let jerkgramSynchronousRuntimeSettingKeys: Set<String> = [
        GhostBaseKey.scheduledSend,
        GhostBaseKey.protectedEnabled,
        GhostBaseKey.oneTimeSave,
    ]
    let defaults = UserDefaults.standard
    for key in jerkgramSynchronousRuntimeSettingKeys {
        guard let value = changes[key] else { continue }
        value.write(
            to: defaults,
            key: jerkgramScopedSettingsKey(accountPeerId: accountPeerId, key: key)
        )
        // Legacy Telegram/Jerkgram runtime owners consume the active-account
        // projection directly from UserDefaults.standard.
        value.write(to: defaults, key: key)
        if key == GhostBaseKey.scheduledSend {
            let sharedDefaults = UserDefaults(suiteName: "group.ph.telegra.Telegraph") ?? defaults
            value.write(to: sharedDefaults, key: key)
        }
    }

    let deferredChanges = changes.filter {
        !jerkgramSynchronousRuntimeSettingKeys.contains($0.key)
    }
    guard !deferredChanges.isEmpty else { return }

    JerkgramSettingsCommitQueue.enqueue {
        let defaults = UserDefaults.standard
        for (key, value) in deferredChanges {
            value.write(to: defaults, key: jerkgramScopedSettingsKey(accountPeerId: accountPeerId, key: key))
            // Non-critical compatibility projections stay off the caller thread.
            value.write(to: defaults, key: key)
        }
    }
}

private func jerkgramProjectActiveSettings(accountPeerId: Int64, state: GhostBaseSettingsState) {
    jerkgramPersistChangedSettings(accountPeerId: accountPeerId, previous: nil, current: state)
}

// Regression sentinel: bulk defaults enumeration must never return here.


struct GhostBaseSettingsState: Equatable {
    var profileEnabled: Bool
    var showIds: Bool
    var showDCs: Bool
    var showRegistration: Bool
    var glassEnabled: Bool
    var profileAvatarBlur: Bool
    var profileAnimatedBackground: Bool
    var profileBlurTint: Bool
    var profileBlurReduced: Bool

    var readMessages: Bool
    var typingActions: Bool
    var recordingActions: Bool
    var uploadingActions: Bool
    var stickerActivity: Bool
    var gameActivity: Bool
    var emojiActivity: Bool
    var presence: Bool
    var scheduledSend: Bool

    var saveDeleted: Bool
    var showDeleted: Bool
    var saveEditHistory: Bool
    var showEditHistory: Bool
    var sendTextStyle: String

    var deletedPortableReplies: Bool
    var preserveDeletedMedia: Bool
    var showRamUnderClock: Bool
    var messageSeconds: Bool
    var hideOwnPhone: Bool

    var protectedEnabled: Bool
    var protectedGalleryShare: Bool
    var protectedGallerySave: Bool
    var protectedGalleryCopy: Bool

    var chatSave: Bool
    var chatCopy: Bool
    var chatForward: Bool
    var allowScreenshots: Bool
    var allowScreenRecording: Bool
    var oneTimeScreenshots: Bool
    var oneTimeScreenRecording: Bool
    var oneTimeSave: Bool
    var storySave: Bool
    var localStarsEnabled: Bool
    var localStarsAmount: String
    var localStarsBaseAmount: String
    static func load(accountPeerId: Int64) -> GhostBaseSettingsState {
        return GhostBaseSettingsState(
            profileEnabled: jerkgramScopedBool(accountPeerId: accountPeerId, key: GhostBaseKey.profileEnabled, defaultValue: true),
            showIds: jerkgramScopedBool(accountPeerId: accountPeerId, key: GhostBaseKey.showIds, defaultValue: true),
            showDCs: jerkgramScopedBool(accountPeerId: accountPeerId, key: GhostBaseKey.showDCs, defaultValue: true),
            showRegistration: jerkgramScopedBool(accountPeerId: accountPeerId, key: GhostBaseKey.showRegistration, defaultValue: true),
            glassEnabled: jerkgramScopedBool(accountPeerId: accountPeerId, key: GhostBaseKey.glassEnabled, defaultValue: true),
            profileAvatarBlur: jerkgramScopedBool(accountPeerId: accountPeerId, key: GhostBaseKey.profileAvatarBlur, defaultValue: true),
            profileAnimatedBackground: jerkgramScopedBool(accountPeerId: accountPeerId, key: GhostBaseKey.profileAnimatedBackground, defaultValue: true),
            profileBlurTint: jerkgramScopedBool(accountPeerId: accountPeerId, key: GhostBaseKey.profileBlurTint, defaultValue: true),
            profileBlurReduced: jerkgramScopedBool(accountPeerId: accountPeerId, key: GhostBaseKey.profileBlurReduced, defaultValue: false),
            readMessages: jerkgramScopedBool(accountPeerId: accountPeerId, key: GhostBaseKey.readMessages, defaultValue: false),
            typingActions: jerkgramScopedBool(accountPeerId: accountPeerId, key: GhostBaseKey.typingActions, defaultValue: false),
            recordingActions: jerkgramScopedBool(accountPeerId: accountPeerId, key: GhostBaseKey.recordingActions, defaultValue: false),
            uploadingActions: jerkgramScopedBool(accountPeerId: accountPeerId, key: GhostBaseKey.uploadingActions, defaultValue: false),
            stickerActivity: jerkgramScopedBool(accountPeerId: accountPeerId, key: GhostBaseKey.stickerActivity, defaultValue: false),
            gameActivity: jerkgramScopedBool(accountPeerId: accountPeerId, key: GhostBaseKey.gameActivity, defaultValue: false),
            emojiActivity: jerkgramScopedBool(accountPeerId: accountPeerId, key: GhostBaseKey.emojiActivity, defaultValue: false),
            presence: jerkgramScopedBool(accountPeerId: accountPeerId, key: GhostBaseKey.presence, defaultValue: false),
            scheduledSend: jerkgramScopedBool(accountPeerId: accountPeerId, key: GhostBaseKey.scheduledSend, defaultValue: false),
            saveDeleted: jerkgramScopedBool(accountPeerId: accountPeerId, key: GhostBaseKey.saveDeleted, defaultValue: true),
            showDeleted: jerkgramScopedBool(accountPeerId: accountPeerId, key: GhostBaseKey.showDeleted, defaultValue: true),
            saveEditHistory: jerkgramScopedBool(accountPeerId: accountPeerId, key: GhostBaseKey.saveEditHistory, defaultValue: true),
            showEditHistory: jerkgramScopedBool(accountPeerId: accountPeerId, key: GhostBaseKey.showEditHistory, defaultValue: true),
            sendTextStyle: jerkgramScopedString(accountPeerId: accountPeerId, key: 
                ghostBaseSendTextStyleKey,
                defaultValue: "normal"
            ),
            deletedPortableReplies: jerkgramScopedBool(accountPeerId: accountPeerId, key: 

                GhostBaseKey.deletedPortableReplies,

                defaultValue: true

            ),

            preserveDeletedMedia: jerkgramScopedBool(accountPeerId: accountPeerId, key: 

                GhostBaseKey.preserveDeletedMedia,

                defaultValue: true

            ),

            showRamUnderClock: jerkgramScopedBool(accountPeerId: accountPeerId, key: 

                GhostBaseKey.showRamUnderClock,

                defaultValue: false

            ),

            messageSeconds: jerkgramScopedBool(accountPeerId: accountPeerId, key: 
                GhostBaseKey.messageSeconds,
                defaultValue: false
            ),
            hideOwnPhone: jerkgramScopedBool(accountPeerId: accountPeerId, key: 
                GhostBaseKey.hideOwnPhone,
                defaultValue: false
            ),
            protectedEnabled: jerkgramScopedBool(accountPeerId: accountPeerId, key: GhostBaseKey.protectedEnabled, defaultValue: true),
            protectedGalleryShare: jerkgramScopedBool(accountPeerId: accountPeerId, key: GhostBaseKey.protectedGalleryShare, defaultValue: true),
            protectedGallerySave: jerkgramScopedBool(accountPeerId: accountPeerId, key: GhostBaseKey.protectedGallerySave, defaultValue: true),
            protectedGalleryCopy: jerkgramScopedBool(accountPeerId: accountPeerId, key: GhostBaseKey.protectedGalleryCopy, defaultValue: true),
            chatSave: jerkgramScopedBool(accountPeerId: accountPeerId, key: GhostBaseKey.chatSave, defaultValue: true),
            chatCopy: jerkgramScopedBool(accountPeerId: accountPeerId, key: GhostBaseKey.chatCopy, defaultValue: true),
            chatForward: jerkgramScopedBool(accountPeerId: accountPeerId, key: GhostBaseKey.chatForward, defaultValue: true),
            allowScreenshots: jerkgramScopedBool(accountPeerId: accountPeerId, key: GhostBaseKey.allowScreenshots, defaultValue: true),
            allowScreenRecording: jerkgramScopedBool(accountPeerId: accountPeerId, key: GhostBaseKey.allowScreenRecording, defaultValue: true),
            oneTimeScreenshots: jerkgramScopedBool(accountPeerId: accountPeerId, key: GhostBaseKey.oneTimeScreenshots, defaultValue: false),
            oneTimeScreenRecording: jerkgramScopedBool(accountPeerId: accountPeerId, key: GhostBaseKey.oneTimeScreenRecording, defaultValue: false),
            oneTimeSave: jerkgramScopedBool(accountPeerId: accountPeerId, key: GhostBaseKey.oneTimeSave, defaultValue: false),
            storySave: jerkgramScopedBool(accountPeerId: accountPeerId, key: GhostBaseKey.storySave, defaultValue: false),
            localStarsEnabled: jerkgramScopedBool(accountPeerId: accountPeerId, key: GhostBaseKey.localStarsEnabled, defaultValue: false),
            localStarsAmount: jerkgramScopedString(accountPeerId: accountPeerId, key: GhostBaseKey.localStarsAmount, defaultValue: "0"),
            localStarsBaseAmount: jerkgramScopedString(accountPeerId: accountPeerId, key: GhostBaseKey.localStarsBaseAmount, defaultValue: "0")
        )
    }

    func save(accountPeerId: Int64) {
        jerkgramPersistChangedSettings(accountPeerId: accountPeerId, previous: nil, current: self)
    }
}


// MARK: GhostBase v1.0R Settings Split
// MARK: Jerkgram v1.2C BUILD114_SETTINGS_ICONS1
private func jerkgramSettingsMenuIcon(
    _ name: String
) -> UIImage? {
    let background: UInt32

    switch name {
    case "Jerkgram/Settings/Airplane":
        background = 0x53606A
    case "Chat/Context Menu/Eye":
        background = 0x4B5064
    case "Chat/Context Menu/MessageBubble":
        background = 0x4B6F83
    case "Premium/CopyProtection/NoForward":
        background = 0x87452F
    case "Item List/Icons/Stories":
        background = 0x6A5C78
    case "Chat/Context Menu/ApplyTheme":
        background = 0x676C43
    case "Chat/Context Menu/FormatCode":
        background = 0x8A6138
    case "Chat/Context Menu/Info":
        background = 0x4B4F54

    default:
        return nil
    }

    return renderSettingsIcon(
        name: name,
        scaleFactor: 1.0,
        backgroundColors: [
            UIColor(
                rgb: background
            )
        ]
    )
}

private enum GhostBaseSettingsPage: Equatable {
    case root
    case dataAndBackup
    case stars
    case home
    case ghostMode
    case messages
    case protectedContent
    case mediaStories
    case appearance
    case debugResearch
    case about

    var title: String {
        switch self {
        case .root:
            return "Jerkgram"
        case .dataAndBackup:
            return "Data and Backup"
        case .stars:
            return "Stars"
        case .home:
            return "Basic Functions"
        case .ghostMode:
            return "Ghost Mode"
        case .messages:
            return "Messages"
        case .protectedContent:
            return "Protected Content"
        case .mediaStories:
            return "Media & Stories"
        case .appearance:
            return "Appearance"
        case .debugResearch:
            return "Debug / Research"
        case .about:
            return "About"
        }
    }


    func localizedTitle(_ strings: JerkgramStrings) -> String {
        switch self {
        case .root:
            return strings.settingsTitle
        case .dataAndBackup:
            return strings.dataAndBackup
        case .stars:
            return strings.starsBalance
        case .home:
            return strings.basicFunctions
        case .ghostMode:
            return strings.ghostMode
        case .messages:
            return strings.messages
        case .protectedContent:
            return strings.protectedContent
        case .mediaStories:
            return strings.mediaAndStories
        case .appearance:
            return strings.appearance
        case .debugResearch:
            return strings.debugResearch
        case .about:
            return strings.about
        }
    }
}

// MARK: GhostBase v1.0T send style row
private final class GhostBaseSettingsArguments {
    let context: AccountContext
    let openAboutChannel: (EnginePeer) -> Void
    let runResearchAction: (String) -> Void
    let updateBool: (String, Bool) -> Void
    let openPage: (GhostBaseSettingsPage) -> Void
    let openSendTextStyle: () -> Void

    init(
        context: AccountContext,
        openAboutChannel: @escaping (EnginePeer) -> Void,
        runResearchAction: @escaping (String) -> Void,
        updateBool: @escaping (String, Bool) -> Void,
        openPage: @escaping (GhostBaseSettingsPage) -> Void,
        openSendTextStyle: @escaping () -> Void
    ) {
        self.context = context
        self.openAboutChannel = openAboutChannel
        self.runResearchAction = runResearchAction
        self.updateBool = updateBool
        self.openPage = openPage
        self.openSendTextStyle = openSendTextStyle
    }
}

private enum GhostBaseSettingsSection: Int32 {
    case profileMetrics
    case ghostMode
    case protectedContent
    case stars
    case debug
    case footer
}

// MARK: Jerkgram v1.2L BUILD123_SETTINGS_SYSTEM1
// Shared visual contract used by every internal Jerkgram destination.
private func JerkgramSettingsSectionHeaderItem(
    presentationData: ItemListPresentationData,
    text: String,
    sectionId: ItemListSectionId
) -> ListViewItem {
    return ItemListSectionHeaderItem(
        presentationData: presentationData,
        text: text.uppercased(),
        sectionId: sectionId
    )
}

private func JerkgramSettingsStatusItem(
    presentationData: ItemListPresentationData,
    text: String,
    sectionId: ItemListSectionId
) -> ListViewItem {
    return ItemListDisclosureItem(
        presentationData: presentationData,
        systemStyle: .glass,
        title: text,
        label: "",
        labelStyle: .text,
        sectionId: sectionId,
        style: .blocks,
        disclosureStyle: .none,
        action: nil
    )
}



private let jerkgramTelemetryEnabledKey = "jerkgram.telemetry.anonymous.enabled"
private func jerkgramTelemetryEnabled() -> Bool {
    let defaults = UserDefaults.standard
    return defaults.object(forKey: jerkgramTelemetryEnabledKey) == nil ? true : defaults.bool(forKey: jerkgramTelemetryEnabledKey)
}
private func jerkgramSetTelemetryEnabled(_ enabled: Bool) {
    UserDefaults.standard.set(enabled, forKey: jerkgramTelemetryEnabledKey)
    NotificationCenter.default.post(name: Notification.Name("JerkgramTelemetryPreferenceChanged"), object: nil)
}

private enum GhostBaseSettingsEntry: ItemListNodeEntry {
    case aboutValue(Int32, Int32, String, String)
    case telemetryToggle(Int32, Int32, String, Bool)
    case header(Int32, String)
    case toggle(Int32, Int32, String, String, Bool)
    case input(Int32, Int32, String, String, String)
    case disclosure(Int32, Int32, String, String, GhostBaseSettingsPage)
    case valueDisclosure(Int32, Int32, String, String, String?, GhostBaseSettingsPage)
    case selector(Int32, Int32, String, String)
    case stylePreview(Int32, Int32, String)
    case aboutChannel(Int32, Int32, String, EnginePeer?, String, Bool)
    case researchAction(Int32, Int32, String, String)
    case researchInfo(Int32, Int32, String)
    case info(Int32, String)

    var section: ItemListSectionId {
        switch self {
        case let .header(section, _):
            return section
        case let .aboutValue(section, _, _, _):
            return section
        case let .telemetryToggle(section, _, _, _):
            return section
        case let .toggle(section, _, _, _, _):
            return section
        case let .input(section, _, _, _, _):
            return section
        case let .disclosure(section, _, _, _, _):
            return section
        case let .valueDisclosure(section, _, _, _, _, _):
            return section
        case let .selector(section, _, _, _):
            return section
        case let .stylePreview(section, _, _):
            return section
        case let .aboutChannel(section, _, _, _, _, _):
            return section
        case let .researchAction(section, _, _, _):
            return section
        case let .researchInfo(section, _, _):
            return section
        case let .info(section, _):
            return section
        }
    }

    var stableId: Int32 {
        switch self {
        case let .header(section, _):
            return section * 1000
        case let .aboutValue(section, index, _, _):
            return section * 1000 + index
        case let .telemetryToggle(section, index, _, _):
            return section * 1000 + index
        case let .toggle(section, index, _, _, _):
            return section * 1000 + index
        case let .input(section, index, _, _, _):
            return section * 1000 + index
        case let .disclosure(section, index, _, _, _):
            return section * 1000 + index
        case let .valueDisclosure(section, index, _, _, _, _):
            return section * 1000 + index
        case let .selector(section, index, _, _):
            return section * 1000 + index
        case let .stylePreview(section, index, _):
            return section * 1000 + index
        case let .aboutChannel(section, index, _, _, _, _):
            return section * 1000 + index
        case let .researchAction(section, index, _, _):
            return section * 1000 + index
        case let .researchInfo(section, index, _):
            return section * 1000 + index
        case let .info(section, _):
            return section * 1000 + 999
        }
    }

    static func ==(lhs: GhostBaseSettingsEntry, rhs: GhostBaseSettingsEntry) -> Bool {
        switch lhs {
        case let .header(ls, lt):
            if case let .header(rs, rt) = rhs {
                return ls == rs && lt == rt
            }
            return false
        case let .aboutValue(ls, li, lt, lv):
            if case let .aboutValue(rs, ri, rt, rv) = rhs {
                return ls == rs && li == ri && lt == rt && lv == rv
            }
            return false
        case let .telemetryToggle(ls, li, lt, lv):
            if case let .telemetryToggle(rs, ri, rt, rv) = rhs {
                return ls == rs && li == ri && lt == rt && lv == rv
            }
            return false
        case let .toggle(ls, li, lk, lt, lv):
            if case let .toggle(rs, ri, rk, rt, rv) = rhs {
                return ls == rs && li == ri && lk == rk && lt == rt && lv == rv
            }
            return false
        case let .input(ls, li, lk, lt, lv):
            if case let .input(rs, ri, rk, rt, rv) = rhs {
                return ls == rs && li == ri && lk == rk && lt == rt && lv == rv
            } else {
                return false
            }
        case let .disclosure(ls, li, lt, lIcon, lPage):
            if case let .disclosure(rs, ri, rt, rIcon, rPage) = rhs {
                return ls == rs
                    && li == ri
                    && lt == rt
                    && lIcon == rIcon
                    && lPage.title == rPage.title
            }
            return false
        case let .selector(ls, li, lt, lv):
            if case let .selector(rs, ri, rt, rv) = rhs {
                return ls == rs && li == ri
                    && lt == rt && lv == rv
            }
            return false
        case let .stylePreview(ls, li, lv):
            if case let .stylePreview(rs, ri, rv) = rhs {
                return ls == rs && li == ri && lv == rv
            }
            return false
        case let .aboutChannel(ls, li, lt, lp, lv, ll):
            if case let .aboutChannel(rs, ri, rt, rp, rv, rl) = rhs {
                return ls == rs && li == ri && lt == rt
                    && lp == rp && lv == rv && ll == rl
            }
            return false
        case let .researchAction(ls, li, lt, la):
            if case let .researchAction(rs, ri, rt, ra) = rhs {
                return ls == rs && li == ri && lt == rt && la == ra
            }
            return false
        case let .researchInfo(ls, li, lt):
            if case let .researchInfo(rs, ri, rt) = rhs {
                return ls == rs && li == ri && lt == rt
            }
            return false
        case let .valueDisclosure(ls, li, lt, lv, lIcon, lPage):
            if case let .valueDisclosure(rs, ri, rt, rv, rIcon, rPage) = rhs {
                return ls == rs && li == ri && lt == rt && lv == rv
                    && lIcon == rIcon && lPage.title == rPage.title
            }
            return false
        case let .info(ls, lt):
            if case let .info(rs, rt) = rhs {
                return ls == rs && lt == rt
            }
            return false
        }
    }

    static func <(lhs: GhostBaseSettingsEntry, rhs: GhostBaseSettingsEntry) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(presentationData: ItemListPresentationData, arguments: Any) -> ListViewItem {
        let arguments = arguments as! GhostBaseSettingsArguments

        switch self {
        case let .header(_, text):
            return JerkgramSettingsSectionHeaderItem(presentationData: presentationData, text: text, sectionId: self.section)

        case let .input(_, _, _, title, text):
            return ItemListSingleLineInputItem(
                presentationData: presentationData,
                title: NSAttributedString(string: title, textColor: presentationData.theme.list.itemPrimaryTextColor),
                text: text,
                placeholder: "0",
                type: .regular(capitalization: false, autocorrection: false),
                returnKeyType: .done,
                alignment: .right,
                spacing: 16.0,
                clearType: .onFocus,
                maxLength: 20,
                selectAllOnFocus: true,
                sectionId: self.section,
                // BUILD122: legacy input is not a persistence owner. The
                // dedicated Stars editor keeps a local draft and commits on Save.
                textUpdated: { _ in },
                shouldUpdateText: { updatedText in
                    return ghostBaseIsValidStarsAmountInput(updatedText)
                },
                action: {}
            )

        case let .aboutValue(_, _, title, value):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: title,
                label: value,
                labelStyle: .text,
                sectionId: self.section,
                style: .blocks,
                disclosureStyle: .none,
                action: nil
            )

        case let .telemetryToggle(_, _, title, value):
            return ItemListSwitchItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: title,
                value: value,
                sectionId: self.section,
                style: .blocks,
                updated: { enabled in
                    jerkgramSetTelemetryEnabled(enabled)
                }
            )

        case let .toggle(_, _, key, title, value):
            return ItemListSwitchItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: title,
                value: value,
                sectionId: self.section,
                style: .blocks,
                updated: { updatedValue in
                    arguments.updateBool(key, updatedValue)
                }
            )

        case let .disclosure(_, _, title, iconName, page):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                icon: jerkgramSettingsMenuIcon(iconName),
                title: title,
                label: "",
                labelStyle: .text,
                sectionId: self.section,
                style: .blocks,
                disclosureStyle: .arrow,
                action: {
                    arguments.openPage(page)
                }
            )

        case let .selector(_, _, title, value):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: title,
                label: "",
                attributedLabel: ghostBaseSendStyleAttributedText(
                    style: value,
                    text: ghostBaseSendTextStyleTitle(
                    value,
                    strings: presentationData.strings.jerkgram
                ),
                    color: presentationData.theme.list.itemSecondaryTextColor,
                    size: 15.0
                ),
                labelStyle: .text,
                sectionId: self.section,
                style: .blocks,
                disclosureStyle: .arrow,
                action: {
                    arguments.openSendTextStyle()
                },
                tag: GhostBaseSettingsEntryTag.sendTextStyle
            )

        case let .stylePreview(_, _, value):
            let line = NSMutableAttributedString(
                string: presentationData.strings.jerkgram.sendStyleExamplePrefix,
                attributes: [
                    .font: UIFont.systemFont(ofSize: 15.0),
                    .foregroundColor:
                        presentationData.theme.list.itemPrimaryTextColor
                ]
            )

            line.append(
                ghostBaseSendStyleAttributedText(
                    style: value,
                    text: presentationData.strings.jerkgram.sendStyleExampleBody,
                    color: presentationData.theme.list.itemPrimaryTextColor,
                    size: 15.0
                )
            )

            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: "",
                attributedTitle: line,
                label: "",
                labelStyle: .text,
                sectionId: self.section,
                style: .blocks,
                disclosureStyle: .none,
                action: nil
            )

        // MARK: Jerkgram v1.2F BUILD117_ABOUT_CHANNEL_CARD1
        case let .aboutChannel(_, _, title, peer, preview, _):
            if let peer {
                return ItemListPeerItem(
                    presentationData: presentationData,
                    systemStyle: .glass,
                    dateTimeFormat: PresentationDateTimeFormat(),
                    nameDisplayOrder: .firstLast,
                    context: arguments.context,
                    peer: peer,
                    height: .peerList,
                    aliasHandling: .standard,
                    nameStyle: .plain,
                    presence: nil,
                    text: .text(preview, .secondary),
                    label: .none,
                    editing: ItemListPeerItemEditing(
                        editable: false,
                        editing: false,
                        revealed: false
                    ),
                    switchValue: nil,
                    enabled: true,
                    selectable: true,
                    sectionId: self.section,
                    action: {
                        arguments.openAboutChannel(peer)
                    },
                    setPeerIdWithRevealedOptions: { _, _ in },
                    removePeer: { _ in }
                )
            } else {
                return ItemListDisclosureItem(
                    presentationData: presentationData,
                    systemStyle: .glass,
                    title: title,
                    label: preview,
                    labelStyle: .text,
                    sectionId: self.section,
                    style: .blocks,
                    disclosureStyle: .none,
                    action: nil
                )
            }

        case let .researchAction(_, _, title, actionId):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: title,
                label: "",
                labelStyle: .text,
                sectionId: self.section,
                style: .blocks,
                disclosureStyle: actionId.hasPrefix("https://") ? .arrow : .none,
                action: {
                    arguments.runResearchAction(actionId)
                }
            )

        case let .researchInfo(_, _, text):
            return JerkgramSettingsStatusItem(presentationData: presentationData, text: text, sectionId: self.section)

        // MARK: Jerkgram v1.2H BUILD119_HYBRID_UI1
        case let .valueDisclosure(_, _, title, value, iconName, page):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                icon: iconName.flatMap { UIImage(bundleImageName: $0) },
                title: title,
                label: value,
                labelStyle: .text,
                sectionId: self.section,
                style: .blocks,
                disclosureStyle: .arrow,
                action: {
                    arguments.openPage(page)
                }
            )

        case let .info(_, text):
            return JerkgramSettingsStatusItem(presentationData: presentationData, text: text, sectionId: self.section)
        }
    }
}


// MARK: GhostBase v1.0Y Hidden Gifts no-spend probe
// MARK: GhostBase v1.0Z Hidden Gifts direct catalog deep probe

private let ghostBaseHiddenGiftItems: [(String, Int64)] = [
    ("New Year Bear", 5956217000635139069),
    ("Christmas Tree", 5922558454332916696),
    ("Valentine Bear", 5800655655995968830),
    ("March 8 Bear", 5866352046986232958),
    ("Valentine Card", 5801108895304779062),
    ("Leprechaun Bear", 5893356958802511476),
    ("April 1 Bear", 5935895822435615975),
    ("Easter Bear", 5969796561943660080),
    ("Builder Bear", 6026193266406327981)
]

private let ghostBaseHiddenGiftsPrefix =
    "jerkgram.Research.HiddenGifts."

private struct GhostBaseHiddenGiftFormProbeResult {
    let total: Int64?
    let text: String
}

private func ghostBaseHiddenGiftCheckText(
    _ result: CanSendGiftResult
) -> String {
    switch result {
    case .available:
        return "available"
    case let .unavailable(text, _):
        return text.isEmpty
            ? "unavailable"
            : "unavailable: \(text)"
    case .failed:
        return "failed"
    }
}

private func ghostBaseHiddenGiftPaymentErrorText(
    _ error: BotPaymentFormRequestError
) -> String {
    switch error {
    case .generic:
        return "generic"
    case .alreadyActive:
        return "alreadyActive"
    case .noPaymentNeeded:
        return "noPaymentNeeded"
    case .disallowedStarGift:
        return "disallowedStarGift"
    case let .starGiftResellTooEarly(timeout):
        return "starGiftResellTooEarly(\(timeout))"
    case .starGiftUserLimit:
        return "starGiftUserLimit"
    }
}

private func ghostBaseHiddenGiftDateText(
    _ value: Int32?
) -> String {
    guard let value else {
        return "nil"
    }

    let date = Date(timeIntervalSince1970: TimeInterval(value))
    return "\(value) / \(ISO8601DateFormatter().string(from: date))"
}

private func ghostBaseHiddenGiftCatalogText(
    index: Int,
    gift: StarGift.Gift
) -> String {
    var flags: [String] = []

    if gift.flags.contains(.isBirthdayGift) {
        flags.append("birthday")
    }
    if gift.flags.contains(.requiresPremium) {
        flags.append("requiresPremium")
    }
    if gift.flags.contains(.peerColorAvailable) {
        flags.append("peerColorAvailable")
    }
    if gift.flags.contains(.isAuction) {
        flags.append("auction")
    }

    let availability: String
    if let value = gift.availability {
        availability = """
        remains=\(value.remains)
        total=\(value.total)
        resale=\(value.resale)
        minResaleStars=\(value.minResaleStars.map(String.init) ?? "nil")
        """
    } else {
        availability = "nil"
    }

    let soldOut: String
    if let value = gift.soldOut {
        soldOut = """
        firstSale=\(ghostBaseHiddenGiftDateText(value.firstSale))
        lastSale=\(ghostBaseHiddenGiftDateText(value.lastSale))
        """
    } else {
        soldOut = "nil"
    }

    let perUserLimit: String
    if let value = gift.perUserLimit {
        perUserLimit =
            "remains=\(value.remains), total=\(value.total)"
    } else {
        perUserLimit = "nil"
    }

    let background: String
    if let value = gift.background {
        background = """
        center=\(value.centerColor)
        edge=\(value.edgeColor)
        text=\(value.textColor)
        """
    } else {
        background = "nil"
    }

    return """
    catalog: present
    catalogIndex: \(index)
    title: \(gift.title ?? "nil")
    fileId: \(gift.file.fileId.id)
    fileNamespace: \(gift.file.fileId.namespace)
    price: \(gift.price)
    convertStars: \(gift.convertStars)
    flags: \(flags.isEmpty ? "none" : flags.joined(separator: ","))
    availability:
    \(availability)
    soldOut:
    \(soldOut)
    upgradeStars: \(gift.upgradeStars.map(String.init) ?? "nil")
    upgradeVariantsCount: \(gift.upgradeVariantsCount.map(String.init) ?? "nil")
    releasedBy: \(gift.releasedBy.map { String(describing: $0) } ?? "nil")
    perUserLimit: \(perUserLimit)
    lockedUntilDate: \(ghostBaseHiddenGiftDateText(gift.lockedUntilDate))
    auctionSlug: \(gift.auctionSlug ?? "nil")
    auctionGiftsPerRound: \(gift.auctionGiftsPerRound.map(String.init) ?? "nil")
    auctionStartDate: \(ghostBaseHiddenGiftDateText(gift.auctionStartDate))
    background:
    \(background)
    """
}

private func ghostBaseHiddenGiftsReport() -> String {
    let defaults = UserDefaults.standard

    let status = defaults.string(
        forKey: ghostBaseHiddenGiftsPrefix + "Status"
    ) ?? "not tested"

    let target = defaults.string(
        forKey: ghostBaseHiddenGiftsPrefix + "Target"
    ) ?? "none"

    let updated = defaults.string(
        forKey: ghostBaseHiddenGiftsPrefix + "Updated"
    ) ?? "none"

    let report = defaults.string(
        forKey: ghostBaseHiddenGiftsPrefix + "Report"
    ) ?? "Результатов пока нет."

    return """
    Status: \(status)
    Target: \(target)
    Updated: \(updated)

    \(report)
    """
}

// MARK: GhostBase v1.0ZA Hidden Gifts real send

private struct GhostBaseHiddenGiftSendState {
    var giftName: String?
    var giftId: Int64?
    var targetPeerId: EnginePeer.Id?
    var targetLabel: String?
    var hideName: Bool = false
    var firstConfirmed: Bool = false
    var isSending: Bool = false
    var status: String = "Выберите подарок и получателя."
}

// MARK: GhostBase v1.0ZA Hidden Gifts self and anonymous send
private var ghostBaseHiddenGiftSendState =
    GhostBaseHiddenGiftSendState()

private func ghostBaseHiddenGiftSendSummary() -> String {
    let state = ghostBaseHiddenGiftSendState

    let gift: String
    if let giftName = state.giftName,
       let giftId = state.giftId {
        gift = "\(giftName)\nID: \(giftId)"
    } else {
        gift = "не выбран"
    }

    let target =
        state.targetLabel
        ?? "не выбран"

    let anonymity =
        state.hideName
        ? "имя отправителя скрыто"
        : "имя отправителя открыто"

    let confirmation: String
    if state.isSending {
        confirmation = "выполняется платёжный запрос"
    } else if state.firstConfirmed {
        confirmation =
            "первое подтверждение принято; требуется списание"
    } else {
        confirmation = "не подтверждено"
    }

    return """
    Подарок:
    \(gift)

    Получатель:
    \(target)

    Цена:
    строго 50 XTR

    Отправитель:
    \(anonymity)

    Подтверждение:
    \(confirmation)

    Статус:
    \(state.status)
    """
}

private func ghostBaseHiddenGiftSendErrorText(
    _ error: SendBotPaymentFormError
) -> String {
    switch error {
    case .generic:
        return "generic"
    case .precheckoutFailed:
        return "precheckoutFailed"
    case .paymentFailed:
        return "paymentFailed"
    case .alreadyPaid:
        return "alreadyPaid"
    case .starGiftOutOfStock:
        return "starGiftOutOfStock"
    case .disallowedStarGift:
        return "disallowedStarGift"
    case .starGiftUserLimit:
        return "starGiftUserLimit"
    case let .serverProvided(value):
        return "serverProvided: \(value)"
    }
}

private func ghostBaseHiddenGiftSendResultText(
    _ result: SendBotPaymentResult
) -> String {
    switch result {
    case .done:
        return "SUCCESS: подарок отправлен, 50 Stars списаны."
    case let .externalVerificationRequired(url):
        return """
        externalVerificationRequired
        URL не открыт автоматически:
        \(url)
        """
    }
}

// MARK: GhostBase v1.0ZA Bot Capability UI

private let ghostBaseBotCapabilityPrefix =
    "jerkgram.Research.BotCapability."

private func ghostBaseBotCapabilityReport() -> String {
    let defaults = UserDefaults.standard

    let status = defaults.string(
        forKey: ghostBaseBotCapabilityPrefix + "Status"
    ) ?? "not tested"

    let updated = defaults.string(
        forKey: ghostBaseBotCapabilityPrefix + "Updated"
    ) ?? "none"

    let report = defaults.string(
        forKey: ghostBaseBotCapabilityPrefix + "Report"
    ) ?? "Результатов пока нет."

    return """
    Status: \(status)
    Updated: \(updated)

    \(report)
    """
}

// MARK: GhostBase v1.0ZB Bot Difference UI

private let ghostBaseBotDifferencePrefix =
    "jerkgram.Research.BotDifference."

private func ghostBaseBotDifferenceReport() -> String {
    let defaults = UserDefaults.standard

    let status = defaults.string(
        forKey: ghostBaseBotDifferencePrefix + "Status"
    ) ?? "not tested"

    let updated = defaults.string(
        forKey: ghostBaseBotDifferencePrefix + "Updated"
    ) ?? "none"

    let report = defaults.string(
        forKey: ghostBaseBotDifferencePrefix + "Report"
    ) ?? "Результатов пока нет."

    return """
    Status: \(status)
    Updated: \(updated)

    \(report)
    """
}

// MARK: GhostBase v1.0ZD PROFILEINTEL1 UI

private let ghostBaseProfileIntelPrefix =
    "jerkgram.Research.ProfileIntel1."

private func ghostBaseProfileIntelReport() -> String {
    let defaults = UserDefaults.standard

    let target = defaults.string(
        forKey: ghostBaseProfileIntelPrefix + "Target"
    ) ?? "none"

    let status = defaults.string(
        forKey: ghostBaseProfileIntelPrefix + "Status"
    ) ?? "not tested"

    let updated = defaults.string(
        forKey: ghostBaseProfileIntelPrefix + "Updated"
    ) ?? "none"

    let current = defaults.string(
        forKey: ghostBaseProfileIntelPrefix + "Report"
    ) ?? "Результатов пока нет."

    let previousUpdated = defaults.string(
        forKey: ghostBaseProfileIntelPrefix + "PreviousUpdated"
    ) ?? "none"

    let previous = defaults.string(
        forKey: ghostBaseProfileIntelPrefix + "PreviousReport"
    ) ?? "Предыдущего результата нет."

    return """
    Target: \(target)
    Status: \(status)
    Updated: \(updated)

    CURRENT
    \(current)

    PREVIOUS
    Updated: \(previousUpdated)
    \(previous)
    """
}

// MARK: GhostBase v1.0ZF PROFILEINTEL2 UI

private let ghostBaseProfileIntel2Prefix =
    "jerkgram.Research.ProfileIntel2."

private func ghostBaseProfileIntel2Report() -> String {
    let defaults = UserDefaults.standard
    let target = defaults.string(
        forKey: ghostBaseProfileIntel2Prefix + "Target"
    ) ?? "none"
    let status = defaults.string(
        forKey: ghostBaseProfileIntel2Prefix + "Status"
    ) ?? "not tested"
    let updated = defaults.string(
        forKey: ghostBaseProfileIntel2Prefix + "Updated"
    ) ?? "none"
    let report = defaults.string(
        forKey: ghostBaseProfileIntel2Prefix + "Report"
    ) ?? "Снимков пока нет."

    return """
    Target: \(target)
    Status: \(status)
    Updated: \(updated)

    \(report)
    """
}

// MARK: Jerkgram v1.2D BUILD115_RESEARCH_SETTINGS_CANONICAL1
// MARK: Jerkgram v1.2D BUILD115_SETTINGS_LOCALIZATION1
// MARK: Jerkgram v1.2D BUILD115_RESEARCH_SETTINGS_LOCALIZED1


private enum JerkgramAboutChannelState: Equatable {
    case loading
    case available(peer: EnginePeer, preview: String)
    case unavailable
}

private func jerkgramAboutChannelState(
    context: AccountContext,
    enabled: Bool,
    username: String
) -> Signal<JerkgramAboutChannelState, NoError> {
    guard enabled else {
        return .single(.unavailable)
    }

    return context.engine.peers.resolvePeerByName(name: username, referrer: nil)
    |> mapToSignal { result -> Signal<JerkgramAboutChannelState, NoError> in
        switch result {
        case .progress:
            return .single(.loading)
        case let .result(peer):
            guard let peer else {
                return .single(.unavailable)
            }

            let history = context.account.postbox
                .aroundMessageHistoryViewForLocation(
                    .peer(peerId: peer.id, threadId: nil),
                    anchor: .upperBound,
                    ignoreMessagesInTimestampRange: nil,
                    ignoreMessageIds: Set(),
                    count: 10,
                    clipHoles: false,
                    fixedCombinedReadStates: nil,
                    topTaggedMessageIdNamespaces: Set(),
                    tag: nil,
                    appendMessagesFromTheSameGroup: false,
                    namespaces: .not(Namespaces.Message.allNonRegular),
                    orderStatistics: []
                )
            let poll: Signal<Void, NoError> = .single(Void())
            |> then(
                context.account.viewTracker.polledChannel(peerId: peer.id)
            )

            return combineLatest(history, poll)
            |> map { viewData, _ -> JerkgramAboutChannelState in
                let (view, _, _) = viewData
                let raw = view.entries.last?.message.text ?? ""
                let compact = raw
                    .split(whereSeparator: { $0.isWhitespace })
                    .joined(separator: " ")
                return .available(
                    peer: peer,
                    preview: String(compact.prefix(160))
                )
            }
        }
    }
    |> distinctUntilChanged
}

// MARK: Jerkgram v1.2M BUILD124_ARCHIVE_IMPORT_REFRESH1
private let jerkgramSettingsDidImportNotification = Notification.Name("JerkgramSettingsDidImport")

func jerkgramNotifySettingsImported(accountPeerId: Int64) {
    NotificationCenter.default.post(
        name: jerkgramSettingsDidImportNotification,
        object: nil,
        userInfo: ["accountPeerId": NSNumber(value: accountPeerId)]
    )
}

private func jerkgramSettingsImportRefreshSignal(
    accountPeerId: Int64,
    reload: @escaping () -> Void
) -> Signal<Void, NoError> {
    return Signal { subscriber in
        // Seed combineLatest immediately. The observer itself is retained only
        // by the controller state signal and is removed with that subscription.
        subscriber.putNext(())
        let observer = NotificationCenter.default.addObserver(
            forName: jerkgramSettingsDidImportNotification,
            object: nil,
            queue: OperationQueue.main,
            using: { notification in
                guard let rawAccountPeerId = notification.userInfo?["accountPeerId"] as? NSNumber,
                      rawAccountPeerId.int64Value == accountPeerId else {
                    return
                }
                reload()
            }
        )
        return ActionDisposable {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}

// MARK: Jerkgram v1.2M BUILD124_SETTINGS_REDESIGN1
// MARK: Jerkgram v1.2T BUILD130_RELEASE_UI_TELEMETRY1
private func ghostBaseSettingsEntries(
    state: GhostBaseSettingsState,
    context: AccountContext,
    page: GhostBaseSettingsPage,
    strings: JerkgramStrings,
    aboutChannelState: JerkgramAboutChannelState,
    aboutCommunityState: JerkgramAboutChannelState
) -> [GhostBaseSettingsEntry] {
    var entries: [GhostBaseSettingsEntry] = []

    let ghost = GhostBaseSettingsSection.ghostMode.rawValue
    let protected = GhostBaseSettingsSection.protectedContent.rawValue
    let stars = GhostBaseSettingsSection.stars.rawValue
    let debug = GhostBaseSettingsSection.debug.rawValue
    let footer = GhostBaseSettingsSection.footer.rawValue

    if page == .debugResearch {
        entries.append(.header(debug, strings.researchHiddenGiftsProbe))
        entries.append(.researchAction(
            debug,
            900,
            strings.researchCheckNineGiftsSelf,
            "hiddenGiftsSelf"
        ))
        entries.append(.researchAction(
            debug,
            901,
            strings.researchCheckUserGifts,
            "hiddenGiftsOther"
        ))
        entries.append(.researchInfo(
            debug,
            902,
            ghostBaseHiddenGiftsReport()
        ))
    }

    if page == .debugResearch {
        entries.append(
            .header(
                debug,
                strings.researchHiddenGiftsSend
            )
        )

        entries.append(.researchAction(
            debug,
            920,
            "New Year Bear · ID 5956217000635139069",
            "hiddenGiftSendSelect0"
        ))
        entries.append(.researchAction(
            debug,
            921,
            "Christmas Tree · ID 5922558454332916696",
            "hiddenGiftSendSelect1"
        ))
        entries.append(.researchAction(
            debug,
            922,
            "Valentine Bear · ID 5800655655995968830",
            "hiddenGiftSendSelect2"
        ))
        entries.append(.researchAction(
            debug,
            923,
            "March 8 Bear · ID 5866352046986232958",
            "hiddenGiftSendSelect3"
        ))
        entries.append(.researchAction(
            debug,
            924,
            "Valentine Card · ID 5801108895304779062",
            "hiddenGiftSendSelect4"
        ))
        entries.append(.researchAction(
            debug,
            925,
            "Leprechaun Bear · ID 5893356958802511476",
            "hiddenGiftSendSelect5"
        ))
        entries.append(.researchAction(
            debug,
            926,
            "April 1 Bear · ID 5935895822435615975",
            "hiddenGiftSendSelect6"
        ))
        entries.append(.researchAction(
            debug,
            927,
            "Easter Bear · ID 5969796561943660080",
            "hiddenGiftSendSelect7"
        ))
        entries.append(.researchAction(
            debug,
            928,
            "Builder Bear · ID 6026193266406327981",
            "hiddenGiftSendSelect8"
        ))

        entries.append(.researchAction(
            debug,
            929,
            strings.researchSendToSelf,
            "hiddenGiftSendSelf"
        ))

        entries.append(.researchAction(
            debug,
            930,
            strings.researchSelectAnotherRecipient,
            "hiddenGiftSendRecipient"
        ))

        entries.append(.researchAction(
            debug,
            931,
            ghostBaseHiddenGiftSendState.hideName
                ? strings.researchHideSenderNameOn
                : strings.researchHideSenderNameOff,
            "hiddenGiftSendToggleHideName"
        ))

        if ghostBaseHiddenGiftSendState.giftId != nil,
           ghostBaseHiddenGiftSendState.targetPeerId != nil,
           !ghostBaseHiddenGiftSendState.firstConfirmed,
           !ghostBaseHiddenGiftSendState.isSending {
            entries.append(.researchAction(
                debug,
                932,
                strings.researchConfirmGiftRecipient,
                "hiddenGiftSendConfirm"
            ))
        }

        if ghostBaseHiddenGiftSendState.firstConfirmed,
           !ghostBaseHiddenGiftSendState.isSending {
            entries.append(.researchAction(
                debug,
                933,
                strings.researchPayAndSend,
                "hiddenGiftSendPay"
            ))
        }

        if !ghostBaseHiddenGiftSendState.isSending {
            entries.append(.researchAction(
                debug,
                934,
                strings.researchResetSelection,
                "hiddenGiftSendReset"
            ))
        }

        entries.append(.researchInfo(
            debug,
            935,
            ghostBaseHiddenGiftSendSummary()
        ))
    }

    if page == .debugResearch {
        entries.append(.header(
            debug,
            strings.researchBotCapabilityHeader
        ))
        entries.append(.researchAction(
            debug,
            940,
            strings.researchBotCapability,
            "botCapabilityProbe"
        ))
        entries.append(.researchInfo(
            debug,
            941,
            ghostBaseBotCapabilityReport()
        ))


        entries.append(.researchAction(
            debug,
            942,
            strings.researchBotDifference,
            "botDifferenceProbe"
        ))
        entries.append(.researchInfo(
            debug,
            943,
            ghostBaseBotDifferenceReport()
        ))




    }

    if page == .root {
        // MARK: Jerkgram v1.2K BUILD122_SETTINGS_RELEASE1
        // Keep the agreed Telegram-native destination list. Presentation work
        // belongs inside destinations, not in a new root hero card.
        return [
            .header(0, strings.features),
            .disclosure(0, 1, strings.basicFunctions, "Jerkgram/Settings/Airplane", .home),
            .disclosure(0, 2, strings.ghostMode, "Chat/Context Menu/Eye", .ghostMode),
            .disclosure(0, 3, strings.messages, "Chat/Context Menu/MessageBubble", .messages),
            .disclosure(0, 4, strings.protectedContent, "Premium/CopyProtection/NoForward", .protectedContent),
            .disclosure(0, 5, strings.mediaAndStories, "Item List/Icons/Stories", .mediaStories),
            .disclosure(0, 6, strings.appearance, "Chat/Context Menu/ApplyTheme", .appearance),
            .disclosure(0, 7, strings.debugResearch, "Chat/Context Menu/FormatCode", .debugResearch),
            .disclosure(0, 8, strings.dataAndBackup, "Item List/Icons/Stories", .dataAndBackup),
            .disclosure(0, 9, strings.about, "Chat/Context Menu/Info", .about)
        ]
    }

    if page == .home {
        let balance = state.localStarsAmount.isEmpty
            ? "0"
            : state.localStarsAmount

        return [
            .header(0, strings.profileInformation),
            .toggle(0, 1, GhostBaseKey.profileEnabled, strings.showProfileInformation, state.profileEnabled),
            .toggle(0, 2, GhostBaseKey.showIds, strings.telegramId, state.showIds),
            .toggle(0, 3, GhostBaseKey.showDCs, strings.avatarDc, state.showDCs),
            .toggle(0, 4, GhostBaseKey.showRegistration, strings.registrationDate, state.showRegistration),
            .header(1, strings.basicFunctions),
            .valueDisclosure(1, 50, strings.starsBalance, strings.starsOverrideSummary(state.localStarsEnabled, balance), nil, .stars),
            .header(2, strings.backup),
            .disclosure(2, 1, strings.dataAndBackup, "Item List/Icons/Stories", .dataAndBackup)
        ]
    }

    // MARK: Jerkgram v1.2H BUILD119_STARS_EDITOR1
    if page == .stars {
        let balance = state.localStarsAmount.isEmpty ? "0" : state.localStarsAmount
        return [
            .header(0, strings.starsBalance),
            .toggle(
                0, 1,
                GhostBaseKey.localStarsEnabled,
                strings.localStarsBalance,
                state.localStarsEnabled
            ),
            .info(0, strings.starsOverrideSummary(state.localStarsEnabled, balance)),
            .header(1, strings.change),
            .input(
                1, 1,
                GhostBaseKey.localStarsAmount,
                strings.starsBalance,
                state.localStarsAmount
            ),
            .info(1, strings.starsEditorHint)
        ]
    }

    if page == .ghostMode {
        return [
            .header(0, strings.ghostMode),
            .toggle(0, 1, GhostBaseKey.readMessages, strings.readGhost, state.readMessages),
            .toggle(0, 2, GhostBaseKey.typingActions, strings.typing, state.typingActions),
            .toggle(0, 3, GhostBaseKey.recordingActions, strings.recording, state.recordingActions),
            .toggle(0, 4, GhostBaseKey.uploadingActions, strings.uploading, state.uploadingActions),
            .toggle(0, 5, GhostBaseKey.stickerActivity, strings.choosingSticker, state.stickerActivity),
            .toggle(0, 6, GhostBaseKey.gameActivity, strings.gameActivity, state.gameActivity),
            .toggle(0, 7, GhostBaseKey.emojiActivity, strings.choosingEmoji, state.emojiActivity),
            .toggle(0, 8, GhostBaseKey.presence, strings.hideOnline, state.presence),
            .toggle(0, 9, GhostBaseKey.scheduledSend, strings.scheduledSend, state.scheduledSend)
        ]
    }

    if page == .messages {
        return [
            .header(0, strings.deletedMessages),
            .toggle(0, 1, GhostBaseKey.saveDeleted, strings.saveDeletedMessages, state.saveDeleted),
            .toggle(0, 2, GhostBaseKey.showDeleted, strings.deletedMessages, state.showDeleted),

            .header(1, strings.editHistory),
            .toggle(1, 3, GhostBaseKey.saveEditHistory, strings.saveEditHistory, state.saveEditHistory),
            .toggle(1, 4, GhostBaseKey.showEditHistory, strings.editHistory, state.showEditHistory),

            .info(1, strings.savedDataHint),

            .header(2, strings.textSending),
            .selector(
                2,
                5,
                strings.sendStyle,
                state.sendTextStyle
            ),
            .stylePreview(
                2,
                6,
                state.sendTextStyle
            ),
            .info(
                2,
                strings.sendStyleHint
            ),
            .header(4, strings.deletedReplies),
            .toggle(
                4,
                90,
                GhostBaseKey.deletedPortableReplies,
            // MARK: Jerkgram v1.1Z BUILD111_PORTABLE_REPLY_TITLE1
                strings.portableReply,
                state.deletedPortableReplies
            ),
            .toggle(
                4,
                91,
                GhostBaseKey.preserveDeletedMedia,
                strings.saveDeletedMedia,
                state.preserveDeletedMedia
            ),
            .info(
                4,
                strings.portableReplyHint
            ),
        ]
    }

    if page == .protectedContent {
        return [
            .header(0, strings.protectedContent),
            .toggle(0, 1, GhostBaseKey.protectedEnabled, strings.protectionEnabled, state.protectedEnabled),
            .toggle(0, 2, GhostBaseKey.protectedGalleryShare, strings.shareFromGallery, state.protectedGalleryShare),
            .toggle(0, 3, GhostBaseKey.protectedGallerySave, strings.saveFromGallery, state.protectedGallerySave),
            .toggle(0, 4, GhostBaseKey.protectedGalleryCopy, strings.copyFromGallery, state.protectedGalleryCopy),
            .toggle(0, 5, GhostBaseKey.chatSave, strings.saveFromChat, state.chatSave),
            .toggle(0, 6, GhostBaseKey.chatCopy, strings.copyFromChat, state.chatCopy),
            .toggle(0, 7, GhostBaseKey.chatForward, strings.forwardFromChat, state.chatForward),
            .toggle(0, 8, GhostBaseKey.allowScreenshots, strings.allowScreenshots, state.allowScreenshots),
            .toggle(0, 9, GhostBaseKey.allowScreenRecording, strings.allowScreenRecording, state.allowScreenRecording)
        ]
    }

    if page == .mediaStories {
        return [
            .header(0, strings.mediaAndStories),
            .toggle(0, 1, GhostBaseKey.oneTimeScreenshots, strings.oneTimeScreenshots, state.oneTimeScreenshots),
            .toggle(0, 2, GhostBaseKey.oneTimeScreenRecording, strings.oneTimeScreenRecording, state.oneTimeScreenRecording),
            .toggle(0, 3, GhostBaseKey.oneTimeSave, strings.oneTimeMedia, state.oneTimeSave),
            .toggle(0, 4, GhostBaseKey.storySave, strings.storySave, state.storySave)
        ]
    }

    if page == .appearance {
        return [
            .header(0, strings.profileBackground),
            .toggle(0, 1, GhostBaseKey.glassEnabled, strings.profileBackgroundEffect, state.glassEnabled),
            .toggle(0, 2, GhostBaseKey.profileAvatarBlur, strings.preferAvatarAsBackground, state.profileAvatarBlur),
            .toggle(0, 3, GhostBaseKey.profileAnimatedBackground, strings.animatedBackground, state.profileAnimatedBackground),
            .toggle(0, 4, GhostBaseKey.profileBlurTint, strings.colorTint, state.profileBlurTint),
            .toggle(0, 5, GhostBaseKey.profileBlurReduced, strings.reducedBlur, state.profileBlurReduced),
            .header(1, strings.interface),
            .toggle(1, 5, GhostBaseKey.messageSeconds, strings.messageSeconds, state.messageSeconds),
            .toggle(1, 6, GhostBaseKey.hideOwnPhone, strings.hideMyPhone, state.hideOwnPhone),
            .toggle(
                1,
                7,
                GhostBaseKey.showRamUnderClock,
                strings.showRamUnderClock,
                state.showRamUnderClock
            ),
            .info(1, strings.hidePhoneHint)
        ]
    }

    // MARK: Jerkgram v1.2G BUILD118_ABOUT_CHANNEL_CARDS1
    if page == .about {
        func channelEntry(index: Int32, username: String, state: JerkgramAboutChannelState) -> GhostBaseSettingsEntry {
            switch state {
            case .loading:
                return .aboutChannel(0, index, username, nil, strings.communityLoading, true)
            case let .available(peer, preview):
                let visiblePreview = preview.isEmpty ? strings.communityNoPosts : "@\(username) · \(preview)"
                return .aboutChannel(0, index, username, peer, visiblePreview, false)
            case .unavailable:
                return .aboutChannel(0, index, username, nil, strings.communityUnavailable, false)
            }
        }
        return [
            .header(0, strings.about),
            channelEntry(index: 1, username: "JerkgramApp", state: aboutChannelState),
            channelEntry(index: 2, username: "JerkgramCommunity", state: aboutCommunityState),
            .header(1, strings.version),
            .aboutValue(1, 1, strings.jerkgramVersion, Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"),
            .aboutValue(1, 2, strings.build, Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "—"),
            .aboutValue(1, 3, strings.telegramBase, "12.9.2"),
            .header(2, strings.privacy),
            .telemetryToggle(2, 1, strings.anonymousAnalytics, jerkgramTelemetryEnabled()),
            .info(3, strings.anonymousAnalyticsDescription)
        ]
    }

        // MARK: Jerkgram v1.2E BUILD116_SETTINGS_RUNTIME_CLEANUP1
    if page == .debugResearch {
        return [
            .researchAction(0, 0, strings.copyExtensionDiagnostics, "copyExtensionDiagnostics")
        ]
    }


    entries.append(.header(ghost, strings.ghostMode))
    entries.append(.toggle(ghost, 1, GhostBaseKey.readMessages, strings.readGhost, state.readMessages))
    entries.append(.toggle(ghost, 2, GhostBaseKey.typingActions, "Hide Typing", state.typingActions))
    entries.append(.toggle(ghost, 3, GhostBaseKey.recordingActions, "Hide Recording", state.recordingActions))
    entries.append(.toggle(ghost, 4, GhostBaseKey.uploadingActions, "Hide Uploading", state.uploadingActions))
    entries.append(.toggle(ghost, 5, GhostBaseKey.stickerActivity, "Hide Sticker Activity", state.stickerActivity))
    entries.append(.toggle(ghost, 6, GhostBaseKey.gameActivity, "Hide Game Activity", state.gameActivity))
    entries.append(.toggle(ghost, 7, GhostBaseKey.emojiActivity, "Hide Emoji Activity", state.emojiActivity))
    entries.append(.toggle(ghost, 8, GhostBaseKey.presence, "Hide Online", state.presence))
    entries.append(.toggle(ghost, 9, GhostBaseKey.scheduledSend, strings.scheduledSend, state.scheduledSend))

    entries.append(.header(protected, strings.protectedContent))
    entries.append(.toggle(protected, 1, GhostBaseKey.protectedEnabled, "Protected Content Bypass", state.protectedEnabled))
    entries.append(.toggle(protected, 2, GhostBaseKey.protectedGalleryShare, "Gallery Share", state.protectedGalleryShare))
    entries.append(.toggle(protected, 3, GhostBaseKey.protectedGallerySave, "Gallery Save", state.protectedGallerySave))
    entries.append(.toggle(protected, 4, GhostBaseKey.protectedGalleryCopy, "Gallery Copy", state.protectedGalleryCopy))
    entries.append(.toggle(protected, 5, GhostBaseKey.chatSave, "Chat Save", state.chatSave))
    entries.append(.toggle(protected, 6, GhostBaseKey.chatCopy, "Chat Copy", state.chatCopy))
    entries.append(.toggle(protected, 7, GhostBaseKey.chatForward, "Chat Forward", state.chatForward))
    entries.append(.toggle(protected, 8, GhostBaseKey.allowScreenshots, strings.allowScreenshots, state.allowScreenshots))
    entries.append(.toggle(protected, 9, GhostBaseKey.allowScreenRecording, strings.allowScreenRecording, state.allowScreenRecording))
    entries.append(.toggle(protected, 10, GhostBaseKey.oneTimeScreenshots, "Allow One-Time Screenshots", state.oneTimeScreenshots))
    entries.append(.toggle(protected, 11, GhostBaseKey.oneTimeScreenRecording, "One-Time Recording", state.oneTimeScreenRecording))
    entries.append(.toggle(protected, 12, GhostBaseKey.oneTimeSave, "Allow One-Time Save", state.oneTimeSave))
    entries.append(.toggle(protected, 13, GhostBaseKey.storySave, "Story Save", state.storySave))

    entries.append(.header(stars, "Stars"))
    entries.append(.toggle(stars, 1, GhostBaseKey.localStarsEnabled, "Enable Local Stars Balance", state.localStarsEnabled))
    let ghostBaseStarsDisplay = state.localStarsAmount.isEmpty ? "0" : state.localStarsAmount
    entries.append(.input(stars, 2, GhostBaseKey.localStarsAmount, strings.localStarsBalance, state.localStarsAmount))
    entries.append(.info(stars, "Current visual balance: \(ghostBaseStarsDisplay) ⭐"))
            let telegramId = String(context.account.peerId.id._internalGetInt64Value())
    let bundleId = Bundle.main.bundleIdentifier ?? "unknown"

    entries.append(.header(debug, "Debug"))
    let ghostBasePushPrefix = "jerkgram.V10E.Push."
    let ghostBasePushDefaults = UserDefaults.standard

    entries.append(.info(debug, """
Main Push Registration Probe:
Total: \(ghostBasePushDefaults.integer(forKey: ghostBasePushPrefix + "Total"))
Last: \(ghostBasePushDefaults.string(forKey: ghostBasePushPrefix + "Last") ?? "none") x\(ghostBasePushDefaults.integer(forKey: ghostBasePushPrefix + "LastAmount")) @ \(ghostBasePushDefaults.integer(forKey: ghostBasePushPrefix + "LastTime"))
settingsRead: \(ghostBasePushDefaults.integer(forKey: ghostBasePushPrefix + "notificationSettingsRead.Count"))
authTrue: \(ghostBasePushDefaults.integer(forKey: ghostBasePushPrefix + "requestAuthorizationTrue.Count"))
authFalse: \(ghostBasePushDefaults.integer(forKey: ghostBasePushPrefix + "requestAuthorizationFalse.Count"))
authorizedRegister: \(ghostBasePushDefaults.integer(forKey: ghostBasePushPrefix + "authorizedRegisterForRemoteNotifications.Count"))
invalidationRegister: \(ghostBasePushDefaults.integer(forKey: ghostBasePushPrefix + "invalidationRegisterForRemoteNotifications.Count"))
didRegisterToken: \(ghostBasePushDefaults.integer(forKey: ghostBasePushPrefix + "didRegisterDeviceToken.Count"))
didFailToken: \(ghostBasePushDefaults.integer(forKey: ghostBasePushPrefix + "didFailRegisterDeviceToken.Count"))
registerDeviceEntry: \(ghostBasePushDefaults.integer(forKey: ghostBasePushPrefix + "registerDeviceEntry.Count"))
registerDeviceRequest: \(ghostBasePushDefaults.integer(forKey: ghostBasePushPrefix + "registerDeviceRequest.Count"))
registerDeviceSuccess: \(ghostBasePushDefaults.integer(forKey: ghostBasePushPrefix + "registerDeviceSuccess.Count"))
registerDeviceInvalidated: \(ghostBasePushDefaults.integer(forKey: ghostBasePushPrefix + "registerDeviceInvalidated.Count"))
registerDeviceError: \(ghostBasePushDefaults.integer(forKey: ghostBasePushPrefix + "registerDeviceError.Count"))
didReceiveRemote: \(ghostBasePushDefaults.integer(forKey: ghostBasePushPrefix + "didReceiveRemoteNotification.Count"))
remoteEncryptedPayload: \(ghostBasePushDefaults.integer(forKey: ghostBasePushPrefix + "remoteEncryptedPayload.Count"))
pushRegistryEncrypted: \(ghostBasePushDefaults.integer(forKey: ghostBasePushPrefix + "pushRegistryEncryptedPayload.Count"))
pushRegistryKeyId: \(ghostBasePushDefaults.integer(forKey: ghostBasePushPrefix + "pushRegistryKeyId.Count"))
pushRegistryKeyFound: \(ghostBasePushDefaults.integer(forKey: ghostBasePushPrefix + "pushRegistryNotificationKeyFound.Count"))
pushRegistryDecryptFailed: \(ghostBasePushDefaults.integer(forKey: ghostBasePushPrefix + "pushRegistryDecryptFailed.Count"))
pushRegistryDecrypted: \(ghostBasePushDefaults.integer(forKey: ghostBasePushPrefix + "pushRegistryDecryptedPayload.Count"))
pushRegistryJson: \(ghostBasePushDefaults.integer(forKey: ghostBasePushPrefix + "pushRegistryJson.Count"))
pushRegistryMsgId: \(ghostBasePushDefaults.integer(forKey: ghostBasePushPrefix + "pushRegistryMsgId.Count"))
LastAuthorizationStatus: \(ghostBasePushDefaults.string(forKey: ghostBasePushPrefix + "LastAuthorizationStatus") ?? "none")
LastRegisterFail: \(ghostBasePushDefaults.string(forKey: ghostBasePushPrefix + "LastRegisterFail") ?? "none")
LastRegisterDeviceType: \(ghostBasePushDefaults.string(forKey: ghostBasePushPrefix + "LastRegisterDeviceType") ?? "none")
LastRegisterDeviceSandbox: \(ghostBasePushDefaults.string(forKey: ghostBasePushPrefix + "LastRegisterDeviceSandbox") ?? "none")
LastRegisterDeviceError: \(ghostBasePushDefaults.string(forKey: ghostBasePushPrefix + "LastRegisterDeviceError") ?? "none")
LastUserInfoKeys: \(ghostBasePushDefaults.string(forKey: ghostBasePushPrefix + "LastUserInfoKeys") ?? "none")
LastAPSKeys: \(ghostBasePushDefaults.string(forKey: ghostBasePushPrefix + "LastAPSKeys") ?? "none")
LastPushRegistryKeys: \(ghostBasePushDefaults.string(forKey: ghostBasePushPrefix + "LastPushRegistryKeys") ?? "none")
LastPushRegistryPayloadKeys: \(ghostBasePushDefaults.string(forKey: ghostBasePushPrefix + "LastPushRegistryPayloadKeys") ?? "none")
Public main-app path: YES
NSE required: NO
"""))

    let ghostBaseNsePrefix = "jerkgram.V10D.NSE."
    let ghostBaseNseDefaults = UserDefaults(suiteName: "group.ph.telegra.Telegraph") ?? UserDefaults.standard

    entries.append(.info(debug, """
Capture Mesh / NSE Probe:
AppGroup: \(ghostBaseNseDefaults.string(forKey: ghostBaseNsePrefix + "AppGroup") ?? "none")
Total: \(ghostBaseNseDefaults.integer(forKey: ghostBaseNsePrefix + "Total"))
Last: \(ghostBaseNseDefaults.string(forKey: ghostBaseNsePrefix + "Last") ?? "none") x\(ghostBaseNseDefaults.integer(forKey: ghostBaseNsePrefix + "LastAmount")) @ \(ghostBaseNseDefaults.integer(forKey: ghostBaseNsePrefix + "LastTime"))
didReceive: \(ghostBaseNseDefaults.integer(forKey: ghostBaseNsePrefix + "didReceive.Count"))
decryptedPayload: \(ghostBaseNseDefaults.integer(forKey: ghostBaseNsePrefix + "decryptedPayload.Count"))
payloadMsgId: \(ghostBaseNseDefaults.integer(forKey: ghostBaseNsePrefix + "payloadMsgId.Count"))
payloadPeerId: \(ghostBaseNseDefaults.integer(forKey: ghostBaseNsePrefix + "payloadPeerId.Count"))
initialBody: \(ghostBaseNseDefaults.integer(forKey: ghostBaseNsePrefix + "initialBody.Count"))
initialGenericBody: \(ghostBaseNseDefaults.integer(forKey: ghostBaseNsePrefix + "initialGenericBody.Count"))
finalBody: \(ghostBaseNseDefaults.integer(forKey: ghostBaseNsePrefix + "finalBody.Count"))
finalGenericBody: \(ghostBaseNseDefaults.integer(forKey: ghostBaseNsePrefix + "finalGenericBody.Count"))
LastLocKey: \(ghostBaseNseDefaults.string(forKey: ghostBaseNsePrefix + "LastLocKey") ?? "none")
LastPayloadKeys: \(ghostBaseNseDefaults.string(forKey: ghostBaseNsePrefix + "LastPayloadKeys") ?? "none")
LastFinalTitle: \(ghostBaseNseDefaults.string(forKey: ghostBaseNsePrefix + "LastFinalTitle") ?? "none")
LastFinalBody: \(ghostBaseNseDefaults.string(forKey: ghostBaseNsePrefix + "LastFinalBody") ?? "none")
"""))

    let ghostBaseCorePrefixV10C = "jerkgram.V10C.Core."
    let ghostBaseCoreDefaultsV10C = UserDefaults.standard

    entries.append(.info(debug, """
Core Difference Deep Probe:
Total: \(ghostBaseCoreDefaultsV10C.integer(forKey: ghostBaseCorePrefixV10C + "Total"))
Last: \(ghostBaseCoreDefaultsV10C.string(forKey: ghostBaseCorePrefixV10C + "Last") ?? "none") x\(ghostBaseCoreDefaultsV10C.integer(forKey: ghostBaseCorePrefixV10C + "LastAmount")) @ \(ghostBaseCoreDefaultsV10C.integer(forKey: ghostBaseCorePrefixV10C + "LastTime"))
diffRuns: \(ghostBaseCoreDefaultsV10C.integer(forKey: ghostBaseCorePrefixV10C + "differenceRuns.Count"))
diffNewMessages: \(ghostBaseCoreDefaultsV10C.integer(forKey: ghostBaseCorePrefixV10C + "differenceNewMessages.Count"))
diffOtherUpdates: \(ghostBaseCoreDefaultsV10C.integer(forKey: ghostBaseCorePrefixV10C + "differenceOtherUpdates.Count"))
deleteEvents: \(ghostBaseCoreDefaultsV10C.integer(forKey: ghostBaseCorePrefixV10C + "deleteMessagesEvents.Count"))
deleteIds: \(ghostBaseCoreDefaultsV10C.integer(forKey: ghostBaseCorePrefixV10C + "deleteMessageIds.Count"))
lastDeleteIds: \(ghostBaseCoreDefaultsV10C.integer(forKey: ghostBaseCorePrefixV10C + "LastDeleteIdsCount"))
lastDiffNewMessages: \(ghostBaseCoreDefaultsV10C.integer(forKey: ghostBaseCorePrefixV10C + "LastDifferenceNewMessagesCount"))
lastDiffOtherUpdates: \(ghostBaseCoreDefaultsV10C.integer(forKey: ghostBaseCorePrefixV10C + "LastDifferenceOtherUpdatesCount"))
lastDiffDeleteIds: \(ghostBaseCoreDefaultsV10C.integer(forKey: ghostBaseCorePrefixV10C + "LastDifferenceDeleteMessageIdsCount"))
"""))


    let ghostBaseRawPrefixV10F = "jerkgram.V10F.Raw."
    let ghostBaseRawDefaultsV10F = UserDefaults.standard

    entries.append(.info(debug, """
v1.0Q Raw Delete Mapping:
QRawDeleteEvents: \(UserDefaults.standard.integer(forKey: "jerkgram.V10Q.RawDeleteEvents"))
QLastRawDeleteSource: \(UserDefaults.standard.string(forKey: "jerkgram.V10Q.LastRawDeleteSource") ?? "none")
QLastRawDeleteIdCount: \(UserDefaults.standard.integer(forKey: "jerkgram.V10Q.LastRawDeleteIdCount"))
QLastMappedDeleteIdCount: \(UserDefaults.standard.integer(forKey: "jerkgram.V10Q.LastMappedDeleteIdCount"))
QLastRawDeleteIds: \(UserDefaults.standard.string(forKey: "jerkgram.V10Q.LastRawDeleteIds") ?? "none")
QLastMappedDeleteIds: \(UserDefaults.standard.string(forKey: "jerkgram.V10Q.LastMappedDeleteIds") ?? "none")
QVerdict: \(UserDefaults.standard.string(forKey: "jerkgram.V10Q.Verdict") ?? "none")

SH2 Standalone Share Scheduled:
SH2StandaloneScheduledIntercept: \(UserDefaults.standard.integer(forKey: "jerkgram.SH2.StandaloneScheduledIntercept.Count"))
SH2LastStandalonePeerId: \(UserDefaults.standard.string(forKey: "jerkgram.SH2.LastStandalonePeerId") ?? "none")
SH2LastStandaloneScheduleTime: \(UserDefaults.standard.integer(forKey: "jerkgram.SH2.LastStandaloneScheduleTime"))

OT2 ViewOnce Visual Keep:
OT2ViewOnceVisibleKeep: \(UserDefaults.standard.integer(forKey: "jerkgram.OT2.ViewOnceVisibleKeep.Count"))
OT2LastViewOnceVisibleId: \(UserDefaults.standard.string(forKey: "jerkgram.OT2.LastViewOnceVisibleId") ?? "none")

v1.0P Pre-delete Shadow Trace:
PDeleteEvents: \(UserDefaults.standard.integer(forKey: "jerkgram.V10P.DeleteEvents"))
PLastDeleteSource: \(UserDefaults.standard.string(forKey: "jerkgram.V10P.LastDeleteSource") ?? "none")
PLastDeleteIdCount: \(UserDefaults.standard.integer(forKey: "jerkgram.V10P.LastDeleteIdCount"))
PPreDeleteMessageHits: \(UserDefaults.standard.integer(forKey: "jerkgram.V10P.PreDeleteMessageHits"))
PPreDeleteTextHits: \(UserDefaults.standard.integer(forKey: "jerkgram.V10P.PreDeleteTextHits"))
PLastPreDeleteId: \(UserDefaults.standard.string(forKey: "jerkgram.V10P.LastPreDeleteId") ?? "none")
PLastPreDeletePeer: \(UserDefaults.standard.string(forKey: "jerkgram.V10P.LastPreDeletePeer") ?? "none")
PLastPreDeleteTextLength: \(UserDefaults.standard.integer(forKey: "jerkgram.V10P.LastPreDeleteTextLength"))
PLastPreDeleteText: \(UserDefaults.standard.string(forKey: "jerkgram.V10P.LastPreDeleteText") ?? "none")
PVerdict: \(UserDefaults.standard.string(forKey: "jerkgram.V10P.Verdict") ?? "none")

SH1 Share Scheduled Send:
SH1ShareScheduledIntercept: \(UserDefaults.standard.integer(forKey: "jerkgram.SH1.ShareScheduledIntercept.Count"))
SH1LastSharePeerId: \(UserDefaults.standard.string(forKey: "jerkgram.SH1.LastSharePeerId") ?? "none")
SH1LastShareMessageCount: \(UserDefaults.standard.integer(forKey: "jerkgram.SH1.LastShareMessageCount"))
SH1LastShareScheduleTime: \(UserDefaults.standard.integer(forKey: "jerkgram.SH1.LastShareScheduleTime"))

OT1 Timer Media Local Keep:
OT1OutgoingKeepBlocked: \(UserDefaults.standard.integer(forKey: "jerkgram.OT1.OutgoingKeepBlocked.Count"))
OT1AutoremoveKeepBlocked: \(UserDefaults.standard.integer(forKey: "jerkgram.OT1.AutoremoveKeepBlocked.Count"))
OT1OutgoingKeepPath: \(UserDefaults.standard.string(forKey: "jerkgram.OT1.OutgoingKeepPath") ?? "none")

v1.0O Persistent SourcePeer Candidate:
OSourcePeerPersistedRaw: \(UserDefaults.standard.object(forKey: "jerkgram.V10O.Persistent.SourcePeerIdRaw") as? Int64 ?? 0)
OSourcePeerPersistedId: \(UserDefaults.standard.string(forKey: "jerkgram.V10O.Persistent.SourcePeerId") ?? "none")
OSourcePeerPersistedSource: \(UserDefaults.standard.string(forKey: "jerkgram.V10O.Persistent.SourcePeerSource") ?? "none")
OSourcePeerRuntimeRaw: \(ghostBaseRawDefaultsV10F.string(forKey: ghostBaseRawPrefixV10F + "OSourcePeerRuntimeRaw") ?? "none")
OSourcePeerPersistedRawLastUse: \(ghostBaseRawDefaultsV10F.string(forKey: ghostBaseRawPrefixV10F + "OSourcePeerPersistedRaw") ?? "none")
OSourcePeerUsedRaw: \(ghostBaseRawDefaultsV10F.string(forKey: ghostBaseRawPrefixV10F + "OSourcePeerUsedRaw") ?? "none")
OSourcePeerCandidateStatus: \(ghostBaseRawDefaultsV10F.string(forKey: ghostBaseRawPrefixV10F + "OSourcePeerCandidateStatus") ?? "none")

READ3 Runtime Probe:
R3UIPeerIdRaw: \(UserDefaults.standard.object(forKey: "jerkgram.READ3.UI.PeerIdRaw") as? Int64 ?? 0)
R3UIMessageId: \(UserDefaults.standard.object(forKey: "jerkgram.READ3.UI.MessageId") as? Int32 ?? 0)
R3UIPeerType: \(UserDefaults.standard.string(forKey: "jerkgram.READ3.UI.PeerType") ?? "none")
R3UIParticipantCount: \(UserDefaults.standard.object(forKey: "jerkgram.READ3.UI.ParticipantCount") as? Int ?? -2)
R3UIThreshold: \(UserDefaults.standard.object(forKey: "jerkgram.READ3.UI.Threshold") as? Int ?? -1)
R3UIAction: \(UserDefaults.standard.string(forKey: "jerkgram.READ3.UI.Action") ?? "none")
R3LastPeerIdRaw: \(UserDefaults.standard.object(forKey: "jerkgram.READ3.LastPeerIdRaw") as? Int64 ?? 0)
R3LastMessageId: \(UserDefaults.standard.object(forKey: "jerkgram.READ3.LastMessageId") as? Int32 ?? 0)
R3LastApi: \(UserDefaults.standard.string(forKey: "jerkgram.READ3.LastApi") ?? "none")
R3LastResponse: \(UserDefaults.standard.string(forKey: "jerkgram.READ3.LastResponse") ?? "none")
R3ForcedApiRawCount: \(UserDefaults.standard.object(forKey: "jerkgram.READ3.ForcedApiRawCount") as? Int ?? -1)
R3ForcedCount: \(UserDefaults.standard.object(forKey: "jerkgram.READ3.ForcedCount") as? Int ?? -1)
R3FirstUserId: \(UserDefaults.standard.object(forKey: "jerkgram.READ3.FirstUserId") as? Int64 ?? 0)
R3FirstReadDate: \(UserDefaults.standard.object(forKey: "jerkgram.READ3.FirstReadDate") as? Int32 ?? 0)
R3LastErrorRaw: \(UserDefaults.standard.string(forKey: "jerkgram.READ3.LastErrorRaw") ?? "none")
R3FinalVerdict: \(UserDefaults.standard.string(forKey: "jerkgram.READ3.FinalVerdict") ?? "none")

v1.0O SourcePeer Verdict:
NSourcePeerVerdict: \(ghostBaseRawDefaultsV10F.string(forKey: ghostBaseRawPrefixV10F + "NSourcePeerVerdict") ?? "none")
NLastSourcePeerId: \(ghostBaseRawDefaultsV10F.string(forKey: ghostBaseRawPrefixV10F + "NLastSourcePeerId") ?? "none")
NLastSourcePeerIdRaw: \(ghostBaseRawDefaultsV10F.object(forKey: ghostBaseRawPrefixV10F + "NLastSourcePeerIdRaw") as? Int64 ?? 0)
NLastSourcePeerSource: \(ghostBaseRawDefaultsV10F.string(forKey: ghostBaseRawPrefixV10F + "NLastSourcePeerSource") ?? "none")
NSourcePeerSaved: \(ghostBaseRawDefaultsV10F.integer(forKey: ghostBaseRawPrefixV10F + "nSourcePeerSaved.Count"))

NSourcePeerCandidateStatus: \(ghostBaseRawDefaultsV10F.string(forKey: ghostBaseRawPrefixV10F + "NSourcePeerCandidateStatus") ?? "none")
NSourcePeerPresent: \(ghostBaseRawDefaultsV10F.integer(forKey: ghostBaseRawPrefixV10F + "nSourcePeerPresent.Count"))
NSourcePeerMissing: \(ghostBaseRawDefaultsV10F.integer(forKey: ghostBaseRawPrefixV10F + "nSourcePeerMissing.Count"))
NSourcePeerInStatePeers: \(ghostBaseRawDefaultsV10F.integer(forKey: ghostBaseRawPrefixV10F + "nSourcePeerInStatePeers.Count"))
NSourcePeerMissingFromStatePeers: \(ghostBaseRawDefaultsV10F.integer(forKey: ghostBaseRawPrefixV10F + "nSourcePeerMissingFromStatePeers.Count"))

NSourcePeerHistoryResponse: \(ghostBaseRawDefaultsV10F.integer(forKey: ghostBaseRawPrefixV10F + "nSourcePeerHistoryResponse.Count"))
NSourcePeerLastRequestedId: \(ghostBaseRawDefaultsV10F.string(forKey: ghostBaseRawPrefixV10F + "NSourcePeerLastRequestedId") ?? "none")
NSourcePeerLastApiMessageCount: \(ghostBaseRawDefaultsV10F.string(forKey: ghostBaseRawPrefixV10F + "NSourcePeerLastApiMessageCount") ?? "none")

NSourcePeerTargetHit: \(ghostBaseRawDefaultsV10F.integer(forKey: ghostBaseRawPrefixV10F + "nSourcePeerTargetHit.Count"))
NSourcePeerNonExactTargetHit: \(ghostBaseRawDefaultsV10F.integer(forKey: ghostBaseRawPrefixV10F + "nSourcePeerNonExactTargetHit.Count"))
NSourcePeerTargetMarker: \(ghostBaseRawDefaultsV10F.string(forKey: ghostBaseRawPrefixV10F + "NSourcePeerTargetMarker") ?? "none")
NSourcePeerTargetText: \(ghostBaseRawDefaultsV10F.string(forKey: ghostBaseRawPrefixV10F + "NSourcePeerTargetText") ?? "none")

NSourcePeerExactMessage: \(ghostBaseRawDefaultsV10F.integer(forKey: ghostBaseRawPrefixV10F + "nSourcePeerExactMessage.Count"))
NSourcePeerExactEmpty: \(ghostBaseRawDefaultsV10F.integer(forKey: ghostBaseRawPrefixV10F + "nSourcePeerExactEmpty.Count"))
NSourcePeerExactService: \(ghostBaseRawDefaultsV10F.integer(forKey: ghostBaseRawPrefixV10F + "nSourcePeerExactService.Count"))
NSourcePeerExactTextLength: \(ghostBaseRawDefaultsV10F.string(forKey: ghostBaseRawPrefixV10F + "NSourcePeerExactTextLength") ?? "none")
NSourcePeerExactText: \(ghostBaseRawDefaultsV10F.string(forKey: ghostBaseRawPrefixV10F + "NSourcePeerExactText") ?? "none")

v1.0M Current Test Verdict:
MTargetVerdict: \(ghostBaseRawDefaultsV10F.string(forKey: ghostBaseRawPrefixV10F + "MTargetVerdict") ?? "none")
MCurrentMarker: \(ghostBaseRawDefaultsV10F.string(forKey: ghostBaseRawPrefixV10F + "MCurrentMarker") ?? "none")

MTargetSnapshotHit: \(ghostBaseRawDefaultsV10F.integer(forKey: ghostBaseRawPrefixV10F + "mTargetSnapshotHit.Count"))
MTargetHistoryHit: \(ghostBaseRawDefaultsV10F.integer(forKey: ghostBaseRawPrefixV10F + "mTargetHistoryHit.Count"))
MTargetExactHit: \(ghostBaseRawDefaultsV10F.integer(forKey: ghostBaseRawPrefixV10F + "mTargetExactHit.Count"))
MTargetText: \(ghostBaseRawDefaultsV10F.string(forKey: ghostBaseRawPrefixV10F + "MTargetText") ?? "none")
MTargetSnapshotText: \(ghostBaseRawDefaultsV10F.string(forKey: ghostBaseRawPrefixV10F + "MTargetSnapshotText") ?? "none")

MFetchShapeCase: \(ghostBaseRawDefaultsV10F.string(forKey: ghostBaseRawPrefixV10F + "MLastFetchShapeCase") ?? "none")
MFetchShapeId: \(ghostBaseRawDefaultsV10F.string(forKey: ghostBaseRawPrefixV10F + "MLastFetchShapeId") ?? "none")
MFetchShapePeer: \(ghostBaseRawDefaultsV10F.string(forKey: ghostBaseRawPrefixV10F + "MLastFetchShapePeer") ?? "none")
MFetchShapeTextLength: \(ghostBaseRawDefaultsV10F.string(forKey: ghostBaseRawPrefixV10F + "MLastFetchShapeTextLength") ?? "none")

MExactHitWithText: \(ghostBaseRawDefaultsV10F.integer(forKey: ghostBaseRawPrefixV10F + "mExactHitWithText.Count"))
MExactHitWithoutText: \(ghostBaseRawDefaultsV10F.integer(forKey: ghostBaseRawPrefixV10F + "mExactHitWithoutText.Count"))
MExactCollisionCount: \(ghostBaseRawDefaultsV10F.integer(forKey: ghostBaseRawPrefixV10F + "mExactIdCollision.Count"))
MExactCollisionRequestedId: \(ghostBaseRawDefaultsV10F.string(forKey: ghostBaseRawPrefixV10F + "MExactCollisionRequestedId") ?? "none")
MExactCollisionPeer: \(ghostBaseRawDefaultsV10F.string(forKey: ghostBaseRawPrefixV10F + "MExactCollisionPeer") ?? "none")
MExactCollisionCase: \(ghostBaseRawDefaultsV10F.string(forKey: ghostBaseRawPrefixV10F + "MExactCollisionCase") ?? "none")
MExactCollisionId: \(ghostBaseRawDefaultsV10F.string(forKey: ghostBaseRawPrefixV10F + "MExactCollisionId") ?? "none")
MExactCollisionText: \(ghostBaseRawDefaultsV10F.string(forKey: ghostBaseRawPrefixV10F + "MExactCollisionText") ?? "none")

MExactCollisionList:
\(ghostBaseRawDefaultsV10F.string(forKey: ghostBaseRawPrefixV10F + "MExactCollisionList") ?? "none")

v1.0L Target Verdict:
TargetVerdict: \(ghostBaseRawDefaultsV10F.string(forKey: ghostBaseRawPrefixV10F + "TargetVerdict") ?? "none")
TargetMarker: \(ghostBaseRawDefaultsV10F.string(forKey: ghostBaseRawPrefixV10F + "TargetMarker") ?? "none")
TargetSnapshotHit: \(ghostBaseRawDefaultsV10F.integer(forKey: ghostBaseRawPrefixV10F + "targetSnapshotHit.Count"))
TargetHistoryHit: \(ghostBaseRawDefaultsV10F.integer(forKey: ghostBaseRawPrefixV10F + "targetHistoryHit.Count"))
TargetExactHit: \(ghostBaseRawDefaultsV10F.integer(forKey: ghostBaseRawPrefixV10F + "targetExactHit.Count"))
TargetText: \(ghostBaseRawDefaultsV10F.string(forKey: ghostBaseRawPrefixV10F + "TargetText") ?? "none")
TargetSnapshotText: \(ghostBaseRawDefaultsV10F.string(forKey: ghostBaseRawPrefixV10F + "TargetSnapshotText") ?? "none")

ExactHitCount: \(ghostBaseRawDefaultsV10F.integer(forKey: ghostBaseRawPrefixV10F + "exactHitCount.Count"))
ExactHitMessage: \(ghostBaseRawDefaultsV10F.integer(forKey: ghostBaseRawPrefixV10F + "exactHitMessage.Count"))
ExactHitEmpty: \(ghostBaseRawDefaultsV10F.integer(forKey: ghostBaseRawPrefixV10F + "exactHitEmpty.Count"))
ExactHitService: \(ghostBaseRawDefaultsV10F.integer(forKey: ghostBaseRawPrefixV10F + "exactHitService.Count"))
ExactHitWithText: \(ghostBaseRawDefaultsV10F.integer(forKey: ghostBaseRawPrefixV10F + "exactHitWithText.Count"))
ExactHitWithoutText: \(ghostBaseRawDefaultsV10F.integer(forKey: ghostBaseRawPrefixV10F + "exactHitWithoutText.Count"))

ExactHitRequestedId: \(ghostBaseRawDefaultsV10F.string(forKey: ghostBaseRawPrefixV10F + "ExactHitRequestedId") ?? "none")
ExactHitPeer: \(ghostBaseRawDefaultsV10F.string(forKey: ghostBaseRawPrefixV10F + "ExactHitPeer") ?? "none")
ExactHitCase: \(ghostBaseRawDefaultsV10F.string(forKey: ghostBaseRawPrefixV10F + "ExactHitCase") ?? "none")
ExactHitId: \(ghostBaseRawDefaultsV10F.string(forKey: ghostBaseRawPrefixV10F + "ExactHitId") ?? "none")
ExactHitTextLength: \(ghostBaseRawDefaultsV10F.string(forKey: ghostBaseRawPrefixV10F + "ExactHitTextLength") ?? "none")
ExactHitText: \(ghostBaseRawDefaultsV10F.string(forKey: ghostBaseRawPrefixV10F + "ExactHitText") ?? "none")
ExactHitMedia: \(ghostBaseRawDefaultsV10F.string(forKey: ghostBaseRawPrefixV10F + "ExactHitMedia") ?? "none")

ExactHitList:
\(ghostBaseRawDefaultsV10F.string(forKey: ghostBaseRawPrefixV10F + "ExactHitList") ?? "none")

Raw Difference Snapshot Probe:
Total: \(ghostBaseRawDefaultsV10F.integer(forKey: ghostBaseRawPrefixV10F + "Total"))
Last: \(ghostBaseRawDefaultsV10F.string(forKey: ghostBaseRawPrefixV10F + "Last") ?? "none") x\(ghostBaseRawDefaultsV10F.integer(forKey: ghostBaseRawPrefixV10F + "LastAmount")) @ \(ghostBaseRawDefaultsV10F.integer(forKey: ghostBaseRawPrefixV10F + "LastTime"))
snapshotSeen: \(ghostBaseRawDefaultsV10F.integer(forKey: ghostBaseRawPrefixV10F + "snapshotSeen.Count"))
snapshotSaved: \(ghostBaseRawDefaultsV10F.integer(forKey: ghostBaseRawPrefixV10F + "snapshotSaved.Count"))
snapshotWithText: \(ghostBaseRawDefaultsV10F.integer(forKey: ghostBaseRawPrefixV10F + "snapshotWithText.Count"))
snapshotEmptyText: \(ghostBaseRawDefaultsV10F.integer(forKey: ghostBaseRawPrefixV10F + "snapshotEmptyText.Count"))
snapshotWithGlobalId: \(ghostBaseRawDefaultsV10F.integer(forKey: ghostBaseRawPrefixV10F + "snapshotWithGlobalId.Count"))
fromDifference: \(ghostBaseRawDefaultsV10F.integer(forKey: ghostBaseRawPrefixV10F + "snapshotFromDifference.Count"))
fromUpdateNewMessage: \(ghostBaseRawDefaultsV10F.integer(forKey: ghostBaseRawPrefixV10F + "snapshotFromUpdateNewMessage.Count"))
fromUpdateNewChannelMessage: \(ghostBaseRawDefaultsV10F.integer(forKey: ghostBaseRawPrefixV10F + "snapshotFromUpdateNewChannelMessage.Count"))
fromChannelDifference: \(ghostBaseRawDefaultsV10F.integer(forKey: ghostBaseRawPrefixV10F + "snapshotFromChannelDifference.Count"))
deleteDirectSeen: \(ghostBaseRawDefaultsV10F.integer(forKey: ghostBaseRawPrefixV10F + "deleteDirectSeen.Count"))
deleteDirectIds: \(ghostBaseRawDefaultsV10F.integer(forKey: ghostBaseRawPrefixV10F + "deleteDirectIds.Count"))
deleteGlobalSeen: \(ghostBaseRawDefaultsV10F.integer(forKey: ghostBaseRawPrefixV10F + "deleteGlobalSeen.Count"))
deleteGlobalIds: \(ghostBaseRawDefaultsV10F.integer(forKey: ghostBaseRawPrefixV10F + "deleteGlobalIds.Count"))
deleteSnapshotHit: \(ghostBaseRawDefaultsV10F.integer(forKey: ghostBaseRawPrefixV10F + "deleteSnapshotHit.Count"))
deleteSnapshotMiss: \(ghostBaseRawDefaultsV10F.integer(forKey: ghostBaseRawPrefixV10F + "deleteSnapshotMiss.Count"))
deleteGlobalSnapshotHit: \(ghostBaseRawDefaultsV10F.integer(forKey: ghostBaseRawPrefixV10F + "deleteGlobalSnapshotHit.Count"))
deleteGlobalSnapshotMiss: \(ghostBaseRawDefaultsV10F.integer(forKey: ghostBaseRawPrefixV10F + "deleteGlobalSnapshotMiss.Count"))
deleteGlobalResolverSeen: \(ghostBaseRawDefaultsV10F.integer(forKey: ghostBaseRawPrefixV10F + "deleteGlobalResolverSeen.Count"))
deleteGlobalResolvedIds: \(ghostBaseRawDefaultsV10F.integer(forKey: ghostBaseRawPrefixV10F + "deleteGlobalResolvedIds.Count"))
deleteGlobalResolverMiss: \(ghostBaseRawDefaultsV10F.integer(forKey: ghostBaseRawPrefixV10F + "deleteGlobalResolverMiss.Count"))
deleteResolvedCurrentText: \(ghostBaseRawDefaultsV10F.integer(forKey: ghostBaseRawPrefixV10F + "deleteResolvedCurrentText.Count"))
fetchRaceStarted: \(ghostBaseRawDefaultsV10F.integer(forKey: ghostBaseRawPrefixV10F + "fetchRaceStarted.Count"))
fetchRaceIds: \(ghostBaseRawDefaultsV10F.integer(forKey: ghostBaseRawPrefixV10F + "fetchRaceIds.Count"))
fetchRaceResponse: \(ghostBaseRawDefaultsV10F.integer(forKey: ghostBaseRawPrefixV10F + "fetchRaceResponse.Count"))
fetchRaceEmpty: \(ghostBaseRawDefaultsV10F.integer(forKey: ghostBaseRawPrefixV10F + "fetchRaceEmpty.Count"))
fetchRaceWithText: \(ghostBaseRawDefaultsV10F.integer(forKey: ghostBaseRawPrefixV10F + "fetchRaceWithText.Count"))
fetchRaceStoreMessage: \(ghostBaseRawDefaultsV10F.integer(forKey: ghostBaseRawPrefixV10F + "fetchRaceStoreMessage.Count"))
fetchRaceError: \(ghostBaseRawDefaultsV10F.integer(forKey: ghostBaseRawPrefixV10F + "fetchRaceError.Count"))
fetchShapeSeen: \(ghostBaseRawDefaultsV10F.integer(forKey: ghostBaseRawPrefixV10F + "fetchShapeSeen.Count"))
fetchShapeMessage: \(ghostBaseRawDefaultsV10F.integer(forKey: ghostBaseRawPrefixV10F + "fetchShapeMessage.Count"))
fetchShapeMessageEmpty: \(ghostBaseRawDefaultsV10F.integer(forKey: ghostBaseRawPrefixV10F + "fetchShapeMessageEmpty.Count"))
fetchShapeMessageService: \(ghostBaseRawDefaultsV10F.integer(forKey: ghostBaseRawPrefixV10F + "fetchShapeMessageService.Count"))
historyProbeStarted: \(ghostBaseRawDefaultsV10F.integer(forKey: ghostBaseRawPrefixV10F + "historyProbeStarted.Count"))
historyProbeInputIds: \(ghostBaseRawDefaultsV10F.integer(forKey: ghostBaseRawPrefixV10F + "historyProbeInputIds.Count"))
historyProbeChatListResponse: \(ghostBaseRawDefaultsV10F.integer(forKey: ghostBaseRawPrefixV10F + "historyProbeChatListResponse.Count"))
historyProbeCandidatePeers: \(ghostBaseRawDefaultsV10F.integer(forKey: ghostBaseRawPrefixV10F + "historyProbeCandidatePeers.Count"))
historyProbeNoCandidates: \(ghostBaseRawDefaultsV10F.integer(forKey: ghostBaseRawPrefixV10F + "historyProbeNoCandidates.Count"))
historyProbePeerTried: \(ghostBaseRawDefaultsV10F.integer(forKey: ghostBaseRawPrefixV10F + "historyProbePeerTried.Count"))
historyProbeResponse: \(ghostBaseRawDefaultsV10F.integer(forKey: ghostBaseRawPrefixV10F + "historyProbeResponse.Count"))
historyProbeEmpty: \(ghostBaseRawDefaultsV10F.integer(forKey: ghostBaseRawPrefixV10F + "historyProbeEmpty.Count"))
historyProbeMessage: \(ghostBaseRawDefaultsV10F.integer(forKey: ghostBaseRawPrefixV10F + "historyProbeMessage.Count"))
historyProbeMessageEmpty: \(ghostBaseRawDefaultsV10F.integer(forKey: ghostBaseRawPrefixV10F + "historyProbeMessageEmpty.Count"))
historyProbeMessageService: \(ghostBaseRawDefaultsV10F.integer(forKey: ghostBaseRawPrefixV10F + "historyProbeMessageService.Count"))
historyProbeExactId: \(ghostBaseRawDefaultsV10F.integer(forKey: ghostBaseRawPrefixV10F + "historyProbeExactId.Count"))
historyProbeExactEmptyId: \(ghostBaseRawDefaultsV10F.integer(forKey: ghostBaseRawPrefixV10F + "historyProbeExactEmptyId.Count"))
historyProbeWithText: \(ghostBaseRawDefaultsV10F.integer(forKey: ghostBaseRawPrefixV10F + "historyProbeWithText.Count"))
historyProbeError: \(ghostBaseRawDefaultsV10F.integer(forKey: ghostBaseRawPrefixV10F + "historyProbeError.Count"))
LastSnapshotSource: \(ghostBaseRawDefaultsV10F.string(forKey: ghostBaseRawPrefixV10F + "LastSnapshotSource") ?? "none")
LastSnapshotKey: \(ghostBaseRawDefaultsV10F.string(forKey: ghostBaseRawPrefixV10F + "LastSnapshotKey") ?? "none")
LastSnapshotGlobalId: \(ghostBaseRawDefaultsV10F.string(forKey: ghostBaseRawPrefixV10F + "LastSnapshotGlobalId") ?? "none")
LastSnapshotText: \(ghostBaseRawDefaultsV10F.string(forKey: ghostBaseRawPrefixV10F + "LastSnapshotText") ?? "none")
LastDeleteSource: \(ghostBaseRawDefaultsV10F.string(forKey: ghostBaseRawPrefixV10F + "LastDeleteSource") ?? "none")
LastDeleteIdsCount: \(ghostBaseRawDefaultsV10F.string(forKey: ghostBaseRawPrefixV10F + "LastDeleteIdsCount") ?? "none")
LastDeleteGlobalIdsCount: \(ghostBaseRawDefaultsV10F.string(forKey: ghostBaseRawPrefixV10F + "LastDeleteGlobalIdsCount") ?? "none")
LastDeleteGlobalInputIdsCount: \(ghostBaseRawDefaultsV10F.string(forKey: ghostBaseRawPrefixV10F + "LastDeleteGlobalInputIdsCount") ?? "none")
LastDeleteGlobalResolvedIdsCount: \(ghostBaseRawDefaultsV10F.string(forKey: ghostBaseRawPrefixV10F + "LastDeleteGlobalResolvedIdsCount") ?? "none")
LastDeleteResolvedKey: \(ghostBaseRawDefaultsV10F.string(forKey: ghostBaseRawPrefixV10F + "LastDeleteResolvedKey") ?? "none")
LastDeleteResolvedText: \(ghostBaseRawDefaultsV10F.string(forKey: ghostBaseRawPrefixV10F + "LastDeleteResolvedText") ?? "none")
LastFetchRaceSource: \(ghostBaseRawDefaultsV10F.string(forKey: ghostBaseRawPrefixV10F + "LastFetchRaceSource") ?? "none")
LastFetchRaceIdsCount: \(ghostBaseRawDefaultsV10F.string(forKey: ghostBaseRawPrefixV10F + "LastFetchRaceIdsCount") ?? "none")
LastFetchRaceApiMessageCount: \(ghostBaseRawDefaultsV10F.string(forKey: ghostBaseRawPrefixV10F + "LastFetchRaceApiMessageCount") ?? "none")
LastFetchRaceMessageKey: \(ghostBaseRawDefaultsV10F.string(forKey: ghostBaseRawPrefixV10F + "LastFetchRaceMessageKey") ?? "none")
LastFetchRaceText: \(ghostBaseRawDefaultsV10F.string(forKey: ghostBaseRawPrefixV10F + "LastFetchRaceText") ?? "none")
LastFetchRaceError: \(ghostBaseRawDefaultsV10F.string(forKey: ghostBaseRawPrefixV10F + "LastFetchRaceError") ?? "none")
LastFetchShapeSource: \(ghostBaseRawDefaultsV10F.string(forKey: ghostBaseRawPrefixV10F + "LastFetchShapeSource") ?? "none")
LastFetchShapeCase: \(ghostBaseRawDefaultsV10F.string(forKey: ghostBaseRawPrefixV10F + "LastFetchShapeCase") ?? "none")
LastFetchShapeId: \(ghostBaseRawDefaultsV10F.string(forKey: ghostBaseRawPrefixV10F + "LastFetchShapeId") ?? "none")
LastFetchShapeFlags: \(ghostBaseRawDefaultsV10F.string(forKey: ghostBaseRawPrefixV10F + "LastFetchShapeFlags") ?? "none")
LastFetchShapeFlags2: \(ghostBaseRawDefaultsV10F.string(forKey: ghostBaseRawPrefixV10F + "LastFetchShapeFlags2") ?? "none")
LastFetchShapePeer: \(ghostBaseRawDefaultsV10F.string(forKey: ghostBaseRawPrefixV10F + "LastFetchShapePeer") ?? "none")
LastFetchShapeFrom: \(ghostBaseRawDefaultsV10F.string(forKey: ghostBaseRawPrefixV10F + "LastFetchShapeFrom") ?? "none")
LastFetchShapeDate: \(ghostBaseRawDefaultsV10F.string(forKey: ghostBaseRawPrefixV10F + "LastFetchShapeDate") ?? "none")
LastFetchShapeTextLength: \(ghostBaseRawDefaultsV10F.string(forKey: ghostBaseRawPrefixV10F + "LastFetchShapeTextLength") ?? "none")
LastFetchShapeTextPreview: \(ghostBaseRawDefaultsV10F.string(forKey: ghostBaseRawPrefixV10F + "LastFetchShapeTextPreview") ?? "none")
LastFetchShapeMedia: \(ghostBaseRawDefaultsV10F.string(forKey: ghostBaseRawPrefixV10F + "LastFetchShapeMedia") ?? "none")
LastFetchShapeAction: \(ghostBaseRawDefaultsV10F.string(forKey: ghostBaseRawPrefixV10F + "LastFetchShapeAction") ?? "none")
LastHistoryProbeInputIdsCount: \(ghostBaseRawDefaultsV10F.string(forKey: ghostBaseRawPrefixV10F + "LastHistoryProbeInputIdsCount") ?? "none")
LastHistoryProbeStateCandidateCount: \(ghostBaseRawDefaultsV10F.string(forKey: ghostBaseRawPrefixV10F + "LastHistoryProbeStateCandidateCount") ?? "none")
LastHistoryProbeChatListCount: \(ghostBaseRawDefaultsV10F.string(forKey: ghostBaseRawPrefixV10F + "LastHistoryProbeChatListCount") ?? "none")
LastHistoryProbeCandidateCount: \(ghostBaseRawDefaultsV10F.string(forKey: ghostBaseRawPrefixV10F + "LastHistoryProbeCandidateCount") ?? "none")
LastHistoryProbeCandidatePeers: \(ghostBaseRawDefaultsV10F.string(forKey: ghostBaseRawPrefixV10F + "LastHistoryProbeCandidatePeers") ?? "none")
LastHistoryProbePeer: \(ghostBaseRawDefaultsV10F.string(forKey: ghostBaseRawPrefixV10F + "LastHistoryProbePeer") ?? "none")
LastHistoryProbeRequestedId: \(ghostBaseRawDefaultsV10F.string(forKey: ghostBaseRawPrefixV10F + "LastHistoryProbeRequestedId") ?? "none")
LastHistoryProbeApiMessageCount: \(ghostBaseRawDefaultsV10F.string(forKey: ghostBaseRawPrefixV10F + "LastHistoryProbeApiMessageCount") ?? "none")
LastHistoryProbeCase: \(ghostBaseRawDefaultsV10F.string(forKey: ghostBaseRawPrefixV10F + "LastHistoryProbeCase") ?? "none")
LastHistoryProbeId: \(ghostBaseRawDefaultsV10F.string(forKey: ghostBaseRawPrefixV10F + "LastHistoryProbeId") ?? "none")
LastHistoryProbePeerFromMessage: \(ghostBaseRawDefaultsV10F.string(forKey: ghostBaseRawPrefixV10F + "LastHistoryProbePeerFromMessage") ?? "none")
LastHistoryProbeDate: \(ghostBaseRawDefaultsV10F.string(forKey: ghostBaseRawPrefixV10F + "LastHistoryProbeDate") ?? "none")
LastHistoryProbeTextLength: \(ghostBaseRawDefaultsV10F.string(forKey: ghostBaseRawPrefixV10F + "LastHistoryProbeTextLength") ?? "none")
LastHistoryProbeText: \(ghostBaseRawDefaultsV10F.string(forKey: ghostBaseRawPrefixV10F + "LastHistoryProbeText") ?? "none")
LastHistoryProbeMedia: \(ghostBaseRawDefaultsV10F.string(forKey: ghostBaseRawPrefixV10F + "LastHistoryProbeMedia") ?? "none")
LastHistoryProbeAction: \(ghostBaseRawDefaultsV10F.string(forKey: ghostBaseRawPrefixV10F + "LastHistoryProbeAction") ?? "none")
LastHistoryProbeError: \(ghostBaseRawDefaultsV10F.string(forKey: ghostBaseRawPrefixV10F + "LastHistoryProbeError") ?? "none")

TestEpoch: \(ghostBaseRawDefaultsV10F.string(forKey: ghostBaseRawPrefixV10F + "TestEpoch") ?? "none")
EpochStartedAt: \(ghostBaseRawDefaultsV10F.string(forKey: ghostBaseRawPrefixV10F + "EpochStartedAt") ?? "none")
ResetMode: \(ghostBaseRawDefaultsV10F.string(forKey: ghostBaseRawPrefixV10F + "ResetMode") ?? "none")

Timeline:
\(ghostBaseRawDefaultsV10F.string(forKey: ghostBaseRawPrefixV10F + "Timeline") ?? "none")

LastDeleteSnapshotKey: \(ghostBaseRawDefaultsV10F.string(forKey: ghostBaseRawPrefixV10F + "LastDeleteSnapshotKey") ?? "none")
LastDeleteSnapshotText: \(ghostBaseRawDefaultsV10F.string(forKey: ghostBaseRawPrefixV10F + "LastDeleteSnapshotText") ?? "none")
LastDeleteSnapshotTexts: \(ghostBaseRawDefaultsV10F.string(forKey: ghostBaseRawPrefixV10F + "LastDeleteSnapshotTexts") ?? "none")
"""))

    let ghostBaseCorePrefix = "jerkgram.V10B.Core."
    let ghostBaseCoreDefaults = UserDefaults.standard
    let ghostBaseCoreTotal = ghostBaseCoreDefaults.integer(forKey: ghostBaseCorePrefix + "Total")
    let ghostBaseCoreLast = ghostBaseCoreDefaults.string(forKey: ghostBaseCorePrefix + "Last") ?? "none"
    let ghostBaseCoreLastTime = ghostBaseCoreDefaults.integer(forKey: ghostBaseCorePrefix + "LastTime")

    entries.append(.info(debug, """
Core Difference Probe:
Total: \(ghostBaseCoreTotal)
Last: \(ghostBaseCoreLast) @ \(ghostBaseCoreLastTime)
newMessage: \(ghostBaseCoreDefaults.integer(forKey: ghostBaseCorePrefix + "newMessage.Count"))
deleteMessages: \(ghostBaseCoreDefaults.integer(forKey: ghostBaseCorePrefix + "deleteMessages.Count"))
editMessage: \(ghostBaseCoreDefaults.integer(forKey: ghostBaseCorePrefix + "editMessage.Count"))
newChannelMessage: \(ghostBaseCoreDefaults.integer(forKey: ghostBaseCorePrefix + "newChannelMessage.Count"))
deleteChannelMessages: \(ghostBaseCoreDefaults.integer(forKey: ghostBaseCorePrefix + "deleteChannelMessages.Count"))
editChannelMessage: \(ghostBaseCoreDefaults.integer(forKey: ghostBaseCorePrefix + "editChannelMessage.Count"))
"""))

    entries.append(.info(debug, """
Telegram ID: \(telegramId)
Bundle ID: \(bundleId)
AppGroup: group.ph.telegra.Telegraph
Base: Official Telegram 12.9.2
KeychainFix: sideloadKeychainFix.dylib
Version: v1.1G-unified-recovery
"""))

    entries.append(.info(footer, "Profile Blur settings apply when a profile is opened. Activity Ghost hides typing, recording, uploading, sticker, game and emoji activity when enabled. v0.5C adds a lower-layer activity guard. Hide Online is active in v0.6A. Read Ghost is active in v0.6B. Read Ghost Extras are active in v0.6C. Scheduled Send is active in v0.7D. Protected Content controls and Internal ShareController Scheduled Send are active in v0.8C."))

    if page == .debugResearch {
        return entries.filter {
            $0.section == debug
        }
    }

    return entries
}

public func ghostBaseSettingsController(
    context: AccountContext
) -> ViewController {
    let rawPage = UserDefaults.standard.string(
        forKey: "jerkgram.Settings.InitialPage"
    ) ?? "home"

    UserDefaults.standard.removeObject(
        forKey: "jerkgram.Settings.InitialPage"
    )

    let page: GhostBaseSettingsPage

    switch rawPage {
    case "ghostMode":
        page = .ghostMode
    case "messages":
        page = .messages
    case "protectedContent":
        page = .protectedContent
    case "mediaStories":
        page = .mediaStories
    case "appearance":
        page = .appearance
    case "debugResearch":
        page = .debugResearch
    case "about":
        page = .about
    default:
        page = .home
    }

    return ghostBaseSettingsPageController(
        context: context,
        page: page
    )
}

// MARK: GhostBase v1.0W native send style page
private final class GhostBaseSendStylePageArguments {
    let select: (String) -> Void

    init(select: @escaping (String) -> Void) {
        self.select = select
    }
}

private enum GhostBaseSendStylePageEntry: ItemListNodeEntry {
    case option(Int32, String, String, Bool)

    var section: ItemListSectionId {
        return 0
    }

    var stableId: Int32 {
        switch self {
        case let .option(index, _, _, _):
            return index
        }
    }

    static func ==(
        lhs: GhostBaseSendStylePageEntry,
        rhs: GhostBaseSendStylePageEntry
    ) -> Bool {
        switch (lhs, rhs) {
        case let (
            .option(li, lv, lt, ls),
            .option(ri, rv, rt, rs)
        ):
            return li == ri
                && lv == rv
                && lt == rt
                && ls == rs
        }
    }

    static func <(
        lhs: GhostBaseSendStylePageEntry,
        rhs: GhostBaseSendStylePageEntry
    ) -> Bool {
        return lhs.stableId < rhs.stableId
    }

    func item(
        presentationData: ItemListPresentationData,
        arguments: Any
    ) -> ListViewItem {
        let arguments =
            arguments as! GhostBaseSendStylePageArguments

        switch self {
        case let .option(_, value, title, selected):
            return ItemListDisclosureItem(
                presentationData: presentationData,
                systemStyle: .glass,
                title: "",
                attributedTitle: ghostBaseSendStyleAttributedText(
                    style: value,
                    text: title,
                    color:
                        presentationData.theme.list.itemPrimaryTextColor,
                    size: 17.0
                ),
                label: selected ? "✓" : "",
                labelStyle: .text,
                sectionId: self.section,
                style: .blocks,
                disclosureStyle: .none,
                action: {
                    arguments.select(value)
                }
            )
        }
    }
}

private func ghostBaseSendStylePageEntries(
    selected: String,
    strings: JerkgramStrings
) -> [GhostBaseSendStylePageEntry] {
    let styles: [(String, String)] = [
        ("normal", strings.sendStyleNormal),
        ("bold", strings.sendStyleBold),
        ("italic", strings.sendStyleItalic),
        ("monospace", strings.sendStyleMonospace),
        ("strikethrough", strings.sendStyleStrikethrough),
        ("underline", strings.sendStyleUnderline),
        ("spoiler", strings.sendStyleSpoiler)
    ]

    return styles.enumerated().map { index, item in
        return .option(
            Int32(index),
            item.0,
            item.1,
            selected == item.0
        )
    }
}

private func ghostBaseSendStylePageController(
    context: AccountContext,
    selected: String,
    select: @escaping (String) -> Void
) -> ViewController {
    let selectedValue = Atomic(value: selected)
    let selectedPromise = ValuePromise(
        selected,
        ignoreRepeated: true
    )

    let arguments = GhostBaseSendStylePageArguments(
        select: { value in
            let updated = selectedValue.modify { _ in value }
            selectedPromise.set(updated)
            select(value)
        }
    )

    let signal = combineLatest(
        context.sharedContext.presentationData,
        selectedPromise.get()
    )
    |> deliverOnMainQueue
    |> map { presentationData, value
        -> (ItemListControllerState, (ItemListNodeState, Any)) in

        let itemPresentationData =
            ItemListPresentationData(presentationData)

        let controllerState = ItemListControllerState(
            presentationData: itemPresentationData,
            title: .text(presentationData.strings.jerkgram.sendStyle),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(
                title: presentationData.strings.Common_Back
            ),
            animateChanges: false
        )

        let listState = ItemListNodeState(
            presentationData: itemPresentationData,
            entries: ghostBaseSendStylePageEntries(
                selected: value,
                strings: presentationData.strings.jerkgram
            ),
            style: .blocks,
            ensureVisibleItemTag: nil,
            emptyStateItem: nil,
            animateChanges: false
        )

        return (
            controllerState,
            (listState, arguments as Any)
        )
    }

    return ItemListController(
        context: context,
        state: signal
    )
}

private func ghostBaseSettingsPageController(
    context: AccountContext,
    page: GhostBaseSettingsPage
) -> ViewController {
    let initialState = GhostBaseSettingsState.load(accountPeerId: context.account.peerId.toInt64())

    jerkgramProjectActiveSettings(accountPeerId: context.account.peerId.toInt64(), state: initialState)
    let statePromise = ValuePromise(initialState, ignoreRepeated: false)
    let stateValue = Atomic(value: initialState)
    let accountPeerId = context.account.peerId.toInt64()
    let jerkgramImportRefreshSignal = jerkgramSettingsImportRefreshSignal(
        accountPeerId: accountPeerId,
        reload: {
            let refreshed = GhostBaseSettingsState.load(accountPeerId: accountPeerId)
            _ = stateValue.modify { _ in refreshed }
            statePromise.set(refreshed)
        }
    )
    // Retain the import observer through the controller's existing state
    // subscription without changing the arity or closure shape of whatever
    // combineLatest the release chain already uses.
    let jerkgramImportRefreshStateSignal = combineLatest(
        statePromise.get(),
        jerkgramImportRefreshSignal
    )
    |> map { (state: GhostBaseSettingsState, _: Void) -> GhostBaseSettingsState in state }

    let updateState: ((GhostBaseSettingsState) -> GhostBaseSettingsState) -> Void = { f in
        let updated = stateValue.modify { current in
            let next = f(current)

            let ghostBaseVisualSettingsChanged =
                current.glassEnabled != next.glassEnabled
                || current.profileAvatarBlur != next.profileAvatarBlur
                || current.profileAnimatedBackground != next.profileAnimatedBackground
                || current.profileBlurTint != next.profileBlurTint
                || current.profileBlurReduced != next.profileBlurReduced

            jerkgramPersistChangedSettings(
                accountPeerId: context.account.peerId.toInt64(),
                previous: current,
                current: next
            )

            if ghostBaseVisualSettingsChanged {
                NotificationCenter.default.post(
                    name: Notification.Name(
                        "jerkgram.ProfileVisualSettingsDidChange.V11M"
                    ),
                    object: nil
                )
            }

            return next
        }

        statePromise.set(updated)
    }

    var pushController: ((ViewController) -> Void)?

    var openSendTextStyleImpl: (() -> Void)?

    let ghostBaseHiddenGiftsDisposable = MetaDisposable()
    let ghostBaseBotCapabilityDisposable = MetaDisposable()
    let ghostBaseBotDifferenceDisposable = MetaDisposable()
    let ghostBaseProfileIntelDisposable = MetaDisposable()
    let ghostBaseProfileIntel2Disposable = MetaDisposable()

    let ghostBaseHiddenGiftFormDisposable = MetaDisposable()
    let ghostBaseHiddenGiftPaymentDisposable = MetaDisposable()

    let refreshResearchPage: () -> Void = {
        statePromise.set(stateValue.with { $0 })
    }

    let runHiddenGiftsProbe: (
        EnginePeer.Id,
        String
    ) -> Void = { targetPeerId, targetLabel in
        let defaults = UserDefaults.standard

        defaults.set(
            "running",
            forKey: ghostBaseHiddenGiftsPrefix + "Status"
        )
        defaults.set(
            targetLabel,
            forKey: ghostBaseHiddenGiftsPrefix + "Target"
        )
        defaults.set(
            "",
            forKey: ghostBaseHiddenGiftsPrefix + "Report"
        )
        refreshResearchPage()

        let catalogSignal =
            context.engine.payments
            .ghostBaseFetchStarGiftsCatalogDirect()

        ghostBaseHiddenGiftsDisposable.set((
            catalogSignal
            |> mapToSignal {
                catalogResult -> Signal<[String], NoError> in

                var catalogById: [
                    Int64: (index: Int, gift: StarGift.Gift)
                ] = [:]

                let catalogHeader: String

                switch catalogResult {
                case let .catalog(list):
                    catalogHeader = """
                    DIRECT_CATALOG: success
                    hash: \(list.hashValue)
                    totalItems: \(list.items.count)
                    """

                    for (index, item) in list.items.enumerated() {
                        if case let .generic(gift) = item {
                            catalogById[gift.id] = (
                                index: index,
                                gift: gift
                            )
                        }
                    }

                case .notModified:
                    catalogHeader = """
                    DIRECT_CATALOG: notModified
                    hashRequested: 0
                    """

                case let .failed(error):
                    catalogHeader = """
                    DIRECT_CATALOG: failed
                    error: \(error)
                    """
                }

                let signals: [Signal<String, NoError>] =
                    ghostBaseHiddenGiftItems.map { name, giftId in

                        let checkSignal =
                            context.engine.payments
                            .checkCanSendStarGift(giftId: giftId)
                            |> map {
                                ghostBaseHiddenGiftCheckText($0)
                            }

                        let formProbe: (
                            Bool
                        ) -> Signal<
                            GhostBaseHiddenGiftFormProbeResult,
                            NoError
                        > = { includeUpgrade in
                            return context.engine.payments
                            .fetchBotPaymentForm(
                                source: .starGift(
                                    hideName: false,
                                    includeUpgrade: includeUpgrade,
                                    peerId: targetPeerId,
                                    giftId: giftId,
                                    text: nil,
                                    entities: nil
                                ),
                                themeParams: nil
                            )
                            |> map { form in
                                let prices =
                                    form.invoice.prices.map {
                                        "\($0.label)=\($0.amount)"
                                    }.joined(separator: ", ")

                                let total =
                                    form.invoice.prices.reduce(
                                        Int64(0),
                                        { $0 + $1.amount }
                                    )

                                let paymentBot =
                                    form.paymentBotId.map {
                                        String(describing: $0)
                                    } ?? "nil"

                                let provider =
                                    form.providerId.map {
                                        String(describing: $0)
                                    } ?? "nil"

                                let nativeProvider =
                                    form.nativeProvider?.name ?? "nil"

                                return GhostBaseHiddenGiftFormProbeResult(
                                    total: total,
                                    text: """
                                    success
                                    formId: \(form.id)
                                    currency: \(form.invoice.currency)
                                    total: \(total)
                                    prices: \(prices)
                                    isTest: \(form.invoice.isTest)
                                    passwordMissing: \(form.passwordMissing)
                                    canSaveCredentials: \(form.canSaveCredentials)
                                    paymentBotId: \(paymentBot)
                                    providerId: \(provider)
                                    nativeProvider: \(nativeProvider)
                                    urlPresent: \(form.url != nil)
                                    additionalMethods: \(form.additionalPaymentMethods.count)
                                    """
                                )
                            }
                            |> `catch` {
                                error -> Signal<
                                    GhostBaseHiddenGiftFormProbeResult,
                                    NoError
                                > in

                                return .single(
                                    GhostBaseHiddenGiftFormProbeResult(
                                        total: nil,
                                        text:
                                            ghostBaseHiddenGiftPaymentErrorText(
                                                error
                                            )
                                    )
                                )
                            }
                        }

                        let plainForm = formProbe(false)
                        let upgradedForm = formProbe(true)

                        return combineLatest(
                            checkSignal,
                            plainForm,
                            upgradedForm
                        )
                        |> map { check, plain, upgraded in
                            let catalogText: String

                            if let entry = catalogById[giftId] {
                                catalogText =
                                    ghostBaseHiddenGiftCatalogText(
                                        index: entry.index,
                                        gift: entry.gift
                                    )
                            } else {
                                catalogText = "catalog: absent"
                            }

                            let delta: String
                            if let plainTotal = plain.total,
                               let upgradedTotal = upgraded.total {
                                delta = String(
                                    upgradedTotal - plainTotal
                                )
                            } else {
                                delta = "n/a"
                            }

                            return """
                            \(name)
                            giftId: \(giftId)
                            \(catalogText)
                            checkCanSendGift: \(check)

                            plainForm:
                            \(plain.text)

                            includeUpgradeForm:
                            \(upgraded.text)

                            upgradeDelta: \(delta)
                            """
                        }
                    }

                return combineLatest(signals)
                |> map { lines in
                    return [catalogHeader] + lines
                }
            }
            |> deliverOnMainQueue
        ).start(next: { lines in
            defaults.set(
                "completed",
                forKey: ghostBaseHiddenGiftsPrefix + "Status"
            )
            defaults.set(
                lines.joined(separator: "\n\n"),
                forKey: ghostBaseHiddenGiftsPrefix + "Report"
            )
            defaults.set(
                ISO8601DateFormatter().string(from: Date()),
                forKey: ghostBaseHiddenGiftsPrefix + "Updated"
            )
            refreshResearchPage()
        }))
    }

    let selectHiddenGiftForSend: (
        Int
    ) -> Void = { index in
        guard !ghostBaseHiddenGiftSendState.isSending else {
            return
        }

        guard index >= 0,
              index < ghostBaseHiddenGiftItems.count else {
            ghostBaseHiddenGiftSendState.status =
                "Ошибка: индекс подарка вне диапазона."
            refreshResearchPage()
            return
        }

        let item = ghostBaseHiddenGiftItems[index]

        ghostBaseHiddenGiftSendState.giftName = item.0
        ghostBaseHiddenGiftSendState.giftId = item.1
        ghostBaseHiddenGiftSendState.firstConfirmed = false
        ghostBaseHiddenGiftSendState.status =
            "Подарок выбран: \(item.0), ID \(item.1)."

        refreshResearchPage()
    }

    let runHiddenGiftRealSend: () -> Void = {
        guard !ghostBaseHiddenGiftSendState.isSending else {
            return
        }

        guard ghostBaseHiddenGiftSendState.firstConfirmed,
              let giftName =
                ghostBaseHiddenGiftSendState.giftName,
              let giftId =
                ghostBaseHiddenGiftSendState.giftId,
              let targetPeerId =
                ghostBaseHiddenGiftSendState.targetPeerId else {
            ghostBaseHiddenGiftSendState.status =
                "Отправка заблокирована: нет полного подтверждения."
            refreshResearchPage()
            return
        }

        let hideName =
            ghostBaseHiddenGiftSendState.hideName

        let source: BotPaymentInvoiceSource = .starGift(
            hideName: hideName,
            includeUpgrade: false,
            peerId: targetPeerId,
            giftId: giftId,
            text: nil,
            entities: nil
        )

        ghostBaseHiddenGiftSendState.isSending = true
        ghostBaseHiddenGiftSendState.status =
            "Повторно получаем платёжную форму для \(giftName)…"
        refreshResearchPage()

        ghostBaseHiddenGiftFormDisposable.set((
            context.engine.payments.fetchBotPaymentForm(
                source: source,
                themeParams: nil
            )
            |> take(1)
            |> deliverOnMainQueue
        ).start(
            next: { form in
                let total = form.invoice.prices.reduce(
                    Int64(0),
                    { current, price in
                        current + price.amount
                    }
                )

                guard form.invoice.currency == "XTR" else {
                    ghostBaseHiddenGiftSendState.isSending = false
                    ghostBaseHiddenGiftSendState.firstConfirmed = false
                    ghostBaseHiddenGiftSendState.status =
                        "ОТМЕНЕНО: currency=\(form.invoice.currency), ожидалось XTR."
                    refreshResearchPage()
                    return
                }

                guard total == 50 else {
                    ghostBaseHiddenGiftSendState.isSending = false
                    ghostBaseHiddenGiftSendState.firstConfirmed = false
                    ghostBaseHiddenGiftSendState.status =
                        "ОТМЕНЕНО: сервер запросил \(total) Stars вместо 50."
                    refreshResearchPage()
                    return
                }

                guard !form.invoice.isTest else {
                    ghostBaseHiddenGiftSendState.isSending = false
                    ghostBaseHiddenGiftSendState.firstConfirmed = false
                    ghostBaseHiddenGiftSendState.status =
                        "ОТМЕНЕНО: сервер вернул тестовую форму."
                    refreshResearchPage()
                    return
                }

                ghostBaseHiddenGiftSendState.status =
                    "Форма подтверждена: 50 XTR. Выполняется единственный payment RPC."
                refreshResearchPage()

                ghostBaseHiddenGiftPaymentDisposable.set((
                    context.engine.payments.sendStarsPaymentForm(
                        formId: form.id,
                        source: source
                    )
                    |> take(1)
                    |> deliverOnMainQueue
                ).start(
                    next: { result in
                        ghostBaseHiddenGiftSendState.isSending = false
                        ghostBaseHiddenGiftSendState.firstConfirmed = false
                        ghostBaseHiddenGiftSendState.status =
                            ghostBaseHiddenGiftSendResultText(result)
                        refreshResearchPage()
                    },
                    error: { error in
                        ghostBaseHiddenGiftSendState.isSending = false
                        ghostBaseHiddenGiftSendState.firstConfirmed = false
                        ghostBaseHiddenGiftSendState.status =
                            "PAYMENT ERROR: "
                            + ghostBaseHiddenGiftSendErrorText(error)
                        refreshResearchPage()
                    }
                ))
            },
            error: { error in
                ghostBaseHiddenGiftSendState.isSending = false
                ghostBaseHiddenGiftSendState.firstConfirmed = false
                ghostBaseHiddenGiftSendState.status =
                    "FORM ERROR: "
                    + ghostBaseHiddenGiftPaymentErrorText(error)
                refreshResearchPage()
            }
        ))
    }

    let aboutChannelSignal = jerkgramAboutChannelState(
        context: context,
        enabled: page == .about,
        username: "JerkgramApp"
    )
    let aboutCommunitySignal = jerkgramAboutChannelState(
        context: context,
        enabled: page == .about,
        username: "JerkgramCommunity"
    )
    var openAboutChannelImpl: ((EnginePeer) -> Void)?

    let arguments = GhostBaseSettingsArguments(
        context: context,
        openAboutChannel: { peer in
            openAboutChannelImpl?(peer)
        },
        runResearchAction: { action in
            switch action {
            case "copyExtensionDiagnostics":
                UIPasteboard.general.string = BuildConfig.jerkgramExtensionDiagnosticsReport()

            case "hiddenGiftsSelf":
                runHiddenGiftsProbe(
                    context.account.peerId,
                    "self: \(String(describing: context.account.peerId))"
                )

            case "hiddenGiftsOther":
                let controller =
                    context.sharedContext.makePeerSelectionController(
                        PeerSelectionControllerParams(
                            context: context,
                            filter: [
                                .onlyPrivateChats,
                                .excludeSavedMessages,
                                .removeSearchHeader,
                                .excludeRecent,
                                .doNotSearchMessages
                            ],
                            title: "Получатель Hidden Gifts"
                        )
                    )

                controller.peerSelected = {
                    [weak controller] peer, _ in
                    controller?.dismiss()
                    runHiddenGiftsProbe(
                        peer.id,
                        "user: \(String(describing: peer.id))"
                    )
                }

                pushController?(controller)

            case "hiddenGiftSendSelect0":
                selectHiddenGiftForSend(0)

            case "hiddenGiftSendSelect1":
                selectHiddenGiftForSend(1)

            case "hiddenGiftSendSelect2":
                selectHiddenGiftForSend(2)

            case "hiddenGiftSendSelect3":
                selectHiddenGiftForSend(3)

            case "hiddenGiftSendSelect4":
                selectHiddenGiftForSend(4)

            case "hiddenGiftSendSelect5":
                selectHiddenGiftForSend(5)

            case "hiddenGiftSendSelect6":
                selectHiddenGiftForSend(6)

            case "hiddenGiftSendSelect7":
                selectHiddenGiftForSend(7)

            case "hiddenGiftSendSelect8":
                selectHiddenGiftForSend(8)

            case "hiddenGiftSendSelf":
                guard !ghostBaseHiddenGiftSendState.isSending else {
                    break
                }

                ghostBaseHiddenGiftSendState.targetPeerId =
                    context.account.peerId
                ghostBaseHiddenGiftSendState.targetLabel =
                    "self: \(String(describing: context.account.peerId))"
                ghostBaseHiddenGiftSendState.firstConfirmed = false
                ghostBaseHiddenGiftSendState.status =
                    "Получатель выбран: собственный аккаунт."
                refreshResearchPage()

            case "hiddenGiftSendToggleHideName":
                guard !ghostBaseHiddenGiftSendState.isSending else {
                    break
                }

                ghostBaseHiddenGiftSendState.hideName.toggle()
                ghostBaseHiddenGiftSendState.firstConfirmed = false

                ghostBaseHiddenGiftSendState.status =
                    ghostBaseHiddenGiftSendState.hideName
                    ? "Имя отправителя будет скрыто."
                    : "Имя отправителя будет открыто."

                refreshResearchPage()

            case "hiddenGiftSendRecipient":
                guard !ghostBaseHiddenGiftSendState.isSending else {
                    break
                }

                let controller =
                    context.sharedContext.makePeerSelectionController(
                        PeerSelectionControllerParams(
                            context: context,
                            filter: [
                                .onlyPrivateChats,
                                .excludeSavedMessages,
                                .removeSearchHeader,
                                .excludeRecent,
                                .doNotSearchMessages
                            ],
                            title: "Получатель сезонного подарка"
                        )
                    )

                controller.peerSelected = {
                    [weak controller] peer, _ in
                    controller?.dismiss()

                    ghostBaseHiddenGiftSendState.targetPeerId =
                        peer.id
                    ghostBaseHiddenGiftSendState.targetLabel =
                        "user: \(String(describing: peer.id))"
                    ghostBaseHiddenGiftSendState.firstConfirmed =
                        false
                    ghostBaseHiddenGiftSendState.status =
                        "Получатель выбран: \(String(describing: peer.id))."

                    refreshResearchPage()
                }

                pushController?(controller)

            case "hiddenGiftSendConfirm":
                guard !ghostBaseHiddenGiftSendState.isSending,
                      ghostBaseHiddenGiftSendState.giftId != nil,
                      ghostBaseHiddenGiftSendState.targetPeerId != nil else {
                    ghostBaseHiddenGiftSendState.status =
                        "Сначала выберите подарок и получателя."
                    refreshResearchPage()
                    break
                }

                ghostBaseHiddenGiftSendState.firstConfirmed = true
                ghostBaseHiddenGiftSendState.status =
                    "Первое подтверждение принято. Проверьте данные и нажмите кнопку списания 50 Stars."
                refreshResearchPage()

            case "hiddenGiftSendPay":
                runHiddenGiftRealSend()

            case "hiddenGiftSendReset":
                guard !ghostBaseHiddenGiftSendState.isSending else {
                    break
                }

                ghostBaseHiddenGiftSendState =
                    GhostBaseHiddenGiftSendState()
                refreshResearchPage()

            case "botCapabilityProbe":
                let defaults = UserDefaults.standard

                defaults.set(
                    "running",
                    forKey:
                        ghostBaseBotCapabilityPrefix + "Status"
                )
                defaults.set(
                    "",
                    forKey:
                        ghostBaseBotCapabilityPrefix + "Report"
                )
                refreshResearchPage()

                ghostBaseBotCapabilityDisposable.set((
                    context.engine.peers
                    .ghostBaseBotCapabilityProbe()
                    |> take(1)
                    |> deliverOnMainQueue
                ).start(next: { report in
                    defaults.set(
                        "completed",
                        forKey:
                            ghostBaseBotCapabilityPrefix + "Status"
                    )
                    defaults.set(
                        report,
                        forKey:
                            ghostBaseBotCapabilityPrefix + "Report"
                    )
                    defaults.set(
                        ISO8601DateFormatter()
                            .string(from: Date()),
                        forKey:
                            ghostBaseBotCapabilityPrefix + "Updated"
                    )
                    refreshResearchPage()
                }))

            case "botDifferenceProbe":
                let defaults = UserDefaults.standard

                defaults.set(
                    "running",
                    forKey: ghostBaseBotDifferencePrefix + "Status"
                )
                defaults.set(
                    "",
                    forKey: ghostBaseBotDifferencePrefix + "Report"
                )
                refreshResearchPage()

                ghostBaseBotDifferenceDisposable.set((
                    context.engine.peers
                    .ghostBaseBotDifferenceProbe()
                    |> take(1)
                    |> deliverOnMainQueue
                ).start(next: { report in
                    defaults.set(
                        "completed",
                        forKey:
                            ghostBaseBotDifferencePrefix + "Status"
                    )
                    defaults.set(
                        report,
                        forKey:
                            ghostBaseBotDifferencePrefix + "Report"
                    )
                    defaults.set(
                        ISO8601DateFormatter()
                            .string(from: Date()),
                        forKey:
                            ghostBaseBotDifferencePrefix + "Updated"
                    )
                    refreshResearchPage()
                }))

            case "profileIntel1Probe":
                let defaults = UserDefaults.standard
                let rawTarget = UIPasteboard.general.string ?? ""
                let target = rawTarget.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )

                guard !target.isEmpty else {
                    defaults.set(
                        "failed: clipboard empty",
                        forKey: ghostBaseProfileIntelPrefix + "Status"
                    )
                    refreshResearchPage()
                    break
                }

                if let current = defaults.string(
                    forKey: ghostBaseProfileIntelPrefix + "Report"
                ), !current.isEmpty {
                    defaults.set(
                        current,
                        forKey:
                            ghostBaseProfileIntelPrefix
                            + "PreviousReport"
                    )
                    defaults.set(
                        defaults.string(
                            forKey:
                                ghostBaseProfileIntelPrefix + "Updated"
                        ) ?? "none",
                        forKey:
                            ghostBaseProfileIntelPrefix
                            + "PreviousUpdated"
                    )
                }

                defaults.set(
                    target,
                    forKey: ghostBaseProfileIntelPrefix + "Target"
                )
                defaults.set(
                    "running",
                    forKey: ghostBaseProfileIntelPrefix + "Status"
                )
                defaults.set(
                    "",
                    forKey: ghostBaseProfileIntelPrefix + "Report"
                )
                refreshResearchPage()

                ghostBaseProfileIntelDisposable.set((
                    context.engine.peers
                    .ghostBaseProfileIntelProbe(username: target)
                    |> take(1)
                    |> deliverOnMainQueue
                ).start(next: { report in
                    defaults.set(
                        "completed",
                        forKey:
                            ghostBaseProfileIntelPrefix + "Status"
                    )
                    defaults.set(
                        report,
                        forKey:
                            ghostBaseProfileIntelPrefix + "Report"
                    )
                    defaults.set(
                        ISO8601DateFormatter().string(from: Date()),
                        forKey:
                            ghostBaseProfileIntelPrefix + "Updated"
                    )
                    refreshResearchPage()
                }))

            case "profileIntel2Snapshot":
                let defaults = UserDefaults.standard
                let rawTarget = UIPasteboard.general.string ?? ""
                let target = rawTarget.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )

                guard !target.isEmpty else {
                    defaults.set(
                        "failed: clipboard empty",
                        forKey: ghostBaseProfileIntel2Prefix + "Status"
                    )
                    refreshResearchPage()
                    break
                }

                defaults.set(
                    target,
                    forKey: ghostBaseProfileIntel2Prefix + "Target"
                )
                defaults.set(
                    "running",
                    forKey: ghostBaseProfileIntel2Prefix + "Status"
                )
                refreshResearchPage()

                ghostBaseProfileIntel2Disposable.set((
                    context.engine.peers
                    .ghostBaseProfileIntel2Snapshot(username: target)
                    |> take(1)
                    |> deliverOnMainQueue
                ).start(next: { report in
                    defaults.set(
                        "completed",
                        forKey: ghostBaseProfileIntel2Prefix + "Status"
                    )
                    defaults.set(
                        report,
                        forKey: ghostBaseProfileIntel2Prefix + "Report"
                    )
                    defaults.set(
                        ISO8601DateFormatter().string(from: Date()),
                        forKey: ghostBaseProfileIntel2Prefix + "Updated"
                    )
                    refreshResearchPage()
                }))

            default:
                break
            }
        },
        updateBool: { key, value in
        updateState { state in
            var updated = state

            switch key {
            case GhostBaseKey.profileEnabled:
                updated.profileEnabled = value
            case GhostBaseKey.showIds:
                updated.showIds = value
                if value {
                    updated.profileEnabled = true
                }
            case GhostBaseKey.showDCs:
                updated.showDCs = value
                if value {
                    updated.profileEnabled = true
                }
            case GhostBaseKey.showRegistration:
                updated.showRegistration = value
                if value {
                    updated.profileEnabled = true
                }

            case GhostBaseKey.saveDeleted:
                updated.saveDeleted = value
            case GhostBaseKey.showDeleted:
                updated.showDeleted = value
            case GhostBaseKey.saveEditHistory:
                updated.saveEditHistory = value
            case GhostBaseKey.showEditHistory:
                updated.showEditHistory = value

            case GhostBaseKey.glassEnabled:
                updated.glassEnabled = value
                UserDefaults.standard.set(value, forKey: GhostBaseKey.glassEnabled)

            case GhostBaseKey.profileAvatarBlur:
                updated.profileAvatarBlur = value
                UserDefaults.standard.set(value, forKey: GhostBaseKey.profileAvatarBlur)

            case GhostBaseKey.profileAnimatedBackground:
                updated.profileAnimatedBackground = value
            case GhostBaseKey.profileBlurTint:
                updated.profileBlurTint = value
                UserDefaults.standard.set(value, forKey: GhostBaseKey.profileBlurTint)

            case GhostBaseKey.profileBlurReduced:
                updated.profileBlurReduced = value
                UserDefaults.standard.set(value, forKey: GhostBaseKey.profileBlurReduced)

            case GhostBaseKey.deletedPortableReplies:
                updated.deletedPortableReplies = value
                UserDefaults.standard.set(
                    value,
                    forKey: GhostBaseKey.deletedPortableReplies
                )

            case GhostBaseKey.preserveDeletedMedia:
                updated.preserveDeletedMedia = value
                UserDefaults.standard.set(
                    value,
                    forKey: GhostBaseKey.preserveDeletedMedia
                )

            case GhostBaseKey.showRamUnderClock:
                updated.showRamUnderClock = value
                UserDefaults.standard.set(
                    value,
                    forKey: GhostBaseKey.showRamUnderClock
                )

            case GhostBaseKey.messageSeconds:
                updated.messageSeconds = value
                UserDefaults.standard.set(
                    value,
                    forKey: GhostBaseKey.messageSeconds
                )

            case GhostBaseKey.hideOwnPhone:
                updated.hideOwnPhone = value
                UserDefaults.standard.set(
                    value,
                    forKey: GhostBaseKey.hideOwnPhone
                )

            case GhostBaseKey.chatSave:
                updated.chatSave = value
            case GhostBaseKey.chatCopy:
                updated.chatCopy = value
            case GhostBaseKey.chatForward:
                updated.chatForward = value
            case GhostBaseKey.allowScreenshots:
                updated.allowScreenshots = value
            case GhostBaseKey.allowScreenRecording:
                updated.allowScreenRecording = value
            case GhostBaseKey.oneTimeScreenshots:
                updated.oneTimeScreenshots = value
            case GhostBaseKey.oneTimeScreenRecording:
                updated.oneTimeScreenRecording = value
            case GhostBaseKey.oneTimeSave:
                updated.oneTimeSave = value
            case GhostBaseKey.storySave:
                updated.storySave = value
            case GhostBaseKey.localStarsEnabled:
                updated.localStarsEnabled = value
            case GhostBaseKey.readMessages:
                updated.readMessages = value

            case GhostBaseKey.typingActions:
                updated.typingActions = value
            case GhostBaseKey.recordingActions:
                updated.recordingActions = value
            case GhostBaseKey.uploadingActions:
                updated.uploadingActions = value
            case GhostBaseKey.stickerActivity:
                updated.stickerActivity = value
            case GhostBaseKey.gameActivity:
                updated.gameActivity = value
            case GhostBaseKey.emojiActivity:
                updated.emojiActivity = value

            case GhostBaseKey.presence:
                updated.presence = value
                if value {
                    context.account.shouldKeepOnlinePresence.set(.single(false))
                } else {
                    context.account.shouldKeepOnlinePresence.set(.single(false))
                    context.account.shouldKeepOnlinePresence.set(.single(true))
                }

            case GhostBaseKey.scheduledSend:
                updated.scheduledSend = value

            case GhostBaseKey.protectedEnabled:
                // MARK: GhostBase v0.8G protected master cascade
                updated.protectedEnabled = value
                updated.protectedGalleryShare = value
                updated.protectedGallerySave = value
                updated.protectedGalleryCopy = value
                updated.chatSave = value
                updated.chatCopy = value
                updated.chatForward = value
                updated.allowScreenshots = value
                updated.allowScreenRecording = value
                updated.oneTimeScreenshots = value
                updated.oneTimeScreenRecording = value
                updated.oneTimeSave = value
                updated.storySave = value
            case GhostBaseKey.protectedGalleryShare:
                updated.protectedGalleryShare = value
                updated.protectedEnabled = updated.protectedGalleryShare || updated.protectedGallerySave || updated.protectedGalleryCopy

            case GhostBaseKey.protectedGallerySave:
                updated.protectedGallerySave = value
                updated.protectedEnabled = updated.protectedGalleryShare || updated.protectedGallerySave || updated.protectedGalleryCopy

            case GhostBaseKey.protectedGalleryCopy:
                updated.protectedGalleryCopy = value
                updated.protectedEnabled = updated.protectedGalleryShare || updated.protectedGallerySave || updated.protectedGalleryCopy

            default:
                break
            }

            // MARK: GhostBase v0.8G protected child consistency
            if !updated.protectedGalleryShare && !updated.protectedGallerySave && !updated.protectedGalleryCopy && !updated.chatSave && !updated.chatCopy && !updated.chatForward && !updated.allowScreenshots && !updated.allowScreenRecording && !updated.oneTimeScreenshots && !updated.oneTimeScreenRecording && !updated.oneTimeSave && !updated.storySave {
                updated.protectedEnabled = false
            } else if updated.protectedGalleryShare || updated.protectedGallerySave || updated.protectedGalleryCopy || updated.chatSave || updated.chatCopy || updated.chatForward || updated.allowScreenshots || updated.allowScreenRecording || updated.oneTimeScreenshots || updated.oneTimeScreenRecording || updated.oneTimeSave || updated.storySave {
                updated.protectedEnabled = true
            }

            return updated
        }
    }, openPage: { selectedPage in
        if selectedPage == .dataAndBackup {
            pushController?(jerkgramDataAndBackupController(context: context))
        } else if selectedPage == .stars {
            pushController?(jerkgramStarsEditorController(context: context))
        } else {
            pushController?(
                ghostBaseSettingsPageController(
                    context: context,
                    page: selectedPage
                )
            )
        }
    }, openSendTextStyle: {
        openSendTextStyleImpl?()
    })

    let signal = combineLatest(
        context.sharedContext.presentationData,
        jerkgramImportRefreshStateSignal,
        aboutChannelSignal,
        aboutCommunitySignal
    )
    |> deliverOnMainQueue
    |> map { presentationData, state, aboutChannelState, aboutCommunityState
        -> (ItemListControllerState, (ItemListNodeState, Any)) in
        let controllerState = ItemListControllerState(
            presentationData: ItemListPresentationData(presentationData),
            title: .text(page.localizedTitle(presentationData.strings.jerkgram)),
            leftNavigationButton: nil,
            rightNavigationButton: nil,
            backNavigationButton: ItemListBackButton(title: presentationData.strings.Common_Back)
        )

        let listState = ItemListNodeState(
            presentationData: ItemListPresentationData(presentationData),
            entries: ghostBaseSettingsEntries(
                state: state,
                context: context,
                page: page,
                strings: presentationData.strings.jerkgram,
                aboutChannelState: aboutChannelState,
                aboutCommunityState: aboutCommunityState
            ),
            style: .blocks,
            animateChanges: false
        )

        return (controllerState, (listState, arguments))
    }

    let controller = ItemListController(
        context: context,
        state: signal
    )

    openAboutChannelImpl = { [weak controller] peer in
        guard let navigationController = controller?.navigationController
            as? NavigationController else {
            return
        }
        context.sharedContext.navigateToChatController(
            NavigateToChatControllerParams(
                navigationController: navigationController,
                context: context,
                chatLocation: .peer(peer)
            )
        )
    }

    // MARK: GhostBase v1.0W native style page opener
    openSendTextStyleImpl = { [weak controller] in
        let selected = stateValue.with {
            $0.sendTextStyle
        }

        let styleController =
            ghostBaseSendStylePageController(
                context: context,
                selected: selected,
                select: { style in
                    updateState { current in
                        var updated = current
                        updated.sendTextStyle = style
                        return updated
                    }
                }
            )

        controller?.push(styleController)
    }

    pushController = { [weak controller] target in
        controller?.push(target)
    }

    return controller
}
