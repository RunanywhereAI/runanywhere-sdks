//
//  ModelDownloadTracker.swift
//  RunAnywhereAI
//
//  Process-wide state for in-flight model downloads.
//

import Foundation
import RunAnywhere

/// Which part of the job a download is doing right now.
///
/// `RunAnywhere.models.download(id:)` does not only move bytes: it verifies a
/// checksum and, for archive models, unpacks the result, and on a
/// multi-gigabyte model each of those runs for long enough to be mistaken for a
/// hang. This app used to read only `.progress` and drop the rest, so the bar
/// sat at 100% for the whole checksum with the same "Downloading" label it had
/// at 3%. Naming the phases is what lets the label tell the truth.
enum ModelDownloadPhase: Equatable {
    /// Accepted, but no byte count has arrived yet.
    case starting
    case downloading
    /// Checksumming what landed.
    case verifying
    /// Unpacking an archive. `percent` is 0...100 when the SDK reports it.
    case extracting(percent: Float?)
    /// The user asked to stop and the SDK has not confirmed yet.
    case cancelling

    /// What the row says it is doing.
    var label: String {
        switch self {
        case .starting: return "Starting…"
        case .downloading: return "Downloading"
        case .verifying: return "Checking download"
        case .extracting: return "Unpacking"
        case .cancelling: return "Cancelling…"
        }
    }

    /// True while bytes are actually moving, which is the only time a rate or a
    /// projected finish means anything.
    var isMovingBytes: Bool { self == .downloading }
}

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
    var phase: ModelDownloadPhase = .starting
    var bytesDone: Int64 = 0
    var bytesTotal: Int64 = 0
    var bytesPerSecond: Float?
    var etaSeconds: Int64?
    var retryAttempt: Int = 0
    var currentFileIndex: Int = 0
    var totalFiles: Int = 1
    var fileName: String?
    /// 0...1 across the whole transfer while bytes are moving, or nil when the
    /// total size is unknown and the bar must be indeterminate.
    var byteFraction: Float?

    init() {}

    init(_ snapshot: DownloadProgressSnapshot) {
        phase = .downloading
        bytesDone = snapshot.bytesDone
        bytesTotal = snapshot.bytesTotal
        bytesPerSecond = snapshot.bytesPerSecond
        etaSeconds = snapshot.etaSeconds
        retryAttempt = snapshot.retryAttempt
        currentFileIndex = snapshot.currentFileIndex
        totalFiles = snapshot.totalFiles
        fileName = snapshot.file
        byteFraction = snapshot.fraction
    }

    /// The bar position, or nil for an honestly indeterminate track.
    ///
    /// Only the download phase has a measurable position. Verification and the
    /// wind-down after a cancel have no length anyone can report, and leaving
    /// the bar full through them is what made a checksum look like a freeze —
    /// so they sweep instead, which says "working, length unknown" rather than
    /// "done".
    var fraction: Float? {
        switch phase {
        case .downloading: return byteFraction
        case .extracting(let percent): return percent.map { min(max($0 / 100, 0), 1) }
        case .starting, .verifying, .cancelling: return nil
        }
    }

    /// True when there is no position to show, so the caller sweeps the track.
    var isIndeterminate: Bool { fraction == nil }

    var percent: Int? { fraction.map { Int(($0 * 100).rounded()) } }

    /// "1.2 GB of 4.1 GB", or just the transferred amount when the total is
    /// unknown.
    var bytesLabel: String {
        guard bytesTotal > 0 else { return Self.formatBytes(bytesDone) }
        return "\(Self.formatBytes(bytesDone)) of \(Self.formatBytes(bytesTotal))"
    }

    /// "3.4 MB/s", or nil when nothing is moving or no rate has been measured.
    var speedLabel: String? {
        guard phase.isMovingBytes else { return nil }
        return bytesPerSecond.map { "\(Self.formatBytes(Int64($0)))/s" }
    }

    /// "2m 15s left", or nil when there is nothing trustworthy to project.
    var etaLabel: String? {
        guard phase.isMovingBytes, let etaSeconds, etaSeconds > 0 else { return nil }
        return "\(Self.formatDuration(etaSeconds)) left"
    }

    /// Which file of a multi-file model is moving, nil for the single-file case.
    ///
    /// Names the file when the SDK reports one, because on a 7-file MLX bundle
    /// "model.safetensors 2/7" says which part of the wait this is, where
    /// "File 2 of 7" only says how many are left. The count stays alongside it —
    /// the name alone gives no sense of progress.
    var fileCountLabel: String? {
        guard totalFiles > 1 else { return nil }
        let position = "\(currentFileIndex + 1)/\(totalFiles)"
        guard let fileName, !fileName.isEmpty else { return "File \(position)" }
        return "\(fileName) \(position)"
    }

    /// "Retry 2" once the transfer has recovered at least once, so a retry is
    /// never silent.
    var retryLabel: String? {
        retryAttempt > 0 ? "Retry \(retryAttempt)" : nil
    }

    /// The leading fragment of the detail line.
    ///
    /// The phase name is dropped while downloading — the byte pair already says
    /// what is happening and the row is narrow — but it leads every other phase,
    /// because "1.9 GB of 1.9 GB" on its own during a two-minute checksum is
    /// exactly the frozen-looking state the phases exist to explain.
    private var phaseLabel: String? {
        phase.isMovingBytes ? nil : phase.label
    }

    /// The bytes fragment, which stops being useful once bytes stop moving:
    /// during verification it can only ever read "N of N".
    private var byteFragment: String? {
        switch phase {
        case .starting, .cancelling: return nil
        case .downloading: return bytesLabel
        case .verifying, .extracting: return bytesTotal > 0 ? Self.formatBytes(bytesTotal) : nil
        }
    }

    /// The single line of detail under the progress bar.
    ///
    /// Ordered by what a waiting user looks for first — how much is left, then
    /// how fast, then when it will be done — and joined only from the parts that
    /// are actually known, so an early frame reads "12 MB of 4.1 GB" rather than
    /// "12 MB of 4.1 GB · 0 B/s · 0s left".
    var detailLine: String {
        Self.join([phaseLabel, byteFragment, speedLabel, etaLabel, fileCountLabel, retryLabel])
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
    /// The phase name and a retry marker are never dropped: one says which job is
    /// running at all, the other is the only signal that something went wrong and
    /// recovered, and hiding either would misrepresent the transfer.
    /// Ordered longest-first, with consecutive duplicates removed: early in a
    /// transfer there is no rate or ETA yet, so several variants render the same
    /// text and only the first is worth offering.
    var detailLineVariants: [String] {
        var seen: Set<String> = []
        return [
            [phaseLabel, byteFragment, speedLabel, etaLabel, fileCountLabel, retryLabel],
            [phaseLabel, byteFragment, speedLabel, etaLabel, retryLabel],
            [phaseLabel, byteFragment, etaLabel, retryLabel],
            [phaseLabel, etaLabel ?? byteFragment, retryLabel]
        ]
        .map(Self.join)
        .filter { !$0.isEmpty && seen.insert($0).inserted }
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

    /// The full snapshot a row renders — bytes, rate, ETA, and phase.
    ///
    /// The only read accessor, on purpose. There used to be an `isDownloading`
    /// predicate and a `progress` fraction beside it; neither had a caller, and
    /// `progress` returned 0 for a transfer whose position is genuinely unknown,
    /// which now contradicts `ModelDownloadProgress.fraction` reporting nil for
    /// exactly that case. `detail(_:) != nil` answers the first question and
    /// `detail(_:)?.fraction` the second, without a second definition of either
    /// that can drift.
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
            await syncResumable(modelID)
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
    ///
    /// Every `DownloadEvent` case is handled, and that is the point rather than a
    /// formality: the stream reports `.failed` as an *event* and then finishes
    /// normally, so a loop that only reads `.progress` falls out the bottom of a
    /// failed download and calls `onFinished` — announcing a model the user does
    /// not have. The phases are handled for the same reason in reverse: a
    /// checksum on a multi-gigabyte file is minutes of work that a
    /// `.progress`-only loop renders as a frozen bar.
    func start(_ model: RAModelInfo, onFinished: @escaping () -> Void) {
        let modelID = model.id
        guard active[modelID] == nil else { return }  // dedup: no second download
        errors[modelID] = nil

        let task = Task { [weak self] in
            // Cancelled until proven otherwise. `models.download(id:)` always
            // ends with a terminal event — except when this side tears the
            // stream down, because cancelling the consuming task terminates the
            // sequence and the `.cancelled` the SDK yields next is dropped on
            // the floor. Defaulting to success there is what made a cancelled
            // download call `onFinished` and announce a model the user stopped.
            var outcome: Outcome = .cancelled
            do {
                for try await event in try await RunAnywhere.models.download(id: modelID) {
                    guard let self else { return }
                    if let terminal = self.fold(event, into: modelID) { outcome = terminal }
                }
            } catch is CancellationError {
                outcome = .cancelled
            } catch {
                outcome = .failed((error as? SDKException)?.message ?? error.localizedDescription)
            }
            await self?.finish(modelID, outcome: outcome, onFinished: onFinished)
        }
        active[modelID] = Active(progress: ModelDownloadProgress(), task: task)
    }

    /// How a download stream ended, so the wind-down happens in exactly one place.
    private enum Outcome {
        case succeeded
        case cancelled
        case failed(String)
    }

    /// Fold one stream event into the row's state, returning an `Outcome` only
    /// for the events that end the download.
    ///
    /// Split out from `start` so the loop there reads as "consume events, keep
    /// the last terminal one" and every phase is handled in one exhaustive
    /// switch — which is what makes a newly added `DownloadEvent` case a compile
    /// error here rather than a silently ignored state.
    private func fold(_ event: DownloadEvent, into modelID: String) -> Outcome? {
        switch event {
        case .started:
            setPhase(.starting, for: modelID)
        case .progress(let snapshot):
            apply(ModelDownloadProgress(snapshot), to: modelID)
        case .verifying:
            setPhase(.verifying, for: modelID)
        case .extracting(_, _, let percent):
            setPhase(.extracting(percent: percent), for: modelID)
        case .completed:
            return .succeeded
        case .cancelled:
            return .cancelled
        case .failed(_, _, let error):
            // Surface the SDK's descriptive failure (disk-full / network /
            // checksum) rather than a generic "download failed".
            return .failed(error.message)
        }
        return nil
    }

    private func finish(_ modelID: String, outcome: Outcome, onFinished: @escaping () -> Void) async {
        active[modelID] = nil
        switch outcome {
        case .succeeded:
            resumable.remove(modelID)
            onFinished()
        case .cancelled:
            // Whether bytes survived is the SDK's answer, not an assumption
            // here: a cancel keeps them, but a checksum failure deliberately
            // discards them.
            await syncResumable(modelID)
        case .failed(let message):
            await syncResumable(modelID)
            errors[modelID] = message
        }
    }

    private func apply(_ progress: ModelDownloadProgress, to modelID: String) {
        // A cancel already asked for is not un-asked by a progress callback that
        // was in flight when the user tapped; letting one through would flip the
        // row back to "Downloading" and then to gone.
        guard active[modelID]?.progress.phase != .cancelling else { return }
        active[modelID]?.progress = progress
    }

    private func setPhase(_ phase: ModelDownloadPhase, for modelID: String) {
        guard var current = active[modelID]?.progress, current.phase != .cancelling else { return }
        current.phase = phase
        active[modelID]?.progress = current
    }

    /// Cancel an in-flight download. The SDK stops the transfer while preserving
    /// the partial bytes, so the next start continues from them.
    ///
    /// The row is not torn down here. Stopping a transfer takes as long as it
    /// takes CFNetwork to hand back the resume blob, and removing the row on the
    /// tap would show "Get" during that window — a label that is wrong twice
    /// over, because the download is still stopping and because the bytes it is
    /// about to preserve mean the next tap resumes. The row shows "Cancelling…"
    /// until the stream confirms, and `finish` is the single place it goes away.
    func cancel(_ modelID: String) {
        setPhase(.cancelling, for: modelID)
        active[modelID]?.task.cancel()
    }
}
