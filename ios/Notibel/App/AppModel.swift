import Observation
import SwiftUI
import UIKit
import UserNotifications

@MainActor
@Observable
final class AppModel: PushEventHandling {
    var selectedTab: AppTab = .notifications
    var settings: NotibelSettings
    var notificationAuthorization: UNAuthorizationStatus = .notDetermined
    var deviceTokenHex = ""
    var deviceSyncStatus: DeviceSyncStatus = .idle
    var pendingTopic: String?
    var reloadSeed = UUID()

    @ObservationIgnored private let settingsStore: SettingsStore

    init(settingsStore: SettingsStore = SettingsStore()) {
        self.settingsStore = settingsStore
        self.settings = settingsStore.load()
    }

    var isConfiguredForServer: Bool {
        settings.baseURL != nil && !settings.appToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var hasTopics: Bool {
        !settings.normalizedTopics.isEmpty
    }

    var authorizationDescription: String {
        switch notificationAuthorization {
        case .authorized:
            return "Authorized"
        case .denied:
            return "Denied"
        case .ephemeral:
            return "Ephemeral"
        case .notDetermined:
            return "Not determined"
        case .provisional:
            return "Provisional"
        @unknown default:
            return "Unknown"
        }
    }

    var deviceTokenPreview: String {
        guard !deviceTokenHex.isEmpty else {
            return "Not available yet"
        }

        if deviceTokenHex.count <= 20 {
            return deviceTokenHex
        }

        return "\(deviceTokenHex.prefix(10))...\(deviceTokenHex.suffix(10))"
    }

    func start() async {
        await refreshNotificationAuthorization()

        if notificationAuthorization.isAuthorized {
            UIApplication.shared.registerForRemoteNotifications()
        }
    }

    func saveSettings() {
        settings.normalize()
        settingsStore.save(settings)
        reloadSeed = UUID()
    }

    func updateServerURL(_ value: String) {
        settings.serverURLString = value
        persistSettingsEdits()
    }

    func updateAppToken(_ value: String) {
        settings.appToken = value
        persistSettingsEdits()
    }

    func updateInstallationName(_ value: String) {
        settings.installationName = value
        persistSettingsEdits()
    }

    func commitSettingsEdits() {
        saveSettings()
    }

    func fetchNotifications(topics: [String]) async throws -> [NotibelEvent] {
        let client = try makeClient()
        return try await client.fetchNotifications(topics: topics, limitPerTopic: 25)
    }

    func fetchEvents(for topic: String) async throws -> [NotibelEvent] {
        let client = try makeClient()
        return try await client.fetchEvents(topic: topic, limit: 50)
    }

    @discardableResult
    func addTopic(_ topic: String) async -> String? {
        let cleaned = NotibelSettings.normalizeTopic(topic)
        guard !cleaned.isEmpty else {
            return nil
        }
        guard !settings.normalizedTopics.contains(cleaned) else {
            return nil
        }

        settings.topics.append(cleaned)
        saveSettings()
        await syncDeviceRegistration()
        return cleaned
    }

    func removeTopics(at offsets: IndexSet) async {
        settings.topics.remove(atOffsets: offsets)
        saveSettings()
        await syncDeviceRegistration()
    }

    func requestNotificationPermission() async {
        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
            await refreshNotificationAuthorization()

            if granted {
                UIApplication.shared.registerForRemoteNotifications()
            } else {
                deviceSyncStatus = .failed("Notifications were not authorized.")
            }
        } catch {
            deviceSyncStatus = .failed(error.localizedDescription)
        }
    }

    func registerForRemoteNotifications() {
        UIApplication.shared.registerForRemoteNotifications()
    }

    func refreshNotificationAuthorization() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        notificationAuthorization = settings.authorizationStatus
    }

    func syncDeviceRegistration() async {
        do {
            let client = try makeClient()
            settings.normalize()

            guard !settings.normalizedTopics.isEmpty else {
                deviceSyncStatus = .needsAttention("Add at least one topic before syncing this device.")
                return
            }

            guard !deviceTokenHex.isEmpty else {
                deviceSyncStatus = .needsAttention("Push registration requires a physical iPhone and notification permission.")
                return
            }

            deviceSyncStatus = .syncing
            try await client.registerDevice(
                installationID: settings.installationID,
                deviceToken: deviceTokenHex,
                topics: settings.normalizedTopics,
                name: settings.installationName
            )
            saveSettings()
            deviceSyncStatus = .synced(Date())
        } catch {
            deviceSyncStatus = .failed(error.localizedDescription)
        }
    }

    func deleteRemoteRegistration() async {
        do {
            let client = try makeClient()
            try await client.deleteDevice(installationID: settings.installationID)
            deviceSyncStatus = .idle
        } catch {
            deviceSyncStatus = .failed(error.localizedDescription)
        }
    }

    func handleDeviceToken(_ token: Data) async {
        deviceTokenHex = token.map { String(format: "%02x", $0) }.joined()
        if settings.installationName.isEmpty {
            settings.installationName = UIDevice.current.name
        }
        await syncDeviceRegistration()
    }

    func handleRegistrationFailure(_ error: Error) async {
        deviceSyncStatus = .failed(error.localizedDescription)
    }

    func handleNotificationOpen(userInfo: [AnyHashable: Any]) async {
        if let topic = Self.topic(from: userInfo) {
            selectedTab = .notifications
            pendingTopic = topic
        }
    }

    private func makeClient() throws -> NotibelAPIClient {
        try NotibelAPIClient(settings: settings)
    }

    private func persistSettingsEdits() {
        settingsStore.save(settings)
    }

    private static func topic(from userInfo: [AnyHashable: Any]) -> String? {
        if let topic = (userInfo["notibel"] as? [String: Any])?["topic"] as? String {
            return topic
        }
        return nil
    }
}

enum DeviceSyncStatus {
    case idle
    case needsAttention(String)
    case syncing
    case synced(Date)
    case failed(String)

    var description: String {
        switch self {
        case .idle:
            return "Idle"
        case .needsAttention(let message):
            return message
        case .syncing:
            return "Syncing device registration..."
        case .synced(let date):
            return "Synced \(date.formatted(date: .abbreviated, time: .shortened))"
        case .failed(let message):
            return message
        }
    }
}

private extension UNAuthorizationStatus {
    var isAuthorized: Bool {
        switch self {
        case .authorized, .ephemeral, .provisional:
            return true
        case .denied, .notDetermined:
            return false
        @unknown default:
            return false
        }
    }
}
