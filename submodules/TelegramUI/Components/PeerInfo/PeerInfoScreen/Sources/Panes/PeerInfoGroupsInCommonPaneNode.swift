import Foundation
import UIKit
import AsyncDisplayKit
import Display
import TelegramCore
import SwiftSignalKit
import TelegramPresentationData
import AccountContext
import ContextUI
import PhotoResources
import TelegramUIPreferences
import ItemListPeerItem
import MergeLists
import ItemListUI
import ChatControllerInteraction
import PeerInfoVisualMediaPaneNode
import PeerInfoPaneNode

private struct GroupsInCommonListTransaction {
    let deletions: [ListViewDeleteItem]
    let insertions: [ListViewInsertItem]
    let updates: [ListViewUpdateItem]
}

private struct GroupsInCommonListEntry: Comparable, Identifiable {
    var index: Int
    var peer: EnginePeer

    var stableId: EnginePeer.Id {
        return self.peer.id
    }

    static func ==(lhs: GroupsInCommonListEntry, rhs: GroupsInCommonListEntry) -> Bool {
        return lhs.peer == rhs.peer
    }
    
    static func <(lhs: GroupsInCommonListEntry, rhs: GroupsInCommonListEntry) -> Bool {
        return lhs.index < rhs.index
    }
    
    func item(context: AccountContext, presentationData: PresentationData, ghostBaseGlassEnabled: Bool, openPeer: @escaping (EnginePeer) -> Void, openPeerContextAction: @escaping (EnginePeer, ASDisplayNode, ContextGesture?) -> Void) -> ListViewItem {
        let peer = self.peer
        return ItemListPeerItem(presentationData: ItemListPresentationData(presentationData), systemStyle: .legacy, dateTimeFormat: presentationData.dateTimeFormat, nameDisplayOrder: presentationData.nameDisplayOrder, context: context, peer: self.peer, presence: nil, text: .none, label: .none, editing: ItemListPeerItemEditing(editable: false, editing: false, revealed: false), switchValue: nil, enabled: true, selectable: true, sectionId: 0, action: {
            openPeer(peer)
        }, setPeerIdWithRevealedOptions: { _, _ in
        }, removePeer: { _ in
        }, contextAction: { node, gesture in
            openPeerContextAction(peer, node, gesture)
        }, hasTopStripe: false, noInsets: true, noCorners: true, style: .plain, displayBackground: !ghostBaseGlassEnabled)
    }
}

private func preparedTransition(from fromEntries: [GroupsInCommonListEntry], to toEntries: [GroupsInCommonListEntry], context: AccountContext, presentationData: PresentationData, ghostBaseGlassEnabled: Bool, openPeer: @escaping (EnginePeer) -> Void, openPeerContextAction: @escaping (EnginePeer, ASDisplayNode, ContextGesture?) -> Void) -> GroupsInCommonListTransaction {
    let (deleteIndices, indicesAndItems, updateIndices) = mergeListsStableWithUpdates(leftList: fromEntries, rightList: toEntries)
    
    let deletions = deleteIndices.map { ListViewDeleteItem(index: $0, directionHint: nil) }
    let insertions = indicesAndItems.map { ListViewInsertItem(index: $0.0, previousIndex: $0.2, item: $0.1.item(context: context, presentationData: presentationData, ghostBaseGlassEnabled: ghostBaseGlassEnabled, openPeer: openPeer, openPeerContextAction: openPeerContextAction), directionHint: nil) }
    let updates = updateIndices.map { ListViewUpdateItem(index: $0.0, previousIndex: $0.2, item: $0.1.item(context: context, presentationData: presentationData, ghostBaseGlassEnabled: ghostBaseGlassEnabled, openPeer: openPeer, openPeerContextAction: openPeerContextAction), directionHint: nil) }
    
    return GroupsInCommonListTransaction(deletions: deletions, insertions: insertions, updates: updates)
}

final class PeerInfoGroupsInCommonPaneNode: ASDisplayNode, PeerInfoPaneNode {
    private let context: AccountContext
    private let peerId: EnginePeer.Id
    private let chatControllerInteraction: ChatControllerInteraction
    private let openPeerContextAction: (Bool, EnginePeer, ASDisplayNode, ContextGesture?) -> Void
    private let groupsInCommonContext: GroupsInCommonContext
    
    weak var parentController: ViewController?

    private let ghostBaseGlassEnabled: Bool
    private let listBackgroundView: UIImageView
    private let listMaskView: UIImageView

    // MARK: GhostBase v1.1R COMMON_GROUPS_GLASS1
    private let ghostBaseGlassEffectView: UIVisualEffectView
    private let ghostBaseGlassTintView: UIView
    private var ghostBaseGlassIsDark: Bool?

    private let listNode: ListView
    private var state: GroupsInCommonState?
    private var currentEntries: [GroupsInCommonListEntry] = []
    private var enqueuedTransactions: [GroupsInCommonListTransaction] = []
    
    private var currentParams: (size: CGSize, isScrollingLockedAtTop: Bool, presentationData: PresentationData)?

    private var ignoreListBackgroundUpdates: Bool = false

    private let ready = Promise<Bool>()
    private var didSetReady: Bool = false
    var isReady: Signal<Bool, NoError> {
        return self.ready.get()
    }

    var status: Signal<PeerInfoStatusData?, NoError> {
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        return self.groupsInCommonContext.state
        |> map { state in
            if let count = state.count {
                return PeerInfoStatusData(text: presentationData.strings.SharedMedia_CommonGroupCount(Int32(count)), isActivity: false, key: .groupsInCommon)
            } else {
                return nil
            }
        }
    }

    var tabBarOffsetUpdated: ((ContainedViewLayoutTransition) -> Void)?
    var tabBarOffset: CGFloat {
        return 0.0
    }
        
    private var disposable: Disposable?
    
    init(context: AccountContext, peerId: EnginePeer.Id, chatControllerInteraction: ChatControllerInteraction, openPeerContextAction: @escaping (Bool, EnginePeer, ASDisplayNode, ContextGesture?) -> Void, groupsInCommonContext: GroupsInCommonContext, ghostBaseGlassEnabled: Bool = false) {
        self.ghostBaseGlassEnabled = ghostBaseGlassEnabled
        self.context = context
        self.peerId = peerId
        self.chatControllerInteraction = chatControllerInteraction
        self.openPeerContextAction = openPeerContextAction
        self.groupsInCommonContext = groupsInCommonContext
        
        let presentationData = context.sharedContext.currentPresentationData.with { $0 }
        self.listNode = ListViewImpl()
        self.listNode.accessibilityPageScrolledString = { row, count in
            return presentationData.strings.VoiceOver_ScrollStatus(row, count).string
        }

        self.listBackgroundView = UIImageView()
        self.listBackgroundView.image = generateStretchableFilledCircleImage(diameter: 26.0 * 2.0, color: .white)?.withRenderingMode(.alwaysTemplate)

        self.ghostBaseGlassEffectView = UIVisualEffectView(effect: nil)
        self.ghostBaseGlassEffectView.isUserInteractionEnabled = false
        self.ghostBaseGlassEffectView.isHidden = !ghostBaseGlassEnabled
        self.ghostBaseGlassTintView = UIView()
        self.ghostBaseGlassTintView.isUserInteractionEnabled = false
        self.ghostBaseGlassIsDark = nil

        self.listMaskView = UIImageView()
        self.listMaskView.image = generateImage(CGSize(width: 16.0 + 26.0 * 2.0 + 16.0, height: 2.0 * 2.0 + 26.0 * 2.0), rotatedContext: { size, context in
            context.clear(CGRect(origin: CGPoint(), size: size))
            context.setFillColor(UIColor.white.cgColor)
            context.fill(CGRect(origin: CGPoint(), size: size))
            context.setFillColor(UIColor.clear.cgColor)
            context.setBlendMode(.copy)
            context.fillEllipse(in: CGRect(origin: CGPoint(x: 16.0, y: 2.0), size: CGSize(width: 26.0 * 2.0, height: 26.0 * 2.0)))
        })?.stretchableImage(withLeftCapWidth: 16 + 26, topCapHeight: 2 + 26).withRenderingMode(.alwaysTemplate)

        super.init()

        self.listNode.preloadPages = true
        self.view.addSubview(self.listBackgroundView)
        self.view.addSubview(self.ghostBaseGlassEffectView)
        self.ghostBaseGlassEffectView.contentView.addSubview(self.ghostBaseGlassTintView)
        self.addSubnode(self.listNode)
        self.view.addSubview(self.listMaskView)
        
        self.disposable = (groupsInCommonContext.state
        |> deliverOnMainQueue).startStrict(next: { [weak self] state in
            guard let strongSelf = self else {
                return
            }
            strongSelf.state = state
            if let (_, _, presentationData) = strongSelf.currentParams {
                strongSelf.updatePeers(state: state, presentationData: presentationData)
            }
        })
        
        self.listNode.visibleBottomContentOffsetChanged = { [weak self] offset in
            guard let strongSelf = self, let state = strongSelf.state, case .ready(true) = state.dataState else {
                return
            }
            if case let .known(value) = offset, value < 100.0, case .ready(true) = state.dataState {
                strongSelf.groupsInCommonContext.loadMore()
            }
        }

        self.listNode.visibleContentOffsetChanged = { [weak self] _, transition in
            guard let self else {
                return
            }
            if !self.ignoreListBackgroundUpdates {
                self.updateListBackground(transition: transition)
            }
        }
        self.listNode.displayedItemRangeChanged = { [weak self] _, _ in
            guard let self else {
                return
            }
            if !self.ignoreListBackgroundUpdates {
                self.updateListBackground(transition: .immediate)
            }
        }
    }
    
    deinit {
        self.disposable?.dispose()
    }
    
    func ensureMessageIsVisible(id: EngineMessage.Id) {    
    }
    
    func scrollToTop() -> Bool {
        if !self.listNode.scrollToOffsetFromTop(0.0, animated: true) {
            self.listNode.transaction(deleteIndices: [], insertIndicesAndItems: [], updateIndicesAndItems: [], options: [.Synchronous, .LowLatency], scrollToItem: ListViewScrollToItem(index: 0, position: .top(0.0), animated: true, curve: .Default(duration: nil), directionHint: .Up), updateSizeAndInsets: nil, stationaryItemRange: nil, updateOpaqueState: nil, completion: { _ in })
            return true
        } else {
            return false
        }
    }
    
    func update(size: CGSize, topInset: CGFloat, sideInset: CGFloat, bottomInset: CGFloat, deviceMetrics: DeviceMetrics, visibleHeight: CGFloat, isScrollingLockedAtTop: Bool, expandProgress: CGFloat, navigationHeight: CGFloat, presentationData: PresentationData, synchronous: Bool, transition: ContainedViewLayoutTransition) {
        let isFirstLayout = self.currentParams == nil
        self.currentParams = (size, isScrollingLockedAtTop, presentationData)
        
        self.ignoreListBackgroundUpdates = true
        transition.updateFrame(node: self.listNode, frame: CGRect(origin: CGPoint(), size: size))
        let (duration, curve) = listViewAnimationDurationAndCurve(transition: transition)

        var scrollToItem: ListViewScrollToItem?
        if isScrollingLockedAtTop {
            switch self.listNode.visibleContentOffset() {
            case let .known(value) where value <= CGFloat.ulpOfOne:
                break
            default:
                scrollToItem = ListViewScrollToItem(index: 0, position: .top(0.0), animated: true, curve: .Spring(duration: duration), directionHint: .Up)
            }
        }

        self.listNode.transaction(deleteIndices: [], insertIndicesAndItems: [], updateIndicesAndItems: [], options: [.Synchronous, .LowLatency], scrollToItem: scrollToItem, updateSizeAndInsets: ListViewUpdateSizeAndInsets(size: size, insets: UIEdgeInsets(top: topInset, left: sideInset + 16.0, bottom: bottomInset, right: sideInset + 16.0), duration: duration, curve: curve), stationaryItemRange: nil, updateOpaqueState: nil, completion: { _ in })

        self.listNode.scrollEnabled = !isScrollingLockedAtTop

        self.ignoreListBackgroundUpdates = false
        self.updateListBackground(transition: transition)

        if self.ghostBaseGlassEnabled {
            let isDark = presentationData.theme.overallDarkAppearance

            self.backgroundColor = .clear
            self.view.backgroundColor = .clear
            self.listNode.backgroundColor = .clear
            self.listNode.view.backgroundColor = .clear

            // MARK: GhostBase v1.1S COMMON_GROUPS_TRANSLUCENT1
            // Do not stack another dark system material over the already
            // blurred profile scene. Keep one light rounded translucent owner.
            self.ghostBaseGlassIsDark = isDark
            self.ghostBaseGlassEffectView.effect = nil
            self.ghostBaseGlassEffectView.backgroundColor = .clear
            self.ghostBaseGlassEffectView.contentView.backgroundColor = .clear
            self.ghostBaseGlassEffectView.isHidden = false
            // MARK: Jerkgram v1.2L BUILD123_COMMON_GROUPS_SURFACE1
            // One neutral readability surface, matching neighboring cards;
            // the fullscreen profile remains the only blur owner.
            self.ghostBaseGlassEffectView.effect = nil
            self.ghostBaseGlassEffectView.backgroundColor = .clear
            self.ghostBaseGlassEffectView.contentView.backgroundColor = .clear
            self.ghostBaseGlassEffectView.isHidden = false
            self.ghostBaseGlassTintView.backgroundColor = UIColor(
                white: isDark ? 0.0 : 1.0,
                alpha: isDark ? 0.26 : 0.18
            )
            self.listBackgroundView.isHidden = true
            self.listBackgroundView.alpha = 0.0
            self.listMaskView.isHidden = true
            self.listMaskView.alpha = 0.0
        } else {
            self.ghostBaseGlassEffectView.isHidden = true
            self.ghostBaseGlassEffectView.effect = nil
            self.ghostBaseGlassTintView.backgroundColor = .clear
            self.listBackgroundView.isHidden = false
            self.listBackgroundView.alpha = 1.0
            self.listMaskView.isHidden = false
            self.listMaskView.alpha = 1.0

            self.listBackgroundView.tintColor =
                presentationData.theme.list.itemBlocksBackgroundColor
            self.listMaskView.tintColor =
                presentationData.theme.list.blocksBackgroundColor
        }


        if isFirstLayout, let state = self.state {
            self.updatePeers(state: state, presentationData: presentationData)
        }
    }
    
    private func updatePeers(state: GroupsInCommonState, presentationData: PresentationData) {
        var entries: [GroupsInCommonListEntry] = []
        for peer in state.peers {
            if let peer = peer.peer {
                entries.append(GroupsInCommonListEntry(index: entries.count, peer: EnginePeer(peer)))
            }
        }
        let transaction = preparedTransition(from: self.currentEntries, to: entries, context: self.context, presentationData: presentationData, ghostBaseGlassEnabled: self.ghostBaseGlassEnabled, openPeer: { [weak self] peer in
            self?.chatControllerInteraction.openPeer(peer, .default, nil, .default)
        }, openPeerContextAction: { [weak self] peer, node, gesture in
            self?.openPeerContextAction(false, peer, node, gesture)
        })
        self.currentEntries = entries
        self.enqueuedTransactions.append(transaction)
        self.dequeueTransaction()
    }
    
    private func dequeueTransaction() {
        guard let _ = self.currentParams, let transaction = self.enqueuedTransactions.first else {
            return
        }
        
        self.enqueuedTransactions.remove(at: 0)
        
        var options = ListViewDeleteAndInsertOptions()
        options.insert(.Synchronous)
        
        self.listNode.transaction(deleteIndices: transaction.deletions, insertIndicesAndItems: transaction.insertions, updateIndicesAndItems: transaction.updates, options: options, updateSizeAndInsets: nil, updateOpaqueState: nil, completion: { [weak self] _ in
            guard let strongSelf = self else {
                return
            }
            if !strongSelf.didSetReady {
                strongSelf.didSetReady = true
                strongSelf.ready.set(.single(true))
            }
        })
    }
    
    private func updateListBackground(transition: ContainedViewLayoutTransition) {
        guard self.listNode.visibleSize.width != 0.0 else {
            return
        }

        var distanceToTop: CGFloat = -100.0
        var distanceToBottom: CGFloat = -100.0
        switch self.listNode.visibleContentOffset() {
        case let .known(topOffset):
            distanceToTop = -topOffset + self.listNode.insets.top
        default:
            break
        }
        switch self.listNode.visibleBottomContentOffset() {
        case let .known(bottomOffset):
            distanceToBottom = -bottomOffset + self.listNode.insets.bottom
        default:
            break
        }

        distanceToTop = max(-100.0, distanceToTop)
        distanceToBottom = max(-100.0, distanceToBottom)

        let listBackgroundFrame = CGRect(origin: CGPoint(x: 16.0, y: distanceToTop), size: CGSize(width: max(1.0, self.listNode.visibleSize.width - 16.0 * 2.0), height: max(1.0, self.listNode.visibleSize.height - distanceToBottom - distanceToTop)))
        let listMaskFrame = CGRect(origin: CGPoint(x: 0.0, y: listBackgroundFrame.minY - 2.0), size: CGSize(width: listBackgroundFrame.width + 16.0 * 2.0, height: listBackgroundFrame.height + 2.0 * 2.0))
        transition.updateFrame(view: self.listBackgroundView, frame: listBackgroundFrame)
        transition.updateFrame(view: self.listMaskView, frame: listMaskFrame)
        transition.updateFrame(view: self.ghostBaseGlassEffectView, frame: listBackgroundFrame)
        self.ghostBaseGlassEffectView.layer.cornerRadius = 26.0
        self.ghostBaseGlassEffectView.layer.masksToBounds = true
        self.ghostBaseGlassTintView.frame = CGRect(origin: .zero, size: listBackgroundFrame.size)
    }

    func findLoadedMessage(id: EngineMessage.Id) -> EngineMessage? {
        return nil
    }
    
    func updateHiddenMedia() {
    }
    
    func transferVelocity(_ velocity: CGFloat) {
        if velocity > 0.0 {
            self.listNode.transferVelocity(velocity)
        }
    }
    
    func cancelPreviewGestures() {
    }
    
    func transitionNodeForGallery(messageId: EngineMessage.Id, media: EngineMedia) -> (ASDisplayNode, CGRect, () -> (UIView?, UIView?))? {
        return nil
    }
    
    func addToTransitionSurface(view: UIView) {
    }
    
    func updateSelectedMessages(animated: Bool) {
    }
}
