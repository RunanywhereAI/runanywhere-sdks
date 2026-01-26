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

    // Built-in demo tools
    private let demoTools: [(definition: ToolDefinition, executor: ToolExecutor)] = [
        // Weather Tool
        (
            definition: ToolDefinition(
                name: "get_weather",
                description: "Gets the current weather for a given location",
                parameters: [
                    ToolParameter(name: "location", type: .string, description: "City name (e.g., 'San Francisco')")
                ],
                category: "Utility"
            ),
            executor: { args in
                let location = args["location"]?.stringValue ?? "Unknown"
                // Simulated weather data
                let temps = [68, 72, 75, 80, 65, 70]
                let conditions = ["Sunny", "Partly Cloudy", "Clear", "Overcast", "Foggy"]
                return [
                    "location": .string(location),
                    "temperature": .number(Double(temps.randomElement() ?? 72)),
                    "unit": .string("fahrenheit"),
                    "condition": .string(conditions.randomElement() ?? "Clear")
                ]
            }
        ),
        // Time Tool
        (
            definition: ToolDefinition(
                name: "get_current_time",
                description: "Gets the current date and time",
                parameters: [],
                category: "Utility"
            ),
            executor: { _ in
                let formatter = DateFormatter()
                formatter.dateStyle = .full
                formatter.timeStyle = .medium
                return [
                    "datetime": .string(formatter.string(from: Date())),
                    "timestamp": .string(ISO8601DateFormatter().string(from: Date()))
                ]
            }
        ),
        // Calculator Tool
        (
            definition: ToolDefinition(
                name: "calculate",
                description: "Performs basic math calculations",
                parameters: [
                    ToolParameter(name: "expression", type: .string, description: "Math expression (e.g., '2 + 2 * 3')")
                ],
                category: "Utility"
            ),
            executor: { args in
                let expression = args["expression"]?.stringValue ?? "0"
                // Simple evaluation using NSExpression
                let exp = NSExpression(format: expression)
                if let result = exp.expressionValue(with: nil, context: nil) as? NSNumber {
                    return [
                        "result": .number(result.doubleValue),
                        "expression": .string(expression)
                    ]
                }
                return [
                    "error": .string("Could not evaluate expression"),
                    "expression": .string(expression)
                ]
            }
        )
    ]

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

#Preview {
    NavigationStack {
        Form {
            ToolSettingsSection(viewModel: ToolSettingsViewModel.shared)
        }
    }
}
