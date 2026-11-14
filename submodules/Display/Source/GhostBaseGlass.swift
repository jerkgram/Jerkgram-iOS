import Foundation
import UIKit

// JG170 settings policy begin
public enum JerkgramSettingsSurfacePolicy {
    public static func active(isSettings: Bool, accepts: Bool, master: Bool, enabled: Bool, hasBackdrop: Bool) -> Bool {
        return isSettings && accepts && master && enabled && hasBackdrop
    }
}
// JG170 settings policy end

// JGC material policy begin
public enum JerkgramSettingsMaterialPolicy {
    public static func active(optIn: Bool, master: Bool, enabled: Bool, reduceTransparency: Bool) -> Bool {
        return optIn && master && enabled && !reduceTransparency
    }
    public static func itemAlpha(isDark: Bool) -> Double { return isDark ? 0.34 : 0.26 }
    public static func cardAlpha(isDark: Bool) -> Double { return isDark ? 0.60 : 0.70 }
}
// JGC material policy end

// JG176 pure policy begin
public enum JerkgramVisualPolicy {
    public static func allowsTransparency(reduceTransparency: Bool) -> Bool { return !reduceTransparency }
    public static func allowsMotion(lowPower: Bool, reduceTransparency: Bool) -> Bool { return !lowPower && !reduceTransparency }
    public static func shouldReconcile(visible: Bool, applied: UInt64?, current: UInt64, dirty: Bool) -> Bool {
        return visible && (applied != current || dirty)
    }
}
// JG176 pure policy end

public enum GhostBaseGlassStyle {
    public static let settingsTranslucencyKey = "jerkgram.Settings.Translucency"
    public static let settingsStyleDidChange = Notification.Name("jerkgram.SettingsSurfaceDidChange")
    private static var settingsTranslucencyValue = UserDefaults.standard.object(forKey: settingsTranslucencyKey) as? Bool ?? false

    private static var revision: UInt64 = 0
    private static var environment = (UIAccessibility.isReduceTransparencyEnabled, ProcessInfo.processInfo.isLowPowerModeEnabled)
    private static var themeIdentity: ObjectIdentifier?
    public static func invalidateVisualEnvironment() {
        let updated = (UIAccessibility.isReduceTransparencyEnabled, ProcessInfo.processInfo.isLowPowerModeEnabled)
        self.enabledLock.lock()
        let changed = self.environment.0 != updated.0 || self.environment.1 != updated.1
        if changed { self.environment = updated; self.revision &+= 1 }
        self.enabledLock.unlock()
        if changed { self.notifySettingsStyleChanged() }
    }
    public static func publishThemeChange(identity: ObjectIdentifier) {
        self.enabledLock.lock()
        let previous = self.themeIdentity
        self.themeIdentity = identity
        let changed = previous != nil && previous != identity
        if changed { self.revision &+= 1 }
        self.enabledLock.unlock()
        if changed { self.notifySettingsStyleChanged() }
    }
    public static var visualRevision: UInt64 {
        self.enabledLock.lock(); defer { self.enabledLock.unlock() }
        return self.revision
    }
    private static func notifySettingsStyleChanged() {
        JerkgramWave1Instrumentation.add("visualPublications")
        DispatchQueue.main.async { NotificationCenter.default.post(name: self.settingsStyleDidChange, object: nil) }
    }
    public static var settingsTranslucencyEnabled: Bool {
        self.enabledLock.lock()
        defer { self.enabledLock.unlock() }
        return self.settingsTranslucencyValue
    }
    public static func setSettingsTranslucencyEnabled(_ value: Bool) {
        self.enabledLock.lock()
        guard self.settingsTranslucencyValue != value else { self.enabledLock.unlock(); return }
        self.settingsTranslucencyValue = value
        self.preferenceGeneration &+= 1
        self.revision &+= 1
        self.enabledLock.unlock()
        self.notifySettingsStyleChanged()
    }

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
        let settingsTranslucency = defaults.object(forKey: self.settingsTranslucencyKey) as? Bool ?? false
        let animated = defaults.object(forKey: "jerkgram.ProfileBlur.Animated") as? Bool ?? true
        let avatar = defaults.object(forKey: "jerkgram.ProfileBlur.Avatar") as? Bool ?? true
        let tint = defaults.object(forKey: "jerkgram.ProfileBlur.Tint") as? Bool ?? true
        let reduced = defaults.object(forKey: "jerkgram.ProfileBlur.Reduced") as? Bool ?? false
        let hideOwnPhone = defaults.object(forKey: "jerkgram.Appearance.HideOwnPhone") as? Bool ?? false
        self.enabledLock.lock()
        defer { self.enabledLock.unlock() }
        guard self.preferenceGeneration == generation else { return }
        let changed = self.enabledValue != enabled || self.settingsTranslucencyValue != settingsTranslucency || self.profileAnimatedValue != animated || self.profileAvatarValue != avatar || self.profileTintValue != tint || self.profileReducedValue != reduced || self.profileHideOwnPhoneValue != hideOwnPhone
        guard changed else { return }
        self.revision &+= 1
        self.enabledValue = enabled
        self.settingsTranslucencyValue = settingsTranslucency
        self.profileAnimatedValue = animated
        self.profileAvatarValue = avatar
        self.profileTintValue = tint
        self.profileReducedValue = reduced
        self.profileHideOwnPhoneValue = hideOwnPhone
        self.notifySettingsStyleChanged()
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

    public static func setProfilePlaybackSettings(glassEnabled: Bool, animatedBackgroundEnabled: Bool, avatarBlurInProfile: Bool? = nil, tintEnabled: Bool? = nil, reducedBlur: Bool? = nil, hideOwnPhone: Bool? = nil, settingsTranslucencyEnabled: Bool? = nil, forceVisualChange: Bool = false) {
        // Controller projects profile and phone keys before atomic publication.
        self.enabledLock.lock()
        let changed = forceVisualChange || self.enabledValue != glassEnabled || self.profileAnimatedValue != animatedBackgroundEnabled || avatarBlurInProfile.map { $0 != self.profileAvatarValue } == true || tintEnabled.map { $0 != self.profileTintValue } == true || reducedBlur.map { $0 != self.profileReducedValue } == true || hideOwnPhone.map { $0 != self.profileHideOwnPhoneValue } == true || settingsTranslucencyEnabled.map { $0 != self.settingsTranslucencyValue } == true
        guard changed else { self.enabledLock.unlock(); return }
        self.revision &+= 1
        if let settingsTranslucencyEnabled { self.settingsTranslucencyValue = settingsTranslucencyEnabled }
        self.enabledValue = glassEnabled
        self.profileAnimatedValue = animatedBackgroundEnabled
        if let avatarBlurInProfile { self.profileAvatarValue = avatarBlurInProfile }
        if let tintEnabled { self.profileTintValue = tintEnabled }
        if let reducedBlur { self.profileReducedValue = reducedBlur }
        if let hideOwnPhone { self.profileHideOwnPhoneValue = hideOwnPhone }
        self.preferenceGeneration &+= 1
        self.enabledLock.unlock()
        self.notifySettingsStyleChanged()
    }

    public static var isEnabled: Bool {
        self.enabledLock.lock()
        defer { self.enabledLock.unlock() }
        return self.enabledValue
    }

    public static var allowsTransparentSurfaces: Bool { return JerkgramVisualPolicy.allowsTransparency(reduceTransparency: UIAccessibility.isReduceTransparencyEnabled) }
    public static var allowsMaterial: Bool { return JerkgramVisualPolicy.allowsMotion(lowPower: ProcessInfo.processInfo.isLowPowerModeEnabled, reduceTransparency: UIAccessibility.isReduceTransparencyEnabled) }
    public static var allowsVideo: Bool { return self.allowsMaterial }

    public static var usesReducedEffects: Bool {
        return UIAccessibility.isReduceTransparencyEnabled || ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    public static func setEnabled(_ value: Bool) {
        UserDefaults.standard.set(value, forKey: self.enabledKey)
        self.enabledLock.lock()
        guard self.enabledValue != value else { self.enabledLock.unlock(); return }
        self.enabledValue = value
        self.preferenceGeneration &+= 1
        self.revision &+= 1
        self.enabledLock.unlock()
        self.notifySettingsStyleChanged()
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

// Default OFF. No timers, observers, formatting or telemetry.
public enum JerkgramWave1Instrumentation {
#if JERKGRAM_PERF_AUDIT
    private static let lock = NSLock()
    private static var counters: [String: Int] = [:]
#endif
    @inline(__always) public static func add(_ counter: String, _ delta: Int = 1) {
#if JERKGRAM_PERF_AUDIT
        lock.lock(); counters[counter, default: 0] += delta; lock.unlock()
#endif
    }
    public static func snapshot() -> [String: Int] {
#if JERKGRAM_PERF_AUDIT
        lock.lock(); defer { lock.unlock() }; return counters
#else
        return [:]
#endif
    }
}
