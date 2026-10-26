import AppKit
import SwiftUI

struct PomodoroSession: Codable {
    var remainingSeconds: Int
    var mode: PomodoroModel.Mode
    var deadline: TimeInterval?
}

@MainActor
final class PomodoroModel: ObservableObject {
    enum Mode: String, Codable { case focus, rest }
    private let defaults: UserDefaults
    private let automaticTicks: Bool
    private var ticker: Task<Void, Never>?
    private var deadline: Date?
    @Published private(set) var mode: Mode = .focus
    @Published private(set) var isRunning = false
    @Published private(set) var remainingSeconds: Int
    @Published private(set) var completedRounds = 0
    @Published var focusMinutes: Int { didSet { defaults.set(focusMinutes, forKey: "pomodoroFocusMinutes"); if !isRunning && mode == .focus { reset() } } }
    @Published var restMinutes: Int { didSet { defaults.set(restMinutes, forKey: "pomodoroRestMinutes"); if !isRunning && mode == .rest { reset() } } }
    @Published var soundEnabled: Bool { didSet { defaults.set(soundEnabled, forKey: "pomodoroSound") } }

    init(defaults: UserDefaults = .standard, automaticTicks: Bool = true) {
        self.defaults = defaults
        self.automaticTicks = automaticTicks
        let focus = defaults.integer(forKey: "pomodoroFocusMinutes")
        let rest = defaults.integer(forKey: "pomodoroRestMinutes")
        focusMinutes = (1...99).contains(focus) ? focus : 25
        restMinutes = (1...30).contains(rest) ? rest : 5
        remainingSeconds = ((1...99).contains(focus) ? focus : 25) * 60
        soundEnabled = defaults.object(forKey: "pomodoroSound") as? Bool ?? true
    }

    var timeString: String { String(format: "%02d:%02d", remainingSeconds / 60, remainingSeconds % 60) }
    var actionTitle: String {
        if isRunning { return "暂停" }
        if remainingSeconds == 0 { return mode == .focus ? "开始休息" : "开始专注" }
        return remainingSeconds == (mode == .focus ? focusMinutes : restMinutes) * 60 ? "开始" : "继续"
    }

    func selectMode(_ value: Mode) {
        guard !isRunning else { return }
        mode = value
        reset()
    }

    func toggle(now: Date = Date()) {
        if isRunning {
            tick(now: now)
            isRunning = false; deadline = nil; ticker?.cancel(); ticker = nil
            return
        }
        if remainingSeconds == 0 { mode = mode == .focus ? .rest : .focus; reset() }
        deadline = now.addingTimeInterval(Double(remainingSeconds))
        isRunning = true
        startTicker()
    }

    /// Reconnect an active timer when installing an updated local build.
    func restoreSession(_ session: PomodoroSession, now: Date = Date()) {
        ticker?.cancel(); ticker = nil; deadline = nil; isRunning = false
        mode = session.mode
        let limit = mode == .focus ? 99 * 60 : 30 * 60
        let restoredDeadline = session.deadline.map { Date(timeIntervalSince1970: $0) }
        remainingSeconds = max(0, min(limit, Int(ceil(restoredDeadline?.timeIntervalSince(now) ?? Double(session.remainingSeconds)))))
        if let restoredDeadline, remainingSeconds > 0 {
            deadline = restoredDeadline
            isRunning = true
            startTicker()
        }
    }

    private func startTicker() {
        guard automaticTicks else { return }
        ticker?.cancel()
        ticker = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled, let self, self.isRunning else { return }
                self.tick()
            }
        }
    }

    func tick(now: Date = Date()) {
        guard isRunning, let deadline else { return }
        let value = max(0, Int(ceil(deadline.timeIntervalSince(now))))
        if remainingSeconds != value { remainingSeconds = value }
        if value == 0 {
            isRunning = false; self.deadline = nil; ticker?.cancel(); ticker = nil
            if mode == .focus { completedRounds += 1 }
            if soundEnabled { NSSound(named: "Glass")?.play() }
        }
    }

    func reset() {
        ticker?.cancel(); ticker = nil; deadline = nil; isRunning = false
        remainingSeconds = (mode == .focus ? focusMinutes : restMinutes) * 60
    }
}

struct PomodoroView: View {
    @ObservedObject var model: PomodoroModel
    var close: () -> Void
    var showSettings: () -> Void
    private let glow = Color(hex: 0xA4FF76)

    var body: some View {
        VStack(spacing: 9) {
            VStack(spacing: 0) {
                SevenSegmentTime(value: model.timeString).frame(width: 208, height: 62)
                    .accessibilityLabel("剩余 \(model.remainingSeconds / 60) 分 \(model.remainingSeconds % 60) 秒")
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .background {
                RoundedRectangle(cornerRadius: 7).fill(Color(hex: 0x051208))
                    .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Color.black.opacity(0.8), lineWidth: 2))
                    .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color(hex: 0x52634B).opacity(0.35), lineWidth: 0.6).padding(2))
                    .overlay {
                        Canvas { context, size in
                            for line in 0..<Int(size.height / 3) {
                                context.fill(Path(CGRect(x: 0, y: CGFloat(line) * 3, width: size.width, height: 0.35)), with: .color(.black.opacity(0.16)))
                            }
                        }.clipShape(RoundedRectangle(cornerRadius: 7)).allowsHitTesting(false)
                    }
            }

            HStack(spacing: 6) {
                modeButton("专注", mode: .focus)
                modeButton("休息", mode: .rest)
                Spacer(minLength: 0)
                Button { model.toggle() } label: {
                    Image(systemName: model.isRunning ? "pause.fill" : "play.fill").font(.system(size: 12)).frame(width: 39, height: 25)
                }.buttonStyle(TactileButtonStyle()).accessibilityLabel(model.actionTitle)
                Button { model.reset() } label: { Image(systemName: "arrow.counterclockwise").font(.system(size: 12, weight: .medium)).frame(width: 27, height: 25) }
                    .buttonStyle(TactileButtonStyle()).help("重置本轮")
                Button(action: showSettings) { Image(systemName: "gearshape").font(.system(size: 12)).frame(width: 27, height: 25) }
                    .buttonStyle(TactileButtonStyle()).help("设置番茄钟时长")

            }.frame(width: 198)
        }
        .padding(16).frame(width: LiftGeometry.boardWidth, height: LiftGeometry.boardHeight)
        .preferredColorScheme(.light).onExitCommand(perform: close)
    }

    private func modeButton(_ title: String, mode: PomodoroModel.Mode) -> some View {
        Button { ButtonFeedback.play(); model.selectMode(mode) } label: {
            Text(title).font(.system(size: 9, weight: .medium)).foregroundStyle(model.mode == mode ? Color(hex: 0x4A6050) : Color(hex: 0x9A9F9C))
                .padding(.horizontal, 6).frame(height: 22)
                .background(Capsule().fill(.black.opacity(model.mode == mode ? 0.07 : 0)))
        }.buttonStyle(.plain).disabled(model.isRunning)
    }
}

struct PomodoroSettingsView: View {
    @ObservedObject var model: PomodoroModel
    var close: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 17) {
            Text("番茄时钟").font(.system(size: 14, weight: .medium))
            VStack(spacing: 14) {
                Stepper("专注：\(model.focusMinutes) 分钟", value: $model.focusMinutes, in: 1...99)
                Stepper("休息：\(model.restMinutes) 分钟", value: $model.restMinutes, in: 1...30)
            }.disabled(model.isRunning)
            Toggle("结束提示音", isOn: $model.soundEnabled)
            HStack {
                if model.isRunning { Text("暂停后可调整时长").font(.system(size: 10)).foregroundStyle(.secondary) }
                Spacer()
                Button("完成", action: close).keyboardShortcut(.defaultAction)
            }
        }
        .font(.system(size: 12)).padding(24).frame(width: 300, height: 220)
        .background(WhiteHousing()).preferredColorScheme(.light).onExitCommand(perform: close)
    }
}

struct SevenSegmentTime: View {
    let value: String
    var body: some View {
        Canvas { context, size in
            let characters = Array(value)
            let total: CGFloat = 4 * 40 + 14 + 4 * 5
            let scale = min(size.width / total, size.height / 70)
            context.translateBy(x: (size.width - total * scale) / 2, y: (size.height - 70 * scale) / 2)
            context.scaleBy(x: scale, y: scale)
            var x: CGFloat = 0
            for character in characters {
                if character == ":" {
                    for y in [CGFloat(24), CGFloat(47)] {
                        let dot = Path(roundedRect: CGRect(x: x + 4, y: y, width: 5, height: 5), cornerRadius: 1)
                        context.fill(dot, with: .color(Color(hex: 0xA4FF76)))
                    }
                    x += 19
                } else if let digit = character.wholeNumberValue {
                    let active = Set([[0,1,2,3,4,5],[1,2],[0,1,6,4,3],[0,1,6,2,3],[5,6,1,2],[0,5,6,2,3],[0,5,6,4,2,3],[0,1,2],[0,1,2,3,4,5,6],[0,1,2,3,5,6]][digit])
                    let segments: [[CGPoint]] = [
                        [CGPoint(x:7,y:2),CGPoint(x:33,y:2),CGPoint(x:36,y:5),CGPoint(x:32,y:8),CGPoint(x:8,y:8),CGPoint(x:4,y:5)],
                        [CGPoint(x:34,y:8),CGPoint(x:39,y:6),CGPoint(x:39,y:30),CGPoint(x:35,y:34),CGPoint(x:33,y:30)],
                        [CGPoint(x:35,y:37),CGPoint(x:39,y:40),CGPoint(x:39,y:64),CGPoint(x:34,y:62),CGPoint(x:33,y:41)],
                        [CGPoint(x:8,y:63),CGPoint(x:32,y:63),CGPoint(x:36,y:66),CGPoint(x:33,y:69),CGPoint(x:7,y:69),CGPoint(x:4,y:66)],
                        [CGPoint(x:5,y:37),CGPoint(x:7,y:41),CGPoint(x:6,y:62),CGPoint(x:1,y:64),CGPoint(x:1,y:40)],
                        [CGPoint(x:1,y:6),CGPoint(x:6,y:8),CGPoint(x:7,y:30),CGPoint(x:5,y:34),CGPoint(x:1,y:30)],
                        [CGPoint(x:8,y:32),CGPoint(x:32,y:32),CGPoint(x:36,y:35),CGPoint(x:32,y:38),CGPoint(x:8,y:38),CGPoint(x:4,y:35)]
                    ]
                    for (index, points) in segments.enumerated() {
                        var path = Path(); path.addLines(points.map { CGPoint(x: $0.x + x, y: $0.y) }); path.closeSubpath()
                        if active.contains(index) {
                            var glow = context
                            glow.addFilter(.shadow(color: Color(hex: 0x82FF58).opacity(0.55), radius: 3))
                            glow.fill(path, with: .color(Color(hex: 0xA4FF76)))
                        } else { context.fill(path, with: .color(Color(hex: 0x17351A).opacity(0.58))) }
                    }
                    x += 45
                }
            }
        }
    }
}
