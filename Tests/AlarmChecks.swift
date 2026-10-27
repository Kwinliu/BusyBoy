import AppKit
import AVFoundation

@MainActor
enum AlarmChecks {
    static func run() throws {
        let suite = "com.paperdesk.AlarmChecks.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "Etc/UTC")!
        let before = date("2026-10-27T07:29:50Z")
        let model = AlarmClockModel(defaults: defaults, automaticTicks: false, now: before, calendar: utc)
        var rings = 0
        var stops = 0
        model.onRing = { rings += 1 }
        model.onStop = { stops += 1 }
        try check(!model.configuration.enabled && model.nextFire == nil, "闹钟默认关闭")
        try check(model.clockString == "07:29:50", "本地时钟按小时、分钟、秒显示")
        model.displayMode = .clock
        model.configure(hour: 7, minute: 30, repeatsDaily: true, enabled: true, soundEnabled: false, now: before)
        try check(model.nextFire == date("2026-10-27T07:30:00Z"), "今日尚未到点的闹钟")
        let restored = AlarmClockModel(defaults: defaults, automaticTicks: false, now: before, calendar: utc)
        try check(restored.displayMode == .clock && restored.configuration.enabled && restored.nextFire == model.nextFire, "显示模式、开关与下次响铃时间持久化")
        model.tick(now: date("2026-10-27T07:30:00Z"))
        model.tick(now: date("2026-10-27T07:30:15Z"))
        try check(rings == 1 && model.isRinging && model.nextFire == date("2026-10-28T07:30:00Z"), "每天到点仅触发一次并安排下一天")
        model.tick(now: date("2026-10-27T07:31:00Z"))
        try check(!model.isRinging && stops == 1, "无人操作时一分钟后停止响铃")

        model.configure(hour: 7, minute: 30, repeatsDaily: false, enabled: true, soundEnabled: false, now: before)
        model.tick(now: date("2026-10-27T07:30:02Z"))
        try check(rings == 2 && !model.configuration.enabled && model.nextFire == nil, "单次闹钟响后自动关闭")
        let onceRestored = AlarmClockModel(defaults: defaults, automaticTicks: false, now: date("2026-10-27T07:30:05Z"), calendar: utc)
        onceRestored.onRing = { rings += 1 }
        onceRestored.tick(now: date("2026-10-27T07:30:05Z"))
        try check(rings == 2, "重新打开应用不重复响已经触发的单次闹钟")

        model.snooze(now: date("2026-10-27T07:30:10Z"))
        try check(!model.isRinging && model.snoozedUntil == date("2026-10-27T07:35:10Z"), "稍后五分钟并立即停止响铃")
        let snoozed = AlarmClockModel(defaults: defaults, automaticTicks: false, now: date("2026-10-27T07:31:00Z"), calendar: utc)
        var snoozeRings = 0
        snoozed.onRing = { snoozeRings += 1 }
        snoozed.tick(now: date("2026-10-27T07:35:09Z"))
        try check(snoozeRings == 0, "贪睡倒计时未到点不响")
        snoozed.tick(now: date("2026-10-27T07:35:10Z"))
        snoozed.tick(now: date("2026-10-27T07:35:11Z"))
        try check(snoozeRings == 1 && snoozed.snoozedUntil == nil, "重启后单次闹钟仍能在五分钟后再次提醒且不重复")
        snoozed.snooze(now: date("2026-10-27T07:35:12Z"))
        snoozed.setEnabled(false, now: date("2026-10-27T07:35:15Z"))
        try check(snoozed.snoozedUntil == nil && !snoozed.isRinging, "关闭闹钟取消贪睡")

        model.configure(hour: 7, minute: 30, repeatsDaily: true, enabled: true, soundEnabled: false, now: before)
        model.tick(now: date("2026-10-27T07:34:00Z"))
        try check(model.isRinging, "唤醒后五分钟内补响")
        model.stopRinging()
        let count = rings
        model.tick(now: date("2026-10-29T12:00:00Z"))
        try check(rings == count && model.nextFire == date("2026-10-30T07:30:00Z"), "长时间睡眠后不连响历史闹钟")
        model.configure(hour: 23, minute: 50, repeatsDaily: false, enabled: true, soundEnabled: false, now: date("2026-10-27T23:51:00Z"))
        try check(model.nextFire == date("2026-10-28T23:50:00Z"), "已过时间安排到明天")
        let valid = model.configuration
        model.configure(hour: 25, minute: -1, repeatsDaily: false, enabled: true, soundEnabled: true, now: before)
        try check(model.configuration == valid, "非法时间不覆盖现有闹钟")

        var newYork = Calendar(identifier: .gregorian)
        newYork.timeZone = TimeZone(identifier: "America/New_York")!
        let spring = AlarmClockModel(defaults: UserDefaults(suiteName: suite + ".dst")!, automaticTicks: false,
                                     now: date("2026-03-08T06:00:00Z"), calendar: newYork)
        defer { UserDefaults.standard.removePersistentDomain(forName: suite + ".dst") }
        spring.configure(hour: 2, minute: 30, repeatsDaily: true, enabled: true, soundEnabled: false, now: date("2026-03-08T06:00:00Z"))
        try check(spring.nextFire == date("2026-03-08T07:00:00Z"), "夏令时跳过的时刻顺延到下一个有效时刻")
        spring.configure(hour: 1, minute: 30, repeatsDaily: true, enabled: true, soundEnabled: false, now: date("2026-11-01T04:00:00Z"))
        try check(spring.nextFire == date("2026-11-01T05:30:00Z"), "冬令时重复时刻选择第一次")
        spring.tick(now: date("2026-11-01T05:30:00Z"))
        spring.stopRinging()
        try check(spring.nextFire == date("2026-11-02T06:30:00Z"), "每天闹钟不会在冬令时重复时刻再次响铃")

        let pomodoro = PomodoroModel(defaults: defaults, automaticTicks: false)
        pomodoro.soundEnabled = false
        pomodoro.toggle(now: before)
        model.displayMode = .alarm
        model.displayMode = .clock
        pomodoro.tick(now: before.addingTimeInterval(20))
        try check(pomodoro.isRunning && pomodoro.remainingSeconds == 25 * 60 - 20, "切换时钟与闹钟不影响番茄倒计时")
        let chime = try AVAudioPlayer(data: PrinterAudio.alarmWave())
        try check(abs(chime.duration - 2.5) < 0.001, "独立闹钟铃声可解码且保留间隔")
        print("PASS  本地时钟、每日/单次闹钟、设置持久化、停止与五分钟贪睡")
        print("PASS  唤醒补响、避免重复、跨日与夏令时，切换不打断番茄计时")
    }
    private static func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
    private static func check(_ value: @autoclosure () -> Bool, _ message: String) throws {
        if !value() { throw AlarmFailure(description: message) }
    }
}
private struct AlarmFailure: Error, CustomStringConvertible { let description: String }
