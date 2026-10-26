import AppKit
import SwiftUI

extension Bundle { static var module: Bundle { .main } }

@main
@MainActor
enum DragChecks {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let launcher = DragTestLauncher()
        app.delegate = launcher
        app.run()
        withExtendedLifetime(launcher) {}
    }

    static func run() async throws {
        let store = TodoStore(fileURL: nil)
        let printer = PrintEngine()
        printer.soundEnabled = false
        let settings = DesktopSettings()
        let panel = DesktopPanel(contentRect: NSRect(x: 550, y: 400, width: 344, height: 286), styleMask: [.borderless], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        WindowPresentation.prepareInteractiveSurface(panel)
        panel.hasShadow = false
        panel.isFloatingPanel = false
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = false
        panel.level = .normal
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        let root = DesktopWidget(store: store, printer: printer, settings: settings, maxPaperHeight: 470,
                                 add: {}, edit: { _ in }, resize: { height in
                                     var frame = panel.frame
                                     frame.origin.y += frame.height - height
                                     frame.size.height = height
                                     panel.setFrame(frame, display: true)
                                 }, export: {}, hide: {}, showWorldClocks: {}, showWeather: {}, showPomodoro: {})
        let hosting = DraggableHostingView(rootView: root)
        hosting.sizingOptions = []
        panel.contentView = hosting
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        defer { panel.orderOut(nil) }
        try await Task.sleep(for: .milliseconds(350))
        let host = panel.contentView!
        print("WINDOW frame=\(panel.frame) ignoresMouseEvents=\(panel.ignoresMouseEvents), hostBounds=\(host.bounds), flipped=\(host.isFlipped), key=\(panel.isKeyWindow), active=\(NSApp.isActive)")
        var misses = 0
        let points: [NSPoint] = [NSPoint(x: 45, y: 55), NSPoint(x: 160, y: 45), NSPoint(x: 205, y: 112), NSPoint(x: 80, y: 110), NSPoint(x: 170, y: 110), NSPoint(x: 300, y: 125), NSPoint(x: 25, y: 205), NSPoint(x: 320, y: 175), NSPoint(x: 30, y: 236)]
        for point in points {
            let windowPoint = NSPoint(x: point.x, y: host.bounds.height - point.y)
            let inputPoint = host.superview?.convert(windowPoint, from: nil) ?? windowPoint
            let hit = host.hitTest(inputPoint)
            let draggable = hit is PrinterDragArea.DragView
            let screenPoint = NSPoint(x: panel.frame.minX + point.x, y: panel.frame.maxY - point.y)
            let systemTarget = NSWindow.windowNumber(at: screenPoint, belowWindowWithWindowNumber: 0)
            let ownsPhysicalHit = systemTarget == panel.windowNumber
            print("HIT top=\(point) target=\(hit.map { String(describing: type(of: $0)) } ?? "nil") draggable=\(draggable) physicalWindow=\(systemTarget)/\(panel.windowNumber)")
            if !draggable || !ownsPhysicalHit { misses += 1 }
        }
        if misses > 0 { throw DragFailure(description: "\(misses)/\(points.count) 个可见机身点没有命中拖动区，会落到背景或其它视图") }
        for point in [NSPoint(x: 279.5, y: 85.5), NSPoint(x: 119, y: 55), NSPoint(x: 202, y: 63), NSPoint(x: 267, y: 42), NSPoint(x: 245, y: 103), NSPoint(x: 172, y: 148), NSPoint(x: 172, y: 190), NSPoint(x: 3, y: 3)] {
            let windowPoint = NSPoint(x: point.x, y: host.bounds.height - point.y)
            let inputPoint = host.superview?.convert(windowPoint, from: nil) ?? windowPoint
            if host.hitTest(inputPoint) is PrinterDragArea.DragView {
                throw DragFailure(description: "拖动区域错误遮住了纸条、按钮或透明边角：\(point)")
            }
        }
        for index in 0..<12 { _ = store.add("纸条滚动检查 \(index)") }
        try await Task.sleep(for: .milliseconds(250))
        func findScroll(_ view: NSView) -> NSScrollView? {
            if let scroll = view as? NSScrollView { return scroll }
            return view.subviews.compactMap { findScroll($0) }.first
        }
        guard let scroll = findScroll(host), !scroll.hasVerticalScroller, !scroll.hasHorizontalScroller else {
            throw DragFailure(description: "纸条出现滚动条")
        }
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 60))
        scroll.reflectScrolledClipView(scroll.contentView)
        guard scroll.contentView.bounds.minY > 0 else { throw DragFailure(description: "隐藏滚动条后纸条不能滚动") }
        print("PASS  纸条保留滚动且不显示滑块")
    }
}

private struct DragFailure: Error, CustomStringConvertible { let description: String }
@MainActor
private final class DragTestLauncher: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task {
            do { try await DragChecks.run(); print("PASS  可见机身命中拖动区域"); exit(0) }
            catch { fputs("FAIL  \(error)\n", stderr); exit(1) }
        }
    }
}
