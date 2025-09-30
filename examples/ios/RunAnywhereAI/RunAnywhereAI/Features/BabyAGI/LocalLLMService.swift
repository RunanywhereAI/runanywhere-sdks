//
//  LocalLLMService.swift
//  RunAnywhereAI
//
//  LLM integration for BabyAGI using local models
//

import Foundation
import RunAnywhereSDK
import os

class LocalLLMService {
    private let sdk = RunAnywhereSDK.shared
    private let logger = Logger(subsystem: "com.runanywhere.RunAnywhereAI", category: "LocalLLMService")

    init() {
        // Service will use whatever model is currently loaded in SDK
    }

    func generateTasks(from objective: String, prompt: String) async throws -> [AgentTask] {
        // Ensure SDK is initialized
        guard sdk.isInitialized else {
            logger.error("SDK not initialized")
            throw AgentError.llmGenerationFailed("SDK not initialized")
        }

        logger.info("Generating tasks for objective: \(objective.prefix(50))...")

        do {

            // Get effective settings from SDK (like ChatViewModel does)
            let effectiveSettings = await sdk.getGenerationSettings()

            // Create generation options with SDK defaults
            let options = RunAnywhereGenerationOptions(
                maxTokens: min(1000, effectiveSettings.maxTokens),
                temperature: Float(0.7),
                topP: Float(0.9)
            )

            // Use SDK's generate method with current loaded model
            let result = try await sdk.generate(
                prompt: prompt,
                options: options
            )

            // Parse JSON response from result text
            return parseTasksFromJSON(result.text)
        } catch {
            logger.error("Error generating tasks: \(error)")
            throw AgentError.llmGenerationFailed(error.localizedDescription)
        }
    }

    func executeTaskWithLLM(_ task: AgentTask) async throws -> String {
        // Ensure SDK is initialized
        guard sdk.isInitialized else {
            logger.error("SDK not initialized")
            throw AgentError.taskExecutionFailed("SDK not initialized")
        }

        logger.info("Executing task: \(task.name)")

        let prompt = PromptTemplates.executeTask(task: task)

        do {

            // Get effective settings from SDK
            let effectiveSettings = await sdk.getGenerationSettings()

            let options = RunAnywhereGenerationOptions(
                maxTokens: min(500, effectiveSettings.maxTokens),
                temperature: Float(0.8),
                topP: Float(0.95)
            )

            let result = try await sdk.generate(
                prompt: prompt,
                options: options
            )

            return result.text
        } catch {
            logger.error("Error executing task: \(error)")
            throw AgentError.taskExecutionFailed(error.localizedDescription)
        }
    }

    private func parseTasksFromJSON(_ jsonString: String) -> [AgentTask] {
        // Clean the response to get pure JSON
        let cleanedJSON = extractJSON(from: jsonString)

        guard let data = cleanedJSON.data(using: .utf8) else {
            print("Failed to convert to data")
            return createDefaultTasks()
        }

        do {
            let taskDTOs = try JSONDecoder().decode([TaskDTO].self, from: data)
            return taskDTOs.map { dto in
                AgentTask(
                    name: dto.name,
                    description: dto.description,
                    priority: parsePriority(dto.priority),
                    status: .pending
                )
            }
        } catch {
            print("JSON parsing error: \(error)")
            print("Attempted to parse: \(cleanedJSON)")
            // Fallback to regex parsing
            return parseTasksWithRegex(jsonString)
        }
    }

    private func extractJSON(from text: String) -> String {
        // Find JSON array in the response
        if let startIndex = text.firstIndex(of: "["),
           let endIndex = text.lastIndex(of: "]") {
            let jsonSubstring = text[startIndex...endIndex]
            return String(jsonSubstring)
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func parseTasksWithRegex(_ text: String) -> [AgentTask] {
        var tasks: [AgentTask] = []

        // Try to extract tasks using patterns
        let lines = text.components(separatedBy: .newlines)
        var currentName = ""
        var currentDescription = ""

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

            // Look for numbered items or bullet points
            if trimmed.hasPrefix("1.") || trimmed.hasPrefix("2.") ||
               trimmed.hasPrefix("3.") || trimmed.hasPrefix("4.") ||
               trimmed.hasPrefix("-") || trimmed.hasPrefix("•") {

                if !currentName.isEmpty {
                    tasks.append(AgentTask(
                        name: currentName,
                        description: currentDescription.isEmpty ? currentName : currentDescription,
                        priority: .medium,
                        status: .pending
                    ))
                }

                // Extract task name
                let cleanLine = trimmed
                    .replacingOccurrences(of: #"^\d+\.\s*"#, with: "", options: .regularExpression)
                    .replacingOccurrences(of: #"^[-•]\s*"#, with: "", options: .regularExpression)

                currentName = String(cleanLine.prefix(50))
                currentDescription = cleanLine
            }
        }

        // Add last task if exists
        if !currentName.isEmpty {
            tasks.append(AgentTask(
                name: currentName,
                description: currentDescription.isEmpty ? currentName : currentDescription,
                priority: .medium,
                status: .pending
            ))
        }

        return tasks.isEmpty ? createDefaultTasks() : tasks
    }

    private func parsePriority(_ priorityString: String) -> TaskPriority {
        switch priorityString.lowercased() {
        case "critical": return .critical
        case "high": return .high
        case "medium": return .medium
        case "low": return .low
        default: return .medium
        }
    }

    private func createDefaultTasks() -> [AgentTask] {
        return [
            AgentTask(
                name: "Initialize",
                description: "Set up the initial context and requirements",
                priority: .high,
                status: .pending
            ),
            AgentTask(
                name: "Plan",
                description: "Create a detailed action plan",
                priority: .high,
                status: .pending
            ),
            AgentTask(
                name: "Execute",
                description: "Carry out the planned actions",
                priority: .medium,
                status: .pending
            ),
            AgentTask(
                name: "Validate",
                description: "Verify the results meet the objective",
                priority: .low,
                status: .pending
            )
        ]
    }
}

// MARK: - Supporting Types

struct TaskDTO: Codable {
    let name: String
    let description: String
    let priority: String
    let estimatedTime: String?

    enum CodingKeys: String, CodingKey {
        case name
        case description
        case priority
        case estimatedTime
    }
}

enum AgentError: LocalizedError {
    case llmGenerationFailed(String)
    case taskExecutionFailed(String)
    case parsingFailed(String)

    var errorDescription: String? {
        switch self {
        case .llmGenerationFailed(let message):
            return "Failed to generate tasks: \(message)"
        case .taskExecutionFailed(let message):
            return "Failed to execute task: \(message)"
        case .parsingFailed(let message):
            return "Failed to parse response: \(message)"
        }
    }
}
