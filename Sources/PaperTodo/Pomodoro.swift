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
    @ObservedObject var clock: AlarmClockModel
    var close: () -> Void
    var showSettings: () -> Void
    var showAlarmSettings: () -> Void

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 5) {
                ForEach(TimerDisplayMode.allCases) { mode in
                    Button { ButtonFeedback.play(); clock.displayMode = mode } label: {
                        Text(mode.title).font(.system(size: 9, weight: .medium))
                            .foregroundStyle(clock.displayMode == mode ? Color(hex: 0x465B4B) : Color(hex: 0x929A94))
                            .frame(width: 42, height: 19)
                            .background(Capsule().fill(.black.opacity(clock.displayMode == mode ? 0.07 : 0)))
                    }.buttonStyle(.plain).accessibilityLabel("切换到\(mode.title)")
                        .accessibilityAddTraits(clock.displayMode == mode ? .isSelected : [])
                }
                Spacer(minLength: 0)
                if clock.isRinging || clock.configuration.enabled || clock.snoozedUntil != nil {
                    Image(systemName: clock.isRinging ? "bell.badge.fill" : "bell.fill")
                        .font(.system(size: 9)).foregroundStyle(Color(hex: 0x6B7F68))
                        .accessibilityLabel(clock.isRinging ? "闹钟正在响铃" : "闹钟已设定")
                }
            }.frame(width: 232)

            GreenDigitalDisplay(value: displayValue,
                                leadingLabel: displayLeadingLabel,
                                leadingDetail: clock.displayMode == .alarm ? displayCaption : "")
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(displayAccessibilityLabel)

            Group {
                switch clock.displayMode {
                case .pomodoro: pomodoroControls
                case .clock:
                    HStack {
                        Text(clock.dateString)
                        Spacer()
                        Text("本地时间").foregroundStyle(Color(hex: 0x969D97))
                    }.font(.system(size: 9)).foregroundStyle(Color(hex: 0x637165))
                case .alarm: alarmControls
                }
            }.frame(width: 232, height: 25)
        }
        .frame(width: LiftGeometry.boardWidth, height: LiftGeometry.boardHeight)
        .preferredColorScheme(.light).onExitCommand(perform: close)
    }

    private var displayValue: String {
        switch clock.displayMode {
        case .pomodoro: return model.timeString
        case .clock: return clock.clockString
        case .alarm: return clock.configuration.timeString
        }
    }
    private var displayCaption: String {
        switch clock.displayMode {
        case .pomodoro: return model.mode == .focus ? "专注" : "休息"
        case .clock: return ""
        case .alarm:
            return clock.configuration.enabled || clock.isRinging || clock.snoozedUntil != nil
                ? clock.alarmStatus : (clock.configuration.repeatsDaily ? "每天" : "仅一次")
        }
    }
    private var displayLeadingLabel: String {
        switch clock.displayMode {
        case .pomodoro: return displayCaption
        case .clock: return ""
        case .alarm: return clock.alarmStateLabel
        }
    }
    private var displayAccessibilityLabel: String {
        switch clock.displayMode {
        case .pomodoro: return "剩余 \(model.remainingSeconds / 60) 分 \(model.remainingSeconds % 60) 秒"
        case .clock: return "本地时间 \(clock.clockString)"
        case .alarm: return "闹钟 \(clock.configuration.timeString)，\(clock.alarmStateLabel)，\(displayCaption)"
        }
    }

    private var pomodoroControls: some View {
        HStack(spacing: 6) {
            modeButton("专注", mode: .focus)
            modeButton("休息", mode: .rest)
            Spacer(minLength: 0)
            Button { model.toggle() } label: {
                Image(systemName: model.isRunning ? "pause.fill" : "play.fill").font(.system(size: 12)).frame(width: 32, height: 25)
            }
            .buttonStyle(TactileButtonStyle()).accessibilityLabel(model.actionTitle)
            Button { model.reset() } label: { Image(systemName: "arrow.counterclockwise").font(.system(size: 12, weight: .medium)).frame(width: 27, height: 25) }
                .buttonStyle(TactileButtonStyle()).help("重置本轮").accessibilityLabel("重置本轮")
            Button(action: showSettings) { Image(systemName: "gearshape").font(.system(size: 12)).frame(width: 27, height: 25) }
                .buttonStyle(TactileButtonStyle()).help("设置番茄钟时长").accessibilityLabel("设置番茄钟时长")
        }
    }

    private var alarmControls: some View {
        HStack(spacing: 7) {
            if clock.isRinging {
                Button { clock.snooze() } label: { Text("稍后 5 分钟").frame(width: 100, height: 25) }.buttonStyle(TactileButtonStyle())
                Button { clock.stopRinging() } label: { Text("停止").frame(width: 55, height: 25) }.buttonStyle(TactileButtonStyle())
            } else {
                Button { clock.setEnabled(!(clock.configuration.enabled || clock.snoozedUntil != nil)) } label: {
                    HStack(spacing: 4) {
                        Image(systemName: clock.configuration.enabled || clock.snoozedUntil != nil ? "bell.fill" : "bell.slash")
                        Text(clock.configuration.enabled || clock.snoozedUntil != nil ? "已开启" : "开启")
                    }.frame(width: 70, height: 25)
                }.buttonStyle(TactileButtonStyle())
                    .accessibilityLabel(clock.configuration.enabled || clock.snoozedUntil != nil ? "关闭闹钟" : "开启闹钟")
                Spacer(minLength: 0)
                Button(action: showAlarmSettings) {
                    Image(systemName: "gearshape").font(.system(size: 12)).frame(width: 27, height: 25)
                }.buttonStyle(TactileButtonStyle()).accessibilityLabel("设置闹钟")
            }
        }.font(.system(size: 9, weight: .medium))
    }

    private func modeButton(_ title: String, mode: PomodoroModel.Mode) -> some View {
        Button { ButtonFeedback.play(); model.selectMode(mode) } label: {
            Text(title).font(.system(size: 9, weight: .medium)).foregroundStyle(model.mode == mode ? Color(hex: 0x4A6050) : Color(hex: 0x9A9F9C))
                .padding(.horizontal, 6).frame(height: 22)
                .background(Capsule().fill(.black.opacity(model.mode == mode ? 0.07 : 0)))
        }.buttonStyle(.plain).disabled(model.isRunning)
    }
}

struct GreenDigitalDisplay: View {
    let value: String
    var leadingLabel = ""
    var leadingDetail = ""
    var body: some View {
        HStack(spacing: 8) {
            if !leadingLabel.isEmpty {
                VStack(spacing: 4) {
                    Text(leadingLabel).font(.system(size: 11, weight: .medium))
                        .foregroundStyle(Color(hex: 0xA4FF76))
                        .shadow(color: Color(hex: 0x82FF58).opacity(0.3), radius: 2)
                        .fixedSize()
                    ForEach(detailLines, id: \.self) { line in
                        Text(line).font(.system(size: 8, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color(hex: 0x98C986)).fixedSize()
                    }
                }
                .frame(width: leadingLabelWidth)
            }
            SevenSegmentTime(value: value)
                .frame(width: leadingLabel.isEmpty ? 208 : 200 - leadingLabelWidth, height: 60)
        }
        .frame(width: 232, height: 74)
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
    }
    private var leadingLabelWidth: CGFloat { leadingLabel.count > 2 ? 38 : 27 }
    private var detailLines: [String] {
        guard !leadingDetail.isEmpty else { return [] }
        return leadingDetail.replacingOccurrences(of: "稍后 ", with: "").components(separatedBy: " · ")
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
            let total = CGFloat(characters.reduce(0) { $0 + ($1 == ":" ? 19 : 45) } - 5)
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
