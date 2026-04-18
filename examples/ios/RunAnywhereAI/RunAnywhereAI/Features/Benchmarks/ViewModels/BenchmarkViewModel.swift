//
//  BenchmarkViewModel.swift
//  RunAnywhereAI
//
//  Orchestrates benchmark execution, persistence, and export.
//

import Foundation
import RunAnywhere
#if canImport(UIKit)
import UIKit
#endif

@MainActor
@Observable
final class BenchmarkViewModel {
    // MARK: - State

    var isRunning = false
    var progress: Double = 0
    var currentScenario: String = ""
    var currentModel: String = ""
    var completedCount: Int = 0
    var totalCount: Int = 0
    var pastRuns: [BenchmarkRun] = []
    var selectedCategories: Set<BenchmarkCategory> = Set(BenchmarkCategory.allCases)
    var errorMessage: String?
    var showClearConfirmation = false

    /// Brief toast message shown after clipboard copy
    var copiedToastMessage: String?

    /// Categories that had no downloaded models during the last run
    var skippedCategoriesMessage: String?

    /// Available downloaded models grouped by category, for user selection
    var availableModels: [BenchmarkCategory: [ModelInfo]] = [:]

    /// Which model IDs the user has selected for benchmarking.
    /// Empty means "all models" (backwards-compatible default).
    var selectedModelIds: Set<String> = []

    // MARK: - Private

    private let runner = BenchmarkRunner()
    private let store = BenchmarkStore()
    private var runTask: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?

    // MARK: - Lifecycle

    func loadPastRuns() {
        pastRuns = store.loadRuns().reversed()
    }

    func refreshAvailableModels() {
        Task {
            do {
                let allModels = try await RunAnywhere.availableModels()
                var grouped: [BenchmarkCategory: [ModelInfo]] = [:]
                for category in BenchmarkCategory.allCases {
                    let models = allModels.filter {
                        $0.category == category.modelCategory && $0.isDownloaded && !$0.isBuiltIn
                    }
                    if !models.isEmpty {
                        grouped[category] = models
                    }
                }
                availableModels = grouped
                if selectedModelIds.isEmpty {
                    selectedModelIds = Set(grouped.values.flatMap { $0 }.map { $0.id })
                }
            } catch {
                availableModels = [:]
            }
        }
    }

    func toggleModel(_ modelId: String) {
        if selectedModelIds.contains(modelId) {
            selectedModelIds.remove(modelId)
        } else {
            selectedModelIds.insert(modelId)
        }
    }

    func selectAllModels() {
        selectedModelIds = Set(availableModels.values.flatMap { $0 }.map { $0.id })
    }

    func deselectAllModels() {
        selectedModelIds.removeAll()
    }

    // MARK: - Run

    func runBenchmarks() {
        guard !isRunning else { return }
        isRunning = true
        errorMessage = nil
        skippedCategoriesMessage = nil
        progress = 0
        completedCount = 0
        totalCount = 0
        currentScenario = "Preparing..."
        currentModel = ""

        runTask = Task {
            let deviceInfo = makeDeviceInfo()
            var run = BenchmarkRun(deviceInfo: deviceInfo)

            do {
                let output = try await runner.runBenchmarks(
                    categories: selectedCategories,
                    modelIds: selectedModelIds
                ) { [weak self] update in
                    Task { @MainActor in
                        self?.progress = update.progress
                        self?.completedCount = update.completedCount
                        self?.totalCount = update.totalCount
                        self?.currentScenario = update.currentScenario
                        self?.currentModel = update.currentModel
                    }
                }

                if !output.skippedCategories.isEmpty {
                    let names = output.skippedCategories.map(\.displayName).joined(separator: ", ")
                    skippedCategoriesMessage = "Skipped (no models): \(names)"
                }

                run.results = output.results
                run.status = output.results.allSatisfy(\.metrics.didSucceed) ? .completed : .failed
                run.completedAt = Date()
            } catch is CancellationError {
                run.status = .cancelled
                run.completedAt = Date()
            } catch let error as BenchmarkRunnerError {
                run.status = .failed
                run.completedAt = Date()
                errorMessage = error.localizedDescription
            } catch {
                run.status = .failed
                run.completedAt = Date()
                errorMessage = error.localizedDescription
            }

            // Only save if we got results or it was explicitly cancelled/failed
            if !run.results.isEmpty || run.status != .running {
                store.save(run: run)
            }
            loadPastRuns()
            isRunning = false
        }
    }

    func cancel() {
        runTask?.cancel()
        runTask = nil
    }

    func clearAllResults() {
        store.clearAll()
        pastRuns = []
    }

    // MARK: - Copy to Clipboard

    func copyToClipboard(run: BenchmarkRun, format: BenchmarkExportFormat) {
        #if canImport(UIKit)
        let report = BenchmarkReportFormatter.formattedString(run: run, format: format)
        UIPasteboard.general.string = report
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        copiedToastMessage = "\(format.displayName) copied!"
        // Auto-dismiss after 2s — cancel any previous dismiss task
        toastTask?.cancel()
        toastTask = Task {
            try? await Task.sleep(for: .seconds(2))
            copiedToastMessage = nil
        }
        #endif
    }

    // MARK: - File Export

    func shareJSON(run: BenchmarkRun) -> URL {
        BenchmarkReportFormatter.writeJSON(run: run)
    }

    func shareCSV(run: BenchmarkRun) -> URL {
        BenchmarkReportFormatter.writeCSV(run: run)
    }

    // MARK: - Helpers

    private func makeDeviceInfo() -> BenchmarkDeviceInfo {
        if let sysInfo = DeviceInfoService.shared.deviceInfo {
            return BenchmarkDeviceInfo.fromSystem(sysInfo)
        }
        return BenchmarkDeviceInfo(
            modelName: "Unknown",
            chipName: "Unknown",
            totalMemoryBytes: Int64(ProcessInfo.processInfo.physicalMemory),
            availableMemoryBytes: SyntheticInputGenerator.availableMemoryBytes(),
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString
        )
    }
}
