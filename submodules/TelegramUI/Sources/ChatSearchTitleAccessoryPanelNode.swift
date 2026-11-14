import Foundation
import UIKit
import Display
import AsyncDisplayKit
import TelegramPresentationData
import PresentationDataUtils
import ChatPresentationInterfaceState
import AccountContext
import ComponentFlow
import MultilineTextComponent
import PlainButtonComponent
import UIKitRuntimeUtils
import TelegramCore
import Postbox
import EmojiStatusComponent
import SwiftSignalKit
import ContextUI
import PromptUI
import BundleIconComponent
import SavedTagNameAlertController
import LegacyChatHeaderPanelComponent

private let backgroundTagImage: UIImage? = {
    if let image = UIImage(bundleImageName: "Chat/Title Panels/SearchTagTab") {
        return image.stretchableImage(withLeftCapWidth: 8, topCapHeight: 0).withRenderingMode(.alwaysTemplate)
    } else {
        return nil
    }
}()

// Only native strip inputs participate; unrelated chat/panel updates do no work.
struct JerkgramLocalSavedTagsRenderKey: Equatable {
    let revision: Int64?
    let selectedId: String?
    let theme: ObjectIdentifier
    let strings: ObjectIdentifier
    let width: CGFloat
    let leftInset: CGFloat
    let rightInset: CGFloat
    let available: Bool
}
struct JerkgramLocalSavedTagsRenderGate {
    private var previous: JerkgramLocalSavedTagsRenderKey?
    mutating func update(_ key: JerkgramLocalSavedTagsRenderKey) -> Bool {
        guard self.previous != key else { return false }
        self.previous = key
        return true
    }
    mutating func invalidate() { self.previous = nil }
}

final class ChatSearchTitleAccessoryPanelNode: ChatTitleAccessoryPanelNode, ChatControllerCustomNavigationPanelNode, ASScrollViewDelegate {
    private struct Params: Equatable {
        var width: CGFloat
        var leftInset: CGFloat
        var rightInset: CGFloat
        var interfaceState: ChatPresentationInterfaceState
        
        init(width: CGFloat, leftInset: CGFloat, rightInset: CGFloat, interfaceState: ChatPresentationInterfaceState) {
            self.width = width
            self.leftInset = leftInset
            self.rightInset = rightInset
            self.interfaceState = interfaceState
        }
        
        static func ==(lhs: Params, rhs: Params) -> Bool {
            if lhs.width != rhs.width {
                return false
            }
            if lhs.leftInset != rhs.leftInset {
                return false
            }
            if lhs.rightInset != rhs.rightInset {
                return false
            }
            if lhs.interfaceState != rhs.interfaceState {
                return false
            }
            return true
        }
    }
    
    private final class Item {
        let reaction: MessageReaction.Reaction
        let count: Int
        let title: String?
        let file: TelegramMediaFile?
        
        init(reaction: MessageReaction.Reaction, count: Int, title: String?, file: TelegramMediaFile?) {
            self.reaction = reaction
            self.count = count
            self.title = title
            self.file = file
        }
    }
    
    private final class PromoView: UIView {
        private let containerButton: HighlightTrackingButton
        
        private let background: UIImageView
        private let titleIcon = ComponentView<Empty>()
        private let title = ComponentView<Empty>()
        private let text = ComponentView<Empty>()
        private let arrowIcon = ComponentView<Empty>()
        
        let action: () -> Void
        
        init(action: @escaping () -> Void) {
            self.action = action
            
            self.containerButton = HighlightTrackingButton()
            
            self.background = UIImageView()
            self.background.image = backgroundTagImage
            
            super.init(frame: CGRect())
            
            self.containerButton.layer.allowsGroupOpacity = true
            
            self.containerButton.addSubview(self.background)
            
            self.addSubview(self.containerButton)
            
            self.containerButton.addTarget(self, action: #selector(self.pressed), for: .touchUpInside)
            self.containerButton.highligthedChanged = { [weak self] highlighted in
                guard let self else {
                    return
                }
                if highlighted {
                    self.containerButton.alpha = 0.7
                } else {
                    ComponentTransition.easeInOut(duration: 0.25).setAlpha(view: self.containerButton, alpha: 1.0)
                }
            }
        }
        
        required init?(coder: NSCoder) {
            preconditionFailure()
        }
        
        @objc private func pressed() {
            self.action()
        }
        
        func update(theme: PresentationTheme, strings: PresentationStrings, height: CGFloat, isUnlock: Bool, transition: ComponentTransition) -> CGSize {
            let titleIconSpacing: CGFloat = 0.0
            
            let titleIconSize = self.titleIcon.update(
                transition: .immediate,
                component: AnyComponent(BundleIconComponent(
                    name: "Chat/Stickers/Lock",
                    tintColor: theme.rootController.navigationBar.accentTextColor,
                    maxSize: CGSize(width: 14.0, height: 14.0)
                )),
                environment: {},
                containerSize: CGSize(width: 14.0, height: 14.0)
            )
            
            let titleSize = self.title.update(
                transition: .immediate,
                component: AnyComponent(MultilineTextComponent(
                    text: .plain(NSAttributedString(string: isUnlock ? strings.Chat_TagsHeaderPanel_Unlock : strings.Chat_TagsHeaderPanel_AddTags, font: Font.medium(14.0), textColor: theme.rootController.navigationBar.accentTextColor))
                )),
                environment: {},
                containerSize: CGSize(width: 200.0, height: 100.0)
            )
            
            let size = CGSize(width: titleIconSize.width + titleIconSpacing + titleSize.width - 1.0, height: height)
            
            let titleIconFrame = CGRect(origin: CGPoint(x: -1.0, y: UIScreenPixel + floor((size.height - titleIconSize.height) * 0.5)), size: titleIconSize)
            if let titleIconView = self.titleIcon.view {
                if titleIconView.superview == nil {
                    titleIconView.isUserInteractionEnabled = false
                    self.containerButton.addSubview(titleIconView)
                }
                titleIconView.frame = titleIconFrame
            }
            
            let titleFrame = CGRect(origin: CGPoint(x: titleIconSize.width + titleIconSpacing, y: floor((size.height - titleSize.height) * 0.5)), size: titleSize)
            if let titleView = self.title.view {
                if titleView.superview == nil {
                    titleView.isUserInteractionEnabled = false
                    self.containerButton.addSubview(titleView)
                }
                titleView.frame = titleFrame
            }
            
            self.background.tintColor = theme.rootController.navigationBar.accentTextColor.withMultipliedAlpha(0.1)
            
            if let image = self.background.image {
                let backgroundFrame = CGRect(origin: CGPoint(x: -6.0, y: floorToScreenPixels((size.height - image.size.height) * 0.5)), size: CGSize(width: size.width + 6.0 + 9.0, height: image.size.height))
                transition.setFrame(view: self.background, frame: backgroundFrame)
            }
            
            var totalSize = size
            
            let textSize = self.text.update(
                transition: .immediate,
                component: AnyComponent(MultilineTextComponent(
                    text: .plain(NSAttributedString(string: strings.Chat_TagsHeaderPanel_AddTagsSuffix, font: Font.regular(14.0), textColor: theme.rootController.navigationBar.secondaryTextColor))
                )),
                environment: {},
                containerSize: CGSize(width: 200.0, height: 100.0)
            )
            let arrowSize = self.arrowIcon.update(
                transition: .immediate,
                component: AnyComponent(BundleIconComponent(
                    name: "Item List/DisclosureArrow",
                    tintColor: theme.rootController.navigationBar.secondaryTextColor.withMultipliedAlpha(0.6)
                )),
                environment: {},
                containerSize: CGSize(width: 200.0, height: 100.0)
            )
            let textSpacing: CGFloat = 13.0
            let arrowSpacing: CGFloat = -5.0
            
            totalSize.width += textSpacing
            
            let textFrame = CGRect(origin: CGPoint(x: totalSize.width, y: floor((size.height - textSize.height) * 0.5)), size: textSize)
            if let textView = self.text.view {
                if textView.superview == nil {
                    textView.isUserInteractionEnabled = false
                    self.containerButton.addSubview(textView)
                }
                textView.frame = textFrame
                transition.setAlpha(view: textView, alpha: isUnlock ? 0.0 : 1.0)
            }
            totalSize.width += textSize.width
            totalSize.width += arrowSpacing
            
            let arrowFrame = CGRect(origin: CGPoint(x: totalSize.width, y: 1.0 + floor((size.height - arrowSize.height) * 0.5)), size: arrowSize)
            if let arrowIconView = self.arrowIcon.view {
                if arrowIconView.superview == nil {
                    arrowIconView.isUserInteractionEnabled = false
                    self.containerButton.addSubview(arrowIconView)
                }
                arrowIconView.frame = arrowFrame
                transition.setAlpha(view: arrowIconView, alpha: isUnlock ? 0.0 : 1.0)
            }
            totalSize.width += arrowSize.width
            
            transition.setFrame(view: self.containerButton, frame: CGRect(origin: CGPoint(), size: totalSize))
            
            return isUnlock ? size : totalSize
        }
    }
    
    private final class ItemView: UIView {
        private let context: AccountContext
        private let action: () -> Void
        
        private let extractedContainerNode: ContextExtractedContentContainingNode
        private let containerNode: ContextControllerSourceNode
        
        private let containerButton: HighlightTrackingButton
        
        private let background: UIImageView
        private let icon = ComponentView<Empty>()
        private let title = ComponentView<Empty>()
        private let counter = ComponentView<Empty>()
        
        init(context: AccountContext, action: @escaping (() -> Void), contextGesture: @escaping (ContextGesture, ContextExtractedContentContainingNode) -> Void) {
            self.context = context
            self.action = action
            
            self.extractedContainerNode = ContextExtractedContentContainingNode()
            self.containerNode = ContextControllerSourceNode()
            
            self.containerButton = HighlightTrackingButton()
            
            self.background = UIImageView()
            self.background.image = backgroundTagImage
            
            super.init(frame: CGRect())
            
            self.extractedContainerNode.contentNode.view.addSubview(self.containerButton)
            
            self.containerNode.addSubnode(self.extractedContainerNode)
            self.containerNode.targetNodeForActivationProgress = self.extractedContainerNode.contentNode
            self.addSubview(self.containerNode.view)
            
            self.containerButton.addSubview(self.background)
            
            self.containerButton.addTarget(self, action: #selector(self.pressed), for: .touchUpInside)
            self.containerButton.highligthedChanged = { [weak self] highlighted in
                if let self, self.bounds.width > 0.0 {
                    let topScale: CGFloat = (self.bounds.width - 1.0) / self.bounds.width
                    let maxScale: CGFloat = (self.bounds.width + 1.0) / self.bounds.width
                    
                    if highlighted {
                        self.layer.removeAnimation(forKey: "opacity")
                        self.layer.removeAnimation(forKey: "sublayerTransform")
                        let transition: ContainedViewLayoutTransition = .animated(duration: 0.2, curve: .easeInOut)
                        transition.updateTransformScale(layer: self.layer, scale: topScale)
                    } else {
                        let transition: ContainedViewLayoutTransition = .immediate
                        transition.updateTransformScale(layer: self.layer, scale: 1.0)
                        
                        self.layer.animateScale(from: topScale, to: maxScale, duration: 0.13, timingFunction: CAMediaTimingFunctionName.easeOut.rawValue, removeOnCompletion: false, completion: { [weak self] _ in
                            guard let self else {
                                return
                            }
                            
                            self.layer.animateScale(from: maxScale, to: 1.0, duration: 0.1, timingFunction: CAMediaTimingFunctionName.easeIn.rawValue)
                        })
                    }
                }
            }
            
            self.containerNode.activated = { [weak self] gesture, _ in
                guard let self else {
                    return
                }
                contextGesture(gesture, self.extractedContainerNode)
            }
        }
        
        required init?(coder: NSCoder) {
            preconditionFailure()
        }
        
        @objc private func pressed() {
            self.action()
        }
        
        override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
            var mappedPoint = point
            if self.bounds.insetBy(dx: -8.0, dy: -4.0).contains(point) {
                mappedPoint = self.bounds.center
            }
            return super.hitTest(mappedPoint, with: event)
        }
        
        func update(item: Item, isSelected: Bool, isLocked: Bool, theme: PresentationTheme, height: CGFloat, transition: ComponentTransition) -> CGSize {
            let spacing: CGFloat = 3.0
            
            let contentsAlpha: CGFloat = isLocked ? 0.6 : 1.0
            
            let reactionSize = CGSize(width: 20.0, height: 20.0)
            var reactionDisplaySize = reactionSize
            if case .builtin = item.reaction {
                reactionDisplaySize = CGSize(width: reactionDisplaySize.width * 2.0, height: reactionDisplaySize.height * 2.0)
            }
            
            if let file = item.file {
            let _ = self.icon.update(
                transition: .immediate,
                component: AnyComponent(EmojiStatusComponent(
                    context: self.context,
                    animationCache: self.context.animationCache,
                    animationRenderer: self.context.animationRenderer,
                    content: .animation(
                        content: .file(file: file),
                        size: reactionDisplaySize,
                        placeholderColor: theme.list.mediaPlaceholderColor,
                        themeColor: theme.list.itemPrimaryTextColor,
                        loopMode: .forever
                    ),
                    isVisibleForAnimations: false,
                    useSharedAnimation: true,
                    action: nil,
                    emojiFileUpdated: nil
                )),
                environment: {},
                containerSize: reactionDisplaySize
            )
            
            } else {
                reactionDisplaySize = reactionSize
                let text: String
                if case let .builtin(value) = item.reaction { text = value } else { text = "" }
                let _ = self.icon.update(transition: .immediate, component: AnyComponent(MultilineTextComponent(
                    text: .plain(NSAttributedString(string: text, font: Font.regular(18.0), textColor: theme.list.itemAccentColor))
                )), environment: {}, containerSize: reactionSize)
            }

            let titleText: String = item.title ?? ""
            let titleSize = self.title.update(
                transition: .immediate,
                component: AnyComponent(MultilineTextComponent(
                    text: .plain(NSAttributedString(string: titleText, font: Font.regular(11.0), textColor: isSelected ? theme.list.itemCheckColors.foregroundColor : theme.list.itemPrimaryTextColor.withMultipliedAlpha(0.6)))
                )),
                environment: {},
                containerSize: CGSize(width: 100.0, height: 100.0)
            )
            
            let counterText: String = item.count < 0 ? "" : "\(item.count)"
            let counterSize = self.counter.update(
                transition: .immediate,
                component: AnyComponent(MultilineTextComponent(
                    text: .plain(NSAttributedString(string: counterText, font: Font.regular(11.0), textColor: isSelected ? theme.list.itemCheckColors.foregroundColor : theme.list.itemPrimaryTextColor.withMultipliedAlpha(0.6)))
                )),
                environment: {},
                containerSize: CGSize(width: 100.0, height: 100.0)
            )
            
            let titleCounterSpacing: CGFloat = 3.0
            
            var titleAndCounterSize: CGFloat = titleSize.width
            if titleSize.width != 0.0 {
                titleAndCounterSize += titleCounterSpacing
            }
            titleAndCounterSize += counterSize.width
            
            let size = CGSize(width: reactionSize.width + spacing + titleAndCounterSize - 2.0, height: height)
            
            let iconFrame = CGRect(origin: CGPoint(x: -1.0, y: floor((size.height - reactionSize.height) * 0.5)), size: reactionSize)
            
            let titleFrame = CGRect(origin: CGPoint(x: iconFrame.maxX + spacing, y: floor((size.height - titleSize.height) * 0.5)), size: titleSize)
            let counterFrame = CGRect(origin: CGPoint(x: titleFrame.maxX + (titleSize.width.isZero ? 0.0 : titleCounterSpacing), y: floor((size.height - counterSize.height) * 0.5)), size: counterSize)
            
            if let iconView = self.icon.view {
                if iconView.superview == nil {
                    iconView.isUserInteractionEnabled = false
                    self.containerButton.addSubview(iconView)
                }
                iconView.frame = reactionDisplaySize.centered(around: iconFrame.center)
                transition.setAlpha(view: iconView, alpha: contentsAlpha)
            }
            
            if let titleView = self.title.view {
                if titleView.superview == nil {
                    titleView.isUserInteractionEnabled = false
                    self.containerButton.addSubview(titleView)
                }
                titleView.frame = titleFrame
                transition.setAlpha(view: titleView, alpha: contentsAlpha)
            }
            if let counterView = self.counter.view {
                if counterView.superview == nil {
                    counterView.isUserInteractionEnabled = false
                    self.containerButton.addSubview(counterView)
                }
                counterView.frame = counterFrame
                transition.setAlpha(view: counterView, alpha: contentsAlpha)
            }
            
            if theme.overallDarkAppearance {
                self.background.tintColor = isSelected ? theme.list.itemCheckColors.fillColor : UIColor(white: 1.0, alpha: 0.1)
            } else {
                self.background.tintColor = isSelected ? theme.list.itemCheckColors.fillColor : theme.rootController.navigationSearchBar.inputFillColor
            }
            if let image = self.background.image {
                let backgroundFrame = CGRect(origin: CGPoint(x: -6.0, y: floorToScreenPixels((size.height - image.size.height) * 0.5)), size: CGSize(width: size.width + 6.0 + 9.0, height: image.size.height))
                transition.setFrame(view: self.background, frame: backgroundFrame)
            }
            
            transition.setFrame(view: self.containerButton, frame: CGRect(origin: CGPoint(), size: size))
            
            self.extractedContainerNode.frame = CGRect(origin: CGPoint(), size: size)
            self.extractedContainerNode.contentNode.frame = CGRect(origin: CGPoint(), size: size)
            self.extractedContainerNode.contentRect = CGRect(origin: CGPoint(x: 0.0, y: 0.0), size: CGSize(width: size.width, height: size.height))
            self.containerNode.frame = CGRect(origin: CGPoint(), size: size)
            
            return size
        }
    }
    
    private final class ScrollView: UIScrollView {
        override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
            return super.hitTest(point, with: event)
        }
        
        override func touchesShouldCancel(in view: UIView) -> Bool {
            return true
        }
    }
    
    private let context: AccountContext
    
    private let scrollView: ScrollView
    
    private var params: Params?
    
    private var items: [Item] = []
    private var itemViews: [MessageReaction.Reaction: ItemView] = [:]
    private var promoView: PromoView?
    
    private final class LocalButton: UIButton {
        var action: (() -> Void)?
        var longAction: (() -> Void)?
        override init(frame: CGRect) {
            super.init(frame: frame)
            self.addTarget(self, action: #selector(self.pressed), for: .touchUpInside)
            self.addGestureRecognizer(UILongPressGestureRecognizer(target: self, action: #selector(self.held(_:))))
            self.titleLabel?.font = Font.medium(14.0)
            self.layer.cornerRadius = 14.0
        }
        required init?(coder: NSCoder) { preconditionFailure() }
        override func sizeThatFits(_ size: CGSize) -> CGSize {
            let fitted = super.sizeThatFits(size)
            return CGSize(width: fitted.width + 20.0, height: fitted.height + 8.0)
        }
        @objc private func pressed() { self.action?() }
        @objc private func held(_ gesture: UILongPressGestureRecognizer) { if gesture.state == .began { self.longAction?() } }
    }
    private let localEligible: Bool
    private var localService: LocalSavedTagsService?
    private let localCatalogue = MetaDisposable()
    private let localAccounts = MetaDisposable()
    private var localTags: [(id: String, name: String, count: Int32)] = []
    private var localRevision: Int64?
    private var localRenderGate = JerkgramLocalSavedTagsRenderGate()
    private var localButtons: [LocalButton] = []
    private var localItemViews: [String: ItemView] = [:]
    private var localReactionFiles: [(MessageReaction.Reaction, TelegramMediaFile)] = []
    private let localMutation = MetaDisposable()
    private let localPromptLoad = MetaDisposable()
    private weak var localNamePrompt: AlertController?
    private var showingCloudTags = false

    private var itemsDisposable: Disposable?
    
    private var appliedScrollToTag: EngineMemoryBuffer?
    
    init(context: AccountContext, chatLocation: ChatLocation) {
        self.context = context
        self.localEligible = chatLocation.peerId == context.account.peerId && chatLocation.threadId == nil
        
        self.scrollView = ScrollView(frame: CGRect())
        
        super.init()
        
        self.scrollView.delaysContentTouches = false
        self.scrollView.canCancelContentTouches = true
        self.scrollView.clipsToBounds = false
        self.scrollView.contentInsetAdjustmentBehavior = .never
        if #available(iOS 13.0, *) {
            self.scrollView.automaticallyAdjustsScrollIndicatorInsets = false
        }
        self.scrollView.showsVerticalScrollIndicator = false
        self.scrollView.showsHorizontalScrollIndicator = false
        self.scrollView.alwaysBounceHorizontal = false
        self.scrollView.alwaysBounceVertical = false
        self.scrollView.scrollsToTop = false
        self.scrollView.delegate = self.wrappedScrollViewDelegate
        
        self.view.addSubview(self.scrollView)
        
        self.scrollView.disablesInteractiveTransitionGestureRecognizer = true
        
        if self.localEligible {
            let service = LocalSavedTagsService(account: context.account)
            self.localService = service
            self.localCatalogue.set((service.catalogueUpdates() |> deliverOnMainQueue).start(next: { [weak self] result in
                guard let self, self.localService != nil else { return }
                if case .failure = result {
                    self.localNamePrompt?.dismissAnimated(); self.localNamePrompt = nil
                    self.localTags = []; self.localRevision = -1; self.update(transition: .immediate)
                }
                if case let .success(catalogue) = result {
                    self.localTags = catalogue.tags.map { (id: $0.id, name: $0.name, count: $0.count) }
                    self.localRevision = catalogue.revision
                    self.update(transition: .immediate)
                }
            }))
            self.localAccounts.set((context.sharedContext.activeAccountContexts |> deliverOnMainQueue).start(next: { [weak self] value in
                guard let self else { return }
                guard let primary = value.primary, primary.account.id == context.account.id,
                    primary.account.peerId == context.account.peerId,
                    primary.account.testingEnvironment == context.account.testingEnvironment else {
                    self.localNamePrompt?.dismissAnimated(); self.localNamePrompt = nil
                    self.localCatalogue.set(nil); self.localService?.dispose(); self.localService = nil
                    self.localTags = []; self.update(transition: .immediate)
                    return
                }
            }))
        }

        let tagsAndFiles: Signal<([MessageReaction.Reaction: Int], [Int64: TelegramMediaFile]), NoError> = context.engine.data.subscribe(
            TelegramEngine.EngineData.Item.Messages.SavedMessageTagStats(peerId: context.account.peerId, threadId: chatLocation.threadId)
        )
        |> distinctUntilChanged
        |> mapToSignal { tags -> Signal<([MessageReaction.Reaction: Int], [Int64: TelegramMediaFile]), NoError> in
            var customFileIds: [Int64] = []
            for (reaction, _) in tags {
                switch reaction {
                case .builtin:
                    break
                case let .custom(fileId):
                    customFileIds.append(fileId)
                case .stars:
                    break
                }
            }
            
            return context.engine.stickers.resolveInlineStickers(fileIds: customFileIds)
            |> map { files in
                return (tags, files)
            }
        }
        
        var isFirstUpdate = true
        self.itemsDisposable = (combineLatest(
            context.availableReactions,
            context.engine.stickers.savedMessageTagData(),
            tagsAndFiles
        )
        |> deliverOnMainQueue).start(next: { [weak self] availableReactions, savedMessageTags, tagsAndFiles in
            guard let self else {
                return
            }
            self.items.removeAll()
            self.localReactionFiles = (availableReactions?.reactions ?? []).map { ($0.value, $0.selectAnimation._parse()) }
            self.localRenderGate.invalidate()
            
            let (tags, files) = tagsAndFiles
            for (reaction, count) in tags {
                let title = savedMessageTags?.tags.first(where: { $0.reaction == reaction })?.title
                
                switch reaction {
                case .builtin, .stars:
                    if let availableReactions {
                        inner: for availableReaction in availableReactions.reactions {
                            if availableReaction.value == reaction {
                                if let file = availableReaction.centerAnimation {
                                    self.items.append(Item(reaction: reaction, count: count, title: title, file: file._parse()))
                                }
                                break inner
                            }
                        }
                    }
                case let .custom(fileId):
                    if let file = files[fileId] {
                        self.items.append(Item(reaction: reaction, count: count, title: title, file: file))
                    }
                }
            }
            self.items.sort(by: { lhs, rhs in
                if lhs.count != rhs.count {
                    return lhs.count > rhs.count
                }
                return lhs.reaction < rhs.reaction
            })
            self.update(transition: isFirstUpdate ? .immediate : .animated(duration: 0.3, curve: .easeInOut))
            isFirstUpdate = false
        })
    }
    
    deinit {
        if let prompt = self.localNamePrompt { DispatchQueue.main.async { [weak prompt] in prompt?.dismissAnimated() } }
        self.localMutation.dispose(); self.localPromptLoad.dispose()
        self.itemsDisposable?.dispose()
        self.localCatalogue.dispose(); self.localAccounts.dispose(); self.localService?.dispose()
    }
    
    private func update(transition: ContainedViewLayoutTransition) {
        if let params = self.params {
            self.update(params: params, transition: transition)
        }
    }
    
    override func updateLayout(width: CGFloat, leftInset: CGFloat, rightInset: CGFloat, transition: ContainedViewLayoutTransition, interfaceState: ChatPresentationInterfaceState) -> LayoutResult {
        let params = Params(width: width, leftInset: leftInset, rightInset: rightInset, interfaceState: interfaceState)
        if self.params != params {
            self.params = params
            self.update(params: params, transition: transition)
        }
        
        let panelHeight: CGFloat = 40.0
        
        return LayoutResult(backgroundHeight: panelHeight, insetHeight: panelHeight, hitTestSlop: 0.0)
    }
    
    func updateLayout(width: CGFloat, leftInset: CGFloat, rightInset: CGFloat, transition: ContainedViewLayoutTransition, chatController: ChatController) -> LayoutResult {
        return self.updateLayout(width: width, leftInset: leftInset, rightInset: rightInset, transition: transition, interfaceState: (chatController as! ChatControllerImpl).presentationInterfaceState)
    }
    
    private func openLocalTagEditor(id: String?) {
        guard let service = self.localService,
            JerkgramLocalPremiumPolicy.savedTagsEnabled(accountPeerId: self.context.account.peerId.toInt64()) else { return }
        let generation = JerkgramLocalPremiumPolicy.generation
        self.localPromptLoad.set((self.context.availableReactions |> filter { $0 != nil } |> take(1) |> deliverOnMainQueue).start(next: { [weak self, weak service] reactions in
            guard let self, let service, self.localService === service, let params = self.params,
                JerkgramLocalPremiumPolicy.generation == generation,
                let candidate = reactions?.reactions.first(where: { $0.value == .builtin("👍") }) ?? reactions?.reactions.first else { return }
            let reaction = candidate.value
            let file = candidate.selectAnimation._parse()
        let current = self.localTags.first(where: { $0.id == id })
        let prompt = savedTagNameAlertController(context: self.context,
            text: id == nil ? params.interfaceState.strings.Chat_EditTagTitle_TitleSet : params.interfaceState.strings.Chat_EditTagTitle_TitleEdit,
            subtext: params.interfaceState.strings.Chat_EditTagTitle_Text,
            value: current?.name ?? "", reaction: reaction, file: file, characterLimit: 64,
            apply: { [weak self, weak service] name in
                guard let self, let service, self.localService === service, let name,
                    JerkgramLocalPremiumPolicy.generation == generation else { return }
                let mutation: Signal<Result<Int64, LocalSavedTagsError>, NoError>
                if let id { mutation = service.rename(tagId: id, name: name) }
                else { mutation = service.create(name: name) |> map { $0.map { _ in Int64(0) } } }
                self.localMutation.set((mutation |> deliverOnMainQueue).start(next: { [weak self] result in
                    if case let .failure(error) = result { self?.presentLocalTagError(error) }
                }))
            })
        self.localNamePrompt = prompt
        self.interfaceInteraction?.presentController(prompt, nil)
        }))
    }

    private func presentLocalTagError(_ error: LocalSavedTagsError) {
        guard let params = self.params else { return }
        self.interfaceInteraction?.presentController(textAlertController(context: self.context, title: nil,
            text: JerkgramSavedTagsStrings(params.interfaceState.strings).error(error),
            actions: [TextAlertAction(type: .defaultAction, title: params.interfaceState.strings.Common_OK, action: {})]), nil)
    }

    private func updateLocalSavedTags(params: Params) {
        let key = JerkgramLocalSavedTagsRenderKey(revision: self.localRevision,
            selectedId: params.interfaceState.historyFilter?.localSavedTagId,
            theme: ObjectIdentifier(params.interfaceState.theme), strings: ObjectIdentifier(params.interfaceState.strings),
            width: params.width, leftInset: params.leftInset, rightInset: params.rightInset, available: self.localService != nil)
        guard self.localRenderGate.update(key) else { return }
        self.promoView?.removeFromSuperview(); self.promoView = nil
        for view in self.itemViews.values { view.isHidden = true }
        for button in self.localButtons { button.removeFromSuperview() }; self.localButtons.removeAll()
        var valid: Set<String> = []
        var x = params.leftInset + 16.0
        let selected = params.interfaceState.historyFilter?.localSavedTagId
        func add(id: String, item: Item, action: @escaping () -> Void) {
            valid.insert(id)
            let view: ItemView
            if let current = self.localItemViews[id] { view = current }
            else {
                view = ItemView(context: self.context, action: action, contextGesture: { [weak self] gesture, source in
                    guard let self, let interaction = self.interfaceInteraction,
                        let controller = interaction.chatController(), id != "+", id != "cloud" else { gesture.cancel(); return }
                    let presentation = self.context.sharedContext.currentPresentationData.with { $0 }
                    let items: [ContextMenuItem] = [
                        .action(ContextMenuActionItem(text: presentation.strings.Chat_ReactionContextMenu_EditTagLabel, icon: { theme in generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/TagEditName"), color: theme.contextMenu.primaryColor) }, action: { [weak self] c, done in
                            c?.dismiss(completion: { self?.openLocalTagEditor(id: id) })
                        })),
                        .action(ContextMenuActionItem(text: presentation.strings.Common_Delete, textColor: .destructive, icon: { _ in nil }, action: { [weak self] _, done in
                            done(.default)
                            guard let self, let service = self.localService else { return }
                            self.localMutation.set((service.delete(tagId: id) |> deliverOnMainQueue).start(next: { [weak self] result in
                                if case let .failure(error) = result { self?.presentLocalTagError(error) }
                            }))
                        }))
                    ]
                    let menu = makeContextController(presentationData: presentation, source: .extracted(TagContextExtractedContentSource(controller: controller, sourceNode: source, keepInPlace: false)), items: .single(ContextController.Items(content: .list(items))), recognizer: nil, gesture: gesture)
                    interaction.presentGlobalOverlayController(menu, nil)
                })
                self.localItemViews[id] = view; self.scrollView.addSubview(view)
            }
            view.isHidden = false
            let size = view.update(item: item, isSelected: selected == id, isLocked: false, theme: params.interfaceState.theme, height: 40.0, transition: .immediate)
            view.frame = CGRect(origin: CGPoint(x: x, y: 0.0), size: size)
            x += size.width + 24.0
        }
        let strings = JerkgramSavedTagsStrings(params.interfaceState.strings)
        add(id: "+", item: Item(reaction: .builtin("+"), count: -1, title: strings.text("Tag", "Тег"), file: nil), action: { [weak self] in self?.openLocalTagEditor(id: nil) })
        for tag in self.localTags {
            let emoji = String(tag.name.first ?? "🏷")
            let reaction = MessageReaction.Reaction.builtin(emoji)
            let file = self.localReactionFiles.first(where: { $0.0 == reaction })?.1
            let title = file == nil ? tag.name : String(tag.name.dropFirst()).trimmingCharacters(in: .whitespaces)
            add(id: tag.id, item: Item(reaction: file == nil ? .builtin("🏷") : reaction, count: Int(tag.count), title: title, file: file), action: { [weak self] in
                guard let self, self.localService != nil,
                    JerkgramLocalPremiumPolicy.savedTagsEnabled(accountPeerId: self.context.account.peerId.toInt64()) else { return }
                self.interfaceInteraction?.updateHistoryFilter { filter in
                    filter?.localSavedTagId == tag.id ? nil : ChatPresentationInterfaceState.HistoryFilter(localSavedTagId: tag.id)
                }
            })
        }
        if params.interfaceState.isPremium {
            add(id: "cloud", item: Item(reaction: .builtin("☁"), count: -1, title: strings.text("Telegram tags", "Теги Telegram"), file: nil), action: { [weak self] in
                guard let self else { return }
                self.showingCloudTags = true
                self.interfaceInteraction?.updateHistoryFilter { _ in nil }
                self.update(transition: .immediate)
            })
        }
        for id in Array(self.localItemViews.keys) where !valid.contains(id) { self.localItemViews.removeValue(forKey: id)?.removeFromSuperview() }
        self.scrollView.frame = CGRect(x: 0, y: 0, width: params.width, height: 40)
        self.scrollView.contentSize = CGSize(width: x + params.rightInset, height: 40)
    }

    private func update(params: Params, transition: ContainedViewLayoutTransition) {
        if self.localEligible && params.interfaceState.hasLocalSavedTags && !self.showingCloudTags {
            self.updateLocalSavedTags(params: params)
            return
        }
        self.localRenderGate.invalidate()
        for view in self.localItemViews.values { view.isHidden = true }
        for button in self.localButtons { button.removeFromSuperview() }
        self.localButtons.removeAll()
        for view in self.itemViews.values { view.isHidden = false }

        let panelHeight: CGFloat = 40.0
        
        let containerInsets = UIEdgeInsets(top: 0.0, left: params.leftInset + 16.0, bottom: 0.0, right: params.rightInset + 16.0)
        let itemSpacing: CGFloat = 24.0
        
        var contentSize = CGSize(width: 0.0, height: panelHeight)
        contentSize.width += containerInsets.left
        if self.localEligible && params.interfaceState.hasLocalSavedTags {
            let button = LocalButton(frame: CGRect(x: contentSize.width, y: 5.0, width: 86.0, height: 30.0))
            button.setTitle(JerkgramSavedTagsStrings(params.interfaceState.strings).title, for: .normal)
            button.setTitleColor(params.interfaceState.theme.list.itemAccentColor, for: .normal)
            button.action = { [weak self] in
                guard let self else { return }
                self.showingCloudTags = false; self.update(transition: .immediate)
            }
            self.scrollView.addSubview(button); self.localButtons.append(button)
            contentSize.width += 98.0
        }
        
        var validIds: [MessageReaction.Reaction] = []
        
        let hadItemViews = !self.itemViews.isEmpty
        var isFirst = true
        
        if !params.interfaceState.isPremium {
            let promoView: PromoView
            var itemTransition = transition
            if let current = self.promoView {
                promoView = current
            } else {
                itemTransition = .immediate
                promoView = PromoView(action: { [weak self] in
                    guard let self, let interfaceInteraction = self.interfaceInteraction else {
                        return
                    }
                    (interfaceInteraction.chatController() as? ChatControllerImpl)?.presentTagPremiumPaywall()
                })
                self.promoView = promoView
                self.scrollView.addSubview(promoView)
            }
            
            let itemSize = promoView.update(theme: params.interfaceState.theme, strings: params.interfaceState.strings, height: panelHeight, isUnlock: !self.items.isEmpty, transition: .immediate)
            let itemFrame = CGRect(origin: CGPoint(x: contentSize.width, y: 0.0), size: itemSize)
            
            itemTransition.updatePosition(layer: promoView.layer, position: itemFrame.center)
            promoView.bounds = CGRect(origin: CGPoint(), size: itemFrame.size)
            
            contentSize.width += itemSize.width
            
            isFirst = false
        } else {
            if let promoView = self.promoView {
                self.promoView = nil
                promoView.removeFromSuperview()
            }
        }
            
        for item in self.items {
            if isFirst {
                isFirst = false
            } else {
                contentSize.width += itemSpacing
            }
            let itemId = item.reaction
            validIds.append(itemId)
            
            var itemTransition = transition
            var animateIn = false
            let itemView: ItemView
            if let current = self.itemViews[itemId] {
                itemView = current
            } else {
                itemTransition = .immediate
                animateIn = true
                let reaction = item.reaction
                itemView = ItemView(context: self.context, action: { [weak self] in
                    guard let self, let params = self.params else {
                        return
                    }
                    
                    if !params.interfaceState.isPremium {
                        if let chatController = self.interfaceInteraction?.chatController() {
                            (chatController as? ChatControllerImpl)?.presentTagPremiumPaywall()
                        }
                        return
                    }
                    
                    let tag = ReactionsMessageAttribute.messageTag(reaction: reaction)
                    
                    var updatedFilter: ChatPresentationInterfaceState.HistoryFilter?
                    let currentTag = params.interfaceState.historyFilter?.customTag
                    if currentTag == tag {
                        updatedFilter = nil
                    } else {
                        updatedFilter = ChatPresentationInterfaceState.HistoryFilter(customTag: tag, isActive: true)
                    }
                    
                    self.interfaceInteraction?.updateHistoryFilter({ filter in
                        return updatedFilter
                    })
                }, contextGesture: { [weak self] gesture, sourceNode in
                    guard let self, let params = self.params, let interfaceInteraction = self.interfaceInteraction, let chatController = interfaceInteraction.chatController() else {
                        gesture.cancel()
                        return
                    }
                    guard let item = self.items.first(where: { $0.reaction == reaction }) else {
                        gesture.cancel()
                        return
                    }
                    
                    if !params.interfaceState.isPremium {
                        (chatController as? ChatControllerImpl)?.presentTagPremiumPaywall()
                        return
                    }
                    
                    var items: [ContextMenuItem] = []
                    
                    let presentationData = self.context.sharedContext.currentPresentationData.with({ $0 })
                    items.append(.action(ContextMenuActionItem(text: item.title != nil ? presentationData.strings.Chat_ReactionContextMenu_EditTagLabel : presentationData.strings.Chat_ReactionContextMenu_SetTagLabel, icon: { theme in
                        return generateTintedImage(image: UIImage(bundleImageName: "Chat/Context Menu/TagEditName"), color: theme.contextMenu.primaryColor)
                    }, action: { [weak self] c, a in
                        guard let self else {
                            a(.default)
                            return
                        }
                        
                        c?.dismiss(completion: { [weak self] in
                            guard let self, let item = self.items.first(where: { $0.reaction == reaction }) else {
                                return
                            }
                            self.openEditTagTitle(reaction: reaction, hasTitle: item.title != nil)
                        })
                    })))
                    
                    let controller = makeContextController(presentationData: presentationData, source: .extracted(TagContextExtractedContentSource(controller: chatController, sourceNode: sourceNode, keepInPlace: false)), items: .single(ContextController.Items(content: .list(items))), recognizer: nil, gesture: gesture)
                    interfaceInteraction.presentGlobalOverlayController(controller, nil)
                })
                self.itemViews[itemId] = itemView
                self.scrollView.addSubview(itemView)
            }
                
            var isSelected = false
            if let historyFilter = params.interfaceState.historyFilter {
                if historyFilter.customTag == ReactionsMessageAttribute.messageTag(reaction: item.reaction) {
                    isSelected = true
                }
            }
            let itemSize = itemView.update(item: item, isSelected: isSelected, isLocked: !params.interfaceState.isPremium, theme: params.interfaceState.theme, height: panelHeight, transition: .immediate)
            let itemFrame = CGRect(origin: CGPoint(x: contentSize.width, y: 0.0), size: itemSize)
            
            itemTransition.updatePosition(layer: itemView.layer, position: itemFrame.center)
            itemTransition.updateBounds(layer: itemView.layer, bounds: CGRect(origin: CGPoint(), size: itemFrame.size))
            
            if animateIn && transition.isAnimated {
                itemView.layer.animateAlpha(from: 0.0, to: itemView.alpha, duration: 0.15)
                transition.animateTransformScale(view: itemView, from: 0.001)
            }
            
            contentSize.width += itemSize.width
        }
        var removedIds: [MessageReaction.Reaction] = []
        for (id, itemView) in self.itemViews {
            if !validIds.contains(id) {
                removedIds.append(id)
                
                if transition.isAnimated {
                    itemView.layer.animateAlpha(from: 1.0, to: 0.0, duration: 0.18, removeOnCompletion: false, completion: { [weak itemView] _ in
                        itemView?.removeFromSuperview()
                    })
                    transition.updateTransformScale(layer: itemView.layer, scale: 0.001)
                } else {
                    itemView.removeFromSuperview()
                }
            }
        }
        for id in removedIds {
            self.itemViews.removeValue(forKey: id)
        }
        
        contentSize.width += containerInsets.right
        
        let scrollSize = CGSize(width: params.width, height: contentSize.height)
        if self.scrollView.bounds.size != scrollSize {
            self.scrollView.frame = CGRect(origin: CGPoint(x: 0.0, y: 0.0), size: scrollSize)
        }
        if self.scrollView.contentSize != contentSize {
            self.scrollView.contentSize = contentSize
        }
        
        let currentFilterTag = params.interfaceState.historyFilter?.customTag
        if self.appliedScrollToTag != currentFilterTag {
            if let tag = currentFilterTag {
                if let reaction = ReactionsMessageAttribute.reactionFromMessageTag(tag: tag), let itemView = self.itemViews[reaction] {
                    self.appliedScrollToTag = currentFilterTag
                    self.scrollView.scrollRectToVisible(itemView.frame.insetBy(dx: -46.0, dy: 0.0), animated: hadItemViews)
                }
            } else {
                self.appliedScrollToTag = currentFilterTag
            }
        }
    }
    
    private func openEditTagTitle(reaction: MessageReaction.Reaction, hasTitle: Bool) {
        let presentationData = self.context.sharedContext.currentPresentationData.with { $0 }
        
        let optionTitle = hasTitle ? presentationData.strings.Chat_EditTagTitle_TitleEdit : presentationData.strings.Chat_EditTagTitle_TitleSet
        
        let reactionFile: Signal<TelegramMediaFile?, NoError>
        switch reaction {
        case .builtin, .stars:
            reactionFile = self.context.engine.stickers.availableReactions()
            |> take(1)
            |> map { availableReactions -> TelegramMediaFile? in
                return availableReactions?.reactions.first(where: { $0.value == reaction })?.selectAnimation._parse()
            }
        case let .custom(fileId):
            reactionFile = self.context.engine.stickers.resolveInlineStickers(fileIds: [fileId])
            |> map { files -> TelegramMediaFile? in
                return files.values.first
            }
        }
        
        let _ = (combineLatest(
            self.context.engine.stickers.savedMessageTagData(),
            reactionFile
        )
        |> take(1)
        |> deliverOnMainQueue).start(next: { [weak self] savedMessageTags, reactionFile in
            guard let self, let reactionFile else {
                return
            }
            
            let promptController = savedTagNameAlertController(context: self.context, updatedPresentationData: nil, text: optionTitle, subtext: presentationData.strings.Chat_EditTagTitle_Text, value: savedMessageTags?.tags.first(where: { $0.reaction == reaction })?.title ?? "", reaction: reaction, file: reactionFile, characterLimit: 12, apply: { [weak self] value in
                guard let self else {
                    return
                }
                
                if let value {
                    let _ = self.context.engine.stickers.setSavedMessageTagTitle(reaction: reaction, title: value.isEmpty ? nil : value).start()
                }
            })
            self.interfaceInteraction?.presentController(promptController, nil)
        })
    }
}

private final class TagContextExtractedContentSource: ContextExtractedContentSource {
    let keepInPlace: Bool
    let ignoreContentTouches: Bool = true
    let blurBackground: Bool = true
    let actionsHorizontalAlignment: ContextActionsHorizontalAlignment = .center
    
    private let controller: ViewController
    private let sourceNode: ContextExtractedContentContainingNode
    
    init(controller: ViewController, sourceNode: ContextExtractedContentContainingNode, keepInPlace: Bool) {
        self.controller = controller
        self.sourceNode = sourceNode
        self.keepInPlace = keepInPlace
    }
    
    func takeView() -> ContextControllerTakeViewInfo? {
        return ContextControllerTakeViewInfo(containingItem: .node(self.sourceNode), contentAreaInScreenSpace: mainWindowScreenBounds)
    }
    
    func putBack() -> ContextControllerPutBackViewInfo? {
        return ContextControllerPutBackViewInfo(contentAreaInScreenSpace: mainWindowScreenBounds)
    }
}
