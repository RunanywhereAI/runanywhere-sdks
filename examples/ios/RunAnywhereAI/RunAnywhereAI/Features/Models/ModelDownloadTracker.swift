//
//  ModelDownloadTracker.swift
//  RunAnywhereAI
//
//  Process-wide state for in-flight model downloads.
//

import Foundation
import RunAnywhere

/// What a download looks like to the UI at one instant.
///
/// A model is hundreds of megabytes to several gigabytes, so a bare percentage
/// cannot tell a slow transfer from a stalled one — what a waiting user actually
/// wants is how fast it is going and how long is left. Every value here comes
/// from the SDK's `DownloadProgressSnapshot`, which the SDK fills from what C++
/// already measures. Nothing is re-derived from successive byte counts: a rate
/// computed from two UI samples disagrees with the transfer that knows its own
/// history.
///
/// Optional parts are absent when genuinely unknown rather than zero, so the UI
/// omits them instead of showing "0 B/s" while the connection is still opening.
///
/// Mirrors `DownloadProgressInfo` in the Android example so the two apps read
/// identically.
struct ModelDownloadProgress: Equatable {
    var bytesDone: Int64 = 0
    var bytesTotal: Int64 = 0
    var bytesPerSecond: Float?
    var etaSeconds: Int64?
    var retryAttempt: Int = 0
    var currentFileIndex: Int = 0
    var totalFiles: Int = 1
    /// 0...1, or nil when the total size is unknown and the bar must be
    /// indeterminate.
    var fraction: Float?

    init() {}

    init(_ snapshot: DownloadProgressSnapshot) {
        bytesDone = snapshot.bytesDone
        bytesTotal = snapshot.bytesTotal
        bytesPerSecond = snapshot.bytesPerSecond
        etaSeconds = snapshot.etaSeconds
        retryAttempt = snapshot.retryAttempt
        currentFileIndex = snapshot.currentFileIndex
        totalFiles = snapshot.totalFiles
        fraction = snapshot.fraction
    }

    /// True when the size is unknown, so the caller shows an indeterminate bar.
    var isIndeterminate: Bool { fraction == nil }

    var percent: Int? { fraction.map { Int(($0 * 100).rounded()) } }

    /// "1.2 GB of 4.1 GB", or just the transferred amount when the total is
    /// unknown.
    var bytesLabel: String {
        guard bytesTotal > 0 else { return Self.formatBytes(bytesDone) }
        return "\(Self.formatBytes(bytesDone)) of \(Self.formatBytes(bytesTotal))"
    }

    /// "3.4 MB/s", or nil when no rate has been measured yet.
    var speedLabel: String? {
        bytesPerSecond.map { "\(Self.formatBytes(Int64($0)))/s" }
    }

    /// "2m 15s left", or nil when there is nothing trustworthy to project.
    var etaLabel: String? {
        guard let etaSeconds, etaSeconds > 0 else { return nil }
        return "\(Self.formatDuration(etaSeconds)) left"
    }

    /// "File 2 of 3" for a multi-file model, nil for the single-file case.
    var fileCountLabel: String? {
        totalFiles > 1 ? "File \(currentFileIndex + 1) of \(totalFiles)" : nil
    }

    /// "Retry 2" once the transfer has recovered at least once, so a retry is
    /// never silent.
    var retryLabel: String? {
        retryAttempt > 0 ? "Retry \(retryAttempt)" : nil
    }

    /// The single line of detail under the progress bar.
    ///
    /// Ordered by what a waiting user looks for first — how much is left, then
    /// how fast, then when it will be done — and joined only from the parts that
    /// are actually known, so an early frame reads "12 MB of 4.1 GB" rather than
    /// "12 MB of 4.1 GB · 0 B/s · 0s left".
    var detailLine: String {
        Self.join([bytesLabel, speedLabel, etaLabel, fileCountLabel, retryLabel])
    }

    /// The same detail, progressively abbreviated — longest first.
    ///
    /// A download row is narrow (it shares a row with a model name), and the full
    /// line does not always fit. Truncating it is the wrong answer: clipping
    /// "37.9 MB/s · 37s left" to "37.9 MB/..." destroys the rate *and* the
    /// remaining time in one stroke, which is exactly the information the line
    /// exists to carry. So whole fields are dropped instead, in reverse order of
    /// what a waiting user needs:
    ///
    /// 1. **File count** goes first — it is context, not progress.
    /// 2. **Speed** next — the bar is already moving, so "how fast" matters less
    ///    than "how much longer".
    /// 3. **Bytes** last, leaving the ETA, because "37s left" answers the actual
    ///    question better than any byte pair.
    ///
    /// A retry marker is never dropped: it is the only signal that something went
    /// wrong and recovered, and silently hiding it would misrepresent the transfer.
    /// Ordered longest-first, with consecutive duplicates removed: early in a
    /// transfer there is no rate or ETA yet, so several variants render the same
    /// text and only the first is worth offering.
    var detailLineVariants: [String] {
        var seen: Set<String> = []
        return [
            [bytesLabel, speedLabel, etaLabel, fileCountLabel, retryLabel],
            [bytesLabel, speedLabel, etaLabel, retryLabel],
            [bytesLabel, etaLabel, retryLabel],
            [etaLabel ?? bytesLabel, retryLabel]
        ]
        .map(Self.join)
        .filter { seen.insert($0).inserted }
    }

    private static func join(_ parts: [String?]) -> String {
        parts.compactMap { $0 }.joined(separator: " · ")
    }

    /// Binary-prefix size with one decimal above a megabyte.
    ///
    /// Decimals are dropped for KB and B: a byte count that precise changes
    /// several times a second and reads as noise rather than information.
    private static func formatBytes(_ bytes: Int64) -> String {
        let kb = 1024.0
        let mb = kb * 1024
        let gb = mb * 1024
        let value = Double(bytes)
        if value >= gb { return String(format: "%.1f GB", value / gb) }
        if value >= mb { return String(format: "%.1f MB", value / mb) }
        if value >= kb { return String(format: "%.0f KB", value / kb) }
        return "\(bytes) B"
    }

    /// Coarse duration — "45s", "2m 15s", "1h 20m". Seconds are dropped past an
    /// hour, where they are noise.
    private static func formatDuration(_ seconds: Int64) -> String {
        if seconds >= 3600 { return "\(seconds / 3600)h \((seconds % 3600) / 60)m" }
        if seconds >= 60 { return "\(seconds / 60)m \(seconds % 60)s" }
        return "\(seconds)s"
    }
}

/// Owns download state (progress + the cancellable `Task`) for each model being
/// downloaded, outside any single row view.
///
/// Why this exists:
/// - **Survives navigation** — the download continues (and stays visible) when the
///   user leaves the row that started it, instead of the `Task` becoming an
///   invisible orphan.
/// - **Cancellable** — the stored `Task` can be cancelled; the download stream's
///   termination handler tears down the native worker.
/// - **De-duplicated** — the same model shown in two places (e.g. Recommended and
///   its family) can't start two concurrent downloads into the same partial file.
/// - **Retryable without losing bytes** — a failed model keeps its error until the
///   user acts, and restarting calls the same SDK verb, which resumes from the
///   partial rather than starting over (`models.download(id:)` is documented as
///   "starting a download IS resuming it").
@MainActor
@Observable
final class ModelDownloadTracker {
    static let shared = ModelDownloadTracker()
    private init() {}

    private struct Active {
        var progress: ModelDownloadProgress
        let task: Task<Void, Never>
    }

    private var active: [String: Active] = [:]
    private var errors: [String: String] = [:]
    /// Models the SDK reports as having recoverable bytes on disk.
    ///
    /// Only a cache of `RunAnywhere.models.isResumable(id:)`, because the verb is
    /// read during view layout and that query touches the filesystem. The SDK
    /// remains the source of truth; this never infers resumability on its own.
    private var resumable: Set<String> = []

    func isDownloading(_ modelID: String) -> Bool { active[modelID] != nil }

    /// Fraction 0...1 for a determinate bar. 0 when nothing is known yet.
    func progress(_ modelID: String) -> Double {
        Double(active[modelID]?.progress.fraction ?? 0)
    }

    /// The full snapshot, for a UI that shows bytes/speed/ETA.
    func detail(_ modelID: String) -> ModelDownloadProgress? { active[modelID]?.progress }

    func errorMessage(_ modelID: String) -> String? { errors[modelID] }
    func clearError(_ modelID: String) { errors[modelID] = nil }

    /// True when a previous attempt left bytes on disk, so the next attempt
    /// continues instead of restarting. Lets a retry button say so honestly.
    func canResume(_ modelID: String) -> Bool { resumable.contains(modelID) }

    /// Refresh the resumable cache for `modelIDs` from the SDK.
    ///
    /// Called when a model list appears, so an interrupted download is offered as
    /// "Resume" even on a cold launch — the session that started it is gone, but
    /// its bytes are not.
    func refreshResumable(_ modelIDs: [String]) async {
        for modelID in modelIDs where active[modelID] == nil {
            if await RunAnywhere.models.isResumable(id: modelID) {
                resumable.insert(modelID)
            } else {
                resumable.remove(modelID)
            }
        }
    }

    /// Re-read one model's resumable state after a download stops.
    private func syncResumable(_ modelID: String) async {
        if await RunAnywhere.models.isResumable(id: modelID) {
            resumable.insert(modelID)
        } else {
            resumable.remove(modelID)
        }
    }

    /// Start a download for `model` unless one is already in flight for it.
    /// `onFinished` runs on the main actor after a successful download.
    func start(_ model: RAModelInfo, onFinished: @escaping () -> Void) {
        let modelID = model.id
        guard active[modelID] == nil else { return }  // dedup: no second download
        errors[modelID] = nil

        let task = Task { [weak self] in
            do {
                for try await event in try await RunAnywhere.models.download(id: modelID) {
                    guard case .progress(let snapshot) = event else { continue }
                    self?.active[modelID]?.progress = ModelDownloadProgress(snapshot)
                }
                self?.active[modelID] = nil
                self?.resumable.remove(modelID)
                onFinished()
            } catch is CancellationError {
                self?.active[modelID] = nil
                // Whether bytes survived is the SDK's answer, not an assumption
                // here: a cancel keeps them, but a checksum failure deliberately
                // discards them.
                await self?.syncResumable(modelID)
            } catch {
                self?.active[modelID] = nil
                await self?.syncResumable(modelID)
                // Surface the SDK's descriptive failure (disk-full / network / checksum).
                self?.errors[modelID] = (error as? SDKException)?.message ?? error.localizedDescription
            }
        }
        active[modelID] = Active(progress: ModelDownloadProgress(), task: task)
    }

    /// Cancel an in-flight download. The SDK stops the transfer while preserving
    /// the partial bytes, so the next start continues from them.
    ///
    /// The resumable flag is not set here: the cancelled task's `catch` block asks
    /// the SDK once the transfer has actually wound down, which is the only point
    /// at which the on-disk answer is settled.
    func cancel(_ modelID: String) {
        active[modelID]?.task.cancel()
        active[modelID] = nil
    }
}
