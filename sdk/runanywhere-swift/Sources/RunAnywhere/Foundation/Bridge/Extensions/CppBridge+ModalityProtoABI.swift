//
//  CppBridge+ModalityProtoABI.swift
//  RunAnywhere SDK
//
//  Optional generated-proto ABI bindings for modality operations.
//

import CRACommons
import Foundation
import os
import SwiftProtobuf

// MARK: - C symbol tables

private enum LLMGeneratedProtoABI {
    typealias StreamCallback = @convention(c) (
        UnsafePointer<UInt8>?,
        Int,
        UnsafeMutableRawPointer?
    ) -> Void
    typealias Stream = @convention(c) (
        UnsafePointer<UInt8>?,
        Int,
        StreamCallback?,
        UnsafeMutableRawPointer?
    ) -> rac_result_t
    typealias Cancel = @convention(c) (
        UnsafeMutablePointer<rac_proto_buffer_t>?
    ) -> rac_result_t

    static let generateName = "rac_llm_generate_proto"
    static let streamName = "rac_llm_generate_stream_proto"
    static let cancelName = "rac_llm_cancel_proto"

    static let generate = NativeProtoABI.load(generateName, as: NativeProtoABI.ProtoRequest.self)
    static let stream = NativeProtoABI.load(streamName, as: Stream.self)
    static let cancel = NativeProtoABI.load(cancelName, as: Cancel.self)
}

private enum STTGeneratedProtoABI {
    // Lifecycle-owned transcribe: takes no handle parameter, uses the
    // currently-loaded STT component from the commons lifecycle directly.
    // Fixes the Swift-actor-handle-separate-from-lifecycle bug that made
    // transcribe() throw "STT model not loaded" after RunAnywhere.loadModel()
    // returned success. Mirrors LLM's handle-less rac_llm_generate_proto.
    typealias Transcribe = @convention(c) (
        UnsafePointer<UInt8>?,
        Int,
        UnsafeMutablePointer<rac_proto_buffer_t>?
    ) -> rac_result_t
    typealias StreamEventCallback = @convention(c) (
        UnsafePointer<UInt8>?,
        Int,
        UnsafeMutableRawPointer?
    ) -> Void
    typealias TranscribeStream = @convention(c) (
        UnsafePointer<UInt8>?,
        Int,
        StreamEventCallback?,
        UnsafeMutableRawPointer?
    ) -> rac_result_t

    static let transcribeName = "rac_stt_transcribe_lifecycle_proto"
    static let streamName = "rac_stt_transcribe_stream_lifecycle_proto"

    static let transcribe = NativeProtoABI.load(transcribeName, as: Transcribe.self)
    static let stream = NativeProtoABI.load(streamName, as: TranscribeStream.self)
}

private enum TTSGeneratedProtoABI {
    typealias VoiceCallback = @convention(c) (
        UnsafePointer<UInt8>?,
        Int,
        UnsafeMutableRawPointer?
    ) -> Void
    typealias ChunkCallback = VoiceCallback
    typealias ListVoices = @convention(c) (
        rac_handle_t?,
        VoiceCallback?,
        UnsafeMutableRawPointer?
    ) -> rac_result_t
    // Lifecycle-owned synthesize: takes no handle parameter.
    typealias Synthesize = @convention(c) (
        UnsafePointer<UInt8>?,
        Int,
        UnsafeMutablePointer<rac_proto_buffer_t>?
    ) -> rac_result_t
    typealias SynthesizeStream = @convention(c) (
        UnsafePointer<UInt8>?,
        Int,
        ChunkCallback?,
        UnsafeMutableRawPointer?
    ) -> rac_result_t

    static let listVoicesName = "rac_tts_component_list_voices_proto"
    static let synthesizeName = "rac_tts_synthesize_lifecycle_proto"
    static let streamName = "rac_tts_synthesize_stream_lifecycle_proto"

    static let listVoices = NativeProtoABI.load(listVoicesName, as: ListVoices.self)
    static let synthesize = NativeProtoABI.load(synthesizeName, as: Synthesize.self)
    static let stream = NativeProtoABI.load(streamName, as: SynthesizeStream.self)
}

private enum VADGeneratedProtoABI {
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

private enum VADLifecycleProtoABI {
    // Lifecycle-owned VAD operations: take no handle parameter, use the
    // currently-loaded VAD component from the commons lifecycle directly.
    // Fixes the Swift-actor-handle-separate-from-lifecycle bug (SWIFT-VAD-001)
    // that made VAD never fire speech-start/end events. Mirrors the STT/TTS
    // handle-less proto surfaces landed in Phase 6h.
    typealias ProcessOrConfigure = @convention(c) (
        UnsafePointer<UInt8>?,
        Int,
        UnsafeMutablePointer<rac_proto_buffer_t>?
    ) -> rac_result_t
    typealias StateOnly = @convention(c) (
        UnsafeMutablePointer<rac_proto_buffer_t>?
    ) -> rac_result_t

    static let processName = "rac_vad_process_lifecycle_proto"
    static let configureName = "rac_vad_configure_lifecycle_proto"
    static let startName = "rac_vad_start_lifecycle_proto"
    static let stopName = "rac_vad_stop_lifecycle_proto"
    static let resetName = "rac_vad_reset_lifecycle_proto"

    static let process = NativeProtoABI.load(processName, as: ProcessOrConfigure.self)
    static let configure = NativeProtoABI.load(configureName, as: ProcessOrConfigure.self)
    static let start = NativeProtoABI.load(startName, as: StateOnly.self)
    static let stop = NativeProtoABI.load(stopName, as: StateOnly.self)
    static let reset = NativeProtoABI.load(resetName, as: StateOnly.self)
}

private enum VoiceAgentGeneratedProtoABI {
    typealias Initialize = @convention(c) (
        rac_voice_agent_handle_t?,
        UnsafePointer<UInt8>?,
        Int,
        UnsafeMutablePointer<rac_proto_buffer_t>?
    ) -> rac_result_t
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

    static let initializeName = "rac_voice_agent_initialize_proto"
    static let statesName = "rac_voice_agent_component_states_proto"
    static let processTurnName = "rac_voice_agent_process_voice_turn_proto"

    static let initialize = NativeProtoABI.load(initializeName, as: Initialize.self)
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

private enum EmbeddingsGeneratedProtoABI {
    typealias EmbedBatch = @convention(c) (
        rac_handle_t?,
        UnsafePointer<UInt8>?,
        Int,
        UnsafeMutablePointer<rac_proto_buffer_t>?
    ) -> rac_result_t

    static let embedBatchName = "rac_embeddings_embed_batch_proto"
    static let embedBatch = NativeProtoABI.load(embedBatchName, as: EmbedBatch.self)
}

private enum RAGGeneratedProtoABI {
    typealias Create = @convention(c) (
        UnsafePointer<UInt8>?,
        Int,
        UnsafeMutablePointer<rac_handle_t?>?
    ) -> rac_result_t
    typealias Destroy = @convention(c) (rac_handle_t?) -> Void
    typealias Request = @convention(c) (
        rac_handle_t?,
        UnsafePointer<UInt8>?,
        Int,
        UnsafeMutablePointer<rac_proto_buffer_t>?
    ) -> rac_result_t
    typealias NoRequest = @convention(c) (
        rac_handle_t?,
        UnsafeMutablePointer<rac_proto_buffer_t>?
    ) -> rac_result_t

    static let createName = "rac_rag_session_create_proto"
    static let destroyName = "rac_rag_session_destroy_proto"
    static let ingestName = "rac_rag_ingest_proto"
    static let queryName = "rac_rag_query_proto"
    static let clearName = "rac_rag_clear_proto"
    static let statsName = "rac_rag_stats_proto"

    static let create = NativeProtoABI.load(createName, as: Create.self)
    static let destroy = NativeProtoABI.load(destroyName, as: Destroy.self)
    static let ingest = NativeProtoABI.load(ingestName, as: Request.self)
    static let query = NativeProtoABI.load(queryName, as: Request.self)
    static let clear = NativeProtoABI.load(clearName, as: NoRequest.self)
    static let stats = NativeProtoABI.load(statsName, as: NoRequest.self)
}

private enum LoRAGeneratedProtoABI {
    typealias RegistryRequest = @convention(c) (
        rac_lora_registry_handle_t?,
        UnsafePointer<UInt8>?,
        Int,
        UnsafeMutablePointer<rac_proto_buffer_t>?
    ) -> rac_result_t
    typealias LLMRequest = @convention(c) (
        rac_handle_t?,
        UnsafePointer<UInt8>?,
        Int,
        UnsafeMutablePointer<rac_proto_buffer_t>?
    ) -> rac_result_t
    static let registerName = "rac_lora_register_proto"
    static let catalogListName = "rac_lora_catalog_list_proto"
    static let catalogQueryName = "rac_lora_catalog_query_proto"
    static let catalogGetName = "rac_lora_catalog_get_proto"
    static let catalogMarkDownloadCompletedName = "rac_lora_catalog_mark_download_completed_proto"
    static let compatibilityName = "rac_lora_compatibility_proto"
    static let applyName = "rac_lora_apply_proto"
    static let removeName = "rac_lora_remove_proto"
    static let listName = "rac_lora_list_proto"
    static let stateName = "rac_lora_state_proto"

    static let register = NativeProtoABI.load(registerName, as: RegistryRequest.self)
    static let catalogList = NativeProtoABI.load(catalogListName, as: RegistryRequest.self)
    static let catalogQuery = NativeProtoABI.load(catalogQueryName, as: RegistryRequest.self)
    static let catalogGet = NativeProtoABI.load(catalogGetName, as: RegistryRequest.self)
    static let catalogMarkDownloadCompleted = NativeProtoABI.load(
        catalogMarkDownloadCompletedName,
        as: RegistryRequest.self
    )
    static let compatibility = NativeProtoABI.load(compatibilityName, as: LLMRequest.self)
    static let apply = NativeProtoABI.load(applyName, as: LLMRequest.self)
    static let remove = NativeProtoABI.load(removeName, as: LLMRequest.self)
    static let list = NativeProtoABI.load(listName, as: LLMRequest.self)
    static let state = NativeProtoABI.load(stateName, as: LLMRequest.self)
}

// MARK: - Callback contexts

/// Non-generic protocol that exposes the byte-yield entry point. The C
/// trampoline can only see non-generic types (Swift forbids generic captures
/// in `@convention(c)` closures), so we bridge through this protocol and let
/// dynamic dispatch reach the generic body in `ProtoStreamContext.yield`.
private protocol ProtoStreamYielder: AnyObject {
    func yield(bytes: UnsafePointer<UInt8>?, size: Int)
}

/// Single shared C trampoline used by `ProtoStreamContext.runRequestStream`.
/// Holds no generic state; recovers the yielder via `Unmanaged` and dispatches
/// dynamically through `ProtoStreamYielder`.
private let protoStreamTrampoline: @convention(c) (
    UnsafePointer<UInt8>?,
    Int,
    UnsafeMutableRawPointer?
) -> Void = { bytes, size, userData in
    guard let userData else { return }
    let yielder = Unmanaged<AnyObject>.fromOpaque(userData).takeUnretainedValue()
    (yielder as? ProtoStreamYielder)?.yield(bytes: bytes, size: size)
}

private final class ProtoStreamContext<Event: Message>: @unchecked Sendable, ProtoStreamYielder {
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
    RAGGeneratedProtoABI.destroy?(session)
}

// MARK: - LLM

extension CppBridge.LLM {
    public func generate(_ request: RALLMGenerateRequest) throws -> RALLMGenerationResult {
        try NativeProtoABI.invoke(
            request,
            symbol: LLMGeneratedProtoABI.generate,
            symbolName: LLMGeneratedProtoABI.generateName,
            responseType: RALLMGenerationResult.self
        )
    }

    public func generateStream(_ request: RALLMGenerateRequest) throws -> AsyncStream<RALLMStreamEvent> {
        let stream = try NativeProtoABI.require(
            LLMGeneratedProtoABI.stream,
            named: LLMGeneratedProtoABI.streamName
        )
        return try ProtoStreamContext<RALLMStreamEvent>.runRequestStream(
            request: request,
            category: "CppBridge.LLM.ProtoStream",
            onError: { rc in
                let mapped = CommonsErrorMapping.toSDKException(rc)
                var event = RALLMStreamEvent()
                event.isFinal = true
                event.finishReason = "error"
                event.errorCode = rc
                event.errorMessage = mapped?.message ?? "LLM stream failed: \(rc)"
                return event
            },
            body: { bytes, size, trampoline, userData in
                stream(bytes, size, trampoline, userData)
            }
        )
    }

    @discardableResult
    public func cancelProto() throws -> RASDKEvent {
        let cancel = try NativeProtoABI.require(
            LLMGeneratedProtoABI.cancel,
            named: LLMGeneratedProtoABI.cancelName
        )
        return try decodeBuffer(
            responseType: RASDKEvent.self,
            symbolName: LLMGeneratedProtoABI.cancelName
        ) { outBuffer in
            cancel(outBuffer)
        }
    }
}

// MARK: - STT

extension CppBridge.STT {
    public func transcribe(audioData: Data, options: RASTTOptions) throws -> RASTTOutput {
        // Lifecycle-owned transcribe: binds to the currently-loaded STT
        // model from the commons lifecycle directly (no Swift actor handle).
        // Swift must now wrap audio + options into a STTTranscriptionRequest
        // proto before calling; the lifecycle C API parses the proto and
        // delegates to the lifecycle's STT service ops.
        let transcribe = try NativeProtoABI.require(
            STTGeneratedProtoABI.transcribe,
            named: STTGeneratedProtoABI.transcribeName
        )
        var request = RASTTTranscriptionRequest()
        var audioSource = RASTTAudioSource()
        audioSource.audioData = audioData
        request.audio = audioSource
        request.options = options
        return try decodeBuffer(
            responseType: RASTTOutput.self,
            symbolName: STTGeneratedProtoABI.transcribeName
        ) { outBuffer in
            try NativeProtoABI.withSerializedBytes(request) { bytes, size in
                transcribe(bytes, size, outBuffer)
            }
        }
    }

    public func transcribeStream(audioData: Data, options: RASTTOptions) throws -> AsyncStream<RASTTPartialResult> {
        let stream = try NativeProtoABI.require(
            STTGeneratedProtoABI.stream,
            named: STTGeneratedProtoABI.streamName
        )
        var request = RASTTTranscriptionRequest()
        var audioSource = RASTTAudioSource()
        audioSource.audioData = audioData
        request.audio = audioSource
        request.options = options
        return try ProtoStreamContext<RASTTPartialResult>.runRequestStream(
            request: request,
            category: "CppBridge.STT.ProtoStream",
            onError: { rc in
                var final = RASTTPartialResult()
                final.isFinal = true
                final.text = "STT stream failed: \(rc)"
                return final
            },
            body: { bytes, size, trampoline, userData in
                stream(bytes, size, trampoline, userData)
            }
        )
    }
}

// MARK: - TTS

extension CppBridge.TTS {
    public func listVoices() throws -> [RATTSVoiceInfo] {
        let handle = try getHandle()
        let listVoices = try NativeProtoABI.require(
            TTSGeneratedProtoABI.listVoices,
            named: TTSGeneratedProtoABI.listVoicesName
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

    public func synthesize(text: String, options: RATTSOptions) throws -> RATTSOutput {
        // Lifecycle-owned synthesize: binds to the TTS voice loaded in the
        // commons lifecycle directly. Mirrors LLM's rac_llm_generate_proto
        // pattern. The handle-based rac_tts_component_synthesize_proto was
        // failing because Swift's CppBridge.TTS actor handle is a separate
        // handle from the lifecycle-owned one (which is what gets loaded by
        // RunAnywhere.loadModel()).
        let synthesize = try NativeProtoABI.require(
            TTSGeneratedProtoABI.synthesize,
            named: TTSGeneratedProtoABI.synthesizeName
        )
        var request = RATTSSynthesisRequest()
        request.text = text
        request.options = options
        return try decodeBuffer(
            responseType: RATTSOutput.self,
            symbolName: TTSGeneratedProtoABI.synthesizeName
        ) { outBuffer in
            try NativeProtoABI.withSerializedBytes(request) { bytes, size in
                synthesize(bytes, size, outBuffer)
            }
        }
    }

    public func synthesizeStream(text: String, options: RATTSOptions) throws -> AsyncStream<RATTSOutput> {
        let stream = try NativeProtoABI.require(
            TTSGeneratedProtoABI.stream,
            named: TTSGeneratedProtoABI.streamName
        )
        var request = RATTSSynthesisRequest()
        request.text = text
        request.options = options
        return try ProtoStreamContext<RATTSOutput>.runRequestStream(
            request: request,
            category: "CppBridge.TTS.ProtoStream",
            onError: { _ in
                var output = RATTSOutput()
                output.timestampMs = Int64(Date().timeIntervalSince1970 * 1000)
                return output
            },
            body: { bytes, size, trampoline, userData in
                stream(bytes, size, trampoline, userData)
            }
        )
    }
}

// MARK: - VAD

extension CppBridge.VAD {
    public func configure(_ config: RAVADConfiguration) throws {
        let handle = try getHandle()
        let configure = try NativeProtoABI.require(
            VADGeneratedProtoABI.configure,
            named: VADGeneratedProtoABI.configureName
        )
        let rc = try NativeProtoABI.withSerializedBytes(config) { bytes, size in
            configure(handle, bytes, size)
        }
        guard rc == RAC_SUCCESS else {
            throw SDKException(code: .invalidConfiguration, message: "VAD configure proto failed: \(rc)", category: .component)
        }
    }

    public func process(samples: [Float], options: RAVADOptions) throws -> RAVADResult {
        let handle = try getHandle()
        let process = try NativeProtoABI.require(
            VADGeneratedProtoABI.process,
            named: VADGeneratedProtoABI.processName
        )
        return try decodeBuffer(
            responseType: RAVADResult.self,
            symbolName: VADGeneratedProtoABI.processName
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

    public func statisticsProto() throws -> RAVADStatistics {
        let handle = try getHandle()
        let statistics = try NativeProtoABI.require(
            VADGeneratedProtoABI.statistics,
            named: VADGeneratedProtoABI.statisticsName
        )
        return try decodeBuffer(
            responseType: RAVADStatistics.self,
            symbolName: VADGeneratedProtoABI.statisticsName
        ) { outBuffer in
            statistics(handle, outBuffer)
        }
    }

    public func setActivityCallbackProto(_ callback: @escaping (RASpeechActivityEvent) -> Void) throws {
        let handle = try getHandle()
        let setCallback = try NativeProtoABI.require(
            VADGeneratedProtoABI.setActivityCallback,
            named: VADGeneratedProtoABI.setActivityCallbackName
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

    // MARK: - Lifecycle-proto surface (SWIFT-VAD-001)
    //
    // These four calls bind the Swift actor to the C++ lifecycle's VAD
    // component instead of the private `rac_vad_component_*` handle. Without
    // this, loading a VAD model through `RunAnywhere.loadModel(...)` (which
    // routes through the commons lifecycle) never connects to the handle the
    // VAD actor owned — VAD reported "not loaded" and never fired events.
    // Mirrors the Phase 6h fix for STT/TTS.

    public func configureLifecycle(_ config: RAVADConfiguration) throws -> RAVADServiceState {
        let configure = try NativeProtoABI.require(
            VADLifecycleProtoABI.configure,
            named: VADLifecycleProtoABI.configureName
        )
        return try decodeBuffer(
            responseType: RAVADServiceState.self,
            symbolName: VADLifecycleProtoABI.configureName
        ) { outBuffer in
            try NativeProtoABI.withSerializedBytes(config) { bytes, size in
                configure(bytes, size, outBuffer)
            }
        }
    }

    public func startLifecycle() throws -> RAVADServiceState {
        let start = try NativeProtoABI.require(
            VADLifecycleProtoABI.start,
            named: VADLifecycleProtoABI.startName
        )
        return try decodeBuffer(
            responseType: RAVADServiceState.self,
            symbolName: VADLifecycleProtoABI.startName
        ) { outBuffer in
            start(outBuffer)
        }
    }

    public func stopLifecycle() throws -> RAVADServiceState {
        let stop = try NativeProtoABI.require(
            VADLifecycleProtoABI.stop,
            named: VADLifecycleProtoABI.stopName
        )
        return try decodeBuffer(
            responseType: RAVADServiceState.self,
            symbolName: VADLifecycleProtoABI.stopName
        ) { outBuffer in
            stop(outBuffer)
        }
    }

    public func resetLifecycle() throws -> RAVADServiceState {
        let reset = try NativeProtoABI.require(
            VADLifecycleProtoABI.reset,
            named: VADLifecycleProtoABI.resetName
        )
        return try decodeBuffer(
            responseType: RAVADServiceState.self,
            symbolName: VADLifecycleProtoABI.resetName
        ) { outBuffer in
            reset(outBuffer)
        }
    }

    public func processLifecycle(request: RAVADProcessRequest) throws -> RAVADResult {
        let process = try NativeProtoABI.require(
            VADLifecycleProtoABI.process,
            named: VADLifecycleProtoABI.processName
        )
        return try decodeBuffer(
            responseType: RAVADResult.self,
            symbolName: VADLifecycleProtoABI.processName
        ) { outBuffer in
            try NativeProtoABI.withSerializedBytes(request) { bytes, size in
                process(bytes, size, outBuffer)
            }
        }
    }
}

// MARK: - Voice Agent

extension CppBridge.VoiceAgent {
    public func initialize(_ config: RAVoiceAgentComposeConfig) async throws -> RAVoiceAgentComponentStates {
        let handle = try await getHandle()
        let initialize = try NativeProtoABI.require(
            VoiceAgentGeneratedProtoABI.initialize,
            named: VoiceAgentGeneratedProtoABI.initializeName
        )
        return try decodeBuffer(
            responseType: RAVoiceAgentComponentStates.self,
            symbolName: VoiceAgentGeneratedProtoABI.initializeName
        ) { outBuffer in
            try NativeProtoABI.withSerializedBytes(config) { bytes, size in
                initialize(handle, bytes, size, outBuffer)
            }
        }
    }

    public func componentStatesProto() throws -> RAVoiceAgentComponentStates {
        let handle = try requireExistingHandle()
        let states = try NativeProtoABI.require(
            VoiceAgentGeneratedProtoABI.states,
            named: VoiceAgentGeneratedProtoABI.statesName
        )
        return try decodeBuffer(
            responseType: RAVoiceAgentComponentStates.self,
            symbolName: VoiceAgentGeneratedProtoABI.statesName
        ) { outBuffer in
            states(handle, outBuffer)
        }
    }

    public func processVoiceTurnProto(_ audioData: Data) async throws -> RAVoiceAgentResult {
        let handle = try await getHandle()
        let processTurn = try NativeProtoABI.require(
            VoiceAgentGeneratedProtoABI.processTurn,
            named: VoiceAgentGeneratedProtoABI.processTurnName
        )
        return try decodeBuffer(
            responseType: RAVoiceAgentResult.self,
            symbolName: VoiceAgentGeneratedProtoABI.processTurnName
        ) { outBuffer in
            audioData.withUnsafeBytes { audio in
                processTurn(handle, audio.baseAddress, audioData.count, outBuffer)
            }
        }
    }
}

// MARK: - VLM

extension CppBridge.VLM {
    public func process(image: RAVLMImage, options: RAVLMGenerationOptions) throws -> RAVLMResult {
        let handle = try getHandle()
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

    public func processStream(image: RAVLMImage, options: RAVLMGenerationOptions) throws -> AsyncStream<RASDKEvent> {
        let handle = try getHandle()
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

    public func cancelProto() throws {
        guard let handle = try? getHandle() else { return }
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

// MARK: - Embeddings

extension CppBridge {
    public enum EmbeddingsProto {
        public static func embedBatch(handle: rac_handle_t, request: RAEmbeddingsRequest) throws -> RAEmbeddingsResult {
            let embed = try NativeProtoABI.require(
                EmbeddingsGeneratedProtoABI.embedBatch,
                named: EmbeddingsGeneratedProtoABI.embedBatchName
            )
            return try decodeBuffer(
                responseType: RAEmbeddingsResult.self,
                symbolName: EmbeddingsGeneratedProtoABI.embedBatchName
            ) { outBuffer in
                try NativeProtoABI.withSerializedBytes(request) { bytes, size in
                    embed(handle, bytes, size, outBuffer)
                }
            }
        }
    }
}

// MARK: - RAG

extension CppBridge.RAG {
    public func createPipeline(config: RARAGConfiguration) throws {
        let create = try NativeProtoABI.require(
            RAGGeneratedProtoABI.create,
            named: RAGGeneratedProtoABI.createName
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

    public func ingest(_ document: RARAGDocument) throws -> RARAGStatistics {
        let session = try requireProtoSession()
        return try NativeProtoABI.invoke(
            document,
            on: session,
            symbol: RAGGeneratedProtoABI.ingest,
            symbolName: RAGGeneratedProtoABI.ingestName,
            responseType: RARAGStatistics.self
        )
    }

    public func query(_ options: RARAGQueryOptions) throws -> RARAGResult {
        let session = try requireProtoSession()
        return try NativeProtoABI.invoke(
            options,
            on: session,
            symbol: RAGGeneratedProtoABI.query,
            symbolName: RAGGeneratedProtoABI.queryName,
            responseType: RARAGResult.self
        )
    }

    public func clearProto() throws -> RARAGStatistics {
        let session = try requireProtoSession()
        let clear = try NativeProtoABI.require(
            RAGGeneratedProtoABI.clear,
            named: RAGGeneratedProtoABI.clearName
        )
        return try decodeBuffer(
            responseType: RARAGStatistics.self,
            symbolName: RAGGeneratedProtoABI.clearName
        ) { outBuffer in
            clear(session, outBuffer)
        }
    }

    public func statsProto() throws -> RARAGStatistics {
        let session = try requireProtoSession()
        let stats = try NativeProtoABI.require(
            RAGGeneratedProtoABI.stats,
            named: RAGGeneratedProtoABI.statsName
        )
        return try decodeBuffer(
            responseType: RARAGStatistics.self,
            symbolName: RAGGeneratedProtoABI.statsName
        ) { outBuffer in
            stats(session, outBuffer)
        }
    }

}

// MARK: - LoRA

extension CppBridge.LLM {
    public func applyLoraAdapters(_ request: RALoRAApplyRequest) throws -> RALoRAApplyResult {
        let handle = try getHandle()
        return try NativeProtoABI.invoke(
            request,
            on: handle,
            symbol: LoRAGeneratedProtoABI.apply,
            symbolName: LoRAGeneratedProtoABI.applyName,
            responseType: RALoRAApplyResult.self
        )
    }

    public func removeLoraAdapters(_ request: RALoRARemoveRequest) throws -> RALoRAState {
        let handle = try getHandle()
        return try NativeProtoABI.invoke(
            request,
            on: handle,
            symbol: LoRAGeneratedProtoABI.remove,
            symbolName: LoRAGeneratedProtoABI.removeName,
            responseType: RALoRAState.self
        )
    }

    public func listLoraAdapters() throws -> RALoRAState {
        let handle = try getHandle()
        return try NativeProtoABI.invoke(
            RALoRAState(),
            on: handle,
            symbol: LoRAGeneratedProtoABI.list,
            symbolName: LoRAGeneratedProtoABI.listName,
            responseType: RALoRAState.self
        )
    }

    public func getLoraState() throws -> RALoRAState {
        let handle = try getHandle()
        return try NativeProtoABI.invoke(
            RALoRAState(),
            on: handle,
            symbol: LoRAGeneratedProtoABI.state,
            symbolName: LoRAGeneratedProtoABI.stateName,
            responseType: RALoRAState.self
        )
    }

    public func checkLoraCompatibility(_ config: RALoRAAdapterConfig) throws -> RALoraCompatibilityResult {
        let handle = try getHandle()
        return try NativeProtoABI.invoke(
            config,
            on: handle,
            symbol: LoRAGeneratedProtoABI.compatibility,
            symbolName: LoRAGeneratedProtoABI.compatibilityName,
            responseType: RALoraCompatibilityResult.self
        )
    }
}

extension CppBridge.LoraRegistry {
    public func register(_ entry: RALoraAdapterCatalogEntry) throws -> RALoraAdapterCatalogEntry {
        let handle = try requireRegistryHandle()
        return try NativeProtoABI.invoke(
            entry,
            on: handle,
            symbol: LoRAGeneratedProtoABI.register,
            symbolName: LoRAGeneratedProtoABI.registerName,
            responseType: RALoraAdapterCatalogEntry.self
        )
    }

    public func listCatalog(
        _ request: RALoraAdapterCatalogListRequest
    ) throws -> RALoraAdapterCatalogListResult {
        let handle = try requireRegistryHandle()
        return try NativeProtoABI.invoke(
            request,
            on: handle,
            symbol: LoRAGeneratedProtoABI.catalogList,
            symbolName: LoRAGeneratedProtoABI.catalogListName,
            responseType: RALoraAdapterCatalogListResult.self
        )
    }

    public func queryCatalog(
        _ query: RALoraAdapterCatalogQuery
    ) throws -> RALoraAdapterCatalogListResult {
        let handle = try requireRegistryHandle()
        return try NativeProtoABI.invoke(
            query,
            on: handle,
            symbol: LoRAGeneratedProtoABI.catalogQuery,
            symbolName: LoRAGeneratedProtoABI.catalogQueryName,
            responseType: RALoraAdapterCatalogListResult.self
        )
    }

    public func getCatalogEntry(
        _ request: RALoraAdapterCatalogGetRequest
    ) throws -> RALoraAdapterCatalogGetResult {
        let handle = try requireRegistryHandle()
        return try NativeProtoABI.invoke(
            request,
            on: handle,
            symbol: LoRAGeneratedProtoABI.catalogGet,
            symbolName: LoRAGeneratedProtoABI.catalogGetName,
            responseType: RALoraAdapterCatalogGetResult.self
        )
    }

    public func markDownloadCompleted(
        _ request: RALoraAdapterDownloadCompletedRequest
    ) throws -> RALoraAdapterDownloadCompletedResult {
        let handle = try requireRegistryHandle()
        return try NativeProtoABI.invoke(
            request,
            on: handle,
            symbol: LoRAGeneratedProtoABI.catalogMarkDownloadCompleted,
            symbolName: LoRAGeneratedProtoABI.catalogMarkDownloadCompletedName,
            responseType: RALoraAdapterDownloadCompletedResult.self
        )
    }

    private func requireRegistryHandle() throws -> rac_lora_registry_handle_t {
        guard let handle = rac_get_lora_registry() else {
            throw SDKException(code: .initializationFailed, message: "LoRA registry not initialized", category: .internal)
        }
        return handle
    }
}

