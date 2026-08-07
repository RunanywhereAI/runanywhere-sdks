//
//  BackgroundDownloadCoordinator.swift
//  RunAnywhere SDK
//
//  Keeps model downloads alive while the app is backgrounded, matching the
//  Android foreground-service behavior. Transfer is the only responsibility that
//  moves to Swift: commons still owns planning, destinations, extraction, and
//  the registry. The coordinator downloads each planned file straight to its
//  final destination path via a background URLSession, then hands off to the
//  commons start+poll path, which detects the already-complete files
//  (download_orchestrator.cpp: `already_complete` → skip fetch → finalize +
//  self_heal_registry) and updates the registry without any network I/O.
//
//  ## Why there is no retry loop here
//
//  Commons already owns one, and it is shared by all five SDKs:
//  `execute_stream_with_retry` in download_orchestrator.cpp retries transient
//  network failures four times with exponential backoff, recomputing the offset
//  from the "<dest>.part" sidecar each attempt. Re-implementing that policy in
//  Swift would mean two retry schedules that drift apart the first time either
//  is tuned. So an interrupted transfer here does exactly one thing: it takes
//  custody of the resume blob and reports the failure honestly. The next start
//  continues from that blob (see `startTasks`), and everything about *when* to
//  retry stays a single decision made in one place.
//
//  Note that the two resume mechanisms are disjoint by construction, which is
//  why the blob custody below matters so much. Commons resumes by measuring a
//  "<dest>.part" file it wrote itself; `URLSessionDownloadTask` keeps its bytes
//  in a private temp file that nothing outside CFNetwork can measure. If this
//  coordinator loses the blob, those bytes are unreachable from either side and
//  the file restarts from zero.
//

import CryptoKit
import Foundation
import os

/// Per-file payload carried in `URLSessionTask.taskDescription` so a background
/// session restored after an app relaunch can place bytes and finalize without
/// any in-memory state.
private struct BackgroundDownloadFile: Codable {
    let modelID: String
    let destinationPath: String
    let expectedBytes: Int64
    let sha256: String
}

private struct ModelTransfer {
    let plan: RADownloadPlanResult
    let onProgress: ((RADownloadProgress) async -> Void)?
    /// `nil` for a transfer adopted from a previous run of the app: the bytes are
    /// still moving in `nsurlsessiond`, but the caller that started them is gone,
    /// so completion drives the commons finalize directly instead of resuming
    /// anyone. Everything else — progress accounting, notifications, blob
    /// custody — is identical, which is the point of modelling it this way
    /// rather than as a separate code path.
    let continuation: CheckedContinuation<Void, Error>?
    var fileBytes: [Int: Int64] = [:]
    /// When the transfer began, for the throughput average.
    let startedAt = Date()
    /// Bytes already on disk when this transfer started. Excluded from the rate
    /// so a resumed download does not report a huge phantom speed in its first
    /// second from bytes it never actually moved.
    var preexistingBytes: Int64 = 0
    /// Per-file bytes that a resumed task inherited from a previous attempt,
    /// discovered on that file's first progress callback. Excluded from the rate
    /// for the same reason as `preexistingBytes`: a resume that starts at 1.4 GB
    /// would otherwise report several gigabytes per second for one sample.
    var resumedBytes: [Int: Int64] = [:]

    var isAdopted: Bool { continuation == nil }
}

final class BackgroundDownloadCoordinator: NSObject, @unchecked Sendable {
    static let shared = BackgroundDownloadCoordinator()

    static let sessionIdentifier = "com.runanywhere.downloads"

    /// A `DispatchQueue` rather than an actor because every mutation below happens
    /// inside a synchronous `URLSession` delegate callback. Hopping those onto an
    /// actor would make each one a suspension point, and two chunks of the same
    /// file could then report progress out of order.
    private let stateQueue = DispatchQueue(label: "com.runanywhere.downloads.state")
    private var transfers: [String: ModelTransfer] = [:]
    private var enabledFlag = true
    private var notificationsFlag = true
    private var backgroundCompletionHandler: (() -> Void)?
    /// Models whose transfer this process has deliberately torn down.
    ///
    /// Cancelling a task is not instantaneous: progress and completion callbacks
    /// already in the delegate queue still arrive afterwards. Without this marker
    /// they would re-adopt the transfer from its persisted plan and a cancelled
    /// download would carry on reporting progress and posting notifications. It
    /// also carries the "cancel arrived before `prefetch` installed its
    /// continuation" case, so that continuation fails fast instead of hanging.
    ///
    /// Cleared by the next `prefetch`, which is what "a new attempt has begun"
    /// means here.
    private var suppressedModels: Set<String> = []
    /// Models whose partial bytes were deliberately thrown away because the result
    /// was corrupt. Narrower than `suppressedModels` and answers a different
    /// question: a cancel suppresses the transfer but *keeps* its blob, whereas
    /// these must never have one filed, or the next attempt would resume straight
    /// back into the same bad file.
    private var discardedModels: Set<String> = []

    private let logger = SDKLogger.download
    /// Everything this transfer leaves on disk so a later attempt — or a later
    /// process — can pick it up. See `DownloadPersistenceStore`.
    private let store = DownloadPersistenceStore()

    /// The session is built on first use behind a lock rather than with `lazy var`.
    /// `lazy` is not thread-safe, and this object is reached from the downloading
    /// task, the cancelling task, and the app delegate's background-events
    /// callback. Two of those racing the lazy initializer would each construct a
    /// `URLSession` for the *same* background identifier; only one can own the
    /// daemon's tasks, so the loser's `getAllTasks` comes back empty and its
    /// cancel silently does nothing.
    private let sessionLock = OSAllocatedUnfairLock<URLSession?>(initialState: nil)

    private var session: URLSession {
        sessionLock.withLock { stored in
            if let stored { return stored }
            let config = URLSessionConfiguration.background(withIdentifier: Self.sessionIdentifier)
            config.sessionSendsLaunchEvents = true
            config.isDiscretionary = false
            config.waitsForConnectivity = true
            // Serial on purpose: the delegate callbacks mutate the transfer table
            // and their order is the progress order a caller sees.
            let queue = OperationQueue()
            queue.maxConcurrentOperationCount = 1
            let created = URLSession(configuration: config, delegate: self, delegateQueue: queue)
            stored = created
            return created
        }
    }

    private override init() { super.init() }

    // MARK: - Configuration

    var isEnabled: Bool {
        get { stateQueue.sync { enabledFlag } }
        set { stateQueue.sync { enabledFlag = newValue } }
    }

    var notificationsEnabled: Bool {
        get { stateQueue.sync { notificationsFlag } }
        set { stateQueue.sync { notificationsFlag = newValue } }
    }

    /// A plan is background-eligible only when every file has a known size, a URL,
    /// and needs no extraction — extraction stays a commons-owned step, so those
    /// models fall back to the foreground path.
    ///
    /// The fallback is logged because it is otherwise invisible: a model that
    /// silently never uses the background session looks identical to one whose
    /// background session is broken, and the two need completely different fixes.
    func shouldHandle(_ plan: RADownloadPlanResult) -> Bool {
        guard isEnabled else { return false }
        guard !plan.files.isEmpty else {
            logger.info("Background download skipped: the plan has no files")
            return false
        }
        let ineligible = plan.files.first {
            $0.expectedBytes <= 0 || $0.requiresExtraction || $0.file.url.isEmpty
        }
        guard let ineligible else { return true }
        logger.info(
            "Background download skipped; using the commons transfer path",
            metadata: [
                "file": ineligible.file.filename,
                "reason": ineligible.requiresExtraction ? "requires extraction"
                    : (ineligible.file.url.isEmpty ? "no URL" : "unknown size")
            ]
        )
        return false
    }

    func registerBackgroundCompletionHandler(_ handler: @escaping () -> Void) {
        stateQueue.sync { backgroundCompletionHandler = handler }
        _ = session // force the background session to exist so events are delivered
    }

    // MARK: - Restoration after a process restart

    /// Re-adopt background transfers that outlived the process.
    ///
    /// A background `URLSession` keeps downloading inside `nsurlsessiond` after
    /// the app is suspended or killed, but its delegate callbacks are only
    /// delivered once the app recreates a session with the same identifier.
    /// Nothing does that on an ordinary relaunch —
    /// `handleEventsForBackgroundURLSession` fires only when the *system*
    /// relaunched the app to hand over events, not when the user taps the icon —
    /// so without this the bytes keep landing on disk while the SDK stays unaware
    /// of them, and the next `download(id:)` starts a second task racing the first
    /// into the same destination.
    ///
    /// Runs from Phase 2, after commons has discovered downloaded models, so a
    /// transfer that finished while the app was gone can be finalized against a
    /// populated registry instead of failing to find its own model.
    func restoreInterruptedTransfers() async {
        guard isEnabled else { return }

        // Reading `allTasks` is what actually reconnects this process to the
        // daemon's tasks; the returned list is a by-product.
        let liveModelIDs = Set(await session.allTasks.compactMap { decode($0.taskDescription)?.modelID })
        for modelID in liveModelIDs {
            _ = adoptedTransfer(modelID: modelID)
        }
        if !liveModelIDs.isEmpty {
            logger.info("Adopted \(liveModelIDs.count) background download(s) still in flight")
        }

        // A persisted plan whose files are all on disk, with no task still
        // running, is a transfer that completed while the app was not running:
        // the bytes landed but the registry was never told. Finalize it now
        // rather than making the user tap download on a model that is already
        // fully downloaded.
        for modelID in store.interruptedModelIDs() where !liveModelIDs.contains(modelID) {
            guard let files = store.loadPlan(modelID: modelID)?.files,
                  allFilesComplete(files) else { continue }
            logger.info("Finalizing a background download that completed while the app was closed",
                        metadata: ["modelId": modelID])
            completeTransfer(modelID: modelID)
        }
    }

    // MARK: - Prefetch (in-process)

    /// Download every planned file to its final destination. Returns once the
    /// bytes are on disk and verified; the caller then runs the commons
    /// start+poll finalize. Throws on transfer or verification failure.
    func prefetch(
        plan: RADownloadPlanResult,
        model: RAModelInfo,
        onProgress: ((RADownloadProgress) async -> Void)?
    ) async throws {
        let modelID = model.id
        store.persistPlan(plan, modelID: modelID)
        // A new attempt begins here, so anything the previous one was suppressing
        // stops applying. Cleared before the awaits below rather than inside the
        // continuation, so that a cancel arriving *during* those awaits is still
        // seen by the continuation and correctly aborts this attempt.
        stateQueue.sync {
            suppressedModels.remove(modelID)
            discardedModels.remove(modelID)
        }

        if notificationsEnabled {
            await DownloadNotifier.shared.requestAuthorizationIfNeeded()
        }

        // Ask the session what it is already moving before planning new tasks. A
        // background task survives the process, so on a relaunch — or on a second
        // `download(id:)` for a model whose first attempt is still running — the
        // destination may already have a live task, and starting another means two
        // tasks racing to move their temp file onto the same path.
        let inFlight = await inFlightDestinations(modelID: modelID)

        nonisolated(unsafe) let progressCallback = onProgress
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                // `onCancel` fires *before* this closure when the task was already
                // cancelled on entry — which is reachable, because several awaits
                // precede it. The teardown would then find no transfer to resume
                // and this continuation would be stranded forever, hanging the
                // caller's download stream. The suppression marker is the note the
                // teardown leaves behind for exactly that ordering.
                let start: Bool = stateQueue.sync {
                    if suppressedModels.contains(modelID) { return false }
                    transfers[modelID] = ModelTransfer(
                        plan: plan,
                        onProgress: progressCallback,
                        continuation: continuation
                    )
                    return true
                }
                guard start else {
                    continuation.resume(throwing: CancellationError())
                    return
                }
                startTasks(for: plan, modelID: modelID, skipping: inFlight)
            }
        } onCancel: {
            // `onCancel` is synchronous, but preserving the partial bytes is not:
            // the resume blob only exists once CFNetwork hands it back. So the
            // teardown runs detached and resumes the caller's continuation only
            // after the blob is on disk. Delivering `CancellationError` first
            // would mean `isResumable(id:)` — which a UI calls the instant a
            // download stops — reads the blob directory before anything has been
            // written to it, and tells the user their bytes are gone.
            //
            // Detached rather than `Task {}` so it is explicit that this teardown
            // must outlive the cancelled task it is cleaning up after.
            Task.detached { await self.cancelTransfer(modelID: modelID) }
        }
    }

    private func startTasks(for plan: RADownloadPlanResult, modelID: String, skipping inFlight: Set<String>) {
        // Bytes that were already complete before this transfer began, so the
        // throughput average measures only what this transfer actually moves.
        let alreadyOnDisk = plan.files
            .filter { fileSize($0.destinationPath) == $0.expectedBytes }
            .reduce(Int64(0)) { $0 + $1.expectedBytes }
        stateQueue.sync { transfers[modelID]?.preexistingBytes = alreadyOnDisk }

        for file in plan.files {
            if fileSize(file.destinationPath) == file.expectedBytes { continue }
            // Already moving in the daemon from a previous run — adopting it is
            // strictly better than starting a duplicate.
            if inFlight.contains(file.destinationPath) { continue }
            guard let url = URL(string: file.file.url) else { continue }

            let payload = BackgroundDownloadFile(
                modelID: modelID,
                destinationPath: file.destinationPath,
                expectedBytes: file.expectedBytes,
                sha256: file.checksumSha256
            )
            // A background session bypasses the commons HTTP dispatcher, which
            // is where `Authorization` is normally attached, so a gated
            // Hugging Face URL has to be authenticated here or it 401s on the
            // default download path while working on every other path.
            // Continue from a previous attempt when there is a resume blob for this
            // file. `withResumeData:` replays the byte range the server already
            // sent, so an interrupted multi-gigabyte transfer costs only what is
            // left. The blob is consumed either way: a stale one (the server no
            // longer honors it) must not be retried forever, and the plain request
            // below is the correct fallback.
            let task: URLSessionDownloadTask
            if let resumeData = store.loadResumeData(
                modelID: modelID, destinationPath: file.destinationPath
            ) {
                task = session.downloadTask(withResumeData: resumeData)
                store.clearResumeData(modelID: modelID, destinationPath: file.destinationPath)
            } else {
                var request = URLRequest(url: url)
                if let bearer = HuggingFaceAuth.bearer(for: url) {
                    request.setValue(bearer, forHTTPHeaderField: "Authorization")
                }
                task = session.downloadTask(with: request)
            }
            task.taskDescription = encode(payload)
            task.resume()
        }

        // Every file was already on disk (e.g. a re-issue after finalize was
        // interrupted); complete immediately.
        if plan.files.allSatisfy({ fileSize($0.destinationPath) == $0.expectedBytes }) {
            completeTransfer(modelID: modelID)
        }
    }

    /// Destination paths this model already has a live task for.
    private func inFlightDestinations(modelID: String) async -> Set<String> {
        var destinations: Set<String> = []
        for task in await session.allTasks {
            guard task.state == .running || task.state == .suspended,
                  let payload = decode(task.taskDescription),
                  payload.modelID == modelID else { continue }
            destinations.insert(payload.destinationPath)
        }
        return destinations
    }

    /// Stop the transfer but keep everything needed to continue it later.
    ///
    /// The plan is deliberately *not* cleared here, unlike on completion or an
    /// unrecoverable failure: the plan plus the per-file resume blobs are exactly
    /// what a later attempt needs, and discarding them is what used to make a
    /// cancel throw away the bytes. The caller's `CancellationError` is delivered
    /// last, once the blobs are settled, so a UI that immediately asks whether the
    /// download is resumable gets the answer that matches what is on disk.
    func cancelTransfer(modelID: String) async {
        // Marked before the cancels, not after: callbacks for tasks torn down
        // below are already queued, and a late one must not resurrect the transfer.
        // It also covers the case where the cancel beat `prefetch` to the transfer
        // table, so that continuation fails fast rather than awaiting a resume
        // that will never come.
        stateQueue.sync { _ = suppressedModels.insert(modelID) }
        await cancelTasks(for: modelID, preservingResumeData: true)
        let transfer = stateQueue.sync { transfers.removeValue(forKey: modelID) }
        transfer?.continuation?.resume(throwing: CancellationError())
    }

    /// Stop every task belonging to `modelID`, awaiting resume-blob custody.
    ///
    /// The await matters: `cancel(byProducingResumeData:)` hands the blob back
    /// through a callback, so returning before it lands means the bytes look lost
    /// to anything that checks straight afterwards.
    private func cancelTasks(for modelID: String, preservingResumeData: Bool) async {
        for task in await session.allTasks {
            guard let payload = decode(task.taskDescription), payload.modelID == modelID else { continue }
            guard preservingResumeData, let download = task as? URLSessionDownloadTask else {
                task.cancel()
                continue
            }
            let resumeData: Data? = await withCheckedContinuation { continuation in
                download.cancel { continuation.resume(returning: $0) }
            }
            guard let resumeData else {
                // The server did not give us a resumable response (no
                // ETag/Accept-Ranges, or the bytes were too few to be worth it).
                // Logged rather than swallowed, because it is the difference
                // between a retry costing the remainder and costing the whole file.
                logger.info(
                    "Download stopped without resume data",
                    metadata: ["modelId": payload.modelID, "file": payload.destinationPath]
                )
                continue
            }
            store.storeResumeData(
                resumeData,
                modelID: payload.modelID,
                destinationPath: payload.destinationPath,
                bytesOnDisk: observedBytes(modelID: payload.modelID, destinationPath: payload.destinationPath)
            )
            logger.info(
                "Download stopped with resume data",
                metadata: ["modelId": payload.modelID, "blobBytes": String(resumeData.count)]
            )
        }
    }

    // MARK: - Completion / failure

    private func completeTransfer(modelID: String) {
        let transfer = stateQueue.sync { transfers.removeValue(forKey: modelID) }
        store.clearPlan(modelID: modelID)
        // Every byte is on disk; a stale resume blob would only mislead a later
        // attempt into continuing a file that is already finished.
        store.clearResumeData(modelID: modelID)

        if let continuation = transfer?.continuation {
            continuation.resume()
            return
        }

        // No in-process awaiter: the transfer was adopted from a previous run of
        // the app, so the coordinator itself drives the commons finalize.
        Task {
            do {
                _ = try await RunAnywhere.finalizeBackgroundDownload(modelID: modelID)
                await notify { await $0.notifyCompleted(modelID: modelID) }
            } catch {
                let message = error.localizedDescription
                await notify { await $0.notifyFailed(modelID: modelID, message: message) }
            }
        }
    }

    /// Fail the transfer, keeping partial bytes when a retry could still use them.
    ///
    /// `recoverable` is false only for a corrupt result — a bad HTTP status, a size
    /// mismatch, or a bad checksum — where the bytes on disk are known to be wrong
    /// and continuing from them would reproduce the same bad file. A network drop
    /// is the opposite case: the bytes are good, so the resume blobs are kept and
    /// the retry costs only the remainder.
    ///
    /// Called from synchronous delegate callbacks, so the actual teardown is
    /// detached; the error reaches the caller only once blob custody has settled,
    /// for the same reason as cancel.
    private func failTransfer(modelID: String, message: String, recoverable: Bool = true) {
        Task.detached {
            await self.finishFailedTransfer(modelID: modelID, message: message, recoverable: recoverable)
        }
    }

    private func finishFailedTransfer(modelID: String, message: String, recoverable: Bool) async {
        // Both marks go up before the cancels below, because the callbacks for the
        // tasks they tear down are already queued: `suppressed` stops a late one
        // resurrecting the transfer, and `discarded` stops a sibling's
        // `didCompleteWithError` re-filing a blob for bytes we just judged wrong.
        stateQueue.sync {
            _ = suppressedModels.insert(modelID)
            if !recoverable { _ = discardedModels.insert(modelID) }
        }
        await cancelTasks(for: modelID, preservingResumeData: recoverable)
        let transfer = stateQueue.sync { transfers.removeValue(forKey: modelID) }
        if !recoverable {
            store.clearPlan(modelID: modelID)
            store.clearResumeData(modelID: modelID)
        }
        let error = SDKException(code: .downloadFailed, message: message, category: .network)
        transfer?.continuation?.resume(throwing: error)
        await notify { await $0.notifyFailed(modelID: modelID, message: message) }
    }

    // MARK: - Helpers

    private func notify(_ body: (DownloadNotifier) async -> Void) async {
        guard notificationsEnabled else { return }
        await body(DownloadNotifier.shared)
    }

    /// The live transfer for `modelID`, adopting the persisted plan when the
    /// bytes are moving but the caller that started them is gone.
    ///
    /// Without this, a delegate callback arriving after a relaunch has no plan to
    /// attribute bytes to, so a multi-file model reports only the file it happens
    /// to hear about and completion never fires.
    @discardableResult
    private func adoptedTransfer(modelID: String) -> ModelTransfer? {
        let lookup = stateQueue.sync { (transfers[modelID], suppressedModels.contains(modelID)) }
        if let existing = lookup.0 { return existing }
        // A transfer this process tore down keeps its plan on disk on purpose, so
        // the plan alone is not permission to adopt: without this check a delegate
        // callback still draining behind a cancel would resurrect the transfer and
        // a cancelled download would go on reporting progress.
        guard !lookup.1, let plan = store.loadPlan(modelID: modelID) else { return nil }
        let alreadyOnDisk = plan.files
            .filter { fileSize($0.destinationPath) == $0.expectedBytes }
            .reduce(Int64(0)) { $0 + $1.expectedBytes }
        return stateQueue.sync {
            if let existing = transfers[modelID] { return existing }
            var adopted = ModelTransfer(plan: plan, onProgress: nil, continuation: nil)
            adopted.preexistingBytes = alreadyOnDisk
            transfers[modelID] = adopted
            return adopted
        }
    }

    /// The most recent byte count this process observed for one planned file, or 0
    /// when it never saw a progress callback for it.
    ///
    /// Lives here rather than in the store because it is a question about the live
    /// transfer table, and it is what lets a resume blob be filed with a truthful
    /// byte count beside it.
    private func observedBytes(modelID: String, destinationPath: String) -> Int64 {
        stateQueue.sync {
            guard let transfer = transfers[modelID],
                  let index = transfer.plan.files.firstIndex(where: {
                      $0.destinationPath == destinationPath
                  }) else { return 0 }
            return transfer.fileBytes[index] ?? 0
        }
    }

    private func allFilesComplete(_ files: [RADownloadFilePlan]) -> Bool {
        files.allSatisfy { fileSize($0.destinationPath) == $0.expectedBytes }
    }

    private func fileSize(_ path: String) -> Int64 {
        let attrs = try? FileManager.default.attributesOfItem(atPath: path)
        return (attrs?[.size] as? Int64) ?? -1
    }

    private func encode(_ payload: BackgroundDownloadFile) -> String? {
        guard let data = try? JSONEncoder().encode(payload) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func decode(_ description: String?) -> BackgroundDownloadFile? {
        guard let data = description?.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(BackgroundDownloadFile.self, from: data)
    }

    private func verifiedChecksum(at url: URL, expected: String) -> Bool {
        guard !expected.isEmpty else { return true }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try? handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
        return digest.caseInsensitiveCompare(expected) == .orderedSame
    }

    /// How many bytes an interrupted attempt left recoverable, so a caller can
    /// offer "Resume" only when resuming would genuinely save work.
    ///
    /// Counts files already complete on disk, plus the checkpointed byte count of
    /// files that hold a resume blob. A blob with no checkpoint means the bytes
    /// are recoverable but their count was never observed — the process died
    /// before the first progress callback — so it contributes a nominal 1 rather
    /// than 0, because 0 would tell the caller the bytes are gone when they are not.
    ///
    /// Zero when no plan is persisted, which is the normal state for a model that
    /// has never been downloaded or whose download finished.
    func resumableBytes(modelID: String) -> Int64 {
        let plan = stateQueue.sync { transfers[modelID]?.plan } ?? store.loadPlan(modelID: modelID)
        guard let plan else { return 0 }
        return plan.files.reduce(Int64(0)) { total, file in
            if fileSize(file.destinationPath) == file.expectedBytes {
                return total + file.expectedBytes
            }
            guard store.loadResumeData(modelID: modelID, destinationPath: file.destinationPath) != nil else {
                return total
            }
            let checkpoint = store.resumeCheckpoint(modelID: modelID, destinationPath: file.destinationPath)
            return total + max(checkpoint ?? 1, 1)
        }
    }
}

// MARK: - URLSessionDownloadDelegate

extension BackgroundDownloadCoordinator: URLSessionDownloadDelegate {
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let payload = decode(downloadTask.taskDescription) else { return }

        // All three of these mean the bytes we hold are wrong, not merely
        // incomplete, so the partial state is discarded — a resume would only
        // rebuild the same bad file.
        //
        // The status check comes first because a background session bypasses the
        // commons HTTP dispatcher and therefore its error handling too: a gated
        // Hugging Face repo answers 401 with a short HTML body, which arrives here
        // as a perfectly successful download. Without this it would be reported as
        // a size mismatch, sending the user to look at their disk instead of their
        // access token.
        if let response = downloadTask.response as? HTTPURLResponse,
           !(200...299).contains(response.statusCode) {
            failTransfer(
                modelID: payload.modelID,
                message: "Server returned HTTP \(response.statusCode) for \(payload.destinationPath)",
                recoverable: false
            )
            return
        }
        let expected = payload.expectedBytes
        if expected > 0, fileSize(location.path) != expected {
            failTransfer(
                modelID: payload.modelID,
                message: "Downloaded file size mismatch for \(payload.destinationPath)",
                recoverable: false
            )
            return
        }
        guard verifiedChecksum(at: location, expected: payload.sha256) else {
            failTransfer(
                modelID: payload.modelID,
                message: "Checksum verification failed for \(payload.destinationPath)",
                recoverable: false
            )
            return
        }

        let destination = URL(fileURLWithPath: payload.destinationPath)
        do {
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: location, to: destination)
        } catch {
            failTransfer(
                modelID: payload.modelID,
                message: "Could not store downloaded file: \(error.localizedDescription)"
            )
            return
        }

        // This file is done, so its resume blob is now a liability: a later
        // attempt that found it would try to continue a finished file.
        store.clearResumeData(modelID: payload.modelID, destinationPath: payload.destinationPath)

        // Adoption (not a bare plan read) on purpose: it is what refuses to
        // finalize a transfer the user already cancelled, even though this last
        // file happened to land.
        guard let files = adoptedTransfer(modelID: payload.modelID)?.plan.files,
              allFilesComplete(files) else { return }
        completeTransfer(modelID: payload.modelID)
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard let payload = decode(downloadTask.taskDescription) else { return }
        let modelID = payload.modelID

        // Adopt on first sight so a transfer restored after a relaunch reports the
        // same whole-plan progress as one this process started, rather than a bare
        // per-file percentage with no notion of the other files.
        guard let transfer = adoptedTransfer(modelID: modelID) else { return }
        let plan = transfer.plan
        guard let index = plan.files.firstIndex(where: {
            $0.destinationPath == payload.destinationPath
        }) else { return }

        let total = plan.totalBytes > 0 ? plan.totalBytes : plan.files.reduce(0) { $0 + $1.expectedBytes }
        let sample: DownloadProgressSample? = stateQueue.sync {
            guard var transfer = transfers[modelID] else { return nil }
            // An adopted task was already mid-flight when this process attached to
            // it, and `didResumeAtOffset` does not fire for it — the daemon never
            // "resumed" anything from our point of view. Its first sample is
            // therefore entirely inherited bytes, and counting them as moved would
            // report gigabytes per second for one tick right after launch.
            if transfer.isAdopted, transfer.fileBytes[index] == nil {
                transfer.resumedBytes[index] = totalBytesWritten
            }
            transfer.fileBytes[index] = totalBytesWritten
            transfers[modelID] = transfer
            let done = transfer.fileBytes.values.reduce(0, +) + transfer.preexistingBytes
            let inherited = transfer.resumedBytes.values.reduce(0, +)
            return DownloadProgressSample(
                modelID: modelID,
                bytesDone: done,
                bytesTotal: total,
                fileIndex: index,
                fileCount: plan.files.count,
                elapsed: Date().timeIntervalSince(transfer.startedAt),
                bytesMoved: done - transfer.preexistingBytes - inherited
            )
        }
        guard let sample else { return }
        nonisolated(unsafe) let callback = stateQueue.sync { transfers[modelID]?.onProgress }
        let progress = sample.asProto()
        let fraction = sample.fraction

        Task {
            await callback?(progress)
            await notify { await $0.notifyProgress(modelID: modelID, fraction: fraction) }
        }
    }

    /// Called when a task created with `withResumeData:` starts, reporting the byte
    /// offset the server agreed to continue from.
    ///
    /// This is the only place that offset is knowable. It is recorded so the rate
    /// calculation can exclude the inherited bytes, and so `bytesDownloaded`
    /// reflects the true total rather than only what this attempt moved — a resume
    /// should continue the progress bar, not restart it.
    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didResumeAtOffset fileOffset: Int64,
        expectedTotalBytes: Int64
    ) {
        guard let payload = decode(downloadTask.taskDescription) else { return }
        let modelID = payload.modelID
        stateQueue.sync {
            guard var transfer = transfers[modelID],
                  let index = transfer.plan.files.firstIndex(where: {
                      $0.destinationPath == payload.destinationPath
                  }) else { return }
            transfer.resumedBytes[index] = fileOffset
            transfers[modelID] = transfer
        }
        logger.debug(
            "Resumed download",
            metadata: ["modelId": modelID, "offset": String(fileOffset)]
        )
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        guard let error, let payload = decode(task.taskDescription) else { return }
        let nsError = error as NSError

        // Whatever ended this task — an explicit cancel, a dropped connection, the
        // system reclaiming the app — CFNetwork attaches the resume blob here
        // whenever the response was resumable. This is the *only* channel that
        // covers the interruptions nobody asked for, so the blob is filed before
        // the error is even classified. Relying on `cancel(byProducingResumeData:)`
        // alone meant a 3 GB model dropped at 90% by a network blip started over
        // from zero, which is exactly the case this coordinator exists to prevent.
        //
        // Skipped only for a model whose bytes were deliberately discarded as
        // corrupt; keeping a blob there would resume straight back into the bad file.
        let isDiscarded = stateQueue.sync { discardedModels.contains(payload.modelID) }
        if let resumeData = nsError.userInfo[NSURLSessionDownloadTaskResumeData] as? Data, !isDiscarded {
            store.storeResumeData(
                resumeData,
                modelID: payload.modelID,
                destinationPath: payload.destinationPath,
                bytesOnDisk: observedBytes(modelID: payload.modelID, destinationPath: payload.destinationPath)
            )
        }

        if nsError.code == NSURLErrorCancelled { return }
        failTransfer(modelID: payload.modelID, message: error.localizedDescription)
    }

    func urlSessionDidFinishEvents(forBackgroundURLSession session: URLSession) {
        nonisolated(unsafe) let handler = stateQueue.sync { () -> (() -> Void)? in
            let handler = backgroundCompletionHandler
            backgroundCompletionHandler = nil
            return handler
        }
        guard let handler else { return }
        DispatchQueue.main.async { handler() }
    }
}
