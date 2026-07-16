//
//  ModelDownloadTracker.swift
//  RunAnywhereAI
//
//  Process-wide state for in-flight model downloads.
//

import Foundation
import RunAnywhere

/// Owns download state (progress + the cancellable `Task`) for each model being
/// downloaded, outside any single row view.
///
/// Why this exists:
/// - **Survives navigation** — the download continues (and stays visible) when the
///   user leaves the row that started it, instead of the `Task` becoming an
///   invisible orphan.
/// - **Cancellable** — the stored `Task` can be cancelled; `RunAnywhere.downloadModel`
///   is already Task-cancellation-aware and tears down the native worker.
/// - **De-duplicated** — the same model shown in two places (e.g. Recommended and
///   its family) can't start two concurrent downloads into the same partial file.
@MainActor
@Observable
final class ModelDownloadTracker {
    static let shared = ModelDownloadTracker()
    private init() {}

    private struct Active {
        var progress: Double
        let task: Task<Void, Never>
    }

    private var active: [String: Active] = [:]
    private var errors: [String: String] = [:]

    func isDownloading(_ modelID: String) -> Bool { active[modelID] != nil }
    func progress(_ modelID: String) -> Double { active[modelID]?.progress ?? 0 }
    func errorMessage(_ modelID: String) -> String? { errors[modelID] }
    func clearError(_ modelID: String) { errors[modelID] = nil }

    /// Start a download for `model` unless one is already in flight for it.
    /// `onFinished` runs on the main actor after a successful download.
    func start(_ model: RAModelInfo, onFinished: @escaping () -> Void) {
        let modelID = model.id
        guard active[modelID] == nil else { return }  // dedup: no second download
        errors[modelID] = nil

        let task = Task { [weak self] in
            do {
                _ = try await RunAnywhere.downloadModel(model) { progress in
                    await MainActor.run { self?.active[modelID]?.progress = Double(progress.overallProgress) }
                }
                self?.active[modelID] = nil
                onFinished()
            } catch is CancellationError {
                self?.active[modelID] = nil
            } catch {
                self?.active[modelID] = nil
                // Surface the SDK's descriptive failure (disk-full / network / checksum).
                self?.errors[modelID] = (error as? SDKException)?.message ?? error.localizedDescription
            }
        }
        active[modelID] = Active(progress: 0, task: task)
    }

    /// Cancel an in-flight download; the SDK stops the native worker.
    func cancel(_ modelID: String) {
        active[modelID]?.task.cancel()
        active[modelID] = nil
    }
}
