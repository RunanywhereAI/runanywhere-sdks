//
//  BenchmarkViewModel.swift
//  RunAnywhereAI
//
//  ViewModel for benchmark UI
//

import Foundation
import RunAnywhere
import os.log

@MainActor
@Observable
final class BenchmarkViewModel {
    // MARK: - Dependencies
    
    let benchmarkService = BenchmarkService()
    private let logger = Logger(subsystem: "com.runanywhere.RunAnywhereAI", category: "BenchmarkViewModel")
    
    // MARK: - UI State
    
    var selectedModelIds: Set<String> = []
    var selectedConfig: ConfigOption = .default
    var showModelPicker = false
    
    // MARK: - Computed State
    
    var state: BenchmarkState { benchmarkService.state }
    var progress: BenchmarkProgress? { benchmarkService.progress }
    var results: [BenchmarkResult] { benchmarkService.results }
    var error: Error? { benchmarkService.currentError }
    
    var availableLLMModels: [ModelInfo] {
        get async {
            (try? await RunAnywhere.availableModels().filter { model in
                model.category == .language && model.isDownloaded
            }) ?? []
        }
    }
    
    var canStartBenchmark: Bool {
        !selectedModelIds.isEmpty && !state.isRunning
    }
    
    // MARK: - Config Options
    
    enum ConfigOption: String, CaseIterable, Identifiable {
        case quick = "Quick"
        case `default` = "Default"
        case comprehensive = "Comprehensive"
        
        var id: String { rawValue }
        
        var config: BenchmarkConfig {
            switch self {
            case .quick: return .quick
            case .default: return .default
            case .comprehensive: return .comprehensive
            }
        }
        
        var description: String {
            switch self {
            case .quick:
                return "1 warmup, 3 iterations, 1 prompt"
            case .default:
                return "3 warmups, 5 iterations, 3 prompts"
            case .comprehensive:
                return "3 warmups, 10 iterations, 3 prompts, more tokens"
            }
        }
    }
    
    // MARK: - Actions
    
    func startBenchmark() async {
        guard canStartBenchmark else { return }
        
        let modelIds = Array(selectedModelIds)
        logger.info("Starting benchmark for \(modelIds.count) models")
        
        do {
            _ = try await benchmarkService.runLLMBenchmark(
                modelIds: modelIds,
                config: selectedConfig.config
            )
        } catch {
            logger.error("Benchmark failed: \(error.localizedDescription)")
        }
    }
    
    func cancelBenchmark() {
        benchmarkService.cancel()
    }
    
    func clearResults() {
        benchmarkService.clearResults()
    }
    
    func toggleModelSelection(_ modelId: String) {
        if selectedModelIds.contains(modelId) {
            selectedModelIds.remove(modelId)
        } else {
            selectedModelIds.insert(modelId)
        }
    }
    
    func selectAllModels(_ models: [ModelInfo]) {
        selectedModelIds = Set(models.map { $0.id })
    }
    
    func deselectAllModels() {
        selectedModelIds.removeAll()
    }
}

// MARK: - Formatting Helpers

extension BenchmarkViewModel {
    func formatTokensPerSecond(_ value: Double) -> String {
        String(format: "%.1f tok/s", value)
    }
    
    func formatLatency(_ ms: Double) -> String {
        if ms >= 1000 {
            return String(format: "%.2fs", ms / 1000)
        } else {
            return String(format: "%.0fms", ms)
        }
    }
    
    func formatMemory(_ bytes: Int64) -> String {
        let mb = Double(bytes) / 1024 / 1024
        return String(format: "%.0f MB", mb)
    }
    
    func formatProgress(_ progress: Double) -> String {
        String(format: "%.0f%%", progress * 100)
    }
    
    func formatDuration(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds) / 60
        let secs = Int(seconds) % 60
        if minutes > 0 {
            return "\(minutes)m \(secs)s"
        } else {
            return "\(secs)s"
        }
    }
}
