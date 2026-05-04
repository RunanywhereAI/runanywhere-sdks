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
    typealias Transcribe = @convention(c) (
        rac_handle_t?,
        UnsafeRawPointer?,
        Int,
        UnsafePointer<UInt8>?,
        Int,
        UnsafeMutablePointer<rac_proto_buffer_t>?
    ) -> rac_result_t
    typealias PartialCallback = @convention(c) (
        UnsafePointer<UInt8>?,
        Int,
        UnsafeMutableRawPointer?
    ) -> Void
    typealias TranscribeStream = @convention(c) (
        rac_handle_t?,
        UnsafeRawPointer?,
        Int,
        UnsafePointer<UInt8>?,
        Int,
        PartialCallback?,
        UnsafeMutableRawPointer?
    ) -> rac_result_t

    static let transcribeName = "rac_stt_component_transcribe_proto"
    static let streamName = "rac_stt_component_transcribe_stream_proto"

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
    typealias Synthesize = @convention(c) (
        rac_handle_t?,
        UnsafePointer<CChar>?,
        UnsafePointer<UInt8>?,
        Int,
        UnsafeMutablePointer<rac_proto_buffer_t>?
    ) -> rac_result_t
    typealias SynthesizeStream = @convention(c) (
        rac_handle_t?,
        UnsafePointer<CChar>?,
        UnsafePointer<UInt8>?,
        Int,
        ChunkCallback?,
        UnsafeMutableRawPointer?
    ) -> rac_result_t

    static let listVoicesName = "rac_tts_component_list_voices_proto"
    static let synthesizeName = "rac_tts_component_synthesize_proto"
    static let streamName = "rac_tts_component_synthesize_stream_proto"

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
    typealias Clear = @convention(c) (
        rac_handle_t?,
        UnsafeMutablePointer<rac_proto_buffer_t>?
    ) -> rac_result_t

    static let registerName = "rac_lora_register_proto"
    static let compatibilityName = "rac_lora_compatibility_proto"
    static let loadName = "rac_lora_load_proto"
    static let removeName = "rac_lora_remove_proto"
    static let clearName = "rac_lora_clear_proto"

    static let register = NativeProtoABI.load(registerName, as: RegistryRequest.self)
    static let compatibility = NativeProtoABI.load(compatibilityName, as: LLMRequest.self)
    static let load = NativeProtoABI.load(loadName, as: LLMRequest.self)
    static let remove = NativeProtoABI.load(removeName, as: LLMRequest.self)
    static let clear = NativeProtoABI.load(clearName, as: Clear.self)
}

private enum DiffusionGeneratedProtoABI {
    typealias Generate = @convention(c) (
        rac_handle_t?,
        UnsafePointer<UInt8>?,
        Int,
        UnsafeMutablePointer<rac_proto_buffer_t>?
    ) -> rac_result_t
    typealias ProgressCallback = @convention(c) (
        UnsafePointer<UInt8>?,
        Int,
        UnsafeMutableRawPointer?
    ) -> rac_bool_t
    typealias GenerateWithProgress = @convention(c) (
        rac_handle_t?,
        UnsafePointer<UInt8>?,
        Int,
        ProgressCallback?,
        UnsafeMutableRawPointer?,
        UnsafeMutablePointer<rac_proto_buffer_t>?
    ) -> rac_result_t
    typealias Cancel = @convention(c) (rac_handle_t?) -> rac_result_t

    static let generateName = "rac_diffusion_generate_proto"
    static let progressName = "rac_diffusion_generate_with_progress_proto"
    static let cancelName = "rac_diffusion_cancel_proto"

    static let generate = NativeProtoABI.load(generateName, as: Generate.self)
    static let progress = NativeProtoABI.load(progressName, as: GenerateWithProgress.self)
    static let cancel = NativeProtoABI.load(cancelName, as: Cancel.self)
}

// MARK: - Callback contexts

private final class ProtoStreamContext<Event: Message>: @unchecked Sendable {
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
        throw SDKException.general(.notSupported, NativeProtoABI.missingSymbolMessage(symbolName))
    }
    var outBuffer = rac_proto_buffer_t()
    defer { NativeProtoABI.free(&outBuffer) }
    let status = try body(&outBuffer)
    guard status == RAC_SUCCESS else {
        let message = outBuffer.error_message.map { String(cString: $0) }
            ?? "Native proto request failed: \(symbolName) rc=\(status)"
        throw SDKException.general(.processingFailed, message)
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
        let data = try request.serializedData()
        return AsyncStream { continuation in
            let context = ProtoStreamContext<RALLMStreamEvent>(
                continuation: continuation,
                category: "CppBridge.LLM.ProtoStream"
            )
            let contextPtr = Unmanaged.passRetained(context).toOpaque()
            Task.detached {
                let rc = data.withUnsafeBytes { rawBuffer in
                    stream(
                        rawBuffer.bindMemory(to: UInt8.self).baseAddress,
                        rawBuffer.count,
                        { bytes, size, userData in
                            guard let userData else { return }
                            Unmanaged<ProtoStreamContext<RALLMStreamEvent>>
                                .fromOpaque(userData)
                                .takeUnretainedValue()
                                .yield(bytes: bytes, size: size)
                        },
                        contextPtr
                    )
                }
                Unmanaged<ProtoStreamContext<RALLMStreamEvent>>
                    .fromOpaque(contextPtr)
                    .release()
                if rc != RAC_SUCCESS {
                    let mapped = CommonsErrorMapping.toSDKException(rc)
                    var event = RALLMStreamEvent()
                    event.isFinal = true
                    event.finishReason = "error"
                    event.errorCode = rc
                    event.errorMessage = mapped?.message ?? "LLM stream failed: \(rc)"
                    continuation.yield(event)
                }
                continuation.finish()
            }
        }
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
        let handle = try getHandle()
        let transcribe = try NativeProtoABI.require(
            STTGeneratedProtoABI.transcribe,
            named: STTGeneratedProtoABI.transcribeName
        )
        return try decodeBuffer(
            responseType: RASTTOutput.self,
            symbolName: STTGeneratedProtoABI.transcribeName
        ) { outBuffer in
            try NativeProtoABI.withSerializedBytes(options) { optionBytes, optionSize in
                audioData.withUnsafeBytes { audio in
                    transcribe(
                        handle,
                        audio.baseAddress,
                        audioData.count,
                        optionBytes,
                        optionSize,
                        outBuffer
                    )
                }
            }
        }
    }

    public func transcribeStream(audioData: Data, options: RASTTOptions) throws -> AsyncStream<RASTTPartialResult> {
        let handle = try getHandle()
        let stream = try NativeProtoABI.require(
            STTGeneratedProtoABI.stream,
            named: STTGeneratedProtoABI.streamName
        )
        let optionsData = try options.serializedData()
        return AsyncStream { continuation in
            let context = ProtoStreamContext<RASTTPartialResult>(
                continuation: continuation,
                category: "CppBridge.STT.ProtoStream"
            )
            let contextPtr = Unmanaged.passRetained(context).toOpaque()
            Task.detached {
                let rc = optionsData.withUnsafeBytes { optionRaw in
                    audioData.withUnsafeBytes { audioRaw in
                        stream(
                            handle,
                            audioRaw.baseAddress,
                            audioData.count,
                            optionRaw.bindMemory(to: UInt8.self).baseAddress,
                            optionRaw.count,
                            { bytes, size, userData in
                                guard let userData else { return }
                                Unmanaged<ProtoStreamContext<RASTTPartialResult>>
                                    .fromOpaque(userData)
                                    .takeUnretainedValue()
                                    .yield(bytes: bytes, size: size)
                            },
                            contextPtr
                        )
                    }
                }
                Unmanaged<ProtoStreamContext<RASTTPartialResult>>
                    .fromOpaque(contextPtr)
                    .release()
                if rc != RAC_SUCCESS {
                    var final = RASTTPartialResult()
                    final.isFinal = true
                    final.text = "STT stream failed: \(rc)"
                    continuation.yield(final)
                }
                continuation.finish()
            }
        }
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
            throw SDKException.general(.processingFailed, "TTS voice listing failed: \(rc)")
        }
        return context.values
    }

    public func synthesize(text: String, options: RATTSOptions) throws -> RATTSOutput {
        let handle = try getHandle()
        let synthesize = try NativeProtoABI.require(
            TTSGeneratedProtoABI.synthesize,
            named: TTSGeneratedProtoABI.synthesizeName
        )
        return try decodeBuffer(
            responseType: RATTSOutput.self,
            symbolName: TTSGeneratedProtoABI.synthesizeName
        ) { outBuffer in
            try NativeProtoABI.withSerializedBytes(options) { optionBytes, optionSize in
                text.withCString { textPtr in
                    synthesize(handle, textPtr, optionBytes, optionSize, outBuffer)
                }
            }
        }
    }

    public func synthesizeStream(text: String, options: RATTSOptions) throws -> AsyncStream<RATTSOutput> {
        let handle = try getHandle()
        let stream = try NativeProtoABI.require(
            TTSGeneratedProtoABI.stream,
            named: TTSGeneratedProtoABI.streamName
        )
        let optionData = try options.serializedData()
        return AsyncStream { continuation in
            let context = ProtoStreamContext<RATTSOutput>(
                continuation: continuation,
                category: "CppBridge.TTS.ProtoStream"
            )
            let contextPtr = Unmanaged.passRetained(context).toOpaque()
            Task.detached {
                let rc = optionData.withUnsafeBytes { raw in
                    text.withCString { textPtr in
                        stream(
                            handle,
                            textPtr,
                            raw.bindMemory(to: UInt8.self).baseAddress,
                            raw.count,
                            { bytes, size, userData in
                                guard let userData else { return }
                                Unmanaged<ProtoStreamContext<RATTSOutput>>
                                    .fromOpaque(userData)
                                    .takeUnretainedValue()
                                    .yield(bytes: bytes, size: size)
                            },
                            contextPtr
                        )
                    }
                }
                Unmanaged<ProtoStreamContext<RATTSOutput>>
                    .fromOpaque(contextPtr)
                    .release()
                if rc != RAC_SUCCESS {
                    var output = RATTSOutput()
                    output.timestampMs = Int64(Date().timeIntervalSince1970 * 1000)
                    continuation.yield(output)
                }
                continuation.finish()
            }
        }
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
            throw SDKException.vad(.invalidConfiguration, "VAD configure proto failed: \(rc)")
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
            throw SDKException.vad(.processingFailed, "VAD activity callback failed: \(rc)")
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
            throw SDKException.vlm(.cancelled, "VLM cancel proto failed: \(rc)")
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
            throw SDKException.rag(.notInitialized, "RAG proto session create failed: \(rc)")
        }
        setProtoSession(newSession)
    }

    public func ingest(_ document: RARAGDocument) throws -> RARAGStatistics {
        let session = try requireProtoSession()
        return try invokeRAGRequest(
            session: session,
            request: document,
            symbol: RAGGeneratedProtoABI.ingest,
            symbolName: RAGGeneratedProtoABI.ingestName,
            responseType: RARAGStatistics.self
        )
    }

    public func query(_ options: RARAGQueryOptions) throws -> RARAGResult {
        let session = try requireProtoSession()
        return try invokeRAGRequest(
            session: session,
            request: options,
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

    private func invokeRAGRequest<Request: Message, Response: Message>(
        session: rac_handle_t,
        request: Request,
        symbol: RAGGeneratedProtoABI.Request?,
        symbolName: String,
        responseType: Response.Type
    ) throws -> Response {
        let symbol = try NativeProtoABI.require(symbol, named: symbolName)
        return try decodeBuffer(responseType: responseType, symbolName: symbolName) { outBuffer in
            try NativeProtoABI.withSerializedBytes(request) { bytes, size in
                symbol(session, bytes, size, outBuffer)
            }
        }
    }
}

// MARK: - LoRA

extension CppBridge.LLM {
    public func loadLoraAdapter(_ config: RALoRAAdapterConfig) throws -> RALoRAAdapterInfo {
        let handle = try getHandle()
        return try invokeLoRARequest(
            handle: handle,
            request: config,
            symbol: LoRAGeneratedProtoABI.load,
            symbolName: LoRAGeneratedProtoABI.loadName,
            responseType: RALoRAAdapterInfo.self
        )
    }

    public func removeLoraAdapter(_ config: RALoRAAdapterConfig) throws -> RALoRAAdapterInfo {
        let handle = try getHandle()
        return try invokeLoRARequest(
            handle: handle,
            request: config,
            symbol: LoRAGeneratedProtoABI.remove,
            symbolName: LoRAGeneratedProtoABI.removeName,
            responseType: RALoRAAdapterInfo.self
        )
    }

    public func clearLoraAdaptersProto() throws -> RALoRAAdapterInfo {
        let handle = try getHandle()
        let clear = try NativeProtoABI.require(
            LoRAGeneratedProtoABI.clear,
            named: LoRAGeneratedProtoABI.clearName
        )
        return try decodeBuffer(
            responseType: RALoRAAdapterInfo.self,
            symbolName: LoRAGeneratedProtoABI.clearName
        ) { outBuffer in
            clear(handle, outBuffer)
        }
    }

    public func checkLoraCompatibility(_ config: RALoRAAdapterConfig) throws -> RALoraCompatibilityResult {
        let handle = try getHandle()
        return try invokeLoRARequest(
            handle: handle,
            request: config,
            symbol: LoRAGeneratedProtoABI.compatibility,
            symbolName: LoRAGeneratedProtoABI.compatibilityName,
            responseType: RALoraCompatibilityResult.self
        )
    }

    private func invokeLoRARequest<Request: Message, Response: Message>(
        handle: rac_handle_t,
        request: Request,
        symbol: LoRAGeneratedProtoABI.LLMRequest?,
        symbolName: String,
        responseType: Response.Type
    ) throws -> Response {
        let symbol = try NativeProtoABI.require(symbol, named: symbolName)
        return try decodeBuffer(responseType: responseType, symbolName: symbolName) { outBuffer in
            try NativeProtoABI.withSerializedBytes(request) { bytes, size in
                symbol(handle, bytes, size, outBuffer)
            }
        }
    }
}

extension CppBridge.LoraRegistry {
    public func register(_ entry: RALoraAdapterCatalogEntry) throws -> RALoraAdapterCatalogEntry {
        guard let handle = getHandleForProtoRegistration() else {
            throw SDKException.general(.initializationFailed, "LoRA registry not initialized")
        }
        let register = try NativeProtoABI.require(
            LoRAGeneratedProtoABI.register,
            named: LoRAGeneratedProtoABI.registerName
        )
        return try decodeBuffer(
            responseType: RALoraAdapterCatalogEntry.self,
            symbolName: LoRAGeneratedProtoABI.registerName
        ) { outBuffer in
            try NativeProtoABI.withSerializedBytes(entry) { bytes, size in
                register(handle, bytes, size, outBuffer)
            }
        }
    }

    private func getHandleForProtoRegistration() -> rac_lora_registry_handle_t? {
        rac_get_lora_registry()
    }
}

// MARK: - Diffusion

extension CppBridge.Diffusion {
    public func generate(options: RADiffusionGenerationOptions) throws -> RADiffusionResult {
        let handle = try getHandle()
        let generate = try NativeProtoABI.require(
            DiffusionGeneratedProtoABI.generate,
            named: DiffusionGeneratedProtoABI.generateName
        )
        return try decodeBuffer(
            responseType: RADiffusionResult.self,
            symbolName: DiffusionGeneratedProtoABI.generateName
        ) { outBuffer in
            try NativeProtoABI.withSerializedBytes(options) { bytes, size in
                generate(handle, bytes, size, outBuffer)
            }
        }
    }

    public func generateWithProgress(
        options: RADiffusionGenerationOptions,
        onProgress: @escaping (RADiffusionProgress) -> Bool
    ) throws -> RADiffusionResult {
        let handle = try getHandle()
        let progress = try NativeProtoABI.require(
            DiffusionGeneratedProtoABI.progress,
            named: DiffusionGeneratedProtoABI.progressName
        )
        let context = ProtoProgressContext<RADiffusionProgress>(
            category: "CppBridge.Diffusion.ProtoProgress",
            callback: onProgress
        )
        let contextPtr = Unmanaged.passRetained(context).toOpaque()
        defer {
            Unmanaged<ProtoProgressContext<RADiffusionProgress>>
                .fromOpaque(contextPtr)
                .release()
        }
        return try decodeBuffer(
            responseType: RADiffusionResult.self,
            symbolName: DiffusionGeneratedProtoABI.progressName
        ) { outBuffer in
            try NativeProtoABI.withSerializedBytes(options) { bytes, size in
                progress(
                    handle,
                    bytes,
                    size,
                    { progressBytes, progressSize, userData in
                        guard let userData else { return RAC_TRUE }
                        return Unmanaged<ProtoProgressContext<RADiffusionProgress>>
                            .fromOpaque(userData)
                            .takeUnretainedValue()
                            .emit(bytes: progressBytes, size: progressSize) ? RAC_TRUE : RAC_FALSE
                    },
                    contextPtr,
                    outBuffer
                )
            }
        }
    }

    public func cancelProto() throws {
        guard let handle = try? getHandle() else { return }
        let cancel = try NativeProtoABI.require(
            DiffusionGeneratedProtoABI.cancel,
            named: DiffusionGeneratedProtoABI.cancelName
        )
        let rc = cancel(handle)
        guard rc == RAC_SUCCESS else {
            throw SDKException.diffusion(.generationFailed, "Diffusion cancel proto failed: \(rc)")
        }
    }
}
