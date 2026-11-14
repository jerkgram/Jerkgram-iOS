import Foundation
import Postbox
import SwiftSignalKit

public struct JerkgramLocalAppearanceRenderToken: Equatable {
    public let revision: Int64
    public let generation: Int64
    public let expiredAt: Int32
}

public struct JerkgramLocalAppearanceSnapshot: Equatable {
    public var settings: JerkgramLocalAppearanceSettings
    public var ownUser: TelegramUser?
    public var masterEnabled = JerkgramLocalPremiumPolicy.enabled
    public var emojiUnlocked: Bool { eligible && masterEnabled && settings.emojiEnabled }
    public var colorsUnlocked: Bool { eligible && masterEnabled && settings.colorsEnabled }
    public var active: Bool
    public var activityGeneration: Int64 = 0
    public var expiredAt: Int32 = 0
    public var appearanceUser: TelegramUser?
    public var appearanceUserWithoutEmoji: TelegramUser?
    public var eligible: Bool { active && ownUser?.id.toInt64() == settings.peer && ownUser?.botInfo == nil && ownUser != nil }
    public var renderToken: JerkgramLocalAppearanceRenderToken? {
        guard eligible, masterEnabled, settings.emojiEnabled || settings.colorsEnabled else { return nil }
        return JerkgramLocalAppearanceRenderToken(revision: settings.revision, generation: activityGeneration, expiredAt: expiredAt)
    }
}

// One store per AccountContext, one account's Postbox. No global preferences,
// peer writes, server setters, layout I/O or process-wide appearance cache.
public final class JerkgramLocalAppearanceStore {
    private let postbox: Postbox
    private let owner: Int64
    private let peerId: PeerId
    private let testing: Bool
    private let clock: () -> Double
    private let value: Atomic<JerkgramLocalAppearanceSnapshot>
    private let promise: ValuePromise<JerkgramLocalAppearanceSnapshot>
    private let observation = MetaDisposable()
    private let write = MetaDisposable()
    private var expiry: SwiftSignalKit.Timer?
    private var masterObserver: NSObjectProtocol?
    private static let key: ValueBoxKey = {
        let key = ValueBoxKey(length: 4); key.setInt32(0, value: 0x4A470004); return key
    }()

    public var snapshot: JerkgramLocalAppearanceSnapshot { value.with { $0 } }
    public var updates: Signal<JerkgramLocalAppearanceSnapshot, NoError> { promise.get() }

    public init(account: Account, clock: @escaping () -> Double = { Date().timeIntervalSince1970 }) {
        self.clock = clock
        self.postbox = account.postbox; self.owner = account.id.int64
        self.peerId = account.peerId; self.testing = account.testingEnvironment
        let initial = JerkgramLocalAppearanceSnapshot(settings: JerkgramLocalAppearanceSettings(owner: account.id.int64, peer: account.peerId.toInt64(), testing: account.testingEnvironment), ownUser: nil, active: false)
        self.value = Atomic(value: initial); self.promise = ValuePromise(initial, ignoreRepeated: true)
        self.masterObserver = NotificationCenter.default.addObserver(forName: JerkgramLocalPremiumPolicy.changed, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            var next = self.snapshot
            next.masterEnabled = JerkgramLocalPremiumPolicy.enabled
            // OFF/ON must not revive callbacks opened before the transition.
            if next.activityGeneration < Int64.max { next.activityGeneration += 1 } else { next.active = false }
            self.publish(next)
        }
        self.observation.set((combineLatest(
            account.postbox.preferencesView(keys: [Self.key]),
            TelegramEngine(account: account).data.subscribe(TelegramEngine.EngineData.Item.Peer.Peer(id: account.peerId))
        ) |> deliverOnMainQueue).start(next: { [weak self] preferences, peer in
            guard let self else { return }
            var next = self.snapshot
            let stored = preferences.values[Self.key]?.get(JerkgramLocalAppearanceSettings.self)
            if let stored, stored.isValid, stored.owner == self.owner, stored.peer == self.peerId.toInt64(), stored.testing == self.testing, stored.revision >= next.settings.revision {
                next.settings = stored
            }
            if case let .user(user)? = peer { next.ownUser = user } else { next.ownUser = nil }
            self.publish(next)
        }))
    }

    public func setActive(_ active: Bool) {
        precondition(Thread.isMainThread)
        var next = snapshot
        guard next.active != active else { return }
        next.active = active
        if next.activityGeneration < Int64.max { next.activityGeneration += 1 } else { next.active = false }
        publish(next)
    }

    private func publish(_ update: JerkgramLocalAppearanceSnapshot) {
        precondition(Thread.isMainThread)
        var next = update
        if next.eligible != snapshot.eligible, next.activityGeneration == snapshot.activityGeneration {
            if next.activityGeneration < Int64.max { next.activityGeneration += 1 } else { next.active = false }
        }
        next.appearanceUser = nil; next.appearanceUserWithoutEmoji = nil
        if next.eligible, next.masterEnabled, var user = next.ownUser {
            if next.settings.colorsEnabled {
                if let color = next.settings.nameColor.map({ PeerNameColor(rawValue: $0) }) { user = user.withUpdatedNameColor(.preset(color)) }
                user = user.withUpdatedProfileColor(next.settings.profileColor.map({ PeerNameColor(rawValue: $0) }))
                user = user.withUpdatedBackgroundEmojiId(next.settings.replyEmoji)
                user = user.withUpdatedProfileBackgroundEmojiId(next.settings.profileEmoji)
            }
            next.appearanceUserWithoutEmoji = user
            if next.settings.emojiEnabled, let fileId = next.settings.emojiFileId {
                user = user.withUpdatedEmojiStatus(PeerEmojiStatus(content: .emoji(fileId: fileId), expirationDate: next.settings.emojiExpiration))
            }
            next.appearanceUser = user
        }
        let _ = value.modify { _ in next }; promise.set(next)
        expiry?.invalidate(); expiry = nil
        if next.eligible, next.masterEnabled, next.settings.emojiEnabled,
            let expiration = next.settings.emojiExpiration,
            Double(expiration) > clock() {
            let timer = SwiftSignalKit.Timer(timeout: max(0.01, Double(expiration) - clock()), repeat: false, completion: { [weak self] in
                guard let self else { return }
                // Expiry is presentation-only; retain the user's other choices.
                var next = self.snapshot
                guard next.eligible, next.settings.emojiExpiration == expiration else { return }
                next.expiredAt = expiration
                self.publish(next)
            }, queue: Queue.mainQueue())
            expiry = timer; timer.start()
        }
    }

    @discardableResult public func update(expectedGeneration: Int64? = nil, _ transform: (inout JerkgramLocalAppearanceSettings) -> Void) -> Bool {
        precondition(Thread.isMainThread)
        var next = snapshot
        guard next.eligible, expectedGeneration.map({ $0 == next.activityGeneration }) ?? true, next.settings.revision < Int64.max else { return false }
        let original = next.settings; transform(&next.settings)
        guard next.settings.owner == owner, next.settings.peer == peerId.toInt64(), next.settings.testing == testing, next.settings.isValid else { return false }
        if next.settings == original { return true }
        next.settings.revision = original.revision + 1
        let stored = next.settings
        if next.settings.emojiEnabled != original.emojiEnabled || next.settings.colorsEnabled != original.colorsEnabled {
            guard next.activityGeneration < Int64.max else { return false }
            next.activityGeneration += 1
        }
        publish(next)
        let ownPeerId = peerId; let testing = self.testing
        // Coalesced writes carry the complete latest record, so cancellation of
        // an earlier pending write cannot lose an earlier toggle or selection.
        write.set(postbox.transaction { transaction -> Void in
            guard let state = transaction.getState() as? AuthorizedAccountState,
                state.peerId == ownPeerId, state.isTestingEnvironment == testing,
                let user = transaction.getPeer(ownPeerId) as? TelegramUser, user.botInfo == nil else { return }
            transaction.updatePreferencesEntry(key: Self.key, { current in
                if let current = current?.get(JerkgramLocalAppearanceSettings.self), current.owner == stored.owner, current.revision > stored.revision { return PreferencesEntry(current) }
                return PreferencesEntry(stored)
            })
        }.start())
        return true
    }

    public func project(_ peer: EnginePeer?, snapshot state: JerkgramLocalAppearanceSnapshot? = nil, now: Int32? = nil) -> EnginePeer? {
        guard case let .user(user)? = peer else { return peer }
        let current = snapshot
        let state = state ?? current
        guard current.eligible, state.activityGeneration == current.activityGeneration,
            state.settings.revision == current.settings.revision else { return peer }
        guard state.masterEnabled else { return peer }
        guard state.settings.permits(recordId: owner, ownPeerId: peerId.toInt64(), testing: testing,
            active: state.active, ownIsBot: state.ownUser.map { $0.botInfo != nil }, displayedPeerId: user.id.toInt64(), displayedIsBot: user.botInfo != nil) else { return peer }
        let timestamp = now ?? Int32(clamping: Int64(clock()))
        guard let result = state.settings.currentEmoji(at: timestamp) == nil ? current.appearanceUserWithoutEmoji : current.appearanceUser else { return peer }
        return .user(result)
    }

    public func projectPeer(_ peer: Peer?) -> Peer? {
        guard let peer, peer.id == peerId else { return peer }
        return project(EnginePeer(peer))?._asPeer()
    }

    public func projectMessage(_ message: EngineRawMessage) -> EngineRawMessage {
        let state = snapshot
        guard state.renderToken != nil,
            let user = (message.peers[peerId] as? TelegramUser) ?? (message.author as? TelegramUser),
            case let .user(projected)? = project(.user(user), snapshot: state), projected != user else { return message }
        var peers = message.peers
        peers[peerId] = projected
        let result = message.withUpdatedPeers(peers)
        return message.author?.id == peerId ? result.withUpdatedAuthor(projected) : result
    }

    deinit { if let masterObserver { NotificationCenter.default.removeObserver(masterObserver) }; expiry?.invalidate(); observation.dispose(); write.dispose() }
}
