//
//  LocalLLMService.swift
//  RunAnywhereAI
//

import Foundation
import RunAnywhereSDK
import os

class LocalLLMService {
    private let sdk = RunAnywhereSDK.shared
    private let logger = Logger(subsystem: "com.runanywhere.RunAnywhereAI", category: "LocalLLMService")

    func generateTasks(from objective: String, prompt: String) async throws -> ([AgentTask], String) {
        guard sdk.isInitialized else {
            throw AgentError.llmGenerationFailed("SDK not initialized")
        }

        do {
            let effectiveSettings = await sdk.getGenerationSettings()
            let options = RunAnywhereGenerationOptions(
                maxTokens: min(1000, effectiveSettings.maxTokens),
                temperature: Float(0.7),
                topP: Float(0.9)
            )

            let result = try await sdk.generate(prompt: prompt, options: options)
            let tasks = parseTasksFromJSON(result.text)
            return (tasks, result.text)
        } catch {
            logger.error("Task generation failed: \(error)")
            throw AgentError.llmGenerationFailed(error.localizedDescription)
        }
    }

    func executeTaskWithLLM(_ task: AgentTask) async throws -> String {
        guard sdk.isInitialized else {
            throw AgentError.taskExecutionFailed("SDK not initialized")
        }

        let prompt = PromptTemplates.executeTask(task: task)

        do {
            let effectiveSettings = await sdk.getGenerationSettings()
            let options = RunAnywhereGenerationOptions(
                maxTokens: min(500, effectiveSettings.maxTokens),
                temperature: Float(0.8),
                topP: Float(0.95)
            )

            let result = try await sdk.generate(prompt: prompt, options: options)
            return result.text
        } catch {
            logger.error("Task execution failed: \(error)")
            throw AgentError.taskExecutionFailed(error.localizedDescription)
        }
    }

    private func parseTasksFromJSON(_ jsonString: String) -> [AgentTask] {
        let cleanedJSON = extractJSON(from: jsonString)

        guard let data = cleanedJSON.data(using: .utf8) else {
            return createDefaultTasks()
        }

        do {
            let taskDTOs = try JSONDecoder().decode([TaskDTO].self, from: data)
            let tasks = taskDTOs.compactMap { dto -> AgentTask? in
                // Validate task has meaningful content
                guard isValidTaskData(name: dto.name, description: dto.description) else {
                    return nil
                }

                return AgentTask(
                    name: dto.name.trimmingCharacters(in: .whitespacesAndNewlines),
                    description: dto.description.trimmingCharacters(in: .whitespacesAndNewlines),
                    priority: parsePriority(dto.priority),
                    status: .pending
                )
            }
            return tasks.isEmpty ? createDefaultTasks() : tasks
        } catch {
            logger.error("JSON parsing failed: \(error)")
            return parseTasksWithRegex(jsonString)
        }
    }

    private func extractJSON(from text: String) -> String {
        if let startIndex = text.firstIndex(of: "["),
           let endIndex = text.lastIndex(of: "]") {
            return String(text[startIndex...endIndex])
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func parseTasksWithRegex(_ text: String) -> [AgentTask] {
        var tasks: [AgentTask] = []
        let lines = text.components(separatedBy: .newlines)
        var currentName = ""
        var currentDescription = ""

        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

            if trimmed.range(of: "^\\d+\\.|^[-•]", options: .regularExpression) != nil {
                if !currentName.isEmpty && isValidTaskData(name: currentName, description: currentDescription) {
                    tasks.append(AgentTask(
                        name: currentName,
                        description: createDistinctDescription(name: currentName, description: currentDescription),
                        priority: .medium,
                        status: .pending
                    ))
                }

                let cleanLine = trimmed
                    .replacingOccurrences(of: #"^\d+\.\s*"#, with: "", options: .regularExpression)
                    .replacingOccurrences(of: #"^[-•]\s*"#, with: "", options: .regularExpression)

                currentName = String(cleanLine.prefix(50)).trimmingCharacters(in: .whitespacesAndNewlines)
                currentDescription = cleanLine.trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }

        if !currentName.isEmpty && isValidTaskData(name: currentName, description: currentDescription) {
            tasks.append(AgentTask(
                name: currentName,
                description: createDistinctDescription(name: currentName, description: currentDescription),
                priority: .medium,
                status: .pending
            ))
        }

        return tasks.isEmpty ? createDefaultTasks() : tasks
    }

    private func isValidTaskData(name: String, description: String) -> Bool {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)

        // Filter out empty, placeholder, or invalid tasks
        guard !trimmedName.isEmpty,
              trimmedName != "--",
              trimmedName.count > 2 else {
            return false
        }

        return true
    }

    private func createDistinctDescription(name: String, description: String) -> String {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedDescription = description.trimmingCharacters(in: .whitespacesAndNewlines)

        // If description is empty or same as name, create a distinct description
        if trimmedDescription.isEmpty || trimmedDescription == trimmedName {
            return "Complete: \(trimmedName)"
        }

        return trimmedDescription
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
                name: "Analyze Objective",
                description: "Break down and understand the requirements of the given objective",
                priority: .high,
                status: .pending
            ),
            AgentTask(
                name: "Create Action Plan",
                description: "Develop a structured approach with prioritized steps",
                priority: .high,
                status: .pending
            ),
            AgentTask(
                name: "Execute Tasks",
                description: "Carry out the planned actions to achieve the objective",
                priority: .medium,
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
}

enum AgentError: LocalizedError {
    case llmGenerationFailed(String)
    case taskExecutionFailed(String)

    var errorDescription: String? {
        switch self {
        case .llmGenerationFailed(let message):
            return "Failed to generate tasks: \(message)"
        case .taskExecutionFailed(let message):
            return "Failed to execute task: \(message)"
        }
    }
}
