//
//  BenchmarkService.swift
//  RunAnywhereAI
//
//  Service for running model benchmarks and collecting metrics
//

import Foundation
import RunAnywhere
import os.log
#if canImport(UIKit)
import UIKit
#endif

// MARK: - Benchmark Service

@MainActor
@Observable
final class BenchmarkService {
    // MARK: - Published State
    
    private(set) var state: BenchmarkState = .idle
    private(set) var progress: BenchmarkProgress?
    private(set) var results: [BenchmarkResult] = []
    private(set) var currentError: Error?
    
    // MARK: - Private State
    
    private let logger = Logger(subsystem: "com.runanywhere.RunAnywhereAI", category: "BenchmarkService")
    private var benchmarkTask: Task<Void, Never>?
    private var startTime: Date?
    private var peakMemoryBytes: Int64 = 0
    
    // MARK: - Public Methods
    
    /// Run LLM benchmarks on the specified models
    func runLLMBenchmark(
        modelIds: [String],
        config: BenchmarkConfig = .default
    ) async throws -> [BenchmarkResult] {
        guard !state.isRunning else {
            throw BenchmarkError.alreadyRunning
        }
        
        state = .preparing
        startTime = Date()
        results = []
        currentError = nil
        
        var allResults: [BenchmarkResult] = []
        
        do {
            for (modelIndex, modelId) in modelIds.enumerated() {
                let result = try await benchmarkSingleModel(
                    modelId: modelId,
                    modelIndex: modelIndex,
                    totalModels: modelIds.count,
                    config: config
                )
                allResults.append(result)
                results = allResults
            }
            
            state = .completed
            
            // Export results to file
            try exportResults(allResults)
            
            logger.info("Benchmark completed: \(allResults.count) models tested")
            return allResults
            
        } catch {
            state = .failed(error: error.localizedDescription)
            currentError = error
            throw error
        }
    }
    
    /// Cancel the current benchmark
    func cancel() {
        benchmarkTask?.cancel()
        state = .idle
        logger.info("Benchmark cancelled")
    }
    
    /// Clear results
    func clearResults() {
        results = []
        state = .idle
        currentError = nil
    }
    
    // MARK: - Private Methods
    
    private func benchmarkSingleModel(
        modelId: String,
        modelIndex: Int,
        totalModels: Int,
        config: BenchmarkConfig
    ) async throws -> BenchmarkResult {
        logger.info("Starting benchmark for model: \(modelId)")
        
        // Get model info
        guard let modelInfo = try await RunAnywhere.availableModels().first(where: { $0.id == modelId }) else {
            throw BenchmarkError.modelNotFound(modelId)
        }
        
        // Load model and measure load time
        let loadStart = CFAbsoluteTimeGetCurrent()
        try await RunAnywhere.loadModel(modelId)
        let loadTimeMs = (CFAbsoluteTimeGetCurrent() - loadStart) * 1000
        
        logger.info("Model loaded in \(loadTimeMs)ms")
        
        // Reset peak memory tracking
        peakMemoryBytes = 0
        
        // Warmup phase
        for i in 0..<config.warmupIterations {
            state = .warmingUp(model: modelInfo.name, iteration: i + 1, total: config.warmupIterations)
            updateProgress(modelIndex: modelIndex, totalModels: totalModels)
            
            _ = try await runSingleInference(
                prompt: config.prompts.first!,
                maxTokens: config.maxTokensList.first!
            )
        }
        
        // Benchmark runs
        var runResults: [SingleRunResult] = []
        let totalRuns = config.prompts.count * config.maxTokensList.count * config.testIterations
        var currentRun = 0
        
        for prompt in config.prompts {
            for maxTokens in config.maxTokensList {
                for iteration in 0..<config.testIterations {
                    currentRun += 1
                    state = .running(
                        model: modelInfo.name,
                        prompt: prompt.id,
                        iteration: currentRun,
                        total: totalRuns
                    )
                    updateProgress(modelIndex: modelIndex, totalModels: totalModels)
                    
                    let result = try await runSingleInference(prompt: prompt, maxTokens: maxTokens)
                    runResults.append(result)
                    
                    // Track peak memory
                    let currentMemory = getMemoryUsage()
                    if currentMemory > peakMemoryBytes {
                        peakMemoryBytes = currentMemory
                    }
                }
            }
        }
        
        // Unload model
        try await RunAnywhere.unloadModel()
        
        // Aggregate results
        let aggregatedResult = aggregateResults(
            runResults: runResults,
            modelInfo: modelInfo,
            loadTimeMs: loadTimeMs,
            config: config
        )
        
        logger.info("Benchmark completed for \(modelId): \(aggregatedResult.avgTokensPerSecond) tok/s")
        
        return aggregatedResult
    }
    
    private func runSingleInference(
        prompt: BenchmarkPrompt,
        maxTokens: Int
    ) async throws -> SingleRunResult {
        let options = LLMGenerationOptions(
            maxTokens: maxTokens,
            temperature: 0.7
        )
        
        let result = try await RunAnywhere.generate(prompt.text, options: options)
        
        return SingleRunResult(
            promptId: prompt.id,
            maxTokens: maxTokens,
            tokensPerSecond: result.tokensPerSecond,
            latencyMs: result.latencyMs,
            ttftMs: result.timeToFirstTokenMs,
            outputTokens: result.tokensUsed,
            inputTokens: result.inputTokens,
            timestamp: Date()
        )
    }
    
    private func aggregateResults(
        runResults: [SingleRunResult],
        modelInfo: ModelInfo,
        loadTimeMs: Double,
        config: BenchmarkConfig
    ) -> BenchmarkResult {
        let tokensPerSecondValues = runResults.map { $0.tokensPerSecond }
        let latencyValues = runResults.map { $0.latencyMs }
        let ttftValues = runResults.compactMap { $0.ttftMs }
        
        // Group by prompt for per-prompt stats
        let promptGroups = Dictionary(grouping: runResults) { $0.promptId }
        let promptResults = promptGroups.map { promptId, results -> PromptAggregatedResult in
            let prompt = config.prompts.first { $0.id == promptId }
            return PromptAggregatedResult(
                promptId: promptId,
                promptCategory: prompt?.category.rawValue ?? "unknown",
                avgTokensPerSecond: results.map { $0.tokensPerSecond }.average(),
                avgLatencyMs: results.map { $0.latencyMs }.average(),
                avgTtftMs: results.compactMap { $0.ttftMs }.average(),
                runCount: results.count
            )
        }
        
        return BenchmarkResult(
            id: UUID().uuidString,
            modelId: modelInfo.id,
            modelName: modelInfo.name,
            framework: modelInfo.framework.rawValue,
            deviceId: getDeviceId(),
            deviceModel: getDeviceModel(),
            osVersion: getOSVersion(),
            sdkVersion: RunAnywhere.version,
            gitCommit: getGitCommit(),
            timestamp: Date(),
            modelLoadTimeMs: loadTimeMs,
            avgTokensPerSecond: tokensPerSecondValues.average(),
            p50TokensPerSecond: tokensPerSecondValues.percentile(50),
            p95TokensPerSecond: tokensPerSecondValues.percentile(95),
            minTokensPerSecond: tokensPerSecondValues.min() ?? 0,
            maxTokensPerSecond: tokensPerSecondValues.max() ?? 0,
            avgTtftMs: ttftValues.average(),
            p50TtftMs: ttftValues.percentile(50),
            p95TtftMs: ttftValues.percentile(95),
            avgLatencyMs: latencyValues.average(),
            p50LatencyMs: latencyValues.percentile(50),
            p95LatencyMs: latencyValues.percentile(95),
            peakMemoryBytes: peakMemoryBytes,
            totalRuns: runResults.count,
            promptResults: promptResults,
            config: config
        )
    }
    
    private func updateProgress(modelIndex: Int, totalModels: Int) {
        guard let startTime = startTime else { return }
        
        let elapsed = Date().timeIntervalSince(startTime)
        let overallProgress: Double
        
        switch state {
        case .warmingUp(_, let iteration, let total):
            let warmupProgress = Double(iteration) / Double(total)
            overallProgress = (Double(modelIndex) + warmupProgress * 0.2) / Double(totalModels)
        case .running(_, _, let iteration, let total):
            let runProgress = Double(iteration) / Double(total)
            overallProgress = (Double(modelIndex) + 0.2 + runProgress * 0.8) / Double(totalModels)
        default:
            overallProgress = Double(modelIndex) / Double(totalModels)
        }
        
        let estimatedRemaining: TimeInterval?
        if overallProgress > 0.1 {
            estimatedRemaining = elapsed / overallProgress * (1 - overallProgress)
        } else {
            estimatedRemaining = nil
        }
        
        progress = BenchmarkProgress(
            state: state,
            overallProgress: overallProgress,
            currentModelIndex: modelIndex,
            totalModels: totalModels,
            elapsedTime: elapsed,
            estimatedRemainingTime: estimatedRemaining
        )
    }
    
    private func exportResults(_ results: [BenchmarkResult]) throws {
        let export = BenchmarkExport(results: results)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        
        let data = try encoder.encode(export)
        
        let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        let timestamp = ISO8601DateFormatter().string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let filename = "benchmark_\(timestamp).json"
        let fileURL = documentsURL.appendingPathComponent(filename)
        
        try data.write(to: fileURL)
        logger.info("Benchmark results exported to: \(fileURL.path)")
    }
    
    // MARK: - Device Info Helpers
    
    private func getDeviceId() -> String {
        #if os(iOS)
        return UIDevice.current.identifierForVendor?.uuidString ?? "unknown"
        #else
        return ProcessInfo.processInfo.hostName
        #endif
    }
    
    private func getDeviceModel() -> String {
        #if os(iOS)
        var systemInfo = utsname()
        uname(&systemInfo)
        let modelCode = withUnsafePointer(to: &systemInfo.machine) {
            $0.withMemoryRebound(to: CChar.self, capacity: 1) {
                String(cString: $0)
            }
        }
        return modelCode
        #else
        return "Mac"
        #endif
    }
    
    private func getOSVersion() -> String {
        #if os(iOS)
        return UIDevice.current.systemVersion
        #else
        return ProcessInfo.processInfo.operatingSystemVersionString
        #endif
    }
    
    private func getGitCommit() -> String? {
        Bundle.main.infoDictionary?["GitCommit"] as? String
    }
    
    private func getMemoryUsage() -> Int64 {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        return result == KERN_SUCCESS ? Int64(info.resident_size) : 0
    }
}

// MARK: - Errors

enum BenchmarkError: LocalizedError {
    case alreadyRunning
    case modelNotFound(String)
    case inferenceError(String)
    
    var errorDescription: String? {
        switch self {
        case .alreadyRunning:
            return "A benchmark is already running"
        case .modelNotFound(let id):
            return "Model not found: \(id)"
        case .inferenceError(let message):
            return "Inference error: \(message)"
        }
    }
}

// MARK: - Array Extensions for Statistics

private extension Array where Element == Double {
    func average() -> Double {
        guard !isEmpty else { return 0 }
        return reduce(0, +) / Double(count)
    }
    
    func percentile(_ p: Int) -> Double {
        guard !isEmpty else { return 0 }
        let sorted = self.sorted()
        let index = Int(Double(count - 1) * Double(p) / 100.0)
        return sorted[Swift.min(index, count - 1)]
    }
}
