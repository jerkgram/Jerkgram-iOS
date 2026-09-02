import Foundation
import Postbox
import TelegramApi
import SwiftSignalKit

func _internal_markMessageContentAsConsumedInteractively(postbox: Postbox, messageId: MessageId) -> Signal<Void, NoError> {
    return postbox.transaction { transaction -> Void in
        if let message = transaction.getMessage(messageId), message.flags.contains(.Incoming) {
            var updateMessage = false
            var updatedAttributes = message.attributes

            for i in 0 ..< updatedAttributes.count {
                if let attribute = updatedAttributes[i] as? ConsumableContentMessageAttribute {
                    if !attribute.consumed {
                        updatedAttributes[i] = ConsumableContentMessageAttribute(consumed: true)
                        updateMessage = true

                        if message.id.peerId.namespace == Namespaces.Peer.SecretChat {
                            if let state = transaction.getPeerChatState(message.id.peerId) as? SecretChatState {
                                var layer: SecretChatLayer?
                                switch state.embeddedState {
                                    case .terminated, .handshake:
                                        break
                                    case .basicLayer:
                                        layer = .layer8
                                    case let .sequenceBasedLayer(sequenceState):
                                        layer = sequenceState.layerNegotiationState.activeLayer.secretChatLayer
                                }
                                if let layer = layer {
                                    var globallyUniqueIds: [Int64] = []
                                    if let globallyUniqueId = message.globallyUniqueId {
                                        globallyUniqueIds.append(globallyUniqueId)
                                        let updatedState = addSecretChatOutgoingOperation(transaction: transaction, peerId: message.id.peerId, operation: SecretChatOutgoingOperationContents.readMessagesContent(layer: layer, actionGloballyUniqueId: Int64.random(in: Int64.min ... Int64.max), globallyUniqueIds: globallyUniqueIds), state: state)
                                        if updatedState != state {
                                            transaction.setPeerChatState(message.id.peerId, state: updatedState)
                                        }
                                    }
                                }
                            }
                        } else {
                            // MARK: GhostBase v0.6C Read Ghost Extras skip consumed-content sync operation
                            let ghostBaseReadGhostExtras = (UserDefaults.standard.object(forKey: "jerkgram.GhostMode.ReadMessages") as? Bool) ?? false
                            let ghostBaseShouldSuppressConsumedSync = ghostBaseReadGhostExtras && message.id.peerId.namespace != Namespaces.Peer.SecretChat
                            if !ghostBaseShouldSuppressConsumedSync {
                                addSynchronizeConsumeMessageContentsOperation(transaction: transaction, messageIds: [message.id])
                            }
                        }
                    }
                } else if let attribute = updatedAttributes[i] as? ConsumablePersonalMentionMessageAttribute, !attribute.consumed {
                    transaction.setPendingMessageAction(type: .consumeUnseenPersonalMessage, id: messageId, action: ConsumePersonalMessageAction())
                    updatedAttributes[i] = ConsumablePersonalMentionMessageAttribute(consumed: attribute.consumed, pending: true)
                }
            }

            let timestamp = Int32(CFAbsoluteTimeGetCurrent() + NSTimeIntervalSince1970)
            for i in 0 ..< updatedAttributes.count {
                if let attribute = updatedAttributes[i] as? AutoremoveTimeoutMessageAttribute {
                    if attribute.countdownBeginTime == nil || attribute.countdownBeginTime == 0 {
                        var timeout = attribute.timeout
                        if let duration = message.secretMediaDuration {
                            timeout = max(timeout, Int32(duration))
                        }
                        updatedAttributes[i] = AutoremoveTimeoutMessageAttribute(timeout: timeout, countdownBeginTime: timestamp)
                        updateMessage = true

                        if messageId.peerId.namespace == Namespaces.Peer.SecretChat {
                            var layer: SecretChatLayer?
                            let state = transaction.getPeerChatState(message.id.peerId) as? SecretChatState
                            if let state = state {
                                switch state.embeddedState {
                                    case .terminated, .handshake:
                                        break
                                    case .basicLayer:
                                        layer = .layer8
                                    case let .sequenceBasedLayer(sequenceState):
                                        layer = sequenceState.layerNegotiationState.activeLayer.secretChatLayer
                                }
                            }

                            if let state = state, let layer = layer, let globallyUniqueId = message.globallyUniqueId {
                                let updatedState = addSecretChatOutgoingOperation(transaction: transaction, peerId: messageId.peerId, operation: .readMessagesContent(layer: layer, actionGloballyUniqueId: Int64.random(in: Int64.min ... Int64.max), globallyUniqueIds: [globallyUniqueId]), state: state)
                                if updatedState != state {
                                    transaction.setPeerChatState(messageId.peerId, state: updatedState)
                                }
                            }
                        }
                    }
                } else if let attribute = updatedAttributes[i] as? AutoclearTimeoutMessageAttribute {
                    if attribute.countdownBeginTime == nil || attribute.countdownBeginTime == 0 {
                        var timeout = attribute.timeout
                        if let duration = message.secretMediaDuration, timeout != viewOnceTimeout {
                            timeout = max(timeout, Int32(duration))
                        }
                        updatedAttributes[i] = AutoclearTimeoutMessageAttribute(timeout: timeout, countdownBeginTime: timestamp)
                        updateMessage = true

                        if messageId.peerId.namespace == Namespaces.Peer.SecretChat {
                            var layer: SecretChatLayer?
                            let state = transaction.getPeerChatState(message.id.peerId) as? SecretChatState
                            if let state = state {
                                switch state.embeddedState {
                                    case .terminated, .handshake:
                                        break
                                    case .basicLayer:
                                        layer = .layer8
                                    case let .sequenceBasedLayer(sequenceState):
                                        layer = sequenceState.layerNegotiationState.activeLayer.secretChatLayer
                                }
                            }

                            if let state = state, let layer = layer, let globallyUniqueId = message.globallyUniqueId {
                                let updatedState = addSecretChatOutgoingOperation(transaction: transaction, peerId: messageId.peerId, operation: .readMessagesContent(layer: layer, actionGloballyUniqueId: Int64.random(in: Int64.min ... Int64.max), globallyUniqueIds: [globallyUniqueId]), state: state)
                                if updatedState != state {
                                    transaction.setPeerChatState(messageId.peerId, state: updatedState)
                                }
                            }
                        }
                    }
                }
            }

            if updateMessage {
                transaction.updateMessage(message.id, update: { currentMessage in
                    var storeForwardInfo: StoreMessageForwardInfo?
                    if let forwardInfo = currentMessage.forwardInfo {
                        storeForwardInfo = StoreMessageForwardInfo(authorId: forwardInfo.author?.id, sourceId: forwardInfo.source?.id, sourceMessageId: forwardInfo.sourceMessageId, date: forwardInfo.date, authorSignature: forwardInfo.authorSignature, psaType: forwardInfo.psaType, flags: forwardInfo.flags)
                    }
                    return .update(StoreMessage(id: currentMessage.id, customStableId: nil, globallyUniqueId: currentMessage.globallyUniqueId, groupingKey: currentMessage.groupingKey, threadId: currentMessage.threadId, timestamp: currentMessage.timestamp, flags: StoreMessageFlags(currentMessage.flags), tags: currentMessage.tags, globalTags: currentMessage.globalTags, localTags: currentMessage.localTags, forwardInfo: storeForwardInfo, authorId: currentMessage.author?.id, text: currentMessage.text, attributes: updatedAttributes, media: currentMessage.media))
                })
            }
        }
    }
}

func _internal_markReactionsOrPollVotesAsSeenInteractively(postbox: Postbox, messageId: MessageId) -> Signal<Void, NoError> {
    return postbox.transaction { transaction -> Void in
        if let message = transaction.getMessage(messageId), (message.tags.contains(.unseenReaction) || message.tags.contains(.unseenPollVote)) {
            var updateMessage = false
            var updatedAttributes = message.attributes
            var updatedMedia = message.media

            for i in 0 ..< updatedAttributes.count {
                if let attribute = updatedAttributes[i] as? ReactionsMessageAttribute, attribute.hasUnseen {
                    updatedAttributes[i] = attribute.withAllSeen()
                    updateMessage = true

                    if message.id.peerId.namespace == Namespaces.Peer.SecretChat {
                    } else {
                        transaction.setPendingMessageAction(type: .readReactionOrPollVote, id: messageId, action: ReadReactionAction())
                    }
                }
            }
            for i in 0 ..< updatedMedia.count {
                if let poll = updatedMedia[i] as? TelegramMediaPoll {
                    updatedMedia[i] = poll.withoutUnreadResults()
                    updateMessage = true

                    if message.id.peerId.namespace == Namespaces.Peer.SecretChat {
                    } else {
                        transaction.setPendingMessageAction(type: .readReactionOrPollVote, id: messageId, action: ReadReactionAction())
                    }
                }
            }

            if updateMessage {
                transaction.updateMessage(message.id, update: { currentMessage in
                    var storeForwardInfo: StoreMessageForwardInfo?
                    if let forwardInfo = currentMessage.forwardInfo {
                        storeForwardInfo = StoreMessageForwardInfo(authorId: forwardInfo.author?.id, sourceId: forwardInfo.source?.id, sourceMessageId: forwardInfo.sourceMessageId, date: forwardInfo.date, authorSignature: forwardInfo.authorSignature, psaType: forwardInfo.psaType, flags: forwardInfo.flags)
                    }
                    var tags = currentMessage.tags
                    tags.remove(.unseenReaction)
                    tags.remove(.unseenPollVote)
                    return .update(StoreMessage(id: currentMessage.id, customStableId: nil, globallyUniqueId: currentMessage.globallyUniqueId, groupingKey: currentMessage.groupingKey, threadId: currentMessage.threadId, timestamp: currentMessage.timestamp, flags: StoreMessageFlags(currentMessage.flags), tags: tags, globalTags: currentMessage.globalTags, localTags: currentMessage.localTags, forwardInfo: storeForwardInfo, authorId: currentMessage.author?.id, text: currentMessage.text, attributes: updatedAttributes, media: updatedMedia))
                })
            }
        }
    }
}

func markMessageContentAsConsumedRemotely(transaction: Transaction, messageId: MessageId, consumeDate: Int32?) {
    if let message = transaction.getMessage(messageId) {
        var updateMessage = false
        var updatedAttributes = message.attributes
        var updatedMedia = message.media
        var updatedTags = message.tags

        for i in 0 ..< updatedAttributes.count {
            if let attribute = updatedAttributes[i] as? ConsumableContentMessageAttribute {
                if !attribute.consumed {
                    updatedAttributes[i] = ConsumableContentMessageAttribute(consumed: true)
                    updateMessage = true
                }
            } else if let attribute = updatedAttributes[i] as? ConsumablePersonalMentionMessageAttribute, !attribute.consumed {
                if attribute.pending {
                    transaction.setPendingMessageAction(type: .consumeUnseenPersonalMessage, id: messageId, action: nil)
                }
                updatedAttributes[i] = ConsumablePersonalMentionMessageAttribute(consumed: true, pending: false)
                updatedTags.remove(.unseenPersonalMessage)
                updateMessage = true
            }
        }

        let timestamp = Int32(CFAbsoluteTimeGetCurrent() + NSTimeIntervalSince1970)
        let countdownBeginTime = consumeDate ?? timestamp
        
        // MARK: Jerkgram v1.2M BUILD124_PERSISTENT_ONETIME_REMOTE1
        // A remote read receipt is the real consumed=true owner for outgoing
        // one-time media. Preserve the media and keep the view-once timeout
        // unscheduled when OneTimeSave is enabled; Secret Chats stay stock.
        let jerkgramKeepOneTimeRemoteMedia = (
            ((UserDefaults.standard.object(forKey: "jerkgram.ProtectedContent.Enabled") as? Bool) ?? true)
            && ((UserDefaults.standard.object(forKey: "jerkgram.ProtectedContent.OneTimeSave") as? Bool) ?? false)
            && message.id.peerId.namespace != Namespaces.Peer.SecretChat
            && message.minAutoremoveOrClearTimeout == viewOnceTimeout
            && message.attributes.contains(where: { $0 is ConsumableContentMessageAttribute })
        )
        
        for i in 0 ..< updatedAttributes.count {

            if let attribute = updatedAttributes[i] as? AutoremoveTimeoutMessageAttribute {
                if (attribute.countdownBeginTime == nil || attribute.countdownBeginTime == 0) && message.containsSecretMedia {
                    if jerkgramKeepOneTimeRemoteMedia {
                        updatedAttributes[i] = AutoremoveTimeoutMessageAttribute(timeout: attribute.timeout, countdownBeginTime: nil)
                    } else {
                        updatedAttributes[i] = AutoremoveTimeoutMessageAttribute(timeout: attribute.timeout, countdownBeginTime: countdownBeginTime)
                    }
                    updateMessage = true

                    if message.id.peerId.namespace == Namespaces.Peer.SecretChat {
                    } else {
                        if !jerkgramKeepOneTimeRemoteMedia && (attribute.timeout == viewOnceTimeout || timestamp >= countdownBeginTime + attribute.timeout) {
                            for i in 0 ..< updatedMedia.count {
                                if let _ = updatedMedia[i] as? TelegramMediaImage {
                                    let ghostBaseOT1KeepOutgoingTimerLocal = (((UserDefaults.standard.object(forKey: "jerkgram.ProtectedContent.Enabled") as? Bool) ?? true) && ((UserDefaults.standard.object(forKey: "jerkgram.ProtectedContent.OneTimeSave") as? Bool) ?? false) && message.id.peerId.namespace != Namespaces.Peer.SecretChat)
                                    if ghostBaseOT1KeepOutgoingTimerLocal {
                                        UserDefaults.standard.set(UserDefaults.standard.integer(forKey: "jerkgram.OT1.OutgoingKeepBlocked.Count") + 1, forKey: "jerkgram.OT1.OutgoingKeepBlocked.Count")
                                        UserDefaults.standard.set("consumeImage", forKey: "jerkgram.OT1.OutgoingKeepPath")
                                    } else {
                                        updatedMedia[i] = TelegramMediaExpiredContent(data: .image)
                                    }
                                } else if let file = updatedMedia[i] as? TelegramMediaFile {
                                    // MARK: GhostBase v0.8I.2 voice/circle local keep
                                    let ghostBaseKeepVoiceCircleLocal = (((UserDefaults.standard.object(forKey: "jerkgram.ProtectedContent.Enabled") as? Bool) ?? true) && ((UserDefaults.standard.object(forKey: "jerkgram.ProtectedContent.OneTimeSave") as? Bool) ?? false) && message.id.peerId.namespace != Namespaces.Peer.SecretChat && (file.isInstantVideo || file.isVoice))
                                    let ghostBaseOT1KeepOutgoingTimerLocal = (((UserDefaults.standard.object(forKey: "jerkgram.ProtectedContent.Enabled") as? Bool) ?? true) && ((UserDefaults.standard.object(forKey: "jerkgram.ProtectedContent.OneTimeSave") as? Bool) ?? false) && message.id.peerId.namespace != Namespaces.Peer.SecretChat)

                                    if file.isInstantVideo {
                                        if !(ghostBaseKeepVoiceCircleLocal || ghostBaseOT1KeepOutgoingTimerLocal) {
                                            updatedMedia[i] = TelegramMediaExpiredContent(data: .videoMessage)
                                        } else {
                                            UserDefaults.standard.set(UserDefaults.standard.integer(forKey: "jerkgram.OT1.OutgoingKeepBlocked.Count") + 1, forKey: "jerkgram.OT1.OutgoingKeepBlocked.Count")
                                            UserDefaults.standard.set("consumeInstantVideo", forKey: "jerkgram.OT1.OutgoingKeepPath")
                                        }
                                    } else if file.isVoice {
                                        if !(ghostBaseKeepVoiceCircleLocal || ghostBaseOT1KeepOutgoingTimerLocal) {
                                            updatedMedia[i] = TelegramMediaExpiredContent(data: .voiceMessage)
                                        } else {
                                            UserDefaults.standard.set(UserDefaults.standard.integer(forKey: "jerkgram.OT1.OutgoingKeepBlocked.Count") + 1, forKey: "jerkgram.OT1.OutgoingKeepBlocked.Count")
                                            UserDefaults.standard.set("consumeVoice", forKey: "jerkgram.OT1.OutgoingKeepPath")
                                        }
                                    } else {
                                        if !ghostBaseOT1KeepOutgoingTimerLocal {
                                            updatedMedia[i] = TelegramMediaExpiredContent(data: .file)
                                        } else {
                                            UserDefaults.standard.set(UserDefaults.standard.integer(forKey: "jerkgram.OT1.OutgoingKeepBlocked.Count") + 1, forKey: "jerkgram.OT1.OutgoingKeepBlocked.Count")
                                            UserDefaults.standard.set("consumeFile", forKey: "jerkgram.OT1.OutgoingKeepPath")
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            } else if let attribute = updatedAttributes[i] as? AutoclearTimeoutMessageAttribute {
                if (attribute.countdownBeginTime == nil || attribute.countdownBeginTime == 0) && message.containsSecretMedia {
                    if jerkgramKeepOneTimeRemoteMedia {
                        updatedAttributes[i] = AutoclearTimeoutMessageAttribute(timeout: attribute.timeout, countdownBeginTime: nil)
                    } else {
                        updatedAttributes[i] = AutoclearTimeoutMessageAttribute(timeout: attribute.timeout, countdownBeginTime: countdownBeginTime)
                    }
                    updateMessage = true

                    if message.id.peerId.namespace == Namespaces.Peer.SecretChat {
                    } else {
                        for i in 0 ..< updatedMedia.count {
                            if !jerkgramKeepOneTimeRemoteMedia && (attribute.timeout == viewOnceTimeout || timestamp >= countdownBeginTime + attribute.timeout) {
                                if let _ = updatedMedia[i] as? TelegramMediaImage {
                                    updatedMedia[i] = TelegramMediaExpiredContent(data: .image)
                                } else if let file = updatedMedia[i] as? TelegramMediaFile {
                                    // MARK: GhostBase v0.8I.2 voice/circle local keep
                                    let ghostBaseKeepVoiceCircleLocal = (((UserDefaults.standard.object(forKey: "jerkgram.ProtectedContent.Enabled") as? Bool) ?? true) && ((UserDefaults.standard.object(forKey: "jerkgram.ProtectedContent.OneTimeSave") as? Bool) ?? false) && message.id.peerId.namespace != Namespaces.Peer.SecretChat && (file.isInstantVideo || file.isVoice))
                                    if file.isInstantVideo {
                                        if !ghostBaseKeepVoiceCircleLocal {
                                            updatedMedia[i] = TelegramMediaExpiredContent(data: .videoMessage)
                                        }
                                    } else if file.isVoice {
                                        if !ghostBaseKeepVoiceCircleLocal {
                                            updatedMedia[i] = TelegramMediaExpiredContent(data: .voiceMessage)
                                        }
                                    } else {
                                        updatedMedia[i] = TelegramMediaExpiredContent(data: .file)
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        if updateMessage {
            transaction.updateMessage(message.id, update: { currentMessage in
                var storeForwardInfo: StoreMessageForwardInfo?
                if let forwardInfo = currentMessage.forwardInfo {
                    storeForwardInfo = StoreMessageForwardInfo(authorId: forwardInfo.author?.id, sourceId: forwardInfo.source?.id, sourceMessageId: forwardInfo.sourceMessageId, date: forwardInfo.date, authorSignature: forwardInfo.authorSignature, psaType: forwardInfo.psaType, flags: forwardInfo.flags)
                }
                return .update(StoreMessage(id: currentMessage.id, customStableId: nil, globallyUniqueId: currentMessage.globallyUniqueId, groupingKey: currentMessage.groupingKey, threadId: currentMessage.threadId, timestamp: currentMessage.timestamp, flags: StoreMessageFlags(currentMessage.flags), tags: updatedTags, globalTags: currentMessage.globalTags, localTags: currentMessage.localTags, forwardInfo: storeForwardInfo, authorId: currentMessage.author?.id, text: currentMessage.text, attributes: updatedAttributes, media: updatedMedia))
            })
        }
    }
}

