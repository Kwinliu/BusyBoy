import AppKit
import SwiftUI

final class DesktopPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

final class DraggableHostingView<Content: View>: NSHostingView<Content> {
    override var mouseDownCanMoveWindow: Bool { false }
}

struct PrinterDragArea: NSViewRepresentable {
    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ nsView: DragView, context: Context) {}
    final class DragView: NSView {
        override var isFlipped: Bool { true }

        private func canDrag(at point: NSPoint) -> Bool {
            guard PrinterCutout().path(in: bounds).contains(point) else { return false }
            let paper = NSRect(x: 52.5, y: DesktopMetrics.mouthY, width: 239, height: max(0, bounds.height - DesktopMetrics.mouthY))
            let feed = NSRect(x: 255, y: 68, width: 49, height: 36)
            let stickers = [
                NSRect(x: 81, y: 22.5, width: 76, height: 65),
                NSRect(x: 169, y: 29.5, width: 66, height: 67),
                NSRect(x: 240, y: 18.5, width: 54, height: 47),
                NSRect(x: 221, y: 85.5, width: 48, height: 35)
            ]
            return !paper.contains(point) && !feed.contains(point) && !stickers.contains { $0.contains(point) }
        }

        override func hitTest(_ point: NSPoint) -> NSView? {
            canDrag(at: convert(point, from: superview)) ? self : nil
        }
        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)

        }
        required init?(coder: NSCoder) { fatalError("init(coder:) is unavailable") }
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
        override func resetCursorRects() {
            addCursorRect(NSRect(x: 25, y: 13, width: 294, height: 140), cursor: .openHand)
            addCursorRect(NSRect(x: 8, y: 154, width: 44, height: 91), cursor: .openHand)
            addCursorRect(NSRect(x: 292, y: 154, width: 44, height: 91), cursor: .openHand)
        }
        override func mouseDown(with event: NSEvent) {
            guard let window else { return }
            WindowPresentation.showPrinter(window)
            NSCursor.closedHand.push()
            defer { NSCursor.pop() }
            window.performDrag(with: event)
            window.saveFrame(usingName: "PaperTodoDesktopV2")
        }
    }
}
