import SwiftUI

struct NotificationsView: View {
    @Environment(AppModel.self) private var appModel

    @State private var state: LoadState<[NotibelEvent]> = .idle
    @State private var isPresentingAddTopic = false
    @State private var isPresentingTopicFilters = false
    @State private var selectedTopics = Set<String>()
    @State private var hasInitializedTopicFilter = false

    var body: some View {
        List {
            notificationContent
        }
        .listStyle(.plain)
        .navigationTitle("Notifications")
        .task(id: loadTaskID) {
            await loadNotifications()
        }
        .onChange(of: availableTopics, initial: true) { oldTopics, newTopics in
            syncSelectedTopics(from: oldTopics, to: newTopics)
        }
        .refreshable {
            await loadNotifications()
        }
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                if appModel.hasTopics {
                    Button {
                        isPresentingTopicFilters = true
                    } label: {
                        filterButtonLabel
                    }
                    .accessibilityLabel(filterAccessibilityLabel)
                }

                Button {
                    isPresentingAddTopic = true
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $isPresentingAddTopic) {
            AddTopicSheet { topic in
                Task {
                    if let addedTopic = await appModel.addTopic(topic) {
                        selectedTopics.insert(addedTopic)
                    }
                }
            }
        }
        .sheet(isPresented: $isPresentingTopicFilters) {
            topicFilterSheet
        }
    }

    private var availableTopics: [String] {
        appModel.settings.normalizedTopics
    }

    private var filteredTopics: [String] {
        availableTopics.filter { selectedTopics.contains($0) }
    }

    private var allTopicsSelected: Bool {
        !availableTopics.isEmpty && selectedTopics == Set(availableTopics)
    }

    private var loadTaskID: NotificationsLoadTaskID {
        NotificationsLoadTaskID(reloadSeed: appModel.reloadSeed, topics: filteredTopics)
    }

    private var filterButtonLabel: some View {
        HStack(spacing: 4) {
            Image(systemName: allTopicsSelected ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
            Text(allTopicsSelected ? "All" : "\(filteredTopics.count)")
                .font(.caption.weight(.semibold))
        }
    }

    @ViewBuilder
    private var notificationContent: some View {
        if !appModel.isConfiguredForServer {
            statusRow {
                ContentUnavailableView(
                    "Configure Notibel",
                    systemImage: "server.rack",
                    description: Text("Add the Notibel server URL and app token in Settings before loading notifications.")
                )
            }
        } else if !appModel.hasTopics {
            statusRow {
                ContentUnavailableView {
                    Label("No Topics Yet", systemImage: "number.square")
                } description: {
                    Text("Add at least one topic to start receiving notifications.")
                } actions: {
                    Button("Add Topic") {
                        isPresentingAddTopic = true
                    }
                }
            }
        } else if filteredTopics.isEmpty {
            statusRow {
                ContentUnavailableView {
                    Label("No Topics Selected", systemImage: "line.3.horizontal.decrease.circle")
                } description: {
                    Text("Turn at least one topic back on to load notifications.")
                } actions: {
                    Button("Show All Topics") {
                        selectedTopics = Set(availableTopics)
                    }
                }
            }
        } else {
            switch state {
            case .idle, .loading:
                statusRow {
                    ProgressView("Loading notifications...")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 32)
                }
            case .failed(let message):
                statusRow {
                    ContentUnavailableView(
                        "Notifications Unavailable",
                        systemImage: "exclamationmark.triangle",
                        description: Text(message)
                    )
                }
            case .loaded(let events):
                if events.isEmpty {
                    statusRow {
                        ContentUnavailableView(
                            "No Notifications Yet",
                            systemImage: "bell.slash",
                            description: Text("The server is reachable, but there are no recent notifications for the selected topics.")
                        )
                    }
                } else {
                    ForEach(events) { event in
                        NavigationLink(value: AppRoute.event(event)) {
                            EventRowView(event: event)
                        }
                        .listRowInsets(Self.rowInsets)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func statusRow<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, minHeight: 320)
            .listRowInsets(Self.rowInsets)
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }

    private static let rowInsets = EdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12)

    private var filterAccessibilityLabel: String {
        if allTopicsSelected {
            return "Filter topics, currently showing all topics"
        }

        return "Filter topics, currently showing \(filteredTopics.count) topics"
    }

    private var topicFilterSheet: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        selectedTopics = Set(availableTopics)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: allTopicsSelected ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(allTopicsSelected ? Color.accentColor : Color.secondary)

                            VStack(alignment: .leading, spacing: 4) {
                                Text("All Topics")
                                    .font(.headline)
                                Text("Show notifications from every topic.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }

                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(allTopicsSelected)

                    ForEach(availableTopics, id: \.self) { topic in
                        Button {
                            toggleTopicSelection(topic)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: selectedTopics.contains(topic) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(selectedTopics.contains(topic) ? Color.accentColor : Color.secondary)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(topic)
                                        .font(.headline)
                                    Text(selectedTopics.contains(topic) ? "Included in notifications" : "Filtered out")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }

                                Spacer(minLength: 0)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .swipeActions {
                            Button(role: .destructive) {
                                removeTopic(topic)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                } header: {
                    Text("Topics")
                } footer: {
                    Text("Tap to include or exclude a topic. Swipe left to remove a topic.")
                }
            }
            .navigationTitle("Filter Topics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        isPresentingTopicFilters = false
                    }
                }
            }
        }
    }

    private func loadNotifications() async {
        guard appModel.isConfiguredForServer, appModel.hasTopics, !filteredTopics.isEmpty else {
            state = .idle
            return
        }

        if !isShowingLoadedEvents {
            state = .loading
        }

        do {
            let events = try await appModel.fetchNotifications(topics: filteredTopics)
            guard !Task.isCancelled else {
                return
            }
            state = .loaded(events)
        } catch is CancellationError {
            return
        } catch {
            state = .failed(error.localizedDescription)
        }
    }

    private var isShowingLoadedEvents: Bool {
        if case .loaded = state {
            return true
        }
        return false
    }

    private func toggleTopicSelection(_ topic: String) {
        if selectedTopics.contains(topic) {
            selectedTopics.remove(topic)
        } else {
            selectedTopics.insert(topic)
        }
    }

    private func syncSelectedTopics(from oldTopics: [String], to newTopics: [String]) {
        let oldSet = Set(oldTopics)
        let newSet = Set(newTopics)

        guard hasInitializedTopicFilter else {
            selectedTopics = newSet
            hasInitializedTopicFilter = true
            return
        }

        let wasShowingAllTopics = selectedTopics == oldSet
        selectedTopics.formIntersection(newSet)

        if wasShowingAllTopics {
            selectedTopics.formUnion(newSet)
        }
    }

    private func removeTopics(at offsets: IndexSet) {
        let removedTopics = offsets.map { index in
            availableTopics[index]
        }

        selectedTopics.subtract(removedTopics)

        Task {
            await appModel.removeTopics(at: offsets)
        }
    }

    private func removeTopic(_ topic: String) {
        guard let topicIndex = availableTopics.firstIndex(of: topic) else {
            return
        }

        removeTopics(at: IndexSet(integer: topicIndex))
    }
}

private struct NotificationsLoadTaskID: Hashable {
    let reloadSeed: UUID
    let topics: [String]
}
