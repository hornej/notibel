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

            metadataSection
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

    @ViewBuilder
    private var metadataSection: some View {
        if metadataItems.isEmpty {
            EmptyView()
        } else if isAccessibilityLayout {
            MetadataStack(items: metadataItems)
        } else {
            ViewThatFits(in: .horizontal) {
                MetadataRow(items: metadataItems)
                    .fixedSize(horizontal: true, vertical: false)

                MetadataSplitRow(items: metadataItems)
                    .fixedSize(horizontal: true, vertical: false)

                MetadataStack(items: metadataItems)
            }
        }
    }

    private var metadataItems: [MetadataItem] {
        var items: [MetadataItem] = [
            MetadataItem(text: event.topic, systemImage: "number")
        ]

        if let source = event.displaySource {
            items.append(MetadataItem(text: source, systemImage: "desktopcomputer"))
        }

        if let project = event.project, !project.isEmpty {
            items.append(MetadataItem(text: project, systemImage: "folder"))
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

private struct MetadataItem: Identifiable {
    let text: String
    let systemImage: String

    var id: String {
        "\(systemImage)-\(text)"
    }
}

private struct MetadataRow: View {
    let items: [MetadataItem]

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            ForEach(items) { item in
                MetadataLabel(item: item)
            }
        }
    }
}

private struct MetadataSplitRow: View {
    let items: [MetadataItem]

    var body: some View {
        if secondaryItems.isEmpty {
            MetadataRow(items: primaryItems)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                MetadataRow(items: primaryItems)
                MetadataRow(items: secondaryItems)
            }
        }
    }

    private var primaryItems: [MetadataItem] {
        Array(items.prefix(2))
    }

    private var secondaryItems: [MetadataItem] {
        Array(items.dropFirst(2))
    }
}

private struct MetadataStack: View {
    let items: [MetadataItem]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(items) { item in
                MetadataLabel(item: item)
            }
        }
    }
}

private struct MetadataLabel: View {
    let item: MetadataItem

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Image(systemName: item.systemImage)
                .imageScale(.small)

            Text(item.text)
                .lineLimit(1)
                .minimumScaleFactor(0.92)
                .truncationMode(.tail)
        }
    }
}
