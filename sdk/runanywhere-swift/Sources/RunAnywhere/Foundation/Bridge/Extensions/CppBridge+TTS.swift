//
//  CppBridge+TTS.swift
//  RunAnywhere SDK
//
//  TTS component bridge - manages C++ TTS component lifecycle.
//
//  Generic scaffolding (handle creation, unload, destroy) lives in
//  `CppBridge.ComponentActor`. TTS-specific surfaces kept here:
//  the `loadVoice` voice-terminology wrapper and `stop()` to interrupt
//  synthesis.
//  The public `isLoaded` accessor was removed — call sites now query
//  `RunAnywhere.currentModel(category: .speechSynthesis)` on the
//  lifecycle as the single source of truth.
//

import CRACommons
import Foundation
import os
import SwiftProtobuf

private enum TTSStreamSessionABI {
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
    typealias Finish = @convention(c) (UInt64) -> rac_result_t

    static let setCallback = NativeProtoABI.load(
        "rac_tts_set_stream_proto_callback",
        as: SetCallback.self
    )
    static let unsetCallback = NativeProtoABI.load(
        "rac_tts_unset_stream_proto_callback",
        as: UnsetCallback.self
    )
    static let quiesce = NativeProtoABI.load("rac_tts_proto_quiesce", as: Quiesce.self)
    static let start = NativeProtoABI.load("rac_tts_stream_start_proto", as: Start.self)
    static let stop = NativeProtoABI.load("rac_tts_stream_stop_proto", as: Finish.self)
    static let cancel = NativeProtoABI.load("rac_tts_stream_cancel_proto", as: Finish.self)
}

private final class TTSStreamSessionContext: @unchecked Sendable {
    private struct State {
        var sessionId: UInt64 = 0
        var isCancelled = false
        var expectedRequestId = ""
    }

    private let state = OSAllocatedUnfairLock<State>(initialState: State())
    private let continuation: AsyncStream<RATTSOutput>.Continuation
    private let logger = SDKLogger(category: "CppBridge.TTS.SessionStream")
    private let terminalSemaphore = DispatchSemaphore(value: 0)

    init(_ continuation: AsyncStream<RATTSOutput>.Continuation) {
        self.continuation = continuation
    }

    var isCancelled: Bool {
        state.withLock { $0.isCancelled }
    }

    var sessionId: UInt64 {
        state.withLock { $0.sessionId }
    }

    func setExpectedRequestId(_ requestId: String) {
        state.withLock { $0.expectedRequestId = requestId }
    }

    func setSessionId(_ sessionId: UInt64) {
        state.withLock { $0.sessionId = sessionId }
    }

    func cancel() -> UInt64 {
        let sessionId = state.withLock { current in
            current.isCancelled = true
            return current.sessionId
        }
        terminalSemaphore.signal()
        return sessionId
    }

    func waitForTerminal() {
        terminalSemaphore.wait()
    }

    func yield(bytes: UnsafePointer<UInt8>?, size: Int) {
        guard let bytes, size > 0, !isCancelled else { return }
        do {
            let event = try RATTSStreamEvent(serializedBytes: Data(bytes: bytes, count: size))
            yield(event)
        } catch {
            logger.warning("Failed to decode TTS stream event: \(error.localizedDescription)")
        }
    }

    func yieldFailure(_ message: String, code: rac_result_t = RAC_ERROR_STREAM_CANCELLED) {
        guard !isCancelled else { return }
        var output = RATTSOutput()
        output.timestampMs = Int64(Date().timeIntervalSince1970 * 1000)
        output.isFinal = true
        output.errorMessage = message
        output.errorCode = Int32(code)
        continuation.yield(output)
        terminalSemaphore.signal()
    }

    private func yield(_ event: RATTSStreamEvent) {
        let expectedRequestId = state.withLock { $0.expectedRequestId }
        if !expectedRequestId.isEmpty, !event.requestID.isEmpty, event.requestID != expectedRequestId {
            return
        }

        switch event.kind {
        case .audioChunk:
            if event.hasOutput {
                continuation.yield(event.output)
            }
        case .completed:
            if event.hasOutput {
                var output = event.output
                output.isFinal = true
                continuation.yield(output)
            } else {
                var output = RATTSOutput()
                output.timestampMs = Int64(Date().timeIntervalSince1970 * 1000)
                output.isFinal = true
                continuation.yield(output)
            }
            terminalSemaphore.signal()
        case .error:
            let message = event.hasErrorMessage ? event.errorMessage : "TTS stream failed"
            yieldFailure(message, code: rac_result_t(event.errorCode))
        case .started, .progress, .phoneme, .unspecified, .UNRECOGNIZED:
            break
        }
    }
}

private let ttsStreamSessionTrampoline: TTSStreamSessionABI.Callback = { bytes, size, userData in
    guard let userData else { return }
    let context = Unmanaged<TTSStreamSessionContext>.fromOpaque(userData).takeUnretainedValue()
    context.yield(bytes: bytes, size: size)
}

// MARK: - TTS Component Bridge

extension CppBridge {

    /// TTS component manager
    /// Provides thread-safe access to the C++ TTS component
    public actor TTS {

        /// Shared TTS component instance
        public static let shared = TTS()

        /// Generic scaffold (handle / isLoaded / loadModel / unload / destroy).
        /// TTS's vtable.loadModel forwards to `rac_tts_component_load_voice`.
        private let inner = ComponentActor(vtable: .tts)

        private init() {}

        // MARK: - Handle Management

        /// Get or create the TTS component handle
        public func getHandle() async throws -> rac_handle_t {
            try await inner.getHandle()
        }

        // MARK: - State

        /// Get the currently loaded voice ID
        public var currentVoiceId: String? {
            get async { await inner.currentAssetId }
        }

        // MARK: - Voice Lifecycle

        /// Load a TTS voice
        public func loadVoice(_ voicePath: String, voiceId: String, voiceName: String) async throws {
            try await inner.loadModel(path: voicePath, id: voiceId, name: voiceName)
        }

        public func synthesizeSessionStream(
            _ request: RATTSSynthesisRequest,
            loadedModel: RACurrentModelResult
        ) async throws -> AsyncStream<RATTSOutput> {
            let handle = try await prepareStreamingHandle(from: loadedModel)
            guard let setCallback = TTSStreamSessionABI.setCallback,
                  let unsetCallback = TTSStreamSessionABI.unsetCallback,
                  let start = TTSStreamSessionABI.start,
                  let stop = TTSStreamSessionABI.stop,
                  let cancel = TTSStreamSessionABI.cancel else {
                throw SDKException(
                    code: .notSupported,
                    message: NativeProtoABI.missingSymbolMessage("rac_tts_stream_start_proto"),
                    category: .component
                )
            }

            var streamRequest = request
            if streamRequest.requestID.isEmpty {
                streamRequest.requestID = "tts-swift-\(UUID().uuidString)"
            }
            let requestId = streamRequest.requestID
            let requestData = try streamRequest.serializedData()

            return AsyncStream { continuation in
                let context = TTSStreamSessionContext(continuation)
                context.setExpectedRequestId(requestId)
                let contextPtr = Unmanaged.passRetained(context).toOpaque()

                let task = Task.detached(priority: .userInitiated) {
                    defer {
                        _ = unsetCallback(handle)
                        TTSStreamSessionABI.quiesce?()
                        Unmanaged<TTSStreamSessionContext>.fromOpaque(contextPtr).release()
                        continuation.finish()
                    }

                    let registerResult = setCallback(handle, ttsStreamSessionTrampoline, contextPtr)
                    guard registerResult == RAC_SUCCESS else {
                        context.yieldFailure("TTS stream callback registration failed: \(registerResult)", code: registerResult)
                        return
                    }

                    var sessionId: UInt64 = 0
                    let startResult = requestData.withUnsafeBytes { rawBuffer in
                        start(
                            handle,
                            rawBuffer.bindMemory(to: UInt8.self).baseAddress,
                            rawBuffer.count,
                            &sessionId
                        )
                    }
                    context.setSessionId(sessionId)
                    guard startResult == RAC_SUCCESS, sessionId != 0 else {
                        if !context.isCancelled {
                            context.yieldFailure("TTS stream start failed: \(startResult)", code: startResult)
                        }
                        return
                    }
                    if Task.isCancelled || context.isCancelled {
                        _ = cancel(sessionId)
                        return
                    }
                    context.waitForTerminal()
                    if Task.isCancelled || context.isCancelled {
                        _ = cancel(sessionId)
                    } else {
                        _ = stop(sessionId)
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
                        rac_tts_component_stop(handle)
                    case .finished:
                        break
                    @unknown default:
                        break
                    }
                }
            }
        }

        /// Unload the current voice
        public func unload() async {
            await inner.unload()
        }

        /// Stop synthesis
        public func stop() async {
            guard let handle = await inner.existingHandle() else { return }
            rac_tts_component_stop(handle)
        }

        // MARK: - Cleanup

        /// Destroy the component
        public func destroy() async {
            await inner.destroy()
        }

        private func prepareStreamingHandle(from snapshot: RACurrentModelResult) async throws -> rac_handle_t {
            guard snapshot.found else {
                throw SDKException(code: .notInitialized, message: "TTS voice not loaded", category: .component)
            }
            let modelId = snapshot.modelID.isEmpty ? snapshot.model.id : snapshot.modelID
            let modelName = snapshot.model.name.isEmpty ? modelId : snapshot.model.name
            let modelPath = snapshot.resolvedPath.isEmpty ? snapshot.model.localPath : snapshot.resolvedPath
            guard !modelId.isEmpty, !modelPath.isEmpty else {
                throw SDKException(
                    code: .modelLoadFailed,
                    message: "Loaded TTS voice is missing a resolved path",
                    category: .component
                )
            }

            if await inner.currentAssetId != modelId {
                try await inner.loadModel(path: modelPath, id: modelId, name: modelName)
            }
            return try await inner.getHandle()
        }
    }
}
