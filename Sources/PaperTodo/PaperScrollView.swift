import AppKit
import SwiftUI

/// An AppKit scroll container avoids SwiftUI restoring a visible legacy scroller.
struct PaperScrollView<Content: View>: NSViewRepresentable {
    var width: CGFloat
    var documentHeight: CGFloat
    var printingID: UUID?
    var content: Content

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSScrollView()
        scroll.drawsBackground = false
        scroll.borderType = .noBorder
        scroll.hasVerticalScroller = false
        scroll.hasHorizontalScroller = false
        scroll.autohidesScrollers = true
        scroll.verticalScrollElasticity = .none
        scroll.horizontalScrollElasticity = .none
        let host = NSHostingView(rootView: content)
        host.frame = NSRect(x: 0, y: 0, width: width, height: documentHeight)
        scroll.documentView = host
        return scroll
    }
    func updateNSView(_ scroll: NSScrollView, context: Context) {
        guard let host = scroll.documentView as? NSHostingView<Content> else { return }
        host.rootView = content
        host.setFrameSize(NSSize(width: width, height: documentHeight))
        if printingID != context.coordinator.printingID, printingID != nil {
            scroll.contentView.scroll(to: .zero)
            scroll.reflectScrolledClipView(scroll.contentView)
        }
        context.coordinator.printingID = printingID
    }
    final class Coordinator { var printingID: UUID? }
}
