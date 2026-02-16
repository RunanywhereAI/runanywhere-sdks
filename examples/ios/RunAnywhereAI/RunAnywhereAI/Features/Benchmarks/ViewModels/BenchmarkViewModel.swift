//
//  BenchmarkViewModel.swift
//  RunAnywhereAI
//
//  Orchestrates benchmark execution, persistence, and export.
//

import Foundation
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

    // MARK: - Private

    private let runner = BenchmarkRunner()
    private let store = BenchmarkStore()
    private var runTask: Task<Void, Never>?

    // MARK: - Lifecycle

    func loadPastRuns() {
        pastRuns = store.loadRuns().reversed()
    }

    // MARK: - Run

    func runBenchmarks() {
        guard !isRunning else { return }
        isRunning = true
        errorMessage = nil
        progress = 0
        completedCount = 0
        totalCount = 0
        currentScenario = "Preparing..."
        currentModel = ""

        runTask = Task {
            let deviceInfo: BenchmarkDeviceInfo
            if let sysInfo = DeviceInfoService.shared.deviceInfo {
                deviceInfo = BenchmarkDeviceInfo.fromSystem(sysInfo)
            } else {
                deviceInfo = BenchmarkDeviceInfo(
                    modelName: "Unknown",
                    chipName: "Unknown",
                    totalMemoryBytes: Int64(ProcessInfo.processInfo.physicalMemory),
                    availableMemoryBytes: SyntheticInputGenerator.availableMemoryBytes(),
                    osVersion: ProcessInfo.processInfo.operatingSystemVersionString
                )
            }

            var run = BenchmarkRun(deviceInfo: deviceInfo)

            do {
                let results = try await runner.runBenchmarks(
                    categories: selectedCategories
                ) { [weak self] update in
                    Task { @MainActor in
                        self?.progress = update.progress
                        self?.completedCount = update.completedCount
                        self?.totalCount = update.totalCount
                        self?.currentScenario = update.currentScenario
                        self?.currentModel = update.currentModel
                    }
                }
                run.results = results
                run.status = .completed
                run.completedAt = Date()
            } catch is CancellationError {
                run.status = .cancelled
                run.completedAt = Date()
            } catch {
                run.status = .failed
                run.completedAt = Date()
                errorMessage = error.localizedDescription
            }

            store.save(run: run)
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

    // MARK: - Export

    func copyReportToClipboard(run: BenchmarkRun) {
        #if canImport(UIKit)
        let report = BenchmarkReportFormatter.formatMarkdown(run: run)
        UIPasteboard.general.string = report
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)
        #endif
    }

    func shareJSON(run: BenchmarkRun) -> URL {
        BenchmarkReportFormatter.writeJSON(run: run)
    }

    func shareCSV(run: BenchmarkRun) -> URL {
        BenchmarkReportFormatter.writeCSV(run: run)
    }
}
