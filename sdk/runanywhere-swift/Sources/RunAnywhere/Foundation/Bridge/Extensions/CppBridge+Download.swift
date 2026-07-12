//
//  CppBridge+Download.swift
//  RunAnywhere SDK
//
//  Download manager bridge extension for C++ interop.
//

import CRACommons
import Foundation
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

private final class DownloadProtoProgressBox {
    let continuation: AsyncStream<RADownloadProgress>.Continuation

    init(continuation: AsyncStream<RADownloadProgress>.Continuation) {
        self.continuation = continuation
    }
}

private func downloadProtoProgressCallback(
    protoBytes: UnsafePointer<UInt8>?,
    protoSize: Int,
    userData: UnsafeMutableRawPointer?
) {
    guard let userData, let protoBytes, protoSize > 0 else { return }
    let box = Unmanaged<DownloadProtoProgressBox>.fromOpaque(userData).takeUnretainedValue()
    if let progress = try? RADownloadProgress(
        serializedBytes: Data(bytes: protoBytes, count: protoSize)
    ) {
        box.continuation.yield(progress)
    }
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
                guard let setProgressCallback = DownloadProtoABI.setProgressCallback else {
                    continuation.finish()
                    return
                }

                let box = DownloadProtoProgressBox(continuation: continuation)
                let retained = Unmanaged.passRetained(box)
                let context = DownloadProtoContextPointer(rawValue: retained.toOpaque())
                let status = setProgressCallback(downloadProtoProgressCallback, context.rawValue)

                guard status == RAC_SUCCESS else {
                    retained.release()
                    continuation.finish()
                    return
                }

                continuation.onTermination = { _ in
                    // commons-072: `rac_download_set_progress_proto_callback`
                    // and the dispatcher (`emit_progress` in
                    // commons/src/infrastructure/download/download_orchestrator.cpp)
                    // both serialize on `progress_sink().mutex`, and the
                    // dispatcher holds that mutex across the user callback
                    // invocation. Setting the slot to nil therefore acts as
                    // a quiesce barrier: it cannot return until any in-flight
                    // callback (which would dereference `userData`) has
                    // returned. The subsequent `Unmanaged.release()` is safe.
                    _ = setProgressCallback(nil, nil)
                    Unmanaged<DownloadProtoProgressBox>.fromOpaque(context.rawValue).release()
                }
            }
        }
    }
}

/// Retained callback context released only after the native unregister call
/// has synchronously quiesced the progress dispatcher.
private struct DownloadProtoContextPointer: @unchecked Sendable {
    let rawValue: UnsafeMutableRawPointer
}
