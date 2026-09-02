import Foundation
import UIKit
import AVFoundation
import Display
import Postbox
import TelegramCore
import AvatarNode
import AccountContext
import SwiftSignalKit
import TelegramPresentationData
import PhotoResources
import PeerInfoAvatarListNode


// MARK: GhostBase v1.1P FULLCORRECTION1
// MARK: GhostBase v1.1G PROFILE_RUNTIME1
enum GhostBaseProfileGlassRuntime {
    static func loadSettings() -> GhostBaseProfileBlurSettings? {
        return GhostBaseProfileBlurSettings.loadEnabled()
    }

    static func shouldBlendStockCover(
        settings: GhostBaseProfileBlurSettings?,
        peer: EnginePeer?,
        cachedData: EngineCachedPeerData?,
        presentationData: PresentationData,
        isSettings: Bool
    ) -> Bool {
        guard let settings else {
            return false
        }

        if !isSettings {
            if let cachedData = cachedData as? CachedUserData,
               cachedData.wallpaper != nil {
                return true
            }

            if let cachedData = cachedData as? CachedChannelData,
               cachedData.wallpaper != nil {
                return true
            }

        }

        guard let peer else {
            return false
        }

        if settings.avatarBlurInProfile,
           !peer.profileImageRepresentations.isEmpty {
            return true
        }

        if let status = peer.emojiStatus,
           case .starGift = status.content {
            return true
        }

        if peer.effectiveProfileColor != nil {
            return true
        }

        // Every resolved peer has a deliberate GhostBase scene.
        // Peers without a photo use Telegram's own placeholder palette.
        return true
    }
}

// MARK: GhostBase v1.1G PROFILEFULLSCREEN1
// The effect is owned by PeerInfoScreenNode and is optional by construction.
// With the main switch off this type is never instantiated, so there are no
// additional views, observers, signals, image work or palette work.
private final class GhostBaseProfileBackgroundCacheEntry: NSObject {
    let image: UIImage
    let tint: UIColor

    init(image: UIImage, tint: UIColor) {
        self.image = image
        self.tint = tint
    }
}

private enum GhostBaseProfileBackgroundSourceKind: Int {
    case personalWallpaper
    case globalWallpaper
    case premiumProfile
    case avatar
    case placeholder
    case telegramTheme
}

private struct GhostBaseProfileBackgroundStateKey: Equatable {
    let peerId: Int64?
    let kind: GhostBaseProfileBackgroundSourceKind
    let wallpaper: TelegramWallpaper?
    let avatarResourceId: String?
    let animatedIdentity: String?
    let premiumIdentity: String?
    let themeIdentity: ObjectIdentifier
}

// MARK: GhostBase v1.1L PROFILESTATE1
// Generic animated-media descriptor. Today it is fed by profile video;
// a future animated-wallpaper provider can feed the same renderer unchanged.
private struct GhostBaseAnimatedMediaSource {
    let identity: String
}

private final class GhostBaseProfileMirrorVideoView: UIView {
    override class var layerClass: AnyClass {
        return AVSampleBufferDisplayLayer.self
    }

    var videoLayer: AVSampleBufferDisplayLayer {
        return self.layer as! AVSampleBufferDisplayLayer
    }

    override init(frame: CGRect) {
        super.init(frame: frame)

        self.isUserInteractionEnabled = false
        self.backgroundColor = .clear
        self.layer.isOpaque = false
        self.videoLayer.videoGravity = .resizeAspectFill
        self.isHidden = true
    }

    required init?(coder: NSCoder) {
        preconditionFailure("init(coder:) has not been implemented")
    }
}

private enum GhostBaseProfileBackgroundSource {
    case wallpaper(TelegramWallpaper, GhostBaseProfileBackgroundSourceKind)
    case premium(UIColor, UIColor, String)
    case avatar(EnginePeer, TelegramMediaImageRepresentation, String, GhostBaseAnimatedMediaSource?)
    case placeholder(EnginePeer, UIColor, UIColor, String)
    case telegramTheme
}

final class GhostBaseProfileBackgroundView: UIView {
    // MARK: GhostBase v1.1S RUNTIME_RECOVERY1
    // MARK: GhostBase v1.1M RUNTIMECORE1
    private static let visualSettingsDidChange =
        Notification.Name(
            "jerkgram.ProfileVisualSettingsDidChange.V11M"
        )
    // MARK: GhostBase v1.1I PROFILEFINAL1
    private static let imageCache: NSCache<NSString, GhostBaseProfileBackgroundCacheEntry> = {
        let cache = NSCache<NSString, GhostBaseProfileBackgroundCacheEntry>()
        cache.countLimit = 64
        return cache
    }()

    // MARK: GhostBase v1.1T BUILD97_STATIC_AVATAR_CACHE1
    // A bounded persistent cache for the already-decoded 360px avatar
    // presentation. This is intentionally NOT a raw MediaBox decoder.
    private static let ghostBaseAvatarDiskCacheLock = NSLock()
    private static let ghostBaseAvatarDiskCacheLimit = 48

    private static func ghostBaseAvatarDiskCacheRoot() -> URL? {
        guard let caches = FileManager.default.urls(
            for: .cachesDirectory,
            in: .userDomainMask
        ).first else {
            return nil
        }
        return caches.appendingPathComponent(
            "GhostBaseProfileAvatarBackgrounds",
            isDirectory: true
        )
    }

    private static func ghostBaseSafeCacheComponent(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(
            CharacterSet(charactersIn: "-_.")
        )
        return value.components(separatedBy: allowed.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "_")
    }

    private static func ghostBaseAvatarDiskCacheURL(
        identity: String
    ) -> URL? {
        guard let root = self.ghostBaseAvatarDiskCacheRoot() else {
            return nil
        }
        let name = self.ghostBaseSafeCacheComponent(identity)
        guard !name.isEmpty else {
            return nil
        }
        return root.appendingPathComponent(name + ".jpg")
    }

    private static func ghostBaseLoadAvatarDiskCache(
        identity: String
    ) -> UIImage? {
        self.ghostBaseAvatarDiskCacheLock.lock()
        defer { self.ghostBaseAvatarDiskCacheLock.unlock() }

        guard let url = self.ghostBaseAvatarDiskCacheURL(identity: identity),
              FileManager.default.fileExists(atPath: url.path),
              let image = UIImage(contentsOfFile: url.path) else {
            return nil
        }
        try? FileManager.default.setAttributes(
            [.modificationDate: Date()],
            ofItemAtPath: url.path
        )
        return image
    }

    private static func ghostBaseStoreAvatarDiskCache(
        _ image: UIImage,
        identity: String
    ) {
        guard let url = self.ghostBaseAvatarDiskCacheURL(identity: identity),
              let data = image.jpegData(compressionQuality: 0.88) else {
            return
        }

        self.ghostBaseAvatarDiskCacheLock.lock()
        defer { self.ghostBaseAvatarDiskCacheLock.unlock() }

        let fm = FileManager.default
        try? fm.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: url, options: .atomic)

        guard let root = self.ghostBaseAvatarDiskCacheRoot(),
              let urls = try? fm.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.contentModificationDateKey],
                options: [.skipsHiddenFiles]
              ),
              urls.count > self.ghostBaseAvatarDiskCacheLimit else {
            return
        }

        let sorted = urls.sorted { lhs, rhs in
            let ld = (try? lhs.resourceValues(
                forKeys: [.contentModificationDateKey]
            ).contentModificationDate) ?? .distantPast
            let rd = (try? rhs.resourceValues(
                forKeys: [.contentModificationDateKey]
            ).contentModificationDate) ?? .distantPast
            return ld < rd
        }

        for old in sorted.prefix(
            max(0, sorted.count - self.ghostBaseAvatarDiskCacheLimit)
        ) {
            try? fm.removeItem(at: old)
        }
    }

    // MARK: GhostBase v1.1K PROFILEPOLISH2
    //
    // Actual image resources remain owned/cached by Telegram MediaBox.
    // Only sampled tone is persisted by source identity.
    private static let persistentToneKey =
        "jerkgram.ProfileVisualTone.V11K"

    private static let persistentToneOrderKey =
        "jerkgram.ProfileVisualToneOrder.V11K"

    private static let persistentToneLock =
        NSLock()

    private static let maximumPersistentTones =
        96

    private static func persistentTint(
        identity: String
    ) -> UIColor? {
        self.persistentToneLock.lock()

        defer {
            self.persistentToneLock.unlock()
        }

        let defaults =
            UserDefaults.standard

        guard
            let values =
                defaults.object(
                    forKey:
                        self.persistentToneKey
                )
                as? [String: String],
            let encoded =
                values[identity]
        else {
            return nil
        }

        let parts =
            encoded.split(
                separator: ","
            )

        guard
            parts.count == 3,
            let red =
                Double(parts[0]),
            let green =
                Double(parts[1]),
            let blue =
                Double(parts[2])
        else {
            return nil
        }

        return UIColor(
            red: CGFloat(red),
            green: CGFloat(green),
            blue: CGFloat(blue),
            alpha: 1.0
        )
    }

    private static func storePersistentTint(
        _ color: UIColor,
        identity: String
    ) {
        var red: CGFloat = 0.0
        var green: CGFloat = 0.0
        var blue: CGFloat = 0.0
        var alpha: CGFloat = 0.0

        guard color.getRed(
            &red,
            green: &green,
            blue: &blue,
            alpha: &alpha
        ) else {
            return
        }

        self.persistentToneLock.lock()

        defer {
            self.persistentToneLock.unlock()
        }

        let defaults =
            UserDefaults.standard

        var values =
            defaults.object(
                forKey:
                    self.persistentToneKey
            )
            as? [String: String]
            ?? [:]

        var order =
            defaults.stringArray(
                forKey:
                    self.persistentToneOrderKey
            )
            ?? []

        values[identity] =
            "\(Double(red)),\(Double(green)),\(Double(blue))"

        order.removeAll(
            where: {
                $0 == identity
            }
        )

        order.append(
            identity
        )

        while order.count
            > self.maximumPersistentTones {

            let removed =
                order.removeFirst()

            values.removeValue(
                forKey: removed
            )
        }

        defaults.set(
            values,
            forKey:
                self.persistentToneKey
        )

        defaults.set(
            order,
            forKey:
                self.persistentToneOrderKey
        )
    }

    private let context: AccountContext
    private var settings: GhostBaseProfileBlurSettings
    private var visualSettingsObserver: NSObjectProtocol?

    // Exactly one reusable image view, one persistent visual-effect view and
    // one independent tint/dimming view. They are created once in init().
    private let imageView: UIImageView
    private let blurView: UIVisualEffectView
    private let tintView: UIView

    // MARK: GhostBase v1.1P VIDEO_MIRROR1
    // One native Telegram decoder/timeline owns playback.
    // The fullscreen backdrop is a secondary render output.
    private let mirrorVideoView: GhostBaseProfileMirrorVideoView
    private var desiredVideoIdentity: String?
    private var secondaryVideoDisposable: Disposable?
    private weak var lastAvatarVideoNode: UniversalVideoNode?

    // Blur/tint intentionally use the proven Build97/V11K visual recipe.

    private let sourceDisposable = MetaDisposable()
    private var currentStateKey: GhostBaseProfileBackgroundStateKey?
    private var currentLoadKey: String?

    private(set) var usesCustomBackground = false
    var requestUpdate: (() -> Void)?

    init(context: AccountContext, settings: GhostBaseProfileBlurSettings) {
        self.context = context
        self.settings = settings

        self.imageView = UIImageView()
        self.imageView.contentMode = .scaleAspectFill
        self.imageView.clipsToBounds = true

        self.mirrorVideoView = GhostBaseProfileMirrorVideoView(frame: .zero)

        self.blurView = UIVisualEffectView(effect: nil)
        self.blurView.isUserInteractionEnabled = false

        self.tintView = UIView()
        self.tintView.isUserInteractionEnabled = false

        super.init(frame: .zero)

        self.clipsToBounds = true
        self.isUserInteractionEnabled = false
        self.addSubview(self.imageView)
        self.addSubview(self.mirrorVideoView)
        self.addSubview(self.blurView)
        self.addSubview(self.tintView)

        self.visualSettingsObserver =
            NotificationCenter.default.addObserver(
                forName:
                    Self.visualSettingsDidChange,
                object: nil,
                queue: .main,
                using: { [weak self] _ in
                    self?.refreshLiveSettings()
                }
            )
    }

    required init?(coder: NSCoder) {
        preconditionFailure("init(coder:) has not been implemented")
    }

    deinit {
        if let visualSettingsObserver =
            self.visualSettingsObserver {

            NotificationCenter.default.removeObserver(
                visualSettingsObserver
            )
        }

        self.secondaryVideoDisposable?.dispose()
        self.secondaryVideoDisposable = nil
        self.sourceDisposable.dispose()
    }

    private func tearDownForDisabledSettings() {
        self.sourceDisposable.set(nil)

        self.currentLoadKey = nil
        self.currentStateKey = nil

        self.clearAnimatedMedia()

        self.imageView.image = nil
        self.blurView.effect = nil

        self.tintView.backgroundColor =
            .clear

        self.backgroundColor = .clear

        self.usesCustomBackground =
            false

        self.isHidden = true
    }

    private func refreshLiveSettings() {
        guard let settings =
            GhostBaseProfileBlurSettings
                .loadEnabled()
        else {
            self.tearDownForDisabledSettings()
            return
        }

        self.settings = settings
        self.isHidden = false

        if !settings
            .animatedBackgroundEnabled {

            self.clearAnimatedMedia()
        }

        self.currentStateKey = nil
        self.requestUpdate?()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // Layout only updates frames. No image generation, color extraction,
        // UserDefaults access, source selection or signal creation occurs here.
        let bounds = self.bounds
        self.imageView.frame = bounds
        self.mirrorVideoView.frame = bounds
        self.blurView.frame = bounds
        self.tintView.frame = bounds
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()

        if self.window == nil {
            self.secondaryVideoDisposable?.dispose()
            self.secondaryVideoDisposable = nil
            self.mirrorVideoView.isHidden = true
        } else {
            self.refreshAnimatedVideoOwner(self.lastAvatarVideoNode)
        }
    }

    func update(
        peer: EnginePeer?,
        cachedData: EngineCachedPeerData?,
        presentationData: PresentationData,
        isSettings: Bool,
        avatarItem: PeerInfoAvatarListItem?
    ) {
        guard let liveSettings =
            GhostBaseProfileBlurSettings
                .loadEnabled()
        else {
            self.tearDownForDisabledSettings()
            return
        }

        self.settings = liveSettings
        self.isHidden = false

        let source = self.resolveSource(
            peer: peer,
            cachedData: cachedData,
            presentationData: presentationData,
            isSettings: isSettings,
            avatarItem: avatarItem
        )
        let stateKey = self.stateKey(
            source: source,
            peer: peer,
            presentationData: presentationData
        )
        guard self.currentStateKey != stateKey else {
            return
        }
        self.currentStateKey = stateKey
        self.apply(
            source: source,
            stateKey: stateKey,
            presentationData: presentationData
        )
    }

    private func placeholderColors(
        peer: EnginePeer,
        presentationData _: PresentationData
    ) -> (UIColor, UIColor, String) {
        // Telegram legacy avatar-placeholder palette.
        let palette:
            [(UInt32, UInt32)] = [
                (0xff516a, 0xff885e),
                (0xffa85c, 0xffcd6a),
                (0x665fff, 0x82b1ff),
                (0x54cb68, 0xa0de7e),
                (0x4acccd, 0x00fcfd),
                (0x2a9ef1, 0x72d5fd),
                (0xd669ed, 0xe0a2f3)
            ]

        let rawId =
            peer.id.id
                ._internalGetInt64Value()

        let absoluteId: UInt64 =
            rawId == Int64.min
            ? UInt64(Int64.max)
            : UInt64(
                Swift.abs(rawId)
            )

        let index =
            Int(
                absoluteId
                % UInt64(
                    palette.count
                )
            )

        let pair =
            palette[index]

        return (
            UIColor(rgb: pair.0),
            UIColor(rgb: pair.1),
            "legacy:\(index)"
        )
    }

    private static func colorLuminance(
        _ color: UIColor
    ) -> CGFloat {
        var red: CGFloat = 0.0
        var green: CGFloat = 0.0
        var blue: CGFloat = 0.0
        var alpha: CGFloat = 0.0

        guard color.getRed(
            &red,
            green: &green,
            blue: &blue,
            alpha: &alpha
        ) else {
            return 0.5
        }

        return
            red * 0.2126
            + green * 0.7152
            + blue * 0.0722
    }

    private func resolveSource(
        peer: EnginePeer?,
        cachedData: EngineCachedPeerData?,
        presentationData: PresentationData,
        isSettings: Bool,
        avatarItem: PeerInfoAvatarListItem?
    ) -> GhostBaseProfileBackgroundSource {
        if !isSettings {
            if let cachedData = cachedData as? CachedUserData,
               let wallpaper = cachedData.wallpaper {

                return .wallpaper(
                    wallpaper,
                    .personalWallpaper
                )
            }

            if let cachedData = cachedData as? CachedChannelData,
               let wallpaper = cachedData.wallpaper {

                return .wallpaper(
                    wallpaper,
                    .personalWallpaper
                )
            }

        }

        if let peer {
            // Existing toggle becomes a real source selector.
            //
            // ON:
            // avatar -> Premium
            //
            // OFF:
            // Premium -> avatar fallback

            if self.settings.avatarBlurInProfile,
               let representation =
                    peer.profileImageRepresentations.last {

                let resourceId =
                    String(
                        describing:
                            representation.resource.id
                    )

                return .avatar(
                    peer,
                    representation,
                    resourceId,
                    self.animatedAvatarSource(
                        peer: peer,
                        item: avatarItem,
                        isSettings: isSettings
                    )
                )
            }

            if let status = peer.emojiStatus,
               case let .starGift(
                    _,
                    _,
                    _,
                    _,
                    _,
                    innerColor,
                    outerColor,
                    _,
                    _
               ) = status.content {

                let main =
                    UIColor(
                        rgb:
                            UInt32(
                                bitPattern:
                                    innerColor
                            )
                    )

                let secondary =
                    UIColor(
                        rgb:
                            UInt32(
                                bitPattern:
                                    outerColor
                            )
                    )

                return .premium(
                    main,
                    secondary,
                    "gift:\(innerColor):\(outerColor)"
                )
            }

            if let profileColor =
                peer.effectiveProfileColor {

                let colors =
                    self.context
                        .peerNameColors
                        .getProfile(
                            profileColor,
                            dark:
                                presentationData
                                    .theme
                                    .overallDarkAppearance
                        )

                return .premium(
                    colors.main,
                    colors.secondary
                        ?? colors.main,
                    "profile:\(String(describing: profileColor)):\(presentationData.theme.overallDarkAppearance)"
                )
            }

            if let representation =
                peer.profileImageRepresentations.last {

                let resourceId =
                    String(
                        describing:
                            representation.resource.id
                    )

                return .avatar(
                    peer,
                    representation,
                    resourceId,
                    self.animatedAvatarSource(
                        peer: peer,
                        item: avatarItem,
                        isSettings: isSettings
                    )
                )
            }

            // No photo at all: never reuse an old image buffer and never wait
            // for an avatar signal. Build the profile scene synchronously from
            // the same Telegram placeholder color family as the letter avatar.
            let placeholder =
                self.placeholderColors(
                    peer: peer,
                    presentationData:
                        presentationData
                )

            return .placeholder(
                peer,
                placeholder.0,
                placeholder.1,
                placeholder.2
            )
        }

        return .telegramTheme
    }

    private func animatedAvatarSource(
        peer: EnginePeer,
        item: PeerInfoAvatarListItem?,
        isSettings _: Bool
    ) -> GhostBaseAnimatedMediaSource? {
        guard
            self.settings.animatedBackgroundEnabled,
            !self.settings.reducedBlur,
            !UIAccessibility.isReduceTransparencyEnabled,
            !ProcessInfo.processInfo.isLowPowerModeEnabled,
            let item
        else {
            return nil
        }

        let videoRepresentations: [VideoRepresentationWithReference]

        switch item {
        case .custom:
            return nil
        case let .topImage(_, values, _):
            videoRepresentations = values
        case let .image(_, _, values, _, _, _):
            videoRepresentations = values
        }

        guard let video = videoRepresentations.last else {
            return nil
        }

        return GhostBaseAnimatedMediaSource(
            identity: "video:\(peer.id.toInt64()):\(String(describing: video.representation.resource.id)):\(video.representation.startTimestamp ?? 0.0)"
        )
    }

    private func stateKey(
        source: GhostBaseProfileBackgroundSource,
        peer: EnginePeer?,
        presentationData: PresentationData
    ) -> GhostBaseProfileBackgroundStateKey {
        let peerId = peer?.id.toInt64()
        let themeIdentity = ObjectIdentifier(presentationData.theme)
        switch source {
        case let .wallpaper(wallpaper, kind):
            return GhostBaseProfileBackgroundStateKey(
                peerId: peerId,
                kind: kind,
                wallpaper: wallpaper,
                avatarResourceId: nil,
                animatedIdentity: nil,
                premiumIdentity: nil,
                themeIdentity: themeIdentity
            )
        case let .premium(_, _, identity):
            return GhostBaseProfileBackgroundStateKey(
                peerId: peerId,
                kind: .premiumProfile,
                wallpaper: nil,
                avatarResourceId: nil,
                animatedIdentity: nil,
                premiumIdentity: identity,
                themeIdentity: themeIdentity
            )
        case let .avatar(
            _,
            _,
            resourceId,
            animatedSource
        ):
            return GhostBaseProfileBackgroundStateKey(
                peerId: peerId,
                kind: .avatar,
                wallpaper: nil,
                avatarResourceId: resourceId,
                animatedIdentity:
                    animatedSource?.identity,
                premiumIdentity: nil,
                themeIdentity: themeIdentity
            )
        case let .placeholder(
            _,
            _,
            _,
            identity
        ):
            return GhostBaseProfileBackgroundStateKey(
                peerId: peerId,
                kind: .placeholder,
                wallpaper: nil,
                avatarResourceId: nil,
                animatedIdentity: nil,
                premiumIdentity: identity,
                themeIdentity: themeIdentity
            )

        case .telegramTheme:
            return GhostBaseProfileBackgroundStateKey(
                peerId: peerId,
                kind: .telegramTheme,
                wallpaper: nil,
                avatarResourceId: nil,
                animatedIdentity: nil,
                premiumIdentity: nil,
                themeIdentity: themeIdentity
            )
        }
    }

    private func clearAnimatedMedia() {
        self.secondaryVideoDisposable?.dispose()
        self.secondaryVideoDisposable = nil
        self.lastAvatarVideoNode = nil
        self.desiredVideoIdentity = nil
        self.mirrorVideoView.isHidden = true
        self.mirrorVideoView.videoLayer.flushAndRemoveImage()
    }

    private func applyAnimatedMedia(_ source: GhostBaseAnimatedMediaSource?) {
        let updatedIdentity = source?.identity

        if self.desiredVideoIdentity != updatedIdentity {
            self.secondaryVideoDisposable?.dispose()
            self.secondaryVideoDisposable = nil
            self.lastAvatarVideoNode = nil
            self.mirrorVideoView.videoLayer.flushAndRemoveImage()
            self.desiredVideoIdentity = updatedIdentity
        }

        if updatedIdentity == nil {
            self.mirrorVideoView.isHidden = true
        }
    }

    func refreshAnimatedVideoOwner(_ videoNode: UniversalVideoNode?) {
        self.lastAvatarVideoNode = videoNode

        guard
            self.window != nil,
            self.desiredVideoIdentity != nil,
            let videoNode
        else {
            return
        }

        if self.secondaryVideoDisposable == nil {
            self.secondaryVideoDisposable =
                videoNode.registerSecondaryVideoLayer(
                    self.mirrorVideoView.videoLayer
                )
        }

        self.mirrorVideoView.isHidden =
            self.secondaryVideoDisposable == nil
    }

    private func apply(
        source: GhostBaseProfileBackgroundSource,
        stateKey: GhostBaseProfileBackgroundStateKey,
        presentationData: PresentationData
    ) {
        self.sourceDisposable.set(nil)
        self.currentLoadKey = nil

        let isDark = presentationData.theme.overallDarkAppearance
        let reduced = self.settings.reducedBlur
            || UIAccessibility.isReduceTransparencyEnabled
            || ProcessInfo.processInfo.isLowPowerModeEnabled
        // Keep wallpaper/avatar structure visible instead of flattening
        // the scene into a dark material field.
        let effectStyle: UIBlurEffect.Style = isDark
            ? .systemUltraThinMaterialDark
            : .systemUltraThinMaterialLight
        self.blurView.effect = UIBlurEffect(style: effectStyle)
        // MARK: GhostBase v1.1S STATIC_AVATAR_BLUR_INTENSITY1
        // Reset for every source; only static avatars lower intensity.
        self.blurView.alpha = 1.0

        switch source {
        case let .wallpaper(wallpaper, kind):
            self.clearAnimatedMedia()
            self.usesCustomBackground = true
            let fallback = presentationData.theme.list.itemBlocksBackgroundColor
            let metadataTint = Self.wallpaperTint(wallpaper, fallback: fallback)
            self.applyTint(metadataTint, fallback: fallback, isDark: isDark, reduced: reduced)
            self.backgroundColor = metadataTint

            let cacheKey = "wallpaper:\(kind.rawValue):\(String(reflecting: wallpaper))" as NSString
            if let cached = Self.imageCache.object(forKey: cacheKey) {
                self.imageView.image = cached.image
                self.applyTint(cached.tint, fallback: metadataTint, isDark: isDark, reduced: reduced)
                return
            }

            // Never generate wallpaper pixels from PeerInfoScreenNode layout.
            // A metadata color is enough for the immediate fallback; any image
            // decode or generated gradient runs on the concurrent image path.
            self.imageView.image = nil
            let loadKey = cacheKey as String
            self.currentLoadKey = loadKey
            self.sourceDisposable.set((self.wallpaperEntrySignal(
                wallpaper: wallpaper,
                fallback: metadataTint,
                identity: loadKey
            )
            |> deliverOnMainQueue).start(next: { [weak self] entry in
                guard let self, self.currentLoadKey == loadKey, let entry else {
                    return
                }
                Self.imageCache.setObject(entry, forKey: cacheKey)
                self.imageView.image = entry.image
                self.applyTint(entry.tint, fallback: metadataTint, isDark: isDark, reduced: reduced)
                self.requestUpdate?()
            }))

        case let .premium(main, secondary, identity):
            self.clearAnimatedMedia()
            self.usesCustomBackground = true
            self.backgroundColor = main
            self.applyTint(main, fallback: main, isDark: isDark, reduced: reduced)

            let cacheKey = "premium:\(identity)" as NSString
            if let cached = Self.imageCache.object(forKey: cacheKey) {
                self.imageView.image = cached.image
                self.applyTint(cached.tint, fallback: main, isDark: isDark, reduced: reduced)
                return
            }

            self.imageView.image = nil
            let loadKey = cacheKey as String
            self.currentLoadKey = loadKey
            self.sourceDisposable.set((deferred { () -> Signal<GhostBaseProfileBackgroundCacheEntry?, NoError> in
                guard let image = Self.generatedGradientImage(
                    colors: [main, secondary]
                ) else {
                    return .single(nil)
                }
                return .single(
                    GhostBaseProfileBackgroundCacheEntry(
                        image: image,
                        tint: main.mixedWith(secondary, alpha: 0.35)
                    )
                )
            }
            |> runOn(Queue.concurrentDefaultQueue())
            |> deliverOnMainQueue).start(next: { [weak self] entry in
                guard let self, self.currentLoadKey == loadKey, let entry else {
                    return
                }
                Self.imageCache.setObject(entry, forKey: cacheKey)
                self.imageView.image = entry.image
                self.applyTint(entry.tint, fallback: main, isDark: isDark, reduced: reduced)
                self.requestUpdate?()
            }))

        case let .avatar(
            peer,
            representation,
            resourceId,
            animatedSource
        ):
            self.usesCustomBackground = true

            // MARK: GhostBase v1.1U BUILD106_STATIC_AVATAR_BLUR1
            // Build105 runtime proved that lowering UIVisualEffectView.alpha
            // does not lower blur intensity: it exposes the sharp stretched
            // image beneath it. Keep the persistent blur owner fully opaque.
            //
            // Reduced mode still affects the existing tint/cost policy; it
            // must not turn the scene back into an almost-unblurred avatar.
            self.blurView.alpha = 1.0

            let fallback =
                presentationData
                    .theme
                    .list
                    .itemBlocksBackgroundColor

            let cacheKey =
                "avatar:\(peer.id.toInt64()):\(resourceId)"
                as NSString

            // Ignore disk entries written from the old blurred-thumbnail
            // pipeline; RAM is process-local and naturally starts clean.
            let loadKey =
                "avatar-final-v2:" + (cacheKey as String)

            // MARK: GhostBase v1.1Q BUILD97_NEUTRAL_REOPEN1
            let immediateTint =
                fallback

            self.backgroundColor =
                fallback

            self.applyTint(
                fallback,
                fallback:
                    fallback,
                isDark:
                    isDark,
                reduced:
                    reduced
            )

            self.applyAnimatedMedia(
                animatedSource
            )

            // MARK: GhostBase v1.1T AVATAR_REOPEN_NO_GREY1
            // RAM cache first, then the small decoded-avatar disk cache.
            // Only if neither exists do we briefly expose the neutral fallback.
            if let cached = Self.imageCache.object(forKey: cacheKey) {
                self.imageView.image = cached.image
                self.applyTint(
                    cached.tint,
                    fallback: fallback,
                    isDark: isDark,
                    reduced: reduced
                )
            } else if let diskImage = Self.ghostBaseLoadAvatarDiskCache(
                identity: loadKey
            ) {
                let diskTint = Self.sampledTint(
                    from: diskImage,
                    fallback: fallback
                )
                let diskEntry = GhostBaseProfileBackgroundCacheEntry(
                    image: diskImage,
                    tint: diskTint
                )
                Self.imageCache.setObject(diskEntry, forKey: cacheKey)
                self.imageView.image = diskImage
                self.applyTint(
                    diskTint,
                    fallback: fallback,
                    isDark: isDark,
                    reduced: reduced
                )
            } else {
                self.imageView.image = nil
            }

            self.currentLoadKey = loadKey

            guard let signal =
                self.avatarEntrySignal(
                    peer: peer,
                    representation:
                        representation,
                    identity: loadKey,
                    fallback:
                        immediateTint
                )
            else {
                return
            }

            self.sourceDisposable.set((signal
            |> deliverOnMainQueue).start(next: { [weak self] entry in
                guard let self, self.currentLoadKey == loadKey, let entry else {
                    return
                }
                Self.imageCache.setObject(
                    entry,
                    forKey: cacheKey
                )
                self.imageView.image = entry.image
                self.applyTint(
                    entry.tint,
                    fallback: fallback,
                    isDark: isDark,
                    reduced: reduced
                )
                self.requestUpdate?()
            }))

        case let .placeholder(
            peer,
            main,
            secondary,
            identity
        ):
            self.clearAnimatedMedia()
            self.sourceDisposable.set(nil)
            self.currentLoadKey = nil

            self.usesCustomBackground =
                true

            let cacheKey =
                "placeholder:\(peer.id.toInt64()):\(identity)"
                as NSString

            if let cached =
                Self.imageCache.object(
                    forKey: cacheKey
                ) {

                self.imageView.image =
                    cached.image
            } else {
                let image =
                    Self.generatedGradientImage(
                        colors: [
                            main,
                            secondary
                        ]
                    )

                if let image {
                    let entry =
                        GhostBaseProfileBackgroundCacheEntry(
                            image:
                                image,
                            tint:
                                main
                        )

                    Self.imageCache.setObject(
                        entry,
                        forKey:
                            cacheKey
                    )

                    self.imageView.image =
                        image
                } else {
                    self.imageView.image =
                        nil
                }
            }

            self.backgroundColor =
                main

            let luminance =
                max(
                    Self.colorLuminance(
                        main
                    ),
                    Self.colorLuminance(
                        secondary
                    )
                )

            // Keep Telegram's circular placeholder brighter than the scene.
            // Very bright yellow/green avatars receive a stronger dark scrim.
            let scrimAlpha =
                min(
                    isDark
                    ? 0.34
                    : 0.24,
                    max(
                        isDark
                        ? 0.16
                        : 0.09,
                        (
                            isDark
                            ? 0.12
                            : 0.06
                        )
                        + luminance
                        * (
                            isDark
                            ? 0.22
                            : 0.16
                        )
                    )
                )

            self.tintView
                .backgroundColor =
                UIColor.black
                    .withAlphaComponent(
                        scrimAlpha
                    )

        case .telegramTheme:
            self.clearAnimatedMedia()
            self.usesCustomBackground = false
            self.imageView.image = nil
            self.tintView.backgroundColor = .clear
            self.backgroundColor = .clear
        }
    }

    private func applyTint(
        _ color: UIColor,
        fallback: UIColor,
        isDark: Bool,
        reduced: Bool
    ) {
        // MARK: JerkGram v1.1Y BUILD110_PROFILE_READABILITY1
        //
        // The fullscreen background stays visible, but the single existing
        // tint layer now also provides adaptive contrast. This is deliberately
        // one scene-wide layer, not per-cell blur/glass.
        let sourceColor = color
        let luminance = Self.colorLuminance(sourceColor)
        // MARK: Jerkgram v1.2C BUILD114_SOURCE_LUMINANCE1
        // Read-only bridge for Links readability.
        // It does NOT alter profile tint / blur / source.
        UserDefaults.standard.set(
            Double(luminance),
            forKey: "Jerkgram.ProfileBackdrop.SourceLuminance"
        )

        let contrastColor: UIColor
        let contrastAlpha: CGFloat

        if isDark {
            let brightBoost = max(
                0.0,
                min(
                    1.0,
                    (luminance - 0.32) / 0.68
                )
            )

            contrastColor = sourceColor.mixedWith(
                UIColor.black,
                alpha: 0.72
            )

            contrastAlpha = min(
                reduced ? 0.24 : 0.32,
                (reduced ? 0.10 : 0.14)
                    + brightBoost
                    * (reduced ? 0.12 : 0.17)
            )
        } else {
            let darkBoost = max(
                0.0,
                min(
                    1.0,
                    (0.48 - luminance) / 0.48
                )
            )

            contrastColor = sourceColor.mixedWith(
                UIColor.white,
                alpha: 0.70
            )

            contrastAlpha = min(
                reduced ? 0.17 : 0.23,
                (reduced ? 0.055 : 0.075)
                    + darkBoost
                    * (reduced ? 0.10 : 0.14)
            )
        }

        if self.settings.tintEnabled {
            self.tintView.backgroundColor =
                contrastColor.withAlphaComponent(
                    contrastAlpha
                )
        } else {
            self.tintView.backgroundColor =
                (isDark ? UIColor.black : UIColor.white)
                    .withAlphaComponent(
                        contrastAlpha
                    )
        }
    }

    private func wallpaperEntrySignal(
        wallpaper: TelegramWallpaper,
        fallback: UIColor,
        identity: String
    ) -> Signal<GhostBaseProfileBackgroundCacheEntry?, NoError> {
        switch wallpaper {
        case let .image(representations, _):
            guard let representation =
                largestImageRepresentation(
                    representations
                ) else {
                return .single(nil)
            }

            return self.resourceEntrySignal(
                resource:
                    representation.resource,
                identity:
                    identity,
                fallback:
                    fallback
            )

        case let .file(file):
            if wallpaper.isPattern {
                return .single(nil)
            }

            return self.resourceEntrySignal(
                resource:
                    file.file.resource,
                identity:
                    identity,
                fallback:
                    fallback
            )

        default:
            let colors =
                Self.wallpaperColors(
                    wallpaper
                )

            let tint =
                Self.wallpaperTint(
                    wallpaper,
                    fallback: fallback
                )

            return deferred {
                guard let image =
                    Self.generatedWallpaperImage(
                        colors: colors,
                        fallback: tint
                    ) else {
                    return .single(nil)
                }

                return .single(
                    GhostBaseProfileBackgroundCacheEntry(
                        image: image,
                        tint: tint
                    )
                )
            }
            |> runOn(
                Queue.concurrentDefaultQueue()
            )
        }
    }

    // MARK: GhostBase v1.1T BUILD97_STATIC_AVATAR_PIPELINE1
    private func avatarEntrySignal(
        peer: EnginePeer,
        representation: TelegramMediaImageRepresentation,
        identity: String,
        fallback: UIColor
    ) -> Signal<GhostBaseProfileBackgroundCacheEntry?, NoError>? {
        // Exact good V11K/Build97 feed: Telegram owns avatar decoding and
        // produces a 360x360 unclipped presentation. Do not decode the raw
        // MediaBox resource as UIImage and do not request the 720px V11S path.
        guard let signal = peerAvatarImage(
            account: self.context.account,
            peerReference: PeerReference(peer),
            authorOfMessage: nil,
            representation: representation,
            displayDimensions: CGSize(width: 360.0, height: 360.0),
            clipStyle: .none,
            blurred: false,
            inset: 0.0,
            emptyColor: nil,
            // MARK: Jerkgram v1.2I BUILD120_PROFILE_COLDSTART1
            synchronousLoad: true,
            completeOnly: true
        ) else {
            return nil
        }

        return signal
        |> deliverOn(Queue.concurrentDefaultQueue())
        |> map { versions -> GhostBaseProfileBackgroundCacheEntry? in
            // MARK: Jerkgram v1.2L BUILD123_PROFILE_FINAL_CACHE1
            // AvatarNode has already rejected every .blurred typed emission.
            guard let image = versions?.0 else {
                return nil
            }

            let tint = Self.sampledTint(
                from: image,
                fallback: fallback
            )

            Self.ghostBaseStoreAvatarDiskCache(
                image,
                identity: identity
            )

            return GhostBaseProfileBackgroundCacheEntry(
                image: image,
                tint: tint
            )
        }
    }

    private func resourceEntrySignal(
        resource: MediaResource,
        identity: String,
        fallback: UIColor,
        alwaysSampleTint: Bool = false
    ) -> Signal<GhostBaseProfileBackgroundCacheEntry?, NoError> {
        let mediaBox =
            self.context.account.postbox.mediaBox

        return Signal {
            subscriber in

            let fetchDisposable =
                mediaBox
                    .fetchedResource(
                        resource,
                        parameters: nil
                    )
                    .start()

            let dataDisposable =
                (
                    mediaBox
                        .resourceData(
                            resource
                        )
                    |> filter {
                        $0.complete
                    }
                    |> take(1)
                    |> mapToSignal {
                        data
                        -> Signal<GhostBaseProfileBackgroundCacheEntry?, NoError>
                        in

                        return deferred {
                            guard let image =
                                UIImage(
                                    contentsOfFile:
                                        data.path
                                ) else {
                                return .single(nil)
                            }

                            let tint: UIColor

                            if alwaysSampleTint {
                                // A decoded static avatar is authoritative.
                                // Never let an old persisted tone turn reopen
                                // into a grey/flat plate.
                                tint = Self.sampledTint(
                                    from: image,
                                    fallback: fallback
                                )
                                Self.storePersistentTint(
                                    tint,
                                    identity: identity
                                )
                            } else if let persisted = Self.persistentTint(
                                identity: identity
                            ) {
                                tint = persisted
                            } else {
                                tint = Self.sampledTint(
                                    from: image,
                                    fallback: fallback
                                )
                                Self.storePersistentTint(
                                    tint,
                                    identity: identity
                                )
                            }

                            return .single(
                                GhostBaseProfileBackgroundCacheEntry(
                                    image: image,
                                    tint: tint
                                )
                            )
                        }
                        |> runOn(
                            Queue.concurrentDefaultQueue()
                        )
                    }
                )
                .start(
                    next: {
                        entry in

                        subscriber.putNext(
                            entry
                        )
                    },
                    completed: {
                        subscriber.putCompletion()
                    }
                )

            return ActionDisposable {
                fetchDisposable.dispose()
                dataDisposable.dispose()
            }
        }
    }

    private static func wallpaperColors(_ wallpaper: TelegramWallpaper) -> [UInt32] {
        switch wallpaper {
        case let .color(value):
            return [value]
        case let .gradient(value):
            return value.colors
        case let .image(_, settings):
            return settings.colors
        case let .file(value):
            return value.settings.colors
        case .builtin:
            return []
        case .emoticon:
            return []
        }
    }

    private static func wallpaperTint(_ wallpaper: TelegramWallpaper, fallback: UIColor) -> UIColor {
        let colors = self.wallpaperColors(wallpaper)
        guard var result = colors.first.map({ UIColor(argb: $0) }) else {
            return fallback
        }
        if colors.count > 1 {
            for (index, value) in colors.dropFirst().enumerated() {
                let count = CGFloat(index + 2)
                result = result.mixedWith(UIColor(argb: value), alpha: 1.0 / count)
            }
        }
        return result
    }

    private static func generatedWallpaperImage(colors: [UInt32], fallback: UIColor) -> UIImage? {
        let resolvedColors: [UIColor]
        if colors.isEmpty {
            resolvedColors = [fallback, fallback]
        } else if colors.count == 1 {
            let color = UIColor(argb: colors[0])
            resolvedColors = [color, color]
        } else {
            resolvedColors = colors.map { UIColor(argb: $0) }
        }

        return generateImage(
            CGSize(width: 48.0, height: 48.0),
            contextGenerator: { size, context in
                let colorSpace = CGColorSpaceCreateDeviceRGB()
                var locations: [CGFloat] = resolvedColors.indices.map { index in
                    if resolvedColors.count <= 1 {
                        return 0.0
                    }
                    return CGFloat(index) / CGFloat(resolvedColors.count - 1)
                }
                guard let gradient = CGGradient(
                    colorsSpace: colorSpace,
                    colors: resolvedColors.map { $0.cgColor } as CFArray,
                    locations: &locations
                ) else {
                    context.setFillColor(fallback.cgColor)
                    context.fill(CGRect(origin: .zero, size: size))
                    return
                }
                context.drawLinearGradient(
                    gradient,
                    start: CGPoint(x: 0.0, y: 0.0),
                    end: CGPoint(x: size.width, y: size.height),
                    options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
                )
            },
            opaque: true,
            scale: 1.0
        )
    }

    private static func generatedGradientImage(colors: [UIColor]) -> UIImage? {
        let resolved = colors.isEmpty ? [UIColor.black, UIColor.black] : colors
        return generateImage(
            CGSize(width: 64.0, height: 64.0),
            contextGenerator: { size, context in
                let colorSpace = CGColorSpaceCreateDeviceRGB()
                var locations: [CGFloat] = resolved.indices.map { index in
                    if resolved.count <= 1 {
                        return 0.0
                    }
                    return CGFloat(index) / CGFloat(resolved.count - 1)
                }
                guard let gradient = CGGradient(
                    colorsSpace: colorSpace,
                    colors: resolved.map { $0.cgColor } as CFArray,
                    locations: &locations
                ) else {
                    context.setFillColor(resolved[0].cgColor)
                    context.fill(CGRect(origin: .zero, size: size))
                    return
                }
                context.drawLinearGradient(
                    gradient,
                    start: CGPoint(x: 0.0, y: 0.0),
                    end: CGPoint(x: size.width, y: size.height),
                    options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
                )
            },
            opaque: true,
            scale: 1.0
        )
    }

    private static func sampledTint(from image: UIImage, fallback: UIColor) -> UIColor {
        guard let cgImage = image.cgImage else {
            return fallback
        }
        var pixel = [UInt8](repeating: 0, count: 4)
        let rendered = pixel.withUnsafeMutableBytes { bytes -> Bool in
            guard let baseAddress = bytes.baseAddress,
                  let context = CGContext(
                    data: baseAddress,
                    width: 1,
                    height: 1,
                    bitsPerComponent: 8,
                    bytesPerRow: 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
                  ) else {
                return false
            }
            context.interpolationQuality = .medium
            context.draw(cgImage, in: CGRect(x: 0.0, y: 0.0, width: 1.0, height: 1.0))
            return true
        }
        guard rendered, pixel[3] > 8 else {
            return fallback
        }
        return UIColor(
            red: CGFloat(pixel[0]) / 255.0,
            green: CGFloat(pixel[1]) / 255.0,
            blue: CGFloat(pixel[2]) / 255.0,
            alpha: 1.0
        )
    }
}
