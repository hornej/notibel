import Foundation

@MainActor
protocol PushEventHandling: AnyObject {
    func handleDeviceToken(_ token: Data) async
    func handleRegistrationFailure(_ error: Error) async
    func handleNotificationOpen(userInfo: [AnyHashable: Any]) async
}

@MainActor
final class PushBridge {
    static let shared = PushBridge()

    private weak var handler: (any PushEventHandling)?
    private var pendingDeviceToken: Data?
    private var pendingRegistrationError: Error?
    private var pendingNotificationUserInfo: [AnyHashable: Any]?

    private init() {}

    func attach(_ handler: any PushEventHandling) async {
        self.handler = handler

        if let pendingDeviceToken {
            self.pendingDeviceToken = nil
            await handler.handleDeviceToken(pendingDeviceToken)
        }

        if let pendingRegistrationError {
            self.pendingRegistrationError = nil
            await handler.handleRegistrationFailure(pendingRegistrationError)
        }

        if let pendingNotificationUserInfo {
            self.pendingNotificationUserInfo = nil
            await handler.handleNotificationOpen(userInfo: pendingNotificationUserInfo)
        }
    }

    func didRegister(deviceToken: Data) async {
        guard let handler else {
            pendingDeviceToken = deviceToken
            return
        }

        await handler.handleDeviceToken(deviceToken)
    }

    func didFailToRegister(error: Error) async {
        guard let handler else {
            pendingRegistrationError = error
            return
        }

        await handler.handleRegistrationFailure(error)
    }

    func didOpenNotification(userInfo: [AnyHashable: Any]) async {
        guard let handler else {
            pendingNotificationUserInfo = userInfo
            return
        }

        await handler.handleNotificationOpen(userInfo: userInfo)
    }
}
