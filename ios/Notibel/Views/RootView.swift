import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var appModel
    @State private var notificationsPath: [AppRoute] = []
    @State private var settingsPath: [AppRoute] = []

    var body: some View {
        TabView(selection: selectedTabBinding) {
            NavigationStack(path: $notificationsPath) {
                NotificationsView()
                    .navigationDestination(for: AppRoute.self, destination: destinationView)
            }
            .tabItem { AppTab.notifications.label }
            .tag(AppTab.notifications)

            NavigationStack(path: $settingsPath) {
                SettingsView()
                    .navigationDestination(for: AppRoute.self, destination: destinationView)
            }
            .tabItem { AppTab.settings.label }
            .tag(AppTab.settings)
        }
        .onChange(of: appModel.pendingEventReference) { _, eventReference in
            guard let eventReference else {
                return
            }
            openEventReference(eventReference)
            appModel.pendingEventReference = nil
        }
        .onChange(of: appModel.pendingTopic) { _, topic in
            guard let topic else {
                return
            }
            openTopic(topic)
            appModel.pendingTopic = nil
        }
    }

    @ViewBuilder
    private func destinationView(for route: AppRoute) -> some View {
        switch route {
        case .topic(let topic):
            TopicDetailView(topic: topic)
        case .event(let event):
            EventDetailView(event: event)
        case .eventReference(let eventReference):
            EventDetailLoaderView(reference: eventReference)
        }
    }

    private var selectedTabBinding: Binding<AppTab> {
        Binding(
            get: { appModel.selectedTab },
            set: { appModel.selectedTab = $0 }
        )
    }

    private func openTopic(_ topic: String) {
        appModel.selectedTab = .notifications
        notificationsPath = [.topic(topic)]
    }

    private func openEventReference(_ eventReference: NotibelEventReference) {
        appModel.selectedTab = .notifications
        notificationsPath = [.eventReference(eventReference)]
    }
}
