import Foundation

// MARK: Jerkgram v1.2G BUILD118_ARCHIVE_V2_1
public struct JerkgramSettingsSnapshot: Codable, Equatable {
    public let accountPeerId: Int64
    public var toggles: [String: Bool]
    public var integerValues: [String: Int64]
    public var stringValues: [String: String]

    public init(
        accountPeerId: Int64,
        toggles: [String: Bool] = [:],
        integerValues: [String: Int64] = [:],
        stringValues: [String: String] = [:]
    ) {
        self.accountPeerId = accountPeerId
        self.toggles = toggles
        self.integerValues = integerValues
        self.stringValues = stringValues
    }
}

public enum JerkgramArchiveComponent: String, Codable, CaseIterable {
    case settingsSnapshot
    case retentionPolicies
    case deletedMessages
    case editedMessages
    case recoveredMediaMetadata
    case profileHistory
    case presenceHistory
    case gifts
    case personalChannels
    case canonicalEvents
}

public struct JerkgramArchivePayloadDescriptor: Codable, Equatable {
    public let component: JerkgramArchiveComponent
    public let relativePath: String
    public let recordCount: Int
    public let uncompressedBytes: Int64
    public let sha256: String

    public init(
        component: JerkgramArchiveComponent,
        relativePath: String,
        recordCount: Int,
        uncompressedBytes: Int64,
        sha256: String
    ) {
        self.component = component
        self.relativePath = relativePath
        self.recordCount = recordCount
        self.uncompressedBytes = uncompressedBytes
        self.sha256 = sha256
    }
}

public struct JerkgramArchiveAccountManifest: Codable, Equatable {
    public let accountPeerId: Int64
    public let payloads: [JerkgramArchivePayloadDescriptor]

    public init(
        accountPeerId: Int64,
        payloads: [JerkgramArchivePayloadDescriptor]
    ) {
        self.accountPeerId = accountPeerId
        self.payloads = payloads
    }
}

public struct JerkgramArchiveManifestV2: Codable, Equatable {
    public let schemaVersion: Int
    public let createdAtMs: Int64
    public let accounts: [JerkgramArchiveAccountManifest]

    public init(createdAtMs: Int64, accounts: [JerkgramArchiveAccountManifest]) {
        self.schemaVersion = 2
        self.createdAtMs = createdAtMs
        self.accounts = accounts
    }
}

public enum JerkgramArchiveValidationError: Error, Equatable {
    case unsupportedVersion(Int)
    case unsafePath(String)
    case duplicatePath(String)
    case missingPayload(String)
    case undeclaredPayload(String)
    case checksumMismatch(String)
    case sizeMismatch(String)
    case unavailableAccount(Int64)
    case settingsConfirmationRequired
    case conflictsPresent(Int)
}

public enum JerkgramArchiveV2 {
    public static let schemaVersion = 2
    public static let maximumPayloadCount = 256
    public static let maximumUncompressedBytes: Int64 = 2 * 1_073_741_824

    public static func validateRelativePath(_ value: String) throws {
        let components = value.split(separator: "/", omittingEmptySubsequences: false)
        guard !value.isEmpty, !value.hasPrefix("/"),
              !components.contains(".."), !components.contains("."),
              !components.contains("") else {
            throw JerkgramArchiveValidationError.unsafePath(value)
        }
    }

    public static func validateExtractedPayloads(
        manifest: JerkgramArchiveManifestV2,
        payloads: [String: Data]
    ) throws {
        guard manifest.schemaVersion == self.schemaVersion else {
            throw JerkgramArchiveValidationError.unsupportedVersion(manifest.schemaVersion)
        }
        let descriptors = manifest.accounts.flatMap(\.payloads)
        guard descriptors.count <= self.maximumPayloadCount else {
            throw JerkgramArchiveValidationError.sizeMismatch("payload-count")
        }
        var declared = Set<String>()
        var total: Int64 = 0
        for descriptor in descriptors {
            try self.validateRelativePath(descriptor.relativePath)
            guard declared.insert(descriptor.relativePath).inserted else {
                throw JerkgramArchiveValidationError.duplicatePath(descriptor.relativePath)
            }
            guard let data = payloads[descriptor.relativePath] else {
                throw JerkgramArchiveValidationError.missingPayload(descriptor.relativePath)
            }
            total += Int64(data.count)
            guard Int64(data.count) == descriptor.uncompressedBytes else {
                throw JerkgramArchiveValidationError.sizeMismatch(descriptor.relativePath)
            }
            guard JerkgramSHA256.hex(data) == descriptor.sha256.lowercased() else {
                throw JerkgramArchiveValidationError.checksumMismatch(descriptor.relativePath)
            }
        }
        guard total <= self.maximumUncompressedBytes else {
            throw JerkgramArchiveValidationError.sizeMismatch("total")
        }
        if let undeclared = payloads.keys.first(where: { !declared.contains($0) }) {
            throw JerkgramArchiveValidationError.undeclaredPayload(undeclared)
        }
    }
}

public enum JerkgramArchiveV1Migrator {
    public static func migratedEvent(
        accountPeerId: Int64,
        chatPeerId: Int64,
        messageNamespace: Int32?,
        messageId: Int32?,
        kind: JerkgramEventKind,
        observedAtMs: Int64,
        discriminator: String,
        sequence: Int64,
        senderPeerId: Int64?,
        payload: JerkgramEventPayload
    ) -> JerkgramCanonicalEvent {
        return JerkgramCanonicalEvent(
            accountPeerId: accountPeerId,
            chatPeerId: chatPeerId,
            eventId: .migrated(
                accountPeerId: accountPeerId,
                chatPeerId: chatPeerId,
                messageNamespace: messageNamespace,
                messageId: messageId,
                kind: kind,
                observedAtMs: observedAtMs,
                discriminator: discriminator
            ),
            sequence: sequence,
            kind: kind,
            senderPeerId: senderPeerId,
            messageNamespace: messageNamespace,
            messageId: messageId,
            observedAtMs: observedAtMs,
            payload: payload
        )
    }
}

// Foundation-only SHA-256 keeps JerkgramCore usable from TelegramCore without
// adding a platform crypto dependency.
public enum JerkgramSHA256 {
    private static let constants: [UInt32] = [
        0x428a2f98,0x71374491,0xb5c0fbcf,0xe9b5dba5,0x3956c25b,0x59f111f1,0x923f82a4,0xab1c5ed5,
        0xd807aa98,0x12835b01,0x243185be,0x550c7dc3,0x72be5d74,0x80deb1fe,0x9bdc06a7,0xc19bf174,
        0xe49b69c1,0xefbe4786,0x0fc19dc6,0x240ca1cc,0x2de92c6f,0x4a7484aa,0x5cb0a9dc,0x76f988da,
        0x983e5152,0xa831c66d,0xb00327c8,0xbf597fc7,0xc6e00bf3,0xd5a79147,0x06ca6351,0x14292967,
        0x27b70a85,0x2e1b2138,0x4d2c6dfc,0x53380d13,0x650a7354,0x766a0abb,0x81c2c92e,0x92722c85,
        0xa2bfe8a1,0xa81a664b,0xc24b8b70,0xc76c51a3,0xd192e819,0xd6990624,0xf40e3585,0x106aa070,
        0x19a4c116,0x1e376c08,0x2748774c,0x34b0bcb5,0x391c0cb3,0x4ed8aa4a,0x5b9cca4f,0x682e6ff3,
        0x748f82ee,0x78a5636f,0x84c87814,0x8cc70208,0x90befffa,0xa4506ceb,0xbef9a3f7,0xc67178f2,
    ]

    public static func hex(_ data: Data) -> String {
        var message = [UInt8](data)
        let bitLength = UInt64(message.count) * 8
        message.append(0x80)
        while message.count % 64 != 56 { message.append(0) }
        message.append(contentsOf: (0..<8).reversed().map { UInt8((bitLength >> UInt64($0 * 8)) & 0xff) })
        var hash: [UInt32] = [0x6a09e667,0xbb67ae85,0x3c6ef372,0xa54ff53a,0x510e527f,0x9b05688c,0x1f83d9ab,0x5be0cd19]
        for offset in stride(from: 0, to: message.count, by: 64) {
            var words = [UInt32](repeating: 0, count: 64)
            for index in 0..<16 {
                let base = offset + index * 4
                words[index] = UInt32(message[base]) << 24 | UInt32(message[base + 1]) << 16 | UInt32(message[base + 2]) << 8 | UInt32(message[base + 3])
            }
            for index in 16..<64 {
                let s0 = rotate(words[index - 15], 7) ^ rotate(words[index - 15], 18) ^ (words[index - 15] >> 3)
                let s1 = rotate(words[index - 2], 17) ^ rotate(words[index - 2], 19) ^ (words[index - 2] >> 10)
                words[index] = words[index - 16] &+ s0 &+ words[index - 7] &+ s1
            }
            var work = hash
            for index in 0..<64 {
                let s1 = rotate(work[4], 6) ^ rotate(work[4], 11) ^ rotate(work[4], 25)
                let choice = (work[4] & work[5]) ^ (~work[4] & work[6])
                let temp1 = work[7] &+ s1 &+ choice &+ constants[index] &+ words[index]
                let s0 = rotate(work[0], 2) ^ rotate(work[0], 13) ^ rotate(work[0], 22)
                let majority = (work[0] & work[1]) ^ (work[0] & work[2]) ^ (work[1] & work[2])
                let temp2 = s0 &+ majority
                work = [temp1 &+ temp2, work[0], work[1], work[2], work[3] &+ temp1, work[4], work[5], work[6]]
            }
            for index in 0..<8 { hash[index] = hash[index] &+ work[index] }
        }
        return hash.map { String(format: "%08x", $0) }.joined()
    }

    private static func rotate(_ value: UInt32, _ count: UInt32) -> UInt32 {
        return (value >> count) | (value << (32 - count))
    }
}
