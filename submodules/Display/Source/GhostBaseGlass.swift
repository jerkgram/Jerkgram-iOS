import Foundation
import UIKit

public enum GhostBaseGlassStyle {
    public static let enabledKey = "jerkgram.Glass.Enabled"

    private static let enabledLock = NSLock()
    private static var enabledValue: Bool = {
        return UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true
    }()

    private static var profileAnimatedValue: Bool = {
        return UserDefaults.standard.object(forKey: "jerkgram.ProfileBlur.Animated") as? Bool ?? true
    }()

    private static var profileAvatarValue = UserDefaults.standard.object(forKey: "jerkgram.ProfileBlur.Avatar") as? Bool ?? true
    private static var profileTintValue = UserDefaults.standard.object(forKey: "jerkgram.ProfileBlur.Tint") as? Bool ?? true
    private static var profileReducedValue = UserDefaults.standard.object(forKey: "jerkgram.ProfileBlur.Reduced") as? Bool ?? false
    private static var profileHideOwnPhoneValue = UserDefaults.standard.object(forKey: "jerkgram.Appearance.HideOwnPhone") as? Bool ?? false

    private static var preferenceGeneration: UInt64 = 0

    public static func reloadFromDefaults() {
        // Account projection/import calls this after updating active defaults.
        // Explicit refresh I/O is outside the hot lock; lazy bootstrap is once.
        self.enabledLock.lock()
        self.preferenceGeneration &+= 1
        let generation = self.preferenceGeneration
        self.enabledLock.unlock()
        let defaults = UserDefaults.standard
        let enabled = defaults.object(forKey: self.enabledKey) as? Bool ?? true
        let animated = defaults.object(forKey: "jerkgram.ProfileBlur.Animated") as? Bool ?? true
        let avatar = defaults.object(forKey: "jerkgram.ProfileBlur.Avatar") as? Bool ?? true
        let tint = defaults.object(forKey: "jerkgram.ProfileBlur.Tint") as? Bool ?? true
        let reduced = defaults.object(forKey: "jerkgram.ProfileBlur.Reduced") as? Bool ?? false
        let hideOwnPhone = defaults.object(forKey: "jerkgram.Appearance.HideOwnPhone") as? Bool ?? false
        self.enabledLock.lock()
        defer { self.enabledLock.unlock() }
        guard self.preferenceGeneration == generation else { return }
        self.enabledValue = enabled
        self.profileAnimatedValue = animated
        self.profileAvatarValue = avatar
        self.profileTintValue = tint
        self.profileReducedValue = reduced
        self.profileHideOwnPhoneValue = hideOwnPhone
    }

    public static var profileBlurSettings: GhostBaseProfileBlurSettings? {
        self.enabledLock.lock()
        defer { self.enabledLock.unlock() }
        guard self.enabledValue else { return nil }
        return GhostBaseProfileBlurSettings(
            avatarBlurInProfile: self.profileAvatarValue,
            animatedBackgroundEnabled: self.profileAnimatedValue,
            tintEnabled: self.profileTintValue,
            reducedBlur: self.profileReducedValue
        )
    }

    public static var profileAnimatedBackgroundEnabled: Bool {
        self.enabledLock.lock()
        defer { self.enabledLock.unlock() }
        return self.enabledValue && self.profileAnimatedValue
    }

    public static var profileHideOwnPhone: Bool {
        self.enabledLock.lock()
        defer { self.enabledLock.unlock() }
        return self.profileHideOwnPhoneValue
    }

    public static func setProfilePlaybackSettings(glassEnabled: Bool, animatedBackgroundEnabled: Bool, avatarBlurInProfile: Bool? = nil, tintEnabled: Bool? = nil, reducedBlur: Bool? = nil, hideOwnPhone: Bool? = nil) {
        // Controller projects profile and phone keys before atomic publication.
        self.enabledLock.lock()
        self.enabledValue = glassEnabled
        self.profileAnimatedValue = animatedBackgroundEnabled
        if let avatarBlurInProfile { self.profileAvatarValue = avatarBlurInProfile }
        if let tintEnabled { self.profileTintValue = tintEnabled }
        if let reducedBlur { self.profileReducedValue = reducedBlur }
        if let hideOwnPhone { self.profileHideOwnPhoneValue = hideOwnPhone }
        self.preferenceGeneration &+= 1
        self.enabledLock.unlock()
    }

    public static var isEnabled: Bool {
        self.enabledLock.lock()
        defer { self.enabledLock.unlock() }
        return self.enabledValue
    }

    public static var usesReducedEffects: Bool {
        return UIAccessibility.isReduceTransparencyEnabled || ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    public static func setEnabled(_ value: Bool) {
        UserDefaults.standard.set(value, forKey: self.enabledKey)
        self.enabledLock.lock()
        self.enabledValue = value
        self.preferenceGeneration &+= 1
        self.enabledLock.unlock()
    }

    // Pure compatibility tokens for the existing lightweight settings/gifts
    // surfaces. They hold no peer palette, observers or persisted tint state.
    public static var backdropOverlayAlpha: CGFloat {
        return self.usesReducedEffects ? 0.78 : 0.52
    }

    public static var coldSurfaceAlpha: CGFloat {
        return self.usesReducedEffects ? 0.92 : 0.70
    }

    public static var lightweightSurfaceAlpha: CGFloat {
        return self.usesReducedEffects ? 0.96 : 0.82
    }

    public static var borderAlpha: CGFloat {
        return self.usesReducedEffects ? 0.08 : 0.20
    }

    public static let compactCornerRadius: CGFloat = 13.0
    public static let cardCornerRadius: CGFloat = 18.0

    public static func coldFillColor(_ base: UIColor) -> UIColor {
        guard self.isEnabled else {
            return base
        }
        return base.withAlphaComponent(self.coldSurfaceAlpha)
    }

    public static func lightweightFillColor(_ base: UIColor) -> UIColor {
        guard self.isEnabled else {
            return base
        }
        return base.withAlphaComponent(self.lightweightSurfaceAlpha)
    }

    public static func lightweightTintColor(_ base: UIColor) -> UIColor {
        guard self.isEnabled else {
            return base
        }
        return base.withAlphaComponent(self.usesReducedEffects ? 0.94 : 0.18)
    }

    public static func borderColor(_ base: UIColor) -> UIColor {
        guard self.isEnabled else {
            return .clear
        }
        return base.withAlphaComponent(self.borderAlpha)
    }

    public static func activeTintColor(fallback: UIColor) -> UIColor {
        // Never inherit a process-global or previous-peer tint.
        return fallback
    }
}

public struct GhostBaseProfileBlurSettings: Equatable {
    public static let avatarBlurKey = "jerkgram.ProfileBlur.Avatar"
    public static let animatedKey = "jerkgram.ProfileBlur.Animated"
    public static let tintKey = "jerkgram.ProfileBlur.Tint"
    public static let reducedKey = "jerkgram.ProfileBlur.Reduced"

    public let avatarBlurInProfile: Bool
    public let animatedBackgroundEnabled: Bool
    public let tintEnabled: Bool
    public let reducedBlur: Bool

    // Master gate and all child values are read atomically from the snapshot.
    // Defaults bootstrap is once; explicit account/import refresh stays supported.
    public static func loadEnabled() -> GhostBaseProfileBlurSettings? {
        return GhostBaseGlassStyle.profileBlurSettings
    }
}
