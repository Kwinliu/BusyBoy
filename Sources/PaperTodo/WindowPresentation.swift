import AppKit

@MainActor
enum WindowPresentation {
    static func prepareInteractiveSurface(_ window: NSWindow) {
        window.isOpaque = false
        // A fully clear AppKit background makes this layer-backed artwork
        // transparent to WindowServer hit testing, even when NSView.hitTest succeeds.
        // A nonzero sub-pixel alpha keeps the cutout visually transparent and clickable.
        window.backgroundColor = NSColor.white.withAlphaComponent(0.001)
        window.ignoresMouseEvents = false
        window.acceptsMouseMovedEvents = true
    }

    static func showEditor(_ panel: NSPanel) {
        panel.hidesOnDeactivate = false
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        focusEditor(in: panel)
        DispatchQueue.main.async {
            guard panel.isVisible else { return }
            panel.makeKeyAndOrderFront(nil)
            focusEditor(in: panel)
        }
    }

    static func showPrinter(_ window: NSWindow) {
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    static func printerLevel(alwaysOnTop: Bool) -> NSWindow.Level {
        alwaysOnTop ? .floating : .normal
    }

    static func editor(in root: NSView?) -> NSTextView? {
        guard let root else { return nil }
        if let editor = root as? NSTextView { return editor }
        for child in root.subviews { if let editor = editor(in: child) { return editor } }
        return nil
    }

    private static func focusEditor(in panel: NSPanel) {
        panel.contentView?.layoutSubtreeIfNeeded()
        if let editor = editor(in: panel.contentView) {
            panel.initialFirstResponder = editor
            panel.makeFirstResponder(editor)
        }
    }
}
