import Foundation

struct NotibelAPIClient: Sendable {
    let baseURL: URL
    let appToken: String

    init(settings: NotibelSettings) throws {
        guard let baseURL = settings.baseURL else {
            throw NotibelAPIError.invalidConfiguration("Enter a valid server URL in Settings.")
        }

        let token = settings.appToken.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else {
            throw NotibelAPIError.invalidConfiguration("Enter the app token from your Notibel server.")
        }

        self.baseURL = baseURL
        self.appToken = token
    }

    func fetchNotifications(topics: [String], limitPerTopic: Int) async throws -> [NotibelEvent] {
        let normalizedTopics = topics
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }

        guard !normalizedTopics.isEmpty else {
            return []
        }

        return try await withThrowingTaskGroup(of: [NotibelEvent].self) { group in
            for topic in normalizedTopics {
                group.addTask {
                    try await fetchEvents(topic: topic, limit: limitPerTopic)
                }
            }

            var collected = [NotibelEvent]()
            for try await events in group {
                collected.append(contentsOf: events)
            }

            let unique = Dictionary(collected.map { ($0.id, $0) }, uniquingKeysWith: { current, _ in current })
            return unique.values.sorted { $0.createdAt > $1.createdAt }
        }
    }

    func fetchEvents(topic: String, limit: Int) async throws -> [NotibelEvent] {
        var components = URLComponents(url: eventsURL(for: topic), resolvingAgainstBaseURL: false)
        components?.queryItems = [URLQueryItem(name: "limit", value: String(limit))]

        guard let url = components?.url else {
            throw NotibelAPIError.invalidConfiguration("Could not build the topic events URL.")
        }

        var request = authorizedRequest(url: url)
        request.httpMethod = "GET"

        let data = try await perform(request)
        return try decoder.decode(TopicEventsResponse.self, from: data).events
    }

    func registerDevice(
        installationID: String,
        deviceToken: String,
        topics: [String],
        name: String
    ) async throws {
        let payload = DeviceRegistrationPayload(deviceToken: deviceToken, topics: topics, name: name)
        let url = devicesURL(for: installationID)
        var request = authorizedRequest(url: url)
        request.httpMethod = "PUT"
        request.httpBody = try JSONEncoder().encode(payload)

        _ = try await perform(request)
    }

    func deleteDevice(installationID: String) async throws {
        let url = devicesURL(for: installationID)
        var request = authorizedRequest(url: url)
        request.httpMethod = "DELETE"

        _ = try await perform(request)
    }

    private func authorizedRequest(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(appToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        return request
    }

    private func perform(_ request: URLRequest) async throws -> Data {
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw NotibelAPIError.invalidResponse
        }

        guard (200..<300).contains(httpResponse.statusCode) else {
            if let serverError = try? decoder.decode(APIErrorResponse.self, from: data) {
                throw NotibelAPIError.server(serverError.error)
            }
            throw NotibelAPIError.server("The server returned status code \(httpResponse.statusCode).")
        }

        return data
    }

    private func eventsURL(for topic: String) -> URL {
        baseURL
            .appendingPathComponent("v1")
            .appendingPathComponent("topics")
            .appendingPathComponent(topic)
            .appendingPathComponent("events")
    }

    private func devicesURL(for installationID: String) -> URL {
        baseURL
            .appendingPathComponent("v1")
            .appendingPathComponent("devices")
            .appendingPathComponent(installationID)
    }

    private var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

enum NotibelAPIError: LocalizedError {
    case invalidConfiguration(String)
    case server(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .invalidConfiguration(let message):
            return message
        case .server(let message):
            return message
        case .invalidResponse:
            return "The server response could not be decoded."
        }
    }
}
