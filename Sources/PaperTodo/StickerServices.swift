import Foundation
import Combine

struct ClockCity: Codable, Equatable, Identifiable {
    var name: String
    var timeZoneID: String
    var id: String { name + timeZoneID }
    var zone: TimeZone { TimeZone(identifier: timeZoneID) ?? .gmt }
    static let defaults = [
        ClockCity(name: "伦敦", timeZoneID: "Europe/London"),
        ClockCity(name: "墨西哥城", timeZoneID: "America/Mexico_City")
    ]
}

struct GeoCity: Codable, Equatable, Identifiable {
    var id: Int
    var name: String
    var latitude: Double
    var longitude: Double
    var timezone: String
    var country: String?
    var admin1: String?
    var detail: String { [country, admin1].compactMap { $0 }.filter { $0 != name }.joined(separator: " · ") }
    var clockCity: ClockCity { ClockCity(name: name, timeZoneID: timezone) }
    static let changchun = GeoCity(id: 2038180, name: "长春", latitude: 43.88, longitude: 125.32278, timezone: "Asia/Shanghai", country: "中国", admin1: "吉林省")
}

@MainActor
final class StickerSettings: ObservableObject {
    private let defaults: UserDefaults
    @Published var clockCities: [ClockCity] { didSet { persist(clockCities, key: "worldClockCities") } }
    @Published var weatherCity: GeoCity { didSet { persist(weatherCity, key: "weatherCity") } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let clocks = defaults.data(forKey: "worldClockCities").flatMap { try? JSONDecoder().decode([ClockCity].self, from: $0) }
        if let clocks, clocks.count == 2, clocks.allSatisfy({ TimeZone(identifier: $0.timeZoneID) != nil }) {
            clockCities = clocks
        } else {
            // Retain London and Mexico City when migrating the previous four clocks.
            clockCities = ClockCity.defaults.map { fallback in
                clocks?.first(where: { $0.timeZoneID == fallback.timeZoneID }) ?? fallback
            }
        }
        weatherCity = defaults.data(forKey: "weatherCity").flatMap { try? JSONDecoder().decode(GeoCity.self, from: $0) } ?? .changchun
    }

    func changeClock(at index: Int, to city: GeoCity) {
        guard clockCities.indices.contains(index), TimeZone(identifier: city.timezone) != nil else { return }
        clockCities[index] = city.clockCity
    }

    private func persist<T: Encodable>(_ value: T, key: String) {
        if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: key) }
    }
}

enum StickerServiceError: LocalizedError {
    case response, empty
    var errorDescription: String? {
        switch self {
        case .response: return "暂时连接不上天气服务，请稍后重试。"
        case .empty: return "没有找到这个城市，试试英文名称或加上国家。"
        }
    }
}

struct WeatherSnapshot: Codable, Equatable {
    var cityID: Int
    var temperature: Double
    var feelsLike: Double
    var humidity: Int
    var wind: Double
    var code: Int
    var isDay: Bool
    var high: Double?
    var low: Double?
    var fetchedAt: Date

    var condition: String {
        switch code {
        case 0: return "晴"
        case 1: return "大部晴朗"
        case 2: return "多云"
        case 3: return "阴"
        case 45, 48: return "雾"
        case 51, 53, 55: return "毛毛雨"
        case 56, 57, 66, 67: return "冻雨"
        case 61: return "小雨"
        case 63: return "中雨"
        case 65: return "大雨"
        case 71: return "小雪"
        case 73: return "中雪"
        case 75, 77: return "大雪"
        case 80, 81, 82: return "阵雨"
        case 85, 86: return "阵雪"
        case 95, 96, 99: return "雷雨"
        default: return "天气更新中"
        }
    }

    var symbol: String {
        switch code {
        case 0, 1: return isDay ? "sun.max.fill" : "moon.stars.fill"
        case 2: return isDay ? "cloud.sun.fill" : "cloud.moon.fill"
        case 3: return "cloud.fill"
        case 45, 48: return "cloud.fog.fill"
        case 71...77, 85, 86: return "cloud.snow.fill"
        case 95...99: return "cloud.bolt.rain.fill"
        default: return "cloud.rain.fill"
        }
    }
}

struct WeatherPayload: Decodable {
    struct Current: Decodable {
        var temperature_2m: Double
        var apparent_temperature: Double
        var relative_humidity_2m: Int
        var weather_code: Int
        var wind_speed_10m: Double
        var is_day: Int
    }
    struct Daily: Decodable { var temperature_2m_max: [Double]; var temperature_2m_min: [Double] }
    var current: Current
    var daily: Daily?
    func snapshot(for city: GeoCity, now: Date = Date()) -> WeatherSnapshot {
        WeatherSnapshot(cityID: city.id, temperature: current.temperature_2m, feelsLike: current.apparent_temperature,
                        humidity: current.relative_humidity_2m, wind: current.wind_speed_10m, code: current.weather_code,
                        isDay: current.is_day == 1, high: daily?.temperature_2m_max.first, low: daily?.temperature_2m_min.first, fetchedAt: now)
    }
}

struct StickerService {
    var session = URLSession.shared

    func searchCities(_ query: String) async throws -> [GeoCity] {
        var parts = URLComponents(string: "https://geocoding-api.open-meteo.com/v1/search")!
        parts.queryItems = [URLQueryItem(name: "name", value: query.trimmingCharacters(in: .whitespacesAndNewlines)),
                            URLQueryItem(name: "count", value: "10"), URLQueryItem(name: "language", value: "zh"), URLQueryItem(name: "format", value: "json")]
        let data = try await load(parts.url!)
        struct Results: Decodable { var results: [GeoCity]? }
        let cities = try JSONDecoder().decode(Results.self, from: data).results ?? []
        guard !cities.isEmpty else { throw StickerServiceError.empty }
        return cities
    }

    func weather(for city: GeoCity) async throws -> WeatherSnapshot {
        var parts = URLComponents(string: "https://api.open-meteo.com/v1/forecast")!
        parts.queryItems = [
            URLQueryItem(name: "latitude", value: String(city.latitude)), URLQueryItem(name: "longitude", value: String(city.longitude)),
            URLQueryItem(name: "current", value: "temperature_2m,apparent_temperature,relative_humidity_2m,weather_code,wind_speed_10m,is_day"),
            URLQueryItem(name: "daily", value: "temperature_2m_max,temperature_2m_min"),
            URLQueryItem(name: "wind_speed_unit", value: "ms"), URLQueryItem(name: "forecast_days", value: "1"), URLQueryItem(name: "timezone", value: "auto")
        ]
        let data = try await load(parts.url!)
        return try JSONDecoder().decode(WeatherPayload.self, from: data).snapshot(for: city)
    }

    private func load(_ url: URL) async throws -> Data {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        let (data, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse, (200..<300).contains(response.statusCode) else { throw StickerServiceError.response }
        return data
    }
}

@MainActor
final class CitySearchModel: ObservableObject {
    @Published var query = ""
    @Published private(set) var results: [GeoCity] = []
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?
    private var task: Task<Void, Never>?
    private var requestID = UUID()

    func search() {
        let term = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard term.count >= 2 else { error = "至少输入两个字或字母。"; return }
        task?.cancel()
        let id = UUID(); requestID = id
        isLoading = true; error = nil; results = []
        task = Task {
            defer { if requestID == id { isLoading = false } }
            do {
                let cities = try await StickerService().searchCities(term)
                guard !Task.isCancelled, requestID == id else { return }
                results = cities
            } catch {
                guard !Task.isCancelled, requestID == id else { return }
                self.error = (error as? LocalizedError)?.errorDescription ?? "城市查询失败，请检查网络后重试。"
            }
        }
    }
}

@MainActor
final class WeatherModel: ObservableObject {
    @Published private(set) var snapshot: WeatherSnapshot?
    @Published private(set) var isLoading = false
    @Published private(set) var error: String?
    private let defaults: UserDefaults
    private var task: Task<Void, Never>?
    private var requestID = UUID()

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        snapshot = defaults.data(forKey: "weatherSnapshot").flatMap { try? JSONDecoder().decode(WeatherSnapshot.self, from: $0) }
    }

    func refresh(city: GeoCity, force: Bool = false) {
        if !force, let snapshot, snapshot.cityID == city.id, Date().timeIntervalSince(snapshot.fetchedAt) < 600 { return }
        task?.cancel()
        if snapshot?.cityID != city.id { snapshot = nil }
        let id = UUID(); requestID = id
        error = nil; isLoading = true
        task = Task {
            defer { if requestID == id { isLoading = false } }
            do {
                let value = try await StickerService().weather(for: city)
                guard !Task.isCancelled, requestID == id else { return }
                snapshot = value
                if let data = try? JSONEncoder().encode(value) { defaults.set(data, forKey: "weatherSnapshot") }
            } catch {
                guard !Task.isCancelled, requestID == id else { return }
                self.error = "暂时无法更新天气，请检查网络后重试。"
            }
        }
    }
}
