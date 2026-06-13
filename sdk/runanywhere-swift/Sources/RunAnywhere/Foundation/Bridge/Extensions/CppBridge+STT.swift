//
//  CppBridge+STT.swift
//  RunAnywhere SDK
//
//  STT component bridge - manages C++ STT component lifecycle.
//
//  Generic scaffolding (handle creation, isLoaded, unload, destroy)
//  lives in `CppBridge.ComponentActor`. STT-specific surfaces kept here:
//  `supportsStreaming`, the `framework:`-aware `loadModel(...)` variant
//  (which configures the component before loading), and the same-model
//  fast-path.
//

import CRACommons
import Foundation
import os
import SwiftProtobuf

private enum STTStreamSessionABI {
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
    typealias Quiesce = @convention(c) () -> Void
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

    static let setCallback = NativeProtoABI.load(
        "rac_stt_set_stream_proto_callback",
        as: SetCallback.self
    )
    static let unsetCallback = NativeProtoABI.load(
        "rac_stt_unset_stream_proto_callback",
        as: UnsetCallback.self
    )
    static let quiesce = NativeProtoABI.load("rac_stt_proto_quiesce", as: Quiesce.self)
    static let start = NativeProtoABI.load("rac_stt_stream_start_proto", as: Start.self)
    static let feedAudio = NativeProtoABI.load(
        "rac_stt_stream_feed_audio_proto",
        as: FeedAudio.self
    )
    static let stop = NativeProtoABI.load("rac_stt_stream_stop_proto", as: Finish.self)
    static let cancel = NativeProtoABI.load("rac_stt_stream_cancel_proto", as: Finish.self)
}

private final class STTStreamSessionContext: @unchecked Sendable {
    private struct State {
        var sessionId: UInt64 = 0
        var isCancelled = false
    }

    private let state = OSAllocatedUnfairLock<State>(initialState: State())
    private let continuation: AsyncStream<RASTTPartialResult>.Continuation
    private let logger = SDKLogger(category: "CppBridge.STT.SessionStream")

    init(_ continuation: AsyncStream<RASTTPartialResult>.Continuation) {
        self.continuation = continuation
    }

    var isCancelled: Bool {
        state.withLock { $0.isCancelled }
    }

    var sessionId: UInt64 {
        state.withLock { $0.sessionId }
    }

    func setSessionId(_ sessionId: UInt64) {
        state.withLock { $0.sessionId = sessionId }
    }

    func cancel() -> UInt64 {
        state.withLock { current in
            current.isCancelled = true
            return current.sessionId
        }
    }

    func yield(bytes: UnsafePointer<UInt8>?, size: Int) {
        guard let bytes, size > 0, !isCancelled else { return }
        do {
            let event = try RASTTStreamEvent(serializedBytes: Data(bytes: bytes, count: size))
            yield(event)
        } catch {
            logger.warning("Failed to decode STT stream event: \(error.localizedDescription)")
        }
    }

    func yieldFailure(_ message: String, code: rac_result_t = RAC_ERROR_STREAM_CANCELLED) {
        guard !isCancelled else { return }
        var partial = RASTTPartialResult()
        partial.isFinal = true
        partial.text = message
        partial.finalOutput.errorMessage = message
        partial.finalOutput.errorCode = Int32(code)
        continuation.yield(partial)
    }

    private func yield(_ event: RASTTStreamEvent) {
        switch event.kind {
        case .partial, .endpoint:
            if event.hasPartial {
                continuation.yield(event.partial)
            }
        case .final:
            var partial = event.hasPartial ? event.partial : RASTTPartialResult()
            partial.isFinal = true
            if event.hasFinalOutput {
                partial.finalOutput = event.finalOutput
                if partial.text.isEmpty {
                    partial.text = event.finalOutput.text
                }
            }
            continuation.yield(partial)
        case .error:
            let message = event.hasErrorMessage ? event.errorMessage : "STT stream failed"
            yieldFailure(message, code: rac_result_t(event.errorCode))
        case .started, .unspecified, .UNRECOGNIZED:
            break
        }
    }
}

private let sttStreamSessionTrampoline: STTStreamSessionABI.Callback = { bytes, size, userData in
    guard let userData else { return }
    let context = Unmanaged<STTStreamSessionContext>.fromOpaque(userData).takeUnretainedValue()
    context.yield(bytes: bytes, size: size)
}

/// Audio pump for `CppBridge.STT.transcribeSessionStream` — verbatim
/// extraction so the session-stream body stays within the lint body-length
/// limit. Returns true when the session must be cancelled (task/stream
/// cancellation or a feed failure).
private func pumpSTTStreamAudio(
    _ audio: AsyncStream<Data>,
    sessionId: UInt64,
    context: STTStreamSessionContext,
    feedAudio: STTStreamSessionABI.FeedAudio
) async -> Bool {
    var shouldCancel = false
    for await chunk in audio {
        if Task.isCancelled || context.isCancelled {
            shouldCancel = true
            break
        }
        guard !chunk.isEmpty else { continue }
        let feedResult = chunk.withUnsafeBytes { rawBuffer in
            feedAudio(
                sessionId,
                rawBuffer.bindMemory(to: UInt8.self).baseAddress,
                rawBuffer.count
            )
        }
        guard feedResult == RAC_SUCCESS else {
            context.yieldFailure("STT stream feed failed: \(feedResult)", code: feedResult)
            shouldCancel = true
            break
        }
    }
    return shouldCancel
}

// MARK: - STT Component Bridge

extension CppBridge {

    /// STT component manager
    /// Provides thread-safe access to the C++ STT component
    public actor STT {

        /// Shared STT component instance
        public static let shared = STT()

        /// Generic scaffold (handle / isLoaded / loadModel / unload / destroy).
        private let inner = ComponentActor(vtable: .stt)

        /// Mirror of the inner actor's loadedAssetId for the same-model
        /// fast-path; allows the fast-path check without awaiting the
        /// inner actor first.
        private var loadedModelId: String?

        private let logger = SDKLogger(category: "CppBridge.STT")

        private init() {}

        // MARK: - Handle Management

        /// Get or create the STT component handle
        public func getHandle() async throws -> rac_handle_t {
            try await inner.getHandle()
        }

        // MARK: - State

        /// Check if a model is loaded
        public var isLoaded: Bool {
            get async { await inner.isLoaded }
        }

        /// Get the currently loaded model ID
        public var currentModelId: String? { loadedModelId }

        /// Check if streaming is supported
        public var supportsStreaming: Bool {
            get async {
                guard let handle = await inner.existingHandle() else { return false }
                return rac_stt_component_supports_streaming(handle) == RAC_TRUE
            }
        }

        // MARK: - Model Lifecycle

        /// Load an STT model
        public func loadModel(
            _ modelPath: String,
            modelId: String,
            modelName: String,
            framework: rac_inference_framework_t = RAC_FRAMEWORK_UNKNOWN
        ) async throws {
            // Skip if the same model is already loaded — avoids redundant
            // backend model-compilation/load work.
            guard loadedModelId != modelId else {
                logger.info("Model already loaded: \(modelId)")
                return
            }

            let handle = try await inner.getHandle()

            // Configure the component with the correct framework so telemetry events
            // carry the real framework value instead of "unknown".
            if framework != RAC_FRAMEWORK_UNKNOWN {
                var config = RAC_STT_CONFIG_DEFAULT
                config.preferred_framework = Int32(framework.rawValue)
                let configResult = rac_stt_component_configure(handle, &config)
                if configResult != RAC_SUCCESS {
                    logger.warning("Failed to configure STT framework: \(configResult)")
                }
            }

            try await inner.loadModel(path: modelPath, id: modelId, name: modelName)
            loadedModelId = modelId
        }

        public func transcribeSessionStream(
            audio: AsyncStream<Data>,
            options: RASTTOptions,
            loadedModel: RACurrentModelResult
        ) async throws -> AsyncStream<RASTTPartialResult> {
            let handle = try await prepareStreamingHandle(from: loadedModel)
            guard let setCallback = STTStreamSessionABI.setCallback,
                  let unsetCallback = STTStreamSessionABI.unsetCallback,
                  let start = STTStreamSessionABI.start,
                  let feedAudio = STTStreamSessionABI.feedAudio,
                  let stop = STTStreamSessionABI.stop,
                  let cancel = STTStreamSessionABI.cancel else {
                throw SDKException(
                    code: .notSupported,
                    message: NativeProtoABI.missingSymbolMessage("rac_stt_stream_start_proto"),
                    category: .component
                )
            }

            let optionsData = try options.serializedData()
            return AsyncStream { continuation in
                let context = STTStreamSessionContext(continuation)
                let contextPtr = Unmanaged.passRetained(context).toOpaque()

                let task = Task.detached(priority: .userInitiated) {
                    defer {
                        _ = unsetCallback(handle)
                        STTStreamSessionABI.quiesce?()
                        Unmanaged<STTStreamSessionContext>.fromOpaque(contextPtr).release()
                        continuation.finish()
                    }

                    let registerResult = setCallback(handle, sttStreamSessionTrampoline, contextPtr)
                    guard registerResult == RAC_SUCCESS else {
                        context.yieldFailure("STT stream callback registration failed: \(registerResult)", code: registerResult)
                        return
                    }

                    var sessionId: UInt64 = 0
                    let startResult = optionsData.withUnsafeBytes { rawBuffer in
                        start(
                            handle,
                            rawBuffer.bindMemory(to: UInt8.self).baseAddress,
                            rawBuffer.count,
                            &sessionId
                        )
                    }
                    guard startResult == RAC_SUCCESS, sessionId != 0 else {
                        context.yieldFailure("STT stream start failed: \(startResult)", code: startResult)
                        return
                    }
                    context.setSessionId(sessionId)

                    let shouldCancel = await pumpSTTStreamAudio(
                        audio,
                        sessionId: sessionId,
                        context: context,
                        feedAudio: feedAudio
                    )

                    if shouldCancel || Task.isCancelled || context.isCancelled {
                        _ = cancel(sessionId)
                    } else {
                        let stopResult = stop(sessionId)
                        if stopResult != RAC_SUCCESS {
                            context.yieldFailure("STT stream stop failed: \(stopResult)", code: stopResult)
                        }
                    }
                }

                continuation.onTermination = { @Sendable termination in
                    switch termination {
                    case .cancelled:
                        task.cancel()
                        let sessionId = context.cancel()
                        if sessionId != 0 {
                            _ = cancel(sessionId)
                        }
                    case .finished:
                        break
                    @unknown default:
                        break
                    }
                }
            }
        }

        /// Unload the current model
        public func unload() async {
            await inner.unload()
            loadedModelId = nil
        }

        // MARK: - Cleanup

        /// Destroy the component
        public func destroy() async {
            await inner.destroy()
            loadedModelId = nil
        }

        private func prepareStreamingHandle(from snapshot: RACurrentModelResult) async throws -> rac_handle_t {
            guard snapshot.found else {
                throw SDKException(code: .notInitialized, message: "STT model not loaded", category: .component)
            }
            let modelId = snapshot.modelID.isEmpty ? snapshot.model.id : snapshot.modelID
            let modelName = snapshot.model.name.isEmpty ? modelId : snapshot.model.name
            let modelPath = snapshot.resolvedPath.isEmpty ? snapshot.model.localPath : snapshot.resolvedPath
            guard !modelId.isEmpty, !modelPath.isEmpty else {
                throw SDKException(
                    code: .modelLoadFailed,
                    message: "Loaded STT model is missing a resolved path",
                    category: .component
                )
            }

            guard loadedModelId != modelId else {
                return try await inner.getHandle()
            }

            let handle = try await inner.getHandle()
            let framework = snapshot.framework.toCFramework()
            if framework != RAC_FRAMEWORK_UNKNOWN {
                var config = RAC_STT_CONFIG_DEFAULT
                config.preferred_framework = Int32(framework.rawValue)
                let configResult = rac_stt_component_configure(handle, &config)
                if configResult != RAC_SUCCESS {
                    logger.warning("Failed to configure STT streaming framework: \(configResult)")
                }
            }

            try await inner.loadModel(path: modelPath, id: modelId, name: modelName)
            loadedModelId = modelId
            return handle
        }
    }
}
