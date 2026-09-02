import UIKit
import UserNotifications
import UserNotificationsUI
import TelegramUI
import BuildConfig


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

@objc(NotificationViewController)
@available(iOSApplicationExtension 10.0, iOS 10.0, *)
class NotificationViewController: UIViewController, UNNotificationContentExtension {
    private var impl: NotificationViewControllerImpl?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        
        if self.impl == nil {
            let appBundleIdentifier = Bundle.main.bundleIdentifier!
            guard let lastDotRange = appBundleIdentifier.range(of: ".", options: [.backwards]) else {
                return
            }
            _ = lastDotRange
            
            let baseAppBundleId = String(appBundleIdentifier[..<lastDotRange.lowerBound])
            
            
            let buildConfig = BuildConfig(baseAppBundleId: baseAppBundleId)
            
            let languagesCategory = "ios"
            
            let appGroupName = jerkgramResolvedApplicationGroupIdentifier(fallback: "group.\(baseAppBundleId)")
// MARK: Jerkgram v1.2E BUILD116_EXTENSION_STAGE1
BuildConfig.jerkgramRecordExtensionDiagnostic(
    process: "notificationContent",
    stage: "profile",
    appGroupIdentifier: appGroupName,
    sharedContainerPath: nil,
    detail: "selected app-group identifier"
)
            
            let maybeAppGroupUrl = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupName)
BuildConfig.jerkgramRecordExtensionDiagnostic(
    process: "notificationContent",
    stage: "container",
    appGroupIdentifier: appGroupName,
    sharedContainerPath: maybeAppGroupUrl?.path,
    detail: "containerURL resolved"
)
            
            guard let appGroupUrl = maybeAppGroupUrl else {
                return
            }
            
            let rootPath = appGroupUrl.path + "/telegram-data"
            
            let deviceSpecificEncryptionParameters = BuildConfig.deviceSpecificEncryptionParameters(rootPath, baseAppBundleId: baseAppBundleId)
BuildConfig.jerkgramRecordExtensionDiagnostic(
    process: "notificationContent",
    stage: "root",
    appGroupIdentifier: appGroupName,
    sharedContainerPath: appGroupUrl.path,
    detail: "telegram-data root ready"
)
BuildConfig.jerkgramRecordExtensionDiagnostic(
    process: "notificationContent",
    stage: "encryption",
    appGroupIdentifier: appGroupName,
    sharedContainerPath: appGroupUrl.path,
    detail: "encryption parameters ready"
)
            let encryptionParameters: (Data, Data) = (deviceSpecificEncryptionParameters.key, deviceSpecificEncryptionParameters.salt)
            
            let appVersion = (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "unknown"
            
            BuildConfig.jerkgramRecordExtensionDiagnostic(
                process: "notificationContent",
                stage: "account",
                appGroupIdentifier: appGroupName,
                sharedContainerPath: appGroupUrl.path,
                detail: "account-backed implementation initialization"
            )
            self.impl = NotificationViewControllerImpl(initializationData: NotificationViewControllerInitializationData(appBundleId: baseAppBundleId, appBuildType: buildConfig.isAppStoreBuild ? .public : .internal, appGroupPath: appGroupUrl.path, apiId: buildConfig.apiId, apiHash: buildConfig.apiHash, languagesCategory: languagesCategory, encryptionParameters: encryptionParameters, appVersion: appVersion, bundleData: buildConfig.bundleData(withAppToken: nil, tokenType: nil, tokenEnvironment: nil, signatureDict: nil), useBetaFeatures: !buildConfig.isAppStoreBuild), setPreferredContentSize: { [weak self] size in
                self?.preferredContentSize = size
            })
        }
        
        self.impl?.viewDidLoad(view: self.view)
    }
    
    func didReceive(_ notification: UNNotification) {
        self.impl?.didReceive(notification, view: self.view)
    }
    
    override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
        super.viewWillTransition(to: size, with: coordinator)
        
        self.impl?.viewWillTransition(to: size)
    }
}
