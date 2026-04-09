import Foundation
import SwiftUI
import UIKit

struct NotibelEvent: Codable, Hashable, Identifiable, Sendable {
    let id: String
    let topic: String
    let title: String
    let message: String
    let source: String?
    let project: String?
    let threadTitle: String?
    let createdAt: Date

    var renderedMessage: AttributedString {
        Self.renderMessage(message)
    }

    // SwiftUI's Text only reliably honors inline markdown from AttributedString.
    // Preserve Codex line breaks and render fenced code blocks as literal monospace text.
    private static func renderMessage(_ message: String) -> AttributedString {
        let normalizedMessage = message
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")

        var renderedMessage = AttributedString()
        var cursor = normalizedMessage.startIndex

        while let fenceStart = normalizedMessage[cursor...].range(of: "```") {
            appendInlineMarkdown(
                String(normalizedMessage[cursor..<fenceStart.lowerBound]),
                to: &renderedMessage
            )

            let languageStart = fenceStart.upperBound
            guard let languageEnd = normalizedMessage[languageStart...].firstIndex(of: "\n") else {
                renderedMessage += AttributedString(String(normalizedMessage[fenceStart.lowerBound...]))
                return renderedMessage
            }

            let codeStart = normalizedMessage.index(after: languageEnd)
            guard let fenceEnd = normalizedMessage[codeStart...].range(of: "\n```") else {
                renderedMessage += AttributedString(String(normalizedMessage[fenceStart.lowerBound...]))
                return renderedMessage
            }

            var codeBlock = AttributedString(String(normalizedMessage[codeStart..<fenceEnd.lowerBound]))
            codeBlock.inlinePresentationIntent = .code
            renderedMessage += codeBlock
            cursor = fenceEnd.upperBound
        }

        appendInlineMarkdown(String(normalizedMessage[cursor...]), to: &renderedMessage)
        applyCodeStyling(to: &renderedMessage)
        return renderedMessage
    }

    private static func appendInlineMarkdown(_ markdown: String, to output: inout AttributedString) {
        guard !markdown.isEmpty else { return }

        if let renderedMarkdown = try? AttributedString(markdown: markdown, options: Self.inlineMarkdownOptions) {
            output += renderedMarkdown
            return
        }

        output += AttributedString(markdown)
    }

    private static let inlineMarkdownOptions: AttributedString.MarkdownParsingOptions = {
        var options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        options.failurePolicy = .returnPartiallyParsedIfPossible
        return options
    }()

    private static func applyCodeStyling(to renderedMessage: inout AttributedString) {
        let codeRanges = renderedMessage.runs.compactMap { run -> Range<AttributedString.Index>? in
            guard run.inlinePresentationIntent?.contains(.code) == true else {
                return nil
            }

            return run.range
        }

        for codeRange in codeRanges {
            renderedMessage[codeRange].font = codeFont
        }
    }

    private static var codeFont: Font {
        if UIFont(name: "BerkeleyMono-Regular", size: 15) != nil {
            return .custom("BerkeleyMono-Regular", size: 15, relativeTo: .body)
        }

        return .system(.body, design: .monospaced)
    }
}

struct NotibelEventReference: Hashable, Sendable {
    let eventID: String
    let topic: String?
    let fallbackEvent: NotibelEvent?
}

struct TopicEventsResponse: Codable, Sendable {
    let topic: String
    let events: [NotibelEvent]
}

struct EventResponse: Codable, Sendable {
    let event: NotibelEvent
}

struct DeviceRegistrationPayload: Codable, Sendable {
    let deviceToken: String
    let topics: [String]
    let name: String
}

struct APIErrorResponse: Codable, Sendable {
    let error: String
}
