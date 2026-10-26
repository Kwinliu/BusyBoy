import AppKit
import SwiftUI
import AVFoundation

@main
@MainActor
enum StickerChecks {
    static func main() async throws {
        let suite = "com.paperdesk.StickerChecks.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = StickerSettings(defaults: defaults)
        try check(settings.clockCities.map(\.name) == ["伦敦", "墨西哥城"], "两个默认城市")
        let date = ISO8601DateFormatter().date(from: "2026-10-26T12:00:00Z")!
        try check(settings.clockCities.map { ClockDisplay.time(date, in: $0) } == ["12:00", "06:00"], "时区与夏令时")
        let legacy = [ClockCity(name: "莫斯科", timeZoneID: "Europe/Moscow"), ClockCity(name: "柏林", timeZoneID: "Europe/Berlin")] + ClockCity.defaults
        defaults.set(try JSONEncoder().encode(legacy), forKey: "worldClockCities")
        try check(StickerSettings(defaults: defaults).clockCities == ClockCity.defaults, "旧四城设置迁移为伦敦和墨西哥城")
        settings.changeClock(at: 0, to: .changchun)
        settings.weatherCity = GeoCity(id: 1, name: "测试", latitude: 0, longitude: 0, timezone: "Etc/UTC")
        let restored = StickerSettings(defaults: defaults)
        try check(restored.clockCities[0].name == "长春" && restored.weatherCity.id == 1, "城市设置持久化")
        print("PASS  世界时钟与城市设置")

        let data = Data(#"{"current":{"temperature_2m":12.4,"apparent_temperature":10.2,"relative_humidity_2m":60,"weather_code":2,"wind_speed_10m":3.2,"is_day":1},"daily":{"temperature_2m_max":[16.8],"temperature_2m_min":[4.5]}}"#.utf8)
        let weather = try JSONDecoder().decode(WeatherPayload.self, from: data).snapshot(for: .changchun, now: date)
        try check(weather.cityID == GeoCity.changchun.id && weather.condition == "多云" && weather.high == 16.8 && weather.wind == 3.2, "天气解码与单位")
        print("PASS  天气响应解析")

        let model = PomodoroModel(defaults: defaults, automaticTicks: false)
        model.soundEnabled = false
        try check(model.timeString == "25:00", "默认专注时长")
        model.focusMinutes = 1
        model.toggle(now: date)
        model.tick(now: date.addingTimeInterval(20.2))
        try check(model.remainingSeconds == 40, "按真实时间倒计时")
        model.toggle(now: date.addingTimeInterval(21))
        try check(!model.isRunning && model.remainingSeconds == 39, "暂停保留剩余时间")
        model.tick(now: date.addingTimeInterval(300))
        try check(model.remainingSeconds == 39, "暂停时不倒计时")
        model.toggle(now: date.addingTimeInterval(500))
        model.tick(now: date.addingTimeInterval(540))
        model.tick(now: date.addingTimeInterval(541))
        try check(!model.isRunning && model.remainingSeconds == 0 && model.completedRounds == 1, "到时只完成一次")
        model.toggle(now: date.addingTimeInterval(550))
        try check(model.mode == .rest && model.remainingSeconds == 300 && model.isRunning, "完成后进入休息")
        model.reset()
        try check(model.remainingSeconds == 300 && !model.isRunning, "重置当前阶段")
        let restoredTimer = PomodoroModel(defaults: defaults, automaticTicks: false)
        try check(restoredTimer.focusMinutes == 1 && !restoredTimer.soundEnabled, "时长与声音设置保存")
        let active = PomodoroModel(defaults: defaults, automaticTicks: false)
        active.restoreSession(PomodoroSession(remainingSeconds: 120, mode: .focus, deadline: date.addingTimeInterval(110).timeIntervalSince1970), now: date)
        try check(active.isRunning && active.remainingSeconds == 110, "更新后按原截止时间接续倒计时")
        active.tick(now: date.addingTimeInterval(20))
        try check(active.remainingSeconds == 90, "恢复后倒计时没有继续")
        active.restoreSession(PomodoroSession(remainingSeconds: 75, mode: .focus, deadline: nil), now: date)
        try check(!active.isRunning && active.remainingSeconds == 75, "恢复时丢失暂停状态")
        print("PASS  番茄钟暂停、恢复、结束、重置")
        for step in 0...100 {
            let progress = CGFloat(step) / 100
            for right in [false, true] {
                let joints = LiftGeometry.joints(deployment: progress, right: right)
                for pair in 0..<2 {
                    let length = hypot(joints[pair + 1].x - joints[pair].x, joints[pair + 1].y - joints[pair].y)
                    try check(abs(length - LiftGeometry.linkLength) < 0.0001, "关节运动中连杆长度变化")
                }
                try check(abs(joints[2].y - LiftGeometry.boardTop(progress) - LiftGeometry.attachmentY) < 0.0001, "背板连接点脱离")
            }
        }
        try check(LiftGeometry.boardTop(0) + LiftGeometry.boardHeight <= LiftGeometry.canvasHeight, "收起时完整背板被绘制区域裁切")
        let foldedTop = LiftGeometry.height - LiftGeometry.boardTop(0) - LiftGeometry.anchorDepth
        try check(foldedTop == LiftGeometry.peek, "收起时背板露出量")
        let opening = PrinterAudio.mechanismWave(opening: true, duration: 0.09)
        let closing = PrinterAudio.mechanismWave(opening: false, duration: 0.09)
        let decoded = try AVAudioPlayer(data: opening)
        try check(abs(decoded.duration - 0.09) < 0.001 && opening != closing, "机械音效长度或收放区分")
        print("PASS  连杆全程等长、背板连接与露头、机械音效解码")
        if CommandLine.arguments.contains("--live") {
            let service = StickerService()
            let cities = try await service.searchCities("Changchun")
            try check(cities.contains { $0.id == GeoCity.changchun.id }, "联网城市搜索")
            let current = try await service.weather(for: .changchun)
            try check(current.cityID == GeoCity.changchun.id && (-80...60).contains(current.temperature), "联网天气")
            print("PASS  联网搜索长春与获取天气（\(current.temperature)°）")
        }
    }
    static func check(_ condition: @autoclosure () -> Bool, _ message: String) throws {
        if !condition() { throw CheckFailure(description: message) }
    }
}
private struct CheckFailure: Error, CustomStringConvertible { let description: String }
