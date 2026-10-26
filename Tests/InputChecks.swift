import AppKit
import SwiftUI

private struct InputFailure: Error, CustomStringConvertible { let description: String }

@main
@MainActor
enum InputChecks {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let launcher = InputTestLauncher()
        app.delegate = launcher
        app.run()
        withExtendedLifetime(launcher) {}
    }

    static func run() async throws {
        // Model the actual global-hotkey call site: the app is already running
        // in the background, rather than showing its first window at launch.
        NSApp.deactivate()
        try await Task.sleep(for: .milliseconds(100))
        try require(!NSApp.isActive, "测试未能进入后台唤起前提")
        let panel = TestEntryPanel(contentRect: NSRect(x: 400, y: 400, width: 568, height: 246),
                                   styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "BusyBoy input regression checks"
        panel.isReleasedWhenClosed = false
        panel.level = .floating
        WindowPresentation.prepareInteractiveSurface(panel)
        var submissions: [String] = []
        panel.contentView = NSHostingView(rootView: QuickEntryView(submit: { submissions.append($0); return true }, cancel: {}))
        WindowPresentation.showEditor(panel)
        defer { panel.orderOut(nil) }
        try await Task.sleep(for: .milliseconds(150))
        let field = try findField(panel.contentView!)
        guard let scroll = field.enclosingScrollView else { throw InputFailure(description: "missing input scroll view") }
        print("INPUT documentHeight=\(field.frame.height), viewportHeight=\(scroll.contentSize.height), keyWindow=\(panel.isKeyWindow), firstResponder=\(panel.firstResponder === field)")
        try require(field.frame.height >= scroll.contentSize.height - 1, "输入区域的下半部分无法点击定位光标：文本视图没有铺满输入区域")
        try require(panel.firstResponder === field, "打开输入框后没有获得键盘焦点")
        try require(NSApp.isActive, "输入框虽然显示了，但应用未激活：键盘和输入法仍归原应用")
        let fieldPoint = NSPoint(x: panel.frame.midX, y: panel.frame.maxY - 120)
        try require(NSWindow.windowNumber(at: fieldPoint, belowWindowWithWindowNumber: 0) == panel.windowNumber, "输入区域的真实鼠标点击穿透到其它窗口")

        field.setMarkedText("ceshi", selectedRange: NSRange(location: 5, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        try await Task.sleep(for: .milliseconds(100))
        try require(field.hasMarkedText(), "中文组合态被 SwiftUI 更新打断")
        try require(field.string == "ceshi", "组合文本被覆盖")
        field.setMarkedText("测试", selectedRange: NSRange(location: 2, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
        try await Task.sleep(for: .milliseconds(100))
        try require(field.hasMarkedText(), "候选词选择阶段丢失了组合态")
        try require(submissions.isEmpty, "选中文时提前提交了待办")
        field.unmarkText()
        field.setSelectedRange(NSRange(location: 0, length: 2))
        try await Task.sleep(for: .milliseconds(100))
        try require(field.selectedRange() == NSRange(location: 0, length: 2), "选区被重绘重置")
        field.insertText("输入", replacementRange: field.selectedRange())
        try await Task.sleep(for: .milliseconds(100))
        try require(field.string == "输入" && field.selectedRange().location == 2, "选词替换后文本或光标位置不正确")
        panel.orderOut(nil)
        let printer = TestEntryPanel(contentRect: NSRect(x: 900, y: 400, width: 344, height: 280), styleMask: [.borderless], backing: .buffered, defer: false)
        printer.isReleasedWhenClosed = false
        defer { printer.orderOut(nil) }
        printer.level = WindowPresentation.printerLevel(alwaysOnTop: false)
        try require(printer.level == .normal, "普通模式被放在桌面背景层，无法按普通窗口的点击顺序恢复")
        printer.orderOut(nil)
        WindowPresentation.showPrinter(printer)
        try await Task.sleep(for: .milliseconds(100))
        try require(printer.isVisible && printer.isKeyWindow, "隐藏后的显示命令没有恢复可交互窗口")
        try require(WindowPresentation.printerLevel(alwaysOnTop: true) > .normal, "置顶开关未提升窗口层级")
    }

    static func findField(_ root: NSView) throws -> CommitTextView {
        if let field = root as? CommitTextView { return field }
        for child in root.subviews { if let field = try? findField(child) { return field } }
        throw InputFailure(description: "找不到实际的原生输入视图")
    }
    static func require(_ value: Bool, _ message: String) throws { if !value { throw InputFailure(description: message) } }
}

@MainActor
private final class InputTestLauncher: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task {
            do { try await InputChecks.run(); print("PASS  后台唤起焦点、中文组合态、选区、普通层级与隐藏恢复"); exit(0) }
            catch { fputs("FAIL  \(error)\n", stderr); exit(1) }
        }
    }
}

private final class TestEntryPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
