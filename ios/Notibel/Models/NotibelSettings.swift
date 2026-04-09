import Foundation
import UIKit

struct NotibelSettings: Codable, Sendable {
    var serverURLString: String
    var appToken: String
    var installationID: String
    var installationName: String
    var topics: [String]

    init(
        serverURLString: String = "",
        appToken: String = "",
        installationID: String = UUID().uuidString.lowercased(),
        installationName: String = UIDevice.current.name,
        topics: [String] = ["codex"]
    ) {
        self.serverURLString = serverURLString
        self.appToken = appToken
        self.installationID = installationID
        self.installationName = installationName
        self.topics = topics
        normalize()
    }

    var baseURL: URL? {
        let rawValue = serverURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !rawValue.isEmpty else {
            return nil
        }
        guard let candidate = URL(string: rawValue), candidate.scheme != nil, candidate.host != nil else {
            return nil
        }
        return candidate
    }

    var normalizedTopics: [String] {
        var copy = topics
        copy = Self.normalizeTopics(copy)
        return copy
    }

    mutating func normalize() {
        serverURLString = serverURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        appToken = appToken.trimmingCharacters(in: .whitespacesAndNewlines)
        installationID = installationID.trimmingCharacters(in: .whitespacesAndNewlines)
        installationName = installationName.trimmingCharacters(in: .whitespacesAndNewlines)
        topics = Self.normalizeTopics(topics)

        if installationID.isEmpty {
            installationID = UUID().uuidString.lowercased()
        }
        if installationName.isEmpty {
            installationName = UIDevice.current.name
        }
    }

    static func normalizeTopic(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func normalizeTopics(_ topics: [String]) -> [String] {
        let cleaned = topics
            .map(normalizeTopic(_:))
            .filter { !$0.isEmpty }

        let deduped = cleaned.reduce(into: [String]()) { partialResult, topic in
            if !partialResult.contains(topic) {
                partialResult.append(topic)
            }
        }

        return deduped.sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }
}
