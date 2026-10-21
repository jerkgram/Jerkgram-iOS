import Foundation
import Darwin
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

/// The attributes an outgoing message stores for the ones it was requested with. A media timer is
/// requested as `AutoremoveTimeoutMessageAttribute`: a secret chat stores it as-is in place of the
/// chat's own timer, any other chat stores it as `AutoclearTimeoutMessageAttribute` beside the chat's
/// auto-delete period (`peerAutoremoveTimeout`).
func outgoingMessageAttributes(requestedAttributes: [MessageAttribute], isSecretChat: Bool, peerAutoremoveTimeout: Int32?) -> [MessageAttribute] {
    var peerAutoremoveTimeout = peerAutoremoveTimeout
    var attributes: [MessageAttribute] = []
    for attribute in filterMessageAttributesForOutgoingMessage(requestedAttributes) {
        if let attribute = attribute as? AutoremoveTimeoutMessageAttribute {
            if isSecretChat {
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
    return attributes
}

/// What a resent message requests in place of `attribute`, which the failed message stores in the
/// form `outgoingMessageAttributes` produced; nil when it is not requested again.
func resentMessageRequestedAttribute(_ attribute: MessageAttribute, isSecretChat: Bool) -> MessageAttribute? {
    if attribute is PaidStarsMessageAttribute {
        return nil
    }
    if let attribute = attribute as? AutoclearTimeoutMessageAttribute {
        // The media timer of a cloud chat, which is requested in its autoremove form.
        return AutoremoveTimeoutMessageAttribute(timeout: attribute.timeout, countdownBeginTime: nil)
    }
    if attribute is AutoremoveTimeoutMessageAttribute && !isSecretChat {
        // The chat's auto-delete period, derived again when the message is enqueued. Requested, it
        // would become a media timer.
        return nil
    }
    return attribute
}

/// What a forward requests when the server cannot forward it and it is sent as a copy, a new message
/// with the source's content: the source is not a cloud message, or the destination is a secret chat.
/// The copy takes the source's content and the forward's own attributes, which say how and where it
/// is sent. Nothing else the source stores is requested: its timer belongs to its chat and would
/// become a media timer in a cloud chat or override a secret chat's own, and its paid stars, send-as
/// peer and schedule are the source chat's. `hidesCaption` drops the formatting of a caption the
/// forward hides.
func forwardCopyRequestedAttributes(sourceAttributes: [MessageAttribute], forwardAttributes: [MessageAttribute], hidesCaption: Bool) -> [MessageAttribute] {
    let contentAttributes = sourceAttributes.filter { attribute in
        switch attribute {
        case _ as TextEntitiesMessageAttribute:
            return !hidesCaption
        case _ as RichTextMessageAttribute:
            return true
        case _ as InlineBotMessageAttribute:
            return true
        case _ as OutgoingContentInfoMessageAttribute:
            return true
        case _ as ReplyMarkupMessageAttribute:
            return true
        case _ as OutgoingChatContextResultMessageAttribute:
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
        default:
            return false
        }
    }
    return contentAttributes + forwardAttributes
}

/// The attributes a forwarded message stores from the forward's request and from its source: one of
/// each kind, the request's where both have one. A resent forward requests what the failed one
/// stored, which already includes the source's; and the sender reads the last paid stars a message
/// stores, which must be the destination's price rather than what the source was paid.
func forwardedMessageAttributes(requestedAttributes: [MessageAttribute], sourceAttributes: [MessageAttribute], forwardedMessageIds: Set<MessageId>?) -> [MessageAttribute] {
    let requested = filterMessageAttributesForForwardedMessage(requestedAttributes)
    let requestedKinds = Set(requested.map { ObjectIdentifier(type(of: $0)) })
    let source = filterMessageAttributesForForwardedMessage(sourceAttributes, forwardedMessageIds: forwardedMessageIds).filter { attribute in
        return !requestedKinds.contains(ObjectIdentifier(type(of: attribute)))
    }
    return requested + source
}

/// The local grouping key of a forwarded message: an album stays one album, under a key of its own
/// so it does not join the source's.
func forwardGroupingKey(grouping: EnqueueMessageGrouping, sourceGroupingKey: Int64?, generatedKeys: inout [Int64: Int64]) -> Int64? {
    switch grouping {
    case .none:
        return nil
    case .auto:
        guard let sourceGroupingKey = sourceGroupingKey else {
            return nil
        }
        if let generatedKey = generatedKeys[sourceGroupingKey] {
            return generatedKey
        }
        let generatedKey = Int64.random(in: Int64.min ... Int64.max)
        generatedKeys[sourceGroupingKey] = generatedKey
        return generatedKey
    }
}

private func filterMessageAttributesForEphemeralOutgoingMessage(_ attributes: [MessageAttribute]) -> [MessageAttribute] {
    return attributes.filter { attribute in
        switch attribute {
        case _ as TextEntitiesMessageAttribute:
            return true
        case _ as RichTextMessageAttribute:
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

private func enqueueEphemeralOutgoingMessage(transaction: Transaction, account: Account, peerId: PeerId, transformedMedia: Bool, message: EnqueueMessage, botPeerId: PeerId, isWelcomeTemplate: Bool = false) -> MessageId? {
    guard case let .message(text, requestedAttributes, inlineStickers, mediaReference, threadId, replyToMessageId, _, _, correlationId, bubbleUpEmojiOrStickersets) = message else {
        return nil
    }
    guard transaction.getPeer(peerId).flatMap(apiInputPeer) != nil else {
        return nil
    }
    if !isWelcomeTemplate && transaction.getPeer(botPeerId).flatMap(apiInputUser) == nil {
        return nil
    }

    for (_, file) in inlineStickers {
        transaction.storeMediaIfNotPresent(media: file)
    }

    var flags = StoreMessageFlags()
    flags.insert(.Sending)
    if isWelcomeTemplate {
        flags.insert(.Incoming)
    }

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
    attributes.append(EphemeralOutgoingMessageAttribute(botPeerId: botPeerId, randomId: randomId, state: .sending, isWelcomeTemplate: isWelcomeTemplate))

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

    let localId = generateEphemeralLocalMessageId(peerId: peerId, transaction: transaction, namespace: isWelcomeTemplate ? Namespaces.Message.WelcomeMessageLocal : Namespaces.Message.EphemeralLocal)
    var timestamp = Int32(account.network.context.globalTime())
    if isWelcomeTemplate {
        timestamp += 1
    }
    let storeMessage = StoreMessage(id: localId, customStableId: nil, globallyUniqueId: randomId, groupingKey: nil, threadId: threadId, timestamp: timestamp, flags: flags, tags: [], globalTags: [], localTags: [], forwardInfo: nil, authorId: isWelcomeTemplate ? peerId : account.peerId, text: text, attributes: attributes, media: mediaList)
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
        if message.id.namespace != Namespaces.Message.Cloud && !Namespaces.Message.allEphemeral.contains(message.id.namespace) {
            return message
        } else {
            return nil
        }
    } else {
        return nil
    }
}

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
    private static var values: [String: String]?
    private static var order: [String] = []

    // All access is protected by lock; these private keys have one in-process writer.
    private static func loadIfNeeded() {
        guard self.values == nil else { return }
        self.values = UserDefaults.standard.dictionary(forKey: self.valuesKey) as? [String: String] ?? [:]
        self.order = UserDefaults.standard.stringArray(forKey: self.orderKey) ?? []
    }

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

        self.loadIfNeeded()
        let defaults = UserDefaults.standard
        let key = String(peerId.toInt64())
        if self.values?[key] == name && self.order.last == key { return }
        var values = self.values ?? [:]
        var order = self.order
        values[key] = name
        order.removeAll(where: { $0 == key })
        order.append(key)

        while order.count > self.maximumCount {
            let removed = order.removeFirst()
            values.removeValue(forKey: removed)
        }
        if self.values != values { defaults.set(values, forKey: self.valuesKey) }
        if self.order != order { defaults.set(order, forKey: self.orderKey) }
        self.values = values
        self.order = order
    }

    static func name(peerId: PeerId) -> String? {
        self.lock.lock()
        defer { self.lock.unlock() }
        self.loadIfNeeded()
        return self.values?[String(peerId.toInt64())]
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

private func ghostBasePruneEmptyDeletedMediaDirectories(root: URL) {
    let keys: [URLResourceKey] = [.isDirectoryKey, .isSymbolicLinkKey]
    guard let children = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles]) else { return }
    for directory in children {
        guard let values = try? directory.resourceValues(forKeys: Set(keys)),
            values.isDirectory == true, values.isSymbolicLink != true else { continue }
        // Atomic empty-directory removal: never recursively remove media or follow links.
        _ = directory.path.withCString { Darwin.rmdir($0) }
    }
}

private enum GhostBaseDeletedMediaCache {
    private static let queueKey = DispatchSpecificKey<Bool>()
    private static let queue: DispatchQueue = {
        let queue = DispatchQueue(label: "org.ghostbase.deleted-media-cache", qos: .utility)
        queue.setSpecific(key: queueKey, value: true)
        return queue
    }()
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
        if DispatchQueue.getSpecific(key: self.queueKey) != true {
            return self.queue.sync { self.copyCompleteResource(mediaBox: mediaBox, messageId: messageId, spec: spec) }
        }
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
        if DispatchQueue.getSpecific(key: self.queueKey) != true {
            self.queue.async { self.cleanupIfNeeded(mediaBox: mediaBox) }
            return
        }
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
        ghostBasePruneEmptyDeletedMediaDirectories(root: root)
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

private struct GhostBaseDeletedReplyPlan {
    let outgoing: EnqueueMessage
    let source: Message?
    let sourceGroup: [Message]
    let authorName: String?
    let authorUsername: String?
    let mentionPeerId: PeerId?
    let limits: UserLimitsConfiguration
    var canSendPolls = false
    var canSendTodos = false
}

private struct GhostBaseDeletedQuoteBody {
    let text: String
    let originalTextOffset: Int?
    let entities: [MessageTextEntity]
}

private func ghostBaseDeletedMediaLabel(_ message: Message, languageCode: String) -> String? {
    func label(_ key: JerkgramDeletedReplyLabel) -> String {
        return key.text(languageCode: languageCode)
    }
    if message.groupingKey != nil && !message.media.isEmpty {
        return label(.album)
    }

    guard let media = message.media.first else {
        return nil
    }
    if media is TelegramMediaPoll {
        return label(.poll)
    }
    if media is TelegramMediaMap {
        return label(.location)
    }
    if media is TelegramMediaContact {
        return label(.contact)
    }
    if media is TelegramMediaDice {
        return label(.dice)
    }
    if media is TelegramMediaTodo {
        return label(.todo)
    }
    if media is TelegramMediaImage {
        return label(.photo)
    }
    if let file = media as? TelegramMediaFile {
        if file.isSticker {
            return label(.sticker)
        } else if file.isVoice {
            return label(.voice)
        } else if file.isInstantVideo {
            return label(.videoMessage)
        } else if file.isAnimated {
            return label(.gif)
        } else if file.isVideo {
            return label(.video)
        } else if file.isMusic {
            return label(.audio)
        } else {
            return label(.file)
        }
    }
    return label(.attachment)
}

private func ghostBaseQuoteBody(
    source: Message,
    recoveredMedia: Bool,
    languageCode: String
) -> GhostBaseDeletedQuoteBody {
    let sourceText = source.text
    if let file = source.media.first as? TelegramMediaFile, file.isSticker {
        var association = ""
        for attribute in file.attributes {
            if case let .Sticker(displayText, _, _) = attribute {
                association = displayText.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines)
                break
            }
        }
        let emoji = JerkgramDeletedReplyLabel.sticker.text(languageCode: languageCode) + (association.isEmpty ? "" : " " + association)
        return GhostBaseDeletedQuoteBody(text: emoji + (sourceText.isEmpty ? "" : "\n" + sourceText), originalTextOffset: sourceText.isEmpty ? nil : (emoji as NSString).length + 1, entities: [])
    }
    let interactiveSnapshot = source.media.first is TelegramMediaPoll || source.media.first is TelegramMediaTodo
    // Native attachment already conveys its type, filename, contact and map data.
    if recoveredMedia && !interactiveSnapshot || source.media.isEmpty {
        return GhostBaseDeletedQuoteBody(text: sourceText, originalTextOffset: sourceText.isEmpty ? nil : 0, entities: [])
    }

    var body = JerkgramDeletedReplyText()
    var entities: [MessageTextEntity] = []
    func append(_ text: String, _ sourceEntities: [MessageTextEntity] = [], prefix: String = "") {
        guard let offset = body.append(text, prefix: prefix) else { return }
        // Preserve rich text, excluding a nested quote inside the outer quote.
        let validEntities = messageTextEntitiesInRange(entities: sourceEntities, range: NSRange(location: 0, length: (text as NSString).length), onlyQuoteable: false).filter {
            if case .BlockQuote = $0.type { return false }
            return true
        }
        entities.append(contentsOf: ghostBaseShiftEntities(validEntities, by: offset))
    }
    func label(_ key: JerkgramDeletedReplyLabel) {
        append(key.text(languageCode: languageCode))
    }

    if let poll = source.media.first as? TelegramMediaPoll {
        label(recoveredMedia ? .freshPollSnapshot : .poll)
        append(poll.text, poll.textEntities)
        if recoveredMedia {
            label(poll.isClosed ? .pollClosed : .pollOpen)
            if let total = poll.results.totalVoters {
                append("\(JerkgramDeletedReplyLabel.votes.text(languageCode: languageCode)): \(total)")
            }
        }
        for option in poll.options {
            append(option.text, option.entities, prefix: "• ")
            if recoveredMedia, let voter = poll.results.voters?.first(where: { $0.opaqueIdentifier == option.opaqueIdentifier }) {
                if let count = voter.count {
                    append("\(JerkgramDeletedReplyLabel.votes.text(languageCode: languageCode)): \(count)")
                }
                if voter.selected { label(.selected) }
            }
        }
        if let solution = poll.results.solution {
            append(solution.text, solution.entities)
        }
    } else if let todo = source.media.first as? TelegramMediaTodo {
        label(recoveredMedia ? .freshTodoSnapshot : .todo)
        append(todo.text, todo.textEntities)
        let completed = Set(todo.completions.map { $0.id })
        for item in todo.items {
            append(item.text, item.entities, prefix: completed.contains(item.id) ? "☑ " : "- ")
        }
    } else if let action = source.media.first as? TelegramMediaAction {
        let reply = source.attributes.first(where: { $0 is ReplyMessageAttribute }) as? ReplyMessageAttribute
        let originalInteractive = reply.flatMap { source.associatedMessages[$0.messageId] }
        if let originalPoll = originalInteractive?.media.first as? TelegramMediaPoll {
            label(.poll)
            append(originalPoll.text, originalPoll.textEntities)
        } else if let originalTodo = originalInteractive?.media.first as? TelegramMediaTodo {
            label(.todo)
            append(originalTodo.text, originalTodo.textEntities)
        }
        switch action.action {
        case let .todoAppendTasks(items):
            label(.tasksAdded)
            for item in items { append(item.text, item.entities, prefix: "+ ") }
        case let .pollOptionAppended(option):
            label(.pollOptionAdded)
            append(option.text, option.entities, prefix: "• ")
        case let .pollOptionDeleted(option):
            label(.pollOptionDeleted)
            append(option.text, option.entities, prefix: "• ")
        case let .todoCompletions(completed, incompleted):
            let reply = source.attributes.first(where: { $0 is ReplyMessageAttribute }) as? ReplyMessageAttribute
            let originalTodo = reply.flatMap { source.associatedMessages[$0.messageId]?.media.first as? TelegramMediaTodo }
            for (ids, key, prefix) in [(completed, JerkgramDeletedReplyLabel.tasksCompleted, "☑ "), (incompleted, .tasksIncomplete, "- ")] where !ids.isEmpty {
                if let originalTodo {
                    label(key)
                    for id in ids {
                        if let item = originalTodo.items.first(where: { $0.id == id }) {
                            append(item.text, item.entities, prefix: prefix)
                        } else {
                            append("\(JerkgramDeletedReplyLabel.task.text(languageCode: languageCode)) #\(id)", prefix: prefix)
                        }
                    }
                } else {
                    // The service action stores IDs only. Never invent missing task names.
                    append("\(key.text(languageCode: languageCode)): \(ids.count)")
                }
            }
            if completed.isEmpty && incompleted.isEmpty { label(.todo) }
        default:
            append(ghostBaseDeletedMediaLabel(source, languageCode: languageCode) ?? JerkgramDeletedReplyLabel.deletedMessage.text(languageCode: languageCode))
        }
    } else if let contact = source.media.first as? TelegramMediaContact {
        label(.contact)
        append([contact.firstName, contact.lastName].filter { !$0.isEmpty }.joined(separator: " "))
        append(contact.phoneNumber)
    } else if let map = source.media.first as? TelegramMediaMap {
        label(.location)
        if let venue = map.venue {
            append(venue.title)
            append(venue.address ?? "")
        }
        append("\(map.latitude), \(map.longitude)")
    } else if let dice = source.media.first as? TelegramMediaDice {
        append(dice.emoji)
        if let value = dice.value {
            append("\(JerkgramDeletedReplyLabel.dice.text(languageCode: languageCode)): \(value)")
        }
    } else if let invoice = source.media.first as? TelegramMediaInvoice {
        label(.invoice)
        append(invoice.title)
        append(invoice.description)
    } else {
        append(ghostBaseDeletedMediaLabel(source, languageCode: languageCode) ?? JerkgramDeletedReplyLabel.deletedMessage.text(languageCode: languageCode))
        if let file = source.media.first as? TelegramMediaFile {
            append(file.fileName ?? "")
        }
    }
    let originalTextOffset = body.append(sourceText)
    if body.text.isEmpty {
        _ = body.append(JerkgramDeletedReplyLabel.deletedMessage.text(languageCode: languageCode))
    }
    return GhostBaseDeletedQuoteBody(text: body.text, originalTextOffset: originalTextOffset, entities: entities)
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
    languageCode: String,
    limits: UserLimitsConfiguration,
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
        userMediaReference == nil && (userText as NSString).length <= Int(limits.maxCaptionLength) ? recoveredMedia : nil
    let body = ghostBaseQuoteBody(
        source: source,
        recoveredMedia: effectiveRecoveredMedia != nil,
        languageCode: languageCode
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

    let hasMedia = userMediaReference != nil || effectiveRecoveredMedia != nil
    let limit = Int(hasMedia ? limits.maxCaptionLength : limits.maxMessageLength)
    let fittedQuote = JerkgramDeletedReplyText.fittedQuote(quoteText, reply: userText, limit: limit, languageCode: languageCode)
    quoteText = fittedQuote.text
    let separator = userText.isEmpty || quoteText.isEmpty ? "" : "\n\n"
    let finalText = quoteText + separator + userText
    let quoteLength = (quoteText as NSString).length
    let userOffset = ((quoteText + separator) as NSString).length

    var entities: [MessageTextEntity] = []
    entities.append(contentsOf: ghostBaseShiftEntities(body.entities, by: authorLength + 1))
    if authorLength > 0 {
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

    if let originalTextStart {
        entities.append(contentsOf: ghostBaseShiftEntities(
            ghostBaseOriginalPortableEntities(source: source),
            by: originalTextStart
        ))
    }

    // Only the retained source prefix gets source/author formatting. The notice
    // must not inherit a truncated URL, custom emoji or source formatting range.
    entities = messageTextEntitiesInRange(entities: entities, range: NSRange(location: 0, length: fittedQuote.retainedLength), onlyQuoteable: false)
    let collapse = quoteLength > 320 || quoteText.components(separatedBy: "\n").count > 4
    if quoteLength > 0 {
        entities.append(MessageTextEntity(range: 0 ..< quoteLength, type: .BlockQuote(isCollapsed: collapse)))
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


// Structured media carries its own payload: no deleted binary cache is needed.
private func ghostBaseStaticDeletedMedia(media: Media) -> AnyMediaReference? {
    if let contact = media as? TelegramMediaContact {
        return .standalone(media: TelegramMediaContact(firstName: contact.firstName, lastName: contact.lastName,
            phoneNumber: contact.phoneNumber, peerId: contact.peerId, vCardData: contact.vCardData))
    }
    if let map = media as? TelegramMediaMap {
        return .standalone(media: TelegramMediaMap(latitude: map.latitude, longitude: map.longitude,
            heading: map.heading, accuracyRadius: map.accuracyRadius, venue: map.venue, address: map.address,
            liveBroadcastingTimeout: nil, liveProximityNotificationRadius: nil))
    }
    return nil
}

// These are new interactive objects. Historical votes/completions remain in the
// quote snapshot only. Complex polls use the localized text fallback.
private func ghostBaseFreshDeletedInteractiveMedia(
    media: Media,
    randomId: Int64,
    canSendPolls: Bool,
    canSendTodos: Bool
) -> AnyMediaReference? {
    if let poll = media as? TelegramMediaPoll {
        guard canSendPolls, !poll.text.isEmpty, (poll.text as NSString).length <= 255,
              (2 ... 10).contains(poll.options.count),
              poll.attachedMedia == nil, poll.results.solution?.media == nil,
              !poll.openAnswers, !poll.restrictToSubscribers, poll.countries.isEmpty,
              poll.options.allSatisfy({ !$0.text.isEmpty && ($0.text as NSString).length <= 100 && $0.media == nil }) else { return nil }
        // Unknown correct answers cannot produce a valid quiz. Keep quiz snapshots
        // textual until the full creation constraints are explicitly supported.
        if case .quiz = poll.kind { return nil }
        let options = poll.options.enumerated().map { index, option in
            return TelegramMediaPollOption(text: option.text, entities: option.entities,
                opaqueIdentifier: Data("\(randomId):\(index)".utf8), media: nil, date: nil, addedBy: nil)
        }
        let freshPoll = TelegramMediaPoll(pollId: MediaId(namespace: Namespaces.Media.LocalPoll, id: randomId),
            publicity: poll.publicity, kind: poll.kind, text: poll.text, textEntities: poll.textEntities,
            options: options, correctAnswers: nil,
            results: TelegramMediaPollResults(voters: nil, totalVoters: nil, recentVoters: [], solution: nil, hasUnseenVotes: nil, canViewStats: false),
            isClosed: false, deadlineTimeout: nil, deadlineDate: nil, pollHash: 0)
        return .standalone(media: freshPoll)
    }
    if let todo = media as? TelegramMediaTodo {
        guard canSendTodos, !todo.text.isEmpty, (todo.text as NSString).length <= 255,
              (1 ... 30).contains(todo.items.count),
              todo.items.allSatisfy({ !$0.text.isEmpty && ($0.text as NSString).length <= 255 }) else { return nil }
        let firstId = Int32(truncatingIfNeeded: randomId & 0x3fffffff) + 1
        let items = todo.items.enumerated().map { index, item in
            return TelegramMediaTodo.Item(text: item.text, entities: item.entities, id: firstId + Int32(index))
        }
        return .standalone(media: TelegramMediaTodo(flags: todo.flags, text: todo.text,
            textEntities: todo.textEntities, items: items, completions: []))
    }
    return nil
}

private func ghostBaseReconstructedMedia(
    account: Account,
    peerId: PeerId,
    source: Message,
    outgoing: EnqueueMessage,
    canSendPolls: Bool,
    canSendTodos: Bool
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
    if let structured = ghostBaseStaticDeletedMedia(media: media) { return structured }
    if media is TelegramMediaPoll || media is TelegramMediaTodo {
        return nil // Keep the original poll/task contents as text, not a new interactive object.
    }
    guard media is TelegramMediaFile || media is TelegramMediaImage else { return nil }
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
    // Most sends have no reply. Avoid settings I/O, a Postbox transaction and
    // an extra worker dispatch for those messages.
    guard messages.contains(where: { outgoing in
        if case let .message(_, _, _, _, _, replySubject, _, _, _, _) = outgoing {
            return replySubject != nil
        }
        return false
    }) else {
        return .single(messages)
    }
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
        var retainedLimits: UserLimitsConfiguration?
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
                    mentionPeerId: nil,
                    limits: .defaultValue
                )
            }

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

            if retainedLimits == nil {
                let appConfiguration = transaction.getPreferencesEntry(key: PreferencesKeys.appConfiguration)?.get(AppConfiguration.self) ?? .defaultValue
                let isPremium = (transaction.getPeer(account.peerId) as? TelegramUser)?.flags.contains(.isPremium) ?? false
                retainedLimits = UserLimitsConfiguration(appConfiguration: appConfiguration, isPremium: isPremium)
            }
            // Mirror conservative creation gates from the pinned attachment menu.
            // Resolve only for deleted plans; ordinary sends keep the fast path.
            let isPremium = (transaction.getPeer(account.peerId) as? TelegramUser)?.flags.contains(.isPremium) ?? false
            var canSendPolls = false
            var canSendTodos = false
            if let peer = transaction.getPeer(peerId) as? TelegramUser {
                canSendPolls = peer.botInfo != nil || peerId == account.peerId
                canSendTodos = isPremium
            } else if let group = transaction.getPeer(peerId) as? TelegramGroup {
                canSendPolls = !group.hasBannedPermission(.banSendPolls) && !group.hasBannedPermission(.banSendText)
                canSendTodos = isPremium && !group.hasBannedPermission(.banSendText)
            } else if let channel = transaction.getPeer(peerId) as? TelegramChannel {
                canSendPolls = channel.hasBannedPermission(.banSendPolls) == nil && channel.hasBannedPermission(.banSendText) == nil && !channel.isMonoForum
                if case .group = channel.info {
                    canSendTodos = isPremium && channel.hasBannedPermission(.banSendText) == nil && !channel.isMonoForum
                }
            }
            return GhostBaseDeletedReplyPlan(
                outgoing: outgoing,
                source: source,
                sourceGroup: sourceGroup,
                authorName: authorName,
                authorUsername: authorUsername,
                mentionPeerId: mentionPeerId,
                limits: retainedLimits!,
                canSendPolls: canSendPolls,
                canSendTodos: canSendTodos
            )
        }
    }
    |> mapToSignal { plans -> Signal<[EnqueueMessage], NoError> in
        guard plans.contains(where: { $0.source != nil }) else {
            return .single(messages)
        }
        return account.jerkgramDeletedReplyLanguageCode()
        |> mapToSignal { languageCode -> Signal<[EnqueueMessage], NoError> in
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
                                outgoing: plan.outgoing,
                                canSendPolls: plan.canSendPolls,
                                canSendTodos: plan.canSendTodos
                            ) {
                            recoveredGroup.append(recovered)
                        }
                    }

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
                                languageCode: languageCode,
                                limits: plan.limits,
                                forcedLocalGroupingKey: localGroupingKey
                            )

                        if case let .message(
                            text, _, _, _, _, _, _, _, _, _
                        ) = first,
                        (text as NSString).length > Int(plan.limits.maxCaptionLength) {
                            first =
                                ghostBaseBuildPortableDeletedReply(
                                    outgoing: plan.outgoing,
                                    source: source,
                                    authorName: authorName,
                                    authorUsername: plan.authorUsername,
                                    mentionPeerId: plan.mentionPeerId,
                                    recoveredMedia: nil,
                                    languageCode: languageCode,
                                    limits: plan.limits
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
                            recoveredMedia: recovered,
                            languageCode: languageCode,
                            limits: plan.limits
                        )

                    if recovered != nil,
                       case let .message(
                            text, _, _, _, _, _, _, _, _, _
                       ) = candidate,
                       (text as NSString).length > Int(plan.limits.maxCaptionLength) {
                        candidate =
                            ghostBaseBuildPortableDeletedReply(
                                outgoing: plan.outgoing,
                                source: source,
                                authorName: authorName,
                                authorUsername: plan.authorUsername,
                                mentionPeerId: plan.mentionPeerId,
                                recoveredMedia: nil,
                                languageCode: languageCode,
                                limits: plan.limits
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

public func enqueueWelcomeMessages(account: Account, peerId: PeerId, messages: [EnqueueMessage]) -> Signal<[MessageId?], NoError> {
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
            var pendingMessageIds: [MessageId] = []
            for i in 0 ..< messages.count {
                let (transformedMedia, message) = messages[i]
                if let messageId = enqueueEphemeralOutgoingMessage(transaction: transaction, account: account, peerId: peerId, transformedMedia: transformedMedia, message: message, botPeerId: peerId, isWelcomeTemplate: true) {
                    resultIds[i] = messageId
                    pendingMessageIds.append(messageId)
                }
            }
            return (resultIds, pendingMessageIds)
        }
        |> map { resultIds, pendingMessageIds -> [MessageId?] in
            for messageId in pendingMessageIds {
                let _ = _internal_sendEphemeralOutgoingMessage(account: account, messageId: messageId).startStandalone()
            }
            return resultIds
        }
    }
}

private func ghostBaseProtectedCopyFailureText(languageCode: String) -> String {
    let russian = languageCode.lowercased().split(whereSeparator: { $0 == "-" || $0 == "_" }).first == "ru"
    return russian ? "Не удалось скопировать защищённое сообщение. Исходное вложение недоступно или его нельзя отправить в этот чат." : "Could not copy this protected message. Its original attachment is unavailable or cannot be sent here."
}

private func ghostBaseProtectedForwardAllowsTextFallback(_ media: Media?) -> Bool {
    return media is TelegramMediaPoll || media is TelegramMediaTodo
}

private func ghostBaseProtectedSourceMessageLink(username: String?, channelId: Int64?, messageId: Int32) -> String? {
    guard let channelId else { return nil }
    if let username, !username.isEmpty { return "https://t.me/\(username)/\(messageId)" }
    return "https://t.me/c/\(channelId)/\(messageId)"
}

private func ghostBaseProtectedForwardEnabled(enabled: Bool, chatForward: Bool, messageProtected: Bool, peerProtected: Bool, dmProtected: Bool, myDmProtected: Bool, channelRestricted: Bool = false) -> Bool {
    return enabled && chatForward && (messageProtected || peerProtected || dmProtected || myDmProtected || channelRestricted)
}

private func ghostBaseProtectedForwardText(title: String, link: String?, mentionPeerId: PeerId?, body: String, bodyEntities: [MessageTextEntity], hideNames: Bool, limit: Int, languageCode: String) -> (text: String, entities: [MessageTextEntity]) {
    let header = hideNames ? "" : title
    let separator = header.isEmpty || body.isEmpty ? "" : "\n"
    let prefix = header + separator
    let fitted = JerkgramDeletedReplyText.fittedQuote(prefix + body, reply: "", limit: limit, languageCode: languageCode)
    var entities = ghostBaseShiftEntities(bodyEntities, by: (prefix as NSString).length)
    let titleLength = (header as NSString).length
    if titleLength > 0 {
        entities.append(MessageTextEntity(range: 0 ..< titleLength, type: .Bold))
        if let link { entities.append(MessageTextEntity(range: 0 ..< titleLength, type: .TextUrl(url: link))) }
        else if let mentionPeerId { entities.append(MessageTextEntity(range: 0 ..< titleLength, type: .TextMention(peerId: mentionPeerId))) }
    }
    entities = messageTextEntitiesInRange(entities: entities, range: NSRange(location: 0, length: fitted.retainedLength), onlyQuoteable: false)
    let quoteLength = (fitted.text as NSString).length
    if quoteLength > 0 {
        let collapse = quoteLength > 320 || fitted.text.components(separatedBy: "\n").count > 4
        entities.append(MessageTextEntity(range: 0 ..< quoteLength, type: .BlockQuote(isCollapsed: collapse)))
    }
    return (fitted.text, entities)
}

private func ghostBaseBuildProtectedForward(outgoing: EnqueueMessage, source: Message, mediaReference: AnyMediaReference?, groupingKey: Int64?, limits: UserLimitsConfiguration, languageCode: String, sourcePeer: Peer? = nil) -> EnqueueMessage {
    guard case let .forward(_, threadId, _, requested, correlationId) = outgoing else { return outgoing }
    let options = requested.compactMap { $0 as? ForwardOptionsMessageAttribute }.last
    let hideNames = options?.hideNames == true
    let hideCaptions = options?.hideCaptions == true && (source.media.first is TelegramMediaFile || source.media.first is TelegramMediaImage)
    let actualPeer = sourcePeer ?? source.peers[source.id.peerId]
    let title = actualPeer.map { EnginePeer($0).debugDisplayTitle } ?? ""
    let username = actualPeer.map { EnginePeer($0).addressName } ?? nil
    let channelId: Int64? = source.id.peerId.namespace == Namespaces.Peer.CloudChannel ? source.id.peerId.id._internalGetInt64Value() : nil
    let messageLink = ghostBaseProtectedSourceMessageLink(username: username, channelId: channelId, messageId: source.id.id)
    // DMs have no portable source-message URL; profile links/mentions identify the chat only.
    let attributionLink = messageLink ?? (channelId == nil ? username.flatMap { $0.isEmpty ? nil : "https://t.me/\($0)" } : nil)
    let mentionPeerId = source.id.peerId.namespace == Namespaces.Peer.CloudUser && attributionLink == nil ? source.id.peerId : nil
    let binaryMedia = source.media.first is TelegramMediaFile || source.media.first is TelegramMediaImage
    let quoteBody = binaryMedia ? GhostBaseDeletedQuoteBody(text: source.text, originalTextOffset: source.text.isEmpty ? nil : 0, entities: []) : ghostBaseQuoteBody(source: source, recoveredMedia: mediaReference != nil, languageCode: languageCode)
    var bodyEntities = quoteBody.entities
    if let offset = quoteBody.originalTextOffset {
        bodyEntities.append(contentsOf: ghostBaseShiftEntities(ghostBaseOriginalPortableEntities(source: source), by: offset))
    }
    let text = ghostBaseProtectedForwardText(title: title, link: attributionLink, mentionPeerId: mentionPeerId,
        body: hideCaptions ? "" : quoteBody.text, bodyEntities: hideCaptions ? [] : bodyEntities, hideNames: hideNames,
        limit: Int(mediaReference == nil ? limits.maxMessageLength : limits.maxCaptionLength), languageCode: languageCode)
    func isCopyTransportAttribute(_ attribute: MessageAttribute) -> Bool {
        return attribute is ForwardSourceInfoAttribute || attribute is SourceReferenceMessageAttribute || attribute is OutgoingChatContextResultMessageAttribute
    }
    var attributes = forwardCopyRequestedAttributes(sourceAttributes: source.attributes, forwardAttributes: requested, hidesCaption: hideCaptions)
    let requestedKinds = Set(requested.map { ObjectIdentifier(type(of: $0)) })
    attributes = attributes.filter { attribute in
        if attribute is TextEntitiesMessageAttribute || attribute is ForwardOptionsMessageAttribute || isCopyTransportAttribute(attribute) { return false }
        return !requestedKinds.contains(ObjectIdentifier(type(of: attribute)))
    } + requested.filter { !($0 is TextEntitiesMessageAttribute) && !($0 is ForwardOptionsMessageAttribute) && !isCopyTransportAttribute($0) }
    if !text.entities.isEmpty { attributes.append(TextEntitiesMessageAttribute(entities: text.entities)) }
    var stickers: [MediaId: Media] = [:]
    for entity in text.entities {
        if case let .CustomEmoji(_, fileId) = entity.type {
            let id = MediaId(namespace: Namespaces.Media.CloudFile, id: fileId)
            if let file = source.associatedMedia[id] as? TelegramMediaFile { stickers[id] = file }
        }
    }
    for attribute in attributes {
        if let embedded = attribute as? EmbeddedMediaStickersMessageAttribute {
            for file in embedded.files { stickers[file.fileId] = file }
        }
    }
    return .message(text: text.text, attributes: attributes, inlineStickers: stickers, mediaReference: mediaReference,
        threadId: threadId, replyToMessageId: nil, replyToStoryId: nil, localGroupingKey: groupingKey,
        correlationId: correlationId, bubbleUpEmojiOrStickersets: [])
}

private func ghostBaseProtectedLocalMedia(account: Account, source: Message, canSendPolls: Bool, canSendTodos: Bool) -> Signal<AnyMediaReference?, NoError> {
    guard let media = source.media.first, source.media.count == 1 else { return .single(nil) }
    if let structured = ghostBaseStaticDeletedMedia(media: media) { return .single(structured) }
    if media is TelegramMediaPoll || media is TelegramMediaTodo {
        return .single(nil) // Polls and task lists are copied as titled text snapshots.
    }
    if media is TelegramMediaWebpage { return .single(.standalone(media: media)) }
    let resource: TelegramMediaResource
    let contentType: MediaResourceUserContentType
    if let file = media as? TelegramMediaFile { resource = file.resource; contentType = MediaResourceUserContentType(file: file) }
    else if let image = media as? TelegramMediaImage, let largest = largestImageRepresentation(image.representations) { resource = largest.resource; contentType = .image }
    else { return .single(nil) }
    let mediaBox = account.postbox.mediaBox
    let reference = AnyMediaReference.message(message: MessageReference(source), media: media).resourceReference(resource)
    func localCopy(_ data: MediaResourceData) -> AnyMediaReference? {
        guard data.complete, data.size > 0 else { return nil }
        let randomId = Int64.random(in: Int64.min ... Int64.max)
        let identity = LocalFileReferenceMediaResource(localFilePath: "", randomId: randomId)
        // Own the bytes under the outgoing resource ID before source fetch paths can disappear.
        let path = mediaBox.resourcePath(identity)
        do { try FileManager.default.copyItem(atPath: data.path, toPath: path) } catch { return nil }
        let local = LocalFileReferenceMediaResource(localFilePath: path, randomId: randomId,
            isUniquelyReferencedTemporaryFile: false, size: data.size)
        if let file = media as? TelegramMediaFile {
            return .standalone(media: TelegramMediaFile(fileId: MediaId(namespace: Namespaces.Media.LocalFile, id: randomId),
                partialReference: nil, resource: local, previewRepresentations: [], videoThumbnails: [], videoCover: nil,
                immediateThumbnailData: file.immediateThumbnailData, mimeType: file.mimeType, size: data.size,
                attributes: file.attributes, alternativeRepresentations: []))
        }
        if let image = media as? TelegramMediaImage, let largest = largestImageRepresentation(image.representations) {
            let representation = TelegramMediaImageRepresentation(dimensions: largest.dimensions, resource: local,
                progressiveSizes: [], immediateThumbnailData: nil, hasVideo: false, isPersonal: false, typeHint: .generic)
            return .standalone(media: TelegramMediaImage(imageId: MediaId(namespace: Namespaces.Media.LocalImage, id: randomId),
                representations: [representation], videoRepresentations: [], immediateThumbnailData: image.immediateThumbnailData,
                emojiMarkup: nil, reference: nil, partialReference: nil, flags: [], video: nil))
        }
        return nil
    }
    return mediaBox.resourceData(resource, option: .complete(waitUntilFetchStatus: false))
    |> take(1)
    |> mapToSignal { cached -> Signal<AnyMediaReference?, NoError> in
        if cached.complete { return .single(localCopy(cached)) }
        return Signal { subscriber in
            let disposables = DisposableSet()
            disposables.add(mediaBox.resourceData(resource, option: .complete(waitUntilFetchStatus: true)).start(next: { data in
                if data.complete { subscriber.putNext(localCopy(data)); subscriber.putCompletion() }
            }))
            disposables.add(fetchedMediaResource(mediaBox: mediaBox, userLocation: .peer(source.id.peerId),
                userContentType: contentType, reference: reference).start(error: { _ in
                    subscriber.putNext(nil); subscriber.putCompletion()
                }))
            return disposables
        }
        |> take(1)
        |> timeout(30.0, queue: Queue.concurrentDefaultQueue(), alternate: .single(nil))
    }
    |> take(1)
}

private func ghostBaseResolveProtectedForwards(account: Account, peerId: PeerId, messages: [EnqueueMessage]) -> Signal<[EnqueueMessage]?, NoError> {
    let enabled = (JerkgramHotSettings.object(forKey: "jerkgram.ProtectedContent.Enabled") as? Bool) ?? true
    let chatForward = (JerkgramHotSettings.object(forKey: "jerkgram.ProtectedContent.ChatForward") as? Bool) ?? true
    guard enabled && chatForward,
        (peerId.namespace == Namespaces.Peer.CloudUser || peerId.namespace == Namespaces.Peer.CloudGroup || peerId.namespace == Namespaces.Peer.CloudChannel),
        messages.contains(where: { if case .forward = $0 { return true }; return false }) else { return .single(messages) }
    return account.postbox.transaction { transaction -> [(EnqueueMessage, Message?, Int64?, UserLimitsConfiguration, Bool, Bool, Peer?)] in
        let config = transaction.getPreferencesEntry(key: PreferencesKeys.appConfiguration)?.get(AppConfiguration.self) ?? .defaultValue
        let premium = (transaction.getPeer(account.peerId) as? TelegramUser)?.flags.contains(.isPremium) ?? false
        let limits = UserLimitsConfiguration(appConfiguration: config, isPremium: premium)
        var polls = false, todos = false
        if let user = transaction.getPeer(peerId) as? TelegramUser { polls = user.botInfo != nil || peerId == account.peerId; todos = premium }
        else if let group = transaction.getPeer(peerId) as? TelegramGroup {
            polls = !group.hasBannedPermission(.banSendPolls) && !group.hasBannedPermission(.banSendText)
            todos = premium && !group.hasBannedPermission(.banSendText)
        } else if let channel = transaction.getPeer(peerId) as? TelegramChannel {
            polls = channel.hasBannedPermission(.banSendPolls) == nil && channel.hasBannedPermission(.banSendText) == nil && !channel.isMonoForum
            if case .group = channel.info { todos = premium && channel.hasBannedPermission(.banSendText) == nil && !channel.isMonoForum }
        }
        var groupingKeys: [Int64: Int64] = [:]
        return messages.map { outgoing in
            guard case let .forward(id, _, grouping, _, _) = outgoing, id.namespace == Namespaces.Message.Cloud,
                id.peerId.namespace != Namespaces.Peer.SecretChat, let source = transaction.getMessage(id),
                !source.containsSecretMedia, !source.media.contains(where: { $0 is TelegramMediaPaidContent || $0 is TelegramMediaAction || $0 is TelegramMediaExpiredContent }) else { return (outgoing, nil, nil, limits, polls, todos, nil) }
            let cached = transaction.getPeerCachedData(peerId: source.id.peerId) as? CachedUserData
            let dmProtected = cached.map { cached in cached.flags.contains(.copyProtectionEnabled) || cached.flags.contains(.myCopyProtectionEnabled) } ?? false
            let actualPeer = transaction.getPeer(source.id.peerId) ?? source.peers[source.id.peerId]
            let sourceChannel = actualPeer as? TelegramChannel
            let channelRestricted = sourceChannel.map { $0.flags.contains(.isScam) || $0.flags.contains(.isFake) } ?? false
            let protected = ghostBaseProtectedForwardEnabled(enabled: enabled, chatForward: chatForward,
                messageProtected: source.isCopyProtected(), peerProtected: actualPeer?.isCopyProtectionEnabled == true,
                dmProtected: dmProtected, myDmProtected: false, channelRestricted: channelRestricted)
            guard protected else { return (outgoing, nil, nil, limits, polls, todos, nil) }
            return (outgoing, source, forwardGroupingKey(grouping: grouping, sourceGroupingKey: source.groupingKey, generatedKeys: &groupingKeys), limits, polls, todos, actualPeer)
        }
    }
    |> mapToSignal { plans -> Signal<[EnqueueMessage]?, NoError> in
        guard plans.contains(where: { $0.1 != nil }) else { return .single(messages) }
        return account.jerkgramDeletedReplyLanguageCode()
        |> mapToSignal { languageCode in
            let signals: [Signal<EnqueueMessage?, NoError>] = plans.map { outgoing, source, grouping, limits, polls, todos, sourcePeer in
                guard let source else { return .single(outgoing) }
                if source.media.isEmpty {
                    return .single(ghostBaseBuildProtectedForward(outgoing: outgoing, source: source, mediaReference: nil, groupingKey: grouping, limits: limits, languageCode: languageCode, sourcePeer: sourcePeer))
                }
                return ghostBaseProtectedLocalMedia(account: account, source: source, canSendPolls: polls, canSendTodos: todos)
                |> map { media -> EnqueueMessage? in
                    guard media != nil || ghostBaseProtectedForwardAllowsTextFallback(source.media.first) else { return nil }
                    return ghostBaseBuildProtectedForward(outgoing: outgoing, source: source, mediaReference: media, groupingKey: grouping, limits: limits, languageCode: languageCode, sourcePeer: sourcePeer)
                }
            }
            return combineLatest(signals) |> map { resolved -> [EnqueueMessage]? in
                guard resolved.allSatisfy({ $0 != nil }) else { return nil }
                return resolved.compactMap { $0 }
            }
        }
    }
}

public func enqueueMessages(
    account: Account,
    peerId: PeerId,
    messages: [EnqueueMessage]
) -> Signal<[MessageId?], NoError> {
    return ghostBaseResolveProtectedForwards(account: account, peerId: peerId, messages: messages)
    |> mapToSignal { protectedMessages -> Signal<[MessageId?], NoError> in
        guard let protectedMessages else {
            return account.jerkgramDeletedReplyLanguageCode()
            |> take(1)
            |> map { languageCode in
                account.stateManager.jerkgramDisplayPortableCopyFailure(text: ghostBaseProtectedCopyFailureText(languageCode: languageCode))
                return Array<MessageId?>(repeating: nil, count: messages.count)
            }
        }
        return ghostBaseResolveDeletedReplies(account: account, peerId: peerId, messages: protectedMessages)
        |> mapToSignal { resolvedMessages in
            return ghostBaseEnqueueResolvedMessages(account: account, peerId: peerId, messages: resolvedMessages)
        }
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
                        } else if let attribute = resentMessageRequestedAttribute(attribute, isSecretChat: peerId.namespace == Namespaces.Peer.SecretChat) {
                            filteredAttributes.append(attribute)
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
    
    var localGroupingKeyBySourceKey: [Int64: Int64] = [:]
    
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
            case let .forward(sourceId, threadId, grouping, forwardAttributes, _):
                if let sourceMessage = forwardedMessageToBeReuploaded(transaction: transaction, id: sourceId) {
                    var mediaReference: AnyMediaReference?
                    if sourceMessage.id.peerId.namespace == Namespaces.Peer.SecretChat {
                        if let media = sourceMessage.media.first {
                            mediaReference = .standalone(media: media)
                        }
                    }
                    var text = sourceMessage.text
                    var hidesCaption = false
                    if let media = mediaReference?.media, media is TelegramMediaImage || media is TelegramMediaFile, forwardAttributes.contains(where: { ($0 as? ForwardOptionsMessageAttribute)?.hideCaptions == true }) {
                        text = ""
                        hidesCaption = true
                    }
                    updatedMessages.append((transformedMedia, .message(text: text, attributes: forwardCopyRequestedAttributes(sourceAttributes: sourceMessage.attributes, forwardAttributes: forwardAttributes, hidesCaption: hidesCaption), inlineStickers: [:], mediaReference: mediaReference, threadId: threadId, replyToMessageId: threadId.flatMap { EngineMessageReplySubject(messageId: MessageId(peerId: peerId, namespace: Namespaces.Message.Cloud, id: Int32(clamping: $0)), quote: nil, innerSubject: nil) }, replyToStoryId: nil, localGroupingKey: forwardGroupingKey(grouping: grouping, sourceGroupingKey: sourceMessage.groupingKey, generatedKeys: &localGroupingKeyBySourceKey), correlationId: nil, bubbleUpEmojiOrStickersets: [])))
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
                    
                    attributes.append(contentsOf: outgoingMessageAttributes(requestedAttributes: requestedAttributes, isSecretChat: peer is TelegramSecretChat, peerAutoremoveTimeout: peerAutoremoveTimeout))

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
                        
                        var hidesCaption = false
                        if hideCaptions {
                            for media in sourceMessage.media {
                                if media is TelegramMediaImage || media is TelegramMediaFile {
                                    messageText = ""
                                    hidesCaption = true
                                    break
                                }
                            }
                        }
                        
                        if (sourceMessage.id.namespace == Namespaces.Message.Cloud || Namespaces.Message.allEphemeral.contains(sourceMessage.id.namespace)) && peerId.namespace != Namespaces.Peer.SecretChat {
                            attributes.append(ForwardSourceInfoAttribute(messageId: sourceMessage.id))
                        
                            if sourceMessage.id.namespace == Namespaces.Message.Cloud && peerId == account.peerId {
                                attributes.append(SourceReferenceMessageAttribute(messageId: sourceMessage.id))
                            }
                            
                            attributes.append(contentsOf: forwardedMessageAttributes(requestedAttributes: requestedAttributes, sourceAttributes: sourceMessage.attributes, forwardedMessageIds: forwardedMessageIds))

                            let ephemeralParams = ephemeralForwardParams(sourceMessage)
                            let ephemeralBotPeerId = ephemeralParams?.botPeerId
                            if sourceMessage.id.namespace == Namespaces.Message.EphemeralLocal {
                                attributes.removeAll(where: { $0 is InlineBotMessageAttribute })
                            } else if sourceMessage.id.namespace == Namespaces.Message.EphemeralAnchored, let inlineBotPeerId = ephemeralParams?.inlineBotPeerId, !attributes.contains(where: { $0 is InlineBotMessageAttribute }) {
                                attributes.append(InlineBotMessageAttribute(peerId: inlineBotPeerId, title: nil))
                            }
                            
                            var sourceReplyMarkup: ReplyMarkupMessageAttribute? = nil
                            var sourceSentViaBot = ephemeralBotPeerId != nil
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
                                
                            } else if sourceMessage.id.namespace == Namespaces.Message.EphemeralLocal {
                                forwardInfo = StoreMessageForwardInfo(authorId: ephemeralParams?.authorId ?? author.id, sourceId: nil, sourceMessageId: nil, date: sourceMessage.timestamp, authorSignature: nil, psaType: nil, flags: [])
                            } else if let sourceForwardInfo = sourceMessage.forwardInfo {
                                forwardInfo = StoreMessageForwardInfo(authorId: sourceForwardInfo.author?.id, sourceId: sourceForwardInfo.source?.id, sourceMessageId: sourceForwardInfo.sourceMessageId, date: sourceForwardInfo.date, authorSignature: sourceForwardInfo.authorSignature, psaType: nil, flags: [])
                            } else {
                                if sourceMessage.id.peerId != account.peerId {
                                    var sourceId = ephemeralParams?.sourceId
                                    var sourceMessageId = ephemeralParams?.sourceMessageId
                                    if ephemeralParams == nil, case let .channel(peer) = messageMainPeer(EngineMessage(sourceMessage)), case .broadcast = peer.info {
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

                                    let forwardAuthorId = ephemeralParams?.authorId ?? author.id
                                    forwardInfo = StoreMessageForwardInfo(authorId: forwardAuthorId, sourceId: sourceId, sourceMessageId: sourceMessageId, date: sourceMessage.timestamp, authorSignature: authorSignature, psaType: psaType, flags: [])
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
                            // A copy into a secret chat, whose own timer is already in `attributes`. The requested
                            // attributes are not necessarily the forward's own: a reply that quotes another chat's
                            // message becomes a forward carrying the reply's attributes.
                            attributes.append(contentsOf: filterMessageAttributesForOutgoingMessage(forwardCopyRequestedAttributes(sourceAttributes: sourceMessage.attributes, forwardAttributes: [], hidesCaption: hidesCaption)))
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
                        
                        let localGroupingKey = forwardGroupingKey(grouping: grouping, sourceGroupingKey: sourceMessage.groupingKey, generatedKeys: &localGroupingKeyBySourceKey)
                        
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
