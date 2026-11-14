import Foundation
import UIKit
import AsyncDisplayKit
import Display
import ChatPresentationInterfaceState
import ChatInputPanelNode
import TelegramPresentationData

final class JerkgramExcludedChatInputPanelNode: ChatInputPanelNode {
    private let label = ASTextNode()
    override init() {
        super.init()
        self.isUserInteractionEnabled = false
        self.label.maximumNumberOfLines = 2
        self.addSubnode(self.label)
    }
    override func updateLayout(width: CGFloat, leftInset: CGFloat, rightInset: CGFloat, bottomInset: CGFloat, additionalSideInsets: UIEdgeInsets, maxHeight: CGFloat, maxOverlayHeight: CGFloat, isSecondary: Bool, transition: ContainedViewLayoutTransition, interfaceState: ChatPresentationInterfaceState, metrics: LayoutMetrics, deviceMetrics: DeviceMetrics, isMediaInputExpanded: Bool) -> CGFloat {
        let text = JerkgramStrings(baseLanguageCode: interfaceState.strings.baseLanguageCode).removedFromChat
        self.label.attributedText = NSAttributedString(string: text, font: Font.regular(15.0), textColor: interfaceState.theme.chat.inputPanel.panelControlColor)
        let size = self.label.measure(CGSize(width: max(0.0, width - leftInset - rightInset - 24.0), height: 100.0))
        let height = max(defaultHeight(metrics: metrics), size.height + 20.0)
        self.label.frame = CGRect(x: leftInset + (width - leftInset - rightInset - size.width) / 2.0, y: (height - size.height) / 2.0, width: size.width, height: size.height)
        return height
    }
    override func minimalHeight(interfaceState: ChatPresentationInterfaceState, metrics: LayoutMetrics) -> CGFloat {
        return defaultHeight(metrics: metrics)
    }
}
