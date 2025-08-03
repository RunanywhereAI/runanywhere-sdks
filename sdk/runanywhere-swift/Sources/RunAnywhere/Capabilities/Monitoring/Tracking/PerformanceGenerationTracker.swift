//
//  PerformanceGenerationTracker.swift
//  RunAnywhere SDK
//
//  Tracks performance during generation
//

import Foundation

/// Generation tracking information for performance monitoring
internal struct PerformanceGenerationTracking {
    let id: UUID
    let framework: LLMFramework
    let modelName: String
    let startTime: CFAbsoluteTime
    let startMemory: Int64
    var firstTokenTime: CFAbsoluteTime?
    var tokenCount: Int = 0
    var tokensGenerated: [String] = []
}

/// Tracks generation performance
internal class PerformanceGenerationTracker {
    private let logger = SDKLogger(category: "GenerationTracker")
    private var activeGeneration: PerformanceGenerationTracking?

    /// Begin tracking a new generation
    func beginGeneration(
        framework: LLMFramework,
        modelInfo: ModelInfo,
        currentMemory: Int64
    ) -> UUID {
        let id = UUID()
        activeGeneration = PerformanceGenerationTracking(
            id: id,
            framework: framework,
            modelName: modelInfo.name,
            startTime: CFAbsoluteTimeGetCurrent(),
            startMemory: currentMemory
        )

        logger.debug("Started tracking generation for \(framework.rawValue) with model \(modelInfo.name)")
        return id
    }

    /// Record a generated token
    func recordToken(_ token: String, currentTime: CFAbsoluteTime) -> (firstTokenTime: CFAbsoluteTime?, tokensPerSecond: Double) {
        guard var generation = activeGeneration else {
            return (nil, 0)
        }

        // Record first token time if not set
        if generation.firstTokenTime == nil {
            generation.firstTokenTime = currentTime
        }

        // Update token count and list
        generation.tokenCount += 1
        generation.tokensGenerated.append(token)
        activeGeneration = generation

        // Calculate tokens per second
        let elapsed = currentTime - generation.startTime
        let tokensPerSecond = elapsed > 0 ? Double(generation.tokenCount) / elapsed : 0

        return (generation.firstTokenTime, tokensPerSecond)
    }

    /// End tracking and return summary
    func endGeneration(currentMemory: Int64) -> GenerationSummary? {
        guard let generation = activeGeneration else {
            logger.warning("Attempted to end generation tracking with no active generation")
            return nil
        }

        let endTime = CFAbsoluteTimeGetCurrent()
        let totalTime = endTime - generation.startTime
        let timeToFirstToken = generation.firstTokenTime.map { $0 - generation.startTime } ?? 0

        let summary = GenerationSummary(
            id: generation.id,
            framework: generation.framework,
            modelName: generation.modelName,
            totalTime: totalTime,
            timeToFirstToken: timeToFirstToken,
            tokenCount: generation.tokenCount,
            tokensPerSecond: totalTime > 0 ? Double(generation.tokenCount) / totalTime : 0,
            memoryUsed: currentMemory - generation.startMemory
        )

        // Clear active generation
        activeGeneration = nil

        return summary
    }

    /// Get current generation info
    var currentGeneration: PerformanceGenerationTracking? {
        return activeGeneration
    }
}
