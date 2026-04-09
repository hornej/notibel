import SwiftUI

struct AddTopicSheet: View {
    let onAdd: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var topic = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("codex", text: $topic)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                } header: {
                    Text("Topic")
                } footer: {
                    Text("Match the topic value used by your desktop publishers, for example `codex` or `claude`.")
                }
            }
            .navigationTitle("Add Topic")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        onAdd(topic)
                        dismiss()
                    }
                    .disabled(normalizedTopic.isEmpty)
                }
            }
        }
    }

    private var normalizedTopic: String {
        NotibelSettings.normalizeTopic(topic)
    }
}
