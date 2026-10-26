import AppKit
import SwiftUI

enum ClockDisplay {
    static func abbreviation(for city: ClockCity) -> String {
        let known = ["莫斯科": "MOW", "moscow": "MOW", "柏林": "BER", "berlin": "BER", "伦敦": "LON", "london": "LON", "墨西哥城": "MEX", "mexico city": "MEX"]
        if let label = known[city.name.lowercased()] { return label }
        let latin = (city.name.applyingTransform(.toLatin, reverse: false) ?? city.name)
            .folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US_POSIX"))
            .filter { $0.isASCII && $0.isLetter }
        return String(latin.prefix(3)).uppercased()
    }

    static func calendar(for city: ClockCity) -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = city.zone
        return calendar
    }
    static func time(_ date: Date, in city: ClockCity) -> String {
        let calendar = calendar(for: city)
        return String(format: "%02d:%02d", calendar.component(.hour, from: date), calendar.component(.minute, from: date))
    }
    static func dayLabel(_ date: Date, in city: ClockCity) -> String {
        let fields: Set<Calendar.Component> = [.year, .month, .day]
        let local = Calendar.current.dateComponents(fields, from: date)
        let remote = calendar(for: city).dateComponents(fields, from: date)
        var utc = Calendar(identifier: .gregorian); utc.timeZone = .gmt
        guard let localDate = utc.date(from: local), let remoteDate = utc.date(from: remote) else { return "今天" }
        switch utc.dateComponents([.day], from: localDate, to: remoteDate).day ?? 0 {
        case ..<0: return "昨天"
        case 0: return "今天"
        default: return "明天"
        }
    }
    static func difference(_ date: Date, in city: ClockCity) -> String {
        let minutes = (city.zone.secondsFromGMT(for: date) - TimeZone.current.secondsFromGMT(for: date)) / 60
        if minutes == 0 { return "与本地相同" }
        let hours = abs(minutes) / 60, remainder = abs(minutes) % 60
        let amount = remainder == 0 ? "\(hours) 小时" : "\(hours) 时 \(remainder) 分"
        return (minutes > 0 ? "+" : "−") + amount
    }
}

struct WorldClocksView: View {
    @ObservedObject var settings: StickerSettings
    var close: () -> Void
    var chooseCity: (Int) -> Void

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            HStack(spacing: 20) {
                ForEach(settings.clockCities.indices, id: \.self) { index in
                    let city = settings.clockCities[index]
                    Button { chooseCity(index) } label: {
                        PrintedClock(date: context.date, city: city)
                            .frame(width: 90, height: 90)
                            .frame(width: 104, height: 108)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain).help(city.name + " · " + ClockDisplay.time(context.date, in: city) + " · 点击更换城市")
                    .accessibilityLabel("更换第\(index + 1)个时钟：\(city.name)，\(ClockDisplay.time(context.date, in: city))")
                }
            }
        }
        .frame(width: LiftGeometry.boardWidth, height: LiftGeometry.boardHeight)
        .preferredColorScheme(.light)
        .onExitCommand(perform: close)

    }
}

private struct PrintedClock: View {
    let date: Date
    let city: ClockCity
    var body: some View {
        let calendar = ClockDisplay.calendar(for: city)
        let hour = calendar.component(.hour, from: date)
        let minute = calendar.component(.minute, from: date)
        let second = calendar.component(.second, from: date)
        Canvas { context, size in
            let center = CGPoint(x: size.width / 2, y: size.height / 2)
            let radius = size.width * 0.4
            let black = Color(hex: 0x26292A)
            let red = Color(hex: 0xD12632)
            // Railway-clock proportions: rectangular hours and short minute marks.
            for mark in 0..<60 {
                let hourMark = mark % 5 == 0
                let angle = CGFloat(mark) * .pi / 30 - .pi / 2
                let length = radius * (hourMark ? 0.235 : 0.073)
                let width = radius * (hourMark ? 0.07 : 0.026)
                var path = Path()
                path.move(to: CGPoint(x: center.x + cos(angle) * (radius - length), y: center.y + sin(angle) * (radius - length)))
                path.addLine(to: CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius))
                context.stroke(path, with: .color(black), style: StrokeStyle(lineWidth: width, lineCap: .butt))
            }
            context.draw(Text(ClockDisplay.abbreviation(for: city))
                .font(.system(size: 7.1, weight: .regular)).tracking(1.1).foregroundColor(black),
                at: CGPoint(x: center.x, y: center.y - radius * 0.45))

            func hand(_ value: Double, length: CGFloat, tail: CGFloat, width: CGFloat, elevation: CGFloat) {
                let angle = CGFloat(value) * .pi * 2 - .pi / 2
                var path = Path()
                path.move(to: CGPoint(x: center.x - cos(angle) * tail, y: center.y - sin(angle) * tail))
                path.addLine(to: CGPoint(x: center.x + cos(angle) * length, y: center.y + sin(angle) * length))
                var raised = context
                raised.addFilter(.shadow(color: .black.opacity(0.24), radius: 0.8, x: 0.55, y: elevation))
                raised.stroke(path, with: .color(black), style: StrokeStyle(lineWidth: width, lineCap: .butt))
            }
            hand((Double(hour % 12) + Double(minute) / 60) / 12, length: radius * 0.65, tail: radius * 0.24, width: radius * 0.092, elevation: 0.9)
            hand((Double(minute) + Double(second) / 60) / 60, length: radius * 0.94, tail: radius * 0.26, width: radius * 0.075, elevation: 1.3)

            let angle = CGFloat(second) * .pi / 30 - .pi / 2
            let tip = CGPoint(x: center.x + cos(angle) * radius * 0.66, y: center.y + sin(angle) * radius * 0.66)
            let discRadius = radius * 0.081
            var seconds = Path()
            seconds.move(to: CGPoint(x: center.x - cos(angle) * radius * 0.3, y: center.y - sin(angle) * radius * 0.3))
            seconds.addLine(to: tip)
            var raisedSeconds = context
            raisedSeconds.addFilter(.shadow(color: .black.opacity(0.23), radius: 0.95, x: 0.5, y: 1.5))
            raisedSeconds.stroke(seconds, with: .color(red), style: StrokeStyle(lineWidth: radius * 0.024, lineCap: .butt))
            raisedSeconds.fill(Path(ellipseIn: CGRect(x: tip.x - discRadius, y: tip.y - discRadius, width: discRadius * 2, height: discRadius * 2)), with: .color(red))
            context.fill(Path(ellipseIn: CGRect(x: center.x - 1.25, y: center.y - 1.25, width: 2.5, height: 2.5)), with: .color(red))
            context.stroke(Path(ellipseIn: CGRect(x: center.x - 1.25, y: center.y - 1.25, width: 2.5, height: 2.5)), with: .color(Color(hex: 0xA81E27).opacity(0.5)), lineWidth: 0.3)
        }.accessibilityHidden(true)
    }
}

struct WeatherStickerView: View {
    @ObservedObject var settings: StickerSettings
    @ObservedObject var model: WeatherModel
    var close: () -> Void
    var chooseCity: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if let weather = model.snapshot, weather.cityID == settings.weatherCity.id {
                HStack(spacing: 15) {
                    VStack(alignment: .leading, spacing: 6) {
                        Button(settings.weatherCity.name) { chooseCity() }
                            .font(.system(size: 13, weight: .medium)).buttonStyle(.plain).help("更换城市")
                        Text(weather.condition).font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: weather.symbol).symbolRenderingMode(.multicolor).font(.system(size: 34))
                    Text("\(Int(weather.temperature.rounded()))°").font(.system(size: 43, weight: .light, design: .rounded))
                }
                HStack {
                    if let high = weather.high, let low = weather.low {
                        Text("↑ \(Int(high.rounded()))°   ↓ \(Int(low.rounded()))°").font(.system(size: 11, weight: .medium, design: .rounded))
                    }
                    Spacer()
                    if model.error != nil { Image(systemName: "wifi.slash").help("暂时无法更新，显示上次结果") }
                    Menu {
                        Button("更换城市") { chooseCity() }
                        Button("刷新天气") { model.refresh(city: settings.weatherCity, force: true) }
                        Link("天气数据 · Open-Meteo", destination: URL(string: "https://open-meteo.com/")!)
                    } label: { Image(systemName: "ellipsis").font(.system(size: 11)).frame(width: 20, height: 18) }
                    .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize().accessibilityLabel("天气设置")
                }.foregroundStyle(.secondary)
            } else {
                HStack {
                    Button(settings.weatherCity.name) { chooseCity() }.buttonStyle(.plain)
                    Spacer()
                    if model.isLoading { ProgressView().controlSize(.small) }
                    else { Button { model.refresh(city: settings.weatherCity, force: true) } label: { Image(systemName: "arrow.clockwise") }.buttonStyle(.plain).help("重试获取天气") }
                }
                Text(model.isLoading ? "正在获取天气…" : "暂时无法更新").font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 36).padding(.vertical, 22).frame(width: LiftGeometry.boardWidth, height: LiftGeometry.boardHeight)
        .preferredColorScheme(.light).onExitCommand(perform: close)
        .task(id: settings.weatherCity.id) { model.refresh(city: settings.weatherCity) }

    }
}

struct CitySearchView: View {
    let title: String
    var selected: (GeoCity) -> Void
    var cancel: () -> Void
    @StateObject private var model = CitySearchModel()
    @FocusState private var focused: Bool
    var body: some View {
        VStack(spacing: 16) {
            HStack { Text(title).font(.system(size: 16, weight: .medium)); Spacer(); Button("取消", action: cancel).buttonStyle(.plain).font(.system(size: 12)) }
            HStack {
                TextField("城市名称，如 长春 / London", text: $model.query)
                    .textFieldStyle(.roundedBorder).focused($focused).onSubmit { model.search() }
                Button("搜索") { model.search() }.disabled(model.isLoading)
            }
            if model.isLoading { ProgressView().controlSize(.small).padding(.top, 15) }
            if let error = model.error { Text(error).font(.system(size: 11)).foregroundStyle(Color.mutedInk).multilineTextAlignment(.center).padding(.top, 12) }
            ScrollView {
                VStack(spacing: 3) {
                    ForEach(model.results) { city in
                        Button { selected(city) } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text(city.name).font(.system(size: 13, weight: .medium))
                                    Text(city.detail).font(.system(size: 10)).foregroundStyle(Color.mutedInk)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(Color.mutedInk)
                            }.padding(11).contentShape(Rectangle())
                        }.buttonStyle(.plain)
                            .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.7)))
                    }
                }
            }.scrollIndicators(.hidden)
            HStack { Text("城市数据 · GeoNames / Open-Meteo"); Spacer() }.font(.system(size: 8)).foregroundStyle(Color.mutedInk)
        }
        .padding(22).frame(width: 390, height: 410).background(Color(hex: 0xF4F5ED))
        .onAppear { focused = true }.onExitCommand(perform: cancel)
    }
}

