import Foundation
import Postbox
import TelegramApi
import SwiftSignalKit
import Emoji

public enum EnqueueMessageGrouping {
    case none
    case auto
}

public enum EngineMessageReplyInnerSubject: Codable, Equatable {
    case todoItem(Int32)
    case pollOption(Data)

    private enum CodingKeys: String, CodingKey {
        case type = "t"
        case value = "v"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let type = try container.decode(Int32.self, forKey: .type)
        switch type {
        case 0:
            self = .todoItem(try container.decode(Int32.self, forKey: .value))
        case 1:
            self = .pollOption(try container.decode(Data.self, forKey: .value))
        default:
            self = .todoItem(try container.decode(Int32.self, forKey: .value))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .todoItem(id):
            try container.encode(Int32(0), forKey: .type)
            try container.encode(id, forKey: .value)
        case let .pollOption(data):
            try container.encode(Int32(1), forKey: .type)
            try container.encode(data, forKey: .value)
        }
    }
}

public struct EngineMessageReplyQuote: Codable, Equatable {
    private enum CodingKeys: String, CodingKey {
        case text = "t"
        case entities = "e"
        case media = "m"
        case offset = "o"
    }
    
    public var text: String
    public var offset: Int?
    public var entities: [MessageTextEntity]
    public var media: Media?
    
    public init(text: String, offset: Int?, entities: [MessageTextEntity], media: Media?) {
        self.text = text
        self.offset = offset
        self.entities = entities
        self.media = media
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        
        self.text = try container.decode(String.self, forKey: .text)
        self.offset = (try container.decodeIfPresent(Int32.self, forKey: .offset)).flatMap(Int.init)
        self.entities = try container.decode([MessageTextEntity].self, forKey: .entities)
        
        if let mediaData = try container.decodeIfPresent(Data.self, forKey: .media) {
            self.media = PostboxDecoder(buffer: MemoryBuffer(data: mediaData)).decodeRootObject() as? Media
        } else {
            self.media = nil
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        
        try container.encode(self.text, forKey: .text)
        try container.encodeIfPresent(self.offset.flatMap(Int32.init(clamping:)), forKey: .offset)
        try container.encode(self.entities, forKey: .entities)
        if let media = self.media {
            let mediaEncoder = PostboxEncoder()
            mediaEncoder.encodeRootObject(media)
            try container.encode(mediaEncoder.makeData(), forKey: .media)
        }
    }
    
    public static func ==(lhs: EngineMessageReplyQuote, rhs: EngineMessageReplyQuote) -> Bool {
        if lhs.text != rhs.text {
            return false
        }
        if lhs.offset != rhs.offset {
            return false
        }
        if lhs.entities != rhs.entities {
            return false
        }
        if let lhsMedia = lhs.media, let rhsMedia = rhs.media {
            if !lhsMedia.isEqual(to: rhsMedia) {
                return false
            }
        } else {
            if (lhs.media == nil) != (rhs.media == nil) {
                return false
            }
        }
        return true
    }
}

public struct EngineMessageReplySubject: Codable, Equatable {
    public var messageId: EngineMessage.Id
    public var quote: EngineMessageReplyQuote?
    public var innerSubject: EngineMessageReplyInnerSubject?
    
    public init(messageId: EngineMessage.Id, quote: EngineMessageReplyQuote?, innerSubject: EngineMessageReplyInnerSubject?) {
        self.messageId = messageId
        self.quote = quote
        self.innerSubject = innerSubject
    }
}

public enum EnqueueMessage {
    case message(text: String, attributes: [MessageAttribute], inlineStickers: [MediaId: Media], mediaReference: AnyMediaReference?, threadId: Int64?, replyToMessageId: EngineMessageReplySubject?, replyToStoryId: StoryId?, localGroupingKey: Int64?, correlationId: Int64?, bubbleUpEmojiOrStickersets: [ItemCollectionId])
    case forward(source: MessageId, threadId: Int64?, grouping: EnqueueMessageGrouping, attributes: [MessageAttribute], correlationId: Int64?)
    
    public func withUpdatedReplyToMessageId(_ replyToMessageId: EngineMessageReplySubject?) -> EnqueueMessage {
        switch self {
        case let .message(text, attributes, inlineStickers, mediaReference, threadId, _, replyToStoryId, localGroupingKey, correlationId, bubbleUpEmojiOrStickersets):
            return .message(text: text, attributes: attributes, inlineStickers: inlineStickers, mediaReference: mediaReference, threadId: threadId, replyToMessageId: replyToMessageId, replyToStoryId: replyToStoryId, localGroupingKey: localGroupingKey, correlationId: correlationId, bubbleUpEmojiOrStickersets: bubbleUpEmojiOrStickersets)
        case .forward:
            return self
        }
    }
    
    public func withUpdatedReplyToStoryId(_ replyToStoryId: StoryId?) -> EnqueueMessage {
        switch self {
        case let .message(text, attributes, inlineStickers, mediaReference, threadId, replyToMessageId, _, localGroupingKey, correlationId, bubbleUpEmojiOrStickersets):
            return .message(text: text, attributes: attributes, inlineStickers: inlineStickers, mediaReference: mediaReference, threadId: threadId, replyToMessageId: replyToMessageId, replyToStoryId: replyToStoryId, localGroupingKey: localGroupingKey, correlationId: correlationId, bubbleUpEmojiOrStickersets: bubbleUpEmojiOrStickersets)
        case .forward:
            return self
        }
    }
    
    public func withUpdatedAttributes(_ f: ([MessageAttribute]) -> [MessageAttribute]) -> EnqueueMessage {
        switch self {
        case let .message(text, attributes, inlineStickers, mediaReference, threadId: threadId, replyToMessageId, replyToStoryId, localGroupingKey, correlationId, bubbleUpEmojiOrStickersets):
            return .message(text: text, attributes: f(attributes), inlineStickers: inlineStickers, mediaReference: mediaReference, threadId: threadId, replyToMessageId: replyToMessageId, replyToStoryId: replyToStoryId, localGroupingKey: localGroupingKey, correlationId: correlationId, bubbleUpEmojiOrStickersets: bubbleUpEmojiOrStickersets)
        case let .forward(source, threadId, grouping, attributes, correlationId):
            return .forward(source: source, threadId: threadId, grouping: grouping, attributes: f(attributes), correlationId: correlationId)
        }
    }
    
    public func withUpdatedGroupingKey(_ f: (Int64?) -> Int64?) -> EnqueueMessage {
        switch self {
        case let .message(text, attributes, inlineStickers, mediaReference, threadId, replyToMessageId, replyToStoryId, localGroupingKey, correlationId, bubbleUpEmojiOrStickersets):
            return .message(text: text, attributes: attributes, inlineStickers: inlineStickers, mediaReference: mediaReference, threadId: threadId, replyToMessageId: replyToMessageId, replyToStoryId: replyToStoryId, localGroupingKey: f(localGroupingKey), correlationId: correlationId, bubbleUpEmojiOrStickersets: bubbleUpEmojiOrStickersets)
        case .forward:
            return self
        }
    }

    public func withUpdatedCorrelationId(_ value: Int64?) -> EnqueueMessage {
        switch self {
        case let .message(text, attributes, inlineStickers, mediaReference, threadId, replyToMessageId, replyToStoryId, localGroupingKey, _, bubbleUpEmojiOrStickersets):
            return .message(text: text, attributes: attributes, inlineStickers: inlineStickers, mediaReference: mediaReference, threadId: threadId, replyToMessageId: replyToMessageId, replyToStoryId: replyToStoryId, localGroupingKey: localGroupingKey, correlationId: value, bubbleUpEmojiOrStickersets: bubbleUpEmojiOrStickersets)
        case let .forward(source, threadId, grouping, attributes, _):
            return .forward(source: source, threadId: threadId, grouping: grouping, attributes: attributes, correlationId: value)
        }
    }
    
    public func withUpdatedThreadId(_ threadId: Int64?) -> EnqueueMessage {
        switch self {
        case let .message(text, attributes, inlineStickers, mediaReference, _, replyToMessageId, replyToStoryId, localGroupingKey, correlationId, bubbleUpEmojiOrStickersets):
            return .message(text: text, attributes: attributes, inlineStickers: inlineStickers, mediaReference: mediaReference, threadId: threadId, replyToMessageId: replyToMessageId, replyToStoryId: replyToStoryId, localGroupingKey: localGroupingKey, correlationId: correlationId, bubbleUpEmojiOrStickersets: bubbleUpEmojiOrStickersets)
        case let .forward(source, _, grouping, attributes, correlationId):
            return .forward(source: source, threadId: threadId, grouping: grouping, attributes: attributes, correlationId: correlationId)
        }
    }
    
    public var groupingKey: Int64? {
        if case let .message(_, _, _, _, _, _, _, localGroupingKey, _, _) = self {
            return localGroupingKey
        } else {
            return nil
        }
    }
    
    public var attributes: [MessageAttribute] {
        switch self {
        case let .message(_, attributes, _, _, _, _, _, _, _, _):
            return attributes
        case let .forward(_, _, _, attributes, _):
            return attributes
        }
    }
}

private extension EnqueueMessage {
    var correlationId: Int64? {
        switch self {
        case let .message(_, _, _, _, _, _, _, _, correlationId, _):
            return correlationId
        case let .forward(_, _, _, _, correlationId):
            return correlationId
        }
    }
    
    var bubbleUpEmojiOrStickersets: [ItemCollectionId] {
        switch self {
        case let .message(_, _, _, _, _, _, _, _, _, bubbleUpEmojiOrStickersets):
            return bubbleUpEmojiOrStickersets
        case .forward:
            return []
        }
    }
}

func augmentMediaWithReference(_ mediaReference: AnyMediaReference) -> Media {
    if let file = mediaReference.media as? TelegramMediaFile {
        if file.partialReference != nil {
            return file
        } else {
            return file.withUpdatedPartialReference(mediaReference.partial)
        }
    } else if let image = mediaReference.media as? TelegramMediaImage {
        if image.partialReference != nil {
            return image
        } else {
            return image.withUpdatedPartialReference(mediaReference.partial)
        }
    } else {
        return mediaReference.media
    }
}

private func convertForwardedMediaForSecretChat(_ media: Media) -> Media {
    if let file = media as? TelegramMediaFile {
        return TelegramMediaFile(fileId: MediaId(namespace: Namespaces.Media.LocalFile, id: Int64.random(in: Int64.min ... Int64.max)), partialReference: file.partialReference, resource: file.resource, previewRepresentations: file.previewRepresentations, videoThumbnails: file.videoThumbnails, immediateThumbnailData: file.immediateThumbnailData, mimeType: file.mimeType, size: file.size, attributes: file.attributes, alternativeRepresentations: [])
    } else if let image = media as? TelegramMediaImage {
        return TelegramMediaImage(imageId: MediaId(namespace: Namespaces.Media.LocalImage, id: Int64.random(in: Int64.min ... Int64.max)), representations: image.representations, immediateThumbnailData: image.immediateThumbnailData, reference: image.reference, partialReference: image.partialReference, flags: [])
    } else {
        return media
    }
}

private func filterMessageAttributesForOutgoingMessage(_ attributes: [MessageAttribute]) -> [MessageAttribute] {
    return attributes.filter { attribute in
        switch attribute {
        case _ as TextEntitiesMessageAttribute:
            return true
        case _ as RichTextMessageAttribute:
            return true
        case _ as InlineBotMessageAttribute:
            return true
        case _ as OutgoingMessageInfoAttribute:
            return false
        case _ as OutgoingContentInfoMessageAttribute:
            return true
        case _ as ReplyMarkupMessageAttribute:
            return true
        case _ as OutgoingChatContextResultMessageAttribute:
            return true
        case _ as AutoremoveTimeoutMessageAttribute:
            return true
        case _ as NotificationInfoMessageAttribute:
            return true
        case _ as OutgoingScheduleInfoMessageAttribute:
            return true
        case _ as OutgoingQuickReplyMessageAttribute:
            return true
        case _ as EmbeddedMediaStickersMessageAttribute:
            return true
        case _ as EmojiSearchQueryMessageAttribute:
            return true
        case _ as ForwardOptionsMessageAttribute:
            return true
        case _ as SendAsMessageAttribute:
            return true
        case _ as MediaSpoilerMessageAttribute:
            return true
        case _ as WebpagePreviewMessageAttribute:
            return true
        case _ as InvertMediaMessageAttribute:
            return true
        case _ as EffectMessageAttribute:
            return true
        case _ as ForwardVideoTimestampAttribute:
            return true
        case _ as PaidStarsMessageAttribute:
            return true
        case _ as SuggestedPostMessageAttribute:
            return true
        case _ as EphemeralOutgoingMessageAttribute:
            assertionFailure("EphemeralOutgoingMessageAttribute must be routed before normal outgoing enqueue")
            return false
        default:
            return false
        }
    }
}

private func filterMessageAttributesForEphemeralOutgoingMessage(_ attributes: [MessageAttribute]) -> [MessageAttribute] {
    return attributes.filter { attribute in
        switch attribute {
        case _ as TextEntitiesMessageAttribute:
            return true
        case _ as EmbeddedMediaStickersMessageAttribute:
            return true
        case _ as EmojiSearchQueryMessageAttribute:
            return true
        case _ as MediaSpoilerMessageAttribute:
            return true
        case _ as WebpagePreviewMessageAttribute:
            return true
        case _ as InvertMediaMessageAttribute:
            return true
        case _ as ForwardVideoTimestampAttribute:
            return true
        default:
            return false
        }
    }
}

private func transientEphemeralOutgoingAttribute(_ attributes: [MessageAttribute]) -> EphemeralOutgoingMessageAttribute? {
    for attribute in attributes {
        if let attribute = attribute as? EphemeralOutgoingMessageAttribute, attribute.randomId == 0, attribute.state == .sending {
            return attribute
        }
    }
    return nil
}

private func ephemeralReplyTargetBotPeerId(transaction: Transaction, accountPeerId: PeerId, replySubject: EngineMessageReplySubject) -> PeerId? {
    guard replySubject.messageId.namespace == Namespaces.Message.EphemeralLocal, replySubject.messageId.id > 0, let replyMessage = transaction.getMessage(replySubject.messageId) else {
        return nil
    }

    if replyMessage.flags.contains(.Incoming) {
        guard let authorId = replyMessage.author?.id, authorId != accountPeerId else {
            return nil
        }
        return authorId
    }

    if let attribute = replyMessage.attributes.first(where: { $0 is EphemeralMessageAttribute }) as? EphemeralMessageAttribute, attribute.receiverId != 0 {
        return PeerId(namespace: Namespaces.Peer.CloudUser, id: PeerId.Id._internalFromInt64Value(attribute.receiverId))
    }

    return nil
}

private func ephemeralBotPeerIdForEnqueuedMessage(transaction: Transaction, accountPeerId: PeerId, message: EnqueueMessage) -> PeerId? {
    switch message {
    case let .message(_, attributes, _, _, _, replyToMessageId, _, _, _, _):
        if let attribute = transientEphemeralOutgoingAttribute(attributes) {
            return attribute.botPeerId
        }
        if let replyToMessageId, replyToMessageId.messageId.namespace == Namespaces.Message.EphemeralLocal {
            return ephemeralReplyTargetBotPeerId(transaction: transaction, accountPeerId: accountPeerId, replySubject: replyToMessageId)
        }
        return nil
    case .forward:
        return nil
    }
}

private func replyMessageAttributeForEphemeralOutgoingMessage(transaction: Transaction, peerId: PeerId, replySubject: EngineMessageReplySubject?) -> ReplyMessageAttribute? {
    guard let replySubject else {
        return nil
    }

    if replySubject.messageId.namespace == Namespaces.Message.EphemeralLocal {
        guard replySubject.messageId.id > 0 else {
            return nil
        }
        return ReplyMessageAttribute(messageId: replySubject.messageId, threadMessageId: nil, quote: nil, isQuote: false, innerSubject: nil)
    }

    guard replySubject.messageId.namespace == Namespaces.Message.Cloud else {
        return nil
    }

    var threadMessageId: MessageId?
    var quote = replySubject.quote
    let isQuote = quote != nil
    if let replyMessage = transaction.getMessage(replySubject.messageId) {
        if replyMessage.id.namespace == Namespaces.Message.Cloud, let threadId = replyMessage.threadId {
            threadMessageId = MessageId(peerId: replyMessage.id.peerId, namespace: Namespaces.Message.Cloud, id: Int32(clamping: threadId))
        }
        if quote == nil, replySubject.messageId.peerId != peerId {
            let nsText = replyMessage.text as NSString
            var replyMedia: Media?
            for media in replyMessage.media {
                switch media {
                case _ as TelegramMediaImage, _ as TelegramMediaFile:
                    replyMedia = media
                default:
                    break
                }
            }
            quote = EngineMessageReplyQuote(text: replyMessage.text, offset: nil, entities: messageTextEntitiesInRange(entities: replyMessage.textEntitiesAttribute?.entities ?? [], range: NSRange(location: 0, length: nsText.length), onlyQuoteable: true), media: replyMedia)
        }
    }

    return ReplyMessageAttribute(messageId: replySubject.messageId, threadMessageId: threadMessageId, quote: quote, isQuote: isQuote, innerSubject: replySubject.innerSubject)
}

private func generateEphemeralOutgoingRandomId() -> Int64 {
    while true {
        let value = Int64.random(in: Int64.min ... Int64.max)
        if value != 0 {
            return value
        }
    }
}

private func enqueueEphemeralOutgoingMessage(transaction: Transaction, account: Account, peerId: PeerId, transformedMedia: Bool, message: EnqueueMessage, botPeerId: PeerId) -> MessageId? {
    guard case let .message(text, requestedAttributes, inlineStickers, mediaReference, threadId, replyToMessageId, _, _, correlationId, bubbleUpEmojiOrStickersets) = message else {
        return nil
    }
    guard transaction.getPeer(peerId).flatMap(apiInputPeer) != nil, transaction.getPeer(botPeerId).flatMap(apiInputUser) != nil else {
        return nil
    }

    for (_, file) in inlineStickers {
        transaction.storeMediaIfNotPresent(media: file)
    }

    var flags = StoreMessageFlags()
    flags.insert(.Sending)

    let randomId = generateEphemeralOutgoingRandomId()
    var infoFlags = OutgoingMessageInfoFlags()
    if transformedMedia {
        infoFlags.insert(.transformedMedia)
    }

    var partialReference: PartialMediaReference?
    if let mediaReference {
        partialReference = mediaReference.partial
    }

    var attributes: [MessageAttribute] = filterMessageAttributesForEphemeralOutgoingMessage(requestedAttributes)
    attributes.append(OutgoingMessageInfoAttribute(uniqueId: randomId, flags: infoFlags, acknowledged: false, correlationId: correlationId, bubbleUpEmojiOrStickersets: bubbleUpEmojiOrStickersets, partialReference: partialReference))
    attributes.append(EphemeralOutgoingMessageAttribute(botPeerId: botPeerId, randomId: randomId, state: .sending))

    if let replyAttribute = replyMessageAttributeForEphemeralOutgoingMessage(transaction: transaction, peerId: peerId, replySubject: replyToMessageId) {
        attributes.append(replyAttribute)
    }

    var mediaList: [Media] = []
    if let mediaReference {
        mediaList.append(augmentMediaWithReference(mediaReference))
    }

    if let file = mediaReference?.media as? TelegramMediaFile, file.isVoice || file.isInstantVideo {
        if peerId.namespace == Namespaces.Peer.CloudUser || peerId.namespace == Namespaces.Peer.CloudGroup {
            attributes.append(ConsumableContentMessageAttribute(consumed: false))
        }
    }

    let localId = generateEphemeralLocalMessageId(peerId: peerId, transaction: transaction)
    let timestamp = Int32(account.network.context.globalTime())
    let storeMessage = StoreMessage(id: localId, customStableId: nil, globallyUniqueId: randomId, groupingKey: nil, threadId: threadId, timestamp: timestamp, flags: flags, tags: [], globalTags: [], localTags: [], forwardInfo: nil, authorId: account.peerId, text: text, attributes: attributes, media: mediaList)
    let _ = transaction.addMessages([storeMessage], location: .Random)

    return localId
}

private func filterMessageAttributesForForwardedMessage(_ attributes: [MessageAttribute], forwardedMessageIds: Set<MessageId>? = nil) -> [MessageAttribute] {
    return attributes.filter { attribute in
        switch attribute {
            case _ as TextEntitiesMessageAttribute:
                return true
            case _ as RichTextMessageAttribute:
                return true
            case _ as InlineBotMessageAttribute:
                return true
            case _ as NotificationInfoMessageAttribute:
                return true
            case _ as OutgoingScheduleInfoMessageAttribute:
                return true
            case _ as OutgoingQuickReplyMessageAttribute:
                return true
            case _ as ForwardOptionsMessageAttribute:
                return true
            case _ as SendAsMessageAttribute:
                return true
            case _ as MediaSpoilerMessageAttribute:
                return true
            case _ as InvertMediaMessageAttribute:
                return true
            case _ as PaidStarsMessageAttribute:
                return true
            case let attribute as ReplyMessageAttribute:
                if attribute.quote != nil {
                    return true
                }
                if let forwardedMessageIds = forwardedMessageIds {
                    return forwardedMessageIds.contains(attribute.messageId)
                } else {
                    return false
                }
            default:
                return false
        }
    }
}

func opportunisticallyTransformMessageWithMedia(network: Network, postbox: Postbox, transformOutgoingMessageMedia: TransformOutgoingMessageMedia, mediaReference: AnyMediaReference, userInteractive: Bool) -> Signal<AnyMediaReference?, NoError> {
    return transformOutgoingMessageMedia(postbox, network, mediaReference, userInteractive)
    |> timeout(2.0, queue: Queue.concurrentDefaultQueue(), alternate: .single(nil))
}

private func forwardedMessageToBeReuploaded(transaction: Transaction, id: MessageId) -> Message? {
    if let message = transaction.getMessage(id) {
        if message.id.namespace != Namespaces.Message.Cloud {
            return message
        } else {
            return nil
        }
    } else {
        return nil
    }
}

// MARK: GhostBase v1.1T BUILD105_FULL1
// Deferred deleted-reply materialization. Composer/reply preview stay stock;
// only the public enqueue boundary converts a locally retained deleted reply.
private let ghostBaseDeletedPortableRepliesKey =
    "jerkgram.Messages.DeletedPortableReplies"
private let ghostBaseSaveDeletedKey =
    "jerkgram.Messages.SaveDeleted"
private let ghostBasePreserveDeletedMediaKey =
    "jerkgram.Messages.PreserveDeletedMedia"
private let ghostBaseDeletedMediaCacheLimitKey =
    "jerkgram.Messages.DeletedMediaCacheLimit"
private let ghostBaseDeletedMediaRetentionDaysKey =
    "jerkgram.Messages.DeletedMediaRetentionDays"

private func ghostBaseDeletedBool(
    _ key: String,
    defaultValue: Bool
) -> Bool {
    if let value = UserDefaults.standard.object(forKey: key) as? Bool {
        return value
    }
    return defaultValue
}

private enum GhostBasePublicPeerNameStore {
    private static let valuesKey = "jerkgram.PublicPeerNames.V11T"
    private static let orderKey = "jerkgram.PublicPeerNamesOrder.V11T"
    private static let maximumCount = 256
    private static let lock = NSLock()

    static func store(
        peerId: PeerId,
        firstName: String,
        lastName: String
    ) {
        let first = firstName.trimmingCharacters(in: .whitespacesAndNewlines)
        let last = lastName.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = [first, last].filter { !$0.isEmpty }.joined(separator: " ")
        guard !name.isEmpty else {
            return
        }

        self.lock.lock()
        defer { self.lock.unlock() }

        let defaults = UserDefaults.standard
        var values = defaults.dictionary(
            forKey: self.valuesKey
        ) as? [String: String] ?? [:]
        var order = defaults.stringArray(forKey: self.orderKey) ?? []
        let key = String(peerId.toInt64())
        values[key] = name
        order.removeAll(where: { $0 == key })
        order.append(key)

        while order.count > self.maximumCount {
            let removed = order.removeFirst()
            values.removeValue(forKey: removed)
        }
        defaults.set(values, forKey: self.valuesKey)
        defaults.set(order, forKey: self.orderKey)
    }

    static func name(peerId: PeerId) -> String? {
        self.lock.lock()
        defer { self.lock.unlock() }
        return (
            UserDefaults.standard.dictionary(forKey: self.valuesKey)
            as? [String: String]
        )?[String(peerId.toInt64())]
    }
}

func ghostBaseStorePublicPeerName(
    peerId: PeerId,
    firstName: String,
    lastName: String
) {
    GhostBasePublicPeerNameStore.store(
        peerId: peerId,
        firstName: firstName,
        lastName: lastName
    )
}

private struct GhostBaseDeletedMediaResourceSpec {
    let resource: MediaResource
    let pathExtension: String?
}

private enum GhostBaseDeletedMediaCache {
    private static let queue = DispatchQueue(
        label: "org.ghostbase.deleted-media-cache",
        qos: .utility
    )
    private static let cleanupLock = NSLock()
    private static var lastCleanupTimestamp: TimeInterval = 0.0

    static func root(mediaBox: MediaBox) -> URL {
        return URL(fileURLWithPath: mediaBox.basePath, isDirectory: true)
            .appendingPathComponent(
                "ghostbase-deleted-media",
                isDirectory: true
            )
    }

    private static func safe(_ value: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(
            CharacterSet(charactersIn: "-_.")
        )
        let result = value.components(separatedBy: allowed.inverted)
            .filter { !$0.isEmpty }
            .joined(separator: "_")
        return result.isEmpty ? "resource" : result
    }

    private static func messageDirectory(
        mediaBox: MediaBox,
        messageId: MessageId
    ) -> URL {
        let folder = "\(messageId.peerId.toInt64())_\(messageId.namespace)_\(messageId.id)"
        return self.root(mediaBox: mediaBox).appendingPathComponent(
            self.safe(folder),
            isDirectory: true
        )
    }

    static func spec(media: Media) -> GhostBaseDeletedMediaResourceSpec? {
        if let image = media as? TelegramMediaImage,
           let largest = largestImageRepresentation(image.representations) {
            return GhostBaseDeletedMediaResourceSpec(
                resource: largest.resource,
                pathExtension: "jpg"
            )
        }

        if let file = media as? TelegramMediaFile {
            var ext: String?
            if let fileName = file.fileName {
                let value = (fileName as NSString).pathExtension
                if !value.isEmpty {
                    ext = value
                }
            }
            if ext == nil {
                switch file.mimeType.lowercased() {
                case "video/mp4":
                    ext = "mp4"
                case "video/webm":
                    ext = "webm"
                case "application/x-tgsticker":
                    ext = "tgs"
                case "image/webp":
                    ext = "webp"
                case "audio/ogg", "audio/opus":
                    ext = "ogg"
                case "audio/mpeg":
                    ext = "mp3"
                case "image/gif":
                    ext = "gif"
                default:
                    break
                }
            }
            return GhostBaseDeletedMediaResourceSpec(
                resource: file.resource,
                pathExtension: ext
            )
        }
        return nil
    }

    private static func fileURL(
        mediaBox: MediaBox,
        messageId: MessageId,
        spec: GhostBaseDeletedMediaResourceSpec
    ) -> URL {
        var name = self.safe(spec.resource.id.stringRepresentation)
        if let ext = spec.pathExtension, !ext.isEmpty {
            name += "." + self.safe(ext)
        } else {
            name += ".bin"
        }
        return self.messageDirectory(
            mediaBox: mediaBox,
            messageId: messageId
        ).appendingPathComponent(name)
    }

    private static func validFile(at url: URL) -> Bool {
        guard let attributes = try? FileManager.default.attributesOfItem(
            atPath: url.path
        ),
        let size = attributes[.size] as? NSNumber else {
            return false
        }
        return size.int64Value > 0
    }

    private static func copyCompleteResource(
        mediaBox: MediaBox,
        messageId: MessageId,
        spec: GhostBaseDeletedMediaResourceSpec
    ) -> String? {
        let destination = self.fileURL(
            mediaBox: mediaBox,
            messageId: messageId,
            spec: spec
        )
        let fm = FileManager.default

        if self.validFile(at: destination) {
            try? fm.setAttributes(
                [.modificationDate: Date()],
                ofItemAtPath: destination.path
            )
            return destination.path
        }

        guard let sourcePath = mediaBox.completedResourcePath(spec.resource),
              self.validFile(at: URL(fileURLWithPath: sourcePath)) else {
            return nil
        }

        do {
            try fm.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if fm.fileExists(atPath: destination.path) {
                try fm.removeItem(at: destination)
            }
            try fm.copyItem(
                at: URL(fileURLWithPath: sourcePath),
                to: destination
            )
            guard self.validFile(at: destination) else {
                try? fm.removeItem(at: destination)
                return nil
            }
            return destination.path
        } catch {
            return nil
        }
    }

    static func resolvePath(
        mediaBox: MediaBox,
        messageId: MessageId,
        media: Media
    ) -> String? {
        guard let spec = self.spec(media: media) else {
            return nil
        }
        let path = self.copyCompleteResource(
            mediaBox: mediaBox,
            messageId: messageId,
            spec: spec
        )
        self.cleanupIfNeeded(mediaBox: mediaBox)
        return path
    }

    static func preserve(
        mediaBox: MediaBox,
        message: Message
    ) {
        guard ghostBaseDeletedBool(
            ghostBasePreserveDeletedMediaKey,
            defaultValue: true
        ) else {
            return
        }

        let messageId = message.id
        let specs = message.media.compactMap { self.spec(media: $0) }
        guard !specs.isEmpty else {
            return
        }

        self.queue.async {
            for spec in specs {
                _ = self.copyCompleteResource(
                    mediaBox: mediaBox,
                    messageId: messageId,
                    spec: spec
                )
            }
            self.cleanupIfNeeded(mediaBox: mediaBox)
        }
    }

    static func remove(
        mediaBox: MediaBox,
        messageIds: [MessageId]
    ) {
        guard !messageIds.isEmpty else {
            return
        }
        self.queue.async {
            let fm = FileManager.default
            for id in messageIds {
                try? fm.removeItem(
                    at: self.messageDirectory(
                        mediaBox: mediaBox,
                        messageId: id
                    )
                )
            }
        }
    }

    private static func cleanupIfNeeded(mediaBox: MediaBox) {
        let now = Date().timeIntervalSince1970
        self.cleanupLock.lock()
        if now - self.lastCleanupTimestamp < 300.0 {
            self.cleanupLock.unlock()
            return
        }
        self.lastCleanupTimestamp = now
        self.cleanupLock.unlock()

        let defaults = UserDefaults.standard
        let retentionDays = (
            defaults.object(forKey: ghostBaseDeletedMediaRetentionDaysKey)
            as? NSNumber
        )?.intValue ?? 30
        let limitBytes = (
            defaults.object(forKey: ghostBaseDeletedMediaCacheLimitKey)
            as? NSNumber
        )?.int64Value ?? (1024 * 1024 * 1024)

        let root = self.root(mediaBox: mediaBox)
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: root,
            includingPropertiesForKeys: [
                .isRegularFileKey,
                .fileSizeKey,
                .contentModificationDateKey,
            ],
            options: [.skipsHiddenFiles]
        ) else {
            return
        }

        var files: [(URL, Int64, Date)] = []
        let cutoff: Date? = retentionDays < 0
            ? nil
            : Date(timeIntervalSinceNow: -Double(retentionDays) * 86400.0)

        for case let url as URL in enumerator {
            guard let values = try? url.resourceValues(
                forKeys: [
                    .isRegularFileKey,
                    .fileSizeKey,
                    .contentModificationDateKey,
                ]
            ), values.isRegularFile == true else {
                continue
            }
            let date = values.contentModificationDate ?? .distantPast
            if let cutoff, date < cutoff {
                try? fm.removeItem(at: url)
                continue
            }
            files.append((url, Int64(values.fileSize ?? 0), date))
        }

        if limitBytes >= 0 {
            var total = files.reduce(Int64(0)) { $0 + max(0, $1.1) }
            if total > limitBytes {
                for item in files.sorted(by: { $0.2 < $1.2 }) {
                    if total <= limitBytes {
                        break
                    }
                    try? fm.removeItem(at: item.0)
                    total -= max(0, item.1)
                }
            }
        }
    }
}

func ghostBaseScheduleDeletedMediaPreservation(
    mediaBox: MediaBox,
    message: Message
) {
    GhostBaseDeletedMediaCache.preserve(
        mediaBox: mediaBox,
        message: message
    )
}

func ghostBaseRemoveDeletedMediaCacheEntries(
    mediaBox: MediaBox,
    messageIds: [MessageId]
) {
    GhostBaseDeletedMediaCache.remove(
        mediaBox: mediaBox,
        messageIds: messageIds
    )
}

// MARK: GhostBase v1.1U BUILD106_FINAL1
private struct GhostBaseDeletedReplyPlan {
    let outgoing: EnqueueMessage
    let source: Message?
    let sourceGroup: [Message]
    let authorName: String?
    let authorUsername: String?
    let mentionPeerId: PeerId?
}

private struct GhostBaseDeletedQuoteBody {
    let text: String
    let originalTextOffset: Int?
}

private func ghostBaseDeletedMediaLabel(_ message: Message) -> String? {
    // MARK: Jerkgram v1.2D BUILD115_RECOVERY_ENGLISH1
    // TelegramCore cannot depend on presentation/UI localization.
    // Portable recovery text therefore uses English canonical labels;
    // richer UI localization uses semantic JerkgramStringKey values.
    if message.groupingKey != nil && !message.media.isEmpty {
        return "Album"
    }

    guard let media = message.media.first else {
        return nil
    }
    if media is TelegramMediaPoll {
        return "Poll"
    }
    if media is TelegramMediaMap {
        return "📍 Location"
    }
    if media is TelegramMediaContact {
        return "👤 Contact"
    }
    if media is TelegramMediaDice {
        return "🎲 Dice"
    }
    if media is TelegramMediaTodo {
        return "Task List"
    }
    if media is TelegramMediaImage {
        return "📷 Photo"
    }
    if let file = media as? TelegramMediaFile {
        if file.isSticker {
            return "Sticker"
        } else if file.isVoice {
            return "🎙 Voice Message"
        } else if file.isInstantVideo {
            return "🎥 Video Message"
        } else if file.isAnimated {
            return "GIF"
        } else if file.isVideo {
            return "🎬 Video"
        } else if file.isMusic {
            return "🎵 Audio"
        } else if let name = file.fileName, !name.isEmpty {
            return "📎 File: \(name)"
        } else {
            return "📎 File"
        }
    }
    return "Attachment"
}

private func ghostBaseQuoteBody(
    source: Message,
    recoveredMedia: Bool
) -> GhostBaseDeletedQuoteBody {
    let sourceText = source.text

    if recoveredMedia || source.media.isEmpty {
        return GhostBaseDeletedQuoteBody(
            text: sourceText,
            originalTextOffset: sourceText.isEmpty ? nil : 0
        )
    }

    let label = ghostBaseDeletedMediaLabel(source) ?? "Deleted Message"
    if sourceText.isEmpty {
        return GhostBaseDeletedQuoteBody(
            text: label,
            originalTextOffset: nil
        )
    }
    let offset = (label as NSString).length + 1
    return GhostBaseDeletedQuoteBody(
        text: label + "\n" + sourceText,
        originalTextOffset: offset
    )
}

private func ghostBaseShiftEntities(
    _ entities: [MessageTextEntity],
    by offset: Int
) -> [MessageTextEntity] {
    guard offset != 0 else {
        return entities
    }
    return entities.map { entity in
        return MessageTextEntity(
            range: (entity.range.lowerBound + offset)
                ..< (entity.range.upperBound + offset),
            type: entity.type
        )
    }
}

// MARK: Jerkgram v1.2M BUILD124_DELETED_FULL_ENTITIES1
private func ghostBaseOriginalPortableEntities(
    source: Message
) -> [MessageTextEntity] {
    guard !source.text.isEmpty else {
        return []
    }

    let liveEntities = (
        source.attributes.first(where: { $0 is TextEntitiesMessageAttribute })
        as? TextEntitiesMessageAttribute
    )?.entities ?? []
    let storedEntities = (
        source.attributes.first(where: { $0 is GhostBaseMessageAttribute })
        as? GhostBaseMessageAttribute
    )?.originalEntities ?? []
    let sourceEntities = liveEntities.isEmpty ? storedEntities : liveEntities

    let length = (source.text as NSString).length
    guard length > 0, !sourceEntities.isEmpty else {
        return []
    }

    // Telegram's `onlyQuoteable` filter deliberately drops Url/TextUrl and
    // TextMention. A portable deleted reply must reproduce the source text,
    // not Telegram's reduced quote-format subset, so preserve every entity
    // whose range belongs to the source text. The outer recovered quote owns
    // its BlockQuote entity; nesting a source BlockQuote is the sole exclusion.
    return messageTextEntitiesInRange(
        entities: sourceEntities,
        range: NSRange(location: 0, length: length),
        onlyQuoteable: false
    ).filter { entity in
        if case .BlockQuote = entity.type {
            return false
        }
        return true
    }
}

private func ghostBaseBuildPortableDeletedReply(
    outgoing: EnqueueMessage,
    source: Message,
    authorName: String,
    authorUsername: String?,
    mentionPeerId: PeerId?,
    recoveredMedia: AnyMediaReference?,
    forcedLocalGroupingKey: Int64? = nil
) -> EnqueueMessage {
    guard case let .message(
        userText,
        requestedAttributes,
        inlineStickers,
        userMediaReference,
        threadId,
        _,
        replyToStoryId,
        localGroupingKey,
        correlationId,
        bubbleUpEmojiOrStickersets
    ) = outgoing else {
        return outgoing
    }

    let effectiveRecoveredMedia: AnyMediaReference? =
        userMediaReference == nil ? recoveredMedia : nil
    let body = ghostBaseQuoteBody(
        source: source,
        recoveredMedia: effectiveRecoveredMedia != nil
    )

    var quoteText = authorName
    let authorLength = (authorName as NSString).length
    var originalTextStart: Int?
    if !body.text.isEmpty {
        quoteText += "\n" + body.text
        if let inner = body.originalTextOffset {
            originalTextStart = authorLength + 1 + inner
        }
    }

    let separator = userText.isEmpty ? "" : "\n\n"
    let finalText = quoteText + separator + userText
    let quoteLength = (quoteText as NSString).length
    let userOffset = ((quoteText + separator) as NSString).length

    var entities: [MessageTextEntity] = []
    if authorLength > 0 {
        // MARK: JerkGram v1.1Y BUILD110_RECOVERED_AUTHOR_NO_WEB_PREVIEW1
        // MARK: GhostBase v1.1U BUILD106_PORTABLE_AUTHOR1
        if let authorUsername,
           !authorUsername.isEmpty {
            entities.append(
                MessageTextEntity(
                    range: 0 ..< authorLength,
                    type: .TextUrl(
                        url: "tg://resolve?domain=\(authorUsername)"
                    )
                )
            )
        } else if let mentionPeerId {
            entities.append(
                MessageTextEntity(
                    range: 0 ..< authorLength,
                    type: .TextMention(
                        peerId: mentionPeerId
                    )
                )
            )
        }

        entities.append(
            MessageTextEntity(
                range: 0 ..< authorLength,
                type: .Bold
            )
        )
    }

    let sourceLength = (source.text as NSString).length
    let collapse = sourceLength > 320
        || source.text.components(separatedBy: "\n").count > 4
    if quoteLength > 0 {
        entities.append(MessageTextEntity(
            range: 0 ..< quoteLength,
            type: .BlockQuote(isCollapsed: collapse)
        ))
    }

    if let originalTextStart {
        entities.append(contentsOf: ghostBaseShiftEntities(
            ghostBaseOriginalPortableEntities(source: source),
            by: originalTextStart
        ))
    }

    var attributes: [MessageAttribute] = []
    var userEntities: [MessageTextEntity] = []
    for attribute in requestedAttributes {
        if let textAttribute = attribute as? TextEntitiesMessageAttribute {
            userEntities.append(contentsOf: textAttribute.entities)
        } else if attribute is ReplyMessageAttribute {
            continue
        } else {
            attributes.append(attribute)
        }
    }
    entities.append(contentsOf: ghostBaseShiftEntities(
        userEntities,
        by: userOffset
    ))
    if !entities.isEmpty {
        attributes.append(TextEntitiesMessageAttribute(entities: entities))
    }

    return .message(
        text: finalText,
        attributes: attributes,
        inlineStickers: inlineStickers,
        mediaReference: userMediaReference ?? effectiveRecoveredMedia,
        threadId: threadId,
        replyToMessageId: nil,
        replyToStoryId: replyToStoryId,
        localGroupingKey: forcedLocalGroupingKey ?? localGroupingKey,
        correlationId: correlationId,
        bubbleUpEmojiOrStickersets: bubbleUpEmojiOrStickersets
    )
}

private func ghostBaseBuildRecoveredAlbumTail(
    outgoing: EnqueueMessage,
    recoveredMedia: AnyMediaReference,
    localGroupingKey: Int64
) -> EnqueueMessage {
    guard case let .message(
        _,
        requestedAttributes,
        _,
        userMediaReference,
        threadId,
        _,
        replyToStoryId,
        _,
        _,
        _
    ) = outgoing,
    userMediaReference == nil else {
        return outgoing
    }

    var attributes: [MessageAttribute] = []

    for attribute in requestedAttributes {
        if attribute is ReplyMessageAttribute
            || attribute is TextEntitiesMessageAttribute {
            continue
        }

        attributes.append(attribute)
    }

    return .message(
        text: "",
        attributes: attributes,
        inlineStickers: [:],
        mediaReference: recoveredMedia,
        threadId: threadId,
        replyToMessageId: nil,
        replyToStoryId: replyToStoryId,
        localGroupingKey: localGroupingKey,
        correlationId: nil,
        bubbleUpEmojiOrStickersets: []
    )
}


private func ghostBaseReconstructedMedia(
    account: Account,
    peerId: PeerId,
    source: Message,
    outgoing: EnqueueMessage
) -> AnyMediaReference? {
    guard ghostBaseDeletedBool(
        ghostBasePreserveDeletedMediaKey,
        defaultValue: true
    ) else {
        return nil
    }

    guard peerId.namespace == Namespaces.Peer.CloudUser
        || peerId.namespace == Namespaces.Peer.CloudGroup
        || peerId.namespace == Namespaces.Peer.CloudChannel else {
        return nil
    }

    // MARK: GhostBase v1.1U BUILD106_GROUPED_MEDIA1
    guard source.media.count == 1 else {
        return nil
    }

    guard case let .message(
        _, attributes, _, userMedia, _, _, _, _, _, _
    ) = outgoing,
    userMedia == nil else {
        return nil
    }

    if attributes.contains(where: {
        $0 is OutgoingScheduleInfoMessageAttribute
    }) {
        return nil
    }

    let media = source.media[0]
    // MARK: Jerkgram v1.2J BUILD121_NATIVE_STICKER_RECOVERY1
    // Preserve the original TelegramMediaFile mimeType + attributes and
    // let the existing deleted-media reconstruction path rebuild it.
    // The textual Sticker label remains only as the missing-media fallback.

    guard let path = GhostBaseDeletedMediaCache.resolvePath(
        mediaBox: account.postbox.mediaBox,
        messageId: source.id,
        media: media
    ) else {
        return nil
    }

    let fm = FileManager.default
    let fileSize = (
        ((try? fm.attributesOfItem(atPath: path))?[.size] as? NSNumber)
    )?.int64Value
    guard (fileSize ?? 0) > 0 else {
        return nil
    }

    let randomId = Int64.random(in: Int64.min ... Int64.max)
    let localResource = LocalFileReferenceMediaResource(
        localFilePath: path,
        randomId: randomId,
        isUniquelyReferencedTemporaryFile: false,
        size: fileSize
    )

    if let file = media as? TelegramMediaFile {
        let localFile = TelegramMediaFile(
            fileId: MediaId(
                namespace: Namespaces.Media.LocalFile,
                id: randomId
            ),
            partialReference: nil,
            resource: localResource,
            previewRepresentations: [],
            videoThumbnails: [],
            videoCover: nil,
            immediateThumbnailData: file.immediateThumbnailData,
            mimeType: file.mimeType,
            size: fileSize,
            attributes: file.attributes,
            alternativeRepresentations: []
        )
        return .standalone(media: localFile)
    }

    if let image = media as? TelegramMediaImage,
       let largest = largestImageRepresentation(image.representations) {
        let localRepresentation = TelegramMediaImageRepresentation(
            dimensions: largest.dimensions,
            resource: localResource,
            progressiveSizes: [],
            immediateThumbnailData: nil,
            hasVideo: false,
            isPersonal: false,
            typeHint: .generic
        )
        let localImage = TelegramMediaImage(
            imageId: MediaId(
                namespace: Namespaces.Media.LocalImage,
                id: randomId
            ),
            representations: [localRepresentation],
            videoRepresentations: [],
            immediateThumbnailData: image.immediateThumbnailData,
            emojiMarkup: nil,
            reference: nil,
            partialReference: nil,
            flags: [],
            video: nil
        )
        return .standalone(media: localImage)
    }

    return nil
}

private func ghostBaseResolveDeletedReplies(
    account: Account,
    peerId: PeerId,
    messages: [EnqueueMessage]
) -> Signal<[EnqueueMessage], NoError> {
    guard ghostBaseDeletedBool(
        ghostBaseSaveDeletedKey,
        defaultValue: true
    ), ghostBaseDeletedBool(
        ghostBaseDeletedPortableRepliesKey,
        defaultValue: true
    ) else {
        return .single(messages)
    }

    let ghostBaseCloudDestination =
        peerId.namespace == Namespaces.Peer.CloudUser
        || peerId.namespace == Namespaces.Peer.CloudGroup
        || peerId.namespace == Namespaces.Peer.CloudChannel

    return account.postbox.transaction { transaction -> [GhostBaseDeletedReplyPlan] in
        return messages.map { outgoing in
            guard case let .message(
                _, _, _, _, _, replySubject, _, _, _, _
            ) = outgoing,
            let replySubject,
            let source =
                transaction.getMessage(
                    replySubject.messageId
                ),
            let deletedAttribute =
                source.attributes.first(
                    where: {
                        $0 is GhostBaseMessageAttribute
                    }
                ) as? GhostBaseMessageAttribute,
            deletedAttribute.isDeleted else {

                return GhostBaseDeletedReplyPlan(
                    outgoing: outgoing,
                    source: nil,
                    sourceGroup: [],
                    authorName: nil,
                    authorUsername: nil,
                    mentionPeerId: nil
                )
            }

            // MARK: GhostBase v1.1U BUILD106_ALBUM_QUERY1
            let sourceGroup: [Message]

            if source.groupingKey != nil {
                sourceGroup =
                    transaction
                        .getMessageGroup(source.id)
                    ?? [source]
            } else {
                sourceGroup = [source]
            }

            let authorPeer = source.author
            let authorName: String

            if let authorPeer,
               let stored =
                    GhostBasePublicPeerNameStore
                        .name(peerId: authorPeer.id),
               !stored.isEmpty {
                authorName = stored
            } else if let authorPeer {
                let title =
                    EnginePeer(authorPeer)
                        .debugDisplayTitle
                authorName =
                    title.isEmpty
                    ? "User"
                    : title
            } else {
                authorName = "User"
            }

            let authorUsername: String?

            if let raw =
                authorPeer?
                    .addressName?
                    .trimmingCharacters(
                        in: .whitespacesAndNewlines
                    ),
               !raw.isEmpty {
                authorUsername =
                    raw.hasPrefix("@")
                    ? String(raw.dropFirst())
                    : raw
            } else {
                authorUsername = nil
            }

            var mentionPeerId: PeerId?

            if ghostBaseCloudDestination,
               authorUsername == nil,
               let authorPeer,
               authorPeer.id.namespace
                    == Namespaces.Peer.CloudUser,
               apiInputUser(authorPeer) != nil {
                mentionPeerId = authorPeer.id
            }

            return GhostBaseDeletedReplyPlan(
                outgoing: outgoing,
                source: source,
                sourceGroup: sourceGroup,
                authorName: authorName,
                authorUsername: authorUsername,
                mentionPeerId: mentionPeerId
            )
        }
    }
    |> mapToSignal { plans -> Signal<[EnqueueMessage], NoError> in
        return Signal { subscriber in
            DispatchQueue.global(qos: .utility).async {
                var result: [EnqueueMessage] = []
                result.reserveCapacity(plans.count)

                for plan in plans {
                    guard
                        let source = plan.source,
                        let authorName = plan.authorName
                    else {
                        result.append(plan.outgoing)
                        continue
                    }

                    let recoverySources =
                        source.groupingKey != nil
                        ? plan.sourceGroup
                        : [source]

                    var recoveredGroup: [AnyMediaReference] = []
                    recoveredGroup.reserveCapacity(recoverySources.count)

                    for groupSource in recoverySources {
                        if let recovered =
                            ghostBaseReconstructedMedia(
                                account: account,
                                peerId: peerId,
                                source: groupSource,
                                outgoing: plan.outgoing
                            ) {
                            recoveredGroup.append(recovered)
                        }
                    }

                    // MARK: GhostBase v1.1U BUILD106_ALBUM_RECOVERY1
                    if source.groupingKey != nil,
                       recoveredGroup.count >= 2 {

                        let localGroupingKey =
                            Int64.random(
                                in: Int64.min ... Int64.max
                            )

                        var first =
                            ghostBaseBuildPortableDeletedReply(
                                outgoing: plan.outgoing,
                                source: source,
                                authorName: authorName,
                                authorUsername: plan.authorUsername,
                                mentionPeerId: plan.mentionPeerId,
                                recoveredMedia: recoveredGroup[0],
                                forcedLocalGroupingKey: localGroupingKey
                            )

                        if case let .message(
                            text, _, _, _, _, _, _, _, _, _
                        ) = first,
                        (text as NSString).length > 1024 {
                            first =
                                ghostBaseBuildPortableDeletedReply(
                                    outgoing: plan.outgoing,
                                    source: source,
                                    authorName: authorName,
                                    authorUsername: plan.authorUsername,
                                    mentionPeerId: plan.mentionPeerId,
                                    recoveredMedia: nil
                                )

                            result.append(first)

                            for recovered in recoveredGroup {
                                result.append(
                                    ghostBaseBuildRecoveredAlbumTail(
                                        outgoing: plan.outgoing,
                                        recoveredMedia: recovered,
                                        localGroupingKey: localGroupingKey
                                    )
                                )
                            }
                        } else {
                            result.append(first)

                            for recovered in recoveredGroup.dropFirst() {
                                result.append(
                                    ghostBaseBuildRecoveredAlbumTail(
                                        outgoing: plan.outgoing,
                                        recoveredMedia: recovered,
                                        localGroupingKey: localGroupingKey
                                    )
                                )
                            }
                        }

                        continue
                    }

                    // MARK: Jerkgram v1.2K BUILD122_STICKER_REPLY_NO_REUPLOAD1
                    // A recovered sticker must stay inside the quoted source context;
                    // attaching it as outgoing media sends a second sticker message.
                    // Preserve the established photo/video/GIF/audio/document and album paths.
                    let jerkgramStickerReply = source.media.contains { media in
                        guard let file = media as? TelegramMediaFile else {
                            return false
                        }
                        return file.isSticker
                    }
                    let recovered = jerkgramStickerReply ? nil : recoveredGroup.first

                    var candidate =
                        ghostBaseBuildPortableDeletedReply(
                            outgoing: plan.outgoing,
                            source: source,
                            authorName: authorName,
                            authorUsername: plan.authorUsername,
                            mentionPeerId: plan.mentionPeerId,
                            recoveredMedia: recovered
                        )

                    if recovered != nil,
                       case let .message(
                            text, _, _, _, _, _, _, _, _, _
                       ) = candidate,
                       (text as NSString).length > 1024 {
                        candidate =
                            ghostBaseBuildPortableDeletedReply(
                                outgoing: plan.outgoing,
                                source: source,
                                authorName: authorName,
                                authorUsername: plan.authorUsername,
                                mentionPeerId: plan.mentionPeerId,
                                recoveredMedia: nil
                            )
                    }

                    result.append(candidate)
                }

                subscriber.putNext(result)
                subscriber.putCompletion()
            }
            return EmptyDisposable
        }
    }
}

private func opportunisticallyTransformOutgoingMedia(network: Network, postbox: Postbox, transformOutgoingMessageMedia: TransformOutgoingMessageMedia, messages: [EnqueueMessage], userInteractive: Bool) -> Signal<[(Bool, EnqueueMessage)], NoError> {
    var hasMedia = false
    loop: for message in messages {
        switch message {
            case let .message(_, _, _, mediaReference, _, _, _, _, _, _):
                if mediaReference != nil {
                    hasMedia = true
                    break loop
                }
            case .forward:
                break
        }
    }
    
    if !hasMedia {
        return .single(messages.map { (true, $0) })
    }
    
    var signals: [Signal<(Bool, EnqueueMessage), NoError>] = []
    for message in messages {
        switch message {
            case let .message(text, attributes, inlineStickers, mediaReference, threadId, replyToMessageId, replyToStoryId, localGroupingKey, correlationId, bubbleUpEmojiOrStickersets):
                if let mediaReference = mediaReference {
                    signals.append(opportunisticallyTransformMessageWithMedia(network: network, postbox: postbox, transformOutgoingMessageMedia: transformOutgoingMessageMedia, mediaReference: mediaReference, userInteractive: userInteractive)
                    |> map { result -> (Bool, EnqueueMessage) in
                        return (result != nil, .message(text: text, attributes: attributes, inlineStickers: inlineStickers, mediaReference: result ?? mediaReference, threadId: threadId, replyToMessageId: replyToMessageId, replyToStoryId: replyToStoryId, localGroupingKey: localGroupingKey, correlationId: correlationId, bubbleUpEmojiOrStickersets: bubbleUpEmojiOrStickersets))
                    })
                } else {
                    signals.append(.single((false, message)))
                }
            case .forward:
                signals.append(.single((false, message)))
        }
    }
    return combineLatest(signals)
}

private func ghostBaseEnqueueResolvedMessages(account: Account, peerId: PeerId, messages: [EnqueueMessage]) -> Signal<[MessageId?], NoError> {
    let signal: Signal<[(Bool, EnqueueMessage)], NoError>
    if let transformOutgoingMessageMedia = account.transformOutgoingMessageMedia {
        signal = opportunisticallyTransformOutgoingMedia(network: account.network, postbox: account.postbox, transformOutgoingMessageMedia: transformOutgoingMessageMedia, messages: messages, userInteractive: true)
    } else {
        signal = .single(messages.map { (false, $0) })
    }
    return signal
    |> mapToSignal { messages -> Signal<[MessageId?], NoError> in
        return account.postbox.transaction { transaction -> ([MessageId?], [MessageId]) in
            var resultIds = Array<MessageId?>(repeating: nil, count: messages.count)
            var ephemeralMessageIds: [MessageId] = []
            var normalMessages: [(Bool, EnqueueMessage)] = []
            var normalMessageIndices: [Int] = []

            for i in 0 ..< messages.count {
                let (transformedMedia, message) = messages[i]
                if let botPeerId = ephemeralBotPeerIdForEnqueuedMessage(transaction: transaction, accountPeerId: account.peerId, message: message) {
                    if let messageId = enqueueEphemeralOutgoingMessage(transaction: transaction, account: account, peerId: peerId, transformedMedia: transformedMedia, message: message, botPeerId: botPeerId) {
                        resultIds[i] = messageId
                        ephemeralMessageIds.append(messageId)
                    }
                } else {
                    normalMessages.append((transformedMedia, message))
                    normalMessageIndices.append(i)
                }
            }

            if !normalMessages.isEmpty {
                let normalIds = enqueueMessages(transaction: transaction, account: account, peerId: peerId, messages: normalMessages)
                for i in 0 ..< min(normalIds.count, normalMessageIndices.count) {
                    resultIds[normalMessageIndices[i]] = normalIds[i]
                }
            }

            return (resultIds, ephemeralMessageIds)
        }
        |> map { resultIds, ephemeralMessageIds -> [MessageId?] in
            for messageId in ephemeralMessageIds {
                let _ = _internal_sendEphemeralOutgoingMessage(account: account, messageId: messageId).startStandalone()
            }
            return resultIds
        }
    }
}

public func enqueueMessages(
    account: Account,
    peerId: PeerId,
    messages: [EnqueueMessage]
) -> Signal<[MessageId?], NoError> {
    return ghostBaseResolveDeletedReplies(
        account: account,
        peerId: peerId,
        messages: messages
    )
    |> mapToSignal { resolvedMessages in
        return ghostBaseEnqueueResolvedMessages(
            account: account,
            peerId: peerId,
            messages: resolvedMessages
        )
    }
}


public func resendMessages(account: Account, messageIds: [MessageId]) -> Signal<Void, NoError> {
    return account.postbox.transaction { transaction -> Void in
        var removeMessageIds: [MessageId] = []
        for (peerId, ids) in messagesIdsGroupedByPeerId(messageIds) {
            var sendPaidMessageStars: StarsAmount?
            let peer = transaction.getPeer(peerId)
            if let user = peer as? TelegramUser, user.flags.contains(.requireStars) {
                if let cachedUserData = transaction.getPeerCachedData(peerId: user.id) as? CachedUserData {
                    sendPaidMessageStars = cachedUserData.sendPaidMessageStars
                }
            } else if let channel = peer as? TelegramChannel {
                if channel.flags.contains(.isCreator) || channel.adminRights != nil {
                } else {
                    sendPaidMessageStars = channel.sendPaidMessageStars
                }
            }
            
            var messages: [EnqueueMessage] = []
            for id in ids {
                if let message = transaction.getMessage(id), !message.flags.contains(.Incoming) {
                    removeMessageIds.append(id)
                    
                    var filteredAttributes: [MessageAttribute] = []
                    var replyToMessageId: EngineMessageReplySubject?
                    var replyToStoryId: StoryId?
                    var bubbleUpEmojiOrStickersets: [ItemCollectionId] = []
                    var forwardSource: MessageId?
                    inner: for attribute in message.attributes {
                        if let attribute = attribute as? ReplyMessageAttribute {
                            replyToMessageId = EngineMessageReplySubject(messageId: attribute.messageId, quote: attribute.quote, innerSubject: attribute.innerSubject)
                        } else if let attribute = attribute as? ReplyStoryAttribute {
                            replyToStoryId = attribute.storyId
                        } else if let attribute = attribute as? OutgoingMessageInfoAttribute {
                            bubbleUpEmojiOrStickersets = attribute.bubbleUpEmojiOrStickersets
                            continue inner
                        } else if let attribute = attribute as? ForwardSourceInfoAttribute {
                            forwardSource = attribute.messageId
                        } else {
                            if attribute is PaidStarsMessageAttribute {
                            } else {
                                filteredAttributes.append(attribute)
                            }
                        }
                    }
                    
                    if let sendPaidMessageStars {
                        filteredAttributes.append(PaidStarsMessageAttribute(stars: sendPaidMessageStars, postponeSending: false))
                    }

                    if let forwardSource = forwardSource {
                        messages.append(.forward(source: forwardSource, threadId: nil, grouping: .auto, attributes: filteredAttributes, correlationId: nil))
                    } else {
                        messages.append(.message(text: message.text, attributes: filteredAttributes, inlineStickers: [:], mediaReference: message.media.first.flatMap(AnyMediaReference.standalone), threadId: message.threadId, replyToMessageId: replyToMessageId, replyToStoryId: replyToStoryId, localGroupingKey: message.groupingKey, correlationId: nil, bubbleUpEmojiOrStickersets: bubbleUpEmojiOrStickersets))
                    }
                }
            }
            let _ = enqueueMessages(transaction: transaction, account: account, peerId: peerId, messages: messages.map { (false, $0) })
        }
        _internal_deleteMessages(transaction: transaction, mediaBox: account.postbox.mediaBox, ids: removeMessageIds, deleteMedia: false)
    }
}

func enqueueMessages(transaction: Transaction, account: Account, peerId: PeerId, messages: [(Bool, EnqueueMessage)], disableAutoremove: Bool = false, transformGroupingKeysWithPeerId: Bool = false) -> [MessageId?] {
    /**
     * If it is a support account, mark messages as read here as they are
     * not marked as read when chat is opened.
     **/
    if account.isSupportUser {
        let namespace: MessageId.Namespace
        if peerId.namespace == Namespaces.Peer.SecretChat {
            namespace = Namespaces.Message.SecretIncoming
        } else {
            namespace = Namespaces.Message.Cloud
        }
        if let index = transaction.getTopPeerMessageIndex(peerId: peerId, namespace: namespace) {
            let _ = transaction.applyInteractiveReadMaxIndex(index)
        }
    }
    
    var forwardedMessageIds = Set<MessageId>()
    for (_, message) in messages {
        if case let .forward(sourceId, _, _, _, _) = message {
            forwardedMessageIds.insert(sourceId)
        }
    }
    
    var updatedMessages: [(Bool, EnqueueMessage)] = []
    outer: for (transformedMedia, message) in messages {
        var updatedMessage = message
        if transformGroupingKeysWithPeerId {
            updatedMessage = updatedMessage.withUpdatedGroupingKey { groupingKey -> Int64? in
                if let groupingKey = groupingKey {
                    return groupingKey &+ peerId.toInt64()
                } else {
                    return nil
                }
            }
        }
        
        switch message {
            case let .message(_, attributes, _, _, threadId, replyToMessageId, _, _, _, _):
                if let replyToMessageId = replyToMessageId, (replyToMessageId.messageId.peerId != peerId && peerId.namespace == Namespaces.Peer.SecretChat), let replyMessage = transaction.getMessage(replyToMessageId.messageId) {
                    var canBeForwarded = true
                    if replyMessage.id.namespace != Namespaces.Message.Cloud {
                        canBeForwarded = false
                    }
                    inner: for media in replyMessage.media {
                        if media is TelegramMediaAction {
                            canBeForwarded = false
                            break inner
                        }
                    }
                    if canBeForwarded {
                        updatedMessages.append((true, .forward(source: replyToMessageId.messageId, threadId: threadId, grouping: .none, attributes: attributes, correlationId: nil)))
                    }
                }
            case let .forward(sourceId, threadId, _, _, _):
                if let sourceMessage = forwardedMessageToBeReuploaded(transaction: transaction, id: sourceId) {
                    var mediaReference: AnyMediaReference?
                    if sourceMessage.id.peerId.namespace == Namespaces.Peer.SecretChat {
                        if let media = sourceMessage.media.first {
                            mediaReference = .standalone(media: media)
                        }
                    }
                    updatedMessages.append((transformedMedia, .message(text: sourceMessage.text, attributes: sourceMessage.attributes, inlineStickers: [:], mediaReference: mediaReference, threadId: threadId, replyToMessageId: threadId.flatMap { EngineMessageReplySubject(messageId: MessageId(peerId: peerId, namespace: Namespaces.Message.Cloud, id: Int32(clamping: $0)), quote: nil, innerSubject: nil) }, replyToStoryId: nil, localGroupingKey: nil, correlationId: nil, bubbleUpEmojiOrStickersets: [])))
                    continue outer
                }
        }
        updatedMessages.append((transformedMedia, updatedMessage))
    }
    
    if let peer = transaction.getPeer(peerId), let accountPeer = transaction.getPeer(account.peerId) {
        let peerPresence = transaction.getPeerPresence(peerId: peerId)
        
        var storeMessages: [StoreMessage] = []
        var timestamp = Int32(account.network.context.globalTime())
        switch peerId.namespace {
            case Namespaces.Peer.CloudChannel, Namespaces.Peer.CloudGroup, Namespaces.Peer.CloudUser:
                if let topIndex = transaction.getTopPeerMessageIndex(peerId: peerId, namespace: Namespaces.Message.Cloud) {
                    timestamp = max(timestamp, topIndex.timestamp)
                }
            default:
                break
        }
        
        var addedHashtags: [String] = []
        var emojiItems: [RecentEmojiItem] = []
        
        var localGroupingKeyBySourceKey: [Int64: Int64] = [:]
        
        var globallyUniqueIds: [Int64] = []
        for (transformedMedia, message) in updatedMessages {
            if case let .message(_, requestedAttributes, _, _, _, replyToMessageId, _, _, _, _) = message {
                if requestedAttributes.contains(where: { $0 is EphemeralOutgoingMessageAttribute }) {
                    assertionFailure("Ephemeral outgoing messages must be routed before normal enqueue")
                    continue
                }
                if replyToMessageId?.messageId.namespace == Namespaces.Message.EphemeralLocal {
                    assertionFailure("Normal outgoing messages must not reply to EphemeralLocal")
                    continue
                }
            } else if case let .forward(_, _, _, requestedAttributes, _) = message, requestedAttributes.contains(where: { $0 is EphemeralOutgoingMessageAttribute }) {
                assertionFailure("Ephemeral outgoing forwards are not supported")
                continue
            }

            var attributes: [MessageAttribute] = []
            var flags = StoreMessageFlags()
            flags.insert(.Unsent)
            
            var randomId: Int64 = 0
            arc4random_buf(&randomId, 8)
            var infoFlags = OutgoingMessageInfoFlags()
            if transformedMedia {
                infoFlags.insert(.transformedMedia)
            }
            
            var partialReference: PartialMediaReference?
            if case let .message(_, _, _, mediaReference, _, _, _, _, _, _) = message {
                partialReference = mediaReference?.partial
            }
            attributes.append(OutgoingMessageInfoAttribute(uniqueId: randomId, flags: infoFlags, acknowledged: false, correlationId: message.correlationId, bubbleUpEmojiOrStickersets: message.bubbleUpEmojiOrStickersets, partialReference: partialReference))
            globallyUniqueIds.append(randomId)
            
            switch message {
                case let .message(text, requestedAttributes, inlineStickers, mediaReference, threadId, replyToMessageId, replyToStoryId, localGroupingKey, _, _):
                    for (_, file) in inlineStickers {
                        transaction.storeMediaIfNotPresent(media: file)
                    }
                
                    for emoji in text.emojis {
                        if emoji.isSingleEmoji {
                            if !emojiItems.contains(where: { $0.content == .text(emoji) }) {
                                emojiItems.append(RecentEmojiItem(.text(emoji)))
                            }
                        }
                    }
                
                    var peerAutoremoveTimeout: Int32?
                    if let peer = peer as? TelegramSecretChat {
                        var isAction = false
                        if let _ = mediaReference?.media as? TelegramMediaAction {
                            isAction = true
                        }
                        if !disableAutoremove, let messageAutoremoveTimeout = peer.messageAutoremoveTimeout, !isAction {
                            peerAutoremoveTimeout = messageAutoremoveTimeout
                        }
                    } else if let cachedData = transaction.getPeerCachedData(peerId: peer.id), !disableAutoremove {
                        var isScheduled = false
                        for attribute in requestedAttributes {
                            if let _ = attribute as? OutgoingScheduleInfoMessageAttribute {
                                isScheduled = true
                            }
                        }
                        
                        if !isScheduled {
                            var messageAutoremoveTimeout: Int32?
                            if let cachedData = cachedData as? CachedUserData {
                                if case let .known(value) = cachedData.autoremoveTimeout {
                                    messageAutoremoveTimeout = value?.effectiveValue
                                }
                            } else if let cachedData = cachedData as? CachedGroupData {
                                if case let .known(value) = cachedData.autoremoveTimeout {
                                    messageAutoremoveTimeout = value?.effectiveValue
                                }
                            } else if let cachedData = cachedData as? CachedChannelData {
                                if case let .known(value) = cachedData.autoremoveTimeout {
                                    messageAutoremoveTimeout = value?.effectiveValue
                                }
                            }
                            
                            if let messageAutoremoveTimeout = messageAutoremoveTimeout {
                                peerAutoremoveTimeout = messageAutoremoveTimeout
                            }
                        }
                    }
                    
                    for attribute in filterMessageAttributesForOutgoingMessage(requestedAttributes) {
                        if let attribute = attribute as? AutoremoveTimeoutMessageAttribute {
                            if let _ = peer as? TelegramSecretChat {
                                peerAutoremoveTimeout = nil
                                attributes.append(attribute)
                            } else {
                                attributes.append(AutoclearTimeoutMessageAttribute(timeout: attribute.timeout, countdownBeginTime: nil))
                            }
                        } else {
                            attributes.append(attribute)
                        }
                    }
                    
                    if let peerAutoremoveTimeout = peerAutoremoveTimeout {
                        attributes.append(AutoremoveTimeoutMessageAttribute(timeout: peerAutoremoveTimeout, countdownBeginTime: nil))
                    }
                        
                    if let replyToMessageId = replyToMessageId {
                        var threadMessageId: MessageId?
                        var quote = replyToMessageId.quote
                        let isQuote = quote != nil
                        if let replyMessage = transaction.getMessage(replyToMessageId.messageId) {
                            if replyMessage.id.namespace == Namespaces.Message.Cloud, let threadId = replyMessage.threadId {
                                threadMessageId = MessageId(peerId: replyMessage.id.peerId, namespace: Namespaces.Message.Cloud, id: Int32(clamping: threadId))
                            }
                            if quote == nil, replyToMessageId.messageId.peerId != peerId {
                                let nsText = replyMessage.text as NSString
                                var replyMedia: Media?
                                for m in replyMessage.media {
                                    switch m {
                                    case _ as TelegramMediaImage, _ as TelegramMediaFile:
                                        replyMedia = m
                                    default:
                                        break
                                    }
                                }
                                quote = EngineMessageReplyQuote(text: replyMessage.text, offset: nil, entities: messageTextEntitiesInRange(entities: replyMessage.textEntitiesAttribute?.entities ?? [], range: NSRange(location: 0, length: nsText.length), onlyQuoteable: true), media: replyMedia)
                            }
                        }
                        attributes.append(ReplyMessageAttribute(messageId: replyToMessageId.messageId, threadMessageId: threadMessageId, quote: quote, isQuote: isQuote, innerSubject: replyToMessageId.innerSubject))
                    }
                    if let replyToStoryId = replyToStoryId {
                        attributes.append(ReplyStoryAttribute(storyId: replyToStoryId))
                    }
                    var mediaList: [Media] = []
                    if let mediaReference = mediaReference {
                        let augmentedMedia = augmentMediaWithReference(mediaReference)
                        mediaList.append(augmentedMedia)
                    }
                    
                    if let file = mediaReference?.media as? TelegramMediaFile, file.isVoice || file.isInstantVideo {
                        if peerId.namespace == Namespaces.Peer.CloudUser || peerId.namespace == Namespaces.Peer.CloudGroup || peerId.namespace == Namespaces.Peer.SecretChat {
                            attributes.append(ConsumableContentMessageAttribute(consumed: false))
                        }
                    }
                    
                    var entitiesAttribute: TextEntitiesMessageAttribute?
                    for attribute in attributes {
                        if let attribute = attribute as? TextEntitiesMessageAttribute {
                            entitiesAttribute = attribute
                            var maybeNsText: NSString?
                            for entity in attribute.entities {
                                if case .Hashtag = entity.type {
                                    let nsText: NSString
                                    if let maybeNsText = maybeNsText {
                                        nsText = maybeNsText
                                    } else {
                                        nsText = text as NSString
                                        maybeNsText = nsText
                                    }
                                    var entityRange = NSRange(location: entity.range.lowerBound, length: entity.range.upperBound - entity.range.lowerBound)
                                    if entityRange.location + entityRange.length > nsText.length {
                                        entityRange.location = max(0, nsText.length - entityRange.length)
                                        entityRange.length = nsText.length - entityRange.location
                                    }
                                    if entityRange.length > 1 {
                                        entityRange.location += 1
                                        entityRange.length -= 1
                                        let hashtag = nsText.substring(with: entityRange)
                                        addedHashtags.append(hashtag)
                                    }
                                } else if case let .CustomEmoji(_, fileId) = entity.type {
                                    let mediaId = MediaId(namespace: Namespaces.Media.CloudFile, id: fileId)
                                    if let file = inlineStickers[mediaId] as? TelegramMediaFile {
                                        emojiItems.append(RecentEmojiItem(.file(file)))
                                    } else if let file = transaction.getMedia(mediaId) as? TelegramMediaFile {
                                        emojiItems.append(RecentEmojiItem(.file(file)))
                                    }
                                }
                            }
                            break
                        }
                    }
                                    
                    let (tags, globalTags) = tagsForStoreMessage(incoming: false, attributes: attributes, media: mediaList, textEntities: entitiesAttribute?.entities, isPinned: false)
                    
                    var localTags: LocalMessageTags = []
                    for media in mediaList {
                        if let media = media as? TelegramMediaMap, media.liveBroadcastingTimeout != nil {
                            localTags.insert(.OutgoingLiveLocation)
                        }
                    }
                    
                    var messageNamespace = Namespaces.Message.Local
                    var effectiveTimestamp = timestamp
                    var sendAsPeer: Peer?
                    for attribute in attributes {
                        if let attribute = attribute as? OutgoingScheduleInfoMessageAttribute {
                            if attribute.scheduleTime == scheduleWhenOnlineTimestamp, let presence = peerPresence as? TelegramUserPresence, case let .present(statusTimestamp) = presence.status, statusTimestamp >= timestamp {
                            } else {
                                messageNamespace = Namespaces.Message.ScheduledLocal
                                effectiveTimestamp = attribute.scheduleTime
                            }
                        } else if attribute is OutgoingQuickReplyMessageAttribute {
                            messageNamespace = Namespaces.Message.QuickReplyLocal
                            effectiveTimestamp = 0
                        } else if let attribute = attribute as? SendAsMessageAttribute {
                            if let peer = transaction.getPeer(attribute.peerId) {
                                sendAsPeer = peer
                            }
                        }
                    }
                
                    var authorId: PeerId?
                    if let sendAsPeer = sendAsPeer {
                        if let peer = peer as? TelegramChannel, case let .broadcast(info) = peer.info {
                            if info.flags.contains(.messagesShouldHaveProfiles) {
                                authorId = sendAsPeer.id
                            } else {
                                authorId = peer.id
                            }
                        } else {
                            authorId = sendAsPeer.id
                        }
                    } else if let peer = peer as? TelegramChannel {
                        if case .broadcast = peer.info {
                            authorId = peer.id
                        } else if case .group = peer.info, peer.hasPermission(.canBeAnonymous) {
                            authorId = peer.id
                        } else {
                            authorId = account.peerId
                        }
                    }  else {
                        authorId = account.peerId
                    }
                    
                    if messageNamespace != Namespaces.Message.ScheduledLocal {
                        attributes.removeAll(where: { $0 is OutgoingScheduleInfoMessageAttribute })
                    }
                    if messageNamespace != Namespaces.Message.QuickReplyLocal {
                        attributes.removeAll(where: { $0 is OutgoingQuickReplyMessageAttribute })
                    }
                                        
                    if let peer = peer as? TelegramChannel {
                        switch peer.info {
                            case let .broadcast(info):
                                if messageNamespace != Namespaces.Message.ScheduledLocal && messageNamespace != Namespaces.Message.QuickReplyLocal {
                                    attributes.append(ViewCountMessageAttribute(count: 1))
                                }
                                if info.flags.contains(.messagesShouldHaveProfiles) {
                                    if sendAsPeer == nil {
                                        authorId = account.peerId
                                    }
                                }
                                if info.flags.contains(.messagesShouldHaveSignatures) {
                                    if let sendAsPeer {
                                        if sendAsPeer.id == peerId {
                                        } else {
                                            attributes.append(AuthorSignatureMessageAttribute(signature: sendAsPeer.debugDisplayTitle))
                                        }
                                    } else {
                                        attributes.append(AuthorSignatureMessageAttribute(signature: accountPeer.debugDisplayTitle))
                                    }
                                }
                            case .group:
                                break
                        }
                    }
                    
                    var threadId: Int64? = threadId
                    if threadId == nil {
                        if let replyToMessageId = replyToMessageId {
                            if let message = transaction.getMessage(replyToMessageId.messageId) {
                                if let threadIdValue = message.threadId {
                                    if threadIdValue == 1 {
                                        if let peer = transaction.getPeer(message.id.peerId), peer.isForum {
                                            threadId = threadIdValue
                                        } else {
                                            if let channel = message.peers[message.id.peerId] as? TelegramChannel, case .group = channel.info {
                                                threadId = Int64(replyToMessageId.messageId.id)
                                            }
                                        }
                                    } else {
                                        threadId = threadIdValue
                                    }
                                } else if let channel = message.peers[message.id.peerId] as? TelegramChannel, case .group = channel.info {
                                    threadId = Int64(replyToMessageId.messageId.id)
                                }
                            }
                        }
                    }
                
                    if threadId == nil, let peer = transaction.getPeer(peerId), (peer is TelegramChannel), peer.isForum {
                        threadId = 1
                    }
                    
                    storeMessages.append(StoreMessage(peerId: peerId, namespace: messageNamespace, customStableId: nil, globallyUniqueId: randomId, groupingKey: localGroupingKey, threadId: threadId, timestamp: effectiveTimestamp, flags: flags, tags: tags, globalTags: globalTags, localTags: localTags, forwardInfo: nil, authorId: authorId, text: text, attributes: attributes, media: mediaList))
                case let .forward(source, threadId, grouping, requestedAttributes, _):
                    let sourceMessage = transaction.getMessage(source)
                    if let sourceMessage = sourceMessage, let author = sourceMessage.author ?? sourceMessage.peers[sourceMessage.id.peerId] {
                        var messageText = sourceMessage.text
                        
                        if let peer = peer as? TelegramSecretChat {
                            var isAction = false
                            for media in sourceMessage.media {
                                if let _ = media as? TelegramMediaAction {
                                    isAction = true
                                }
                            }
                            if !disableAutoremove, let messageAutoremoveTimeout = peer.messageAutoremoveTimeout, !isAction {
                                attributes.append(AutoremoveTimeoutMessageAttribute(timeout: messageAutoremoveTimeout, countdownBeginTime: nil))
                            }
                        } else if let cachedData = transaction.getPeerCachedData(peerId: peer.id), !disableAutoremove {
                            var isScheduled = false
                            for attribute in attributes {
                                if let _ = attribute as? OutgoingScheduleInfoMessageAttribute {
                                    isScheduled = true
                                    break
                                }
                            }
                            
                            if !isScheduled {
                                var messageAutoremoveTimeout: Int32?
                                if let cachedData = cachedData as? CachedUserData {
                                    if case let .known(value) = cachedData.autoremoveTimeout {
                                        messageAutoremoveTimeout = value?.effectiveValue
                                    }
                                } else if let cachedData = cachedData as? CachedGroupData {
                                    if case let .known(value) = cachedData.autoremoveTimeout {
                                        messageAutoremoveTimeout = value?.effectiveValue
                                    }
                                } else if let cachedData = cachedData as? CachedChannelData {
                                    if case let .known(value) = cachedData.autoremoveTimeout {
                                        messageAutoremoveTimeout = value?.effectiveValue
                                    }
                                }
                                
                                if let messageAutoremoveTimeout = messageAutoremoveTimeout {
                                    attributes.append(AutoremoveTimeoutMessageAttribute(timeout: messageAutoremoveTimeout, countdownBeginTime: nil))
                                }
                            }
                        }
                        
                        var forwardInfo: StoreMessageForwardInfo?
                        
                        var hideSendersNames = false
                        var hideCaptions = false
                        for attribute in requestedAttributes {
                            if let attribute = attribute as? ForwardOptionsMessageAttribute {
                                hideSendersNames = attribute.hideNames
                                hideCaptions = attribute.hideCaptions
                                break
                            }
                        }
                        
                        if hideCaptions {
                            for media in sourceMessage.media {
                                if media is TelegramMediaImage || media is TelegramMediaFile {
                                    messageText = ""
                                    break
                                }
                            }
                        }
                        
                        if sourceMessage.id.namespace == Namespaces.Message.Cloud && peerId.namespace != Namespaces.Peer.SecretChat {
                            attributes.append(ForwardSourceInfoAttribute(messageId: sourceMessage.id))
                        
                            if peerId == account.peerId {
                                attributes.append(SourceReferenceMessageAttribute(messageId: sourceMessage.id))
                            }
                            
                            attributes.append(contentsOf: filterMessageAttributesForForwardedMessage(requestedAttributes))
                            attributes.append(contentsOf: filterMessageAttributesForForwardedMessage(sourceMessage.attributes, forwardedMessageIds: forwardedMessageIds))
                            
                            var sourceReplyMarkup: ReplyMarkupMessageAttribute? = nil
                            var sourceSentViaBot = false
                            for attribute in attributes {
                                if let attribute = attribute as? ReplyMarkupMessageAttribute {
                                    sourceReplyMarkup = attribute
                                } else if let _ = attribute as? InlineBotMessageAttribute {
                                    sourceSentViaBot = true
                                }
                            }
                            
                            if let sourceReplyMarkup = sourceReplyMarkup {
                                var rows: [ReplyMarkupRow] = []
                                loop: for row in sourceReplyMarkup.rows {
                                    var buttons: [ReplyMarkupButton] = []
                                    for button in row.buttons {
                                        if case .url = button.action {
                                            buttons.append(button)
                                        } else if case .urlAuth = button.action {
                                            buttons.append(button)
                                        } else if case let .switchInline(samePeer, query, peerTypes) = button.action, sourceSentViaBot {
                                            let samePeer = samePeer && peerId == sourceMessage.id.peerId
                                            let updatedButton = ReplyMarkupButton(title: button.titleWhenForwarded ?? button.title, titleWhenForwarded: button.titleWhenForwarded,  action: .switchInline(samePeer: samePeer, query: query, peerTypes: peerTypes), style: button.style)
                                            buttons.append(updatedButton)
                                        } else {
                                            rows.removeAll()
                                            break loop
                                        }
                                    }
                                    rows.append(ReplyMarkupRow(buttons: buttons))
                                }
                                
                                if !rows.isEmpty {
                                    attributes.append(ReplyMarkupMessageAttribute(rows: rows, flags: sourceReplyMarkup.flags, placeholder: sourceReplyMarkup.placeholder))
                                }
                            }
                            
                            if hideSendersNames {
                                
                            } else if let sourceForwardInfo = sourceMessage.forwardInfo {
                                forwardInfo = StoreMessageForwardInfo(authorId: sourceForwardInfo.author?.id, sourceId: sourceForwardInfo.source?.id, sourceMessageId: sourceForwardInfo.sourceMessageId, date: sourceForwardInfo.date, authorSignature: sourceForwardInfo.authorSignature, psaType: nil, flags: [])
                            } else {
                                if sourceMessage.id.peerId != account.peerId {
                                    var sourceId: PeerId? = nil
                                    var sourceMessageId: MessageId? = nil
                                    if case let .channel(peer) = messageMainPeer(EngineMessage(sourceMessage)), case .broadcast = peer.info {
                                        sourceId = peer.id
                                        sourceMessageId = sourceMessage.id
                                    }

                                    var authorSignature: String?
                                    for attribute in sourceMessage.attributes {
                                        if let attribute = attribute as? AuthorSignatureMessageAttribute {
                                            authorSignature = attribute.signature
                                            break
                                        }
                                    }

                                    let psaType: String? = nil

                                    forwardInfo = StoreMessageForwardInfo(authorId: author.id, sourceId: sourceId, sourceMessageId: sourceMessageId, date: sourceMessage.timestamp, authorSignature: authorSignature, psaType: psaType, flags: [])
                                } else {
                                    forwardInfo = nil
                                }
                            }
                            
                            for attribute in requestedAttributes {
                                if attribute is ForwardVideoTimestampAttribute {
                                    attributes.append(attribute)
                                }
                            }
                        } else {
                            attributes.append(contentsOf: filterMessageAttributesForOutgoingMessage(sourceMessage.attributes))
                        }
                                                
                        var messageNamespace = Namespaces.Message.Local
                        var entitiesAttribute: TextEntitiesMessageAttribute?
                        var effectiveTimestamp = timestamp
                        var sendAsPeer: Peer?
                        var threadId: Int64? = threadId
                        for attribute in attributes {
                            if let attribute = attribute as? TextEntitiesMessageAttribute {
                                entitiesAttribute = attribute
                            } else if let attribute = attribute as? OutgoingScheduleInfoMessageAttribute {
                                if attribute.scheduleTime == scheduleWhenOnlineTimestamp, let presence = peerPresence as? TelegramUserPresence, case let .present(statusTimestamp) = presence.status, statusTimestamp >= timestamp {
                                } else {
                                    messageNamespace = Namespaces.Message.ScheduledLocal
                                    effectiveTimestamp = attribute.scheduleTime
                                }
                            } else if attribute is OutgoingQuickReplyMessageAttribute {
                                messageNamespace = Namespaces.Message.QuickReplyLocal
                                effectiveTimestamp = 0
                            } else if let attribute = attribute as? ReplyMessageAttribute {
                                if let threadMessageId = attribute.threadMessageId {
                                    threadId = Int64(threadMessageId.id)
                                }
                            } else if let attribute = attribute as? SendAsMessageAttribute {
                                if let peer = transaction.getPeer(attribute.peerId) {
                                    sendAsPeer = peer
                                }
                            }
                        }
                        
                        let authorId: PeerId?
                        if let sendAsPeer = sendAsPeer {
                            authorId = sendAsPeer.id
                        } else if let peer = peer as? TelegramChannel {
                            if case .broadcast = peer.info {
                                authorId = peer.id
                            } else if case .group = peer.info, peer.hasPermission(.canBeAnonymous) {
                                authorId = peer.id
                            } else {
                                authorId = account.peerId
                            }
                        }  else {
                            authorId = account.peerId
                        }
                        
                        if messageNamespace != Namespaces.Message.ScheduledLocal {
                            attributes.removeAll(where: { $0 is OutgoingScheduleInfoMessageAttribute })
                        }
                        if messageNamespace != Namespaces.Message.QuickReplyLocal {
                            attributes.removeAll(where: { $0 is OutgoingQuickReplyMessageAttribute })
                        }
                        
                        let (tags, globalTags) = tagsForStoreMessage(incoming: false, attributes: attributes, media: sourceMessage.media, textEntities: entitiesAttribute?.entities, isPinned: false)
                        
                        let localGroupingKey: Int64?
                        switch grouping {
                            case .none:
                                localGroupingKey = nil
                            case .auto:
                                if let groupingKey = sourceMessage.groupingKey {
                                    if let generatedKey = localGroupingKeyBySourceKey[groupingKey] {
                                        localGroupingKey = generatedKey
                                    } else {
                                        let generatedKey = Int64.random(in: Int64.min ... Int64.max)
                                        localGroupingKeyBySourceKey[groupingKey] = generatedKey
                                        localGroupingKey = generatedKey
                                    }
                                } else {
                                    localGroupingKey = nil
                                }
                        }
                        
                        var augmentedMediaList = sourceMessage.media.map { media -> Media in
                            return augmentMediaWithReference(.message(message: MessageReference(sourceMessage), media: media))
                        }
                        
                        if peerId.namespace == Namespaces.Peer.SecretChat {
                            augmentedMediaList = augmentedMediaList.map(convertForwardedMediaForSecretChat)
                        }
                        
                        if threadId == nil, let peer = transaction.getPeer(peerId), peer.isForum {
                            threadId = 1
                        }
                                                
                        storeMessages.append(StoreMessage(peerId: peerId, namespace: messageNamespace, customStableId: nil, globallyUniqueId: randomId, groupingKey: localGroupingKey, threadId: threadId, timestamp: effectiveTimestamp, flags: flags, tags: tags, globalTags: globalTags, localTags: [], forwardInfo: forwardInfo, authorId: authorId, text: messageText, attributes: attributes, media: augmentedMediaList))
                    }
            }
        }
        var messageIds: [MessageId?] = []
        if !storeMessages.isEmpty {
            for emojiItem in emojiItems {
                if let entry = CodableEntry(emojiItem) {
                    let id: RecentEmojiItemId
                    switch emojiItem.content {
                    case let .file(file):
                        id = RecentEmojiItemId(file.fileId)
                    case let .text(text):
                        id = RecentEmojiItemId(text)
                    }
                    transaction.addOrMoveToFirstPositionOrderedItemListItem(collectionId: Namespaces.OrderedItemList.LocalRecentEmoji, item: OrderedItemListEntry(id: id.rawValue, contents: entry), removeTailIfCountExceeds: 20)
                }
            }
            
            let globallyUniqueIdToMessageId = transaction.addMessages(storeMessages, location: .Random)
            for globallyUniqueId in globallyUniqueIds {
                messageIds.append(globallyUniqueIdToMessageId[globallyUniqueId])
            }
            
            if peerId.namespace == Namespaces.Peer.CloudUser {
                if case .notIncluded = transaction.getPeerChatListInclusion(peerId) {
                    transaction.updatePeerChatListInclusion(peerId, inclusion: .ifHasMessagesOrOneOf(groupId: .root, pinningIndex: nil, minTimestamp: nil))
                }
            }
        }
        for hashtag in addedHashtags {
            addRecentlyUsedHashtag(transaction: transaction, string: hashtag)
        }
        return messageIds
    } else {
        return []
    }
}
