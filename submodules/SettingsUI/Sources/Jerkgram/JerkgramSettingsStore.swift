import Foundation

// MARK: Jerkgram v1.2E BUILD116_SETTINGS_FOUNDATION1
public enum JerkgramSendStyleV1: String, Codable, CaseIterable {
    case normal
    case bold
    case italic
    case monospace
    case strikethrough
    case underline
    case spoiler
}

public struct JerkgramSettingsV1: Codable, Equatable {
    public var schemaVersion: Int = 1
    public var sendStyle: JerkgramSendStyleV1
    public var saveDeletedMessages: Bool
    public var saveEditHistory: Bool
    public var portableDeletedReplies: Bool
    public var preserveDeletedMedia: Bool

    public init(
        sendStyle: JerkgramSendStyleV1 = .normal,
        saveDeletedMessages: Bool = false,
        saveEditHistory: Bool = false,
        portableDeletedReplies: Bool = false,
        preserveDeletedMedia: Bool = false
    ) {
        self.sendStyle = sendStyle
        self.saveDeletedMessages = saveDeletedMessages
        self.saveEditHistory = saveEditHistory
        self.portableDeletedReplies = portableDeletedReplies
        self.preserveDeletedMedia = preserveDeletedMedia
    }
}

public enum JerkgramSettingsStoreError: Error, Equatable {
    case unsupportedSchemaVersion(Int)
}

public final class JerkgramSettingsStore {
    private let fileURL: URL
    private let decoder = JSONDecoder()

    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    public func load() throws -> JerkgramSettingsV1 {
        guard FileManager.default.fileExists(atPath: self.fileURL.path) else {
            return JerkgramSettingsV1()
        }
        let value = try self.decoder.decode(
            JerkgramSettingsV1.self,
            from: Data(contentsOf: self.fileURL)
        )
        guard value.schemaVersion == 1 else {
            throw JerkgramSettingsStoreError.unsupportedSchemaVersion(value.schemaVersion)
        }
        return value
    }

    public func save(_ value: JerkgramSettingsV1) throws {
        guard value.schemaVersion == 1 else {
            throw JerkgramSettingsStoreError.unsupportedSchemaVersion(value.schemaVersion)
        }
        try FileManager.default.createDirectory(
            at: self.fileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = JSONEncoder.OutputFormatting.sortedKeys
        try encoder.encode(value).write(to: self.fileURL, options: .atomic)
    }
}
