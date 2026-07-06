//
//  ToolSettingsView.swift
//  RunAnywhereAI
//
//  Tool registration and management settings
//

import SwiftUI
import Foundation
import RunAnywhere
import os

// MARK: - Tool Settings View Model

@MainActor
class ToolSettingsViewModel: ObservableObject {
    static let shared = ToolSettingsViewModel()

    private let logger = Logger(subsystem: "com.runanywhere", category: "ToolCalling")

    @Published var registeredTools: [RAToolDefinition] = []
    @Published var toolCallingEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(toolCallingEnabled, forKey: "toolCallingEnabled")
            if toolCallingEnabled {
                logger.info("Registered tool calling enabled")
                Task { await registerDemoTools() }
            }
        }
    }

    // Built-in demo tools with REAL API implementations
    private var demoTools: [(definition: RAToolDefinition, executor: ToolExecutor)] {
        [
            // Web Search Tool - Uses DuckDuckGo Instant Answer API (free, no API key required)
            (
                definition: RAToolDefinition(
                    name: "search_web",
                    description: "Searches the web for current information using DuckDuckGo Instant Answer API",
                    parameters: [
                        RAToolParameter(
                            name: "query",
                            type: .string,
                            description: "Search query (e.g., 'latest Swift concurrency updates')"
                        )
                    ],
                    category: "Web"
                ),
                executor: { args in
                    try await WebSearchService.search(query: args["query"]?.string ?? "")
                }
            ),
            // Weather Tool - Uses Open-Meteo API (free, no API key required)
            (
                definition: RAToolDefinition(
                    name: "get_weather",
                    description: "Gets the current weather for a given location using Open-Meteo API",
                    parameters: [
                        RAToolParameter(
                            name: "location",
                            type: .string,
                            description: "City name (e.g., 'San Francisco', 'London', 'Tokyo')"
                        )
                    ],
                    category: "Utility"
                ),
                executor: { args in
                    try await WeatherService.fetchWeather(for: args["location"]?.string ?? "San Francisco")
                }
            ),
            // Time Tool - Real system time with timezone
            (
                definition: RAToolDefinition(
                    name: "get_current_time",
                    description: "Gets the current date, time, and timezone information",
                    parameters: [],
                    category: "Utility"
                ),
                executor: { _ in
                    let now = Date()
                    let dateFormatter = DateFormatter()
                    dateFormatter.dateStyle = .full
                    dateFormatter.timeStyle = .medium

                    let timeZone = TimeZone.current
                    let timeFormatter = DateFormatter()
                    timeFormatter.dateFormat = "HH:mm:ss"

                    return [
                        "datetime": RAToolValue(dateFormatter.string(from: now)),
                        "time": RAToolValue(timeFormatter.string(from: now)),
                        "timestamp": RAToolValue(ISO8601DateFormatter().string(from: now)),
                        "timezone": RAToolValue(timeZone.identifier),
                        "utc_offset": RAToolValue(timeZone.abbreviation() ?? "UTC")
                    ]
                }
            ),
            // Calculator Tool - Real math evaluation
            (
                definition: RAToolDefinition(
                    name: "calculate",
                    description: "Performs math calculations. Supports +, -, *, /, and parentheses",
                    parameters: [
                        RAToolParameter(
                            name: "expression",
                            type: .string,
                            description: "Math expression (e.g., '2 + 2 * 3', '(10 + 5) / 3')"
                        )
                    ],
                    category: "Utility"
                ),
                executor: { args in
                    // Extract expression from args, handling both string and number RAToolValue types.
                    let expression: String? = {
                        let keys = ["expression", "input", "expr"]
                        for key in keys {
                            if let val = args[key] {
                                if let str = val.string { return str }
                                if let num = val.number { return "\(num)" }
                            }
                        }
                        // Fallback: try any value in the dict
                        for val in args.values {
                            if let str = val.string { return str }
                            if let num = val.number { return "\(num)" }
                        }
                        return nil
                    }()
                    guard let expression, !expression.isEmpty else {
                        return [
                            "error": RAToolValue("Missing expression argument")
                        ]
                    }
                    print("Calculator received args: \(args), using expression: '\(expression)'")
                    // Clean the expression - remove any non-math characters
                    let cleanedExpression = expression
                        .replacingOccurrences(of: "=", with: "")
                        .replacingOccurrences(of: "x", with: "*")
                        .replacingOccurrences(of: "×", with: "*")
                        .replacingOccurrences(of: "÷", with: "/")
                        .trimmingCharacters(in: .whitespacesAndNewlines)

                    // Safely evaluate using a deterministic parser that validates
                    // grammar and returns errors instead of crashing (unlike
                    // NSExpression, whose Obj-C exceptions cannot be caught from Swift).
                    if let value = SafeMathEvaluator.evaluate(cleanedExpression) {
                        return [
                            "result": RAToolValue(value),
                            "expression": RAToolValue(expression)
                        ]
                    }
                    return [
                        "error": RAToolValue("Could not evaluate expression: \(expression)"),
                        "expression": RAToolValue(expression)
                    ]
                }
            )
        ]
    }

    init() {
        toolCallingEnabled = UserDefaults.standard.bool(forKey: "toolCallingEnabled")
        Task {
            await refreshRegisteredTools()
        }
    }

    func refreshRegisteredTools() async {
        registeredTools = await RunAnywhere.getRegisteredTools()
    }

    func registerDemoTools() async {
        for tool in demoTools {
            await RunAnywhere.registerTool(tool.definition, executor: tool.executor)
            logger.info("Registered tool \(tool.definition.name)")
        }
        await refreshRegisteredTools()
    }

    func clearAllTools() async {
        await RunAnywhere.clearTools()
        await refreshRegisteredTools()
    }
}

// MARK: - Tool Settings Section (iOS)

struct ToolSettingsSection: View {
    @ObservedObject var viewModel: ToolSettingsViewModel

    var body: some View {
        Section {
            Toggle("Enable Tool Calling", isOn: $viewModel.toolCallingEnabled)

            if viewModel.toolCallingEnabled {
                HStack {
                    Text("Registered Tools")
                    Spacer()
                    Text("\(viewModel.registeredTools.count)")
                        .foregroundColor(AppColors.textSecondary)
                }

                if viewModel.registeredTools.isEmpty {
                    Button("Add Demo Tools") {
                        Task {
                            await viewModel.registerDemoTools()
                        }
                    }
                    .foregroundColor(AppColors.primaryAccent)
                    // Keep tap target clear of the bottom tab bar so the
                    // centre of the button doesn't register a tab-switch tap.
                    .padding(.bottom, 50)
                } else {
                    ForEach(viewModel.registeredTools, id: \.name) { tool in
                        ToolRow(tool: tool)
                    }

                    Button("Clear All Tools") {
                        Task {
                            await viewModel.clearAllTools()
                        }
                    }
                    .foregroundColor(AppColors.primaryRed)
                    // Same tab-bar overlap mitigation as the demo-tools button.
                    .padding(.bottom, 50)
                }
            }
        } header: {
            Text("Tool Calling")
        } footer: {
            Text(
                "Allow the LLM to use registered tools to perform actions like "
                + "web lookup, weather, time, or calculations."
            )
            .font(AppTypography.caption)
        }
    }
}

// MARK: - Tool Settings Card (macOS)

struct ToolSettingsCard: View {
    @ObservedObject var viewModel: ToolSettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xLarge) {
            Text("Tool Calling")
                .font(AppTypography.headline)
                .foregroundColor(AppColors.textSecondary)

            VStack(alignment: .leading, spacing: AppSpacing.large) {
                HStack {
                    Text("Enable Tool Calling")
                        .frame(width: 150, alignment: .leading)
                    Toggle("", isOn: $viewModel.toolCallingEnabled)
                    Spacer()
                    Text(viewModel.toolCallingEnabled ? "Enabled" : "Disabled")
                        .font(AppTypography.caption)
                        .foregroundColor(viewModel.toolCallingEnabled ? AppColors.statusGreen : AppColors.textSecondary)
                }

                if viewModel.toolCallingEnabled {
                    Divider()

                    HStack {
                        Text("Registered Tools")
                        Spacer()
                        Text("\(viewModel.registeredTools.count)")
                            .font(AppTypography.monospaced)
                            .foregroundColor(AppColors.primaryAccent)
                    }

                    if viewModel.registeredTools.isEmpty {
                        Button("Add Demo Tools") {
                            Task {
                                await viewModel.registerDemoTools()
                            }
                        }
                        .buttonStyle(.bordered)
                        .tint(AppColors.primaryAccent)
                    } else {
                        ForEach(viewModel.registeredTools, id: \.name) { tool in
                            ToolRow(tool: tool)
                        }

                        Button("Clear All Tools") {
                            Task {
                                await viewModel.clearAllTools()
                            }
                        }
                        .buttonStyle(.bordered)
                        .tint(AppColors.primaryRed)
                    }
                }

                Text(
                    "Allow the LLM to use registered tools to perform actions like "
                    + "web lookup, weather, time, or calculations."
                )
                .font(AppTypography.caption)
                .foregroundColor(AppColors.textSecondary)
            }
            .padding(AppSpacing.large)
            .background(AppColors.backgroundSecondary)
            .cornerRadius(AppSpacing.cornerRadiusLarge)
        }
    }
}

// MARK: - Tool Row

struct ToolRow: View {
    let tool: RAToolDefinition

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "wrench.and.screwdriver")
                    .font(.system(size: 12))
                    .foregroundColor(AppColors.primaryAccent)
                Text(tool.name)
                    .font(AppTypography.subheadlineMedium)
            }
            Text(tool.description_p)
                .font(AppTypography.caption)
                .foregroundColor(AppColors.textSecondary)
                .lineLimit(2)

            if !tool.parameters.isEmpty {
                HStack(spacing: 4) {
                    Text("Params:")
                        .font(AppTypography.caption2)
                        .foregroundColor(AppColors.textSecondary)
                    ForEach(tool.parameters, id: \.name) { param in
                        Text(param.name)
                            .font(AppTypography.caption2)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(AppColors.backgroundTertiary)
                            .cornerRadius(4)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Web Search Service

/// Real web lookup service using DuckDuckGo Lite (free, no API key required)
enum WebSearchService {
    private static let liteSearchURL = "https://lite.duckduckgo.com/lite/"
    private static let instantAnswerURL = "https://api.duckduckgo.com/"

    static func search(query: String) async throws -> [String: RAToolValue] {
        let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuery.isEmpty else {
            return ["error": RAToolValue("Missing search query")]
        }

        guard let encodedQuery = trimmedQuery.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(liteSearchURL)?q=\(encodedQuery)") else {
            return ["error": RAToolValue("Invalid search query")]
        }

        // SAMPLE_HTTP_CARVE_OUT: external demo tool call, not SDK auth/download traffic.
        let (data, _) = try await URLSession.shared.data(for: request(url: url))
        let html = String(data: data, encoding: .utf8) ?? ""
        let results = parseLiteResults(html).prefix(5)

        if let first = results.first {
            return resultPayload(query: trimmedQuery, primary: first, related: Array(results.dropFirst()))
        }

        return try await instantAnswerFallback(query: trimmedQuery, encodedQuery: encodedQuery)
    }

    private static func instantAnswerFallback(
        query: String,
        encodedQuery: String
    ) async throws -> [String: RAToolValue] {
        guard let url = URL(
            string: "\(instantAnswerURL)?q=\(encodedQuery)&format=json&no_redirect=1&no_html=1&skip_disambig=1"
        ) else {
            return ["error": RAToolValue("Invalid search query")]
        }

        let (data, _) = try await URLSession.shared.data(for: request(url: url))
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ["error": RAToolValue("Could not parse search response")]
        }

        let abstract = stringValue(json["AbstractText"])
        let answer = stringValue(json["Answer"])
        let heading = stringValue(json["Heading"])
        let sourceURL = stringValue(json["AbstractURL"])
        let related = relatedTopics(from: json["RelatedTopics"]).prefix(5)

        var result: [String: RAToolValue] = ["query": RAToolValue(query)]

        if !heading.isEmpty {
            result["heading"] = RAToolValue(heading)
        }

        if !abstract.isEmpty {
            result["summary"] = RAToolValue(abstract)
        } else if !answer.isEmpty {
            result["summary"] = RAToolValue(answer)
        } else if let firstRelated = related.first {
            result["summary"] = RAToolValue(firstRelated.text)
        } else {
            result["summary"] = RAToolValue("No instant answer was returned for this query.")
        }

        if !sourceURL.isEmpty {
            result["source_url"] = RAToolValue(sourceURL)
        }

        let relatedValues = related.map { topic in
            RAToolValue.object([
                "title": RAToolValue(topic.title),
                "text": RAToolValue(topic.text),
                "url": RAToolValue(topic.url)
            ])
        }

        if !relatedValues.isEmpty {
            result["related_results"] = RAToolValue.array(relatedValues)
        }

        return result
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

    private static func resultPayload(
        query: String,
        primary: SearchResult,
        related: [SearchResult]
    ) -> [String: RAToolValue] {
        var result: [String: RAToolValue] = [
            "query": RAToolValue(query),
            "heading": RAToolValue(primary.title),
            "summary": RAToolValue(primary.snippet),
            "source_url": RAToolValue(primary.url)
        ]

        if !related.isEmpty {
            result["related_results"] = RAToolValue.array(related.map { item in
                RAToolValue.object([
                    "title": RAToolValue(item.title),
                    "text": RAToolValue(item.snippet),
                    "url": RAToolValue(item.url)
                ])
            })
        }

        return result
    }

    private static func request(url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15
        return request
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

    private static func relatedTopics(from value: Any?) -> [RelatedTopic] {
        guard let topics = value as? [[String: Any]] else { return [] }
        return topics.flatMap { topic -> [RelatedTopic] in
            if let nestedTopics = topic["Topics"] as? [[String: Any]] {
                return nestedTopics.compactMap(makeRelatedTopic)
            }
            return makeRelatedTopic(topic).map { [$0] } ?? []
        }
    }

    private static func makeRelatedTopic(_ topic: [String: Any]) -> RelatedTopic? {
        let text = stringValue(topic["Text"])
        guard !text.isEmpty else { return nil }

        let title = text.components(separatedBy: " - ").first ?? text
        return RelatedTopic(
            title: title,
            text: text,
            url: stringValue(topic["FirstURL"])
        )
    }

    private static func stringValue(_ value: Any?) -> String {
        (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
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

// MARK: - Weather Service (Open-Meteo API)

/// Real weather service using Open-Meteo API (free, no API key required)
enum WeatherService {
    // Open-Meteo Geocoding API
    private static let geocodingURL = "https://geocoding-api.open-meteo.com/v1/search"
    // Open-Meteo Weather API
    private static let weatherURL = "https://api.open-meteo.com/v1/forecast"

    /// Fetch real weather data for a location
    static func fetchWeather(for location: String) async throws -> [String: RAToolValue] {
        // Step 1: Geocode the location to get coordinates
        guard let coordinates = try await geocodeLocation(location) else {
            return [
                "error": RAToolValue("Could not find location: \(location)"),
                "location": RAToolValue(location)
            ]
        }

        // Step 2: Fetch weather for coordinates
        return try await fetchWeatherForCoordinates(
            latitude: coordinates.latitude,
            longitude: coordinates.longitude,
            locationName: coordinates.name
        )
    }

    /// Resolved geocoding coordinates plus the canonical place name.
    struct GeocodedLocation {
        let latitude: Double
        let longitude: Double
        let name: String
    }

    private static func geocodeLocation(_ location: String) async throws -> GeocodedLocation? {
        guard let encodedLocation = location.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(geocodingURL)?name=\(encodedLocation)&count=1&language=en&format=json") else {
            return nil
        }

        // SAMPLE_HTTP_CARVE_OUT: external weather-tool demo call, not SDK auth/download traffic.
        let (data, _) = try await URLSession.shared.data(from: url)

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]],
              let first = results.first,
              let latitude = first["latitude"] as? Double,
              let longitude = first["longitude"] as? Double else {
            return nil
        }

        let name = first["name"] as? String ?? location
        return GeocodedLocation(latitude: latitude, longitude: longitude, name: name)
    }

    private static func fetchWeatherForCoordinates(
        latitude: Double,
        longitude: Double,
        locationName: String
    ) async throws -> [String: RAToolValue] {
        let urlString = "\(weatherURL)?latitude=\(latitude)&longitude=\(longitude)" +
            "&current=temperature_2m,relative_humidity_2m,weather_code,wind_speed_10m" +
            "&temperature_unit=fahrenheit&wind_speed_unit=mph"

        guard let url = URL(string: urlString) else {
            return ["error": RAToolValue("Invalid weather API URL")]
        }

        // SAMPLE_HTTP_CARVE_OUT: external weather-tool demo call, not SDK auth/download traffic.
        let (data, _) = try await URLSession.shared.data(from: url)

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let current = json["current"] as? [String: Any] else {
            return ["error": RAToolValue("Could not parse weather data")]
        }

        let temperature = current["temperature_2m"] as? Double ?? 0
        let humidity = current["relative_humidity_2m"] as? Double ?? 0
        let windSpeed = current["wind_speed_10m"] as? Double ?? 0
        let weatherCode = current["weather_code"] as? Int ?? 0

        return [
            "location": RAToolValue(locationName),
            "temperature": RAToolValue(temperature),
            "unit": RAToolValue("fahrenheit"),
            "humidity": RAToolValue(humidity),
            "wind_speed_mph": RAToolValue(windSpeed),
            "condition": RAToolValue(weatherCodeToCondition(weatherCode))
        ]
    }

    // Convert WMO weather code to human-readable condition.
    // swiftlint:disable:next cyclomatic_complexity
    private static func weatherCodeToCondition(_ code: Int) -> String {
        switch code {
        case 0: return "Clear sky"
        case 1: return "Mainly clear"
        case 2: return "Partly cloudy"
        case 3: return "Overcast"
        case 45, 48: return "Foggy"
        case 51, 53, 55: return "Drizzle"
        case 56, 57: return "Freezing drizzle"
        case 61, 63, 65: return "Rain"
        case 66, 67: return "Freezing rain"
        case 71, 73, 75: return "Snow"
        case 77: return "Snow grains"
        case 80, 81, 82: return "Rain showers"
        case 85, 86: return "Snow showers"
        case 95: return "Thunderstorm"
        case 96, 99: return "Thunderstorm with hail"
        default: return "Unknown"
        }
    }
}

// MARK: - Safe Math Evaluator
//
// Deterministic recursive-descent parser for simple arithmetic expressions.
// Replaces NSExpression(format:) which can raise uncaught Objective-C
// exceptions (e.g. for "1 2", "(1+2", "1++2") that Swift's do-catch cannot
// intercept. Supports the grammar:
//   expr    := term (("+" | "-") term)*
//   term    := factor (("*" | "/") factor)*
//   factor  := ("+" | "-") factor | primary
//   primary := number | "(" expr ")"
enum SafeMathEvaluator {
    static func evaluate(_ expression: String) -> Double? {
        var parser = Parser(input: expression)
        guard let value = parser.parseExpression() else { return nil }
        guard parser.isAtEnd else { return nil }
        guard value.isFinite else { return nil }
        return value
    }

    private struct Parser {
        let scalars: [Character]
        var index: Int = 0

        init(input: String) {
            self.scalars = Array(input)
        }

        var isAtEnd: Bool {
            mutating get {
                skipWhitespace()
                return index >= scalars.count
            }
        }

        mutating func skipWhitespace() {
            while index < scalars.count, scalars[index].isWhitespace {
                index += 1
            }
        }

        mutating func peek() -> Character? {
            skipWhitespace()
            return index < scalars.count ? scalars[index] : nil
        }

        mutating func advance() -> Character? {
            skipWhitespace()
            guard index < scalars.count else { return nil }
            let char = scalars[index]
            index += 1
            return char
        }

        mutating func match(_ char: Character) -> Bool {
            if peek() == char {
                _ = advance()
                return true
            }
            return false
        }

        mutating func parseExpression() -> Double? {
            guard var value = parseTerm() else { return nil }
            while let op = peek(), op == "+" || op == "-" {
                _ = advance()
                guard let rhs = parseTerm() else { return nil }
                value = op == "+" ? value + rhs : value - rhs
            }
            return value
        }

        mutating func parseTerm() -> Double? {
            guard var value = parseFactor() else { return nil }
            while let op = peek(), op == "*" || op == "/" {
                _ = advance()
                guard let rhs = parseFactor() else { return nil }
                if op == "/" {
                    guard rhs != 0 else { return nil }
                    value /= rhs
                } else {
                    value *= rhs
                }
            }
            return value
        }

        mutating func parseFactor() -> Double? {
            if match("+") { return parseFactor() }
            if match("-") {
                guard let value = parseFactor() else { return nil }
                return -value
            }
            return parsePrimary()
        }

        mutating func parsePrimary() -> Double? {
            guard let next = peek() else { return nil }
            if next == "(" {
                _ = advance()
                guard let value = parseExpression() else { return nil }
                guard match(")") else { return nil }
                return value
            }
            return parseNumber()
        }

        mutating func parseNumber() -> Double? {
            skipWhitespace()
            let start = index
            var seenDot = false
            while index < scalars.count {
                let char = scalars[index]
                if char.isNumber {
                    index += 1
                } else if char == "." && !seenDot {
                    seenDot = true
                    index += 1
                } else {
                    break
                }
            }
            guard index > start else { return nil }
            return Double(String(scalars[start..<index]))
        }
    }
}

#Preview {
    NavigationStack {
        Form {
            ToolSettingsSection(viewModel: ToolSettingsViewModel.shared)
        }
    }
}
