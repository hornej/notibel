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
            guard oldField == .appToken, newField != .appToken, !isReplacingAppToken else {
                return
            }
            finishInitialAppTokenEntry()
        }
        .onDisappear {
            if isReplacingAppToken {
                cancelAppTokenReplacement()
            } else {
                finishInitialAppTokenEntry()
            }
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
        } else if isReplacingAppToken {
            VStack(alignment: .leading, spacing: 12) {
                TextField("New app token", text: $appTokenDraft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: .appToken)
                    .submitLabel(.done)
                    .onSubmit {
                        saveReplacementToken()
                    }

                HStack {
                    Button("Cancel") {
                        cancelAppTokenReplacement()
                    }
                    .buttonStyle(.borderless)

                    Spacer()

                    Button("Save") {
                        saveReplacementToken()
                    }
                    .buttonStyle(.borderless)
                    .disabled(normalizedAppTokenDraft.isEmpty)
                }
                .font(.subheadline)
            }
        } else {
            TextField("App token", text: $appTokenDraft)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focusedField, equals: .appToken)
                .submitLabel(.done)
                .onSubmit {
                    finishInitialAppTokenEntry()
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

    private func finishInitialAppTokenEntry() {
        guard !hasSavedAppToken else {
            appTokenDraft = ""
            return
        }

        appModel.updateAppToken(normalizedAppTokenDraft)
        if !normalizedAppTokenDraft.isEmpty {
            appTokenDraft = ""
        }
    }

    private func saveReplacementToken() {
        guard !normalizedAppTokenDraft.isEmpty else {
            return
        }

        appModel.updateAppToken(normalizedAppTokenDraft)
        isReplacingAppToken = false
        appTokenDraft = ""
        focusedField = nil
    }

    private func cancelAppTokenReplacement() {
        isReplacingAppToken = false
        appTokenDraft = ""
        focusedField = nil
    }

    private func syncAppTokenDraft() {
        guard !hasSavedAppToken else {
            appTokenDraft = ""
            return
        }

        appTokenDraft = appModel.settings.appToken
    }

    private var normalizedAppTokenDraft: String {
        appTokenDraft.trimmingCharacters(in: .whitespacesAndNewlines)
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
