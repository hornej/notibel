import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var appModel
    @State private var isShowingAppToken = false

    var body: some View {
        Form {
            Section {
                TextField("https://notibel.example.com", text: serverURLBinding)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)

                HStack(spacing: 12) {
                    Group {
                        if isShowingAppToken {
                            TextField("App token", text: appTokenBinding)
                        } else {
                            SecureField("App token", text: appTokenBinding)
                        }
                    }
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                    Button {
                        isShowingAppToken.toggle()
                    } label: {
                        Image(systemName: isShowingAppToken ? "eye.slash" : "eye")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(isShowingAppToken ? "Hide app token" : "Show app token")
                }
            } header: {
                Text("Server")
            }

            Section {
                TextField("Installation name", text: installationNameBinding)

                LabeledContent("Installation ID") {
                    Text(appModel.settings.installationID)
                        .font(.footnote.monospaced())
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Installation")
            }

            Section {
                LabeledContent("Authorization", value: appModel.authorizationDescription)
                LabeledContent("Device token", value: appModel.deviceTokenPreview)
                LabeledContent("Sync status", value: appModel.deviceSyncStatus.description)

                Button("Request Permission") {
                    Task {
                        await appModel.requestNotificationPermission()
                    }
                }

                Button("Register With APNs Again") {
                    appModel.registerForRemoteNotifications()
                }

                Button("Sync Device Registration") {
                    Task {
                        await appModel.syncDeviceRegistration()
                    }
                }
                .disabled(!appModel.isConfiguredForServer)

                Button("Delete Remote Registration", role: .destructive) {
                    Task {
                        await appModel.deleteRemoteRegistration()
                    }
                }
                .disabled(!appModel.isConfiguredForServer)
            } header: {
                Text("Push")
            } footer: {
                Text("Push delivery requires a physical iPhone. The simulator can browse history, but it will not receive APNs device tokens.")
            }
        }
        .navigationTitle("Settings")
        .onDisappear {
            appModel.commitSettingsEdits()
        }
    }

    private var serverURLBinding: Binding<String> {
        Binding(
            get: { appModel.settings.serverURLString },
            set: { appModel.updateServerURL($0) }
        )
    }

    private var appTokenBinding: Binding<String> {
        Binding(
            get: { appModel.settings.appToken },
            set: { appModel.updateAppToken($0) }
        )
    }

    private var installationNameBinding: Binding<String> {
        Binding(
            get: { appModel.settings.installationName },
            set: { appModel.updateInstallationName($0) }
        )
    }
}
