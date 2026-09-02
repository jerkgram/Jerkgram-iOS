import Foundation
import UIKit
import Darwin
import Display
import AsyncDisplayKit
import TelegramCore
import SwiftSignalKit
import TelegramPresentationData
import AccountContext
import ContactListUI
import CallListUI
import ChatListUI
import SettingsUI
import AppBundle
import DatePickerNode
import DebugSettingsUI
import TabBarUI
import WallpaperBackgroundNode
import ChatPresentationInterfaceState
import CameraScreen
import MediaEditorScreen
import LegacyComponents
import LegacyMediaPickerUI
import LegacyCamera
import AvatarNode
import LocalMediaResources
import ImageCompression
import TextFormat
import MediaEditor
import PeerInfoScreen
import PeerInfoStoryGridScreen
import ShareWithPeersScreen
import ChatEmptyNode

private class DetailsChatPlaceholderNode: ASDisplayNode, NavigationDetailsPlaceholderNode {
    private var presentationData: PresentationData
    private var presentationInterfaceState: ChatPresentationInterfaceState
    
    let wallpaperBackgroundNode: WallpaperBackgroundNode
    let emptyNode: ChatEmptyNode
    
    init(context: AccountContext) {
        self.presentationData = context.sharedContext.currentPresentationData.with { $0 }
        self.presentationInterfaceState = ChatPresentationInterfaceState(chatWallpaper: self.presentationData.chatWallpaper, theme: self.presentationData.theme, preferredGlassType: .default, strings: self.presentationData.strings, dateTimeFormat: self.presentationData.dateTimeFormat, nameDisplayOrder: self.presentationData.nameDisplayOrder, limitsConfiguration: context.currentLimitsConfiguration.with { $0 }, fontSize: self.presentationData.chatFontSize, bubbleCorners: self.presentationData.chatBubbleCorners, accountPeerId: context.account.peerId, mode: .standard(.default), chatLocation: .peer(id: context.account.peerId), subject: nil, greetingData: nil, pendingUnpinnedAllMessages: false, activeGroupCallInfo: nil, hasActiveGroupCall: false, threadData: nil, isGeneralThreadClosed: nil, replyMessage: nil, accountPeerColor: nil, businessIntro: nil)
        
        self.wallpaperBackgroundNode = createWallpaperBackgroundNode(context: context, forChatDisplay: true, useSharedAnimationPhase: true)
        self.emptyNode = ChatEmptyNode(context: context, interaction: nil)
        
        super.init()
        
        self.addSubnode(self.wallpaperBackgroundNode)
        self.addSubnode(self.emptyNode)
    }
    
    func updatePresentationData(_ presentationData: PresentationData) {
        self.presentationData = presentationData
        let preferredGlassType = self.presentationInterfaceState.preferredGlassType
        self.presentationInterfaceState = ChatPresentationInterfaceState(chatWallpaper: self.presentationData.chatWallpaper, theme: self.presentationData.theme, preferredGlassType: preferredGlassType, strings: self.presentationData.strings, dateTimeFormat: self.presentationData.dateTimeFormat, nameDisplayOrder: self.presentationData.nameDisplayOrder, limitsConfiguration: self.presentationInterfaceState.limitsConfiguration, fontSize: self.presentationData.chatFontSize, bubbleCorners: self.presentationData.chatBubbleCorners, accountPeerId: self.presentationInterfaceState.accountPeerId, mode: .standard(.default), chatLocation: self.presentationInterfaceState.chatLocation, subject: nil, greetingData: nil, pendingUnpinnedAllMessages: false, activeGroupCallInfo: nil, hasActiveGroupCall: false, threadData: nil, isGeneralThreadClosed: nil, replyMessage: nil, accountPeerColor: nil, businessIntro: nil)
        
        self.wallpaperBackgroundNode.update(wallpaper: presentationData.chatWallpaper, animated: false)
    }
    
    func updateLayout(size: CGSize, needsTiling: Bool, transition: ContainedViewLayoutTransition) {
        let contentBounds = CGRect(origin: .zero, size: size)
        self.wallpaperBackgroundNode.updateLayout(size: size, displayMode: needsTiling ? .aspectFit : .aspectFill, transition: transition)
        transition.updateFrame(node: self.wallpaperBackgroundNode, frame: contentBounds)
        
        self.emptyNode.updateLayout(interfaceState: self.presentationInterfaceState, subject: .detailsPlaceholder, loadingNode: nil, backgroundNode: self.wallpaperBackgroundNode, size: contentBounds.size, insets: .zero, leftInset: 0.0, rightInset: 0.0, transition: transition)
        transition.updateFrame(node: self.emptyNode, frame: CGRect(origin: .zero, size: size))
        self.emptyNode.update(rect: contentBounds, within: contentBounds.size, transition: transition)
    }
}

public final class TelegramRootController: NavigationController, TelegramRootControllerInterface {
    private let context: AccountContext
    
    public var rootTabController: TabBarController?
    
    public var contactsController: ContactsController?
    public var callListController: CallListController?
    public var chatListController: ChatListController?
    public var accountSettingsController: PeerInfoScreen?
    
    private var permissionsDisposable: Disposable?
    private var presentationDataDisposable: Disposable?
    private var presentationData: PresentationData
    
    private var detailsPlaceholderNode: DetailsChatPlaceholderNode?
    
    private var applicationInFocusDisposable: Disposable?
    private var storyUploadEventsDisposable: Disposable?

    // MARK: GhostBase v1.1R RAM_OVERLAY1
    private var ghostBaseRamLabel: UILabel?
    private var ghostBaseRamTimer: Foundation.Timer?
    private var ghostBaseRamDefaultsObserver: NSObjectProtocol?
    private var ghostBaseRamActiveObserver: NSObjectProtocol?
    private var ghostBaseRamInactiveObserver: NSObjectProtocol?
    private var ghostBaseRamLayout: ContainerViewLayout?
    
    override public var minimizedContainer: MinimizedContainer? {
        didSet {
            self.minimizedContainer?.navigationController = self
            self.minimizedContainerUpdated(self.minimizedContainer)
        }
    }
    
    public var minimizedContainerUpdated: (MinimizedContainer?) -> Void = { _ in }
        
    public init(context: AccountContext) {
        self.context = context
        
        self.presentationData = context.sharedContext.currentPresentationData.with { $0 }
        
        super.init(mode: .automaticMasterDetail, theme: NavigationControllerTheme(presentationTheme: self.presentationData.theme))
        
        self.presentationDataDisposable = (context.sharedContext.presentationData
        |> deliverOnMainQueue).startStrict(next: { [weak self] presentationData in
            if let strongSelf = self {
                strongSelf.detailsPlaceholderNode?.updatePresentationData(presentationData)
                
                let previousTheme = strongSelf.presentationData.theme
                strongSelf.presentationData = presentationData
                if previousTheme !== presentationData.theme {
                    (strongSelf.rootTabController as? TabBarControllerImpl)?.updateTheme(theme: presentationData.theme)
                    strongSelf.rootTabController?.statusBar.statusBarStyle = presentationData.theme.rootController.statusBarStyle.style
                }
            }
        })
        
        if context.sharedContext.applicationBindings.isMainApp {
            self.applicationInFocusDisposable = (context.sharedContext.applicationBindings.applicationIsActive
            |> distinctUntilChanged
            |> deliverOn(Queue.mainQueue())).startStrict(next: { value in
                context.sharedContext.mainWindow?.setForceBadgeHidden(!value)
            })
            
            self.storyUploadEventsDisposable = (context.engine.messages.allStoriesUploadEvents()
            |> deliverOnMainQueue).startStrict(next: { [weak self] event in
                guard let self else {
                    return
                }
                let (stableId, id) = event
                moveStorySource(engine: self.context.engine, peerId: self.context.account.peerId, from: Int64(stableId), to: Int64(id))
            })
        }
    
        self.ghostBaseSetupRamOverlay()
    }
    
    required public init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    deinit {
        self.permissionsDisposable?.dispose()
        self.presentationDataDisposable?.dispose()
        self.applicationInFocusDisposable?.dispose()
        self.storyUploadEventsDisposable?.dispose()
        self.ghostBaseRamTimer?.invalidate()
        if let observer = self.ghostBaseRamDefaultsObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = self.ghostBaseRamActiveObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        if let observer = self.ghostBaseRamInactiveObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    private static let ghostBaseRamEnabledKey =
        "jerkgram.Appearance.ShowRamUnderClock"

    private func ghostBaseSetupRamOverlay() {
        self.ghostBaseRamDefaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: UserDefaults.standard,
            queue: .main,
            using: { [weak self] _ in
                self?.ghostBaseUpdateRamOverlayState()
            }
        )
        self.ghostBaseRamActiveObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main,
            using: { [weak self] _ in
                self?.ghostBaseUpdateRamOverlayState()
            }
        )
        self.ghostBaseRamInactiveObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.willResignActiveNotification,
            object: nil,
            queue: .main,
            using: { [weak self] _ in
                self?.ghostBaseUpdateRamOverlayState(forceInactive: true)
            }
        )
        self.ghostBaseUpdateRamOverlayState()
    }

    private func ghostBaseUpdateRamOverlayState(forceInactive: Bool = false) {
        let enabled = (
            UserDefaults.standard.object(
                forKey: Self.ghostBaseRamEnabledKey
            ) as? Bool
        ) ?? false
        let active = !forceInactive && UIApplication.shared.applicationState == .active

        guard enabled && active else {
            self.ghostBaseRamTimer?.invalidate()
            self.ghostBaseRamTimer = nil
            self.ghostBaseRamLabel?.removeFromSuperview()
            self.ghostBaseRamLabel = nil
            return
        }

        let label: UILabel
        if let current = self.ghostBaseRamLabel {
            label = current
        } else {
            label = UILabel()
            label.isUserInteractionEnabled = false
            label.backgroundColor = .clear
            label.font = UIFont.monospacedDigitSystemFont(
                ofSize: 8.5,
                weight: .semibold
            )
            label.textAlignment = .left
            label.adjustsFontSizeToFitWidth = false
            self.view.addSubview(label)
            self.ghostBaseRamLabel = label
        }

        label.textColor = self.presentationData.theme.overallDarkAppearance
            ? UIColor.white.withAlphaComponent(0.78)
            : UIColor.black.withAlphaComponent(0.68)

        if self.ghostBaseRamTimer == nil {
            let timer = Foundation.Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
                self?.ghostBaseUpdateRamValue()
            }
            RunLoop.main.add(timer, forMode: .common)
            self.ghostBaseRamTimer = timer
        }

        self.ghostBaseUpdateRamValue()
        self.ghostBaseLayoutRamLabel()
        self.view.bringSubviewToFront(label)
    }

    private func ghostBaseCurrentMemoryFootprint() -> UInt64? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(
                to: integer_t.self,
                capacity: Int(count)
            ) {
                task_info(
                    mach_task_self_,
                    task_flavor_t(TASK_VM_INFO),
                    $0,
                    &count
                )
            }
        }
        guard result == KERN_SUCCESS else {
            return nil
        }
        return info.phys_footprint
    }

    private func ghostBaseUpdateRamValue() {
        guard let label = self.ghostBaseRamLabel else {
            return
        }
        if let bytes = self.ghostBaseCurrentMemoryFootprint() {
            let megabytes = Int((bytes + 524_288) / 1_048_576)
            label.text = "RAM \(megabytes) MB"
        } else {
            label.text = "RAM —"
        }
    }

    private func ghostBaseLayoutRamLabel() {
        guard let label = self.ghostBaseRamLabel,
              let layout = self.ghostBaseRamLayout else {
            return
        }
        let statusHeight = max(
            layout.statusBarHeight ?? 0.0,
            layout.safeInsets.top
        )
        let height: CGFloat = 11.0
        let y: CGFloat
        if statusHeight >= 40.0 {
            y = max(0.0, statusHeight - height - 2.0)
        } else {
            y = statusHeight + 1.0
        }
        label.frame = CGRect(
            x: max(6.0, layout.safeInsets.left + 6.0),
            y: y,
            width: 76.0,
            height: height
        )
    }

    public func getContactsController() -> ViewController? {
        return self.contactsController
    }
    
    public func getChatsController() -> ViewController? {
        return self.chatListController
    }
    
    public func getSettingsController() -> ViewController? {
        return self.accountSettingsController
    }
    
    public func getPrivacySettings() -> Promise<AccountPrivacySettings?>? {
        return self.accountSettingsController?.privacySettings
    }
    
    public func getTwoStepAuthData() -> Promise<TwoStepAuthData?>? {
        return self.accountSettingsController?.twoStepAuthData
    }
    
    public func getNotificationExceptions() -> Promise<NotificationExceptionsList?>? {
        return self.accountSettingsController?.notificationExceptions
    }
    
    override public func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        let needsRootWallpaperBackgroundNode: Bool
        if case .regular = layout.metrics.widthClass {
            needsRootWallpaperBackgroundNode = true
        } else {
            needsRootWallpaperBackgroundNode = false
        }
        
        if needsRootWallpaperBackgroundNode {
            let detailsPlaceholderNode: DetailsChatPlaceholderNode
            if let current = self.detailsPlaceholderNode {
                detailsPlaceholderNode = current
            } else {
                detailsPlaceholderNode = DetailsChatPlaceholderNode(context: self.context)
                detailsPlaceholderNode.wallpaperBackgroundNode.update(wallpaper: self.presentationData.chatWallpaper, animated: false)
                self.detailsPlaceholderNode = detailsPlaceholderNode
            }
            self.updateDetailsPlaceholderNode(detailsPlaceholderNode)
        } else if let _ = self.detailsPlaceholderNode {
            self.detailsPlaceholderNode = nil
            self.updateDetailsPlaceholderNode(nil)
        }
    
        super.containerLayoutUpdated(layout, transition: transition)
        self.ghostBaseRamLayout = layout
        self.ghostBaseUpdateRamOverlayState()
        self.ghostBaseLayoutRamLabel()
    }
    
    public func addRootControllers(showCallsTab: Bool) {
        let tabBarController = TabBarControllerImpl(theme: self.presentationData.theme, strings: self.presentationData.strings)
        tabBarController.navigationPresentation = .master
        let chatListController = self.context.sharedContext.makeChatListController(context: self.context, location: .chatList(groupId: .root), controlsHistoryPreload: true, hideNetworkActivityStatus: false, previewing: false, enableDebugActions: !GlobalExperimentalSettings.isAppStoreBuild)
        if let sharedContext = self.context.sharedContext as? SharedAccountContextImpl {
            chatListController.tabBarItem.badgeValue = sharedContext.switchingData.chatListBadge
        }
        let callListController = CallListController(context: self.context, mode: .tab)
        
        var controllers: [ViewController] = []
        
        let contactsController = ContactsController(context: self.context)
        contactsController.switchToChatsController = {  [weak self] in
            self?.openChatsController(activateSearch: false)
        }
        controllers.append(contactsController)
        
        if showCallsTab {
            controllers.append(callListController)
        }
        controllers.append(chatListController)
        
        var restoreSettignsController: (ViewController & SettingsController)?
        if let sharedContext = self.context.sharedContext as? SharedAccountContextImpl {
            restoreSettignsController = sharedContext.switchingData.settingsController
        }
        restoreSettignsController?.updateContext(context: self.context)
        if let sharedContext = self.context.sharedContext as? SharedAccountContextImpl {
            sharedContext.switchingData = (nil, nil, nil)
        }
        
        let accountSettingsController = PeerInfoScreenImpl(context: self.context, updatedPresentationData: nil, peerId: self.context.account.peerId, avatarInitiallyExpanded: false, isOpenedFromChat: false, reactionSourceMessageId: nil, callMessages: [], isSettings: true)
        accountSettingsController.tabBarItemDebugTapAction = { [weak self] in
            guard let strongSelf = self else {
                return
            }
            strongSelf.pushViewController(debugController(sharedContext: strongSelf.context.sharedContext, context: strongSelf.context))
        }
        accountSettingsController.parentController = self
        controllers.append(accountSettingsController)
                
        tabBarController.setControllers(controllers, selectedIndex: restoreSettignsController != nil ? (controllers.count - 1) : (controllers.count - 2))
        
        self.contactsController = contactsController
        self.callListController = callListController
        self.chatListController = chatListController
        self.accountSettingsController = accountSettingsController
        self.rootTabController = tabBarController
        self.pushViewController(tabBarController, animated: false)
    }
        
    public func updateRootControllers(showCallsTab: Bool) {
        guard let rootTabController = self.rootTabController as? TabBarControllerImpl else {
            return
        }
        var controllers: [ViewController] = []
        controllers.append(self.contactsController!)
        if showCallsTab {
            controllers.append(self.callListController!)
        }
        controllers.append(self.chatListController!)
        controllers.append(self.accountSettingsController!)
        
        rootTabController.setControllers(controllers, selectedIndex: nil)
    }
    
    public func openChatsController(activateSearch: Bool, filter: ChatListSearchFilter = .chats, query: String? = nil) {
        guard let rootTabController = self.rootTabController else {
            return
        }
        
        if activateSearch {
            self.popToRoot(animated: false)
        }
        
        if let index = rootTabController.controllers.firstIndex(where: { $0 is ChatListController}) {
            rootTabController.selectedIndex = index
        }
        
        if activateSearch {
            self.chatListController?.activateSearch(filter: filter, query: query)
        }
    }
    
    public func openRootCompose() {
        self.chatListController?.activateCompose()
    }
    
    public func openRootCamera() {
        guard let controller = self.viewControllers.last as? ViewController else {
            return
        }
        controller.view.endEditing(true)
        presentedLegacyShortcutCamera(context: self.context, saveCapturedMedia: false, saveEditedPhotos: false, mediaGrouping: true, parentController: controller)
    }
    
    public func openAppIcon() {
        guard let rootTabController = self.rootTabController else {
            return
        }
        
        self.popToRoot(animated: false)
        
        if let index = rootTabController.controllers.firstIndex(where: { $0 is PeerInfoScreenImpl }) {
            rootTabController.selectedIndex = index
        }
        
        let themeController = themeSettingsController(context: self.context, focusOnItemTag: .icon)
        var controllers: [UIViewController] = Array(self.viewControllers.prefix(1))
        controllers.append(themeController)
        self.setViewControllers(controllers, animated: true)
    }
    
    @discardableResult
    public func openStoryCamera(mode: StoryCameraMode, customTarget: Stories.PendingTarget?, resumeLiveStream: Bool, transitionIn: StoryCameraTransitionIn?, transitionedIn: @escaping () -> Void, transitionOut: @escaping (Stories.PendingTarget?, Bool) -> StoryCameraTransitionOut?) -> StoryCameraTransitionInCoordinator? {
        guard let controller = self.viewControllers.last as? ViewController else {
            return nil
        }
        controller.view.endEditing(true)
        
        let context = self.context
        
        let externalState = MediaEditorTransitionOutExternalState(
            storyTarget: nil,
            isForcedTarget: customTarget != nil,
            isPeerArchived: false,
            transitionOut: nil
        )
        
        let mediaEditorCustomTarget = customTarget.flatMap { value -> EnginePeer.Id? in
            switch value {
            case .myStories:
                return nil
            case let .peer(id):
                return id
            case let .botPreview(id, _):
                return id
            }
        }
        
        let cameraMode: CameraScreenImpl.CameraMode
        switch mode {
        case .photo:
            cameraMode = .photo
        case .video:
            cameraMode = .video
        case .live:
            cameraMode = .live
        }
        
        var presentImpl: ((ViewController) -> Void)?
        var returnToCameraImpl: (() -> Void)?
        var dismissCameraImpl: (() -> Void)?
        var showDraftTooltipImpl: (() -> Void)?
        let cameraController = CameraScreenImpl(
            context: context,
            mode: .story,
            cameraMode: cameraMode,
            customTarget: mediaEditorCustomTarget,
            resumeLiveStream: resumeLiveStream,
            transitionIn: transitionIn.flatMap {
                if let sourceView = $0.sourceView {
                    return CameraScreenImpl.TransitionIn(
                        sourceView: sourceView,
                        sourceRect: $0.sourceRect,
                        sourceCornerRadius: $0.sourceCornerRadius,
                        useFillAnimation: $0.useFillAnimation
                    )
                } else {
                    return nil
                }
            },
            transitionOut: { finished in
                if let transitionOut = (externalState.transitionOut ?? transitionOut)(finished ? externalState.storyTarget : nil, externalState.isPeerArchived), let destinationView = transitionOut.destinationView {
                    return CameraScreenImpl.TransitionOut(
                        destinationView: destinationView,
                        destinationRect: transitionOut.destinationRect,
                        destinationCornerRadius: transitionOut.destinationCornerRadius,
                        completion: transitionOut.completion
                    )
                } else {
                    return nil
                }
            },
            completion: { result, resultTransition, storyRemainingCount, dismissed in
                let subject: Signal<MediaEditorScreenImpl.Subject?, NoError> = result
                |> map { value -> MediaEditorScreenImpl.Subject? in
                    func editorPIPPosition(_ position: CameraScreenImpl.PIPPosition) -> MediaEditorScreenImpl.PIPPosition {
                        switch position {
                        case .topLeft:
                            return .topLeft
                        case .topRight:
                            return .topRight
                        case .bottomLeft:
                            return .bottomLeft
                        case .bottomRight:
                            return .bottomRight
                        }
                    }
                    switch value {
                    case .pendingImage:
                        return nil
                    case let .image(image):
                        return .image(image: image.image, dimensions: PixelDimensions(image.image.size), additionalImage: image.additionalImage, additionalImagePosition: editorPIPPosition(image.additionalImagePosition), fromCamera: true)
                    case let .video(video):
                        return .video(videoPath: video.videoPath, thumbnail: video.coverImage, mirror: video.mirror, additionalVideoPath: video.additionalVideoPath, additionalThumbnail: video.additionalCoverImage, dimensions: video.dimensions, duration: video.duration, videoPositionChanges: video.positionChangeTimestamps, additionalVideoPosition: editorPIPPosition(video.additionalVideoPosition), fromCamera: true)
                    case let .videoCollage(collage):
                        func editorCollageItem(_ item: CameraScreenImpl.Result.VideoCollage.Item) -> MediaEditorScreenImpl.Subject.VideoCollageItem {
                            let content: MediaEditorScreenImpl.Subject.VideoCollageItem.Content
                            switch item.content {
                            case let .image(image):
                                content = .image(image)
                            case let .video(path, duration):
                                content = .video(path, duration)
                            case let .asset(asset):
                                content = .asset(asset)
                            }
                            return MediaEditorScreenImpl.Subject.VideoCollageItem(
                                content: content,
                                frame: item.frame,
                                contentScale: item.contentScale,
                                contentOffset: item.contentOffset
                            )
                        }
                        return .videoCollage(items: collage.items.map { editorCollageItem($0) })
                    case let .asset(asset):
                        return .asset(asset)
                    case let .draft(draft):
                        return .draft(draft, nil)
                    case let .assets(assets):
                        return .multiple(assets.map { .asset($0) })
                    }
                }
                
                var transitionIn: MediaEditorScreenImpl.TransitionIn?
                if let resultTransition, let sourceView = resultTransition.sourceView {
                    transitionIn = .gallery(
                        MediaEditorScreenImpl.TransitionIn.GalleryTransitionIn(
                            sourceView: sourceView,
                            sourceRect: resultTransition.sourceRect,
                            sourceImage: resultTransition.sourceImage
                        )
                    )
                } else {
                    transitionIn = .camera
                }
                
                let controller = MediaEditorScreenImpl(
                    context: context,
                    mode: .storyEditor(remainingCount: storyRemainingCount ?? 1),
                    subject: subject,
                    customTarget: mediaEditorCustomTarget,
                    transitionIn: transitionIn,
                    transitionOut: { finished, isNew in
                        if finished, let transitionOut = (externalState.transitionOut ?? transitionOut)(externalState.storyTarget, false), let destinationView = transitionOut.destinationView {
                            return MediaEditorScreenImpl.TransitionOut(
                                destinationView: destinationView,
                                destinationRect: transitionOut.destinationRect,
                                destinationCornerRadius: transitionOut.destinationCornerRadius,
                                completion: transitionOut.completion
                            )
                        } else if !finished, let resultTransition, let (destinationView, destinationRect) = resultTransition.transitionOut(isNew) {
                            return MediaEditorScreenImpl.TransitionOut(
                                destinationView: destinationView,
                                destinationRect: destinationRect,
                                destinationCornerRadius: 0.0,
                                completion: nil
                            )
                        } else {
                            return nil
                        }
                    }, completion: { [weak self] results, commit in
                        guard let self else {
                            dismissCameraImpl?()
                            commit({})
                            return
                        }
                        
                        if let customTarget, case .botPreview = customTarget {
                            externalState.storyTarget = customTarget
                            self.proceedWithStoryUpload(target: customTarget, results: results, existingMedia: nil, forwardInfo: nil, externalState: externalState, commit: commit)
                            
                            dismissCameraImpl?()
                            return
                         } else {
                             let target: Stories.PendingTarget
                             let targetPeerId: EnginePeer.Id
                             if let customTarget, case let .peer(id) = customTarget {
                                 target = .peer(id)
                                 targetPeerId = id
                             } else {
                                 if let sendAsPeerId = results.first?.options.sendAsPeerId {
                                     target = .peer(sendAsPeerId)
                                     targetPeerId = sendAsPeerId
                                 } else {
                                     target = .myStories
                                     targetPeerId = context.account.peerId
                                 }
                             }
                             externalState.storyTarget = target
                             
                             let _ = (self.context.engine.data.get(TelegramEngine.EngineData.Item.Peer.Peer(id: targetPeerId))
                             |> deliverOnMainQueue).startStandalone(next: { [weak self] peer in
                                guard let self, let peer else {
                                    return
                                }
                                 
                                if case let .user(user) = peer {
                                    externalState.isPeerArchived = user.storiesHidden ?? false
                                } else if case let .channel(channel) = peer {
                                    externalState.isPeerArchived = channel.storiesHidden ?? false
                                }
                                 
                                 self.proceedWithStoryUpload(target: target, results: results, existingMedia: nil, forwardInfo: nil, externalState: externalState, commit: commit)
                                
                                dismissCameraImpl?()
                            })
                        }
                    } as ([MediaEditorScreenImpl.Result], @escaping (@escaping () -> Void) -> Void) -> Void
                )
                controller.cancelled = { showDraftTooltip in
                    if showDraftTooltip {
                        showDraftTooltipImpl?()
                    }
                    returnToCameraImpl?()
                }
                controller.dismissed = {
                    dismissed()
                }
                presentImpl?(controller)
            }
        )
        cameraController.transitionedIn = transitionedIn
        controller.push(cameraController)
        presentImpl = { [weak cameraController] c in
            if let navigationController = cameraController?.navigationController as? NavigationController {
                var controllers = navigationController.viewControllers
                controllers.append(c)
                navigationController.setViewControllers(controllers, animated: false)
            }
        }
        dismissCameraImpl = { [weak cameraController] in
            cameraController?.dismiss(animated: false)
        }
        returnToCameraImpl = { [weak cameraController] in
            if let cameraController {
                cameraController.returnFromEditor()
            }
        }
        showDraftTooltipImpl = { [weak cameraController] in
            if let cameraController {
                cameraController.presentDraftTooltip()
            }
        }
        return StoryCameraTransitionInCoordinator(
            animateIn: { [weak cameraController] in
                if let cameraController {
                    if transitionIn?.useFillAnimation == true {
                        cameraController.animateIn()
                    } else {
                        cameraController.updateTransitionProgress(0.0, transition: .immediate)
                        cameraController.completeWithTransitionProgress(1.0, velocity: 0.0, dismissing: false)
                    }
                }
            },
            updateTransitionProgress: { [weak cameraController] transitionFraction in
                if let cameraController {
                    cameraController.updateTransitionProgress(transitionFraction, transition: .immediate)
                }
            },
            completeWithTransitionProgressAndVelocity: { [weak cameraController] transitionFraction, velocity in
                if let cameraController {
                    cameraController.completeWithTransitionProgress(transitionFraction, velocity: velocity, dismissing: false)
                }
            })
    }
    
    public func proceedWithStoryUpload(target: Stories.PendingTarget, results: [MediaEditorScreenResult], existingMedia: EngineMedia?, forwardInfo: Stories.PendingForwardInfo?, externalState: MediaEditorTransitionOutExternalState, commit: @escaping (@escaping () -> Void) -> Void) {
        guard let results = results as? [MediaEditorScreenImpl.Result] else {
            return
        }
        let context = self.context
        let targetPeerId: EnginePeer.Id?
        switch target {
        case let .peer(peerId):
            targetPeerId = peerId
        case .myStories:
            targetPeerId = context.account.peerId
        case .botPreview:
            targetPeerId = nil
        }
        
        let folders: [Int64] = results.first?.options.folderIds ?? []

        if let rootTabController = self.rootTabController {
            if let index = rootTabController.controllers.firstIndex(where: { $0 is ChatListController}) {
                rootTabController.selectedIndex = index
            }
            if forwardInfo != nil {
                var viewControllers = self.viewControllers
                var dismissNext = false
                var range: Range<Int>?
                for i in (0 ..< viewControllers.count).reversed() {
                    let controller = viewControllers[i]
                    if controller is MediaEditorScreen {
                        dismissNext = true
                    }
                    if dismissNext {
                        if controller !== self.rootTabController {
                            if let current = range {
                                range = current.lowerBound - 1 ..< current.upperBound
                            } else {
                                range = i ..< i
                            }
                        } else {
                            break
                        }
                    }
                }
                if let range {
                    viewControllers.removeSubrange(range)
                    self.setViewControllers(viewControllers, animated: false)
                }
            } else if self.viewControllers.contains(where: { $0 is PeerInfoStoryGridScreen }) {
                var viewControllers: [UIViewController] = []
                for i in (0 ..< self.viewControllers.count) {
                    let controller = self.viewControllers[i]
                    if i == 0 {
                        viewControllers.append(controller)
                    } else if controller is MediaEditorScreen {
                        viewControllers.append(controller)
                    } else if controller is ShareWithPeersScreen {
                        viewControllers.append(controller)
                    }
                }
                self.setViewControllers(viewControllers, animated: false)
            }
        }
        
        let completionImpl: () -> Void = { [weak self] in
            guard let self else {
                return
            }
            
            var chatListController: ChatListControllerImpl?
            
            if externalState.isPeerArchived {
                var viewControllers = self.viewControllers
                
                let archiveController = ChatListControllerImpl(context: context, location: .chatList(groupId: .archive), controlsHistoryPreload: false, hideNetworkActivityStatus: false, previewing: false, enableDebugActions: false)
                if !externalState.isForcedTarget {
                    externalState.transitionOut = archiveController.storyCameraTransitionOut()
                }
                chatListController = archiveController
                viewControllers.insert(archiveController, at: 1)
                self.setViewControllers(viewControllers, animated: false)
            } else {
                chatListController = self.chatListController as? ChatListControllerImpl
                if !externalState.isForcedTarget {
                    externalState.transitionOut = chatListController?.storyCameraTransitionOut()
                }
            }
             
            if let chatListController {
                let _ = (chatListController.hasPendingStories
                |> filter { $0 }
                |> take(1)
                |> timeout(externalState.isPeerArchived ? 0.5 : 0.25, queue: .mainQueue(), alternate: .single(true))
                |> deliverOnMainQueue).startStandalone(completed: { [weak chatListController] in
                    guard let chatListController else {
                        return
                    }
                    
                    if let targetPeerId {
                        chatListController.scrollToStories(peerId: targetPeerId)
                    }
                    Queue.mainQueue().justDispatch {
                        commit({})
                    }
                })
            } else {
                Queue.mainQueue().justDispatch {
                    commit({})
                }
            }
        }
        
        if let _ = self.chatListController as? ChatListControllerImpl {
            var index: Int32 = 0
            let groupingId = Int32.random(in: 2000000 ..< Int32.max)
            for result in results {
                var media: EngineStoryInputMedia?
                
                if let mediaResult = result.media {
                    switch mediaResult {
                    case let .image(image, dimensions):
                        let tempFile = EngineTempBox.shared.tempFile(fileName: "file")
                        defer {
                            EngineTempBox.shared.dispose(tempFile)
                        }
                        if let imageData = compressImageToJPEG(image, quality: 0.7, tempFilePath: tempFile.path) {
                            media = .image(dimensions: dimensions, data: imageData, stickers: result.stickers)
                        }
                    case let .video(content, firstFrameImage, values, duration, dimensions):
                        let adjustments: VideoMediaResourceAdjustments
                        if let valuesData = try? JSONEncoder().encode(values) {
                            let data = EngineMemoryBuffer(data: valuesData)
                            let digest = EngineMemoryBuffer(data: data.md5Digest())
                            adjustments = VideoMediaResourceAdjustments(data: data, digest: digest, isStory: true)
                            
                            let resource: TelegramMediaResource
                            switch content {
                            case let .imageFile(path):
                                resource = LocalFileVideoMediaResource(randomId: Int64.random(in: .min ... .max), path: path, adjustments: adjustments)
                            case let .videoFile(path):
                                resource = LocalFileVideoMediaResource(randomId: Int64.random(in: .min ... .max), path: path, adjustments: adjustments)
                            case let .asset(localIdentifier):
                                resource = VideoLibraryMediaResource(localIdentifier: localIdentifier, conversion: .compress(adjustments))
                            }
                            let tempFile = EngineTempBox.shared.tempFile(fileName: "file")
                            defer {
                                EngineTempBox.shared.dispose(tempFile)
                            }
                            let imageData = firstFrameImage.flatMap { compressImageToJPEG($0, quality: 0.6, tempFilePath: tempFile.path) }
                            let firstFrameFile = imageData.flatMap { data -> EngineTempBoxFile? in
                                let file = EngineTempBox.shared.tempFile(fileName: "image.jpg")
                                if let _ = try? data.write(to: URL(fileURLWithPath: file.path)) {
                                    return file
                                } else {
                                    return nil
                                }
                            }
                            
                            var coverTime: Double?
                            if let coverImageTimestamp = values.coverImageTimestamp {
                                if let trimRange = values.videoTrimRange {
                                    coverTime = min(duration, coverImageTimestamp - trimRange.lowerBound)
                                } else {
                                    coverTime = min(duration, coverImageTimestamp)
                                }
                            }
                            
                            media = .video(dimensions: dimensions, duration: duration, resource: resource, firstFrameFile: firstFrameFile, stickers: result.stickers, coverTime: coverTime)
                        }
                    default:
                        break
                    }
                } else if let existingMedia {
                    media = .existing(media: existingMedia._asMedia())
                }
                
                if let media {
                    #if DEBUG
                    if !"".isEmpty {
                        let _ = context.engine.messages.beginStoryLivestream(peerId: context.account.peerId, rtmp: true, privacy: result.options.privacy, isForwardingDisabled: false, messagesEnabled: true, sendPaidMessageStars: 0).startStandalone()
                    }
                    #endif
                    
                    let _ = (context.engine.messages.uploadStory(
                        target: target,
                        media: media,
                        mediaAreas: result.mediaAreas,
                        text: result.caption.string,
                        entities: generateChatInputTextEntities(result.caption),
                        pin: result.options.pin,
                        privacy: result.options.privacy,
                        isForwardingDisabled: result.options.isForwardingDisabled,
                        period: result.options.timeout,
                        randomId: result.randomId,
                        forwardInfo: forwardInfo,
                        folders: folders,
                        music: result.music,
                        uploadInfo: results.count > 1 ? StoryUploadInfo(groupingId: groupingId, index: index, total: Int32(results.count)) : nil
                    )
                    |> deliverOnMainQueue).startStandalone(next: { stableId in
                        moveStorySource(engine: context.engine, peerId: context.account.peerId, from: result.randomId, to: Int64(stableId))
                    })
                }
                index += 1
            }
            completionImpl()
        }
    }
    
    public func openChats() {
        guard let rootTabController = self.rootTabController else {
            return
        }
        
        self.popToRoot(animated: false)
    
        if let index = rootTabController.controllers.firstIndex(where: { $0 is ChatListController }) {
            rootTabController.selectedIndex = index
        }
    }
    
    public func openContacts() {
        guard let rootTabController = self.rootTabController else {
            return
        }
        
        self.popToRoot(animated: false)
    
        if let index = rootTabController.controllers.firstIndex(where: { $0 is ContactsController }) {
            rootTabController.selectedIndex = index
        }
    }
        
    public func openSettings(edit: Bool) {
        guard let rootTabController = self.rootTabController else {
            return
        }
        
        self.popToRoot(animated: false)
    
        if let index = rootTabController.controllers.firstIndex(where: { $0 is PeerInfoScreenImpl }) {
            rootTabController.selectedIndex = index
        }
        
        if edit {
            self.accountSettingsController?.activateEdit()
        }
    }
    
    public func openBirthdaySetup() {
        self.accountSettingsController?.openBirthdaySetup()
    }
    
    public func openPhotoSetup(completedWithUploadingImage: @escaping (UIImage, Signal<PeerInfoAvatarUploadStatus, NoError>) -> UIView?) {
        self.accountSettingsController?.openAvatarSetup(completedWithUploadingImage: completedWithUploadingImage)
    }
    
    public func openAvatars() {
        if let accountSettingsController = self.accountSettingsController {
            self.rootTabController?.updateControllerLayout(controller: accountSettingsController)
            accountSettingsController.openAvatars()
        }
    }
    
    public func startNewCall() {
        self.callListController?.tabBarActivateSearch()
    }
}

#if SWIFT_PACKAGE
extension MediaEditorScreenImpl.Result: MediaEditorScreenResult {
    public var target: Stories.PendingTarget {
        if let sendAsPeerId = self.options.sendAsPeerId {
            return .peer(sendAsPeerId)
        } else {
            return .myStories
        }
    }
}
#else
extension MediaEditorScreenImpl.Result: @retroactive MediaEditorScreenResult {
    public var target: Stories.PendingTarget {
        if let sendAsPeerId = self.options.sendAsPeerId {
            return .peer(sendAsPeerId)
        } else {
            return .myStories
        }
    }
}
#endif
