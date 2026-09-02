import Foundation
import Display
import SwiftSignalKit
import TelegramCore
import TelegramPresentationData
import PresentationDataUtils
import AccountContext
import AlertUI
import LegacyMediaPickerUI
import JerkgramCore
import ZipArchive

// MARK: Jerkgram v1.2G BUILD118_ARCHIVE_FLOW1
private let jerkgramPortableBooleanKeys: [String] = [
    "jerkgram.Profile.Enabled", "jerkgram.Profile.ShowIds", "jerkgram.Profile.ShowDCs",
    "jerkgram.Profile.ShowRegistration", "jerkgram.Glass.Enabled",
    "jerkgram.ProfileBlur.Avatar", "jerkgram.ProfileBlur.Animated",
    "jerkgram.ProfileBlur.Tint", "jerkgram.ProfileBlur.Reduced",
    "jerkgram.GhostMode.ReadMessages", "jerkgram.GhostMode.TypingActions",
    "jerkgram.GhostMode.HideRecording", "jerkgram.GhostMode.HideUploading",
    "jerkgram.GhostMode.HideStickerActivity", "jerkgram.GhostMode.HideGameActivity",
    "jerkgram.GhostMode.HideEmojiActivity", "jerkgram.GhostMode.Presence",
    "jerkgram.GhostMode.ScheduledSend", "jerkgram.Messages.SaveDeleted",
    "jerkgram.Messages.ShowDeleted", "jerkgram.Messages.SaveEditHistory",
    "jerkgram.Messages.ShowEditHistory", "jerkgram.Messages.DeletedPortableReplies",
    "jerkgram.Messages.PreserveDeletedMedia", "jerkgram.Appearance.ShowRamUnderClock",
    "jerkgram.Appearance.MessageSeconds", "jerkgram.Appearance.HideOwnPhone",
    "jerkgram.ProtectedContent.Enabled", "jerkgram.ProtectedContent.GalleryShare",
    "jerkgram.ProtectedContent.GallerySave", "jerkgram.ProtectedContent.GalleryCopy",
    "jerkgram.ProtectedContent.ChatSave", "jerkgram.ProtectedContent.ChatCopy",
    "jerkgram.ProtectedContent.ChatForward", "jerkgram.ProtectedContent.AllowScreenshots",
    "jerkgram.ProtectedContent.AllowScreenRecording",
    "jerkgram.ProtectedContent.OneTimeScreenshots",
    "jerkgram.ProtectedContent.OneTimeScreenRecording",
    "jerkgram.ProtectedContent.OneTimeSave", "jerkgram.Stories.Save",
    "jerkgram.Stars.LocalBalance.Enabled",
]

private let jerkgramPortableStringKeys = [
    "jerkgram.Messages.SendTextStyle",
    "jerkgram.Stars.LocalBalance.Amount",
    "jerkgram.Stars.LocalBalance.BaseAmount",
]

private let jerkgramPortableIntegerKeys = [
    "jerkgram.Messages.DeletedMediaCacheLimit",
    "jerkgram.Messages.DeletedMediaRetentionDays",
]

private func jerkgramCoreRootURL() -> URL {
    return FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Jerkgram", isDirectory: true)
}

private func jerkgramSettingsSnapshot(accountPeerId: Int64) -> JerkgramSettingsSnapshot {
    var toggles: [String: Bool] = [:]
    var strings: [String: String] = [:]
    var integers: [String: Int64] = [:]
    for key in jerkgramPortableBooleanKeys {
        let scoped = "jerkgram.account.\(accountPeerId).setting.\(key)"
        if let value = UserDefaults.standard.object(forKey: scoped) as? Bool {
            toggles[key] = value
        } else if let value = UserDefaults.standard.object(forKey: key) as? Bool {
            toggles[key] = value
        }
    }
    for key in jerkgramPortableStringKeys {
        let scoped = "jerkgram.account.\(accountPeerId).setting.\(key)"
        if let value = UserDefaults.standard.string(forKey: scoped) {
            strings[key] = value
        } else if let value = UserDefaults.standard.string(forKey: key) {
            strings[key] = value
        }
    }
    for key in jerkgramPortableIntegerKeys {
        let scoped = "jerkgram.account.\(accountPeerId).setting.\(key)"
        if let value = UserDefaults.standard.object(forKey: scoped) as? NSNumber {
            integers[key] = value.int64Value
        } else if let value = UserDefaults.standard.object(forKey: key) as? NSNumber {
            integers[key] = value.int64Value
        }
    }
    return JerkgramSettingsSnapshot(
        accountPeerId: accountPeerId,
        toggles: toggles,
        integerValues: integers,
        stringValues: strings
    )
}

private func jerkgramWritePayload<T: Encodable>(
    _ value: T,
    component: JerkgramArchiveComponent,
    relativePath: String,
    rootURL: URL,
    recordCount: Int
) throws -> JerkgramArchivePayloadDescriptor {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys]
    let data = try encoder.encode(value)
    let url = rootURL.appendingPathComponent(relativePath)
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: url, options: .atomic)
    return JerkgramArchivePayloadDescriptor(
        component: component,
        relativePath: relativePath,
        recordCount: recordCount,
        uncompressedBytes: Int64(data.count),
        sha256: JerkgramSHA256.hex(data)
    )
}

// MARK: Jerkgram v1.2M BUILD124_ARCHIVE_EXPORT_RUNTIME1
private func jerkgramPresentArchiveExportError(
    context: AccountContext,
    controller: ViewController,
    text: String
) {
    Queue.mainQueue().async {
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        let alert = textAlertController(
            context: context,
            title: presentationData.strings.jerkgram.exportArchive,
            text: text,
            actions: [
                TextAlertAction(
                    type: .defaultAction,
                    title: presentationData.strings.Common_OK,
                    action: {}
                )
            ]
        )
        controller.present(alert, in: .window(.root), with: nil)
    }
}

public func jerkgramPresentArchiveExport(
    context: AccountContext,
    controller: ViewController
) {
    let accountPeerId = context.account.peerId.toInt64()

    // Full event snapshotting, JSON encoding and ZIP creation are intentionally
    // kept off the UI thread. Flush the recorder on this worker first so the
    // archive does not race the 250 ms capture buffer and silently miss the
    // newest deleted/edited events.
    Queue.concurrentDefaultQueue().async {
        let workURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("jerkgram-export-\(UUID().uuidString)", isDirectory: true)
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("Jerkgram-\(accountPeerId)-Build124.jerkgram")
        do {
            JerkgramCaptureRecorder.flushSynchronously()
            try FileManager.default.createDirectory(at: workURL, withIntermediateDirectories: true)
            let base = "accounts/\(accountPeerId)"
            let settings = jerkgramSettingsSnapshot(accountPeerId: accountPeerId)
            let retention = JerkgramRetentionRuntime.configuration(accountPeerId: accountPeerId)
            let eventStore = JerkgramJSONLEventStore(rootURL: jerkgramCoreRootURL())

            // Never convert a canonical-store failure into an apparently valid
            // empty archive. If reading history fails, surface that failure and
            // leave the user's canonical store untouched.
            let events = try eventStore.events(accountPeerId: accountPeerId, chatPeerId: nil)
            let descriptors = try [
                jerkgramWritePayload(
                    settings,
                    component: .settingsSnapshot,
                    relativePath: "\(base)/settings.json",
                    rootURL: workURL,
                    recordCount: settings.toggles.count + settings.stringValues.count
                ),
                jerkgramWritePayload(
                    retention,
                    component: .retentionPolicies,
                    relativePath: "\(base)/retention.json",
                    rootURL: workURL,
                    recordCount: retention.chatOverrides.count + 1
                ),
                jerkgramWritePayload(
                    events,
                    component: .canonicalEvents,
                    relativePath: "\(base)/events.json",
                    rootURL: workURL,
                    recordCount: events.count
                ),
            ]
            let manifest = JerkgramArchiveManifestV2(
                createdAtMs: Int64(Date().timeIntervalSince1970 * 1000.0),
                accounts: [
                    JerkgramArchiveAccountManifest(
                        accountPeerId: accountPeerId,
                        payloads: descriptors
                    )
                ]
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.sortedKeys]
            try encoder.encode(manifest).write(
                to: workURL.appendingPathComponent("manifest.json"),
                options: .atomic
            )
            try? FileManager.default.removeItem(at: outputURL)
            guard SSZipArchive.createZipFile(
                atPath: outputURL.path,
                withContentsOfDirectory: workURL.path
            ) else {
                throw CocoaError(.fileWriteUnknown)
            }

            Queue.mainQueue().async {
                let presentationData = context.sharedContext.currentPresentationData.with { $0 }
                let picker = legacyICloudFilePicker(
                    theme: presentationData.theme,
                    mode: .export,
                    url: outputURL,
                    documentTypes: [],
                    dismissed: {
                        try? FileManager.default.removeItem(at: workURL)
                        try? FileManager.default.removeItem(at: outputURL)
                    },
                    completion: { _ in
                        try? FileManager.default.removeItem(at: workURL)
                        try? FileManager.default.removeItem(at: outputURL)
                    }
                )
                controller.present(picker, in: .window(.root), with: nil)
            }
        } catch {
            try? FileManager.default.removeItem(at: workURL)
            try? FileManager.default.removeItem(at: outputURL)
            jerkgramPresentArchiveExportError(
                context: context,
                controller: controller,
                text: String(describing: error)
            )
        }
    }
}

private final class JerkgramRuntimeRetentionStore: JerkgramRetentionConfigurationStore {
    func configuration(accountPeerId: Int64) throws -> JerkgramRetentionConfiguration {
        return JerkgramRetentionRuntime.configuration(accountPeerId: accountPeerId)
    }

    func replace(_ configuration: JerkgramRetentionConfiguration) throws {
        try JerkgramRetentionRuntime.save(configuration)
    }
}

private final class JerkgramUserDefaultsSnapshotStore: JerkgramSettingsSnapshotStore {
    func snapshot(accountPeerId: Int64) throws -> JerkgramSettingsSnapshot {
        return jerkgramSettingsSnapshot(accountPeerId: accountPeerId)
    }

    func replace(_ snapshot: JerkgramSettingsSnapshot) throws {
        // Replacement is exact so a failed transaction can restore absence as
        // well as values; otherwise newly introduced keys would leak past rollback.
        for key in jerkgramPortableBooleanKeys + jerkgramPortableStringKeys + jerkgramPortableIntegerKeys {
            let scoped = "jerkgram.account.\(snapshot.accountPeerId).setting.\(key)"
            UserDefaults.standard.removeObject(forKey: scoped)
        }
        for (key, value) in snapshot.toggles {
            UserDefaults.standard.set(value, forKey: "jerkgram.account.\(snapshot.accountPeerId).setting.\(key)")
        }
        for (key, value) in snapshot.stringValues {
            UserDefaults.standard.set(value, forKey: "jerkgram.account.\(snapshot.accountPeerId).setting.\(key)")
        }
        for (key, value) in snapshot.integerValues {
            UserDefaults.standard.set(value, forKey: "jerkgram.account.\(snapshot.accountPeerId).setting.\(key)")
        }
    }
}

// MARK: Jerkgram v1.2K BUILD122_ARCHIVE_ACTIVE_ACCOUNTS1
// MARK: Jerkgram v1.2M BUILD124_ARCHIVE_IMPORT_BACKGROUND1
private func jerkgramProjectImportedSettingsToActiveDefaults(_ snapshot: JerkgramSettingsSnapshot) {
    let defaults = UserDefaults.standard
    for (key, value) in snapshot.toggles {
        defaults.set(value, forKey: key)
    }
    for (key, value) in snapshot.stringValues {
        defaults.set(value, forKey: key)
    }
    for (key, value) in snapshot.integerValues {
        defaults.set(value, forKey: key)
    }

    // Archive v2 originally used Jerkgram-prefixed portable names while a few
    // low-level runtime owners still consume their legacy GhostBase projection.
    // Project both spellings for the three synchronous side-effect settings.
    let legacyRuntimeKeys: [String: String] = [
        "jerkgram.GhostMode.ScheduledSend": "GhostBase.GhostMode.ScheduledSend",
        "jerkgram.ProtectedContent.Enabled": "GhostBase.ProtectedContent.Enabled",
        "jerkgram.ProtectedContent.OneTimeSave": "GhostBase.ProtectedContent.OneTimeSave",
    ]
    for (portableKey, legacyKey) in legacyRuntimeKeys {
        if let value = snapshot.toggles[portableKey] {
            defaults.set(value, forKey: legacyKey)
            if legacyKey == "GhostBase.GhostMode.ScheduledSend" {
                (UserDefaults(suiteName: "group.ph.telegra.Telegraph") ?? defaults).set(value, forKey: legacyKey)
            }
        }
    }
}

private func jerkgramPresentArchiveImportError(
    context: AccountContext,
    controller: ViewController,
    presentationData: PresentationData,
    text: String
) {
    Queue.mainQueue().async {
        let alert = textAlertController(
            context: context,
            title: presentationData.strings.jerkgram.importArchive,
            text: text,
            actions: [
                TextAlertAction(
                    type: .defaultAction,
                    title: presentationData.strings.Common_OK,
                    action: {}
                )
            ]
        )
        controller.present(alert, in: .window(.root), with: nil)
    }
}

public func jerkgramPresentArchiveImport(
    context: AccountContext,
    controller: ViewController
) {
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    let picker = legacyICloudFilePicker(
        theme: presentationData.theme,
        mode: .import,
        documentTypes: ["public.zip-archive", "public.data"],
        completion: { urls in
            guard let sourceURL = urls.first else { return }
            let didAccess = sourceURL.startAccessingSecurityScopedResource()

            // ZIP enumeration/unzip, payload reads and JSON validation are all
            // potentially unbounded file I/O. Never execute them in the file
            // picker/UI callback.
            Queue.concurrentDefaultQueue().async {
                defer {
                    if didAccess {
                        sourceURL.stopAccessingSecurityScopedResource()
                    }
                }
                let workURL = FileManager.default.temporaryDirectory
                    .appendingPathComponent("jerkgram-import-\(UUID().uuidString)", isDirectory: true)
                defer { try? FileManager.default.removeItem(at: workURL) }

                do {
                    try FileManager.default.createDirectory(at: workURL, withIntermediateDirectories: true)
                    guard let entries = SSZipArchive.getEntriesForFile(atPath: sourceURL.path),
                          entries.count <= JerkgramArchiveV2.maximumPayloadCount + 1 else {
                        throw CocoaError(.fileReadCorruptFile)
                    }
                    for entry in entries {
                        let normalizedPath = entry.path.hasSuffix("/")
                            ? String(entry.path.dropLast())
                            : entry.path
                        if !normalizedPath.isEmpty {
                            try JerkgramArchiveV2.validateRelativePath(normalizedPath)
                        }
                    }
                    guard SSZipArchive.unzipFile(atPath: sourceURL.path, toDestination: workURL.path) else {
                        throw CocoaError(.fileReadCorruptFile)
                    }

                    let decoder = JSONDecoder()
                    let manifest = try decoder.decode(
                        JerkgramArchiveManifestV2.self,
                        from: Data(contentsOf: workURL.appendingPathComponent("manifest.json"))
                    )
                    let accountPeerId = context.account.peerId.toInt64()
                    guard let account = manifest.accounts.first(where: { $0.accountPeerId == accountPeerId }) else {
                        throw JerkgramArchiveValidationError.unavailableAccount(accountPeerId)
                    }

                    var payloads: [String: Data] = [:]
                    for descriptor in account.payloads {
                        payloads[descriptor.relativePath] = try Data(
                            contentsOf: workURL.appendingPathComponent(descriptor.relativePath)
                        )
                    }
                    try JerkgramArchiveV2.validateExtractedPayloads(
                        manifest: JerkgramArchiveManifestV2(
                            createdAtMs: manifest.createdAtMs,
                            accounts: [account]
                        ),
                        payloads: payloads
                    )

                    let base = "accounts/\(accountPeerId)"
                    guard let settingsData = payloads["\(base)/settings.json"],
                          let retentionData = payloads["\(base)/retention.json"],
                          let eventsData = payloads["\(base)/events.json"] else {
                        throw JerkgramArchiveValidationError.missingPayload(base)
                    }
                    let settings = try decoder.decode(JerkgramSettingsSnapshot.self, from: settingsData)
                    let retention = try decoder.decode(JerkgramRetentionConfiguration.self, from: retentionData)
                    let events = try decoder.decode([JerkgramCanonicalEvent].self, from: eventsData)

                    Queue.mainQueue().async {
                        let strings = presentationData.strings.jerkgram
                        let alert = textAlertController(
                            context: context,
                            title: strings.importArchive,
                            text: strings.importSettingsConfirmation(accountPeerId),
                            actions: [
                                TextAlertAction(
                                    type: .genericAction,
                                    title: presentationData.strings.Common_Cancel,
                                    action: {}
                                ),
                                TextAlertAction(
                                    type: .defaultAction,
                                    title: strings.importSettings,
                                    action: {
                                        // ArchiveTransaction loads/merges and may atomically
                                        // rewrite the complete canonical account store. Keep
                                        // that transaction and its rollback away from UI.
                                        Queue.concurrentDefaultQueue().async {
                                            do {
                                                let eventStore = JerkgramJSONLEventStore(
                                                    rootURL: jerkgramCoreRootURL()
                                                )
                                                let settingsStore = JerkgramUserDefaultsSnapshotStore()
                                                try JerkgramArchiveTransaction.apply(
                                                    selectedAccountPeerIds: [accountPeerId],
                                                    availableAccountPeerIds: [context.account.peerId.toInt64()],
                                                    incomingEvents: [accountPeerId: events],
                                                    incomingSettings: [accountPeerId: settings],
                                                    confirmSettingsChanges: true,
                                                    eventStore: eventStore,
                                                    settingsStore: settingsStore
                                                )
                                                try JerkgramRetentionRuntime.save(retention)
                                                jerkgramProjectImportedSettingsToActiveDefaults(settings)
                                                Queue.mainQueue().async {
                                                    jerkgramNotifySettingsImported(accountPeerId: accountPeerId)
                                                }
                                            } catch {
                                                jerkgramPresentArchiveImportError(
                                                    context: context,
                                                    controller: controller,
                                                    presentationData: presentationData,
                                                    text: String(describing: error)
                                                )
                                            }
                                        }
                                    }
                                ),
                            ]
                        )
                        controller.present(alert, in: .window(.root), with: nil)
                    }
                } catch {
                    jerkgramPresentArchiveImportError(
                        context: context,
                        controller: controller,
                        presentationData: presentationData,
                        text: String(describing: error)
                    )
                }
            }
        }
    )
    controller.present(picker, in: .window(.root), with: nil)
}

private func jerkgramPresentArchiveImportPicker(
    context: AccountContext,
    controller: ViewController,
    availableAccountPeerIds: Set<Int64>
) {
    let presentationData = context.sharedContext.currentPresentationData.with { $0 }
    let picker = legacyICloudFilePicker(
        theme: presentationData.theme,
        mode: .import,
        documentTypes: ["public.zip-archive", "public.data"],
        completion: { urls in
            guard let sourceURL = urls.first else { return }
            let didAccess = sourceURL.startAccessingSecurityScopedResource()
            defer { if didAccess { sourceURL.stopAccessingSecurityScopedResource() } }
            let workURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("jerkgram-import-\(UUID().uuidString)", isDirectory: true)
            do {
                try FileManager.default.createDirectory(at: workURL, withIntermediateDirectories: true)
                guard let entries = SSZipArchive.getEntriesForFile(atPath: sourceURL.path),
                      entries.count <= JerkgramArchiveV2.maximumPayloadCount + 1 else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                for entry in entries {
                    let normalizedPath = entry.path.hasSuffix("/")
                        ? String(entry.path.dropLast())
                        : entry.path
                    if !normalizedPath.isEmpty {
                        try JerkgramArchiveV2.validateRelativePath(normalizedPath)
                    }
                }
                guard SSZipArchive.unzipFile(atPath: sourceURL.path, toDestination: workURL.path) else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                let decoder = JSONDecoder()
                let manifest = try decoder.decode(
                    JerkgramArchiveManifestV2.self,
                    from: Data(contentsOf: workURL.appendingPathComponent("manifest.json"))
                )
                var payloads: [String: Data] = [:]
                for descriptor in manifest.accounts.flatMap(\.payloads) {
                    payloads[descriptor.relativePath] = try Data(contentsOf: workURL.appendingPathComponent(descriptor.relativePath))
                }
                try JerkgramArchiveV2.validateExtractedPayloads(manifest: manifest, payloads: payloads)

                let matchingAccounts = manifest.accounts.filter { availableAccountPeerIds.contains($0.accountPeerId) }
                guard !matchingAccounts.isEmpty else {
                    throw JerkgramArchiveValidationError.unavailableAccount(manifest.accounts.first?.accountPeerId ?? 0)
                }
                let selectedAccountPeerIds = Set(matchingAccounts.map(\.accountPeerId))
                let disconnected = manifest.accounts.map(\.accountPeerId).filter { !availableAccountPeerIds.contains($0) }.sorted()
                var incomingSettings: [Int64: JerkgramSettingsSnapshot] = [:]
                var incomingRetention: [Int64: JerkgramRetentionConfiguration] = [:]
                var incomingEvents: [Int64: [JerkgramCanonicalEvent]] = [:]
                for account in matchingAccounts {
                    let accountPeerId = account.accountPeerId
                    let base = "accounts/\(accountPeerId)"
                    guard let settingsData = payloads["\(base)/settings.json"],
                          let retentionData = payloads["\(base)/retention.json"],
                          let eventsData = payloads["\(base)/events.json"] else {
                        throw JerkgramArchiveValidationError.missingPayload(base)
                    }
                    let settings = try decoder.decode(JerkgramSettingsSnapshot.self, from: settingsData)
                    let retention = try decoder.decode(JerkgramRetentionConfiguration.self, from: retentionData)
                    let events = try decoder.decode([JerkgramCanonicalEvent].self, from: eventsData)
                    guard settings.accountPeerId == accountPeerId, retention.accountPeerId == accountPeerId,
                          events.allSatisfy({ $0.accountPeerId == accountPeerId }) else {
                        throw JerkgramArchiveValidationError.unavailableAccount(accountPeerId)
                    }
                    incomingSettings[accountPeerId] = settings
                    incomingRetention[accountPeerId] = retention
                    incomingEvents[accountPeerId] = events
                }
                let strings = presentationData.strings.jerkgram
                let connectedLines = selectedAccountPeerIds.sorted().map { "✓ Telegram ID \($0)" }
                let disconnectedSuffix = strings.languageCode == "ru" ? "не подключён — пропущен" : "not connected — skipped"
                let disconnectedLines = disconnected.map { "— Telegram ID \($0) (\(disconnectedSuffix))" }
                let importPreview = (connectedLines + disconnectedLines).joined(separator: "\\n")
                let alert = textAlertController(
                    context: context,
                    title: strings.importArchive,
                    text: importPreview,
                    actions: [
                        TextAlertAction(type: .genericAction, title: presentationData.strings.Common_Cancel, action: {}),
                        TextAlertAction(type: .defaultAction, title: strings.importSettings, action: {
                            let eventStore = JerkgramJSONLEventStore(rootURL: jerkgramCoreRootURL())
                            let settingsStore = JerkgramUserDefaultsSnapshotStore()
                            // MARK: Jerkgram v1.2K BUILD122_ARCHIVE_RESULT_FEEDBACK1
                            let retentionStore = JerkgramRuntimeRetentionStore()
                            do {
                                try JerkgramArchiveTransaction.apply(
                                    selectedAccountPeerIds: selectedAccountPeerIds,
                                    availableAccountPeerIds: availableAccountPeerIds,
                                    incomingEvents: incomingEvents,
                                    incomingSettings: incomingSettings,
                                    confirmSettingsChanges: true,
                                    eventStore: eventStore,
                                    settingsStore: settingsStore,
                                    incomingRetention: incomingRetention,
                                    retentionStore: retentionStore
                                )
                                let result = textAlertController(
                                    context: context,
                                    title: strings.importArchive,
                                    text: strings.languageCode == "ru" ? "Импорт завершён." : "Import completed.",
                                    actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})]
                                )
                                controller.present(result, in: .window(.root), with: nil)
                            } catch {
                                let result = textAlertController(
                                    context: context,
                                    title: strings.importArchive,
                                    text: String(describing: error),
                                    actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})]
                                )
                                controller.present(result, in: .window(.root), with: nil)
                            }
                        }),
                    ]
                )
                controller.present(alert, in: .window(.root), with: nil)
            } catch {
                let alert = textAlertController(
                    context: context,
                    title: presentationData.strings.jerkgram.importArchive,
                    text: String(describing: error),
                    actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})]
                )
                controller.present(alert, in: .window(.root), with: nil)
            }
            try? FileManager.default.removeItem(at: workURL)
        }
    )
    controller.present(picker, in: .window(.root), with: nil)
}
