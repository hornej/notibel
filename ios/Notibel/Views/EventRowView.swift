import SwiftUI

struct EventRowView: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let event: NotibelEvent

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header

            if let threadTitle = event.threadTitle, !threadTitle.isEmpty {
                Text(threadTitle)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(isAccessibilityLayout ? 3 : 2)
                    .multilineTextAlignment(.leading)
            }

            Text(event.renderedMessage)
                .font(.subheadline)
                .foregroundStyle(.primary)
                .lineLimit(isAccessibilityLayout ? 8 : 6)
                .multilineTextAlignment(.leading)

            Group {
                if isAccessibilityLayout {
                    VStack(alignment: .leading, spacing: 4) {
                        ForEach(metadataItems, id: \.label) { item in
                            metadataLabel(text: item.label, systemImage: item.systemImage)
                        }
                    }
                } else {
                    HStack(spacing: 12) {
                        ForEach(metadataItems, id: \.label) { item in
                            metadataLabel(text: item.label, systemImage: item.systemImage)
                        }
                    }
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 6)
    }

    @ViewBuilder
    private var header: some View {
        if isAccessibilityLayout {
            VStack(alignment: .leading, spacing: 6) {
                titleView
                timestampView
            }
        } else {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                titleView
                Spacer(minLength: 8)
                timestampView
            }
        }
    }

    private var titleView: some View {
        Text(event.title)
            .font(.headline)
            .lineLimit(isAccessibilityLayout ? 3 : 2)
            .multilineTextAlignment(.leading)
    }

    private var timestampView: some View {
        Text(Self.timestampFormatter.localizedString(for: event.createdAt, relativeTo: .now))
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    private func metadataLabel(text: String, systemImage: String) -> some View {
        Label(text, systemImage: systemImage)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var metadataItems: [(label: String, systemImage: String)] {
        var items: [(label: String, systemImage: String)] = [
            (event.topic, "number")
        ]

        if let source = event.source, !source.isEmpty {
            items.append((source, "desktopcomputer"))
        }

        if let project = event.project, !project.isEmpty {
            items.append((project, "folder"))
        }

        return items
    }

    private var isAccessibilityLayout: Bool {
        dynamicTypeSize.isAccessibilitySize
    }

    private static let timestampFormatter: RelativeDateTimeFormatter = {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter
    }()
}
