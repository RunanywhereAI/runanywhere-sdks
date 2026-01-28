//
//  ToolSettingsView.swift
//  RunAnywhereAI
//
//  Tool registration and management settings
//

import SwiftUI
import RunAnywhere

// MARK: - Tool Settings View Model

@MainActor
class ToolSettingsViewModel: ObservableObject {
    static let shared = ToolSettingsViewModel()

    @Published var registeredTools: [ToolDefinition] = []
    @Published var toolCallingEnabled: Bool = false {
        didSet {
            UserDefaults.standard.set(toolCallingEnabled, forKey: "toolCallingEnabled")
        }
    }

    // Built-in demo tools with REAL API implementations
    private var demoTools: [(definition: ToolDefinition, executor: ToolExecutor)] {
        [
            // Weather Tool - Uses Open-Meteo API (free, no API key required)
            (
                definition: ToolDefinition(
                    name: "get_weather",
                    description: "Gets the current weather for a given location using Open-Meteo API",
                    parameters: [
                        ToolParameter(
                            name: "location",
                            type: .string,
                            description: "City name (e.g., 'San Francisco', 'London', 'Tokyo')"
                        )
                    ],
                    category: "Utility"
                ),
                executor: { args in
                    try await WeatherService.fetchWeather(for: args["location"]?.stringValue ?? "San Francisco")
                }
            ),
            // Time Tool - Real system time with timezone
            (
                definition: ToolDefinition(
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
                        "datetime": .string(dateFormatter.string(from: now)),
                        "time": .string(timeFormatter.string(from: now)),
                        "timestamp": .string(ISO8601DateFormatter().string(from: now)),
                        "timezone": .string(timeZone.identifier),
                        "utc_offset": .string(timeZone.abbreviation() ?? "UTC")
                    ]
                }
            ),
            // Calculator Tool - Real math evaluation
            (
                definition: ToolDefinition(
                    name: "calculate",
                    description: "Performs math calculations. Supports +, -, *, /, and parentheses",
                    parameters: [
                        ToolParameter(
                            name: "expression",
                            type: .string,
                            description: "Math expression (e.g., '2 + 2 * 3', '(10 + 5) / 3')"
                        )
                    ],
                    category: "Utility"
                ),
                executor: { args in
                    let expression = args["expression"]?.stringValue ?? args["input"]?.stringValue ?? "0"
                    // Clean the expression - remove any non-math characters
                    let cleanedExpression = expression
                        .replacingOccurrences(of: "=", with: "")
                        .replacingOccurrences(of: "x", with: "*")
                        .replacingOccurrences(of: "×", with: "*")
                        .replacingOccurrences(of: "÷", with: "/")
                        .trimmingCharacters(in: .whitespacesAndNewlines)

                    do {
                        let exp = NSExpression(format: cleanedExpression)
                        if let result = exp.expressionValue(with: nil, context: nil) as? NSNumber {
                            return [
                                "result": .number(result.doubleValue),
                                "expression": .string(expression)
                            ]
                        }
                    } catch {
                        // Fall through to error
                    }
                    return [
                        "error": .string("Could not evaluate expression: \(expression)"),
                        "expression": .string(expression)
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
                }
            }
        } header: {
            Text("Tool Calling")
        } footer: {
            Text("Allow the LLM to use registered tools to perform actions like getting weather, time, or calculations.")
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

                Text("Allow the LLM to use registered tools to perform actions like getting weather, time, or calculations.")
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
    let tool: ToolDefinition

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: "wrench.and.screwdriver")
                    .font(.system(size: 12))
                    .foregroundColor(AppColors.primaryAccent)
                Text(tool.name)
                    .font(AppTypography.subheadlineMedium)
            }
            Text(tool.description)
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

// MARK: - Weather Service (Open-Meteo API)

/// Real weather service using Open-Meteo API (free, no API key required)
enum WeatherService {
    // Open-Meteo Geocoding API
    private static let geocodingURL = "https://geocoding-api.open-meteo.com/v1/search"
    // Open-Meteo Weather API
    private static let weatherURL = "https://api.open-meteo.com/v1/forecast"

    /// Fetch real weather data for a location
    static func fetchWeather(for location: String) async throws -> [String: ToolValue] {
        // Step 1: Geocode the location to get coordinates
        guard let coordinates = try await geocodeLocation(location) else {
            return [
                "error": .string("Could not find location: \(location)"),
                "location": .string(location)
            ]
        }

        // Step 2: Fetch weather for coordinates
        return try await fetchWeatherForCoordinates(
            latitude: coordinates.latitude,
            longitude: coordinates.longitude,
            locationName: coordinates.name
        )
    }

    private static func geocodeLocation(_ location: String) async throws -> (latitude: Double, longitude: Double, name: String)? {
        guard let encodedLocation = location.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "\(geocodingURL)?name=\(encodedLocation)&count=1&language=en&format=json") else {
            return nil
        }

        let (data, _) = try await URLSession.shared.data(from: url)

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let results = json["results"] as? [[String: Any]],
              let first = results.first,
              let latitude = first["latitude"] as? Double,
              let longitude = first["longitude"] as? Double else {
            return nil
        }

        let name = first["name"] as? String ?? location
        return (latitude, longitude, name)
    }

    private static func fetchWeatherForCoordinates(
        latitude: Double,
        longitude: Double,
        locationName: String
    ) async throws -> [String: ToolValue] {
        let urlString = "\(weatherURL)?latitude=\(latitude)&longitude=\(longitude)" +
            "&current=temperature_2m,relative_humidity_2m,weather_code,wind_speed_10m" +
            "&temperature_unit=fahrenheit&wind_speed_unit=mph"

        guard let url = URL(string: urlString) else {
            return ["error": .string("Invalid weather API URL")]
        }

        let (data, _) = try await URLSession.shared.data(from: url)

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let current = json["current"] as? [String: Any] else {
            return ["error": .string("Could not parse weather data")]
        }

        let temperature = current["temperature_2m"] as? Double ?? 0
        let humidity = current["relative_humidity_2m"] as? Double ?? 0
        let windSpeed = current["wind_speed_10m"] as? Double ?? 0
        let weatherCode = current["weather_code"] as? Int ?? 0

        return [
            "location": .string(locationName),
            "temperature": .number(temperature),
            "unit": .string("fahrenheit"),
            "humidity": .number(humidity),
            "wind_speed_mph": .number(windSpeed),
            "condition": .string(weatherCodeToCondition(weatherCode))
        ]
    }

    /// Convert WMO weather code to human-readable condition
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

#Preview {
    NavigationStack {
        Form {
            ToolSettingsSection(viewModel: ToolSettingsViewModel.shared)
        }
    }
}
