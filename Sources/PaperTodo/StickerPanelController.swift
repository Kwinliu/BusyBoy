import AppKit
import SwiftUI

enum StickerKind { case clocks, weather, pomodoro }

@MainActor
final class LiftPresentation: ObservableObject {
    @Published var deployment: CGFloat = 0
    @Published var kind: StickerKind = .clocks
}

@MainActor
private struct UtilityBackboard: View {
    @ObservedObject var lift: LiftPresentation
    @ObservedObject var settings: StickerSettings
    @ObservedObject var weather: WeatherModel
    @ObservedObject var pomodoro: PomodoroModel
    @ObservedObject var clock: AlarmClockModel
    var close: () -> Void
    var chooseClockCity: (Int) -> Void
    var chooseWeatherCity: () -> Void
    var showTimerSettings: () -> Void
    var showAlarmSettings: () -> Void

    var body: some View {
        MechanicalAssembly(deployment: lift.deployment, content: content)
    }
    @ViewBuilder private var content: some View {
        switch lift.kind {
        case .clocks: WorldClocksView(settings: settings, close: close, chooseCity: chooseClockCity)
        case .weather: WeatherStickerView(settings: settings, model: weather, close: close, chooseCity: chooseWeatherCity)
        case .pomodoro: PomodoroView(model: pomodoro, clock: clock, close: close, showSettings: showTimerSettings, showAlarmSettings: showAlarmSettings)
        }
    }
}

@MainActor
final class StickerPanelController: NSObject, NSWindowDelegate {
    let settings = StickerSettings()
    let weather = WeatherModel()
    let pomodoro = PomodoroModel()
    let clock: AlarmClockModel
    let lift = LiftPresentation()
    private unowned let printer: NSWindow
    private let soundEnabled: () -> Bool
    private let audio = PrinterAudio()
    private let alarmAudio = PrinterAudio()
    private var alarmPanel: NSPanel?
    private var accessory: NSPanel?
    private var editor: NSPanel?
    private var isStowed = true
    private var originalTopLeft: NSPoint?
    private var motion: Task<Void, Never>?
    private var targetDeployment: CGFloat = 0
    private var userMovedDuringMotion = false
    private(set) var isPositioningPrinter = false

    init(printer: NSWindow, soundEnabled: @escaping () -> Bool = { true }, clock: AlarmClockModel? = nil) {
        self.printer = printer; self.soundEnabled = soundEnabled
        self.clock = clock ?? AlarmClockModel()
        super.init()
        self.clock.onRing = { [weak self] in self?.showAlarmAlert() }
        self.clock.onStop = { [weak self] in self?.closeAlarmAlert() }
    }

    func showClocks() { show(.clocks) }
    func showWeather() { show(.weather) }
    func togglePomodoro() { show(.pomodoro) }

    private func show(_ kind: StickerKind) {
        install()
        closeEditor()
        let closing = lift.kind == kind && targetDeployment == 1
        lift.kind = kind
        accessory?.title = kind == .clocks ? "BusyBoy 世界时间" : kind == .weather ? "BusyBoy 天气" : "BusyBoy 番茄时钟"
        WindowPresentation.showPrinter(printer)
        resume()
        if !closing {
            accessory?.makeKeyAndOrderFront(nil)
            accessory?.order(.below, relativeTo: printer.windowNumber)
        }
        animate(to: closing ? 0 : 1)
    }

    /// Retain the entire backboard; the printer itself occludes the stowed panel.
    func install() {
        guard accessory == nil else { return }
        let result = EntryPanel(contentRect: stowedFrame(), styleMask: [.borderless], backing: .buffered, defer: false)
        WindowPresentation.prepareInteractiveSurface(result)
        result.level = printer.level
        result.hasShadow = false
        result.hidesOnDeactivate = false
        result.isFloatingPanel = false
        result.isReleasedWhenClosed = false
        result.ignoresMouseEvents = true
        result.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        result.delegate = self
        let host = NSHostingView(rootView: StowedBackboard())
        host.sizingOptions = []
        result.contentView = host
        accessory = result
        printer.addChildWindow(result, ordered: .below)
        if printer.isVisible { result.order(.below, relativeTo: printer.windowNumber) }
    }

    private func unfoldSurface() {
        guard isStowed, let accessory else { return }
        isStowed = false
        let host = NSHostingView(rootView: UtilityBackboard(lift: lift, settings: settings, weather: weather, pomodoro: pomodoro, clock: clock,
            close: { [weak self] in self?.hide() },
            chooseClockCity: { [weak self] in self?.chooseClockCity($0) },
            chooseWeatherCity: { [weak self] in self?.chooseWeatherCity() },
            showTimerSettings: { [weak self] in self?.showPomodoroSettings() },
            showAlarmSettings: { [weak self] in self?.showAlarmSettings() }))
        host.sizingOptions = []
        accessory.contentView = host
        accessory.setFrame(panelFrame(), display: true)
        accessory.makeFirstResponder(host)
    }

    private func stowSurface() {
        guard let accessory else { return }
        isStowed = true
        let host = NSHostingView(rootView: StowedBackboard())
        host.sizingOptions = []
        accessory.contentView = host
        accessory.setFrame(stowedFrame(), display: true)
    }
    private func stowedFrame() -> NSRect {
        NSRect(x: printer.frame.midX - 172, y: printer.frame.maxY + LiftGeometry.peek - LiftGeometry.stowedHeight,
               width: 344, height: LiftGeometry.stowedHeight)
    }
    private func displayFrame() -> NSRect { isStowed ? stowedFrame() : panelFrame() }

    private func panelFrame() -> NSRect {
        NSRect(x: printer.frame.midX - 172,
               y: printer.frame.maxY + LiftGeometry.boardHeight + LiftGeometry.clearance - LiftGeometry.canvasHeight,
               width: 344, height: LiftGeometry.canvasHeight)
    }

    private func animate(to target: CGFloat) {
        if motion == nil, lift.deployment == target { return }
        motion?.cancel(); audio.stop()
        unfoldSurface()
        targetDeployment = target
        let start = lift.deployment
        let duration = max(0.16, 0.72 * Double(abs(target - start)))
        let startTopLeft = NSPoint(x: printer.frame.minX, y: printer.frame.maxY)
        var endTopLeft = startTopLeft
        if target == 1 {
            let screen = printer.screen?.visibleFrame ?? NSScreen.main!.visibleFrame
            let ceiling = screen.maxY - LiftGeometry.boardHeight - LiftGeometry.clearance - 8
            if printer.frame.maxY > ceiling {
                if originalTopLeft == nil { originalTopLeft = startTopLeft }
                endTopLeft.y = ceiling
            }
        } else if let originalTopLeft { endTopLeft = originalTopLeft }
        userMovedDuringMotion = false
        accessory?.ignoresMouseEvents = target == 0
        if soundEnabled(), abs(target - start) > 0.01 { audio.moveMechanism(opening: target == 1, duration: duration) }
        let beginning = ProcessInfo.processInfo.systemUptime
        motion = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                let elapsed = ProcessInfo.processInfo.systemUptime - beginning
                let time = min(1, elapsed / duration)
                let eased = CGFloat(time * time * (3 - 2 * time))
                self.lift.deployment = start + (target - start) * eased
                if !self.userMovedDuringMotion, startTopLeft != endTopLeft {
                    let point = NSPoint(x: startTopLeft.x + (endTopLeft.x - startTopLeft.x) * eased,
                                        y: startTopLeft.y + (endTopLeft.y - startTopLeft.y) * eased - self.printer.frame.height)
                    self.isPositioningPrinter = true
                    self.printer.setFrameOrigin(point)
                    self.isPositioningPrinter = false
                }
                self.accessory?.setFrame(self.panelFrame(), display: true)
                if time >= 1 { break }
                try? await Task.sleep(for: .milliseconds(16))
            }
            guard !Task.isCancelled, let self else { return }
            self.lift.deployment = target
            self.accessory?.ignoresMouseEvents = target == 0
            if target == 0 {
                self.originalTopLeft = nil
                self.stowSurface()
                if self.accessory?.isKeyWindow == true { self.printer.makeKey() }
            }
            self.motion = nil
        }
    }

    func syncLevel() {
        install()
        accessory?.level = printer.level
        editor?.level = printer.level
        if let accessory, printer.isVisible { accessory.order(.below, relativeTo: printer.windowNumber) }
        if let editor { editor.order(.above, relativeTo: printer.windowNumber) }
    }

    func printerMoved() {
        guard !isPositioningPrinter else { return }
        originalTopLeft = nil
        userMovedDuringMotion = true
        printerResized()
    }
    func printerResized() { accessory?.setFrame(displayFrame(), display: true) }

    func hide() { closeEditor(); animate(to: 0) }
    func resume() {
        install()
        accessory?.setFrame(displayFrame(), display: true)
        accessory?.order(.below, relativeTo: printer.windowNumber)
    }
    func suspend() { shutdown(); accessory?.orderOut(nil) }
    func shutdown() {
        motion?.cancel(); motion = nil; audio.stop(); closeEditor()
        lift.deployment = 0; targetDeployment = 0
        accessory?.ignoresMouseEvents = true
        if let originalTopLeft {
            isPositioningPrinter = true
            printer.setFrameOrigin(NSPoint(x: originalTopLeft.x, y: originalTopLeft.y - printer.frame.height))
            isPositioningPrinter = false
        }
        originalTopLeft = nil
        stowSurface()
    }

    func showPomodoroSettings() {
        showEditor(title: "BusyBoy 番茄钟设置", size: NSSize(width: 300, height: 220),
                   view: PomodoroSettingsView(model: pomodoro, close: { [weak self] in self?.closeEditor() }))
    }
    func showAlarmSettings() {
        showEditor(title: "BusyBoy 闹钟设置", size: NSSize(width: 300, height: 264),
                   view: AlarmSettingsView(model: clock, close: { [weak self] in self?.closeEditor() }))
    }

    private func showAlarmAlert() {
        closeAlarmAlert()
        let screen = printer.screen?.visibleFrame ?? NSScreen.main!.visibleFrame
        let result = EntryPanel(contentRect: NSRect(x: screen.midX - 150, y: screen.midY - 110, width: 300, height: 220),
                                styleMask: [.borderless], backing: .buffered, defer: false)
        result.title = "BusyBoy 闹钟"
        WindowPresentation.prepareInteractiveSurface(result)
        result.hasShadow = true
        result.hidesOnDeactivate = false
        result.isFloatingPanel = false
        result.level = .floating
        result.isReleasedWhenClosed = false
        result.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        result.contentView = NSHostingView(rootView: AlarmRingingView(model: clock))
        alarmPanel = result
        WindowPresentation.showEditor(result)
        if clock.configuration.soundEnabled { alarmAudio.ringAlarm() }
    }
    private func closeAlarmAlert() {
        alarmAudio.stop()
        alarmPanel?.orderOut(nil)
        alarmPanel?.contentView = nil
        alarmPanel = nil
    }
    private func chooseClockCity(_ index: Int) {
        showEditor(title: "更换时钟城市", size: NSSize(width: 390, height: 410), view:
            CitySearchView(title: "更换时钟城市", selected: { [weak self] city in
                self?.settings.changeClock(at: index, to: city); self?.closeEditor()
            }, cancel: { [weak self] in self?.closeEditor() }))
    }
    private func chooseWeatherCity() {
        showEditor(title: "选择天气城市", size: NSSize(width: 390, height: 410), view:
            CitySearchView(title: "选择天气城市", selected: { [weak self] city in
                self?.settings.weatherCity = city; self?.closeEditor()
            }, cancel: { [weak self] in self?.closeEditor() }))
    }

    private func showEditor<Content: View>(title: String, size: NSSize, view: Content) {
        closeEditor()
        let screen = printer.screen?.visibleFrame ?? NSScreen.main!.visibleFrame
        let boardTop = panelFrame().maxY
        let x = min(max(printer.frame.midX - size.width / 2, screen.minX + 8), screen.maxX - size.width - 8)
        let y = min(max(boardTop - size.height, screen.minY + 8), screen.maxY - size.height - 8)
        let result = EntryPanel(contentRect: NSRect(origin: NSPoint(x: x, y: y), size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        result.title = title
        WindowPresentation.prepareInteractiveSurface(result)
        result.level = printer.level
        result.hasShadow = true
        result.isFloatingPanel = false
        result.hidesOnDeactivate = false
        result.isReleasedWhenClosed = false
        result.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        result.contentView = NSHostingView(rootView: view)
        editor = result
        printer.addChildWindow(result, ordered: .above)
        WindowPresentation.showPrinter(result)
        result.order(.above, relativeTo: printer.windowNumber)
    }
    private func closeEditor() {
        guard let editor else { return }
        printer.removeChildWindow(editor)
        editor.orderOut(nil); editor.contentView = nil
        self.editor = nil
    }

    func windowDidBecomeKey(_ notification: Notification) {
        if let accessory, notification.object as? NSWindow === accessory { accessory.order(.below, relativeTo: printer.windowNumber) }
    }
}
