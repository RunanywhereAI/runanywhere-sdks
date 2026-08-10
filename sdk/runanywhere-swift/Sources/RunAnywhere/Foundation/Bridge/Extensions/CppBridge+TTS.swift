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

private enum TTSStateProtoABI {
    typealias State = @convention(c) (
        UnsafeMutablePointer<rac_proto_buffer_t>?
    ) -> rac_result_t

    static let stateName = "rac_tts_state_lifecycle_proto"

    static let state = NativeProtoABI.load(stateName, as: State.self)
}

/// `TTSServiceState.voices` (tag 3) was reserved off the wire outright
/// (idl/tts_options.proto: "use the list-voices verb") — available voices
/// are a dedicated lifecycle-driven call now, not a state-snapshot field.
private enum TTSListVoicesProtoABI {
    typealias ListVoices = @convention(c) (
        UnsafeMutablePointer<rac_proto_buffer_t>?
    ) -> rac_result_t

    static let listVoicesName = "rac_tts_list_voices_lifecycle_proto"

    static let listVoices = NativeProtoABI.load(listVoicesName, as: ListVoices.self)
}

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
    static let start = NativeProtoABI.load("rac_tts_stream_start_proto", as: Start.self)
    static let stop = NativeProtoABI.load("rac_tts_stream_stop_proto", as: Finish.self)
    static let cancel = NativeProtoABI.load("rac_tts_stream_cancel_proto", as: Finish.self)

    struct Functions {
        let setCallback: SetCallback
        let unsetCallback: UnsetCallback
        let start: Start
        let stop: Finish
        let cancel: Finish
    }

    static func resolve() -> Functions? {
        guard let setCallback, let unsetCallback, let start,
              let stop, let cancel else { return nil }
        return Functions(
            setCallback: setCallback,
            unsetCallback: unsetCallback,
            start: start,
            stop: stop,
            cancel: cancel
        )
    }
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
        // Bounded wait: if the native engine streams audio but never delivers a
        // terminal event, don't park the consumer's stream forever. Time out and
        // surface a failure terminal (yieldFailure also signals), matching the
        // timed waits used elsewhere in the bridge.
        if terminalSemaphore.wait(timeout: .now() + 120) == .timedOut {
            yieldFailure("TTS synthesis timed out waiting for completion")
        }
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
        var error = RASDKError.from(rcResult: code)
            ?? RASDKError.make(code: .streamCancelled, message: message, category: .component)
        error.message = message
        output.error = error
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
            let message = event.hasError ? event.error.message : "TTS stream failed"
            let code = event.hasError ? rac_result_t(event.error.cAbiCode) : RAC_ERROR_STREAM_CANCELLED
            yieldFailure(message, code: code)
        case .started, .unspecified, .UNRECOGNIZED:
            // .progress/.phoneme were deleted outright (idl/tts_options.proto):
            // RATTSStreamEventKind is now started/audioChunk/completed/error only.
            break
        }
    }
}

private let ttsStreamSessionTrampoline: TTSStreamSessionABI.Callback = { bytes, size, userData in
    guard let userData else { return }
    let context = Unmanaged<TTSStreamSessionContext>.fromOpaque(userData).takeUnretainedValue()
    context.yield(bytes: bytes, size: size)
}

/// Component handle borrowed by one detached TTS stream task. The component
/// actor owns its lifetime; stream cancellation synchronously unregisters and
/// quiesces callbacks before the task releases its context.
private struct TTSStreamingHandle: @unchecked Sendable {
    let rawValue: rac_handle_t
}

/// Retained stream context passed through the C callback ABI and released only
/// after unregister + quiesce complete.
private struct TTSStreamingContextPointer: @unchecked Sendable {
    let rawValue: UnsafeMutableRawPointer
}

private func terminateTTSStream(
    _ termination: AsyncStream<RATTSOutput>.Continuation.Termination,
    task: Task<Void, Never>,
    context: TTSStreamSessionContext,
    handle: TTSStreamingHandle
) {
    guard case .cancelled = termination else { return }
    task.cancel()
    let sessionId = context.cancel()
    if sessionId != 0 {
        _ = TTSStreamSessionABI.cancel?(sessionId)
    }
    rac_tts_component_stop(handle.rawValue)
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

        // MARK: - State

        /// Get the currently loaded voice ID
        public var currentVoiceId: String? {
            get async { await inner.currentAssetId }
        }

        /// Lifecycle TTS service state (readiness, current voice, available
        /// voices, supported language codes).
        public func stateProto() throws -> RATTSServiceState {
            let symbol = try NativeProtoABI.require(
                TTSStateProtoABI.state,
                named: TTSStateProtoABI.stateName
            )
            var outBuffer = rac_proto_buffer_t()
            defer { NativeProtoABI.free(&outBuffer) }
            let status = symbol(&outBuffer)
            guard status == RAC_SUCCESS else {
                let message = outBuffer.error_message.map { String(cString: $0) }
                    ?? "Native proto request failed: \(TTSStateProtoABI.stateName) rc=\(status)"
                throw SDKException(code: .processingFailed, message: message, category: .internal)
            }
            return try NativeProtoABI.decode(RATTSServiceState.self, from: outBuffer)
        }

        /// Voices the currently-loaded (or default) TTS engine can speak
        /// with. Replaces the deleted `RATTSServiceState.voices` field.
        public func listVoicesProto() throws -> RATTSVoiceList {
            let symbol = try NativeProtoABI.require(
                TTSListVoicesProtoABI.listVoices,
                named: TTSListVoicesProtoABI.listVoicesName
            )
            var outBuffer = rac_proto_buffer_t()
            defer { NativeProtoABI.free(&outBuffer) }
            let status = symbol(&outBuffer)
            guard status == RAC_SUCCESS else {
                let message = outBuffer.error_message.map { String(cString: $0) }
                    ?? "Native proto request failed: \(TTSListVoicesProtoABI.listVoicesName) rc=\(status)"
                throw SDKException(code: .processingFailed, message: message, category: .internal)
            }
            return try NativeProtoABI.decode(RATTSVoiceList.self, from: outBuffer)
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
            let handle = TTSStreamingHandle(
                rawValue: try await prepareStreamingHandle(from: loadedModel).rawValue
            )
            guard TTSStreamSessionABI.resolve() != nil else {
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
                let contextPtr = TTSStreamingContextPointer(
                    rawValue: Unmanaged.passRetained(context).toOpaque()
                )

                let task = Task.detached(priority: .userInitiated) {
                    guard let functions = TTSStreamSessionABI.resolve() else {
                        context.yieldFailure("TTS stream ABI became unavailable")
                        Unmanaged<TTSStreamSessionContext>.fromOpaque(contextPtr.rawValue).release()
                        continuation.finish()
                        return
                    }
                    defer {
                        _ = functions.unsetCallback(handle.rawValue)
                        rac_tts_proto_quiesce()
                        Unmanaged<TTSStreamSessionContext>.fromOpaque(contextPtr.rawValue).release()
                        continuation.finish()
                    }

                    let registerResult = functions.setCallback(
                        handle.rawValue,
                        ttsStreamSessionTrampoline,
                        contextPtr.rawValue
                    )
                    guard registerResult == RAC_SUCCESS else {
                        context.yieldFailure("TTS stream callback registration failed: \(registerResult)", code: registerResult)
                        return
                    }

                    var sessionId: UInt64 = 0
                    let startResult = requestData.withUnsafeBytes { rawBuffer in
                        functions.start(
                            handle.rawValue,
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
                        _ = functions.cancel(sessionId)
                        return
                    }
                    context.waitForTerminal()
                    if Task.isCancelled || context.isCancelled {
                        _ = functions.cancel(sessionId)
                    } else {
                        _ = functions.stop(sessionId)
                    }
                }

                continuation.onTermination = { @Sendable termination in
                    terminateTTSStream(termination, task: task, context: context, handle: handle)
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
            rac_tts_component_stop(handle.rawValue)
        }

        // MARK: - Cleanup

        /// Destroy the component
        public func destroy() async {
            await inner.destroy()
        }

        private func prepareStreamingHandle(
            from snapshot: RACurrentModelResult
        ) async throws -> ComponentHandle {
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
