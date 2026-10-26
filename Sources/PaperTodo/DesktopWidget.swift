import AppKit
import SwiftUI

struct DesktopWidget: View {
    @ObservedObject var store: TodoStore
    @ObservedObject var printer: PrintEngine
    @ObservedObject var settings: DesktopSettings
    var maxPaperHeight: CGFloat
    var add: () -> Void
    var edit: (TodoItem) -> Void
    var resize: (CGFloat) -> Void
    var export: () -> Void
    var hide: () -> Void
    var showWorldClocks: () -> Void
    var showWeather: () -> Void
    var showPomodoro: () -> Void
    @State private var hovering = false
    @State private var tearing = false
    @State private var tearOffset: CGFloat = 0
    @State private var tearAngle: Double = 0
    @State private var tearOpacity: Double = 1

    private let width: CGFloat = 344
    private let paperWidth: CGFloat = 239
    private let mouthY = DesktopMetrics.mouthY
    private var visibleHeight: CGFloat { min(paperHeight, maxPaperHeight) }
    private var totalHeight: CGFloat { max(286, mouthY + visibleHeight + 23) }
    private var printedItems: [TodoItem] { store.visibleItems.reversed().filter { !printer.hiddenIDs.contains($0.id) } }
    private var current: TodoItem? { store.items.first { $0.id == printer.currentID } }
    private var paperHeight: CGFloat {
        let rows = printedItems.reduce(CGFloat.zero) { $0 + DesktopMetrics.rowHeight($1.text) } + CGFloat(max(0, printedItems.count - 1)) * 14
        let feeding = current.map { (DesktopMetrics.rowHeight($0.text) + (printedItems.isEmpty ? 0 : 14)) * printer.progress } ?? 0
        return rows + feeding + 101
    }

    var body: some View {
        ZStack(alignment: .top) {
            Image(nsImage: PrinterArtwork.image)
                .resizable().interpolation(.high).scaledToFit()
                .frame(width: width, height: 258)
                .clipShape(PrinterCutout())
                .shadow(color: .black.opacity(0.2), radius: 8, x: 1, y: 10)
                .allowsHitTesting(false)
                .accessibilityHidden(true)

            // The printed paper lies over the front of the physical housing.
            PaperScrollView(width: paperWidth + 26, documentHeight: paperHeight + 20, printingID: printer.currentID,
                            content: receipt.padding(.horizontal, 13).padding(.bottom, 20))
                .frame(width: paperWidth + 26, height: visibleHeight)
            .offset(x: tearing ? 12 : 0, y: tearOffset)
            .rotationEffect(.degrees(tearAngle), anchor: .topTrailing)
            .opacity(tearOpacity)
            .padding(.top, mouthY)

            PrinterDragArea().frame(width: 344, height: 258).position(x: 172, y: 129)

            // Real controls are composited exactly over the button and LED lens.
            Ellipse()
                .fill(printer.ledOn ? Color(hex: 0x78C66B) : Color(hex: 0x243B25))
                .frame(width: 6.5, height: 4.5)
                .overlay(Ellipse().fill(.white.opacity(printer.ledOn ? 0.5 : 0.05)).frame(width: 2.5, height: 1.5).offset(x: -1, y: -1))
                .shadow(color: Color.green.opacity(printer.ledOn ? 0.9 : 0), radius: 4)
                .position(x: 46.4, y: 87)
                .animation(.easeInOut(duration: 0.07), value: printer.ledOn)
                .allowsHitTesting(false)
                .accessibilityElement().accessibilityLabel(printer.status)
                .accessibilityValue(printer.ledOn ? "绿灯亮" : "绿灯灭")

            Button(action: add) {
                Image(systemName: "plus").font(.system(size: 8, weight: .medium))
                    .foregroundStyle(Color(hex: 0x85877B).opacity(0.6))
                    .frame(width: 38, height: 23)
                    .contentShape(Capsule())
            }
            .buttonStyle(FeedButtonStyle())
            .position(x: 279.5, y: 85.5)
            .help("写一条待办 · ⌃⌥Space")
            .accessibilityLabel("写一条待办")

            stickerButton("世界时间", width: 76, height: 65, x: 119, y: 55, action: showWorldClocks)
            stickerButton("番茄时钟", width: 66, height: 67, x: 202, y: 63, action: showPomodoro)
            stickerButton("天气", width: 54, height: 47, x: 267, y: 42, action: showWeather)
            stickerButton("撕下当前纸条", width: 48, height: 35, x: 245, y: 103, action: tearPaper)
                .disabled(printer.phase != .idle || store.currentItems.isEmpty || tearing || store.filter == .archive)

            if hovering {
                HStack(spacing: 7) {
                    Text(printer.phase == .idle ? "⌃⌥Space 随手记" : printer.phase == .receiving ? "接收中…" : "正在慢慢打印…")
                    Spacer()
                    Menu {
                        Button("写一条待办…", action: add)
                        Button("撤销上次更改") { store.undo() }.disabled(!store.canUndo)
                        Divider()
                        Picker("纸条内容", selection: $store.filter) {
                            Text("全部事项").tag(ReceiptFilter.all)
                            Text("待办事项").tag(ReceiptFilter.pending)
                            Text("已完成").tag(ReceiptFilter.completed)
                            Text("撕下的纸条").tag(ReceiptFilter.archive)
                        }
                        Toggle("机械与打印声音", isOn: $store.soundEnabled)
                        Toggle("保持在所有窗口最前", isOn: $settings.alwaysOnTop)
                        Button("撕下当前纸条", action: tearPaper)
                            .disabled(printer.phase != .idle || store.currentItems.isEmpty || tearing || store.filter == .archive)
                        Button("查看撕下的纸条") { store.filter = .archive }
                        Button("导出备份…", action: export)
                        Button("隐藏桌面打印机", action: hide)
                    } label: { Image(systemName: "ellipsis").frame(width: 18, height: 16) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                    .accessibilityLabel("打印机设置")
                }
                .font(.system(size: 9, weight: .medium)).foregroundStyle(Color.white.opacity(0.92))
                .padding(.horizontal, 9).frame(width: 220, height: 24)
                .background(Capsule().fill(Color.black.opacity(0.38)))
                .position(x: 172, y: totalHeight - 12)
                .transition(.opacity)
            }
        }
        .frame(width: width, height: totalHeight, alignment: .top)
        .onAppear { resize(totalHeight) }
        .onChange(of: totalHeight) { _, height in resize(height) }
        .onHover { hovering = $0 }
        .contextMenu {
            Button("写一条待办…", action: add)
            Button("撤销上次更改") { store.undo() }.disabled(!store.canUndo)
            Button("撕下当前纸条", action: tearPaper)
                .disabled(printer.phase != .idle || store.currentItems.isEmpty || tearing || store.filter == .archive)
            Toggle("保持在所有窗口最前", isOn: $settings.alwaysOnTop)
            Divider()
            Button("导出清单备份…", action: export)
            Button("隐藏桌面打印机", action: hide)
        }
        .preferredColorScheme(.light)
    }

    private func stickerButton(_ title: String, width: CGFloat, height: CGFloat, x: CGFloat, y: CGFloat, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Color.white.opacity(0.001).frame(width: width, height: height).contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain).position(x: x, y: y).help(title).accessibilityLabel(title)
    }

    private func tearPaper() {
        guard printer.phase == .idle, !tearing, !store.currentItems.isEmpty, store.filter != .archive else { return }
        tearing = true
        ButtonFeedback.play()
        printer.tearSound()
        withAnimation(.easeIn(duration: 0.42)) { tearOffset = 210; tearAngle = 5; tearOpacity = 0 }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.44) {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                store.tearCurrentPaper()
                tearOffset = 0; tearAngle = 0; tearOpacity = 1; tearing = false
            }
        }
    }

    private var receipt: some View {
        VStack(spacing: 0) {
            if let current {
                FeedingRow(progress: printer.progress, height: DesktopMetrics.rowHeight(current.text) + (printedItems.isEmpty ? 0 : 14)) {
                    VStack(spacing: 0) {
                        row(current, printing: true)
                        if !printedItems.isEmpty { StarDivider() }
                    }
                }
            }
            ForEach(Array(printedItems.enumerated()), id: \.element.id) { index, item in
                if index > 0 { StarDivider() }
                row(item)
            }
            StarDivider().padding(.top, 4)
            HStack {
                ThermalText(text: "待办 \(String(format: "%02d", store.pendingCount))", size: 9)
                Spacer()
                ThermalText(text: "完成 \(String(format: "%02d", store.completedCount))", size: 9)
            }
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .foregroundStyle(Color.ink.opacity(0.7)).padding(.top, 11)
            HStack(spacing: 5) {
                ThermalText(text: "BusyBoy  ·  " + Date.now.formatted(.dateTime.year().month(.twoDigits).day(.twoDigits)), size: 7)
            }
            .font(.system(size: 7, design: .monospaced)).foregroundStyle(Color.mutedInk)
            .padding(.top, 14).padding(.bottom, 18)
        }
        .padding(.horizontal, 19)
        .frame(width: paperWidth)
        .fixedSize(horizontal: false, vertical: true)
        .background {
            ThermalPaperShape().fill(LinearGradient(colors: [Color(hex: 0xF4F4F0), Color(hex: 0xFFFFFF), Color(hex: 0xFCFCF9)], startPoint: .top, endPoint: .bottom))
                .shadow(color: .black.opacity(0.24), radius: 5, x: 2, y: 6)
                .overlay {
                    Image(nsImage: PrinterArtwork.paper).resizable(resizingMode: .tile)
                        .blendMode(.multiply).opacity(0.22).clipShape(ThermalPaperShape()).accessibilityHidden(true)
                }
                .overlay(alignment: .top) {
                    LinearGradient(stops: [
                        .init(color: .black.opacity(0.3), location: 0),
                        .init(color: .black.opacity(0.07), location: 0.12),
                        .init(color: .white.opacity(0.34), location: 0.43),
                        .init(color: .white.opacity(0.1), location: 0.72),
                        .init(color: .black.opacity(0.018), location: 0.87),
                        .init(color: .clear, location: 1)
                    ], startPoint: .top, endPoint: .bottom)
                    .frame(height: 60).clipShape(ThermalPaperShape())
                }
        }
    }

    private func row(_ item: TodoItem, printing: Bool = false) -> some View {
        DesktopReceiptRow(item: item, index: (store.items.firstIndex { $0.id == item.id } ?? 0) + 1,
                          printing: printing,
                          toggle: { withAnimation(.easeInOut(duration: 0.2)) { store.toggle(item.id) } },
                          edit: { edit(item) }, delete: { withAnimation { store.delete(item.id) } })
    }
}

private enum PrinterArtwork {
    static let image: NSImage = {
        let url = Bundle.main.url(forResource: "printer-busyboy", withExtension: "png")
            ?? Bundle.module.url(forResource: "printer-busyboy", withExtension: "png")!
        return NSImage(contentsOf: url)!
    }()
    static let paper: NSImage = {
        let url = Bundle.main.url(forResource: "thermal-paper", withExtension: "png")
            ?? Bundle.module.url(forResource: "thermal-paper", withExtension: "png")!
        return NSImage(contentsOf: url)!
    }()
}

private struct FeedingRow<Content: View>: View {
    var progress: CGFloat
    var height: CGFloat
    @ViewBuilder var content: () -> Content
    var body: some View {
        content().fixedSize(horizontal: false, vertical: true)
            .scaleEffect(x: 1, y: 0.88 + progress * 0.12, anchor: .top)
            .frame(height: height * progress, alignment: .top)
            .clipped()
    }
}

enum DesktopMetrics {
    static let mouthY: CGFloat = 146
    static func rowHeight(_ text: String) -> CGFloat {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 4
        let bounds = NSAttributedString(string: text, attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular),
            .paragraphStyle: paragraph
        ]).boundingRect(with: NSSize(width: 201, height: 10000), options: [.usesLineFragmentOrigin, .usesFontLeading])
        return max(20, ceil(bounds.height) + 17) + 26
    }
}

private struct DesktopReceiptRow: View {
    let item: TodoItem
    let index: Int
    var printing = false
    var toggle: () -> Void
    var edit: () -> Void
    var delete: () -> Void

    var body: some View {
        Button(action: toggle) {
            VStack(alignment: .leading, spacing: 6) {
                ThermalText(text: item.text, size: 13)
                    .lineSpacing(4).fixedSize(horizontal: false, vertical: true)
                    .opacity(item.isCompleted ? 0.68 : 0.92)
                    .overlay {
                        if item.isCompleted { MarkerStrike(text: item.text, seed: index, fontSize: 13, lineSpacing: 4).allowsHitTesting(false) }
                    }
                ThermalText(text: "\(String(format: "%03d", index))  ·  \(item.createdAt.formatted(.dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits)))", size: 7)
                    .opacity(0.45)
            }
            .padding(.top, 3).frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 13)
        }
        .buttonStyle(.plain).disabled(printing)
        .accessibilityLabel(item.isCompleted ? "恢复待办：\(item.text)" : "完成：\(item.text)")
        .help(item.isCompleted ? "点击文字恢复待办" : "点击文字，用马克笔划掉")
        .contentShape(Rectangle())
        .contextMenu {
            Button(item.isCompleted ? "恢复为待办" : "用马克笔划掉", action: toggle)
            Button("编辑待办…", action: edit)
            Divider()
            Button("删除待办", role: .destructive, action: delete)
        }
        .accessibilityElement(children: .contain)
    }
}

private struct FeedButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(Capsule().fill(.black.opacity(configuration.isPressed ? 0.13 : 0)).frame(width: 29, height: 10))
            .offset(y: configuration.isPressed ? 0.7 : 0)
            .onChange(of: configuration.isPressed) { _, pressed in
                if pressed { Task { @MainActor in ButtonFeedback.play() } }
            }
    }
}
