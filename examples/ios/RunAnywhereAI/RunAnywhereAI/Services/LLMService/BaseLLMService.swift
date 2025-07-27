//
//  BaseLLMService.swift
//  RunAnywhereAI
//
//  Created by Sanchit Monga on 7/26/25.
//

import Foundation

/// Base class providing default implementations for LLM services
/// This helps existing services migrate to the new protocol structure
class BaseLLMService: LLMService {
    // MARK: - Properties to be overridden

    var frameworkInfo: FrameworkInfo {
        fatalError("Subclasses must override frameworkInfo")
    }

    var name: String {
        frameworkInfo.name
    }

    var isInitialized: Bool = false

    var supportedModels: [ModelInfo] = []

    // MARK: - LLMCapabilities defaults

    var supportsStreaming: Bool { true }
    var supportsQuantization: Bool { false }
    var supportsBatching: Bool { false }
    var supportsMultiModal: Bool { false }
    var quantizationFormats: [QuantizationFormat] { [] }
    var maxContextLength: Int { 2048 }
    var supportsCustomOperators: Bool { false }
    var hardwareAcceleration: [HardwareAcceleration] { [.cpu] }

    // MARK: - LLMModelLoader defaults

    var modelState: ModelState = .unloaded
    var supportedFormats: [ModelFormat] { [] }

    func isFormatSupported(_ format: ModelFormat) -> Bool {
        supportedFormats.contains(format)
    }

    func loadModel(_ path: String) async throws {
        // Legacy support - call initialize
        try await initialize(modelPath: path)
        modelState = .loaded(modelInfo: getModelInfo() ?? ModelInfo(
            name: "Unknown",
            format: .other,
            size: "Unknown",
            framework: .mock
        ))
    }

    func unloadModel() async throws {
        cleanup()
        modelState = .unloaded
    }

    func preloadModel(_ config: ModelConfiguration) async throws {
        try await loadModel(config.modelPath)
    }

    func validateModel(at path: String) async throws -> ModelValidation {
        // Basic validation
        let fileExists = FileManager.default.fileExists(atPath: path)
        let attributes = try? FileManager.default.attributesOfItem(atPath: path)
        let fileSize = attributes?[.size] as? Int64 ?? 0

        return ModelValidation(
            isValid: fileExists,
            format: nil,
            fileSize: fileSize,
            estimatedMemory: fileSize * 2, // Rough estimate
            warnings: fileExists ? [] : ["File not found"],
            metadata: [:]
        )
    }

    // MARK: - LLMInference defaults

    var isReadyForInference: Bool { isInitialized }
    var generationState: GenerationState = .idle

    func generate(_ request: GenerationRequest) async throws -> GenerationResponse {
        // Use legacy method
        let startTime = CFAbsoluteTimeGetCurrent()
        let text = try await generate(prompt: request.prompt, options: request.options)
        let duration = CFAbsoluteTimeGetCurrent() - startTime

        let tokens = text.split(separator: " ").count
        return GenerationResponse(
            text: text,
            tokensGenerated: tokens,
            timeToFirstToken: 0.1,
            totalTime: duration,
            tokensPerSecond: Double(tokens) / duration,
            promptTokens: request.prompt.split(separator: " ").count,
            completionTokens: tokens,
            totalTokens: request.prompt.split(separator: " ").count + tokens,
            finishReason: .completed,
            metadata: [:]
        )
    }

    func streamGenerate(_ request: GenerationRequest) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    try await streamGenerate(
                        prompt: request.prompt,
                        options: request.options
                    ) { token in
                        continuation.yield(token)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    func cancelGeneration() async {
        generationState = .cancelled
    }

    // MARK: - LLMMetrics defaults

    func getPerformanceMetrics() -> LLMPerformanceMetrics {
        LLMPerformanceMetrics(
            averageTokensPerSecond: 0,
            peakTokensPerSecond: 0,
            averageLatency: 0,
            p95Latency: 0,
            p99Latency: 0,
            totalTokensGenerated: 0,
            totalGenerations: 0,
            failureRate: 0,
            averageContextLength: 0,
            hardwareUtilization: HardwareUtilization(
                cpuUsage: 0,
                gpuUsage: nil,
                neuralEngineUsage: nil,
                powerUsage: 0,
                thermalState: .nominal
            )
        )
    }

    func getMemoryUsage() -> LLMMemoryStats {
        LLMMemoryStats(
            modelMemory: 0,
            contextMemory: 0,
            peakMemory: 0,
            availableMemory: Int64(ProcessInfo.processInfo.physicalMemory),
            memoryPressure: .normal,
            cacheSize: 0
        )
    }

    func getBenchmarkResults() -> BenchmarkResults {
        BenchmarkResults(
            framework: name,
            model: getModelInfo()?.name ?? "Unknown",
            device: "Unknown",
            timestamp: Date(),
            promptProcessingSpeed: 0,
            generationSpeed: 0,
            firstTokenLatency: 0,
            memoryFootprint: 0,
            energyEfficiency: 0,
            qualityScore: nil,
            configurations: [:]
        )
    }

    func resetMetrics() {}

    func exportMetrics() -> Data? { nil }

    func subscribeToMetrics(_ handler: @escaping (MetricsUpdate) -> Void) -> UUID { UUID() }

    func unsubscribeFromMetrics(_ id: UUID) {}

    // MARK: - Additional requirements

    func configure(_ options: [String: Any]) throws {}

    func healthCheck() async -> HealthCheckResult {
        HealthCheckResult(
            isHealthy: isInitialized,
            frameworkVersion: frameworkInfo.version,
            availableMemory: Int64(ProcessInfo.processInfo.physicalMemory),
            modelLoaded: isInitialized,
            lastError: nil,
            diagnostics: [:]
        )
    }

    // MARK: - Legacy methods to be implemented by subclasses

    func initialize(modelPath: String) async throws {
        fatalError("Subclasses must implement initialize(modelPath:)")
    }

    func generate(prompt: String, options: GenerationOptions) async throws -> String {
        fatalError("Subclasses must implement generate(prompt:options:)")
    }

    func streamGenerate(
        prompt: String,
        options: GenerationOptions,
        onToken: @escaping (String) -> Void
    ) async throws {
        // Default implementation using generate
        let result = try await generate(prompt: prompt, options: options)
        let words = result.split(separator: " ")
        for word in words {
            onToken(String(word) + " ")
            try await Task.sleep(nanoseconds: 50_000_000) // 50ms
        }
    }

    func getModelInfo() -> ModelInfo? { nil }

    func cleanup() {
        isInitialized = false
    }
}
