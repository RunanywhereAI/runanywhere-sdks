//
//  RunAnywhere+WebSearchTool.swift
//  RunAnywhere SDK
//
//  SDK-facing web search tool helper for Swift tool-calling clients.
//

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public extension RunAnywhere {
    /// Definition for the built-in web search tool helper.
    static var webSearchToolDefinition: RAToolDefinition {
        WebSearchTool.definition
    }

    /// Register the built-in web search tool helper.
    static func registerWebSearchTool() async {
        await registerTool(WebSearchTool.definition, executor: WebSearchTool.executor)
    }
}

private enum WebSearchTool {
    private enum Tool {
        static let name = "search_web"
        static let description = "Searches the web for current information using DuckDuckGo Instant Answer API"
        static let category = "Web"
    }

    private enum Parameter {
        static let query = "query"
        static let queryDescription = "Search query (e.g., 'latest Swift concurrency updates')"
    }

    private enum PayloadKey {
        static let error = "error"
        static let query = "query"
        static let heading = "heading"
        static let summary = "summary"
        static let sourceURL = "source_url"
        static let relatedResults = "related_results"
        static let title = "title"
        static let text = "text"
        static let url = "url"
    }

    private enum URLConstants {
        static let scheme = "https"
        static let duckDuckGoLiteHost = "lite.duckduckgo.com"
        static let duckDuckGoLitePath = "/lite/"
        static let duckDuckGoAPIHost = "api.duckduckgo.com"
        static let duckDuckGoAPIPath = "/"
        static let userAgentHeader = "User-Agent"
        static let userAgent = "Mozilla/5.0"
        static let timeout: TimeInterval = 15
    }

    static let definition = RAToolDefinition(
        name: Tool.name,
        description: Tool.description,
        parameters: [
            RAToolParameter(
                name: Parameter.query,
                type: .string,
                description: Parameter.queryDescription
            )
        ],
        category: Tool.category
    )

    static var executor: ToolExecutor {
        { args in
            try await search(query: args[Parameter.query]?.string ?? "")
        }
    }

    private static func search(query: String) async throws -> [String: RAToolValue] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return [PayloadKey.error: RAToolValue("Missing search query")]
        }

        guard let url = makeLiteSearchURL(query: trimmedQuery) else {
            return [PayloadKey.error: RAToolValue("Invalid search query")]
        }

        let (data, _) = try await URLSession.shared.data(for: request(url: url))
        let html = String(data: data, encoding: .utf8) ?? ""
        let results = parseLiteResults(html).prefix(5)

        if let first = results.first {
            return resultPayload(query: trimmedQuery, primary: first, related: Array(results.dropFirst()))
        }

        return try await instantAnswerFallback(query: trimmedQuery)
    }

    private static func instantAnswerFallback(query: String) async throws -> [String: RAToolValue] {
        guard let url = makeInstantAnswerURL(query: query) else {
            return [PayloadKey.error: RAToolValue("Invalid search query")]
        }

        let (data, _) = try await URLSession.shared.data(for: request(url: url))
        guard let response = try? JSONDecoder().decode(InstantAnswerResponse.self, from: data) else {
            return [PayloadKey.error: RAToolValue("Could not parse search response")]
        }

        let related = relatedTopics(from: response.relatedTopics).prefix(5)
        var result: [String: RAToolValue] = [PayloadKey.query: RAToolValue(query)]

        if !response.heading.isEmpty {
            result[PayloadKey.heading] = RAToolValue(response.heading)
        }

        if !response.abstractText.isEmpty {
            result[PayloadKey.summary] = RAToolValue(response.abstractText)
        } else if !response.answer.isEmpty {
            result[PayloadKey.summary] = RAToolValue(response.answer)
        } else if let firstRelated = related.first {
            result[PayloadKey.summary] = RAToolValue(firstRelated.text)
        } else {
            result[PayloadKey.summary] = RAToolValue("No instant answer was returned for this query.")
        }

        if !response.abstractURL.isEmpty {
            result[PayloadKey.sourceURL] = RAToolValue(response.abstractURL)
        }

        let relatedValues = related.map { topic in
            RAToolValue.object([
                PayloadKey.title: RAToolValue(topic.title),
                PayloadKey.text: RAToolValue(topic.text),
                PayloadKey.url: RAToolValue(topic.url)
            ])
        }

        if !relatedValues.isEmpty {
            result[PayloadKey.relatedResults] = RAToolValue.array(relatedValues)
        }

        return result
    }

    private static func makeLiteSearchURL(query: String) -> URL? {
        var components = URLComponents()
        components.scheme = URLConstants.scheme
        components.host = URLConstants.duckDuckGoLiteHost
        components.path = URLConstants.duckDuckGoLitePath
        components.queryItems = [URLQueryItem(name: Parameter.query, value: query)]
        return components.url
    }

    private static func makeInstantAnswerURL(query: String) -> URL? {
        var components = URLComponents()
        components.scheme = URLConstants.scheme
        components.host = URLConstants.duckDuckGoAPIHost
        components.path = URLConstants.duckDuckGoAPIPath
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "format", value: "json"),
            URLQueryItem(name: "no_redirect", value: "1"),
            URLQueryItem(name: "no_html", value: "1"),
            URLQueryItem(name: "skip_disambig", value: "1")
        ]
        return components.url
    }

    private static func request(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue(URLConstants.userAgent, forHTTPHeaderField: URLConstants.userAgentHeader)
        request.timeoutInterval = URLConstants.timeout
        return request
    }

    private static func resultPayload(
        query: String,
        primary: SearchResult,
        related: [SearchResult]
    ) -> [String: RAToolValue] {
        var result: [String: RAToolValue] = [
            PayloadKey.query: RAToolValue(query),
            PayloadKey.heading: RAToolValue(primary.title),
            PayloadKey.summary: RAToolValue(primary.snippet),
            PayloadKey.sourceURL: RAToolValue(primary.url)
        ]

        if !related.isEmpty {
            result[PayloadKey.relatedResults] = RAToolValue.array(related.map { item in
                RAToolValue.object([
                    PayloadKey.title: RAToolValue(item.title),
                    PayloadKey.text: RAToolValue(item.snippet),
                    PayloadKey.url: RAToolValue(item.url)
                ])
            })
        }

        return result
    }

    private static func parseLiteResults(_ html: String) -> [SearchResult] {
        let pattern = #"<a[^>]*href="([^"]+)"[^>]*class='result-link'[^>]*>(.*?)</a>[\s\S]*?<td class='result-snippet'>\s*([\s\S]*?)\s*</td>"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(html.startIndex..<html.endIndex, in: html)

        return regex.matches(in: html, range: range).compactMap { match in
            guard
                let href = substring(html, match.range(at: 1)),
                let title = substring(html, match.range(at: 2)),
                let snippet = substring(html, match.range(at: 3))
            else {
                return nil
            }

            let resolvedURL = redirectURL(from: decodeHTML(href))
            let cleanTitle = cleanHTML(title)
            let cleanSnippet = cleanHTML(snippet)
            guard !cleanTitle.isEmpty, !cleanSnippet.isEmpty, !resolvedURL.isEmpty else {
                return nil
            }

            return SearchResult(title: cleanTitle, url: resolvedURL, snippet: cleanSnippet)
        }
    }

    private static func redirectURL(from href: String) -> String {
        guard let urlRange = href.range(of: "uddg=") else {
            if href.hasPrefix("//") {
                return "https:\(href)"
            }
            return href
        }

        let encodedStart = href[urlRange.upperBound...]
        let encoded = encodedStart.split(separator: "&").first.map(String.init) ?? String(encodedStart)
        return encoded.removingPercentEncoding ?? encoded
    }

    private static func relatedTopics(from topics: [RelatedTopicResponse]) -> [RelatedTopic] {
        topics.flatMap { topic -> [RelatedTopic] in
            if !topic.topics.isEmpty {
                return relatedTopics(from: topic.topics)
            }
            return makeRelatedTopic(topic).map { [$0] } ?? []
        }
    }

    private static func makeRelatedTopic(_ topic: RelatedTopicResponse) -> RelatedTopic? {
        guard !topic.text.isEmpty else { return nil }
        let title = topic.text.components(separatedBy: " - ").first ?? topic.text
        return RelatedTopic(title: title, text: topic.text, url: topic.firstURL)
    }

    private static func substring(_ string: String, _ range: NSRange) -> String? {
        guard let range = Range(range, in: string) else { return nil }
        return String(string[range])
    }

    private static func cleanHTML(_ value: String) -> String {
        let noTags = value.replacingOccurrences(
            of: #"<[^>]+>"#,
            with: " ",
            options: .regularExpression
        )
        return decodeHTML(noTags)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func decodeHTML(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#x27;", with: "'")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
            .replacingOccurrences(of: "&nbsp;", with: " ")
    }
}

private struct SearchResult {
    let title: String
    let url: String
    let snippet: String
}

private struct RelatedTopic {
    let title: String
    let text: String
    let url: String
}

private struct InstantAnswerResponse: Decodable {
    let abstractText: String
    let answer: String
    let heading: String
    let abstractURL: String
    let relatedTopics: [RelatedTopicResponse]

    enum CodingKeys: String, CodingKey {
        case abstractText = "AbstractText"
        case answer = "Answer"
        case heading = "Heading"
        case abstractURL = "AbstractURL"
        case relatedTopics = "RelatedTopics"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        abstractText = Self.trimmed(try container.decodeIfPresent(String.self, forKey: .abstractText))
        answer = Self.trimmed(try container.decodeIfPresent(String.self, forKey: .answer))
        heading = Self.trimmed(try container.decodeIfPresent(String.self, forKey: .heading))
        abstractURL = Self.trimmed(try container.decodeIfPresent(String.self, forKey: .abstractURL))
        relatedTopics = try container.decodeIfPresent([RelatedTopicResponse].self, forKey: .relatedTopics) ?? []
    }

    private static func trimmed(_ value: String?) -> String {
        value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}

private struct RelatedTopicResponse: Decodable {
    let text: String
    let firstURL: String
    let topics: [RelatedTopicResponse]

    enum CodingKeys: String, CodingKey {
        case text = "Text"
        case firstURL = "FirstURL"
        case topics = "Topics"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        text = Self.trimmed(try container.decodeIfPresent(String.self, forKey: .text))
        firstURL = Self.trimmed(try container.decodeIfPresent(String.self, forKey: .firstURL))
        topics = try container.decodeIfPresent([RelatedTopicResponse].self, forKey: .topics) ?? []
    }

    private static func trimmed(_ value: String?) -> String {
        value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    }
}
