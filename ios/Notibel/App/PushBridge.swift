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

    private init() {}

    func attach(_ handler: any PushEventHandling) {
        self.handler = handler
    }

    func didRegister(deviceToken: Data) async {
        await handler?.handleDeviceToken(deviceToken)
    }

    func didFailToRegister(error: Error) async {
        await handler?.handleRegistrationFailure(error)
    }

    func didOpenNotification(userInfo: [AnyHashable: Any]) async {
        await handler?.handleNotificationOpen(userInfo: userInfo)
    }
}
