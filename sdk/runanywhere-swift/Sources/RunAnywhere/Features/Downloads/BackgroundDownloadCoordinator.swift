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

import CryptoKit
import Foundation

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
    let continuation: CheckedContinuation<Void, Error>
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
}

final class BackgroundDownloadCoordinator: NSObject, @unchecked Sendable {
    static let shared = BackgroundDownloadCoordinator()

    static let sessionIdentifier = "com.runanywhere.downloads"

    private let stateQueue = DispatchQueue(label: "com.runanywhere.downloads.state")
    private var transfers: [String: ModelTransfer] = [:]
    private var enabledFlag = true
    private var notificationsFlag = true
    private var backgroundCompletionHandler: (() -> Void)?

    private let logger = SDKLogger.download

    private lazy var session: URLSession = {
        let config = URLSessionConfiguration.background(withIdentifier: Self.sessionIdentifier)
        config.sessionSendsLaunchEvents = true
        config.isDiscretionary = false
        config.waitsForConnectivity = true
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        return URLSession(configuration: config, delegate: self, delegateQueue: queue)
    }()

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
    func shouldHandle(_ plan: RADownloadPlanResult) -> Bool {
        guard isEnabled, !plan.files.isEmpty else { return false }
        return plan.files.allSatisfy {
            $0.expectedBytes > 0 && !$0.requiresExtraction && !$0.file.url.isEmpty
        }
    }

    func registerBackgroundCompletionHandler(_ handler: @escaping () -> Void) {
        stateQueue.sync { backgroundCompletionHandler = handler }
        _ = session // force the background session to exist so events are delivered
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
        persistPlan(plan, modelID: modelID)

        if notificationsEnabled {
            await DownloadNotifier.shared.requestAuthorizationIfNeeded()
        }

        nonisolated(unsafe) let progressCallback = onProgress
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                stateQueue.sync {
                    transfers[modelID] = ModelTransfer(
                        plan: plan,
                        onProgress: progressCallback,
                        continuation: continuation
                    )
                }
                startTasks(for: plan, modelID: modelID)
            }
        } onCancel: {
            cancelTransfer(modelID: modelID)
        }
    }

    private func startTasks(for plan: RADownloadPlanResult, modelID: String) {
        // Bytes that were already complete before this transfer began, so the
        // throughput average measures only what this transfer actually moves.
        let alreadyOnDisk = plan.files
            .filter { fileSize($0.destinationPath) == $0.expectedBytes }
            .reduce(Int64(0)) { $0 + $1.expectedBytes }
        stateQueue.sync { transfers[modelID]?.preexistingBytes = alreadyOnDisk }

        for file in plan.files {
            if fileSize(file.destinationPath) == file.expectedBytes { continue }
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
            if let resumeData = loadResumeData(
                modelID: modelID, destinationPath: file.destinationPath
            ) {
                task = session.downloadTask(withResumeData: resumeData)
                clearResumeData(modelID: modelID, destinationPath: file.destinationPath)
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

    /// Stop the transfer but keep everything needed to continue it later.
    ///
    /// The plan is deliberately *not* cleared here, unlike on completion or
    /// failure: the plan plus the per-file resume blobs are exactly what a later
    /// attempt needs, and discarding them is what used to make a cancel throw away
    /// the bytes.
    func cancelTransfer(modelID: String) {
        cancelTasks(for: modelID, preservingResumeData: true)
        let transfer = stateQueue.sync { transfers.removeValue(forKey: modelID) }
        transfer?.continuation.resume(throwing: CancellationError())
    }

    private func cancelTasks(for modelID: String, preservingResumeData: Bool = false) {
        session.getAllTasks { tasks in
            for task in tasks where self.decode(task.taskDescription)?.modelID == modelID {
                guard preservingResumeData,
                      let download = task as? URLSessionDownloadTask,
                      let payload = self.decode(task.taskDescription) else {
                    task.cancel()
                    continue
                }
                // The resume blob arrives asynchronously, so it is stored from the
                // completion handler rather than read back off the task.
                download.cancel { data in
                    guard let data else {
                        // The server did not give us a resumable response (no
                        // ETag/Accept-Ranges, or the bytes were too few to be
                        // worth it). Logged rather than swallowed, because it is
                        // the difference between a retry costing the remainder
                        // and costing the whole file.
                        self.logger.info(
                            "Download cancelled without resume data",
                            metadata: ["modelId": payload.modelID]
                        )
                        return
                    }
                    self.storeResumeData(
                        data,
                        modelID: payload.modelID,
                        destinationPath: payload.destinationPath
                    )
                    self.logger.info(
                        "Download cancelled with resume data",
                        metadata: ["modelId": payload.modelID, "bytes": String(data.count)]
                    )
                }
            }
        }
    }

    // MARK: - Completion / failure

    private func completeTransfer(modelID: String) {
        let transfer = stateQueue.sync { transfers.removeValue(forKey: modelID) }
        clearPersistedPlan(modelID: modelID)
        // Every byte is on disk; a stale resume blob would only mislead a later
        // attempt into continuing a file that is already finished.
        clearResumeData(modelID: modelID)

        if let transfer {
            transfer.continuation.resume()
            return
        }

        // No in-process awaiter: the app was relaunched to deliver background
        // events, so the coordinator itself drives the commons finalize.
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
    /// `recoverable` is false only for a corrupt result — a size mismatch or a bad
    /// checksum — where the bytes on disk are known to be wrong and continuing from
    /// them would reproduce the same bad file. A network drop is the opposite case:
    /// the bytes are good, so the resume blobs are kept and the retry costs only
    /// the remainder.
    private func failTransfer(modelID: String, message: String, recoverable: Bool = true) {
        cancelTasks(for: modelID, preservingResumeData: recoverable)
        let transfer = stateQueue.sync { transfers.removeValue(forKey: modelID) }
        if !recoverable {
            clearPersistedPlan(modelID: modelID)
            clearResumeData(modelID: modelID)
        }
        let error = SDKException(code: .downloadFailed, message: message, category: .network)
        transfer?.continuation.resume(throwing: error)
        Task { await notify { await $0.notifyFailed(modelID: modelID, message: message) } }
    }

    // MARK: - Helpers

    private func notify(_ body: (DownloadNotifier) async -> Void) async {
        guard notificationsEnabled else { return }
        await body(DownloadNotifier.shared)
    }

    private func planFiles(for modelID: String) -> [RADownloadFilePlan]? {
        if let plan = stateQueue.sync(execute: { transfers[modelID]?.plan }) {
            return plan.files
        }
        return loadPersistedPlan(modelID: modelID)?.files
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

    // MARK: - Plan persistence (survives app relaunch)

    private func persistenceDirectory() -> URL? {
        guard let base = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first else { return nil }
        let dir = base.appendingPathComponent("RunAnywhereDownloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func planURL(modelID: String) -> URL? {
        let name = modelID.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? modelID
        return persistenceDirectory()?.appendingPathComponent("\(name).plan")
    }

    private func persistPlan(_ plan: RADownloadPlanResult, modelID: String) {
        guard let url = planURL(modelID: modelID),
              let data = try? plan.serializedData() else { return }
        try? data.write(to: url, options: .atomic)
    }

    private func loadPersistedPlan(modelID: String) -> RADownloadPlanResult? {
        guard let url = planURL(modelID: modelID),
              let data = try? Data(contentsOf: url) else { return nil }
        return try? RADownloadPlanResult(serializedBytes: data)
    }

    private func clearPersistedPlan(modelID: String) {
        guard let url = planURL(modelID: modelID) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    // MARK: - Resume data (survives cancel and app relaunch)

    /// `URLSessionDownloadTask` keeps its partial bytes in a private temp file and
    /// deletes them on a plain `cancel()`. `cancel(byProducingResumeData:)` instead
    /// hands back an opaque blob that a later `downloadTask(withResumeData:)`
    /// continues from, and that blob is what has to be kept.
    ///
    /// It is written to disk rather than held in memory because the case that
    /// matters most is the app being killed: a 3 GB model interrupted at 90% must
    /// cost the remaining 10% on next launch, not the whole file again. Keyed per
    /// file, since a multi-file model can be interrupted with some files done and
    /// one mid-flight.
    private func resumeDataURL(modelID: String, destinationPath: String) -> URL? {
        let key = "\(modelID)|\(destinationPath)"
        let name = key.addingPercentEncoding(withAllowedCharacters: .alphanumerics)
            ?? String(key.hashValue)
        return persistenceDirectory()?.appendingPathComponent("\(name).resume")
    }

    private func storeResumeData(_ data: Data, modelID: String, destinationPath: String) {
        guard let url = resumeDataURL(modelID: modelID, destinationPath: destinationPath) else {
            return
        }
        try? data.write(to: url, options: .atomic)
    }

    private func loadResumeData(modelID: String, destinationPath: String) -> Data? {
        guard let url = resumeDataURL(modelID: modelID, destinationPath: destinationPath) else {
            return nil
        }
        return try? Data(contentsOf: url)
    }

    private func clearResumeData(modelID: String, destinationPath: String) {
        guard let url = resumeDataURL(modelID: modelID, destinationPath: destinationPath) else {
            return
        }
        try? FileManager.default.removeItem(at: url)
    }

    /// Drop every stored blob for a model, used once the model is fully downloaded
    /// or has failed for a reason a resume cannot fix.
    private func clearResumeData(modelID: String) {
        guard let dir = persistenceDirectory(),
              let entries = try? FileManager.default.contentsOfDirectory(
                  at: dir, includingPropertiesForKeys: nil
              ) else { return }
        let prefix = "\(modelID)|".addingPercentEncoding(withAllowedCharacters: .alphanumerics)
        guard let prefix else { return }
        for entry in entries
        where entry.pathExtension == "resume" && entry.lastPathComponent.hasPrefix(prefix) {
            try? FileManager.default.removeItem(at: entry)
        }
    }

    /// How many bytes an interrupted attempt left recoverable, so a caller can
    /// offer "Resume" only when resuming would genuinely save work.
    ///
    /// Counts files already complete on disk, plus files that hold a resume blob.
    /// A blob's exact byte offset is opaque until the task actually resumes, so a
    /// partial file contributes a nominal 1 — the caller only needs to know whether
    /// anything is recoverable, not how much.
    ///
    /// Zero when no plan is persisted, which is the normal state for a model that
    /// has never been downloaded or whose download finished.
    func resumableBytes(modelID: String) -> Int64 {
        let plan = stateQueue.sync { transfers[modelID]?.plan } ?? loadPersistedPlan(modelID: modelID)
        guard let plan else { return 0 }
        return plan.files.reduce(Int64(0)) { total, file in
            if fileSize(file.destinationPath) == file.expectedBytes {
                return total + file.expectedBytes
            }
            let hasBlob = loadResumeData(
                modelID: modelID, destinationPath: file.destinationPath
            ) != nil
            return hasBlob ? total + 1 : total
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

        let expected = payload.expectedBytes
        // Both of these mean the bytes we hold are wrong, not merely incomplete, so
        // the partial state is discarded — a resume would only rebuild the same
        // corrupt file.
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

        guard let files = planFiles(for: payload.modelID), allFilesComplete(files) else { return }
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

        guard let plan = stateQueue.sync(execute: { transfers[modelID]?.plan }) else {
            // Relaunch case: no in-process awaiter, drive the notifier per file.
            if totalBytesExpectedToWrite > 0 {
                let fraction = Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)
                Task { await notify { await $0.notifyProgress(modelID: modelID, fraction: fraction) } }
            }
            return
        }

        let index = plan.files.firstIndex { $0.destinationPath == payload.destinationPath } ?? 0
        let total = plan.totalBytes > 0 ? plan.totalBytes : plan.files.reduce(0) { $0 + $1.expectedBytes }
        let sample: (done: Int64, elapsed: TimeInterval, moved: Int64)? = stateQueue.sync {
            guard var transfer = transfers[modelID] else { return nil }
            transfer.fileBytes[index] = totalBytesWritten
            transfers[modelID] = transfer
            let done = transfer.fileBytes.values.reduce(0, +) + transfer.preexistingBytes
            // Bytes this attempt actually moved: everything on disk, minus what was
            // already complete before it started, minus what a resumed task
            // inherited. Without the last term a download resumed at 1.4 GB would
            // report gigabytes per second on its first sample.
            let inherited = transfer.resumedBytes.values.reduce(0, +)
            return (
                done: done,
                elapsed: Date().timeIntervalSince(transfer.startedAt),
                moved: done - transfer.preexistingBytes - inherited
            )
        }
        guard let sample else { return }
        let done = sample.done
        nonisolated(unsafe) let callback = stateQueue.sync { transfers[modelID]?.onProgress }

        var progress = RADownloadProgress()
        progress.modelID = modelID
        // RADownloadStage was folded into RADownloadState
        // (idl/download_service.proto); `.state` alone now carries what
        // `.stage` used to.
        progress.state = .downloading
        progress.bytesDownloaded = done
        progress.totalBytes = total
        progress.totalFiles = Int32(plan.files.count)
        progress.currentFileIndex = Int32(index)
        progress.overallProgress = total > 0 ? Float(Double(done) / Double(total)) : 0

        // Throughput and ETA, matching what the commons path reports
        // (`download_orchestrator.cpp`) so the two transfer paths are
        // indistinguishable to a caller. A whole-transfer average, not a
        // windowed rate: the same choice commons makes, and a windowed rate on
        // a multi-gigabyte download reads as jitter rather than information.
        if sample.elapsed > 0, sample.moved > 0 {
            let speed = Double(sample.moved) / sample.elapsed
            progress.bytesPerSecond = Float(speed)
            if total > done, speed > 0 {
                progress.etaSeconds = Int64(Double(total - done) / speed)
            }
        }
        let fraction = Double(progress.overallProgress)

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
            guard var transfer = transfers[modelID] else { return }
            let index = transfer.plan.files.firstIndex {
                $0.destinationPath == payload.destinationPath
            } ?? 0
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
        if (error as NSError).code == NSURLErrorCancelled { return }
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
