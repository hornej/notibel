import SwiftUI

enum AppTab: Hashable, CaseIterable {
    case notifications
    case settings

    @ViewBuilder
    var label: some View {
        switch self {
        case .notifications:
            Label("Notifications", systemImage: "bell.badge")
        case .settings:
            Label("Settings", systemImage: "gearshape")
        }
    }
}
