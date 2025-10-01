//
//  BabyAGI.swift
//  RunAnywhereAI
//

import Foundation
import SwiftUI
import RunAnywhereSDK
import os

@MainActor
class BabyAGI: ObservableObject {
    @Published var tasks: [AgentTask] = []
    @Published var isProcessing = false
    @Published var currentObjective = ""
    @Published var currentStatus = "Ready"
    @Published var error: String?
    @Published var currentPhase: AgentPhase = .idle
    @Published var executionStartTime: Date?
    @Published var executionEndTime: Date?
    @Published var taskBreakdownResponse: String?
    @Published var updateTrigger: Int = 0

    private let llmService: LocalLLMService
    private let logger = Logger(subsystem: "com.runanywhere.RunAnywhereAI", category: "BabyAGI")

    init() {
        self.llmService = LocalLLMService()
    }

    func processObjective(_ objective: String) async {
        guard !objective.isEmpty else { return }

        executionStartTime = Date()
        executionEndTime = nil
        isProcessing = true
        currentObjective = objective
        tasks = []
        error = nil
        taskBreakdownResponse = nil

        guard ModelListViewModel.shared.currentModel != nil else {
            error = "No model loaded. Load a model from Settings."
            currentStatus = "No model loaded"
            currentPhase = .idle
            isProcessing = false
            return
        }

        // Phase 1: Analyze objective
        currentPhase = .analyzing
        currentStatus = "🧠 Analyzing objective..."
        try? await Task.sleep(nanoseconds: 500_000_000)

        // Phase 2: Generate tasks
        currentPhase = .generating
        currentStatus = "⚙️ Breaking down into tasks..."
        let (generatedTasks, breakdownText) = await generateTasks(objective)
        tasks = generatedTasks
        taskBreakdownResponse = breakdownText

        guard !tasks.isEmpty else {
            error = "Failed to generate tasks"
            currentStatus = "❌ Failed to generate tasks"
            currentPhase = .idle
            isProcessing = false
            executionEndTime = Date()
            return
        }

        currentStatus = "✅ Generated \(tasks.count) tasks"
        try? await Task.sleep(nanoseconds: 500_000_000)

        // Phase 3: Execute tasks (generate suggestions)
        currentPhase = .executing
        for index in tasks.indices {
            let taskNumber = index + 1
            let task = tasks[index]
            currentStatus = "💡 Generating suggestion \(taskNumber)/\(tasks.count): \(task.name)"

            logger.info("Starting task \(taskNumber): \(task.name)")

            // Update to in-progress
            var currentTask = task
            currentTask.status = .inProgress
            currentTask.startTime = Date()

            var newTasks = tasks
            newTasks[index] = currentTask
            tasks = newTasks
            updateTrigger += 1

            // Generate suggestion
            let result = await executeTask(task)

            logger.info("Got result for task \(taskNumber): '\(result)' (length: \(result.count) chars)")

            // Update with result
            currentTask.status = .completed
            currentTask.result = result
            currentTask.endTime = Date()

            newTasks = tasks
            newTasks[index] = currentTask
            tasks = newTasks
            updateTrigger += 1

            let elapsed = currentTask.executionTime
            logger.info("Task \(taskNumber) completed with result in \(elapsed, format: .fixed(precision: 1))s")

            if taskNumber < tasks.count {
                try? await Task.sleep(nanoseconds: 300_000_000)
            }
        }

        // Phase 4: Complete
        currentPhase = .completed
        executionEndTime = Date()
        let totalTime = executionEndTime!.timeIntervalSince(executionStartTime!)
        currentStatus = "✅ Generated \(tasks.count) suggestions in \(String(format: "%.1f", totalTime))s"
        isProcessing = false

        try? await Task.sleep(nanoseconds: 1_000_000_000)
        currentPhase = .idle
    }

    private func generateTasks(_ objective: String) async -> ([AgentTask], String?) {
        let prompt = PromptTemplates.taskBreakdown(objective: objective)

        do {
            let (generatedTasks, rawResponse) = try await llmService.generateTasks(from: objective, prompt: prompt)
            return (generatedTasks.sorted { $0.priority.rawValue > $1.priority.rawValue }, rawResponse)
        } catch {
            logger.error("Task generation failed: \(error.localizedDescription)")
            self.error = "Failed to generate tasks"
            return ([], nil)
        }
    }

    private func executeTask(_ task: AgentTask) async -> String {
        do {
            return try await llmService.executeTaskWithLLM(task)
        } catch {
            logger.error("Task execution failed: \(error.localizedDescription)")
            return "Failed to execute task"
        }
    }
}

// MARK: - Models

enum AgentPhase {
    case idle
    case analyzing
    case generating
    case executing
    case completed

    var description: String {
        switch self {
        case .idle: return "Ready"
        case .analyzing: return "Analyzing"
        case .generating: return "Planning"
        case .executing: return "Executing"
        case .completed: return "Complete"
        }
    }

    var icon: String {
        switch self {
        case .idle: return "brain"
        case .analyzing: return "magnifyingglass"
        case .generating: return "list.bullet.clipboard"
        case .executing: return "bolt.fill"
        case .completed: return "checkmark.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .idle: return .secondary
        case .analyzing: return .blue
        case .generating: return .orange
        case .executing: return .purple
        case .completed: return .green
        }
    }
}

struct AgentTask: Identifiable, Equatable {
    let id = UUID()
    var name: String
    var description: String
    var priority: TaskPriority
    var status: TaskStatus
    var result: String?
    var startTime: Date?
    var endTime: Date?

    init(name: String, description: String, priority: TaskPriority, status: TaskStatus = .pending) {
        self.name = name
        self.description = description
        self.priority = priority
        self.status = status
    }

    var executionTime: TimeInterval {
        guard let start = startTime, let end = endTime else { return 0 }
        return end.timeIntervalSince(start)
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

// MARK: - Prompts

struct PromptTemplates {
    static func taskBreakdown(objective: String) -> String {
        return """
        Break down this objective into specific, actionable tasks.

        Objective: \(objective)

        Return a JSON array with this structure:
        [
            {
                "name": "Task name",
                "description": "What needs to be done",
                "priority": "critical/high/medium/low",
                "estimatedTime": "time estimate"
            }
        ]

        Create 3-5 tasks. Be specific and practical. Return ONLY the JSON array.
        """
    }

    static func executeTask(task: AgentTask) -> String {
        return """
        For this task: \(task.name)
        Description: \(task.description)

        Provide a brief, actionable suggestion or recommendation on how to complete this task. 2-3 sentences maximum.
        """
    }
}
