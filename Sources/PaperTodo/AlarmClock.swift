import AppKit
import SwiftUI

enum TimerDisplayMode: String, CaseIterable, Identifiable {
    case pomodoro, clock, alarm
    var id: String { rawValue }
    var title: String {
        switch self { case .pomodoro: return "番茄"; case .clock: return "时钟"; case .alarm: return "闹钟" }
    }
}

struct AlarmConfiguration: Codable, Equatable {
    var hour = 7
    var minute = 30
    var repeatsDaily = true
    var enabled = false
    var soundEnabled = true
    var timeString: String { String(format: "%02d:%02d", hour, minute) }
}

private struct SavedAlarm: Codable {
    var configuration: AlarmConfiguration
    var nextFire: Date?
    var snoozedUntil: Date?
    var timeZoneID: String
}

/// Owns the alarm independently of the backboard's SwiftUI lifetime.
/// Calendar matching preserves the selected wall-clock time across DST changes.
@MainActor
final class AlarmClockModel: ObservableObject {
    private let defaults: UserDefaults
    private let fixedCalendar: Calendar?
    private var ticker: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []
    private var timeZoneID: String
    @Published var displayMode: TimerDisplayMode {
        didSet { defaults.set(displayMode.rawValue, forKey: "timerDisplayMode") }
    }
    @Published private(set) var now: Date
    @Published private(set) var configuration: AlarmConfiguration
    @Published private(set) var nextFire: Date?
    @Published private(set) var snoozedUntil: Date?
    @Published private(set) var ringingSince: Date?
    var onRing: (() -> Void)?
    var onStop: (() -> Void)?
    var isRinging: Bool { ringingSince != nil }
    private var calendar: Calendar { fixedCalendar ?? .autoupdatingCurrent }

    init(defaults: UserDefaults = .standard, automaticTicks: Bool = true,
         now: Date = Date(), calendar: Calendar? = nil) {
        self.defaults = defaults
        self.fixedCalendar = calendar
        self.now = now
        self.timeZoneID = (calendar ?? .autoupdatingCurrent).timeZone.identifier
        displayMode = TimerDisplayMode(rawValue: defaults.string(forKey: "timerDisplayMode") ?? "") ?? .pomodoro
        let saved = defaults.data(forKey: "deskAlarm.v1").flatMap { try? JSONDecoder().decode(SavedAlarm.self, from: $0) }
        if let saved, (0...23).contains(saved.configuration.hour), (0...59).contains(saved.configuration.minute) {
            configuration = saved.configuration
            nextFire = saved.configuration.enabled ? saved.nextFire : nil
            snoozedUntil = saved.snoozedUntil
            if saved.timeZoneID != timeZoneID { nextFire = nil }
        } else {
            configuration = AlarmConfiguration()
        }
        if configuration.enabled && nextFire == nil { nextFire = nextOccurrence(after: now) }
        if automaticTicks {
            ticker = Task { [weak self] in
                while !Task.isCancelled {
                    self?.tick()
                    try? await Task.sleep(for: .seconds(1))
                }
            }
            observers.append(NotificationCenter.default.addObserver(forName: .NSSystemTimeZoneDidChange, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.timeEnvironmentChanged() }
            })
            observers.append(NotificationCenter.default.addObserver(forName: .NSSystemClockDidChange, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.timeEnvironmentChanged() }
            })
        }
    }

    deinit {
        ticker?.cancel()
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    var clockString: String {
        let parts = calendar.dateComponents([.hour, .minute, .second], from: now)
        return String(format: "%02d:%02d:%02d", parts.hour ?? 0, parts.minute ?? 0, parts.second ?? 0)
    }
    var dateString: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "zh_CN")
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = "M月d日 EEEE"
        return formatter.string(from: now)
    }
    var alarmStatus: String {
        if isRinging { return "时间到了" }
        if let snoozedUntil {
            let seconds = max(0, Int(ceil(snoozedUntil.timeIntervalSince(now))))
            return String(format: "稍后 %02d:%02d", seconds / 60, seconds % 60)
        }
        if !configuration.enabled { return "未开启" }
        let day = nextFire.map { calendar.isDate($0, inSameDayAs: now) ? "今天" : "明天" } ?? ""
        return day + " · " + (configuration.repeatsDaily ? "每天" : "仅一次")
    }
    var alarmStateLabel: String {
        if isRinging { return "响铃中" }
        if snoozedUntil != nil { return "稍后" }
        return configuration.enabled ? "已开启" : "未开启"
    }

    func configure(hour: Int, minute: Int, repeatsDaily: Bool, enabled: Bool,
                   soundEnabled: Bool, now: Date = Date()) {
        guard (0...23).contains(hour), (0...59).contains(minute) else { return }
        stopRinging()
        self.now = now
        configuration = AlarmConfiguration(hour: hour, minute: minute, repeatsDaily: repeatsDaily, enabled: enabled, soundEnabled: soundEnabled)
        snoozedUntil = nil
        nextFire = enabled ? nextOccurrence(after: now) : nil
        timeZoneID = calendar.timeZone.identifier
        persist()
    }

    func setEnabled(_ enabled: Bool, now: Date = Date()) {
        configure(hour: configuration.hour, minute: configuration.minute,
                  repeatsDaily: configuration.repeatsDaily, enabled: enabled,
                  soundEnabled: configuration.soundEnabled, now: now)
    }

    func tick(now: Date = Date()) {
        self.now = now
        if timeZoneID != calendar.timeZone.identifier {
            timeZoneID = calendar.timeZone.identifier
            nextFire = configuration.enabled ? nextOccurrence(after: now) : nil
            persist()
        }
        // Bound unattended ringing to one minute.
        if let ringingSince, now.timeIntervalSince(ringingSince) >= 60 { stopRinging() }
        if let snooze = snoozedUntil, snooze <= now {
            snoozedUntil = nil
            persist()
            if now.timeIntervalSince(snooze) <= 5 * 60 { ring(now: now) }
        }
        guard configuration.enabled, let fire = nextFire, fire <= now else { return }
        if configuration.repeatsDaily { nextFire = nextOccurrence(after: now) }
        else { configuration.enabled = false; nextFire = nil }
        // Persist before notifying UI so repeated ticks / relaunch cannot ring twice.
        persist()
        if now.timeIntervalSince(fire) <= 5 * 60 { ring(now: now) }
    }

    func stopRinging() {
        guard isRinging else { return }
        ringingSince = nil
        onStop?()
    }

    func snooze(now: Date = Date()) {
        guard isRinging else { return }
        stopRinging()
        self.now = now
        snoozedUntil = now.addingTimeInterval(5 * 60)
        persist()
    }

    func timeEnvironmentChanged(now: Date = Date()) {
        tick(now: now)
        timeZoneID = calendar.timeZone.identifier
        nextFire = configuration.enabled ? nextOccurrence(after: now) : nil
        persist()
    }

    private func ring(now: Date) {
        guard !isRinging else { return }
        ringingSince = now
        onRing?()
    }
    private func nextOccurrence(after now: Date) -> Date? {
        calendar.nextDate(after: now, matching: DateComponents(hour: configuration.hour, minute: configuration.minute, second: 0),
                          matchingPolicy: .nextTime, repeatedTimePolicy: .first, direction: .forward)
    }
    private func persist() {
        let state = SavedAlarm(configuration: configuration, nextFire: nextFire, snoozedUntil: snoozedUntil, timeZoneID: timeZoneID)
        if let data = try? JSONEncoder().encode(state) { defaults.set(data, forKey: "deskAlarm.v1") }
    }
}

struct AlarmSettingsView: View {
    @ObservedObject var model: AlarmClockModel
    var close: () -> Void
    @State private var time: Date
    @State private var repeatsDaily: Bool
    @State private var enabled: Bool
    @State private var soundEnabled: Bool

    init(model: AlarmClockModel, close: @escaping () -> Void) {
        self.model = model; self.close = close
        let value = model.configuration
        _time = State(initialValue: Calendar.current.date(from: DateComponents(year: 2001, month: 1, day: 1, hour: value.hour, minute: value.minute)) ?? .now)
        _repeatsDaily = State(initialValue: value.repeatsDaily)
        _enabled = State(initialValue: value.enabled)
        _soundEnabled = State(initialValue: value.soundEnabled)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("闹钟").font(.system(size: 14, weight: .medium))
            DatePicker("时间", selection: $time, displayedComponents: .hourAndMinute)
                .datePickerStyle(.field).environment(\.locale, Locale(identifier: "en_GB"))
            Picker("重复", selection: $repeatsDaily) {
                Text("仅一次").tag(false)
                Text("每天").tag(true)
            }.pickerStyle(.segmented)
            HStack {
                Toggle("开启", isOn: $enabled)
                Spacer()
                Toggle("响铃", isOn: $soundEnabled)
            }
            Text("需保持应用运行；睡眠时不会唤醒 Mac。")
                .font(.system(size: 9)).foregroundStyle(.secondary)
            HStack {
                Button("取消", action: close).keyboardShortcut(.cancelAction)
                Spacer()
                Button("保存") {
                    let parts = Calendar.current.dateComponents([.hour, .minute], from: time)
                    model.configure(hour: parts.hour ?? 7, minute: parts.minute ?? 30,
                                    repeatsDaily: repeatsDaily, enabled: enabled, soundEnabled: soundEnabled)
                    close()
                }.keyboardShortcut(.defaultAction)
            }
        }
        .font(.system(size: 12)).padding(24).frame(width: 300, height: 264)
        .background(WhiteHousing()).preferredColorScheme(.light)
    }
}

struct AlarmRingingView: View {
    @ObservedObject var model: AlarmClockModel
    var body: some View {
        VStack(spacing: 16) {
            Label("时间到了", systemImage: "bell.fill")
                .font(.system(size: 13, weight: .medium)).foregroundStyle(Color(hex: 0x526657))
            GreenDigitalDisplay(value: model.configuration.timeString, leadingLabel: "闹钟")
            HStack(spacing: 12) {
                Button { model.snooze() } label: { Text("稍后 5 分钟").frame(width: 105, height: 30) }
                    .buttonStyle(TactileButtonStyle()).keyboardShortcut("s", modifiers: [])
                Button { model.stopRinging() } label: { Text("停止").frame(width: 80, height: 30) }
                    .buttonStyle(TactileButtonStyle()).keyboardShortcut(.defaultAction)
            }
            .font(.system(size: 11, weight: .medium))
        }
        .padding(24).frame(width: 300, height: 220)
        .background(WhiteHousing(profile: .soft)).preferredColorScheme(.light)
    }
}
