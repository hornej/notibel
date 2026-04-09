import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var appModel
    @FocusState private var focusedField: Field?
    @State private var appTokenDraft = ""
    @State private var isReplacingAppToken = false

    private enum Field: Hashable {
        case appToken
    }

    var body: some View {
        Form {
            Section {
                TextField("https://notibel.example.com", text: serverURLBinding)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)

                appTokenRow
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
        .onAppear {
            syncAppTokenDraft()
        }
        .onChange(of: focusedField) { oldField, newField in
            guard oldField == .appToken, newField != .appToken else {
                return
            }
            finishAppTokenEntry()
        }
        .onDisappear {
            finishAppTokenEntry()
            appModel.commitSettingsEdits()
        }
    }

    @ViewBuilder
    private var appTokenRow: some View {
        if hasSavedAppToken && !isReplacingAppToken {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("App token saved")
                        .foregroundStyle(.primary)
                    Text("Enter a new token to replace it.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 12)

                Button("Replace") {
                    beginAppTokenReplacement()
                }
                .buttonStyle(.borderless)
            }
        } else {
            TextField("App token", text: $appTokenDraft)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focusedField, equals: .appToken)
                .submitLabel(.done)
                .onSubmit {
                    finishAppTokenEntry()
                }
        }
    }

    private var hasSavedAppToken: Bool {
        !appModel.settings.appToken.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func beginAppTokenReplacement() {
        isReplacingAppToken = true
        appTokenDraft = ""
        focusedField = .appToken
    }

    private func finishAppTokenEntry() {
        let cleanedToken = appTokenDraft.trimmingCharacters(in: .whitespacesAndNewlines)

        if isReplacingAppToken {
            if !cleanedToken.isEmpty {
                appModel.updateAppToken(cleanedToken)
            }
            isReplacingAppToken = false
            appTokenDraft = ""
            return
        }

        guard !hasSavedAppToken else {
            appTokenDraft = ""
            return
        }

        appModel.updateAppToken(cleanedToken)
        if !cleanedToken.isEmpty {
            appTokenDraft = ""
        }
    }

    private func syncAppTokenDraft() {
        guard !hasSavedAppToken else {
            appTokenDraft = ""
            return
        }

        appTokenDraft = appModel.settings.appToken
    }

    private var serverURLBinding: Binding<String> {
        Binding(
            get: { appModel.settings.serverURLString },
            set: { appModel.updateServerURL($0) }
        )
    }

    private var installationNameBinding: Binding<String> {
        Binding(
            get: { appModel.settings.installationName },
            set: { appModel.updateInstallationName($0) }
        )
    }
}
