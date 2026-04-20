// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// URLSession-based download with KVO progress + resume support.
// Replaces the legacy AlamofireDownloadService with a stdlib-only
// implementation suitable for the `PlatformAdapter.http_download`
// callback and for the `RunAnywhere.downloadModel` async stream.

import Foundation

@MainActor
public final class DownloadService: NSObject, URLSessionDownloadDelegate {

    public struct Progress: Sendable {
        public let bytesReceived: Int64
        public let totalBytes: Int64
        public let percent: Double
    }

    public enum Outcome: Sendable {
        case success(localURL: URL)
        case failure(Swift.Error)
        case cancelled
    }

    private struct ActiveTask {
        let progress: @Sendable (Progress) -> Void
        let completion: @Sendable (Outcome) -> Void
        let destination: URL
    }

    private let session: URLSession
    private var tasks: [URLSessionDownloadTask: ActiveTask] = [:]
    private var cancelHandles: [String: URLSessionDownloadTask] = [:]
    private var resumeData: [String: Data] = [:]

    public init(configuration: URLSessionConfiguration = .default) {
        self.session = URLSession(configuration: configuration)
        super.init()
        // Reassign with this as the delegate (URLSession init order
        // needs super.init first).
        let cfg = configuration
        self._session = URLSession(configuration: cfg, delegate: self, delegateQueue: .main)
    }

    // Internal lazily-initialised; captured by the base `session` for
    // subclass APIs, but all actual requests go through `_session` so
    // `self` is the delegate.
    private var _session: URLSession!

    /// Start a download. `taskId` is user-supplied and used for `cancel`.
    @discardableResult
    public func start(
        url: URL,
        destination: URL,
        taskId: String,
        authHeader: String? = nil,
        onProgress: @Sendable @escaping (Progress) -> Void,
        onComplete: @Sendable @escaping (Outcome) -> Void
    ) -> URLSessionDownloadTask {
        var request = URLRequest(url: url)
        if let auth = authHeader {
            request.setValue(auth, forHTTPHeaderField: "Authorization")
        }
        let task: URLSessionDownloadTask
        if let resume = resumeData.removeValue(forKey: taskId) {
            task = _session.downloadTask(withResumeData: resume)
        } else {
            task = _session.downloadTask(with: request)
        }
        tasks[task] = ActiveTask(progress: onProgress,
                                   completion: onComplete,
                                   destination: destination)
        cancelHandles[taskId] = task
        task.resume()
        return task
    }

    /// Cancel an in-flight download. Saves resume data keyed by `taskId`.
    public func cancel(taskId: String) {
        guard let task = cancelHandles.removeValue(forKey: taskId) else { return }
        task.cancel(byProducingResumeData: { [weak self] data in
            if let d = data { Task { @MainActor in self?.resumeData[taskId] = d } }
        })
    }

    // MARK: - URLSessionDownloadDelegate

    public nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        let total = totalBytesExpectedToWrite
        let pct = total > 0 ? Double(totalBytesWritten) / Double(total) : 0
        let progress = Progress(
            bytesReceived: totalBytesWritten,
            totalBytes: total,
            percent: pct)
        Task { @MainActor [weak self] in
            self?.tasks[downloadTask]?.progress(progress)
        }
    }

    public nonisolated func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        // We're on a background queue here and must move the file before
        // returning (iOS deletes it after the delegate returns). Do the
        // move synchronously, then post the completion to the main actor.
        let info: (ActiveTask, URL)? = DispatchQueue.main.sync { [weak self] in
            guard let self = self,
                  let t = self.tasks[downloadTask] else { return nil }
            return (t, t.destination)
        }
        guard let (task, destination) = info else { return }

        do {
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true)
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
            Task { @MainActor in task.completion(.success(localURL: destination)) }
        } catch {
            Task { @MainActor in task.completion(.failure(error)) }
        }
    }

    public nonisolated func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: (any Swift.Error)?
    ) {
        guard let error = error, let dlTask = task as? URLSessionDownloadTask else { return }
        Task { @MainActor [weak self] in
            guard let self = self, let t = self.tasks.removeValue(forKey: dlTask) else { return }
            let nsErr = error as NSError
            if nsErr.code == NSURLErrorCancelled {
                t.completion(.cancelled)
            } else {
                t.completion(.failure(error))
            }
        }
    }
}
