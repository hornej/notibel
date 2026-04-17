import Foundation
import Security

struct SettingsStore {
    private let defaults: UserDefaults
    private let appTokenStore: KeychainAppTokenStore
    private let settingsKey = "notibel.settings.v1"

    init(
        defaults: UserDefaults = .standard,
        appTokenStore: KeychainAppTokenStore = KeychainAppTokenStore()
    ) {
        self.defaults = defaults
        self.appTokenStore = appTokenStore
    }

    func load() -> NotibelSettings {
        let persistedSettings: PersistedSettings
        if let data = defaults.data(forKey: settingsKey),
           let decodedSettings = try? JSONDecoder().decode(PersistedSettings.self, from: data) {
            persistedSettings = decodedSettings
        } else {
            persistedSettings = PersistedSettings()
        }

        let appToken = loadAppToken()
        var settings = persistedSettings.makeSettings(appToken: appToken)
        settings.normalize()
        return settings
    }

    func save(_ settings: NotibelSettings) {
        var copy = settings
        copy.normalize()

        appTokenStore.save(copy.appToken)

        if let data = try? JSONEncoder().encode(PersistedSettings(settings: copy)) {
            defaults.set(data, forKey: settingsKey)
        }
    }

    private func loadAppToken() -> String {
        let keychainToken = appTokenStore.load()
        if !keychainToken.isEmpty {
            scrubLegacyAppTokenFromDefaultsIfNeeded()
            return keychainToken
        }

        guard let data = defaults.data(forKey: settingsKey),
              let legacySettings = try? JSONDecoder().decode(NotibelSettings.self, from: data)
        else {
            return ""
        }

        let legacyToken = legacySettings.appToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !legacyToken.isEmpty else {
            return ""
        }

        appTokenStore.save(legacyToken)
        persistSettingsWithoutToken(legacySettings)
        return legacyToken
    }

    private func scrubLegacyAppTokenFromDefaultsIfNeeded() {
        guard let data = defaults.data(forKey: settingsKey),
              let legacySettings = try? JSONDecoder().decode(NotibelSettings.self, from: data)
        else {
            return
        }

        let legacyToken = legacySettings.appToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !legacyToken.isEmpty else {
            return
        }

        persistSettingsWithoutToken(legacySettings)
    }

    private func persistSettingsWithoutToken(_ settings: NotibelSettings) {
        if let data = try? JSONEncoder().encode(PersistedSettings(settings: settings)) {
            defaults.set(data, forKey: settingsKey)
        }
    }
}

private struct PersistedSettings: Codable {
    var serverURLString: String
    var installationID: String
    var installationName: String
    var topics: [String]

    init(
        serverURLString: String = "",
        installationID: String = "",
        installationName: String = "",
        topics: [String] = ["codex"]
    ) {
        self.serverURLString = serverURLString
        self.installationID = installationID
        self.installationName = installationName
        self.topics = topics
    }

    init(settings: NotibelSettings) {
        self.serverURLString = settings.serverURLString
        self.installationID = settings.installationID
        self.installationName = settings.installationName
        self.topics = settings.topics
    }

    func makeSettings(appToken: String) -> NotibelSettings {
        NotibelSettings(
            serverURLString: serverURLString,
            appToken: appToken,
            installationID: installationID,
            installationName: installationName,
            topics: topics
        )
    }
}

struct KeychainAppTokenStore {
    private let service: String
    private let account = "notibel.app-token"

    init(service: String = Bundle.main.bundleIdentifier ?? "com.notibel.app") {
        self.service = service
    }

    func load() -> String {
        var query = baseQuery
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        query[kSecReturnData as String] = true

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let token = String(data: data, encoding: .utf8)
        else {
            return ""
        }

        return token.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func save(_ token: String) {
        let trimmedToken = token.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedToken.isEmpty else {
            delete()
            return
        }

        delete()

        var query = baseQuery
        query[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        query[kSecValueData as String] = Data(trimmedToken.utf8)
        SecItemAdd(query as CFDictionary, nil)
    }

    func delete() {
        SecItemDelete(baseQuery as CFDictionary)
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
