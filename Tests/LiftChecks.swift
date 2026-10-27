import AppKit
import SwiftUI

@main
@MainActor
enum LiftChecks {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let launcher = LiftLauncher()
        app.delegate = launcher
        app.run()
        withExtendedLifetime(launcher) {}
    }
    static func run() async throws {
        let screen = NSScreen.main!.visibleFrame
        let printer = EntryPanel(contentRect: NSRect(x: screen.midX - 172, y: screen.maxY - 460, width: 344, height: 420), styleMask: [.borderless], backing: .buffered, defer: false)
        printer.isReleasedWhenClosed = false
        printer.level = .normal
        WindowPresentation.prepareInteractiveSurface(printer)
        printer.contentView = NSHostingView(rootView: Color.white.frame(width: 344, height: 420))
        WindowPresentation.showPrinter(printer)
        let original = printer.frame
        let suite = "com.paperdesk.LiftAlarmChecks.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        let alarm = AlarmClockModel(defaults: defaults, automaticTicks: false)
        let controller = StickerPanelController(printer: printer, soundEnabled: { false }, clock: alarm)
        defer {
            alarm.stopRinging(); controller.shutdown(); printer.orderOut(nil)
            defaults.removePersistentDomain(forName: suite)
        }
        controller.install()
        try await Task.sleep(for: .milliseconds(100))
        let board = try requirePanel(printer.childWindows?.first, "背板未安装")
        try require(board.isVisible && board.ignoresMouseEvents && controller.lift.deployment == 0 && board.frame.height == LiftGeometry.boardHeight, "收起时应保留完整背板且不拦截鼠标")
        controller.showClocks()
        try await Task.sleep(for: .milliseconds(850))
        try require(controller.lift.deployment == 1 && !board.ignoresMouseEvents, "背板未展开到位")
        try require(board.frame.maxY <= screen.maxY - 7, "展开背板超出屏幕顶部")
        try require(abs(board.frame.maxY - LiftGeometry.height - printer.frame.maxY + LiftGeometry.anchorDepth) < 1, "关节底座脱离打印机")
        let size = board.frame.size
        controller.hide()
        try await Task.sleep(for: .milliseconds(850))
        try require(controller.lift.deployment == 0 && board.frame.height == LiftGeometry.boardHeight && abs(printer.frame.maxY - original.maxY) < 1, "收起后未恢复打印机位置")
        controller.togglePomodoro()
        try await Task.sleep(for: .milliseconds(850))
        try require(board.frame.size == size, "番茄钟背板尺寸不统一")
        controller.showPomodoroSettings()
        try await Task.sleep(for: .milliseconds(150))
        let editor = try requirePanel(printer.childWindows?.first(where: { $0.title == "BusyBoy 番茄钟设置" }), "未打开番茄钟设置")
        editor.setFrameOrigin(NSPoint(x: printer.frame.minX + 20, y: printer.frame.maxY - 180))
        try await Task.sleep(for: .milliseconds(120))
        let overlap = NSPoint(x: editor.frame.midX, y: editor.frame.midY)
        print("SETTINGS physical=\(NSWindow.windowNumber(at: overlap, belowWindowWithWindowNumber: 0)) expected=\(editor.windowNumber), printer=\(printer.windowNumber), board=\(board.windowNumber), visible=\(editor.isVisible), frame=\(editor.frame), level=\(editor.level), children=\(printer.childWindows?.map { ($0.title, $0.windowNumber) } ?? [])")
        try require(NSWindow.windowNumber(at: overlap, belowWindowWithWindowNumber: 0) == editor.windowNumber, "番茄钟设置仍被打印机遮挡")
        try require(editor.level == .normal, "设置面板意外始终置顶")
        controller.showAlarmSettings()
        try await Task.sleep(for: .milliseconds(150))
        let alarmEditor = try requirePanel(printer.childWindows?.first(where: { $0.title == "BusyBoy 闹钟设置" }), "未打开闹钟设置")
        let alarmPoint = NSPoint(x: alarmEditor.frame.midX, y: alarmEditor.frame.midY)
        try require(NSWindow.windowNumber(at: alarmPoint, belowWindowWithWindowNumber: 0) == alarmEditor.windowNumber, "闹钟设置被打印机遮挡")
        controller.showPomodoroSettings()
        let timerEditor = try requirePanel(printer.childWindows?.first(where: { $0.title == "BusyBoy 番茄钟设置" }), "未恢复番茄钟设置")
        printer.level = .floating; controller.syncLevel()
        try require(board.level == .floating && timerEditor.level == .floating, "显式置顶后面板层级未同步")
        printer.level = .normal; controller.syncLevel()
        controller.hide()
        try await Task.sleep(for: .milliseconds(120))
        controller.showWeather()
        try await Task.sleep(for: .milliseconds(80))
        controller.hide()
        try await Task.sleep(for: .milliseconds(80))
        controller.showWeather()
        try await Task.sleep(for: .milliseconds(850))
        try require(controller.lift.deployment == 1 && board.frame.size == size, "快速反向收放或天气尺寸异常")
        let manual = NSPoint(x: printer.frame.minX + 35, y: printer.frame.minY - 25)
        printer.setFrameOrigin(manual); controller.printerMoved()
        controller.hide()
        try await Task.sleep(for: .milliseconds(850))
        try require(printer.frame.origin == manual, "收起覆盖了手动移动位置")
        controller.suspend()
        try require(!board.isVisible, "隐藏打印机后仍留下背板")
        controller.resume()
        try require(board.isVisible && board.ignoresMouseEvents, "隐藏恢复后背板状态异常")
        controller.suspend(); printer.orderOut(nil)
        let now = Date()
        let parts = Calendar.current.dateComponents([.hour, .minute], from: now.addingTimeInterval(60))
        alarm.configure(hour: parts.hour!, minute: parts.minute!, repeatsDaily: false, enabled: true, soundEnabled: false, now: now)
        alarm.tick(now: alarm.nextFire!)
        try await Task.sleep(for: .milliseconds(100))
        let alert = try requirePanel(NSApp.windows.first(where: { $0.title == "BusyBoy 闹钟" && $0.isVisible }), "隐藏打印机时闹钟没有弹出")
        let alertPoint = NSPoint(x: alert.frame.midX, y: alert.frame.midY)
        let frontWindow = NSWindow.windowNumber(at: alertPoint, belowWindowWithWindowNumber: 0)
        print("ALARM physical=\(frontWindow) expected=\(alert.windowNumber), level=\(alert.level), key=\(alert.isKeyWindow)")
        try require(alert.level == .floating && frontWindow == alert.windowNumber, "闹钟提醒没有出现在前台")
        alarm.stopRinging()
        try require(!alert.isVisible && !alarm.isRinging, "停止闹钟后提醒窗口未收起")
        print("PASS  背板露头、上方展开、同尺寸与连续反向收放")
        print("PASS  番茄钟设置实际鼠标命中位于打印机前方，置顶同步")
        print("PASS  临时让位恢复、手动位置保留与隐藏恢复")
        print("PASS  闹钟设置前置，打印机隐藏时仍弹出到点提醒，停止后收起")
    }
    static func require(_ condition: Bool, _ message: String) throws { if !condition { throw LiftFailure(description: message) } }
    static func requirePanel(_ panel: NSWindow?, _ message: String) throws -> NSWindow {
        guard let panel else { throw LiftFailure(description: message) }; return panel
    }
}
private struct LiftFailure: Error, CustomStringConvertible { let description: String }
@MainActor
private final class LiftLauncher: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Task {
            do { try await LiftChecks.run(); exit(0) }
            catch { fputs("FAIL  \(error)\n", stderr); exit(1) }
        }
    }
}
final class EntryPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
