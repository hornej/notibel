import Foundation

struct SettingsStore {
    private let defaults: UserDefaults
    private let settingsKey = "notibel.settings.v1"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func load() -> NotibelSettings {
        guard let data = defaults.data(forKey: settingsKey) else {
            return NotibelSettings()
        }

        do {
            var settings = try JSONDecoder().decode(NotibelSettings.self, from: data)
            settings.normalize()
            return settings
        } catch {
            return NotibelSettings()
        }
    }

    func save(_ settings: NotibelSettings) {
        var copy = settings
        copy.normalize()

        if let data = try? JSONEncoder().encode(copy) {
            defaults.set(data, forKey: settingsKey)
        }
    }
}
