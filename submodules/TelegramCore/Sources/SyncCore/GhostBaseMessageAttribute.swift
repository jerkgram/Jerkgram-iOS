import Foundation
import Postbox

// MARK: Jerkgram v1.2L BUILD123_MESSAGE_SNAPSHOT1
public final class GhostBaseEditEntitySnapshot: PostboxCoding {
    public let entities: [MessageTextEntity]
    public let inlineStickerFiles: [TelegramMediaFile]

    public init(entities: [MessageTextEntity], inlineStickerFiles: [TelegramMediaFile]) {
        self.entities = entities
        self.inlineStickerFiles = inlineStickerFiles
    }

    required public init(decoder: PostboxDecoder) {
        self.entities = decoder.decodeObjectArrayWithDecoderForKey("e")
        self.inlineStickerFiles = decoder.decodeObjectArrayWithDecoderForKey("f")
    }

    public func encode(_ encoder: PostboxEncoder) {
        encoder.encodeObjectArray(self.entities, forKey: "e")
        encoder.encodeObjectArray(self.inlineStickerFiles, forKey: "f")
    }
}

public final class GhostBaseMessageAttribute: MessageAttribute {
    public let originalText: String?
    public let originalEntities: [MessageTextEntity]
    public let editHistoryTexts: [String]
    public let editHistoryDates: [String]
    public let editHistoryEntities: [String]
    public let editHistorySnapshots: [GhostBaseEditEntitySnapshot]
    public let isDeleted: Bool
    public let deletedAt: Int32

    public init(
        originalText: String?,
        editHistoryTexts: [String],
        editHistoryDates: [String],
        isDeleted: Bool,
        deletedAt: Int32,
        originalEntities: [MessageTextEntity] = [],
        editHistoryEntities: [String] = [],
        editHistorySnapshots: [GhostBaseEditEntitySnapshot] = []
    ) {
        self.originalText = originalText
        self.originalEntities = originalEntities
        self.editHistoryTexts = editHistoryTexts
        self.editHistoryDates = editHistoryDates
        self.editHistoryEntities = editHistoryEntities
        self.editHistorySnapshots = editHistorySnapshots
        self.isDeleted = isDeleted
        self.deletedAt = deletedAt
    }

    required public init(decoder: PostboxDecoder) {
        self.originalText = decoder.decodeOptionalStringForKey("ot")
        self.originalEntities = decoder.decodeObjectArrayWithDecoderForKey("oe")
        self.editHistoryTexts = decoder.decodeStringArrayForKey("eht")
        self.editHistoryDates = decoder.decodeStringArrayForKey("ehd")
        self.editHistoryEntities = decoder.decodeStringArrayForKey("ehe")
        self.editHistorySnapshots = decoder.decodeObjectArrayWithDecoderForKey("ehs")
        self.isDeleted = decoder.decodeInt32ForKey("del", orElse: 0) != 0
        self.deletedAt = decoder.decodeInt32ForKey("dat", orElse: 0)
    }

    public func encode(_ encoder: PostboxEncoder) {
        if let originalText = self.originalText { encoder.encodeString(originalText, forKey: "ot") }
        encoder.encodeObjectArray(self.originalEntities, forKey: "oe")
        encoder.encodeStringArray(self.editHistoryTexts, forKey: "eht")
        encoder.encodeStringArray(self.editHistoryDates, forKey: "ehd")
        encoder.encodeStringArray(self.editHistoryEntities, forKey: "ehe")
        encoder.encodeObjectArray(self.editHistorySnapshots, forKey: "ehs")
        encoder.encodeInt32(self.isDeleted ? 1 : 0, forKey: "del")
        encoder.encodeInt32(self.deletedAt, forKey: "dat")
    }

    private static func encodeEntities(_ entities: [MessageTextEntity]) -> String {
        guard let data = try? JSONEncoder().encode(entities) else { return "" }
        return data.base64EncodedString()
    }

    public func entitiesForEditVersion(_ index: Int) -> [MessageTextEntity] {
        if index >= 0, index < self.editHistorySnapshots.count {
            return self.editHistorySnapshots[index].entities
        }
        guard index >= 0, index < self.editHistoryEntities.count,
              let data = Data(base64Encoded: self.editHistoryEntities[index]),
              let entities = try? JSONDecoder().decode([MessageTextEntity].self, from: data) else {
            return []
        }
        return entities
    }

    public func inlineStickerFilesForEditVersion(_ index: Int) -> [TelegramMediaFile] {
        guard index >= 0, index < self.editHistorySnapshots.count else { return [] }
        return self.editHistorySnapshots[index].inlineStickerFiles
    }

    public func withAddedEditVersion(text: String, date: Int32, entities: [MessageTextEntity] = [], inlineStickerFiles: [TelegramMediaFile] = []) -> GhostBaseMessageAttribute {
        var texts = self.editHistoryTexts
        var dates = self.editHistoryDates
        var entitySets = self.editHistoryEntities
        var snapshots = self.editHistorySnapshots
        let encodedEntities = Self.encodeEntities(entities)

        // Record text changes and entity-only edits (links, formatting, premium emoji).
        if texts.last != text || entitySets.last != encodedEntities {
            texts.append(text)
            dates.append(String(date))
            entitySets.append(encodedEntities)
            snapshots.append(GhostBaseEditEntitySnapshot(entities: entities, inlineStickerFiles: inlineStickerFiles))
            if texts.count > 30 {
                texts = Array(texts.suffix(30))
                dates = Array(dates.suffix(30))
                entitySets = Array(entitySets.suffix(30))
                snapshots = Array(snapshots.suffix(30))
            }
        }

        return GhostBaseMessageAttribute(
            originalText: self.originalText ?? text,
            editHistoryTexts: texts,
            editHistoryDates: dates,
            isDeleted: self.isDeleted,
            deletedAt: self.deletedAt,
            originalEntities: self.originalEntities.isEmpty ? entities : self.originalEntities,
            editHistoryEntities: entitySets,
            editHistorySnapshots: snapshots
        )
    }

    public func withUpdatedDeleted(isDeleted: Bool, deletedAt: Int32) -> GhostBaseMessageAttribute {
        return GhostBaseMessageAttribute(
            originalText: self.originalText,
            editHistoryTexts: self.editHistoryTexts,
            editHistoryDates: self.editHistoryDates,
            isDeleted: isDeleted,
            deletedAt: deletedAt,
            originalEntities: self.originalEntities,
            editHistoryEntities: self.editHistoryEntities,
            editHistorySnapshots: self.editHistorySnapshots
        )
    }
}
