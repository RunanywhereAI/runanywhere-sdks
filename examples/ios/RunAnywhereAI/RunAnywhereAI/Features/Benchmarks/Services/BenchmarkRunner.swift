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
        model: RAModelInfo
    ) async throws -> BenchmarkMetrics
}

// MARK: - Runner Errors

enum BenchmarkRunnerError: LocalizedError {
    case noModelsAvailable(skippedCategories: [BenchmarkCategory])
    case noWorkItems(skippedCategories: [BenchmarkCategory])
    case fetchModelsFailed(underlying: Error)

    var errorDescription: String? {
        switch self {
        case .noModelsAvailable(let skipped):
            let names = skipped.map(\.displayName).joined(separator: ", ")
            return "No downloaded models found for: \(names). Download models first from the Models tab."
        case .noWorkItems(let skipped):
            if skipped.isEmpty {
                return "No benchmarks to run. Select at least one downloaded model and try again."
            }
            let names = skipped.map(\.displayName).joined(separator: ", ")
            return """
            No benchmarks to run. Missing on-disk models for: \(names). \
            Download models first from the Models tab.
            """
        case .fetchModelsFailed(let error):
            return "Failed to fetch available models: \(error.localizedDescription)"
        }
    }
}

// MARK: - Pre-flight Result

struct BenchmarkPreflightResult: Sendable {
    let availableCategories: [BenchmarkCategory: [RAModelInfo]]
    let skippedCategories: [BenchmarkCategory]
    let totalWorkItems: Int
}

// MARK: - Work Item

/// One scenario/model pair to execute in a single benchmark category.
struct BenchmarkWorkItem: Sendable {
    let category: BenchmarkCategory
    let model: RAModelInfo
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
            VLMBenchmarkProvider()
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
        await RunAnywhere.refreshModelRegistry()

        let allModels: [RAModelInfo]
        let listResult = await RunAnywhere.listModels()
        guard listResult.success else {
            throw BenchmarkRunnerError.fetchModelsFailed(
                underlying: SDKException(
                    code: .processingFailed,
                    message: listResult.errorMessage.isEmpty ? "model registry" : listResult.errorMessage,
                    category: .internal
                )
            )
        }
        allModels = listResult.models.models

        var available: [BenchmarkCategory: [RAModelInfo]] = [:]
        var skipped: [BenchmarkCategory] = []

        for category in BenchmarkCategory.allCases where categories.contains(category) {
            guard providers[category] != nil else {
                skipped.append(category)
                continue
            }
            let models = Self.downloadedModels(for: category, in: allModels)
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
        trials: Int = 1,
        onProgress: @escaping @Sendable (BenchmarkProgressUpdate) -> Void
    ) async throws -> BenchmarkRunOutput {
        let trialCount = max(1, trials)
        let preflight = try await preflight(categories: categories)

        // If nothing to run, throw a descriptive error
        if preflight.availableCategories.isEmpty || preflight.totalWorkItems == 0 {
            throw BenchmarkRunnerError.noModelsAvailable(
                skippedCategories: preflight.skippedCategories
            )
        }

        let workItems = buildWorkItems(
            categories: categories,
            modelIds: modelIds,
            preflight: preflight
        )

        guard !workItems.isEmpty else {
            throw BenchmarkRunnerError.noWorkItems(
                skippedCategories: preflight.skippedCategories
            )
        }

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

            // Each execute() is a full independent pass (load → warmup → measure →
            // unload). Running it `trialCount` times and reporting the per-metric
            // median (with min/max range) damps single-run noise. Any trial failure
            // fails the whole item, matching the deterministic (temperature 0) intent.
            let aggregated: BenchmarkMetrics
            let variance: BenchmarkVariance?
            do {
                guard let provider = providers[item.category] else { continue }
                var trialMetrics: [BenchmarkMetrics] = []
                trialMetrics.reserveCapacity(trialCount)
                for _ in 0..<trialCount {
                    try Task.checkCancellation()
                    trialMetrics.append(try await provider.execute(
                        scenario: item.scenario,
                        model: item.model
                    ))
                }
                (aggregated, variance) = BenchmarkMetrics.aggregate(trialMetrics)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                var errorMetrics = BenchmarkMetrics()
                let prefix = "\(item.category.displayName) [\(item.model.name)]"
                errorMetrics.errorMessage = "\(prefix): \(error.localizedDescription)"
                aggregated = errorMetrics
                variance = nil
            }

            results.append(BenchmarkResult(
                category: item.category,
                scenario: item.scenario,
                modelInfo: ComponentModelInfo(from: item.model),
                metrics: aggregated,
                variance: variance
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
            let filteredModels: [RAModelInfo]
            if let modelIds, !modelIds.isEmpty {
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

    /// Models whose artifacts exist on disk (registry `isDownloaded` may be stale).
    static func downloadedModels(
        for category: BenchmarkCategory,
        in allModels: [RAModelInfo]
    ) -> [RAModelInfo] {
        allModels.filter { model in
            guard model.category == category.modelCategory, !model.isBuiltIn else { return false }
            if model.isDownloadedOnDisk { return true }
            // Post-download registry may mark downloaded before artifact probe catches up.
            return model.isDownloaded && !model.localPath.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }
}
