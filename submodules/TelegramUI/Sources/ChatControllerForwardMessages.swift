import Foundation
import Postbox
import TelegramPresentationData
import AccountContext
import TelegramCore
import SwiftSignalKit
import Display
import TelegramPresentationData
import PresentationDataUtils
import TextFormat
import UndoUI
import ChatInterfaceState
import PremiumUI
import ReactionSelectionNode
import TopMessageReactions
import ChatMessagePaymentAlertController

// MARK: Jerkgram v1.2M BUILD124_PROTECTED_FORWARD_LOCAL_COPY1
// MARK: Jerkgram v1.2M BUILD124_PROTECTED_FORWARD_SOURCE_CHANNEL1
// MARK: Jerkgram v1.2R BUILD129_PROTECTED_CHAT_FORWARD1
private func jerkgramRequiresPortableForward(_ message: Message) -> Bool {
    if message.isCopyProtected() { return true }
    if let chatPeer = message.peers[message.id.peerId], chatPeer.isCopyProtectionEnabled { return true }
    if let sourcePeer = message.forwardInfo?.author ?? message.effectiveAuthor { return sourcePeer.isCopyProtectionEnabled }
    return false
}

private func jerkgramPortableForwardBaseMessage(
    _ message: Message,
    hideAuthor: Bool,
    threadId: Int64?,
    mediaReference: AnyMediaReference?
) -> EnqueueMessage {
    var text = message.text
    var entities = message.textEntitiesAttribute?.entities ?? []

    // Telegram's own forwarding UI resolves attribution from forwardInfo first
    // and then effectiveAuthor. For channel-authored posts the chat peer itself
    // is not necessarily the author we need to reproduce.
    if !hideAuthor, let author = message.forwardInfo?.author ?? message.effectiveAuthor ?? message.peers[message.id.peerId] {
        let sourcePeer = EnginePeer(author)
        let title = sourcePeer.compactDisplayTitle
        if !title.isEmpty {
            let prefix = text.isEmpty ? "" : "\n\n"
            let start = (text as NSString).length + (prefix as NSString).length
            text += prefix + "— " + title
            let titleStart = start + 2
            let titleEnd = titleStart + (title as NSString).length
            if let username = sourcePeer.addressName, !username.isEmpty {
                entities.append(MessageTextEntity(
                    range: titleStart ..< titleEnd,
                    type: .TextUrl(url: "https://t.me/\(username)")
                ))
            }
            entities.append(MessageTextEntity(range: titleStart ..< titleEnd, type: .Bold))
        }
    }

    var attributes: [MessageAttribute] = []
    if !entities.isEmpty {
        attributes.append(TextEntitiesMessageAttribute(entities: entities))
    }
    let embeddedFiles = (
        message.attributes.first(where: { $0 is EmbeddedMediaStickersMessageAttribute })
        as? EmbeddedMediaStickersMessageAttribute
    )?.files ?? []
    var inlineStickers: [MediaId: Media] = [:]
    for file in embeddedFiles {
        inlineStickers[file.fileId] = file
    }

    return .message(
        text: text,
        attributes: attributes,
        inlineStickers: inlineStickers,
        mediaReference: mediaReference,
        threadId: threadId,
        replyToMessageId: nil,
        replyToStoryId: nil,
        localGroupingKey: message.groupingKey,
        correlationId: nil,
        bubbleUpEmojiOrStickersets: []
    )
}

private func jerkgramProtectedResourceData(
    context: AccountContext,
    message: Message,
    mediaReference: AnyMediaReference,
    resource: TelegramMediaResource,
    userContentType: MediaResourceUserContentType,
    pathExtension: String?
) -> Signal<EngineMediaResource.ResourceData, NoError> {
    // Use the same public EngineResources fetch/data pair as Official Telegram's
    // SaveToCameraRoll path. The cloud reference stays alive only while fetching;
    // the outgoing message is created after a completed local path exists.
    // MARK: Jerkgram v1.2N BUILD125_PROTECTED_FORWARD_CACHE_FIRST1
    // A viewed private/protected post is normally already in MediaBox. Reuse
    // that completed local file before attempting a server fetch: the latter
    // is rejected for no-forward channels and led to the red failure state.
    return context.engine.resources.data(
        resource: EngineMediaResource(resource),
        pathExtension: pathExtension,
        waitUntilFetchStatus: false
    )
    |> take(1)
    |> mapToSignal { cachedData -> Signal<EngineMediaResource.ResourceData, NoError> in
        if cachedData.isComplete {
            return .single(cachedData)
        }
        return Signal { subscriber in
            let fetchDisposable = context.engine.resources.fetch(
                reference: mediaReference.resourceReference(resource),
                userLocation: .peer(message.id.peerId),
                userContentType: userContentType
            ).start()
            let dataDisposable = context.engine.resources.data(
                resource: EngineMediaResource(resource),
                pathExtension: pathExtension,
                waitUntilFetchStatus: true
            ).start(next: { data in
                if data.isComplete {
                    subscriber.putNext(data)
                    subscriber.putCompletion()
                }
            }, completed: {
                subscriber.putCompletion()
            })
            return ActionDisposable {
                fetchDisposable.dispose()
                dataDisposable.dispose()
            }
        }
        |> take(1)
    }
}

private func jerkgramPortableForwardMessage(
    _ message: Message,
    hideAuthor: Bool,
    threadId: Int64?,
    context: AccountContext
) -> Signal<EnqueueMessage, NoError> {
    guard jerkgramRequiresPortableForward(message), let media = message.media.first else {
        let reference = message.media.first.map { AnyMediaReference.standalone(media: $0) }
        return .single(jerkgramPortableForwardBaseMessage(
            message,
            hideAuthor: hideAuthor,
            threadId: threadId,
            mediaReference: reference
        ))
    }

    if let file = media as? TelegramMediaFile {
        let sourceReference = AnyMediaReference.message(
            message: MessageReference(message),
            media: file
        )
        let pathExtension: String?
        if let fileName = file.fileName {
            let ext = (fileName as NSString).pathExtension
            pathExtension = ext.isEmpty ? nil : ext
        } else {
            pathExtension = nil
        }
        return jerkgramProtectedResourceData(
            context: context,
            message: message,
            mediaReference: sourceReference,
            resource: file.resource,
            userContentType: MediaResourceUserContentType(file: file),
            pathExtension: pathExtension
        )
        |> map { data -> EnqueueMessage in
            let localId = Int64.random(in: Int64.min ... Int64.max)
            let localResource = LocalFileReferenceMediaResource(
                localFilePath: data.path,
                randomId: localId
            )
            // Do not retain protected cloud thumbnail/alternative resources in
            // the outgoing file. Dimensions/duration/voice/video semantics live
            // in attributes and are preserved; Telegram regenerates upload media.
            let localFile = TelegramMediaFile(
                fileId: MediaId(namespace: Namespaces.Media.LocalFile, id: localId),
                partialReference: nil,
                resource: localResource,
                previewRepresentations: [],
                videoThumbnails: [],
                videoCover: nil,
                immediateThumbnailData: file.immediateThumbnailData,
                mimeType: file.mimeType,
                size: file.size,
                attributes: file.attributes,
                alternativeRepresentations: []
            )
            return jerkgramPortableForwardBaseMessage(
                message,
                hideAuthor: hideAuthor,
                threadId: threadId,
                mediaReference: .standalone(media: localFile)
            )
        }
    } else if let image = media as? TelegramMediaImage,
              let representation = largestImageRepresentation(image.representations) {
        let sourceReference = AnyMediaReference.message(
            message: MessageReference(message),
            media: image
        )
        return jerkgramProtectedResourceData(
            context: context,
            message: message,
            mediaReference: sourceReference,
            resource: representation.resource,
            userContentType: .image,
            pathExtension: "jpg"
        )
        |> map { data -> EnqueueMessage in
            let localId = Int64.random(in: Int64.min ... Int64.max)
            let localResource = LocalFileReferenceMediaResource(
                localFilePath: data.path,
                randomId: localId
            )
            let localRepresentation = TelegramMediaImageRepresentation(
                dimensions: representation.dimensions,
                resource: localResource,
                progressiveSizes: [],
                immediateThumbnailData: nil,
                hasVideo: false,
                isPersonal: false
            )
            let localImage = TelegramMediaImage(
                imageId: MediaId(namespace: Namespaces.Media.LocalImage, id: localId),
                representations: [localRepresentation],
                immediateThumbnailData: image.immediateThumbnailData,
                reference: nil,
                partialReference: nil,
                flags: image.flags
            )
            return jerkgramPortableForwardBaseMessage(
                message,
                hideAuthor: hideAuthor,
                threadId: threadId,
                mediaReference: .standalone(media: localImage)
            )
        }
    } else {
        // The red-failure regression is the protected upload-media path. Keep
        // existing portable semantics for non-upload message media.
        return .single(jerkgramPortableForwardBaseMessage(
            message,
            hideAuthor: hideAuthor,
            threadId: threadId,
            mediaReference: .standalone(media: media)
        ))
    }
}


extension ChatControllerImpl {
    func forwardMessages(messageIds: [EngineMessage.Id], options: ChatInterfaceForwardOptionsState? = nil, resetCurrent: Bool = false) {
        let _ = (self.context.engine.data.get(EngineDataMap(
            messageIds.map(TelegramEngine.EngineData.Item.Messages.Message.init)
        ))
        |> deliverOnMainQueue).startStandalone(next: { [weak self] messages in
            let sortedMessages = messages.values.compactMap { $0?._asMessage() }.sorted { lhs, rhs in
                return lhs.id < rhs.id
            }
            self?.forwardMessages(messages: sortedMessages, options: options, resetCurrent: resetCurrent)
        })
    }

    func forwardMessages(messages: [EngineRawMessage], options: ChatInterfaceForwardOptionsState? = nil, resetCurrent: Bool) {
        let _ = self.presentVoiceMessageDiscardAlert(action: {
            var filter: ChatListNodePeersFilter = [.onlyWriteable, .excludeDisabled, .doNotSearchMessages]
            var hasPublicPolls = false
            var hasPublicQuiz = false
            var hasTodo = false
            for message in messages {
                for media in message.media {
                    if let poll = media as? TelegramMediaPoll, case .public = poll.publicity {
                        hasPublicPolls = true
                        if case .quiz = poll.kind {
                            hasPublicQuiz = true
                        }
                        filter.insert(.excludeChannels)
                    } else if let _ = media as? TelegramMediaTodo {
                        hasTodo = true
                        filter.insert(.excludeChannels)
                    } else if let _ = media as? TelegramMediaPaidContent {
                        filter.insert(.excludeSecretChats)
                    }
                }
            }
            var attemptSelectionImpl: ((EnginePeer, ChatListDisabledPeerReason) -> Void)?
            let controller = self.context.sharedContext.makePeerSelectionController(PeerSelectionControllerParams(context: self.context, updatedPresentationData: self.updatedPresentationData, filter: filter, hasFilters: true, attemptSelection: { peer, _, reason in
                attemptSelectionImpl?(peer, reason)
            }, multipleSelection: true, forwardedMessageIds: messages.map { $0.id }, selectForumThreads: true))
            let context = self.context
            attemptSelectionImpl = { [weak self, weak controller] peer, reason in
                guard let strongSelf = self, let controller = controller else {
                    return
                }
                let presentationData = context.sharedContext.currentPresentationData.with { $0 }
                if hasPublicPolls {
                    if case let .channel(channel) = peer, case .broadcast = channel.info {
                        controller.present(textAlertController(context: context, title: nil, text: hasPublicQuiz ? presentationData.strings.Forward_ErrorPublicQuizDisabledInChannels : presentationData.strings.Forward_ErrorPublicPollDisabledInChannels, actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})]), in: .window(.root))
                        return
                    }
                } else if hasTodo {
                    if case let .channel(channel) = peer, case .broadcast = channel.info {
                        controller.present(textAlertController(context: context, title: nil, text: presentationData.strings.Forward_ErrorTodoDisabledInChannels, actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})]), in: .window(.root))
                        return
                    }
                }
                switch reason {
                case .generic:
                    controller.present(textAlertController(context: context, updatedPresentationData: strongSelf.updatedPresentationData, title: nil, text: presentationData.strings.Forward_ErrorDisabledForChat, actions: [TextAlertAction(type: .defaultAction, title: presentationData.strings.Common_OK, action: {})]), in: .window(.root))
                case .premiumRequired:
                    controller.forEachController { c in
                        if let c = c as? UndoOverlayController {
                            c.dismiss()
                        }
                        return true
                    }
                    
                    var hasAction = false
                    let premiumConfiguration = PremiumConfiguration.with(appConfiguration: strongSelf.context.currentAppConfiguration.with { $0 })
                    if !premiumConfiguration.isPremiumDisabled {
                        hasAction = true
                    }
                    
                    controller.present(UndoOverlayController(presentationData: presentationData, content: .premiumPaywall(title: nil, text: presentationData.strings.Chat_ToastMessagingRestrictedToPremium_Text(peer.compactDisplayTitle).string, customUndoText: hasAction ? presentationData.strings.Chat_ToastMessagingRestrictedToPremium_Action : nil, timeout: nil, linkAction: { _ in
                    }), elevatedLayout: false, animateInAsReplacement: true, action: { [weak controller] action in
                        guard let self, let controller else {
                            return false
                        }
                        if case .undo = action {
                            let premiumController = PremiumIntroScreen(context: self.context, source: .settings)
                            controller.push(premiumController)
                        }
                        return false
                    }), in: .current)
                }
            }
            controller.multiplePeersSelected = { [weak self, weak controller] peers, peerMap, messageText, mode, forwardOptions, _ in
                let peerIds = peers.map { $0.id }
                
                let _ = (context.engine.data.get(
                    EngineDataMap(
                        peerIds.map(TelegramEngine.EngineData.Item.Peer.SendPaidMessageStars.init(id:))
                    ),
                    EngineDataList(
                        peerIds.map(TelegramEngine.EngineData.Item.Peer.RenderedPeer.init(id:))
                    )
                )
                |> deliverOnMainQueue).start(next: { [weak self, weak controller] sendPaidMessageStars, renderedPeers in
                    guard let strongSelf = self else {
                        return
                    }
                    let renderedPeers = renderedPeers.compactMap({ $0 })
                    
                    var count: Int32 = Int32(messages.count)
                    if messageText.string.count > 0 {
                        count += 1
                    }
                    var totalAmount: StarsAmount = .zero
                    var chargingPeers: [EngineRenderedPeer] = []
                    for peer in renderedPeers {
                        if let maybeAmount = sendPaidMessageStars[peer.peerId], let amount = maybeAmount {
                            totalAmount = totalAmount + amount
                            chargingPeers.append(peer)
                        }
                    }
                                        
                    let proceed = { [weak self, weak controller] in
                        guard let strongSelf = self, let strongController = controller else {
                            return
                        }
                        
                        strongController.dismiss()
                        
                        var result: [EnqueueMessage] = []
                        var jerkgramPortableMessagesSignal: Signal<[EnqueueMessage], NoError>?
                        if messageText.string.count > 0 {
                            let inputText = convertMarkdownToAttributes(messageText)
                            for text in breakChatInputText(trimChatInputText(inputText)) {
                                if text.length != 0 {
                                    var attributes: [EngineMessage.Attribute] = []
                                    let entities = generateTextEntities(text.string, enabledTypes: .all, currentEntities: generateChatInputTextEntities(text))
                                    if !entities.isEmpty {
                                        attributes.append(TextEntitiesMessageAttribute(entities: entities))
                                    }
                                    result.append(.message(text: text.string, attributes: attributes, inlineStickers: [:], mediaReference: nil, threadId: strongSelf.chatLocation.threadId, replyToMessageId: nil, replyToStoryId: nil, localGroupingKey: nil, correlationId: nil, bubbleUpEmojiOrStickersets: []))
                                }
                            }
                        }
                        
                        var attributes: [EngineMessage.Attribute] = []
                        attributes.append(
                            ForwardOptionsMessageAttribute(
                                hideNames:
                                    forwardOptions?.hideNames == true
                                    || options?.hideNames == true,
                                hideCaptions:
                                    forwardOptions?.hideCaptions == true
                                    || options?.hideCaptions == true
                            )
                        )
                        
                        let hideAuthor = forwardOptions?.hideNames == true || options?.hideNames == true
                        let canUsePortableCopy = messages.allSatisfy { message in
                            message.id.peerId.namespace != Namespaces.Peer.SecretChat
                            && !message.media.contains(where: {
                                $0 is TelegramMediaPaidContent
                                || $0 is TelegramMediaAction
                                || $0 is TelegramMediaExpiredContent
                            })
                        }
                        if canUsePortableCopy && (hideAuthor || messages.contains(where: { jerkgramRequiresPortableForward($0) })) {
                            let jerkgramPrefixMessages = result
                            jerkgramPortableMessagesSignal = combineLatest(messages.map { message in
                                jerkgramPortableForwardMessage(
                                    message,
                                    hideAuthor: hideAuthor,
                                    threadId: strongSelf.chatLocation.threadId,
                                    context: strongSelf.context
                                )
                            })
                            |> map { portableMessages in
                                jerkgramPrefixMessages + portableMessages
                            }
                        } else {
                            result.append(contentsOf: messages.map { message -> EnqueueMessage in
                                return .forward(source: message.id, threadId: nil, grouping: .auto, attributes: attributes, correlationId: nil)
                            })
                        }
                        
                        let commit: ([EnqueueMessage]) -> Void = { result in
                            guard let strongSelf = self else {
                                return
                            }
                            var result = result
                            
                            strongSelf.updateChatPresentationInterfaceState(animated: false, interactive: true, { $0.updatedInterfaceState({ $0.withoutSelectionState() }).updatedSearch(nil) })
                            
                            var correlationIds: [Int64] = []
                            for i in 0 ..< result.count {
                                let correlationId = Int64.random(in: Int64.min ... Int64.max)
                                correlationIds.append(correlationId)
                                result[i] = result[i].withUpdatedCorrelationId(correlationId)
                            }
                            
                            let targetPeersShouldDivertSignals: [Signal<(EnginePeer, Bool), NoError>] = peers.map { peer -> Signal<(EnginePeer, Bool), NoError> in
                                return strongSelf.shouldDivertMessagesToScheduled(targetPeer: peer, messages: result)
                                |> map { shouldDivert -> (EnginePeer, Bool) in
                                    return (peer, shouldDivert)
                                }
                            }
                            let targetPeersShouldDivert: Signal<[(EnginePeer, Bool)], NoError> = combineLatest(targetPeersShouldDivertSignals)
                            let _ = (targetPeersShouldDivert
                            |> deliverOnMainQueue).startStandalone(next: { targetPeersShouldDivert in
                                guard let strongSelf = self else {
                                    return
                                }
                                
                                var displayConvertingTooltip = false
                                
                                var displayPeers: [EnginePeer] = []
                                for (peer, shouldDivert) in targetPeersShouldDivert {
                                    var peerMessages = result
                                    if shouldDivert {
                                        displayConvertingTooltip = true
                                        peerMessages = peerMessages.map { message -> EnqueueMessage in
                                            return message.withUpdatedAttributes { attributes in
                                                var attributes = attributes
                                                attributes.removeAll(where: { $0 is OutgoingScheduleInfoMessageAttribute })
                                                attributes.append(OutgoingScheduleInfoMessageAttribute(scheduleTime: Int32(Date().timeIntervalSince1970) + 10 * 24 * 60 * 60, repeatPeriod: nil))
                                                return attributes
                                            }
                                        }
                                    }
                                    
                                    // MARK: GhostBase v1.0P+SH1 Share Scheduled Send
                                    let ghostBaseSH1ScheduledSendEnabled = ((UserDefaults.standard.object(forKey: "jerkgram.GhostMode.ScheduledSend") as? Bool) ?? false)
                                    if ghostBaseSH1ScheduledSendEnabled && !shouldDivert {
                                        let ghostBaseSH1ScheduleTime = Int32(Date().timeIntervalSince1970) + 12
                                        peerMessages = peerMessages.map { message -> EnqueueMessage in
                                            return message.withUpdatedAttributes { attributes in
                                                var attributes = attributes
                                                if !attributes.contains(where: { $0 is OutgoingScheduleInfoMessageAttribute }) {
                                                    attributes.append(OutgoingScheduleInfoMessageAttribute(scheduleTime: ghostBaseSH1ScheduleTime, repeatPeriod: nil))
                                                }
                                                return attributes
                                            }
                                        }
                                        UserDefaults.standard.set(UserDefaults.standard.integer(forKey: "jerkgram.SH1.ShareScheduledIntercept.Count") + 1, forKey: "jerkgram.SH1.ShareScheduledIntercept.Count")
                                        UserDefaults.standard.set("\(peer.id)", forKey: "jerkgram.SH1.LastSharePeerId")
                                        UserDefaults.standard.set(peerMessages.count, forKey: "jerkgram.SH1.LastShareMessageCount")
                                        UserDefaults.standard.set(Int(ghostBaseSH1ScheduleTime), forKey: "jerkgram.SH1.LastShareScheduleTime")
                                    }

                                    if let maybeAmount = sendPaidMessageStars[peer.id], let amount = maybeAmount {
                                        peerMessages = peerMessages.map { message -> EnqueueMessage in
                                            return message.withUpdatedAttributes { attributes in
                                                var attributes = attributes
                                                attributes.append(PaidStarsMessageAttribute(stars: amount, postponeSending: false))
                                                return attributes
                                            }
                                        }
                                    }
                                    
                                    let _ = (enqueueMessages(account: strongSelf.context.account, peerId: peer.id, messages: peerMessages)
                                    |> deliverOnMainQueue).startStandalone(next: { messageIds in
                                        if let strongSelf = self {
                                            let signals: [Signal<Bool, NoError>] = messageIds.compactMap({ id -> Signal<Bool, NoError>? in
                                                guard let id = id else {
                                                    return nil
                                                }
                                                return strongSelf.context.account.pendingMessageManager.pendingMessageStatus(id)
                                                |> mapToSignal { status, _ -> Signal<Bool, NoError> in
                                                    if status != nil {
                                                        return .never()
                                                    } else {
                                                        return .single(true)
                                                    }
                                                }
                                                |> take(1)
                                            })
                                            if strongSelf.shareStatusDisposable == nil {
                                                strongSelf.shareStatusDisposable = MetaDisposable()
                                            }
                                            strongSelf.shareStatusDisposable?.set((combineLatest(signals)
                                            |> deliverOnMainQueue).startStrict())
                                        }
                                    })
                                    
                                    if case let .secretChat(secretPeer) = peer {
                                        if let peer = peerMap[secretPeer.regularPeerId] {
                                            displayPeers.append(peer)
                                        }
                                    } else {
                                        displayPeers.append(peer)
                                    }
                                }
                                
                                let presentationData = strongSelf.context.sharedContext.currentPresentationData.with { $0 }
                                let text: String
                                var savedMessages = false
                                if displayPeers.count == 1, let peerId = displayPeers.first?.id, peerId == strongSelf.context.account.peerId {
                                    text = messages.count == 1 ? presentationData.strings.Conversation_ForwardTooltip_SavedMessages_One : presentationData.strings.Conversation_ForwardTooltip_SavedMessages_Many
                                    savedMessages = true
                                } else {
                                    if displayPeers.count == 1, let peer = displayPeers.first {
                                        var peerName = peer.id == strongSelf.context.account.peerId ? presentationData.strings.DialogList_SavedMessages : peer.displayTitle(strings: presentationData.strings, displayOrder: presentationData.nameDisplayOrder)
                                        peerName = peerName.replacingOccurrences(of: "**", with: "")
                                        text = messages.count == 1 ? presentationData.strings.Conversation_ForwardTooltip_Chat_One(peerName).string : presentationData.strings.Conversation_ForwardTooltip_Chat_Many(peerName).string
                                    } else if displayPeers.count == 2, let firstPeer = displayPeers.first, let secondPeer = displayPeers.last {
                                        var firstPeerName = firstPeer.id == strongSelf.context.account.peerId ? presentationData.strings.DialogList_SavedMessages : firstPeer.displayTitle(strings: presentationData.strings, displayOrder: presentationData.nameDisplayOrder)
                                        firstPeerName = firstPeerName.replacingOccurrences(of: "**", with: "")
                                        var secondPeerName = secondPeer.id == strongSelf.context.account.peerId ? presentationData.strings.DialogList_SavedMessages : secondPeer.displayTitle(strings: presentationData.strings, displayOrder: presentationData.nameDisplayOrder)
                                        secondPeerName = secondPeerName.replacingOccurrences(of: "**", with: "")
                                        text = messages.count == 1 ? presentationData.strings.Conversation_ForwardTooltip_TwoChats_One(firstPeerName, secondPeerName).string : presentationData.strings.Conversation_ForwardTooltip_TwoChats_Many(firstPeerName, secondPeerName).string
                                    } else if let peer = displayPeers.first {
                                        var peerName = peer.displayTitle(strings: presentationData.strings, displayOrder: presentationData.nameDisplayOrder)
                                        peerName = peerName.replacingOccurrences(of: "**", with: "")
                                        text = messages.count == 1 ? presentationData.strings.Conversation_ForwardTooltip_ManyChats_One(peerName, "\(displayPeers.count - 1)").string : presentationData.strings.Conversation_ForwardTooltip_ManyChats_Many(peerName, "\(displayPeers.count - 1)").string
                                    } else {
                                        text = ""
                                    }
                                }
                                
                                let reactionItems: Signal<[ReactionItem], NoError>
                                if savedMessages && messages.count > 0 {
                                    reactionItems = tagMessageReactions(context: strongSelf.context, subPeerId: nil)
                                } else {
                                    reactionItems = .single([])
                                }
                                
                                let _ = (reactionItems
                                |> deliverOnMainQueue).startStandalone(next: { [weak strongSelf] reactionItems in
                                    guard let strongSelf else {
                                        return
                                    }
                                    
                                    strongSelf.present(UndoOverlayController(presentationData: presentationData, content: .forward(savedMessages: savedMessages, text: text), elevatedLayout: false, position: savedMessages && messages.count > 0 ? .top : .bottom, animateInAsReplacement: true, action: { action in
                                        if savedMessages, let self, action == .info {
                                            let _ = (self.context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: self.context.account.peerId))
                                                     |> deliverOnMainQueue).start(next: { [weak self] peer in
                                                guard let self, let peer else {
                                                    return
                                                }
                                                guard let navigationController = self.navigationController as? NavigationController else {
                                                    return
                                                }
                                                self.context.sharedContext.navigateToChatController(NavigateToChatControllerParams(navigationController: navigationController, context: self.context, chatLocation: .peer(peer), forceOpenChat: true))
                                            })
                                        }
                                        return false
                                    }, additionalView: (savedMessages && messages.count > 0) ? chatShareToSavedMessagesAdditionalView(strongSelf, reactionItems: reactionItems, correlationIds: correlationIds) : nil), in: .current)
                                })
                                
                                if displayConvertingTooltip {
                                }
                            })
                        }
                        
                        let commitResolved: ([EnqueueMessage]) -> Void = { resolvedResult in
                            switch mode {
                            case .generic:
                                commit(resolvedResult)
                            case .silent:
                                let transformedMessages = strongSelf.transformEnqueueMessages(resolvedResult, silentPosting: true)
                                commit(transformedMessages)
                            case .schedule:
                                strongSelf.presentScheduleTimePicker(completion: { [weak self] timeResult in
                                    if let strongSelf = self {
                                        let transformedMessages = strongSelf.transformEnqueueMessages(resolvedResult, silentPosting: timeResult.silentPosting, scheduleTime: timeResult.time, repeatPeriod: timeResult.repeatPeriod)
                                        commit(transformedMessages)
                                    }
                                })
                            case .whenOnline:
                                let transformedMessages = strongSelf.transformEnqueueMessages(resolvedResult, silentPosting: strongSelf.presentationInterfaceState.interfaceState.silentPosting, scheduleTime: scheduleWhenOnlineTimestamp)
                                commit(transformedMessages)
                            }
                        }
                        if let jerkgramPortableMessagesSignal {
                            let _ = (jerkgramPortableMessagesSignal
                            |> deliverOnMainQueue).startStandalone(next: { resolvedMessages in
                                commitResolved(resolvedMessages)
                            })
                        } else {
                            commitResolved(result)
                        }
                    }
                    
                    if totalAmount.value > 0 {
                        let controller = chatMessagePaymentAlertController(
                            context: nil,
                            presentationData: strongSelf.presentationData,
                            updatedPresentationData: nil,
                            peers: chargingPeers,
                            count: count,
                            amount: totalAmount,
                            totalAmount: totalAmount,
                            hasCheck: false,
                            navigationController: strongSelf.navigationController as? NavigationController,
                            completion: { _ in
                                proceed()
                            }
                        )
                        strongSelf.present(controller, in: .window(.root))
                    } else {
                        proceed()
                    }
                })
            }
            controller.peerSelected = { [weak self, weak controller] peer, threadId in
                guard let strongSelf = self, let strongController = controller else {
                    return
                }
                let peerId = peer.id
                let accountPeerId = strongSelf.context.account.peerId
                
                if resetCurrent {
                    strongSelf.updateChatPresentationInterfaceState(animated: false, interactive: true, { $0.updatedInterfaceState({ $0.withUpdatedForwardMessageIds(nil).withUpdatedForwardOptionsState(nil) }) })
                }
                
                var isPinnedMessages = false
                if case .pinnedMessages = strongSelf.presentationInterfaceState.subject {
                    isPinnedMessages = true
                }
                
                var hasNotOwnMessages = false
                for message in messages {
                    if message.id.peerId == accountPeerId && message.forwardInfo == nil {
                    } else {
                        hasNotOwnMessages = true
                    }
                }
                
                if case .peer(peerId) = strongSelf.chatLocation, strongSelf.parentController == nil, !isPinnedMessages {
                    strongSelf.updateChatPresentationInterfaceState(animated: false, interactive: true, { $0.updatedInterfaceState({ $0.withUpdatedForwardMessageIds(messages.map { $0.id }).withUpdatedForwardOptionsState(ChatInterfaceForwardOptionsState(hideNames: !hasNotOwnMessages || (options?.hideNames ?? false) , hideCaptions: false, unhideNamesOnCaptionChange: false)).withoutSelectionState() }).updatedSearch(nil) })
                    strongSelf.updateItemNodesSearchTextHighlightStates()
                    strongSelf.searchResultsController = nil
                    strongController.dismiss()
                } else if peerId == strongSelf.context.account.peerId {
                    Queue.mainQueue().after(0.88) {
                        strongSelf.chatDisplayNode.hapticFeedback.success()
                    }
                    
                    let reactionItems: Signal<[ReactionItem], NoError>
                    if messages.count > 0 {
                        reactionItems = tagMessageReactions(context: strongSelf.context, subPeerId: nil)
                    } else {
                        reactionItems = .single([])
                    }
                    
                    var correlationIds: [Int64] = []
                    let mappedMessages = messages.map { message -> EnqueueMessage in
                        let correlationId = Int64.random(in: Int64.min ... Int64.max)
                        correlationIds.append(correlationId)
                        return .forward(
                            source: message.id,
                            threadId: nil,
                            grouping: .auto,
                            attributes: (
                                options?.hideNames == true
                            )
                            ? [
                                ForwardOptionsMessageAttribute(
                                    hideNames: true,
                                    hideCaptions:
                                        options?.hideCaptions == true
                                )
                            ]
                            : [],
                            correlationId: correlationId
                        )
                    }
                    
                    let _ = (reactionItems
                    |> deliverOnMainQueue).startStandalone(next: { [weak strongSelf] reactionItems in
                        guard let strongSelf else {
                            return
                        }
                        
                        let presentationData = strongSelf.context.sharedContext.currentPresentationData.with { $0 }
                        strongSelf.present(UndoOverlayController(presentationData: presentationData, content: .forward(savedMessages: true, text: messages.count == 1 ? presentationData.strings.Conversation_ForwardTooltip_SavedMessages_One : presentationData.strings.Conversation_ForwardTooltip_SavedMessages_Many), elevatedLayout: false, position: .top, animateInAsReplacement: true, action: { [weak self] value in
                            if case .info = value, let strongSelf = self {
                                let _ = (strongSelf.context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: strongSelf.context.account.peerId))
                                |> deliverOnMainQueue).startStandalone(next: { peer in
                                    guard let strongSelf = self, let peer = peer, let navigationController = strongSelf.effectiveNavigationController else {
                                        return
                                    }
                                    
                                    strongSelf.context.sharedContext.navigateToChatController(NavigateToChatControllerParams(navigationController: navigationController, context: strongSelf.context, chatLocation: .peer(peer), keepStack: .always, purposefulAction: {}, peekData: nil, forceOpenChat: true))
                                })
                                return true
                            }
                            return false
                        }, additionalView: messages.count > 0 ? chatShareToSavedMessagesAdditionalView(strongSelf, reactionItems: reactionItems, correlationIds: correlationIds) : nil), in: .current)
                    })
                    
                    let _ = (enqueueMessages(account: strongSelf.context.account, peerId: peerId, messages: mappedMessages)
                    |> deliverOnMainQueue).startStandalone(next: { messageIds in
                        if let strongSelf = self {
                            let signals: [Signal<Bool, NoError>] = messageIds.compactMap({ id -> Signal<Bool, NoError>? in
                                guard let id = id else {
                                    return nil
                                }
                                return strongSelf.context.account.pendingMessageManager.pendingMessageStatus(id)
                                |> mapToSignal { status, _ -> Signal<Bool, NoError> in
                                    if status != nil {
                                        return .never()
                                    } else {
                                        return .single(true)
                                    }
                                }
                                |> take(1)
                            })
                            if strongSelf.shareStatusDisposable == nil {
                                strongSelf.shareStatusDisposable = MetaDisposable()
                            }
                            strongSelf.shareStatusDisposable?.set((combineLatest(signals)
                            |> deliverOnMainQueue).startStrict())
                        }
                    })
                    strongSelf.updateChatPresentationInterfaceState(animated: false, interactive: true, { $0.updatedInterfaceState({ $0.withoutSelectionState() }) })
                    strongController.dismiss()
                } else {
                    if let navigationController = strongSelf.navigationController as? NavigationController {
                        for controller in navigationController.viewControllers {
                            if let maybeChat = controller as? ChatControllerImpl {
                                if case .peer(peerId) = maybeChat.chatLocation {
                                    var isChatPinnedMessages = false
                                    if case .pinnedMessages = maybeChat.presentationInterfaceState.subject {
                                        isChatPinnedMessages = true
                                    }
                                    if !isChatPinnedMessages {
                                        maybeChat.updateChatPresentationInterfaceState(
                                            animated: false,
                                            interactive: true,
                                            {
                                                $0.updatedInterfaceState {
                                                    $0.withUpdatedForwardMessageIds(
                                                        messages.map { $0.id }
                                                    )
                                                    .withUpdatedForwardOptionsState(
                                                        ChatInterfaceForwardOptionsState(
                                                            hideNames:
                                                                !hasNotOwnMessages
                                                                || (options?.hideNames ?? false),
                                                            hideCaptions:
                                                                options?.hideCaptions
                                                                ?? false,
                                                            unhideNamesOnCaptionChange:
                                                                false
                                                        )
                                                    )
                                                    .withoutSelectionState()
                                                }
                                            }
                                        )
                                        strongSelf.dismiss()
                                        strongController.dismiss()
                                        return
                                    }
                                }
                            }
                        }
                    }

                    let _ = (ChatInterfaceState.update(engine: strongSelf.context.engine, peerId: peerId, threadId: threadId, { currentState in
                        return currentState.withUpdatedForwardMessageIds(messages.map { $0.id }).withUpdatedForwardOptionsState(ChatInterfaceForwardOptionsState(hideNames: !hasNotOwnMessages || (options?.hideNames ?? false) , hideCaptions: false, unhideNamesOnCaptionChange: false))
                    })
                    |> deliverOnMainQueue).startStandalone(completed: {
                        if let strongSelf = self {
                            let proceed: (ChatController) -> Void = { chatController in
                                strongSelf.updateChatPresentationInterfaceState(animated: false, interactive: true, { $0.updatedInterfaceState({ $0.withoutSelectionState() }) })
                                
                                let navigationController: NavigationController?
                                if let parentController = strongSelf.parentController {
                                    navigationController = (parentController.navigationController as? NavigationController)
                                } else {
                                    navigationController = strongSelf.effectiveNavigationController
                                }
                                
                                if let navigationController = navigationController {
                                    var viewControllers = navigationController.viewControllers
                                    if threadId != nil {
                                        viewControllers.insert(chatController, at: viewControllers.count - 2)
                                    } else {
                                        viewControllers.insert(chatController, at: viewControllers.count - 1)
                                    }
                                    navigationController.setViewControllers(viewControllers, animated: false)
                                    
                                    strongSelf.controllerNavigationDisposable.set((chatController.ready.get()
                                    |> SwiftSignalKit.filter { $0 }
                                    |> take(1)
                                    |> deliverOnMainQueue).startStrict(next: { [weak navigationController] _ in
                                        viewControllers.removeAll(where: { $0 is PeerSelectionController })
                                        navigationController?.setViewControllers(viewControllers, animated: true)
                                    }))
                                }
                            }
                            if let threadId = threadId {
                                let _ = (strongSelf.context.sharedContext.chatControllerForForumThread(context: strongSelf.context, peerId: peerId, threadId: threadId)
                                |> deliverOnMainQueue).startStandalone(next: { chatController in
                                    proceed(chatController)
                                })
                            } else {
                                proceed(ChatControllerImpl(context: strongSelf.context, chatLocation: .peer(id: peerId)))
                            }
                        }
                    })
                }
            }
            self.chatDisplayNode.dismissInput()
            self.effectiveNavigationController?.pushViewController(controller)
        })
    }
}
