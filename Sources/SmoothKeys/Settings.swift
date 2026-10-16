import Foundation

struct AppSettings: Codable, Equatable {
    var mouse = MouseSettings()
    var inputMethod = InputMethodSettings()
    var keyboard = KeyboardSettings()
}

struct MouseSettings: Codable, Equatable {
    var enabled = true
    var smoothScroll = true
    var reverseVertical = false
    var reverseHorizontal = false
    var speed = 1.0
    var smoothness = 0.72
}

struct InputMethodSettings: Codable, Equatable {
    var lockEnabled = false
    var selectedSourceID: String?
}

struct KeyboardSettings: Codable, Equatable {
    var enabled = true
    var selectedDeviceIDs: Set<String> = []
}

enum SettingsStore {
    private static let key = "SmoothKeys.settings.v1"

    static func load() -> AppSettings {
        guard let data = UserDefaults.standard.data(forKey: key) else {
            return AppSettings()
        }
        do {
            return try JSONDecoder().decode(AppSettings.self, from: data)
        } catch {
            NSLog("SmoothKeys settings decode failed: \(error.localizedDescription)")
            return AppSettings()
        }
    }

    static func save(_ settings: AppSettings) {
        do {
            let data = try JSONEncoder().encode(settings)
            UserDefaults.standard.set(data, forKey: key)
        } catch {
            NSLog("SmoothKeys settings encode failed: \(error.localizedDescription)")
        }
    }
}
