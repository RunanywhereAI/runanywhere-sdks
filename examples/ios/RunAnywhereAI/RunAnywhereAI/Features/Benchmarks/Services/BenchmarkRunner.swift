//
//  BenchmarkRunner.swift
//  RunAnywhereAI
//
//  Orchestrates benchmark execution across all providers.
//

import Foundation
import RunAnywhere

// MARK: - Provider Protocol

protocol BenchmarkScenarioProvider: Sendable {
    var category: BenchmarkCategory { get }
    func scenarios() -> [BenchmarkScenario]
    func execute(
        scenario: BenchmarkScenario,
        model: ModelInfo
    ) async throws -> BenchmarkMetrics
}

// MARK: - Runner Errors

enum BenchmarkRunnerError: LocalizedError {
    case noModelsAvailable(skippedCategories: [BenchmarkCategory])
    case fetchModelsFailed(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .noModelsAvailable(let skipped):
            let names = skipped.map(\.displayName).joined(separator: ", ")
            return "No downloaded models found for: \(names). Download models first from the Models tab."
        case .fetchModelsFailed(let error):
            return "Failed to fetch available models: \(error.localizedDescription)"
        }
    }
}

// MARK: - Pre-flight Result

struct BenchmarkPreflightResult: Sendable {
    let availableCategories: [BenchmarkCategory: [ModelInfo]]
    let skippedCategories: [BenchmarkCategory]
    let totalWorkItems: Int
}

// MARK: - Work Item

/// One scenario/model pair to execute in a single benchmark category.
struct BenchmarkWorkItem: Sendable {
    let category: BenchmarkCategory
    let model: ModelInfo
    let scenario: BenchmarkScenario
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
            DiffusionBenchmarkProvider()
        ]
        for provider in all {
            map[provider.category] = provider
        }
        self.providers = map
    }

    // MARK: - Preflight Check

    /// Checks which categories have downloaded models before running. This lets the UI
    /// inform the user which categories will be skipped.
    func preflight(categories: Set<BenchmarkCategory>) async throws -> BenchmarkPreflightResult {
        let allModels: [ModelInfo]
        do {
            allModels = try await RunAnywhere.availableModels()
        } catch {
            throw BenchmarkRunnerError.fetchModelsFailed(underlying: error)
        }

        var available: [BenchmarkCategory: [ModelInfo]] = [:]
        var skipped: [BenchmarkCategory] = []

        for category in BenchmarkCategory.allCases where categories.contains(category) {
            guard providers[category] != nil else {
                skipped.append(category)
                continue
            }
            let models = allModels.filter {
                $0.category == category.modelCategory && $0.isDownloaded && !$0.isBuiltIn
            }
            if models.isEmpty {
                skipped.append(category)
            } else {
                available[category] = models
            }
        }

        var totalItems = 0
        for (category, models) in available {
            let scenarioCount = providers[category]?.scenarios().count ?? 0
            totalItems += models.count * scenarioCount
        }

        return BenchmarkPreflightResult(
            availableCategories: available,
            skippedCategories: skipped,
            totalWorkItems: totalItems
        )
    }

    // MARK: - Run

    // swiftlint:disable:next function_body_length
    func runBenchmarks(
        categories: Set<BenchmarkCategory>,
        modelIds: Set<String>? = nil,
        onProgress: @escaping @Sendable (BenchmarkProgressUpdate) -> Void
    ) async throws -> BenchmarkRunOutput {
        let preflight = try await preflight(categories: categories)

        // If nothing to run, throw a descriptive error
        if preflight.availableCategories.isEmpty {
            throw BenchmarkRunnerError.noModelsAvailable(
                skippedCategories: preflight.skippedCategories
            )
        }

        let workItems = buildWorkItems(
            categories: categories,
            modelIds: modelIds,
            preflight: preflight
        )

        let total = workItems.count
        var results: [BenchmarkResult] = []

        for (index, item) in workItems.enumerated() {
            try Task.checkCancellation()

            onProgress(BenchmarkProgressUpdate(
                completedCount: index,
                totalCount: total,
                currentScenario: item.scenario.name,
                currentModel: item.model.name
            ))

            let metrics: BenchmarkMetrics
            do {
                guard let provider = providers[item.category] else { continue }
                metrics = try await provider.execute(
                    scenario: item.scenario,
                    model: item.model
                )
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                var errorMetrics = BenchmarkMetrics()
                let prefix = "\(item.category.displayName) [\(item.model.name)]"
                errorMetrics.errorMessage = "\(prefix): \(error.localizedDescription)"
                metrics = errorMetrics
            }

            results.append(BenchmarkResult(
                category: item.category,
                scenario: item.scenario,
                modelInfo: ComponentModelInfo(from: item.model),
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

        return BenchmarkRunOutput(
            results: results,
            skippedCategories: preflight.skippedCategories
        )
    }

    /// Expand `(category × model × scenario)` into a flat list of work items.
    private func buildWorkItems(
        categories: Set<BenchmarkCategory>,
        modelIds: Set<String>?,
        preflight: BenchmarkPreflightResult
    ) -> [BenchmarkWorkItem] {
        var workItems: [BenchmarkWorkItem] = []
        for category in BenchmarkCategory.allCases where categories.contains(category) {
            guard let provider = providers[category],
                  let models = preflight.availableCategories[category] else { continue }
            let filteredModels: [ModelInfo]
            if let modelIds {
                filteredModels = models.filter { modelIds.contains($0.id) }
            } else {
                filteredModels = models
            }
            let scenarioList = provider.scenarios()
            for model in filteredModels {
                for scenario in scenarioList {
                    workItems.append(BenchmarkWorkItem(
                        category: category,
                        model: model,
                        scenario: scenario
                    ))
                }
            }
        }
        return workItems
    }
}
