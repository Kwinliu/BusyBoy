import AppKit
import SwiftUI
import Combine

@main
enum PaperTodoApp {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
        withExtendedLifetime(delegate) {}
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    private let demo = CommandLine.arguments.contains("--demo")
    private let preview = CommandLine.arguments.contains("--preview")
    private lazy var store = TodoStore(fileURL: demo ? nil : TodoStore.defaultURL, demo: demo)
    private let hotKey = GlobalHotKey()
    private let printer = PrintEngine()
    private let settings = DesktopSettings()
    private var desktop: DesktopPanel!
    private var panel: EntryPanel?
    private lazy var stickers = StickerPanelController(printer: desktop, soundEnabled: { [weak self] in self?.store.soundEnabled ?? true })
    private var statusItem: NSStatusItem?
    private var previousApp: NSRunningApplication?
    private var editingID: UUID?
    private var inputDraft = UserDefaults.standard.string(forKey: "inputDraft") ?? ""
    private var cancellables = Set<AnyCancellable>()
    private var hasPositioned = false
    private var resizingDesktop = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        buildMenu()
        buildDesktop()
        buildStatusItem()
        if let index = CommandLine.arguments.firstIndex(of: "--restore-pomodoro"),
           CommandLine.arguments.indices.contains(index + 1),
           let data = CommandLine.arguments[index + 1].data(using: .utf8),
           let session = try? JSONDecoder().decode(PomodoroSession.self, from: data) {
            stickers.pomodoro.restoreSession(session)
        }
        settings.$alwaysOnTop.sink { [weak self] enabled in
            guard let self else { return }
            self.desktop.level = WindowPresentation.printerLevel(alwaysOnTop: self.preview || enabled)
            self.statusItem?.menu?.items.first(where: { $0.identifier?.rawValue == "alwaysOnTop" })?.state = enabled ? .on : .off
            self.stickers.syncLevel()
            self.desktop.orderFrontRegardless()
        }.store(in: &cancellables)
        store.$soundEnabled.sink { [weak self] in self?.printer.soundEnabled = $0 }.store(in: &cancellables)
        hotKey.action = { [weak self] in self?.toggleEntry() }
        hotKey.register()
        desktop.orderFrontRegardless()
        store.$items.sink { [weak self] items in
            let remaining = items.filter { !$0.isCompleted && $0.tornAt == nil }.count
            self?.statusItem?.button?.toolTip = "BusyBoy · \(remaining) 件待办 · ⌃⌥Space 随手记"
        }.store(in: &cancellables)
        store.$errorMessage.compactMap { $0 }.sink { [weak self] message in
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "本机清单需要留意"
                alert.informativeText = message
                alert.addButton(withTitle: "知道了")
                alert.runModal()
                self?.store.dismissError()
            }
        }.store(in: &cancellables)
    }

    private var desktopLevel: NSWindow.Level {
        WindowPresentation.printerLevel(alwaysOnTop: preview || settings.alwaysOnTop)
    }

    private func buildDesktop() {
        let screen = NSScreen.main ?? NSScreen.screens[0]
        let maximum = min(470, screen.visibleFrame.height - 250)
        desktop = DesktopPanel(contentRect: NSRect(x: 0, y: 0, width: 344, height: 350),
                               styleMask: [.borderless], backing: .buffered, defer: false)
        desktop.title = "BusyBoy 桌面打印机"
        WindowPresentation.prepareInteractiveSurface(desktop)
        desktop.hasShadow = false
        desktop.isFloatingPanel = false
        desktop.hidesOnDeactivate = false
        desktop.level = desktopLevel
        desktop.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        desktop.isMovable = true
        desktop.isMovableByWindowBackground = false
        desktop.isReleasedWhenClosed = false
        desktop.delegate = self
        let root = DesktopWidget(store: store, printer: printer, settings: settings, maxPaperHeight: maximum,
                                 add: { [weak self] in self?.showEntry() },
                                 edit: { [weak self] in self?.showEntry(editing: $0) },
                                 resize: { [weak self] in self?.resizeDesktop($0) },
                                 export: { [weak self] in self?.exportData() },
                                 hide: { [weak self] in self?.hideDesktop() },
                                 showWorldClocks: { [weak self] in self?.stickers.showClocks() },
                                 showWeather: { [weak self] in self?.stickers.showWeather() },
                                 showPomodoro: { [weak self] in self?.stickers.togglePomodoro() })
        let hosting = DraggableHostingView(rootView: root)
        hosting.sizingOptions = []
        desktop.contentView = hosting
        if !desktop.setFrameUsingName("PaperTodoDesktopV2") { resetPosition() }
        if !NSScreen.screens.contains(where: { $0.visibleFrame.intersects(desktop.frame) }) { resetPosition() }
        hasPositioned = true
    }

    private func resizeDesktop(_ height: CGFloat) {
        guard desktop != nil else { return }
        var frame = desktop.frame
        let top = frame.maxY
        frame.size = NSSize(width: 344, height: ceil(height))
        frame.origin.y = top - frame.height
        resizingDesktop = true
        desktop.setFrame(frame, display: true)
        resizingDesktop = false
        if hasPositioned { stickers.printerResized() }
    }

    @objc private func resetPosition() {
        let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }) ?? NSScreen.main!
        let frame = screen.visibleFrame
        desktop.setFrameOrigin(NSPoint(x: frame.maxX - 344 - 35, y: frame.maxY - desktop.frame.height - 55))
        desktop.saveFrame(usingName: "PaperTodoDesktopV2")
    }

    private func buildMenu() {
        let menu = NSMenu()
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "关于 BusyBoy", action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "退出 BusyBoy", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        let appItem = NSMenuItem(); appItem.submenu = appMenu; menu.addItem(appItem)
        let file = NSMenu(title: "文件")
        file.addItem(item("写一条待办…", #selector(newEntry), key: "n"))
        file.addItem(item("显示桌面打印机", #selector(showDesktop)))
        file.addItem(item("导出清单备份…", #selector(exportData), key: "e"))
        let fileItem = NSMenuItem(); fileItem.submenu = file; menu.addItem(fileItem)
        let edit = NSMenu(title: "编辑")
        edit.addItem(item("撤销", #selector(undoTodo), key: "z"))
        edit.addItem(.separator())
        edit.addItem(withTitle: "剪切", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "拷贝", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "粘贴", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "全选", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        let editItem = NSMenuItem(); editItem.submenu = edit; menu.addItem(editItem)
        NSApp.mainMenu = menu
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let result = NSMenuItem(title: title, action: action, keyEquivalent: key)
        result.target = self
        return result
    }

    private func buildStatusItem() {
        let status = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        status.button?.image = NSImage(systemSymbolName: "printer", accessibilityDescription: "BusyBoy")
        let menu = NSMenu()
        menu.addItem(item("写一条待办…   ⌃⌥Space", #selector(newEntry)))
        menu.addItem(item("显示桌面打印机", #selector(showDesktop)))
        menu.addItem(item("移回桌面右上角", #selector(resetPosition)))
        let onTop = item("保持在所有窗口最前", #selector(toggleOnTop))
        onTop.identifier = NSUserInterfaceItemIdentifier("alwaysOnTop")
        onTop.state = settings.alwaysOnTop ? .on : .off
        menu.addItem(onTop)
        menu.addItem(.separator())
        menu.addItem(item("世界时间", #selector(showWorldClocks)))
        menu.addItem(item("天气", #selector(showWeather)))
        menu.addItem(item("番茄时钟", #selector(showPomodoro)))
        menu.addItem(.separator())
        menu.addItem(item("显示全部事项", #selector(showAll)))
        menu.addItem(item("只显示待办", #selector(showPending)))
        menu.addItem(item("只显示已完成", #selector(showCompleted)))
        menu.addItem(item("查看撕下的纸条", #selector(showArchive)))
        menu.addItem(item("撤销上次更改", #selector(undoTodo)))
        menu.addItem(.separator())
        menu.addItem(item("导出清单备份…", #selector(exportData)))
        menu.addItem(item("打开本机数据文件夹", #selector(revealData)))
        menu.addItem(.separator())
        menu.addItem(item("退出 BusyBoy", #selector(quitApp)))
        status.menu = menu
        statusItem = status
    }

    private func hideDesktop() { stickers.suspend(); desktop.orderOut(nil) }
    @objc private func showWorldClocks() { stickers.showClocks() }
    @objc private func showWeather() { stickers.showWeather() }
    @objc private func showPomodoro() { stickers.togglePomodoro() }
    @objc private func newEntry() { showEntry() }
    @objc private func quitApp() { NSApp.terminate(nil) }
    @objc private func showDesktop() { WindowPresentation.showPrinter(desktop); stickers.resume() }
    @objc private func showAll() { store.filter = .all; showDesktop() }
    @objc private func showPending() { store.filter = .pending; showDesktop() }
    @objc private func showCompleted() { store.filter = .completed; showDesktop() }
    @objc private func showArchive() { store.filter = .archive; showDesktop() }
    @objc private func revealData() {
        guard let url = store.dataURL else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        NSWorkspace.shared.open(url.deletingLastPathComponent())
    }
    @objc private func toggleOnTop(_ sender: NSMenuItem) {
        settings.alwaysOnTop.toggle()
    }
    @objc private func undoTodo() {
        if let textView = NSApp.keyWindow?.firstResponder as? NSTextView { textView.undoManager?.undo() }
        else { withAnimation { store.undo() } }
    }

    private func toggleEntry() {
        if let panel, panel.isVisible, panel.isKeyWindow, NSApp.isActive { hideEntry(restoreFocus: true) }
        else { showEntry() }
    }

    private func showEntry(editing item: TodoItem? = nil) {
        if let panel, panel.isVisible, item == nil { WindowPresentation.showEditor(panel); return }
        if panel?.isVisible == true { hideEntry(restoreFocus: false) }
        previousApp = NSWorkspace.shared.frontmostApplication
        editingID = item?.id
        let entry = EntryPanel(contentRect: NSRect(x: 0, y: 0, width: 568, height: 246),
                               styleMask: [.borderless], backing: .buffered, defer: false)
        entry.level = .floating
        entry.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        WindowPresentation.prepareInteractiveSurface(entry)
        entry.hasShadow = true
        entry.isMovableByWindowBackground = true
        entry.isReleasedWhenClosed = false
        entry.delegate = self
        entry.contentView = NSHostingView(rootView: QuickEntryView(initialText: item?.text ?? inputDraft, isEditing: item != nil,
            submit: { [weak self] text in
                guard let self else { return false }
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !trimmed.isEmpty, trimmed.count <= 500 else { return false }
                if let id = self.editingID { self.store.edit(id, text: trimmed) }
                else if self.store.add(trimmed), let item = self.store.items.last {
                    self.printer.enqueue(item)
                }
                let wasNewItem = self.editingID == nil
                self.desktop.orderFrontRegardless()
                self.hideEntry(restoreFocus: true)
                if wasNewItem { self.inputDraft = ""; UserDefaults.standard.removeObject(forKey: "inputDraft") }
                return true
            }, cancel: { [weak self] in self?.hideEntry(restoreFocus: true) }))
        let screen = NSScreen.screens.first(where: { NSMouseInRect(NSEvent.mouseLocation, $0.frame, false) }) ?? NSScreen.main
        if let frame = screen?.visibleFrame {
            entry.setFrameOrigin(NSPoint(x: frame.midX - 284, y: frame.midY + 30))
        } else { entry.center() }
        panel?.orderOut(nil)
        panel = entry
        WindowPresentation.showEditor(entry)
    }

    private func hideEntry(restoreFocus: Bool) {
        let old = panel
        if editingID == nil, let editor = WindowPresentation.editor(in: old?.contentView) { inputDraft = editor.string }
        UserDefaults.standard.set(inputDraft, forKey: "inputDraft")
        panel = nil
        old?.orderOut(nil)
        editingID = nil
        if restoreFocus, let previousApp, previousApp.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previousApp.activate(options: [])
        }
        previousApp = nil
    }

    func windowDidMove(_ notification: Notification) {
        if hasPositioned, let window = notification.object as? DesktopPanel {
            if !stickers.isPositioningPrinter && !resizingDesktop {
                stickers.printerMoved()
                window.saveFrame(usingName: "PaperTodoDesktopV2")
            }
        }
    }

    @objc private func exportData() {
        let save = NSSavePanel()
        save.nameFieldStringValue = "BusyBoy清单-\(Date.now.formatted(.iso8601.year().month().day().dateSeparator(.dash))).json"
        save.allowedContentTypes = [.json]
        save.canCreateDirectories = true
        NSApp.activate(ignoringOtherApps: true)
        guard save.runModal() == .OK, let url = save.url else { return }
        do { try store.export(to: url) }
        catch {
            let alert = NSAlert()
            alert.messageText = "未能导出清单"
            alert.informativeText = error.localizedDescription
            alert.runModal()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { showDesktop(); return true }
    func applicationWillTerminate(_ notification: Notification) {
        stickers.shutdown()
        if editingID == nil, let editor = WindowPresentation.editor(in: panel?.contentView) { inputDraft = editor.string }
        UserDefaults.standard.set(inputDraft, forKey: "inputDraft")
        hotKey.unregister()
    }
}

final class EntryPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

