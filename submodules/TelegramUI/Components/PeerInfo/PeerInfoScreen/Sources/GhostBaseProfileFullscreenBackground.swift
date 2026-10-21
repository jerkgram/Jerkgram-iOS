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


// Temporary P0 diagnostics: fixed counters, main-thread timings, lifecycle summaries.
// No timer, observer, extra renderer, per-frame logging or peer/resource identifiers.
final class JerkgramProfilePerformanceProbe {
    enum Stage: String, CaseIterable {
        case layout, data, background, transition, play, attach, detach, preferences, alpha
        case bgPreferences, bgResolve, bgApply, header, sections, panesAndTail, navigation, scrollHeader, scrollPanes
        case headerPhonePreference, headerAvatar, headerCover

        var settingsDetail: Bool {
            switch self {
            case .bgPreferences, .bgResolve, .bgApply, .header, .sections, .panesAndTail, .navigation, .scrollHeader, .scrollPanes: return true
            case .headerPhonePreference, .headerAvatar, .headerCover: return true
            default: return false
            }
        }
    }
    private struct Sample {
        var count = 0
        var maxMs = 0.0
        var slow = 0
    }
    private static var created = 0
    private static var destroyed = 0
    private static var liveInstances = 0
    private let instance: Int
    private var samples: [Stage: Sample] = [:]
    var context = "pending"
    var outputIdentity = "pending"
    var subscriptions = 0
    var disposals = 0
    var ready = 0
    var updateRequests = 0
    var ramHits = 0
    var readyMaxWallMs = 0.0

    init() {
        Self.created += 1
        Self.liveInstances += 1
        self.instance = Self.created
    }

    deinit {
        Self.destroyed += 1
        Self.liveInstances -= 1
    }

    func begin(_ stage: Stage) -> TimeInterval {
        self.samples[stage, default: Sample()].count += 1
        return ProcessInfo.processInfo.systemUptime
    }

    func end(_ stage: Stage, _ started: TimeInterval) {
        let elapsed = (ProcessInfo.processInfo.systemUptime - started) * 1000.0
        var sample = self.samples[stage] ?? Sample()
        sample.maxMs = max(sample.maxMs, elapsed)
        if elapsed >= 16.7 { sample.slow += 1 }
        self.samples[stage] = sample
        // Settings-only detail keys keep both contexts plus workers under32.
        if !stage.settingsDetail || self.context == "settings" {
            JerkgramPerformanceDiagnostics.shared.measure(self.context + "." + stage.rawValue, milliseconds: elapsed, startedAt: started, owner: self.instance)
        }
    }

    func summary(_ boundary: String, sourceRetained: Bool, outputRetained: Bool) {
        JerkgramPerformanceDiagnostics.shared.record("profile id=\(self.instance) output=\(self.outputIdentity) context=\(self.context) \(boundary) live=\(Self.liveInstances) created=\(Self.created) destroyed=\(Self.destroyed) sub=\(self.subscriptions) dispose=\(self.disposals) ready=\(self.ready) readyWallMs=\(Int(self.readyMaxWallMs)) ram=\(self.ramHits) requests=\(self.updateRequests) sourceSlot=\(sourceRetained) outputSlot=\(outputRetained)")
        let timings = Stage.allCases.map { stage -> String in
            let sample = self.samples[stage] ?? Sample()
            return "\(stage.rawValue)=\(sample.count)/\(Int(sample.maxMs))/\(sample.slow)"
        }.joined(separator: " ")
        Logger.shared.log("JerkgramProfilePerf", "v1 id=\(self.instance) output=\(self.outputIdentity) context=\(self.context) boundary=\(boundary) created=\(Self.created) destroyed=\(Self.destroyed) live=\(Self.liveInstances) sub=\(self.subscriptions) dispose=\(self.disposals) ready=\(self.ready) readyWallMs=\(Int(self.readyMaxWallMs)) requests=\(self.updateRequests) ram=\(self.ramHits) sourceSlot=\(sourceRetained) outputSlot=\(outputRetained) count/maxMs/slow: \(timings)")
    }
}

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

        // Peers without a photo use Telegram's own placeholder palette.
        return true
    }
}

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
    private static let visualSettingsDidChange =
        Notification.Name(
            "jerkgram.ProfileVisualSettingsDidChange.V11M"
        )
    private static let imageCache: NSCache<NSString, GhostBaseProfileBackgroundCacheEntry> = {
        let cache = NSCache<NSString, GhostBaseProfileBackgroundCacheEntry>()
        cache.countLimit = 64
        return cache
    }()

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
        let perfStart = JerkgramPerformanceDiagnostics.shared.isRecording ? ProcessInfo.processInfo.systemUptime : nil
        defer { if let perfStart { JerkgramPerformanceDiagnostics.shared.measure((Thread.isMainThread ? "main." : "worker.") + "avatarDiskLoad", milliseconds: (ProcessInfo.processInfo.systemUptime - perfStart) * 1000.0) } }
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
        let perfStart = JerkgramPerformanceDiagnostics.shared.isRecording ? ProcessInfo.processInfo.systemUptime : nil
        defer { if let perfStart { JerkgramPerformanceDiagnostics.shared.measure((Thread.isMainThread ? "main." : "worker.") + "avatarDiskStore", milliseconds: (ProcessInfo.processInfo.systemUptime - perfStart) * 1000.0) } }
        guard let url = self.ghostBaseAvatarDiskCacheURL(identity: identity) else {
            return
        }

        self.ghostBaseAvatarDiskCacheLock.lock()
        // This identity includes the immutable resource id and final-v2 cache namespace.
        // Only an image-readable, equally sized final entry may suppress a write; missing or
        // corrupt files must still be repaired. Keep the existing LRU access timestamp.
        let alreadyCached = self.ghostBaseTouchMatchingAvatarDiskCache(url: url, image: image)
        self.ghostBaseAvatarDiskCacheLock.unlock()
        if alreadyCached {
            return
        }
        // JPEG encoding must stay outside the lock also used by main-thread cache loads.
        guard let data = image.jpegData(compressionQuality: 0.88) else {
            return
        }
        self.ghostBaseAvatarDiskCacheLock.lock()
        defer { self.ghostBaseAvatarDiskCacheLock.unlock() }
        // Another final emission may have filled the same identity while we encoded.
        if self.ghostBaseTouchMatchingAvatarDiskCache(url: url, image: image) {
            return
        }
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

        let sorted = urls.map { url in
            let date = (try? url.resourceValues(
                forKeys: [.contentModificationDateKey]
            ).contentModificationDate) ?? .distantPast
            return (url: url, date: date)
        }.sorted { lhs, rhs in
            return lhs.date < rhs.date
        }

        for old in sorted.prefix(
            max(0, sorted.count - self.ghostBaseAvatarDiskCacheLimit)
        ) {
            try? fm.removeItem(at: old.url)
        }
    }

    // Caller owns ghostBaseAvatarDiskCacheLock.
    private static func ghostBaseTouchMatchingAvatarDiskCache(url: URL, image: UIImage) -> Bool {
        guard let cached = UIImage(contentsOfFile: url.path),
              cached.cgImage != nil, image.cgImage != nil,
              cached.cgImage?.width == image.cgImage?.width,
              cached.cgImage?.height == image.cgImage?.height else {
            return false
        }
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
        return true
    }

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

    // One native Telegram decoder/timeline owns playback.
    // The fullscreen backdrop is a secondary render output.
    private let mirrorVideoView: GhostBaseProfileMirrorVideoView
    private var desiredVideoIdentity: String?
    private var secondaryVideoDisposable: Disposable?
    private weak var lastAvatarVideoNode: UniversalVideoNode?


    private let sourceDisposable = MetaDisposable()
    let performanceProbe = JerkgramProfilePerformanceProbe()
    private var sourceSubscriptionRetained = false
    private var sourceSubscribedAt: TimeInterval?
    private var isSceneActive = false
    private var isControllerVisible = false
    private var isApplicationActive = UIApplication.shared.applicationState == .active
    private var lifecycleObservers: [NSObjectProtocol] = []
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
        self.performanceProbe.outputIdentity = String(describing: ObjectIdentifier(self.mirrorVideoView.videoLayer))

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
        for name in [UIApplication.willResignActiveNotification, UIApplication.didBecomeActiveNotification] {
            self.lifecycleObservers.append(NotificationCenter.default.addObserver(
                forName: name, object: nil, queue: .main,
                using: { [weak self] _ in
                    guard let self else { return }
                    self.isApplicationActive = name == UIApplication.didBecomeActiveNotification
                    self.setSceneActive(self.isControllerVisible)
                }
            ))
        }
    }

    required init?(coder: NSCoder) {
        preconditionFailure("init(coder:) has not been implemented")
    }

    deinit {
        for observer in self.lifecycleObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        if let visualSettingsObserver =
            self.visualSettingsObserver {

            NotificationCenter.default.removeObserver(
                visualSettingsObserver
            )
        }

        self.secondaryVideoDisposable?.dispose()
        self.secondaryVideoDisposable = nil
        self.setSourceSubscription(nil)
        self.sourceDisposable.dispose()
        self.performanceProbe.summary("deinit", sourceRetained: self.sourceSubscriptionRetained, outputRetained: self.secondaryVideoDisposable != nil)
    }

    func beginPerformanceSpan(_ stage: JerkgramProfilePerformanceProbe.Stage) -> TimeInterval {
        return self.performanceProbe.begin(stage)
    }

    func endPerformanceSpan(_ stage: JerkgramProfilePerformanceProbe.Stage, _ started: TimeInterval) {
        self.performanceProbe.end(stage, started)
    }

    private func setSourceSubscription(_ value: Disposable?) {
        if self.sourceSubscriptionRetained { self.performanceProbe.disposals += 1 }
        self.sourceDisposable.set(value)
        self.sourceSubscriptionRetained = value != nil
        self.sourceSubscribedAt = value == nil ? nil : ProcessInfo.processInfo.systemUptime
        if value != nil { self.performanceProbe.subscriptions += 1 }
    }

    private func recordSourceReady() {
        self.performanceProbe.ready += 1
        if let started = self.sourceSubscribedAt {
            JerkgramPerformanceDiagnostics.shared.measure(self.performanceProbe.context + ".sourceReadyWall", milliseconds: (ProcessInfo.processInfo.systemUptime - started) * 1000.0)
            self.performanceProbe.readyMaxWallMs = max(self.performanceProbe.readyMaxWallMs, (ProcessInfo.processInfo.systemUptime - started) * 1000.0)
            self.sourceSubscribedAt = nil
        }
    }

    private func requestSceneUpdate() {
        self.performanceProbe.updateRequests += 1
        self.requestUpdate?()
    }

    private func tearDownForDisabledSettings() {
        self.setSourceSubscription(nil)

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

    func setSceneActive(_ active: Bool) {
        self.isControllerVisible = active
        let active = active && self.isApplicationActive
        guard self.isSceneActive != active else {
            return
        }
        self.isSceneActive = active
        self.currentStateKey = nil
        self.currentLoadKey = nil
        if active {
            self.requestSceneUpdate()
        } else {
            let detach = self.beginPerformanceSpan(.detach)
            self.setSourceSubscription(nil)
            self.secondaryVideoDisposable?.dispose()
            self.secondaryVideoDisposable = nil
            self.mirrorVideoView.isHidden = true
            self.mirrorVideoView.videoLayer.flushAndRemoveImage()
            self.endPerformanceSpan(.detach, detach)
            self.performanceProbe.summary("inactive", sourceRetained: self.sourceSubscriptionRetained, outputRetained: self.secondaryVideoDisposable != nil)
        }
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
        guard self.isSceneActive else {
            return
        }
        self.requestSceneUpdate()
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
        self.performanceProbe.context = isSettings ? "settings" : "peer"
        let timing = self.beginPerformanceSpan(.background)
        defer { self.endPerformanceSpan(.background, timing) }
        guard self.isSceneActive else {
            return
        }
        let preferencesTiming = self.beginPerformanceSpan(.bgPreferences)
        let loadedSettings = GhostBaseProfileBlurSettings.loadEnabled()
        self.endPerformanceSpan(.bgPreferences, preferencesTiming)
        guard let liveSettings = loadedSettings else {
            self.tearDownForDisabledSettings()
            return
        }

        self.settings = liveSettings
        self.isHidden = false

        let resolveTiming = self.beginPerformanceSpan(.bgResolve)
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
        self.endPerformanceSpan(.bgResolve, resolveTiming)
        guard self.currentStateKey != stateKey else {
            return
        }
        self.currentStateKey = stateKey
        let applyTiming = self.beginPerformanceSpan(.bgApply)
        defer { self.endPerformanceSpan(.bgApply, applyTiming) }
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
            self.isSceneActive,
            self.window != nil,
            self.desiredVideoIdentity != nil,
            let videoNode
        else {
            return
        }

        if self.secondaryVideoDisposable == nil {
            let timing = self.beginPerformanceSpan(.attach)
            defer { self.endPerformanceSpan(.attach, timing) }
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
        self.setSourceSubscription(nil)
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
            self.setSourceSubscription((self.wallpaperEntrySignal(
                wallpaper: wallpaper,
                fallback: metadataTint,
                identity: loadKey
            )
            |> deliverOnMainQueue).start(next: { [weak self] entry in
                guard let self, self.currentLoadKey == loadKey, let entry else {
                    return
                }
                self.recordSourceReady()
                Self.imageCache.setObject(entry, forKey: cacheKey)
                self.imageView.image = entry.image
                self.applyTint(entry.tint, fallback: metadataTint, isDark: isDark, reduced: reduced)
                self.requestSceneUpdate()
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
            self.setSourceSubscription((deferred { () -> Signal<GhostBaseProfileBackgroundCacheEntry?, NoError> in
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
                self.recordSourceReady()
                Self.imageCache.setObject(entry, forKey: cacheKey)
                self.imageView.image = entry.image
                self.applyTint(entry.tint, fallback: main, isDark: isDark, reduced: reduced)
                self.requestSceneUpdate()
            }))

        case let .avatar(
            peer,
            representation,
            resourceId,
            animatedSource
        ):
            self.usesCustomBackground = true

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

            // Final avatar RAM hit: immutable resource identity, no new subscription.
            if let cached = Self.imageCache.object(forKey: cacheKey) {
                self.performanceProbe.ramHits += 1
                self.imageView.image = cached.image
                self.applyTint(
                    cached.tint,
                    fallback: fallback,
                    isDark: isDark,
                    reduced: reduced
                )
                return
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

            self.setSourceSubscription((signal
            |> deliverOnMainQueue).start(next: { [weak self] entry in
                guard let self, self.currentLoadKey == loadKey, let entry else {
                    return
                }
                self.recordSourceReady()
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
                self.requestSceneUpdate()
            }))

        case let .placeholder(
            peer,
            main,
            secondary,
            identity
        ):
            self.clearAnimatedMedia()
            self.setSourceSubscription(nil)
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
        //
        // The fullscreen background stays visible, but the single existing
        // tint layer now also provides adaptive contrast. This is deliberately
        // one scene-wide layer, not per-cell blur/glass.
        let sourceColor = color
        let luminance = Self.colorLuminance(sourceColor)
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

    private func avatarEntrySignal(
        peer: EnginePeer,
        representation: TelegramMediaImageRepresentation,
        identity: String,
        fallback: UIColor
    ) -> Signal<GhostBaseProfileBackgroundCacheEntry?, NoError>? {
        let context = self.context
        return deferred { () -> Signal<GhostBaseProfileBackgroundCacheEntry?, NoError> in
            // Disk read/decode/tint and AvatarNode subscription all start off main.
            if let image = Self.ghostBaseLoadAvatarDiskCache(identity: identity) {
                return .single(GhostBaseProfileBackgroundCacheEntry(
                    image: image,
                    tint: Self.sampledTint(from: image, fallback: fallback)
                ))
            }
            // produces a 360x360 unclipped presentation. Do not decode the raw
            // MediaBox resource as UIImage and do not request the 720px V11S path.
            guard let signal = peerAvatarImage(
                account: context.account,
                peerReference: PeerReference(peer),
                authorOfMessage: nil,
                representation: representation,
                displayDimensions: CGSize(width: 360.0, height: 360.0),
                clipStyle: .none,
                blurred: false,
                inset: 0.0,
                emptyColor: nil,
                synchronousLoad: false,
                completeOnly: true
            ) else {
                return .single(nil)
            }

            return signal
            |> deliverOn(Queue.concurrentDefaultQueue())
            |> map { versions -> GhostBaseProfileBackgroundCacheEntry? in
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
        |> runOn(Queue.concurrentDefaultQueue())
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
        let perfStart = JerkgramPerformanceDiagnostics.shared.isRecording ? ProcessInfo.processInfo.systemUptime : nil
        defer { if let perfStart { JerkgramPerformanceDiagnostics.shared.measure((Thread.isMainThread ? "main." : "worker.") + "wallpaperImage", milliseconds: (ProcessInfo.processInfo.systemUptime - perfStart) * 1000.0) } }
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
        let perfStart = JerkgramPerformanceDiagnostics.shared.isRecording ? ProcessInfo.processInfo.systemUptime : nil
        defer { if let perfStart { JerkgramPerformanceDiagnostics.shared.measure((Thread.isMainThread ? "main." : "worker.") + "gradientImage", milliseconds: (ProcessInfo.processInfo.systemUptime - perfStart) * 1000.0) } }
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
        let perfStart = JerkgramPerformanceDiagnostics.shared.isRecording ? ProcessInfo.processInfo.systemUptime : nil
        defer { if let perfStart { JerkgramPerformanceDiagnostics.shared.measure((Thread.isMainThread ? "main." : "worker.") + "sampledTint", milliseconds: (ProcessInfo.processInfo.systemUptime - perfStart) * 1000.0) } }
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
