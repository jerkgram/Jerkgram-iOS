import Foundation
import UIKit

// MARK: GhostBase v1.1F PROFILEBLURSETTINGS1
public enum GhostBaseGlassStyle {
    public static let enabledKey = "jerkgram.Glass.Enabled"

    public static var isEnabled: Bool {
        if let value = UserDefaults.standard.object(forKey: self.enabledKey) as? Bool {
            return value
        }
        return true
    }

    public static var usesReducedEffects: Bool {
        return UIAccessibility.isReduceTransparencyEnabled || ProcessInfo.processInfo.isLowPowerModeEnabled
    }

    public static func setEnabled(_ value: Bool) {
        UserDefaults.standard.set(value, forKey: self.enabledKey)
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

    // Reads the master key first. Child settings are not read and no profile
    // object is created when the effect is disabled.
    public static func loadEnabled() -> GhostBaseProfileBlurSettings? {
        guard GhostBaseGlassStyle.isEnabled else {
            return nil
        }
        let defaults = UserDefaults.standard
        return GhostBaseProfileBlurSettings(
            avatarBlurInProfile: defaults.object(forKey: self.avatarBlurKey) as? Bool ?? true,
            animatedBackgroundEnabled: defaults.object(forKey: self.animatedKey) as? Bool ?? true,
            tintEnabled: defaults.object(forKey: self.tintKey) as? Bool ?? true,
            reducedBlur: defaults.object(forKey: self.reducedKey) as? Bool ?? false
        )
    }
}
