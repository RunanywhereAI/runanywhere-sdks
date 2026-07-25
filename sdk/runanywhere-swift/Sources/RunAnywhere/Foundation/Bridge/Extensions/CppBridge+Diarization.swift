//
//  CppBridge+Diarization.swift
//  RunAnywhere SDK
//
//  Standalone speaker-diarization bridge over the generated proto-byte ABI.
//

import CRACommons
import Foundation
import os
import SwiftProtobuf

private enum DiarizationLifecycleProtoABI {
    static let diarizeName = "rac_diarization_diarize_lifecycle_proto"
    static let diarize: NativeProtoABI.ProtoRequest? = {
        // RACommons ships as a static archive on Apple platforms. Keep a
        // typed reference so the linker retains the diarization archive
        // member even when RTLD_DEFAULT cannot enumerate executable symbols.
        let linked: NativeProtoABI.ProtoRequest = rac_diarization_diarize_lifecycle_proto
        return NativeProtoABI.load(
            diarizeName,
            as: NativeProtoABI.ProtoRequest.self
        ) ?? linked
    }()
}

private enum DiarizationStreamSessionABI {
    typealias Callback = @convention(c) (
        UnsafePointer<UInt8>?,
        Int,
        UnsafeMutableRawPointer?
    ) -> Void
    typealias SetCallback = @convention(c) (
        rac_handle_t?,
        Callback?,
        UnsafeMutableRawPointer?
    ) -> rac_result_t
    typealias UnsetCallback = @convention(c) (rac_handle_t?) -> rac_result_t
    typealias Start = @convention(c) (
        rac_handle_t?,
        UnsafePointer<UInt8>?,
        Int,
        UnsafeMutablePointer<UInt64>?
    ) -> rac_result_t
    typealias FeedAudio = @convention(c) (
        UInt64,
        UnsafePointer<UInt8>?,
        Int
    ) -> rac_result_t
    typealias Finish = @convention(c) (UInt64) -> rac_result_t
    typealias Quiesce = @convention(c) () -> Void

    // Keep a typed reference to each diarization stream entry point. RACommons
    // ships as a static archive on Apple platforms; a dlsym-only reference does
    // not pull an otherwise-unreferenced archive member into the final app, so
    // the symbol can be dead-stripped even though it is present in the
    // XCFramework. The direct fallback is both a link-time anchor and a valid
    // invocation path when RTLD_DEFAULT cannot enumerate executable symbols.

    static let setCallback: SetCallback? = {
        let linked: SetCallback = rac_diarization_set_stream_proto_callback
        return NativeProtoABI.load(
            "rac_diarization_set_stream_proto_callback",
            as: SetCallback.self
        ) ?? linked
    }()
    static let unsetCallback: UnsetCallback? = {
        let linked: UnsetCallback = rac_diarization_unset_stream_proto_callback
        return NativeProtoABI.load(
            "rac_diarization_unset_stream_proto_callback",
            as: UnsetCallback.self
        ) ?? linked
    }()
    static let start: Start? = {
        let linked: Start = rac_diarization_stream_start_proto
        return NativeProtoABI.load(
            "rac_diarization_stream_start_proto",
            as: Start.self
        ) ?? linked
    }()
    static let feedAudio: FeedAudio? = {
        let linked: FeedAudio = rac_diarization_stream_feed_audio_proto
        return NativeProtoABI.load(
            "rac_diarization_stream_feed_audio_proto",
            as: FeedAudio.self
        ) ?? linked
    }()
    static let stop: Finish? = {
        let linked: Finish = rac_diarization_stream_stop_proto
        return NativeProtoABI.load(
            "rac_diarization_stream_stop_proto",
            as: Finish.self
        ) ?? linked
    }()
    static let cancel: Finish? = {
        let linked: Finish = rac_diarization_stream_cancel_proto
        return NativeProtoABI.load(
            "rac_diarization_stream_cancel_proto",
            as: Finish.self
        ) ?? linked
    }()
    static let quiesce: Quiesce? = {
        let linked: Quiesce = rac_diarization_proto_quiesce
        return NativeProtoABI.load(
            "rac_diarization_proto_quiesce",
            as: Quiesce.self
        ) ?? linked
    }()

    struct Functions {
        let setCallback: SetCallback
        let unsetCallback: UnsetCallback
        let start: Start
        let feedAudio: FeedAudio
        let stop: Finish
        let cancel: Finish
        let quiesce: Quiesce
    }

    static func resolve() -> Functions? {
        guard let setCallback, let unsetCallback, let start, let feedAudio,
              let stop, let cancel, let quiesce else { return nil }
        return Functions(
            setCallback: setCallback,
            unsetCallback: unsetCallback,
            start: start,
            feedAudio: feedAudio,
            stop: stop,
            cancel: cancel,
            quiesce: quiesce
        )
    }
}

private final class DiarizationStreamContext: @unchecked Sendable {
    private struct State {
        var sessionID: UInt64 = 0
        var isCancelled = false
        var isTerminal = false
    }

    private let state = OSAllocatedUnfairLock(initialState: State())
    private let continuation: AsyncThrowingStream<RADiarizationStreamEvent, Error>.Continuation
    private let logger = SDKLogger(category: "CppBridge.Diarization.Stream")

    init(_ continuation: AsyncThrowingStream<RADiarizationStreamEvent, Error>.Continuation) {
        self.continuation = continuation
    }

    var isCancelled: Bool {
        state.withLock { $0.isCancelled }
    }

    func setSessionID(_ sessionID: UInt64) {
        state.withLock { $0.sessionID = sessionID }
    }

    func cancel() -> UInt64 {
        state.withLock { current in
            current.isCancelled = true
            return current.sessionID
        }
    }

    func yield(bytes: UnsafePointer<UInt8>?, size: Int) {
        guard let bytes, size > 0, !isCancelled else { return }
        do {
            let event = try RADiarizationStreamEvent(
                serializedBytes: Data(bytes: bytes, count: size)
            )
            continuation.yield(event)
            if event.kind == .final || event.kind == .error {
                finish()
            }
        } catch {
            logger.warning("Failed to decode diarization stream event: \(error.localizedDescription)")
            finish(throwing: error)
        }
    }

    func fail(_ message: String, status: rac_result_t) {
        finish(
            throwing: SDKException(
                code: .processingFailed,
                message: "\(message): \(status)",
                category: .component
            )
        )
    }

    private func finish(throwing error: Error? = nil) {
        let shouldFinish = state.withLock { current -> Bool in
            guard !current.isTerminal else { return false }
            current.isTerminal = true
            return true
        }
        guard shouldFinish else { return }
        if let error {
            continuation.finish(throwing: error)
        } else {
            continuation.finish()
        }
    }
}

private let diarizationStreamTrampoline: DiarizationStreamSessionABI.Callback = { bytes, size, userData in
    guard let userData else { return }
    let context = Unmanaged<DiarizationStreamContext>.fromOpaque(userData).takeUnretainedValue()
    context.yield(bytes: bytes, size: size)
}

private struct DiarizationStreamContextPointer: @unchecked Sendable {
    let rawValue: UnsafeMutableRawPointer
}

private func pumpDiarizationAudio(
    _ audio: AsyncStream<Data>,
    sessionID: UInt64,
    context: DiarizationStreamContext,
    feedAudio: DiarizationStreamSessionABI.FeedAudio
) async -> Bool {
    for await chunk in audio {
        if Task.isCancelled || context.isCancelled { return true }
        guard !chunk.isEmpty else { continue }
        let result = chunk.withUnsafeBytes { buffer in
            feedAudio(
                sessionID,
                buffer.bindMemory(to: UInt8.self).baseAddress,
                buffer.count
            )
        }
        guard result == RAC_SUCCESS else {
            context.fail("Diarization stream feed failed", status: result)
            return true
        }
    }
    return Task.isCancelled || context.isCancelled
}

extension CppBridge {
    public actor Diarization {
        public static let shared = Diarization()

        private let inner = ComponentActor(vtable: .diarization)
        private var loadedModelID: String?
        private let logger = SDKLogger(category: "CppBridge.Diarization")

        private init() {}

        public func diarize(_ request: RADiarizationRequest) async throws -> RADiarizationResult {
            try await Task.detached(priority: .userInitiated) {
                try NativeProtoABI.invoke(
                    request,
                    symbol: DiarizationLifecycleProtoABI.diarize,
                    symbolName: DiarizationLifecycleProtoABI.diarizeName,
                    responseType: RADiarizationResult.self
                )
            }.value
        }

        public func stream(
            audio: AsyncStream<Data>,
            options: RADiarizationOptions,
            loadedModel: RACurrentModelResult
        ) async throws -> AsyncThrowingStream<RADiarizationStreamEvent, Error> {
            let handle = try await prepareStreamingHandle(from: loadedModel)
            guard DiarizationStreamSessionABI.resolve() != nil else {
                throw SDKException(
                    code: .notSupported,
                    message: NativeProtoABI.missingSymbolMessage(
                        "rac_diarization_stream_start_proto"
                    ),
                    category: .component
                )
            }
            let optionsData = try options.serializedData()

            return AsyncThrowingStream { continuation in
                let context = DiarizationStreamContext(continuation)
                let contextPointer = DiarizationStreamContextPointer(
                    rawValue: Unmanaged.passRetained(context).toOpaque()
                )
                let task = Task.detached(priority: .userInitiated) {
                    guard let functions = DiarizationStreamSessionABI.resolve() else {
                        context.fail("Diarization stream ABI became unavailable", status: RAC_ERROR_NOT_SUPPORTED)
                        Unmanaged<DiarizationStreamContext>
                            .fromOpaque(contextPointer.rawValue)
                            .release()
                        return
                    }
                    defer {
                        _ = functions.unsetCallback(handle.rawValue)
                        functions.quiesce()
                        Unmanaged<DiarizationStreamContext>
                            .fromOpaque(contextPointer.rawValue)
                            .release()
                        continuation.finish()
                    }

                    let registerResult = functions.setCallback(
                        handle.rawValue,
                        diarizationStreamTrampoline,
                        contextPointer.rawValue
                    )
                    guard registerResult == RAC_SUCCESS else {
                        context.fail("Diarization callback registration failed", status: registerResult)
                        return
                    }

                    var sessionID: UInt64 = 0
                    let startResult = optionsData.withUnsafeBytes { buffer in
                        functions.start(
                            handle.rawValue,
                            buffer.bindMemory(to: UInt8.self).baseAddress,
                            buffer.count,
                            &sessionID
                        )
                    }
                    guard startResult == RAC_SUCCESS, sessionID != 0 else {
                        context.fail("Diarization stream start failed", status: startResult)
                        return
                    }
                    context.setSessionID(sessionID)

                    let shouldCancel = await pumpDiarizationAudio(
                        audio,
                        sessionID: sessionID,
                        context: context,
                        feedAudio: functions.feedAudio
                    )
                    if shouldCancel {
                        _ = functions.cancel(sessionID)
                    } else {
                        let stopResult = functions.stop(sessionID)
                        if stopResult != RAC_SUCCESS {
                            context.fail("Diarization stream stop failed", status: stopResult)
                        }
                    }
                }

                continuation.onTermination = { @Sendable termination in
                    guard case .cancelled = termination else { return }
                    task.cancel()
                    let sessionID = context.cancel()
                    if sessionID != 0 {
                        _ = DiarizationStreamSessionABI.cancel?(sessionID)
                    }
                }
            }
        }

        public func unload() async {
            loadedModelID = nil
            await inner.unload()
        }

        public func destroy() async {
            loadedModelID = nil
            await inner.destroy()
        }

        /// Reconcile the lazily loaded streaming component with a successful
        /// canonical lifecycle unload. `unload_all` and an explicitly
        /// speaker-diarization-scoped request clear any component copy. For a
        /// model-specific or otherwise unscoped request, only the exact model
        /// ID reported by the canonical unload result may clear the copy.
        func reconcileCanonicalUnload(
            request: RAModelUnloadRequest,
            result: RAModelUnloadResult
        ) async {
            guard Self.shouldUnloadComponentCopy(
                loadedModelID: loadedModelID,
                request: request,
                result: result
            ) else { return }
            await unload()
        }

        nonisolated static func shouldUnloadComponentCopy(
            loadedModelID: String?,
            request: RAModelUnloadRequest,
            result: RAModelUnloadResult
        ) -> Bool {
            guard result.success, let loadedModelID, !loadedModelID.isEmpty else {
                return false
            }
            if request.unloadAll {
                return true
            }
            if request.hasCategory, request.category == .speakerDiarization {
                return true
            }
            return result.unloadedModelIds.contains(loadedModelID)
        }

        private func prepareStreamingHandle(
            from snapshot: RACurrentModelResult
        ) async throws -> ComponentHandle {
            guard snapshot.found else {
                throw SDKException(
                    code: .notInitialized,
                    message: "Speaker-diarization model not loaded",
                    category: .component
                )
            }
            let modelID = snapshot.modelID.isEmpty ? snapshot.model.id : snapshot.modelID
            let modelName = snapshot.model.name.isEmpty ? modelID : snapshot.model.name
            let modelPath = snapshot.resolvedPath.isEmpty
                ? snapshot.model.localPath
                : snapshot.resolvedPath
            guard !modelID.isEmpty, !modelPath.isEmpty else {
                throw SDKException(
                    code: .modelLoadFailed,
                    message: "Loaded speaker-diarization model is missing a resolved path",
                    category: .component
                )
            }
            if loadedModelID == modelID {
                return try await inner.getHandle()
            }
            try await inner.loadModel(path: modelPath, id: modelID, name: modelName)
            loadedModelID = modelID
            logger.info("Speaker-diarization streaming model loaded: \(modelID)")
            return try await inner.getHandle()
        }
    }
}
