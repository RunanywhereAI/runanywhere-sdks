//
//  CppBridge+ModalityProtoABI.swift
//  RunAnywhere SDK
//
//  Hand-written companion to `Generated/ModalityProtoABI+Generated.swift`.
//
//  Phase B (aggressive): the 24 codegen-eligible methods (7 fully-equivalent
//  + 17 former facades) are now emitted by the generator. This file retains
//  only the 18 `kind: custom` methods that cannot be expressed via the
//  generator's invoke/stream templates, plus the shared C trampoline /
//  AsyncStream scaffolding referenced by both files.
//

import CRACommons
import Foundation
import os
import SwiftProtobuf

// MARK: - C symbol tables (custom methods only)
//
// Tables below own ONLY the dlsym entries for `kind: custom` methods. The
// 24 codegen-eligible C symbols live in the generated file's tables.

private enum LLMCancelProtoABI {
    typealias Cancel = @convention(c) (
        UnsafeMutablePointer<rac_proto_buffer_t>?
    ) -> rac_result_t

    static let cancelName = "rac_llm_cancel_proto"

    static let cancel = NativeProtoABI.load(cancelName, as: Cancel.self)
}

private enum TTSListVoicesProtoABI {
    typealias VoiceCallback = @convention(c) (
        UnsafePointer<UInt8>?,
        Int,
        UnsafeMutableRawPointer?
    ) -> Void
    typealias ListVoices = @convention(c) (
        rac_handle_t?,
        VoiceCallback?,
        UnsafeMutableRawPointer?
    ) -> rac_result_t

    static let listVoicesName = "rac_tts_component_list_voices_proto"

    static let listVoices = NativeProtoABI.load(listVoicesName, as: ListVoices.self)
}

private enum VADComponentProtoABI {
    typealias Configure = @convention(c) (
        rac_handle_t?,
        UnsafePointer<UInt8>?,
        Int
    ) -> rac_result_t
    typealias Process = @convention(c) (
        rac_handle_t?,
        UnsafePointer<Float>?,
        Int,
        UnsafePointer<UInt8>?,
        Int,
        UnsafeMutablePointer<rac_proto_buffer_t>?
    ) -> rac_result_t
    typealias GetStatistics = @convention(c) (
        rac_handle_t?,
        UnsafeMutablePointer<rac_proto_buffer_t>?
    ) -> rac_result_t
    typealias ActivityCallback = @convention(c) (
        UnsafePointer<UInt8>?,
        Int,
        UnsafeMutableRawPointer?
    ) -> Void
    typealias SetActivityCallback = @convention(c) (
        rac_handle_t?,
        ActivityCallback?,
        UnsafeMutableRawPointer?
    ) -> rac_result_t

    static let configureName = "rac_vad_component_configure_proto"
    static let processName = "rac_vad_component_process_proto"
    static let statisticsName = "rac_vad_component_get_statistics_proto"
    static let setActivityCallbackName = "rac_vad_component_set_activity_proto_callback"

    static let configure = NativeProtoABI.load(configureName, as: Configure.self)
    static let process = NativeProtoABI.load(processName, as: Process.self)
    static let statistics = NativeProtoABI.load(statisticsName, as: GetStatistics.self)
    static let setActivityCallback = NativeProtoABI.load(
        setActivityCallbackName,
        as: SetActivityCallback.self
    )
}

private enum VADLifecycleStateProtoABI {
    // State-only lifecycle entries: `(outBuffer*) -> rc`, no request bytes.
    typealias StateOnly = @convention(c) (
        UnsafeMutablePointer<rac_proto_buffer_t>?
    ) -> rac_result_t

    static let startName = "rac_vad_start_lifecycle_proto"
    static let stopName = "rac_vad_stop_lifecycle_proto"
    static let resetName = "rac_vad_reset_lifecycle_proto"

    static let start = NativeProtoABI.load(startName, as: StateOnly.self)
    static let stop = NativeProtoABI.load(stopName, as: StateOnly.self)
    static let reset = NativeProtoABI.load(resetName, as: StateOnly.self)
}

private enum VoiceAgentStateProtoABI {
    typealias States = @convention(c) (
        rac_voice_agent_handle_t?,
        UnsafeMutablePointer<rac_proto_buffer_t>?
    ) -> rac_result_t
    typealias ProcessTurn = @convention(c) (
        rac_voice_agent_handle_t?,
        UnsafeRawPointer?,
        Int,
        UnsafeMutablePointer<rac_proto_buffer_t>?
    ) -> rac_result_t

    static let statesName = "rac_voice_agent_component_states_proto"
    static let processTurnName = "rac_voice_agent_process_voice_turn_proto"

    static let states = NativeProtoABI.load(statesName, as: States.self)
    static let processTurn = NativeProtoABI.load(processTurnName, as: ProcessTurn.self)
}

private enum VLMGeneratedProtoABI {
    typealias Process = @convention(c) (
        rac_handle_t?,
        UnsafePointer<UInt8>?,
        Int,
        UnsafePointer<UInt8>?,
        Int,
        UnsafeMutablePointer<rac_proto_buffer_t>?
    ) -> rac_result_t
    typealias StreamCallback = @convention(c) (
        UnsafePointer<UInt8>?,
        Int,
        UnsafeMutableRawPointer?
    ) -> rac_bool_t
    typealias ProcessStream = @convention(c) (
        rac_handle_t?,
        UnsafePointer<UInt8>?,
        Int,
        UnsafePointer<UInt8>?,
        Int,
        StreamCallback?,
        UnsafeMutableRawPointer?,
        UnsafeMutablePointer<rac_proto_buffer_t>?
    ) -> rac_result_t
    typealias Cancel = @convention(c) (rac_handle_t?) -> rac_result_t

    static let processName = "rac_vlm_process_proto"
    static let streamName = "rac_vlm_process_stream_proto"
    static let cancelName = "rac_vlm_cancel_proto"

    static let process = NativeProtoABI.load(processName, as: Process.self)
    static let stream = NativeProtoABI.load(streamName, as: ProcessStream.self)
    static let cancel = NativeProtoABI.load(cancelName, as: Cancel.self)
}

private enum RAGSessionProtoABI {
    typealias Create = @convention(c) (
        UnsafePointer<UInt8>?,
        Int,
        UnsafeMutablePointer<rac_handle_t?>?
    ) -> rac_result_t
    typealias Destroy = @convention(c) (rac_handle_t?) -> Void
    typealias NoRequest = @convention(c) (
        rac_handle_t?,
        UnsafeMutablePointer<rac_proto_buffer_t>?
    ) -> rac_result_t

    static let createName = "rac_rag_session_create_proto"
    static let destroyName = "rac_rag_session_destroy_proto"
    static let clearName = "rac_rag_clear_proto"
    static let statsName = "rac_rag_stats_proto"

    static let create = NativeProtoABI.load(createName, as: Create.self)
    static let destroy = NativeProtoABI.load(destroyName, as: Destroy.self)
    static let clear = NativeProtoABI.load(clearName, as: NoRequest.self)
    static let stats = NativeProtoABI.load(statsName, as: NoRequest.self)
}

// MARK: - Callback contexts

/// Non-generic protocol that exposes the byte-yield entry point. The C
/// trampoline can only see non-generic types (Swift forbids generic captures
/// in `@convention(c)` closures), so we bridge through this protocol and let
/// dynamic dispatch reach the generic body in `ProtoStreamContext.yield`.
protocol ProtoStreamYielder: AnyObject {
    func yield(bytes: UnsafePointer<UInt8>?, size: Int)
}

/// Single shared C trampoline used by `ProtoStreamContext.runRequestStream`.
/// Holds no generic state; recovers the yielder via `Unmanaged` and dispatches
/// dynamically through `ProtoStreamYielder`.
let protoStreamTrampoline: @convention(c) (
    UnsafePointer<UInt8>?,
    Int,
    UnsafeMutableRawPointer?
) -> Void = { bytes, size, userData in
    guard let userData else { return }
    let yielder = Unmanaged<AnyObject>.fromOpaque(userData).takeUnretainedValue()
    (yielder as? ProtoStreamYielder)?.yield(bytes: bytes, size: size)
}

final class ProtoStreamContext<Event: Message>: @unchecked Sendable, ProtoStreamYielder {
    let continuation: AsyncStream<Event>.Continuation
    let logger: SDKLogger

    init(continuation: AsyncStream<Event>.Continuation, category: String) {
        self.continuation = continuation
        self.logger = SDKLogger(category: category)
    }

    func yield(bytes: UnsafePointer<UInt8>?, size: Int) {
        guard let bytes, size > 0 else { return }
        do {
            let event = try Event(serializedBytes: Data(bytes: bytes, count: size))
            continuation.yield(event)
        } catch {
            logger.warning("Failed to decode proto stream event: \(error.localizedDescription)")
        }
    }

    /// Run a request-shaped streaming C call: serialises `request`, retains a
    /// fresh `ProtoStreamContext<Event>` as the userData pointer, invokes
    /// `body` with the shared `@convention(c)` trampoline, and balances the
    /// retain on completion. If the call returns non-`RAC_SUCCESS`, the
    /// optional `onError` closure may produce a terminal `Event` to yield
    /// before the stream finishes.
    ///
    /// - Parameters:
    ///   - request: Proto request to serialise into the bytes/size pair.
    ///   - category: Logger category for decode failures.
    ///   - onError: Optional terminal-event factory invoked when the C call
    ///     reports a non-success status. Returning `nil` finishes the stream
    ///     silently. The closure runs on the detached task.
    ///   - body: Closure that invokes the C streaming function pointer with
    ///     the serialised bytes, the trampoline, and the userData pointer.
    /// - Returns: An `AsyncStream<Event>` that yields decoded events as the C
    ///   callback fires and finishes when the C call returns.
    /// - Throws: Errors raised by `request.serializedData()`.
    static func runRequestStream<Request: Message>(
        request: Request,
        category: String,
        onError: (@Sendable (rac_result_t) -> Event?)? = nil,
        body: @escaping @Sendable (
            UnsafePointer<UInt8>?,
            Int,
            @convention(c) (UnsafePointer<UInt8>?, Int, UnsafeMutableRawPointer?) -> Void,
            UnsafeMutableRawPointer
        ) -> rac_result_t
    ) throws -> AsyncStream<Event> {
        let requestData = try request.serializedData()
        return AsyncStream { continuation in
            let context = ProtoStreamContext<Event>(
                continuation: continuation,
                category: category
            )
            let contextPtr = Unmanaged.passRetained(context).toOpaque()
            Task.detached {
                let rc = requestData.withUnsafeBytes { rawBuffer in
                    body(
                        rawBuffer.bindMemory(to: UInt8.self).baseAddress,
                        rawBuffer.count,
                        protoStreamTrampoline,
                        contextPtr
                    )
                }
                Unmanaged<ProtoStreamContext<Event>>
                    .fromOpaque(contextPtr)
                    .release()
                if rc != RAC_SUCCESS, let terminal = onError?(rc) {
                    continuation.yield(terminal)
                }
                continuation.finish()
            }
        }
    }
}

private final class ProtoCollectingContext<Event: Message>: @unchecked Sendable {
    private let lock = OSAllocatedUnfairLock(initialState: [Event]())
    let logger: SDKLogger

    init(category: String) {
        self.logger = SDKLogger(category: category)
    }

    var values: [Event] { lock.withLock { $0 } }

    func append(bytes: UnsafePointer<UInt8>?, size: Int) {
        guard let bytes, size > 0 else { return }
        do {
            let event = try Event(serializedBytes: Data(bytes: bytes, count: size))
            lock.withLock { $0.append(event) }
        } catch {
            logger.warning("Failed to decode collected proto event: \(error.localizedDescription)")
        }
    }
}

private final class ProtoProgressContext<Event: Message>: @unchecked Sendable {
    let callback: (Event) -> Bool
    let logger: SDKLogger

    init(category: String, callback: @escaping (Event) -> Bool) {
        self.callback = callback
        self.logger = SDKLogger(category: category)
    }

    func emit(bytes: UnsafePointer<UInt8>?, size: Int) -> Bool {
        guard let bytes, size > 0 else { return true }
        do {
            let event = try Event(serializedBytes: Data(bytes: bytes, count: size))
            return callback(event)
        } catch {
            logger.warning("Failed to decode progress proto: \(error.localizedDescription)")
            return true
        }
    }
}

// MARK: - Shared invoke helpers

private func decodeBuffer<Response: Message>(
    responseType: Response.Type,
    symbolName: String,
    _ body: (UnsafeMutablePointer<rac_proto_buffer_t>) throws -> rac_result_t
) throws -> Response {
    guard NativeProtoABI.canReceiveProtoBuffer else {
        throw SDKException(code: .notSupported, message: NativeProtoABI.missingSymbolMessage(symbolName), category: .internal)
    }
    var outBuffer = rac_proto_buffer_t()
    defer { NativeProtoABI.free(&outBuffer) }
    let status = try body(&outBuffer)
    guard status == RAC_SUCCESS else {
        let message = outBuffer.error_message.map { String(cString: $0) }
            ?? "Native proto request failed: \(symbolName) rc=\(status)"
        throw SDKException(code: .processingFailed, message: message, category: .internal)
    }
    return try NativeProtoABI.decode(responseType, from: outBuffer)
}

func destroyRAGProtoSessionIfAvailable(_ session: rac_handle_t) {
    RAGSessionProtoABI.destroy?(session)
}

// MARK: - LLM custom

extension CppBridge.LLM {
    @discardableResult
    public func cancelProto() throws -> RASDKEvent {
        let cancel = try NativeProtoABI.require(
            LLMCancelProtoABI.cancel,
            named: LLMCancelProtoABI.cancelName
        )
        return try decodeBuffer(
            responseType: RASDKEvent.self,
            symbolName: LLMCancelProtoABI.cancelName
        ) { outBuffer in
            cancel(outBuffer)
        }
    }
}

// MARK: - TTS custom

extension CppBridge.TTS {
    public func listVoices() async throws -> [RATTSVoiceInfo] {
        let handle = try await getHandle()
        let listVoices = try NativeProtoABI.require(
            TTSListVoicesProtoABI.listVoices,
            named: TTSListVoicesProtoABI.listVoicesName
        )
        let context = ProtoCollectingContext<RATTSVoiceInfo>(category: "CppBridge.TTS.ProtoVoices")
        let contextPtr = Unmanaged.passRetained(context).toOpaque()
        let rc = listVoices(handle, { bytes, size, userData in
            guard let userData else { return }
            Unmanaged<ProtoCollectingContext<RATTSVoiceInfo>>
                .fromOpaque(userData)
                .takeUnretainedValue()
                .append(bytes: bytes, size: size)
        }, contextPtr)
        Unmanaged<ProtoCollectingContext<RATTSVoiceInfo>>
            .fromOpaque(contextPtr)
            .release()
        guard rc == RAC_SUCCESS else {
            throw SDKException(code: .processingFailed, message: "TTS voice listing failed: \(rc)", category: .internal)
        }
        return context.values
    }
}

// MARK: - VAD custom

extension CppBridge.VAD {
    public func configure(_ config: RAVADConfiguration) async throws {
        let handle = try await getHandle()
        let configure = try NativeProtoABI.require(
            VADComponentProtoABI.configure,
            named: VADComponentProtoABI.configureName
        )
        let rc = try NativeProtoABI.withSerializedBytes(config) { bytes, size in
            configure(handle, bytes, size)
        }
        guard rc == RAC_SUCCESS else {
            throw SDKException(code: .invalidConfiguration, message: "VAD configure proto failed: \(rc)", category: .component)
        }
    }

    public func process(samples: [Float], options: RAVADOptions) async throws -> RAVADResult {
        let handle = try await getHandle()
        let process = try NativeProtoABI.require(
            VADComponentProtoABI.process,
            named: VADComponentProtoABI.processName
        )
        return try decodeBuffer(
            responseType: RAVADResult.self,
            symbolName: VADComponentProtoABI.processName
        ) { outBuffer in
            try NativeProtoABI.withSerializedBytes(options) { optionBytes, optionSize in
                samples.withUnsafeBufferPointer { sampleBuffer in
                    process(
                        handle,
                        sampleBuffer.baseAddress,
                        samples.count,
                        optionBytes,
                        optionSize,
                        outBuffer
                    )
                }
            }
        }
    }

    public func statisticsProto() async throws -> RAVADStatistics {
        let handle = try await getHandle()
        let statistics = try NativeProtoABI.require(
            VADComponentProtoABI.statistics,
            named: VADComponentProtoABI.statisticsName
        )
        return try decodeBuffer(
            responseType: RAVADStatistics.self,
            symbolName: VADComponentProtoABI.statisticsName
        ) { outBuffer in
            statistics(handle, outBuffer)
        }
    }

    public func setActivityCallbackProto(_ callback: @escaping (RASpeechActivityEvent) -> Void) async throws {
        let handle = try await getHandle()
        let setCallback = try NativeProtoABI.require(
            VADComponentProtoABI.setActivityCallback,
            named: VADComponentProtoABI.setActivityCallbackName
        )
        let context = ProtoProgressContext<RASpeechActivityEvent>(
            category: "CppBridge.VAD.ProtoActivity"
        ) { event in
            callback(event)
            return true
        }
        let contextPtr = Unmanaged.passRetained(context).toOpaque()
        let rc = setCallback(handle, { bytes, size, userData in
            guard let userData else { return }
            _ = Unmanaged<ProtoProgressContext<RASpeechActivityEvent>>
                .fromOpaque(userData)
                .takeUnretainedValue()
                .emit(bytes: bytes, size: size)
        }, contextPtr)
        guard rc == RAC_SUCCESS else {
            Unmanaged<ProtoProgressContext<RASpeechActivityEvent>>
                .fromOpaque(contextPtr)
                .release()
            throw SDKException(code: .processingFailed, message: "VAD activity callback failed: \(rc)", category: .component)
        }
    }

    // MARK: - Lifecycle-proto surface (SWIFT-VAD-001) — state-only
    //
    // These three calls bind the Swift actor to the C++ lifecycle's VAD
    // component instead of the private `rac_vad_component_*` handle. Without
    // this, loading a VAD model through `RunAnywhere.loadModel(...)` (which
    // routes through the commons lifecycle) never connects to the handle the
    // VAD actor owned — VAD reported "not loaded" and never fired events.

    public func startLifecycle() throws -> RAVADServiceState {
        let start = try NativeProtoABI.require(
            VADLifecycleStateProtoABI.start,
            named: VADLifecycleStateProtoABI.startName
        )
        return try decodeBuffer(
            responseType: RAVADServiceState.self,
            symbolName: VADLifecycleStateProtoABI.startName
        ) { outBuffer in
            start(outBuffer)
        }
    }

    public func stopLifecycle() throws -> RAVADServiceState {
        let stop = try NativeProtoABI.require(
            VADLifecycleStateProtoABI.stop,
            named: VADLifecycleStateProtoABI.stopName
        )
        return try decodeBuffer(
            responseType: RAVADServiceState.self,
            symbolName: VADLifecycleStateProtoABI.stopName
        ) { outBuffer in
            stop(outBuffer)
        }
    }

    public func resetLifecycle() throws -> RAVADServiceState {
        let reset = try NativeProtoABI.require(
            VADLifecycleStateProtoABI.reset,
            named: VADLifecycleStateProtoABI.resetName
        )
        return try decodeBuffer(
            responseType: RAVADServiceState.self,
            symbolName: VADLifecycleStateProtoABI.resetName
        ) { outBuffer in
            reset(outBuffer)
        }
    }
}

// MARK: - Voice Agent custom

extension CppBridge.VoiceAgent {
    public func componentStatesProto() throws -> RAVoiceAgentComponentStates {
        let handle = try requireExistingHandle()
        let states = try NativeProtoABI.require(
            VoiceAgentStateProtoABI.states,
            named: VoiceAgentStateProtoABI.statesName
        )
        return try decodeBuffer(
            responseType: RAVoiceAgentComponentStates.self,
            symbolName: VoiceAgentStateProtoABI.statesName
        ) { outBuffer in
            states(handle, outBuffer)
        }
    }

    public func processVoiceTurnProto(_ audioData: Data) async throws -> RAVoiceAgentResult {
        let handle = try await getHandle()
        let processTurn = try NativeProtoABI.require(
            VoiceAgentStateProtoABI.processTurn,
            named: VoiceAgentStateProtoABI.processTurnName
        )
        return try decodeBuffer(
            responseType: RAVoiceAgentResult.self,
            symbolName: VoiceAgentStateProtoABI.processTurnName
        ) { outBuffer in
            audioData.withUnsafeBytes { audio in
                processTurn(handle, audio.baseAddress, audioData.count, outBuffer)
            }
        }
    }
}

// MARK: - VLM custom

extension CppBridge.VLM {
    public func process(image: RAVLMImage, options: RAVLMGenerationOptions) async throws -> RAVLMResult {
        let handle = try await getHandle()
        let process = try NativeProtoABI.require(
            VLMGeneratedProtoABI.process,
            named: VLMGeneratedProtoABI.processName
        )
        let imageData = try image.serializedData()
        return try decodeBuffer(
            responseType: RAVLMResult.self,
            symbolName: VLMGeneratedProtoABI.processName
        ) { outBuffer in
            try NativeProtoABI.withSerializedBytes(options) { optionBytes, optionSize in
                imageData.withUnsafeBytes { imageBytes in
                    process(
                        handle,
                        imageBytes.bindMemory(to: UInt8.self).baseAddress,
                        imageBytes.count,
                        optionBytes,
                        optionSize,
                        outBuffer
                    )
                }
            }
        }
    }

    public func processStream(image: RAVLMImage, options: RAVLMGenerationOptions) async throws -> AsyncStream<RASDKEvent> {
        let handle = try await getHandle()
        let stream = try NativeProtoABI.require(
            VLMGeneratedProtoABI.stream,
            named: VLMGeneratedProtoABI.streamName
        )
        let imageData = try image.serializedData()
        let optionData = try options.serializedData()
        return AsyncStream { continuation in
            let context = ProtoStreamContext<RASDKEvent>(
                continuation: continuation,
                category: "CppBridge.VLM.ProtoStream"
            )
            let contextPtr = Unmanaged.passRetained(context).toOpaque()
            Task.detached {
                var outBuffer = rac_proto_buffer_t()
                defer { NativeProtoABI.free(&outBuffer) }
                let rc = imageData.withUnsafeBytes { imageRaw in
                    optionData.withUnsafeBytes { optionRaw in
                        stream(
                            handle,
                            imageRaw.bindMemory(to: UInt8.self).baseAddress,
                            imageRaw.count,
                            optionRaw.bindMemory(to: UInt8.self).baseAddress,
                            optionRaw.count,
                            { bytes, size, userData in
                                guard let userData else { return RAC_TRUE }
                                Unmanaged<ProtoStreamContext<RASDKEvent>>
                                    .fromOpaque(userData)
                                    .takeUnretainedValue()
                                    .yield(bytes: bytes, size: size)
                                return RAC_TRUE
                            },
                            contextPtr,
                            &outBuffer
                        )
                    }
                }
                Unmanaged<ProtoStreamContext<RASDKEvent>>
                    .fromOpaque(contextPtr)
                    .release()
                if rc != RAC_SUCCESS {
                    SDKLogger(category: "CppBridge.VLM.ProtoStream")
                        .warning("VLM proto stream failed: \(rc)")
                }
                continuation.finish()
            }
        }
    }

    public func cancelProto() async throws {
        guard let handle = try? await getHandle() else { return }
        let cancel = try NativeProtoABI.require(
            VLMGeneratedProtoABI.cancel,
            named: VLMGeneratedProtoABI.cancelName
        )
        let rc = cancel(handle)
        guard rc == RAC_SUCCESS else {
            throw SDKException(code: .cancelled, message: "VLM cancel proto failed: \(rc)", category: .component)
        }
    }
}

// MARK: - Embeddings namespace
//
// The generated file emits `static func embedBatch(handle:, request:)` into
// `extension CppBridge.EmbeddingsProto`. We declare the empty namespace here
// because Swift requires the outer enum to exist before generated extensions
// can attach to it.

extension CppBridge {
    /// Embeddings proto namespace. Methods live in
    /// `Generated/ModalityProtoABI+Generated.swift`.
    public enum EmbeddingsProto {}
}

// MARK: - RAG custom

extension CppBridge.RAG {
    public func createPipeline(config: RARAGConfiguration) throws {
        let create = try NativeProtoABI.require(
            RAGSessionProtoABI.create,
            named: RAGSessionProtoABI.createName
        )
        var newSession: rac_handle_t?
        let rc = try NativeProtoABI.withSerializedBytes(config) { bytes, size in
            create(bytes, size, &newSession)
        }
        guard rc == RAC_SUCCESS, let newSession else {
            throw SDKException(code: .notInitialized, message: "RAG proto session create failed: \(rc)", category: .component)
        }
        setProtoSession(newSession)
    }

    public func clearProto() throws -> RARAGStatistics {
        let session = try requireProtoSession()
        let clear = try NativeProtoABI.require(
            RAGSessionProtoABI.clear,
            named: RAGSessionProtoABI.clearName
        )
        return try decodeBuffer(
            responseType: RARAGStatistics.self,
            symbolName: RAGSessionProtoABI.clearName
        ) { outBuffer in
            clear(session, outBuffer)
        }
    }

    public func statsProto() throws -> RARAGStatistics {
        let session = try requireProtoSession()
        let stats = try NativeProtoABI.require(
            RAGSessionProtoABI.stats,
            named: RAGSessionProtoABI.statsName
        )
        return try decodeBuffer(
            responseType: RARAGStatistics.self,
            symbolName: RAGSessionProtoABI.statsName
        ) { outBuffer in
            stats(session, outBuffer)
        }
    }
}
