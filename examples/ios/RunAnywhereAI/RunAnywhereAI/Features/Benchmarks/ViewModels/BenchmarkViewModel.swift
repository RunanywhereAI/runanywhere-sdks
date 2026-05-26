//
//  BenchmarkViewModel.swift
//  RunAnywhereAI
//
//  Orchestrates benchmark execution, persistence, and export.
//

import Foundation
import RunAnywhere
import os
#if canImport(UIKit)
import UIKit
#endif

@MainActor
@Observable
final class BenchmarkViewModel {
    /// Grep marker for TC-19 harness (`test_workflows/scripts/_log_markers.sh`).
    private static let historySavedLogMarker = "Benchmark history saved"
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
    var availableModels: [BenchmarkCategory: [RAModelInfo]] = [:]

    /// Which model IDs the user has selected for benchmarking.
    /// Empty means "all models" (backwards-compatible default).
    var selectedModelIds: Set<String> = []

    // MARK: - Private

    private let runner = BenchmarkRunner()
    private let store = BenchmarkStore()
    private let logger = Logger(subsystem: "com.runanywhere.RunAnywhereAI", category: "Benchmarks")
    private var runTask: Task<Void, Never>?
    private var toastTask: Task<Void, Never>?

    // MARK: - Lifecycle

    func loadPastRuns() {
        pastRuns = store.loadRuns().reversed()
    }

    func refreshAvailableModels() {
        Task {
            await reloadAvailableModels()
        }
    }

    /// Resync registry paths from disk, then rebuild the grouped model picker state.
    private func reloadAvailableModels() async {
        await RunAnywhere.refreshModelRegistry()

        let listResult = await RunAnywhere.listModels()
        guard listResult.success else {
            availableModels = [:]
            return
        }
        let allModels = listResult.models.models
        var grouped: [BenchmarkCategory: [RAModelInfo]] = [:]
        for category in BenchmarkCategory.allCases {
            let models = BenchmarkRunner.downloadedModels(for: category, in: allModels)
            if !models.isEmpty {
                grouped[category] = models
            }
        }
        availableModels = grouped
        let availableIds = Set(grouped.values.flatMap { $0 }.map { $0.id })
        if selectedModelIds.isEmpty {
            selectedModelIds = availableIds
        } else {
            selectedModelIds = selectedModelIds.intersection(availableIds)
            if selectedModelIds.isEmpty, !availableIds.isEmpty {
                selectedModelIds = availableIds
            }
        }
    }

    /// Categories that have on-disk models after the latest registry rescan.
    private func categoriesReadyToRun() -> Set<BenchmarkCategory> {
        let withModels = selectedCategories.filter { !(availableModels[$0]?.isEmpty ?? true) }
        return withModels.isEmpty ? selectedCategories : withModels
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
            await executeBenchmarkRun()
        }
    }

    private func executeBenchmarkRun() async {
        await reloadAvailableModels()

        let availableIds = Set(availableModels.values.flatMap { $0 }.map { $0.id })
        if !availableIds.isEmpty {
            selectedModelIds = availableIds
        }
        let categoriesToRun = categoriesReadyToRun()

        let deviceInfo = makeDeviceInfo()
        var run = BenchmarkRun(deviceInfo: deviceInfo)

        do {
            let modelIds: Set<String>? = availableIds.isEmpty ? nil : availableIds
            let output = try await runner.runBenchmarks(
                categories: categoriesToRun,
                modelIds: modelIds
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

        // Persist completed work only — skip empty failed preflight runs so TC-19
        // grading waits for a real benchmark history entry.
        if !run.results.isEmpty || run.status == .cancelled {
            store.save(run: run)
            if !run.results.isEmpty {
                let duration = run.duration ?? 0
                logger.info(
                    "\(Self.historySavedLogMarker, privacy: .public) results=\(run.results.count) duration=\(duration, privacy: .public)s"
                )
            }
        }
        loadPastRuns()
        isRunning = false
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
