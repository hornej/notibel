import SwiftUI

@main
struct NotibelApp: App {
    @UIApplicationDelegateAdaptor(NotibelAppDelegate.self) private var appDelegate
    @State private var appModel = AppModel()

    init() {
        FontRegistrar.registerBundledFonts()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(appModel)
                .task {
                    await PushBridge.shared.attach(appModel)
                    await appModel.start()
                }
        }
    }
}
