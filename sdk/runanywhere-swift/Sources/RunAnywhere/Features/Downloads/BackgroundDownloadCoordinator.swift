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
        for file in plan.files {
            if fileSize(file.destinationPath) == file.expectedBytes { continue }
            guard let url = URL(string: file.file.url) else { continue }

            let payload = BackgroundDownloadFile(
                modelID: modelID,
                destinationPath: file.destinationPath,
                expectedBytes: file.expectedBytes,
                sha256: file.checksumSha256
            )
            let task = session.downloadTask(with: url)
            task.taskDescription = encode(payload)
            task.resume()
        }

        // Every file was already on disk (e.g. a re-issue after finalize was
        // interrupted); complete immediately.
        if plan.files.allSatisfy({ fileSize($0.destinationPath) == $0.expectedBytes }) {
            completeTransfer(modelID: modelID)
        }
    }

    func cancelTransfer(modelID: String) {
        cancelTasks(for: modelID)
        let transfer = stateQueue.sync { transfers.removeValue(forKey: modelID) }
        transfer?.continuation.resume(throwing: CancellationError())
        clearPersistedPlan(modelID: modelID)
    }

    private func cancelTasks(for modelID: String) {
        session.getAllTasks { tasks in
            for task in tasks where self.decode(task.taskDescription)?.modelID == modelID {
                task.cancel()
            }
        }
    }

    // MARK: - Completion / failure

    private func completeTransfer(modelID: String) {
        let transfer = stateQueue.sync { transfers.removeValue(forKey: modelID) }
        clearPersistedPlan(modelID: modelID)

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

    private func failTransfer(modelID: String, message: String) {
        cancelTasks(for: modelID)
        let transfer = stateQueue.sync { transfers.removeValue(forKey: modelID) }
        clearPersistedPlan(modelID: modelID)
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
        if expected > 0, fileSize(location.path) != expected {
            failTransfer(
                modelID: payload.modelID,
                message: "Downloaded file size mismatch for \(payload.destinationPath)"
            )
            return
        }
        guard verifiedChecksum(at: location, expected: payload.sha256) else {
            failTransfer(
                modelID: payload.modelID,
                message: "Checksum verification failed for \(payload.destinationPath)"
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
        let done: Int64 = stateQueue.sync {
            transfers[modelID]?.fileBytes[index] = totalBytesWritten
            return transfers[modelID]?.fileBytes.values.reduce(0, +) ?? totalBytesWritten
        }
        nonisolated(unsafe) let callback = stateQueue.sync { transfers[modelID]?.onProgress }

        var progress = RADownloadProgress()
        progress.modelID = modelID
        progress.state = .downloading
        progress.stage = .downloading
        progress.bytesDownloaded = done
        progress.totalBytes = total
        progress.totalFiles = Int32(plan.files.count)
        progress.currentFileIndex = Int32(index)
        progress.overallProgress = total > 0 ? Float(Double(done) / Double(total)) : 0
        let fraction = Double(progress.overallProgress)

        Task {
            await callback?(progress)
            await notify { await $0.notifyProgress(modelID: modelID, fraction: fraction) }
        }
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
