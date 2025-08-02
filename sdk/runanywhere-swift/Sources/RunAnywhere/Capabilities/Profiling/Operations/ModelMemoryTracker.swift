//
//  ModelMemoryTracker.swift
//  RunAnywhere SDK
//
//  Tracks memory usage during model loading
//

import Foundation

/// Tracks memory usage specifically for model loading operations
class ModelMemoryTracker {
    private let logger = SDKLogger(category: "ModelMemoryTracker")
    private var activeTracking: [String: ModelMemoryTracking] = [:]
    private let queue = DispatchQueue(label: "com.runanywhere.sdk.modeltracker", attributes: .concurrent)

    /// Begin tracking model loading
    func beginModelTracking(
        framework: LLMFramework,
        modelName: String,
        expectedSize: Int64
    ) -> String {
        let trackingId = UUID().uuidString
        let tracking = ModelMemoryTracking(
            framework: framework,
            modelName: modelName,
            expectedSize: expectedSize,
            startMemory: SystemMetrics.getCurrentMemoryUsage(),
            startTime: Date()
        )

        queue.async(flags: .barrier) { [weak self] in
            self?.activeTracking[trackingId] = tracking
        }

        logger.info("Started tracking \(framework) model: \(modelName), expected size: \(ByteCountFormatter.string(fromByteCount: expectedSize, countStyle: .memory))")

        return trackingId
    }

    /// End tracking and generate profile
    func endModelTracking(trackingId: String) -> ModelMemoryProfile? {
        guard let tracking = queue.sync(execute: { activeTracking[trackingId] }) else {
            logger.warning("No active tracking found for ID: \(trackingId)")
            return nil
        }

        let endMemory = SystemMetrics.getCurrentMemoryUsage()
        let actualMemoryUsed = endMemory - tracking.startMemory
        let memoryOverhead = actualMemoryUsed - tracking.expectedSize
        let loadTime = Date().timeIntervalSince(tracking.startTime)
        let compressionRatio = tracking.expectedSize > 0 ? Double(tracking.expectedSize) / Double(actualMemoryUsed) : 1.0

        let profile = ModelMemoryProfile(
            framework: tracking.framework,
            modelName: tracking.modelName,
            expectedSize: tracking.expectedSize,
            actualMemoryUsed: actualMemoryUsed,
            memoryOverhead: memoryOverhead,
            loadTime: loadTime,
            compressionRatio: compressionRatio
        )

        queue.async(flags: .barrier) { [weak self] in
            self?.activeTracking.removeValue(forKey: trackingId)
        }

        logger.info("""
            Model loading complete:
            - Framework: \(tracking.framework)
            - Model: \(tracking.modelName)
            - Expected: \(ByteCountFormatter.string(fromByteCount: tracking.expectedSize, countStyle: .memory))
            - Actual: \(ByteCountFormatter.string(fromByteCount: actualMemoryUsed, countStyle: .memory))
            - Overhead: \(ByteCountFormatter.string(fromByteCount: memoryOverhead, countStyle: .memory))
            - Load time: \(String(format: "%.2f", loadTime))s
            """)

        return profile
    }

    /// Profile model loading with async operation
    func profileModelLoading(
        framework: LLMFramework,
        modelName: String,
        expectedSize: Int64,
        loadOperation: () async throws -> Void
    ) async throws -> ModelMemoryProfile {
        let trackingId = beginModelTracking(
            framework: framework,
            modelName: modelName,
            expectedSize: expectedSize
        )

        do {
            try await loadOperation()

            guard let profile = endModelTracking(trackingId: trackingId) else {
                throw ProfilingError.trackingNotFound
            }

            return profile
        } catch {
            // Clean up tracking on error
            queue.async(flags: .barrier) { [weak self] in
                self?.activeTracking.removeValue(forKey: trackingId)
            }
            throw error
        }
    }

    /// Get all active model trackings
    func getActiveTrackings() -> [ModelMemoryTracking] {
        queue.sync {
            Array(activeTracking.values)
        }
    }
}

enum ProfilingError: LocalizedError {
    case trackingNotFound

    var errorDescription: String? {
        switch self {
        case .trackingNotFound:
            return "Model tracking information not found"
        }
    }
}
