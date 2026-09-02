import Foundation

// MARK: Jerkgram v1.2G BUILD118_ARCHIVE_TRANSACTION1
public enum JerkgramImportEventDisposition: Equatable {
    case new
    case duplicate
    case conflict
}

public struct JerkgramImportAccountPreview: Equatable {
    public let accountPeerId: Int64
    public let newCount: Int
    public let duplicateCount: Int
    public let conflictCount: Int
    public let uncompressedBytes: Int64
}

public struct JerkgramImportPreview: Equatable {
    public let accounts: [JerkgramImportAccountPreview]
    public let settingsWillChange: Bool
}

public protocol JerkgramSettingsSnapshotStore: AnyObject {
    func snapshot(accountPeerId: Int64) throws -> JerkgramSettingsSnapshot
    func replace(_ snapshot: JerkgramSettingsSnapshot) throws
}

// MARK: Jerkgram v1.2K BUILD122_ARCHIVE_EXACT_ACCOUNTS1
public protocol JerkgramRetentionConfigurationStore: AnyObject {
    func configuration(accountPeerId: Int64) throws -> JerkgramRetentionConfiguration
    func replace(_ configuration: JerkgramRetentionConfiguration) throws
}

public enum JerkgramArchiveTransaction {
    public static func classify(
        incoming: JerkgramCanonicalEvent,
        existingById: [JerkgramEventId: JerkgramCanonicalEvent]
    ) -> JerkgramImportEventDisposition {
        guard let existing = existingById[incoming.eventId] else { return .new }
        return existing == incoming ? .duplicate : .conflict
    }

    public static func apply(
        selectedAccountPeerIds: Set<Int64>,
        availableAccountPeerIds: Set<Int64>,
        incomingEvents: [Int64: [JerkgramCanonicalEvent]],
        incomingSettings: [Int64: JerkgramSettingsSnapshot],
        confirmSettingsChanges: Bool,
        eventStore: JerkgramEventStore,
        settingsStore: JerkgramSettingsSnapshotStore,
        incomingRetention: [Int64: JerkgramRetentionConfiguration] = [:],
        retentionStore: JerkgramRetentionConfigurationStore? = nil
    ) throws {
        guard selectedAccountPeerIds.isSubset(of: availableAccountPeerIds) else {
            let missing = selectedAccountPeerIds.subtracting(availableAccountPeerIds).sorted().first!
            throw JerkgramArchiveValidationError.unavailableAccount(missing)
        }
        if !incomingSettings.keys.filter(selectedAccountPeerIds.contains).isEmpty && !confirmSettingsChanges {
            throw JerkgramArchiveValidationError.settingsConfirmationRequired
        }

        var eventRollback: [Int64: [JerkgramCanonicalEvent]] = [:]
        var settingsRollback: [Int64: JerkgramSettingsSnapshot] = [:]
        var retentionRollback: [Int64: JerkgramRetentionConfiguration] = [:]
        do {
            for accountPeerId in selectedAccountPeerIds.sorted() {
                let existing = try eventStore.events(accountPeerId: accountPeerId, chatPeerId: nil)
                eventRollback[accountPeerId] = existing
                settingsRollback[accountPeerId] = try settingsStore.snapshot(accountPeerId: accountPeerId)
                if incomingRetention[accountPeerId] != nil, let retentionStore {
                    retentionRollback[accountPeerId] = try retentionStore.configuration(accountPeerId: accountPeerId)
                }
                let existingById = Dictionary(uniqueKeysWithValues: existing.map { ($0.eventId, $0) })
                var merged = existing
                var conflicts = 0
                for event in incomingEvents[accountPeerId] ?? [] {
                    guard event.accountPeerId == accountPeerId else {
                        throw JerkgramArchiveValidationError.unavailableAccount(event.accountPeerId)
                    }
                    switch classify(incoming: event, existingById: existingById) {
                    case .new:
                        merged.append(event)
                    case .duplicate:
                        break
                    case .conflict:
                        conflicts += 1
                    }
                }
                guard conflicts == 0 else {
                    throw JerkgramArchiveValidationError.conflictsPresent(conflicts)
                }
                try eventStore.replaceAtomically(accountPeerId: accountPeerId, events: merged)
                if let settings = incomingSettings[accountPeerId] {
                    guard settings.accountPeerId == accountPeerId else {
                        throw JerkgramArchiveValidationError.unavailableAccount(settings.accountPeerId)
                    }
                    try settingsStore.replace(settings)
                }
                if let retention = incomingRetention[accountPeerId], let retentionStore {
                    guard retention.accountPeerId == accountPeerId else {
                        throw JerkgramArchiveValidationError.unavailableAccount(retention.accountPeerId)
                    }
                    try retentionStore.replace(retention)
                }
            }
        } catch {
            // Rollback is best-effort for every already touched exact account;
            // original error remains the reported failure.
            for accountPeerId in eventRollback.keys.sorted() {
                if let events = eventRollback[accountPeerId] {
                    try? eventStore.replaceAtomically(accountPeerId: accountPeerId, events: events)
                }
                if let settings = settingsRollback[accountPeerId] {
                    try? settingsStore.replace(settings)
                }
                if let retention = retentionRollback[accountPeerId], let retentionStore {
                    try? retentionStore.replace(retention)
                }
            }
            throw error
        }
    }
}
