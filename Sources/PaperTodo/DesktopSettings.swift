import Foundation
import Combine

@MainActor
final class DesktopSettings: ObservableObject {
    @Published var alwaysOnTop = UserDefaults.standard.bool(forKey: "desktopAlwaysOnTop") {
        didSet { UserDefaults.standard.set(alwaysOnTop, forKey: "desktopAlwaysOnTop") }
    }
}
