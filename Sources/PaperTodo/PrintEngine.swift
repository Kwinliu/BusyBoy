import AppKit
import SwiftUI

@MainActor
final class PrintEngine: ObservableObject {
    enum Phase: String { case idle, receiving, printing }
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var hiddenIDs: Set<UUID> = []
    @Published private(set) var currentID: UUID?
    @Published private(set) var progress: CGFloat = 0
    @Published private(set) var ledOn = true

    private var queue: [TodoItem] = []
    private var worker: Task<Void, Never>?
    private let audio = PrinterAudio()
    var soundEnabled = true {
        didSet { if !soundEnabled { audio.stop() } }
    }

    func tearSound() { if soundEnabled { audio.tearPaper() } }

    var status: String {
        switch phase {
        case .idle: return "准备好了 · 按机身上的按钮写一条待办"
        case .receiving: return "正在接收待办…"
        case .printing: return "正在打印，请稍候…"
        }
    }

    func enqueue(_ item: TodoItem) {
        guard !hiddenIDs.contains(item.id), currentID != item.id else { return }
        hiddenIDs.insert(item.id)
        queue.append(item)
        guard worker == nil else { return }
        worker = Task { [weak self] in await self?.processQueue() }
    }

    private func processQueue() async {
        while !queue.isEmpty, !Task.isCancelled {
            let item = queue.removeFirst()
            phase = .receiving
            for index in 0..<8 {
                ledOn = index.isMultiple(of: 2)
                try? await Task.sleep(for: .milliseconds(130))
            }
            currentID = item.id
            progress = 0
            phase = .printing
            let reduced = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
            let duration = reduced ? 0.25 : 2.2 + min(1.8, Double(item.text.count) / 55)
            // Give the zero-height row one render pass before feeding it out.
            try? await Task.sleep(for: .milliseconds(40))
            let ticks = max(1, Int(ceil(duration / 0.145)))
            if soundEnabled { audio.printPaper(duration: Double(ticks) * 0.145) }
            for index in 1...ticks {
                withAnimation(reduced ? nil : .linear(duration: 0.105)) {
                    progress = reduced ? 1 : CGFloat(index) / CGFloat(ticks)
                }
                ledOn = index % 3 != 0
                try? await Task.sleep(for: .milliseconds(145))
            }
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                hiddenIDs.remove(item.id)
                currentID = nil
                progress = 0
            }
            audio.stop()
        }
        phase = .idle
        ledOn = true
        worker = nil
    }
}
