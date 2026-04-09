import SwiftUI

struct TopicDetailView: View {
    @Environment(AppModel.self) private var appModel
    let topic: String

    @State private var state: LoadState<[NotibelEvent]> = .idle

    var body: some View {
        content
            .navigationTitle(topic)
            .navigationBarTitleDisplayMode(.inline)
            .task(id: appModel.reloadSeed) {
                await loadEvents()
            }
    }

    private var content: some View {
        List {
            if !appModel.isConfiguredForServer {
                statusRow {
                    ContentUnavailableView(
                        "Configure Notibel",
                        systemImage: "server.rack",
                        description: Text("Add the server URL and app token in Settings before loading topic history.")
                    )
                }
            } else {
                switch state {
                case .idle, .loading:
                    statusRow {
                        ProgressView("Loading topic history...")
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 32)
                    }
                case .failed(let message):
                    statusRow {
                        ContentUnavailableView(
                            "Topic Unavailable",
                            systemImage: "exclamationmark.triangle",
                            description: Text(message)
                        )
                    }
                case .loaded(let events):
                    if events.isEmpty {
                        statusRow {
                            ContentUnavailableView(
                                "No Events Yet",
                                systemImage: "tray",
                                description: Text("This topic is registered, but there are no recent events.")
                            )
                        }
                    } else {
                        ForEach(events) { event in
                            NavigationLink(value: AppRoute.event(event)) {
                                EventRowView(event: event)
                            }
                            .listRowInsets(Self.eventRowInsets)
                        }
                    }
                }
            }
        }
        .listStyle(.plain)
        .refreshable {
            await loadEvents()
        }
    }

    @ViewBuilder
    private func statusRow<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, minHeight: 320)
            .listRowInsets(Self.eventRowInsets)
            .listRowSeparator(.hidden)
            .listRowBackground(Color.clear)
    }

    private static let eventRowInsets = EdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12)

    private func loadEvents() async {
        guard appModel.isConfiguredForServer else {
            state = .idle
            return
        }

        if !isShowingLoadedEvents {
            state = .loading
        }

        do {
            let events = try await appModel.fetchEvents(for: topic)
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
}
