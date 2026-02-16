//
//  BenchmarkRunner.swift
//  RunAnywhereAI
//
//  Orchestrates benchmark execution across all providers.
//

import Foundation
import RunAnywhere

// MARK: - Provider Protocol

protocol BenchmarkScenarioProvider {
    var category: BenchmarkCategory { get }
    func scenarios() -> [BenchmarkScenario]
    func execute(
        scenario: BenchmarkScenario,
        model: ModelInfo,
        deviceInfo: BenchmarkDeviceInfo
    ) async throws -> BenchmarkMetrics
}

// MARK: - Runner

final class BenchmarkRunner {

    private let providers: [BenchmarkCategory: BenchmarkScenarioProvider]

    init() {
        var map: [BenchmarkCategory: BenchmarkScenarioProvider] = [:]
        let all: [BenchmarkScenarioProvider] = [
            LLMBenchmarkProvider(),
            STTBenchmarkProvider(),
            TTSBenchmarkProvider(),
            VLMBenchmarkProvider(),
            DiffusionBenchmarkProvider(),
        ]
        for provider in all {
            map[provider.category] = provider
        }
        self.providers = map
    }

    // MARK: - Run

    func runBenchmarks(
        categories: Set<BenchmarkCategory>,
        onProgress: @escaping @Sendable (BenchmarkProgressUpdate) -> Void
    ) async throws -> [BenchmarkResult] {
        let allModels = try await RunAnywhere.availableModels()

        // Build work list: (category, model, scenario)
        var workItems: [(BenchmarkCategory, ModelInfo, BenchmarkScenario)] = []

        for category in BenchmarkCategory.allCases where categories.contains(category) {
            guard let provider = providers[category] else { continue }
            let scenarioList = provider.scenarios()
            let categoryModels = allModels.filter {
                $0.category == category.modelCategory && $0.isDownloaded && !$0.isBuiltIn
            }
            for model in categoryModels {
                for scenario in scenarioList {
                    workItems.append((category, model, scenario))
                }
            }
        }

        let total = workItems.count
        var results: [BenchmarkResult] = []

        for (index, (category, model, scenario)) in workItems.enumerated() {
            try Task.checkCancellation()

            onProgress(BenchmarkProgressUpdate(
                completedCount: index,
                totalCount: total,
                currentScenario: scenario.name,
                currentModel: model.name
            ))

            let metrics: BenchmarkMetrics
            do {
                guard let provider = providers[category] else { continue }
                metrics = try await provider.execute(
                    scenario: scenario,
                    model: model,
                    deviceInfo: BenchmarkDeviceInfo(
                        modelName: "",
                        chipName: "",
                        totalMemoryBytes: 0,
                        availableMemoryBytes: SyntheticInputGenerator.availableMemoryBytes(),
                        osVersion: ""
                    )
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                var errorMetrics = BenchmarkMetrics()
                errorMetrics.errorMessage = error.localizedDescription
                metrics = errorMetrics
            }

            results.append(BenchmarkResult(
                category: category,
                scenario: scenario,
                modelInfo: ComponentModelInfo(from: model),
                metrics: metrics
            ))
        }

        // Final progress
        onProgress(BenchmarkProgressUpdate(
            completedCount: total,
            totalCount: total,
            currentScenario: "Done",
            currentModel: ""
        ))

        return results
    }
}
