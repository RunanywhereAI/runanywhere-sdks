//
//  BabyAGI.swift
//  RunAnywhereAI
//
//  Created for BabyAGI Demo
//  Fully local autonomous agent implementation
//

import Foundation
import SwiftUI
import RunAnywhereSDK
import os

@MainActor
class BabyAGI: ObservableObject {
    @Published var tasks: [AgentTask] = []
    @Published var executionLog: [ExecutionLogEntry] = []
    @Published var isProcessing = false
    @Published var currentObjective = ""
    @Published var currentStatus = "Ready"
    @Published var error: String?

    private let llmService: LocalLLMService
    private let taskQueue = TaskQueue()
    private let logger = Logger(subsystem: "com.runanywhere.RunAnywhereAI", category: "BabyAGI")

    init() {
        self.llmService = LocalLLMService()
    }

    func processObjective(_ objective: String) async {
        guard !objective.isEmpty else { return }

        await MainActor.run {
            self.isProcessing = true
            self.currentObjective = objective
            self.currentStatus = "Initializing BabyAGI..."
            self.tasks = []
            self.executionLog = []
            self.error = nil
            self.addLog("🎯 New objective: \(objective)", type: .info)
        }

        // Check if a model is loaded (like ChatViewModel does)
        guard ModelListViewModel.shared.currentModel != nil else {
            await MainActor.run {
                self.error = "No model loaded. Please select and load a model from the Settings tab first."
                self.currentStatus = "No model loaded"
                self.isProcessing = false
                self.addLog("❌ No model loaded. Please go to Settings > Models to load one.", type: .error)
            }
            return
        }

        await MainActor.run {
            self.addLog("✅ Model loaded: \(ModelListViewModel.shared.currentModel?.name ?? "Unknown")", type: .success)
        }

        // Step 1: Break down the objective into tasks
        await MainActor.run {
            self.currentStatus = "Generating tasks..."
        }
        let generatedTasks = await breakDownObjective(objective)

        await MainActor.run {
            self.tasks = generatedTasks
            self.addLog("📝 Generated \(generatedTasks.count) tasks", type: .success)
        }

        // Step 2: Prioritize and order tasks
        await MainActor.run {
            self.currentStatus = "Prioritizing tasks..."
        }
        let prioritizedTasks = await prioritizeTasks(generatedTasks)

        await MainActor.run {
            self.tasks = prioritizedTasks
            self.addLog("🔄 Tasks prioritized by importance", type: .info)
        }

        // Step 3: Execute each task (simulation for demo)
        for (index, task) in prioritizedTasks.enumerated() {
            await MainActor.run {
                self.currentStatus = "Executing task \(index + 1) of \(prioritizedTasks.count)..."
                if let taskIndex = self.tasks.firstIndex(where: { $0.id == task.id }) {
                    self.tasks[taskIndex].status = .inProgress
                }
            }

            let result = await executeTask(task)

            await MainActor.run {
                if let taskIndex = self.tasks.firstIndex(where: { $0.id == task.id }) {
                    self.tasks[taskIndex].status = .completed
                    self.tasks[taskIndex].result = result
                }
                self.addLog("✅ Completed: \(task.name)", type: .success)
            }

            // Small delay for demo visibility
            try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
        }

        await MainActor.run {
            self.isProcessing = false
            self.currentStatus = "All tasks completed!"
            self.addLog("🎉 Objective completed successfully!", type: .success)
        }
    }

    private func breakDownObjective(_ objective: String) async -> [AgentTask] {
        let prompt = PromptTemplates.taskBreakdown(objective: objective)

        do {
            let response = try await llmService.generateTasks(from: objective, prompt: prompt)
            return response
        } catch {
            await MainActor.run {
                self.addLog("⚠️ Error generating tasks: \(error.localizedDescription)", type: .error)
            self.error = "Failed to generate tasks. Please check your model is loaded."
            }
            return createFallbackTasks(for: objective)
        }
    }

    private func prioritizeTasks(_ tasks: [AgentTask]) async -> [AgentTask] {
        // Simple priority-based sorting for MVP
        // In future, can use LLM to determine dependencies
        return tasks.sorted { task1, task2 in
            task1.priority.rawValue > task2.priority.rawValue
        }
    }

    private func executeTask(_ task: AgentTask) async -> String {
        // Simulate task execution with LLM
        do {
            let result = try await llmService.executeTaskWithLLM(task)
            return result
        } catch {
            return "Task completed (simulated)"
        }
    }

    private func createFallbackTasks(for objective: String) -> [AgentTask] {
        // Fallback tasks if LLM fails
        return [
            AgentTask(
                name: "Research",
                description: "Gather information about: \(objective)",
                priority: .high,
                status: .pending
            ),
            AgentTask(
                name: "Plan",
                description: "Create a detailed plan",
                priority: .high,
                status: .pending
            ),
            AgentTask(
                name: "Execute",
                description: "Implement the plan",
                priority: .medium,
                status: .pending
            ),
            AgentTask(
                name: "Review",
                description: "Review and refine results",
                priority: .low,
                status: .pending
            )
        ]
    }

    private func addLog(_ message: String, type: LogType) {
        let entry = ExecutionLogEntry(
            timestamp: Date(),
            message: message,
            type: type
        )
        executionLog.append(entry)
    }
}

// MARK: - Supporting Types

struct AgentTask: Identifiable, Equatable {
    let id = UUID()
    var name: String
    var description: String
    var priority: TaskPriority
    var status: TaskStatus
    var subtasks: [AgentTask] = []
    var result: String?
    var dependencies: [UUID] = []
    var estimatedTime: String?

    init(name: String, description: String, priority: TaskPriority, status: TaskStatus = .pending) {
        self.name = name
        self.description = description
        self.priority = priority
        self.status = status
    }

    static func == (lhs: AgentTask, rhs: AgentTask) -> Bool {
        lhs.id == rhs.id
    }
}

enum TaskPriority: Int, Codable {
    case critical = 4
    case high = 3
    case medium = 2
    case low = 1

    var color: Color {
        switch self {
        case .critical: return .red
        case .high: return .orange
        case .medium: return .yellow
        case .low: return .green
        }
    }

    var label: String {
        switch self {
        case .critical: return "Critical"
        case .high: return "High"
        case .medium: return "Medium"
        case .low: return "Low"
        }
    }
}

enum TaskStatus: Codable {
    case pending
    case inProgress
    case completed
    case failed

    var icon: String {
        switch self {
        case .pending: return "circle"
        case .inProgress: return "arrow.clockwise.circle.fill"
        case .completed: return "checkmark.circle.fill"
        case .failed: return "xmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .pending: return .gray
        case .inProgress: return .blue
        case .completed: return .green
        case .failed: return .red
        }
    }
}

struct ExecutionLogEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let message: String
    let type: LogType
}

enum LogType {
    case info
    case success
    case warning
    case error

    var color: Color {
        switch self {
        case .info: return .blue
        case .success: return .green
        case .warning: return .orange
        case .error: return .red
        }
    }
}

// MARK: - Task Queue

class TaskQueue {
    private var queue: [AgentTask] = []
    private let lock = NSLock()

    func add(_ tasks: [AgentTask]) {
        lock.withLock {
            queue.append(contentsOf: tasks)
        }
    }

    func next() -> AgentTask? {
        lock.withLock {
            guard !queue.isEmpty else { return nil }
            return queue.removeFirst()
        }
    }

    var isEmpty: Bool {
        lock.withLock {
            return queue.isEmpty
        }
    }

    func clear() {
        lock.withLock {
            queue.removeAll()
        }
    }
}

// MARK: - Prompt Templates

struct PromptTemplates {
    static func taskBreakdown(objective: String) -> String {
        return """
        You are an AI task planner. Break down this objective into specific, actionable tasks.

        Objective: \(objective)

        Return a JSON array of tasks with this EXACT structure:
        [
            {
                "name": "Short task name",
                "description": "Detailed description of what needs to be done",
                "priority": "critical/high/medium/low",
                "estimatedTime": "time estimate (e.g., '10 minutes', '1 hour')"
            }
        ]

        Requirements:
        - Be specific and practical
        - Create 4-7 main tasks maximum
        - Tasks should be actionable and measurable
        - Order tasks logically
        - Keep names concise (3-5 words)
        - Make descriptions clear and detailed

        Return ONLY the JSON array, no other text.
        """
    }

    static func executeTask(task: AgentTask) -> String {
        return """
        You are executing this task: \(task.name)
        Description: \(task.description)

        Provide a brief, actionable result or recommendation for this task.
        Be specific and practical. Limit response to 2-3 sentences.
        """
    }

    static func prioritizeTasks(tasks: String) -> String {
        return """
        Given these tasks, analyze their dependencies and suggest the optimal execution order:

        Tasks: \(tasks)

        Consider:
        - Logical dependencies
        - Time efficiency
        - Resource requirements

        Return the reordered task list.
        """
    }
}
