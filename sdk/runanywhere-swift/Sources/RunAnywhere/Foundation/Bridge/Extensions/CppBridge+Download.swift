//
//  CppBridge+Download.swift
//  RunAnywhere SDK
//
//  Download manager bridge extension for C++ interop.
//

import CRACommons
import Foundation
import os
import SwiftProtobuf

// MARK: - Download Bridge

private enum DownloadProtoABI {
    typealias ProtoFunction = @convention(c) (
        UnsafePointer<UInt8>?,
        Int,
        UnsafeMutablePointer<rac_proto_buffer_t>?
    ) -> rac_result_t
    typealias ProgressCallback = @convention(c) (
        UnsafePointer<UInt8>?,
        Int,
        UnsafeMutableRawPointer?
    ) -> Void
    typealias SetProgressCallback = @convention(c) (
        ProgressCallback?,
        UnsafeMutableRawPointer?
    ) -> rac_result_t

    static let setProgressCallback = NativeProtoABI.load(
        "rac_download_set_progress_proto_callback",
        as: SetProgressCallback.self
    )
    static let plan = NativeProtoABI.load("rac_download_plan_proto", as: ProtoFunction.self)
    static let start = NativeProtoABI.load("rac_download_start_proto", as: ProtoFunction.self)
    static let cancel = NativeProtoABI.load("rac_download_cancel_proto", as: ProtoFunction.self)
    static let resume = NativeProtoABI.load("rac_download_resume_proto", as: ProtoFunction.self)
    static let pollProgress = NativeProtoABI.load(
        "rac_download_progress_poll_proto",
        as: ProtoFunction.self
    )
}

/// Process-wide fan-out over the single native download progress callback slot.
///
/// `rac_download_set_progress_proto_callback` exposes exactly ONE callback
/// slot. Registering it per subscriber lets a second subscriber overwrite the
/// first's context, and the first stream's teardown (`setProgressCallback(nil,
/// nil)`) then silences every other subscriber. Concurrent downloads therefore
/// need one native registration multiplexed to many `AsyncStream`
/// continuations, mirroring the LLMStreamAdapter fan-out. The trampoline reads
/// this immortal singleton (no `user_data` pointer to release), so a native
/// callback can never outlive its context.
private final class DownloadProgressFanOut: @unchecked Sendable {
    static let shared = DownloadProgressFanOut()

    // Subscriber continuations. `dispatch` (invoked from the C trampoline while
    // the commons progress-sink mutex is held) reads this, so it MUST NOT be the
    // lock held across the native register/unregister calls.
    private let subscribers = OSAllocatedUnfairLock(
        initialState: [UUID: AsyncStream<RADownloadProgress>.Continuation]()
    )

    // Serializes the native register/unregister calls together with the
    // first/last-subscriber decision, so two concurrent subscribe/unsubscribe
    // can't reorder their native calls and leave the single slot inconsistent
    // with `registered` (which would silence a fresh subscriber). Held ACROSS
    // the native call. Never taken by `dispatch`, so it cannot invert with the
    // commons progress-sink mutex: register/unregister acquire
    // registration -> commons-mutex; dispatch acquires commons-mutex ->
    // subscribers; the two lock sets are disjoint, so no cycle.
    private let registration = OSAllocatedUnfairLock(initialState: false)

    private init() {}

    /// Add a subscriber; registers the native callback only for the first one.
    /// Returns the subscription id, or nil if native registration failed. The
    /// whole decision + native call is serialized under `registration`, so a
    /// concurrent joiner cannot be stranded by a first-subscriber register
    /// failure (it runs afterwards and re-tries the registration).
    func subscribe(
        _ continuation: AsyncStream<RADownloadProgress>.Continuation
    ) -> UUID? {
        let id = UUID()
        return registration.withLock { registered -> UUID? in
            subscribers.withLock { $0[id] = continuation }
            guard !registered else { return id }
            guard let setProgressCallback = DownloadProtoABI.setProgressCallback,
                  setProgressCallback(downloadProtoProgressCallback, nil) == RAC_SUCCESS else {
                subscribers.withLock { $0[id] = nil }
                return nil
            }
            registered = true
            return id
        }
    }

    /// Remove a subscriber; unregisters the native callback once the last one
    /// leaves. Serialized with `subscribe` under `registration` so it cannot
    /// reorder against a concurrent register. commons-072:
    /// `setProgressCallback(nil, nil)` serializes on the dispatcher mutex, so it
    /// acts as a quiesce barrier — it cannot return while a callback is in flight.
    func unsubscribe(_ id: UUID) {
        registration.withLock { registered in
            let isEmpty = subscribers.withLock { dict -> Bool in
                dict[id] = nil
                return dict.isEmpty
            }
            guard isEmpty, registered,
                  let setProgressCallback = DownloadProtoABI.setProgressCallback else { return }
            _ = setProgressCallback(nil, nil)
            registered = false
        }
    }

    /// Fan a single native progress update out to every active subscriber.
    func dispatch(_ progress: RADownloadProgress) {
        let continuations = subscribers.withLock { Array($0.values) }
        for continuation in continuations {
            continuation.yield(progress)
        }
    }
}

private func downloadProtoProgressCallback(
    protoBytes: UnsafePointer<UInt8>?,
    protoSize: Int,
    userData: UnsafeMutableRawPointer?
) {
    guard let protoBytes, protoSize > 0 else { return }
    guard let progress = try? RADownloadProgress(
        serializedBytes: Data(bytes: protoBytes, count: protoSize)
    ) else { return }
    DownloadProgressFanOut.shared.dispatch(progress)
}

extension CppBridge {

    /// Download manager bridge
    /// Wraps C++ rac_download.h functions for download orchestration
    public actor Download {

        /// Shared download manager instance
        public static let shared = Download()

        private init() {}

        // MARK: - Proto Download Workflow

        public func plan(_ request: RADownloadPlanRequest) -> RADownloadPlanResult {
            do {
                return try NativeProtoABI.invoke(
                    request,
                    symbol: DownloadProtoABI.plan,
                    symbolName: "rac_download_plan_proto",
                    responseType: RADownloadPlanResult.self
                )
            } catch {
                var result = RADownloadPlanResult()
                result.canStart = false
                result.modelID = request.modelID
                result.errorMessage = String(describing: error)
                return result
            }
        }

        public func start(_ request: RADownloadStartRequest) -> RADownloadStartResult {
            do {
                return try NativeProtoABI.invoke(
                    request,
                    symbol: DownloadProtoABI.start,
                    symbolName: "rac_download_start_proto",
                    responseType: RADownloadStartResult.self
                )
            } catch {
                var result = RADownloadStartResult()
                result.accepted = false
                result.modelID = request.modelID
                result.errorMessage = String(describing: error)
                return result
            }
        }

        public func cancel(_ request: RADownloadCancelRequest) -> RADownloadCancelResult {
            do {
                return try NativeProtoABI.invoke(
                    request,
                    symbol: DownloadProtoABI.cancel,
                    symbolName: "rac_download_cancel_proto",
                    responseType: RADownloadCancelResult.self
                )
            } catch {
                var result = RADownloadCancelResult()
                result.success = false
                result.modelID = request.modelID
                result.taskID = request.taskID
                result.errorMessage = String(describing: error)
                return result
            }
        }

        public func resume(_ request: RADownloadResumeRequest) -> RADownloadResumeResult {
            do {
                return try NativeProtoABI.invoke(
                    request,
                    symbol: DownloadProtoABI.resume,
                    symbolName: "rac_download_resume_proto",
                    responseType: RADownloadResumeResult.self
                )
            } catch {
                var result = RADownloadResumeResult()
                result.accepted = false
                result.modelID = request.modelID
                result.taskID = request.taskID
                result.errorMessage = String(describing: error)
                return result
            }
        }

        public func pollProgress(_ request: RADownloadSubscribeRequest) -> RADownloadProgress {
            do {
                return try NativeProtoABI.invoke(
                    request,
                    symbol: DownloadProtoABI.pollProgress,
                    symbolName: "rac_download_progress_poll_proto",
                    responseType: RADownloadProgress.self
                )
            } catch {
                var progress = RADownloadProgress()
                progress.modelID = request.modelID
                progress.taskID = request.taskID
                progress.state = .failed
                progress.errorMessage = String(describing: error)
                return progress
            }
        }

        public nonisolated func progressEvents() -> AsyncStream<RADownloadProgress> {
            AsyncStream { continuation in
                // One process-wide native callback slot is fanned out to every
                // subscriber by DownloadProgressFanOut, so concurrent downloads
                // (e.g. Voice one-tap STT + LLM + TTS) each get their own stream
                // instead of clobbering a single shared registration.
                guard let subscriptionID = DownloadProgressFanOut.shared.subscribe(continuation) else {
                    continuation.finish()
                    return
                }

                continuation.onTermination = { _ in
                    DownloadProgressFanOut.shared.unsubscribe(subscriptionID)
                }
            }
        }
    }
}
