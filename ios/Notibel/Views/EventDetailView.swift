import SwiftUI

struct EventDetailView: View {
    let event: NotibelEvent
    private let horizontalContentPadding: CGFloat = 12
    private let verticalContentPadding: CGFloat = 16
    private let messageCardHorizontalPadding: CGFloat = 12
    private let messageCardVerticalPadding: CGFloat = 16

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                headerCard
                messageCard
                metadataCard
            }
            .padding(.horizontal, horizontalContentPadding)
            .padding(.vertical, verticalContentPadding)
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Notification")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var headerCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(event.title)
                .font(.title3.weight(.semibold))
                .frame(maxWidth: .infinity, alignment: .leading)

            if let threadTitle = event.threadTitle, !threadTitle.isEmpty {
                Text(threadTitle)
                    .font(.headline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Text(Self.timestampFormatter.localizedString(for: event.createdAt, relativeTo: .now))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var messageCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Message")
                .font(.headline)

            Text(event.renderedMessage)
                .font(.body)
                .frame(maxWidth: .infinity, alignment: .leading)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, messageCardHorizontalPadding)
        .padding(.vertical, messageCardVerticalPadding)
        .background(.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private var metadataCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Details")
                .font(.headline)

            NavigationLink(value: AppRoute.topic(event.topic)) {
                metadataRow(label: "Topic", value: event.topic, systemImage: "number")
            }
            .buttonStyle(.plain)

            if let source = event.source, !source.isEmpty {
                metadataRow(label: "Source", value: source, systemImage: "desktopcomputer")
            }

            if let project = event.project, !project.isEmpty {
                metadataRow(label: "Project", value: project, systemImage: "folder")
            }

            if let threadTitle = event.threadTitle, !threadTitle.isEmpty {
                metadataRow(label: "Thread", value: threadTitle, systemImage: "text.bubble")
            }

            metadataRow(
                label: "Received",
                value: event.createdAt.formatted(date: .abbreviated, time: .standard),
                systemImage: "clock"
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.background, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func metadataRow(label: String, value: String, systemImage: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: systemImage)
                .foregroundStyle(.secondary)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(value)
                    .font(.body)
                    .foregroundStyle(.primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private static let timestampFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .full
        return formatter
    }()
}
