//
//  CppBridge+ModalityProtoABI.swift
//  RunAnywhere SDK
//
//  Hand-written companion to `Generated/ModalityProtoABI+Generated.swift`.
//
//  Phase C (aggressive): in addition to the original Phase B migration,
//  11 former `kind: custom` methods have been migrated onto the new
//  getWithContext / voidCall / createHandle / invokeOutOnly templates.
//  This file now retains only the remaining genuinely-irregular custom
//  methods (dual-proto inputs, callback collection patterns, raw-audio
//  pointers, long-lived callback registration) plus the shared C
//  trampoline / AsyncStream scaffolding referenced by both files.
//

import CRACommons
import Foundation
import os
import SwiftProtobuf

// MARK: - C symbol tables (custom methods only)
//
// Tables below own ONLY the dlsym entries for the still-custom methods. The
// codegen-eligible C symbols (incl. all Phase C migrations) live in the
// generated file's tables.

private enum VADComponentProtoABI {
    typealias Process = @convention(c) (
        rac_handle_t?,
        UnsafePointer<Float>?,
        Int,
        UnsafePointer<UInt8>?,
        Int,
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

    static let processName = "rac_vad_component_process_proto"
    static let setActivityCallbackName = "rac_vad_component_set_activity_proto_callback"

    static let process = NativeProtoABI.load(processName, as: Process.self)
    static let setActivityCallback = NativeProtoABI.load(
        setActivityCallbackName,
        as: SetActivityCallback.self
    )
}

private enum VoiceAgentStateProtoABI {
    typealias ProcessTurn = @convention(c) (
        rac_voice_agent_handle_t?,
        UnsafeRawPointer?,
        Int,
        UnsafeMutablePointer<rac_proto_buffer_t>?
    ) -> rac_result_t

    static let processTurnName = "rac_voice_agent_process_voice_turn_proto"

    static let processTurn = NativeProtoABI.load(processTurnName, as: ProcessTurn.self)
}

private enum VLMCustomProtoABI {
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
    // Handle-scoped cancel used by `processStream`'s onTermination so
    // that consumer cancellation tears down the in-flight native
    // generation instead of letting it run to completion.
    static let cancel = NativeProtoABI.load(cancelName, as: Cancel.self)
}

private enum RAGSessionProtoABI {
    typealias Destroy = @convention(c) (rac_handle_t?) -> Void

    static let destroyName = "rac_rag_session_destroy_proto"

    static let destroy = NativeProtoABI.load(destroyName, as: Destroy.self)
}

// MARK: - Callback contexts

/// Non-generic protocol that exposes the byte-yield entry point. The C
/// trampoline can only see non-generic types (Swift forbids generic captures
/// in `@convention(c)` closures), so we bridge through this protocol and let
/// dynamic dispatch reach the generic body in `ProtoStreamContext.yield`.
/// Class-only so the trampoline can recover the instance via `Unmanaged`.
protocol ProtoStreamYielder: AnyObject {  // swiftlint:disable:this avoid_any_object
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

    // Thread-safe cancellation flag flipped by the AsyncStream's
    // onTermination handler (consumer cancelled via `break`, task
    // cancellation, or dropping the stream). yield() and any C
    // callback that consults `isCancelled` must stop emitting events
    // and (where the C ABI allows) signal the native side to stop.
    // OSAllocatedUnfairLock matches the rest of the SDK's locking
    // policy (AGENTS.md forbids NSLock).
    private let cancellationState = OSAllocatedUnfairLock<Bool>(initialState: false)

    init(continuation: AsyncStream<Event>.Continuation, category: String) {
        self.continuation = continuation
        self.logger = SDKLogger(category: category)
    }

    /// True once the AsyncStream has been cancelled by its consumer.
    /// Safe to call from any thread (including the C callback).
    var isCancelled: Bool {
        cancellationState.withLock { $0 }
    }

    /// Mark the stream cancelled. Idempotent; safe from any thread.
    /// Subsequent `yield(bytes:size:)` calls become no-ops so the
    /// native callback cannot deliver more events once the consumer
    /// has broken out of the stream.
    func cancel() {
        cancellationState.withLock { $0 = true }
    }

    func yield(bytes: UnsafePointer<UInt8>?, size: Int) {
        guard let bytes, size > 0 else { return }
        if isCancelled { return }
        do {
            let event = try Event(serializedBytes: Data(bytes: bytes, count: size))
            continuation.yield(event)
        } catch {
            logger.warning("Failed to decode proto stream event: \(error.localizedDescription)")
        }
    }

    // Usages live in `Sources/RunAnywhere/Generated/`, which `.swiftlint.yml`
    // excludes from analysis; the analyzer therefore cannot see them.
    // swiftlint:disable unused_declaration
    /// Run a request-shaped streaming C call: serialises `request`, retains a
    /// fresh `ProtoStreamContext<Event>` as the userData pointer, invokes
    /// `body` with the shared `@convention(c)` trampoline, and balances the
    /// retain on completion. If the call returns non-`RAC_SUCCESS`, the
    /// optional `onError` closure may produce a terminal `Event` to yield
    /// before the stream finishes.
    ///
    /// Cancellation fires on BOTH paths: (1) `onTermination` on the
    /// returned `AsyncStream` (consumer breaks out of / drops the stream),
    /// and (2) a `withTaskCancellationHandler` around the detached body, so
    /// cancelling the consumer's owning task — which terminates the stream
    /// as `.finished` rather than `.cancelled` — still tears the native call
    /// down. Either path flips the context's `isCancelled` flag (so the
    /// shared trampoline stops decoding/yielding) and invokes the optional
    /// `onCancel` closure where a domain-specific C cancel symbol is
    /// available (e.g. `rac_llm_cancel_proto` /
    /// `rac_vlm_cancel_lifecycle_proto`). This satisfies the AsyncStream
    /// ownership contract: dropping the stream or cancelling its owner stops
    /// the native work instead of letting it run to completion in the
    /// detached task.
    ///
    /// - Parameters:
    ///   - request: Proto request to serialise into the bytes/size pair.
    ///   - category: Logger category for decode failures.
    ///   - onError: Optional terminal-event factory invoked when the C call
    ///     reports a non-success status. Returning `nil` finishes the stream
    ///     silently. The closure runs on the detached task. Not invoked when
    ///     the failure was triggered by cancellation.
    ///   - onCancel: Optional closure invoked when the consumer cancels the
    ///     AsyncStream. Typical implementations call a domain-specific
    ///     `rac_*_cancel_*` symbol so the native runtime stops producing
    ///     events. May be called from any thread.
    ///   - body: Closure that invokes the C streaming function pointer with
    ///     the serialised bytes, the trampoline, and the userData pointer.
    /// - Returns: An `AsyncStream<Event>` that yields decoded events as the C
    ///   callback fires and finishes when the C call returns.
    /// - Throws: Errors raised by `request.serializedData()`.
    static func runRequestStream<Request: Message>(
        request: Request,
        category: String,
        onError: (@Sendable (rac_result_t) -> Event?)? = nil,
        onCancel: (@Sendable () -> Void)? = nil,
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

            // Wire cancellation BEFORE Task.detached starts so the
            // handler is already installed if the consumer cancels
            // before the native call gets going. Only react to
            // `.cancelled` — `.finished` means the detached task has
            // already drained the native call and called finish(),
            // so re-invoking the native cancel symbol would either be
            // a no-op or report a spurious error.
            continuation.onTermination = { @Sendable termination in
                switch termination {
                case .cancelled:
                    context.cancel()
                    onCancel?()
                case .finished:
                    break
                @unknown default:
                    break
                }
            }

            // The task is detached so the native call neither blocks the
            // caller nor inherits its actor isolation, but a detached task
            // also drops structured-concurrency cancellation. Wrap the body
            // in `withTaskCancellationHandler` so a cancel on ANY enclosing
            // task — including the case where the consumer's owning task is
            // cancelled and the AsyncStream terminates as `.finished` rather
            // than `.cancelled` — still flips `isCancelled` and fires the
            // native cancel symbol instead of decoding to completion.
            Task.detached {
                let rc = await withTaskCancellationHandler {
                    requestData.withUnsafeBytes { rawBuffer in
                        body(
                            rawBuffer.bindMemory(to: UInt8.self).baseAddress,
                            rawBuffer.count,
                            protoStreamTrampoline,
                            contextPtr
                        )
                    }
                } onCancel: {
                    context.cancel()
                    onCancel?()
                }
                Unmanaged<ProtoStreamContext<Event>>
                    .fromOpaque(contextPtr)
                    .release()
                // Skip the synthesized terminal error event when the
                // consumer cancelled — the non-success return code is
                // the expected effect of `onCancel`, not a real error.
                if rc != RAC_SUCCESS, !context.isCancelled, let terminal = onError?(rc) {
                    continuation.yield(terminal)
                }
                continuation.finish()
            }
        }
    }
    // swiftlint:enable unused_declaration
}

internal final class ProtoProgressContext<Event: Message>: @unchecked Sendable {
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

// MARK: - VAD custom

extension CppBridge.VAD {
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

    public func setActivityCallbackProto(_ callback: @escaping (RASpeechActivityEvent) -> Void) async throws {
        let handle = try await getHandle()
        let setCallback = try NativeProtoABI.require(
            VADComponentProtoABI.setActivityCallback,
            named: VADComponentProtoABI.setActivityCallbackName
        )

        // Tear down the previous callback BEFORE installing a new one so the
        // C component drops its borrow on the old context pointer first; the
        // matching Unmanaged.release() then balances the +1 retain that
        // Unmanaged.passRetained gave it. Without this, every successful call
        // beyond the first leaks the prior ProtoProgressContext (and its
        // captured closure). See comment record `mlt-001`.
        let previousPtr = swapActivityCallbackContextPtr(nil)
        if let previousPtr {
            _ = setCallback(handle, nil, nil)
            Unmanaged<ProtoProgressContext<RASpeechActivityEvent>>
                .fromOpaque(previousPtr)
                .release()
        }

        let context = ProtoProgressContext<RASpeechActivityEvent>(
            category: "CppBridge.VAD.ProtoActivity"
        ) { event in
            callback(event)
            return true
        }
        let contextPtr = Unmanaged.passRetained(context).toOpaque()
        let rc = setCallback(
            handle,
            { bytes, size, userData in
                guard let userData else { return }
                _ = Unmanaged<ProtoProgressContext<RASpeechActivityEvent>>
                    .fromOpaque(userData)
                    .takeUnretainedValue()
                    .emit(bytes: bytes, size: size)
            },
            contextPtr
        )
        guard rc == RAC_SUCCESS else {
            Unmanaged<ProtoProgressContext<RASpeechActivityEvent>>
                .fromOpaque(contextPtr)
                .release()
            throw SDKException(code: .processingFailed, message: "VAD activity callback failed: \(rc)", category: .component)
        }
        // Registration succeeded — record the new pointer so subsequent
        // setActivityCallbackProto / destroy() calls can release it.
        _ = swapActivityCallbackContextPtr(contextPtr)
    }
}

// MARK: - Voice Agent custom

extension CppBridge.VoiceAgent {
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
            VLMCustomProtoABI.process,
            named: VLMCustomProtoABI.processName
        )
        let imageData = try image.serializedData()
        return try decodeBuffer(
            responseType: RAVLMResult.self,
            symbolName: VLMCustomProtoABI.processName
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
            VLMCustomProtoABI.stream,
            named: VLMCustomProtoABI.streamName
        )
        let imageData = try image.serializedData()
        let optionData = try options.serializedData()
        return AsyncStream { continuation in
            let context = ProtoStreamContext<RASDKEvent>(
                continuation: continuation,
                category: "CppBridge.VLM.ProtoStream"
            )
            let contextPtr = Unmanaged.passRetained(context).toOpaque()

            // Wire the AsyncStream cancellation BEFORE launching the
            // detached task. Consumer cancellation (`.cancelled`) now
            // (a) flips the context cancellation flag so the stream
            // callback returns RAC_FALSE and stops yielding, and (b)
            // invokes the native VLM cancel symbol so the underlying
            // generation tears down instead of running to completion
            // in the background. `.finished` means the detached task
            // already drained the native call, so the cancel symbol
            // is intentionally skipped on that path. The detached
            // task's `release()` still balances `passRetained`
            // regardless of which path completes first.
            continuation.onTermination = { @Sendable termination in
                switch termination {
                case .cancelled:
                    context.cancel()
                    if let cancel = VLMCustomProtoABI.cancel {
                        _ = cancel(handle)
                    }
                case .finished:
                    break
                @unknown default:
                    break
                }
            }

            // Detached for the same reason as `runRequestStream`; wrap the
            // native call in `withTaskCancellationHandler` so cancelling the
            // consumer's owning task (AsyncStream terminates `.finished`, not
            // `.cancelled`) still flips the context flag and fires the VLM
            // cancel symbol instead of decoding the whole response.
            Task.detached {
                var outBuffer = rac_proto_buffer_t()
                defer { NativeProtoABI.free(&outBuffer) }
                let rc = await withTaskCancellationHandler {
                    imageData.withUnsafeBytes { imageRaw in
                        optionData.withUnsafeBytes { optionRaw in
                            stream(
                                handle,
                                imageRaw.bindMemory(to: UInt8.self).baseAddress,
                                imageRaw.count,
                                optionRaw.bindMemory(to: UInt8.self).baseAddress,
                                optionRaw.count,
                                { bytes, size, userData in
                                    guard let userData else { return RAC_FALSE }
                                    let ctx = Unmanaged<ProtoStreamContext<RASDKEvent>>
                                        .fromOpaque(userData)
                                        .takeUnretainedValue()
                                    // Signal the C side to stop as soon as
                                    // the consumer cancels — skip the yield
                                    // entirely and return RAC_FALSE so the
                                    // native loop breaks on its next tick.
                                    if ctx.isCancelled { return RAC_FALSE }
                                    ctx.yield(bytes: bytes, size: size)
                                    return ctx.isCancelled ? RAC_FALSE : RAC_TRUE
                                },
                                contextPtr,
                                &outBuffer
                            )
                        }
                    }
                } onCancel: {
                    context.cancel()
                    if let cancel = VLMCustomProtoABI.cancel {
                        _ = cancel(handle)
                    }
                }
                Unmanaged<ProtoStreamContext<RASDKEvent>>
                    .fromOpaque(contextPtr)
                    .release()
                // A non-success return code on a cancelled stream is
                // expected (the native runtime bailed out); only log it
                // as an actual failure when the consumer is still attached.
                if rc != RAC_SUCCESS, !context.isCancelled {
                    SDKLogger(category: "CppBridge.VLM.ProtoStream")
                        .warning("VLM proto stream failed: \(rc)")
                }
                continuation.finish()
            }
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

// MARK: - Embeddings lifecycle proto ABI (parity with Flutter's
// `rac_embeddings_embed_batch_lifecycle_proto` path)
//
// Mirrors the lifecycle pattern used by VLM (`rac_vlm_cancel_lifecycle_proto`):
// no handle threading — commons resolves the active embeddings lifecycle
// component internally. Public callers reach this through
// `RunAnywhere.embeddings.embedBatch(_:)`.

private enum EmbeddingsLifecycleProtoABI {
    typealias EmbedBatchLifecycle = NativeProtoABI.ProtoRequest

    static let embedBatchLifecycleName = "rac_embeddings_embed_batch_lifecycle_proto"

    static let embedBatchLifecycle = NativeProtoABI.load(
        embedBatchLifecycleName,
        as: EmbedBatchLifecycle.self
    )
}

extension CppBridge.EmbeddingsProto {
    /// Generate embeddings using the lifecycle-loaded embeddings model.
    ///
    /// Backed by `rac_embeddings_embed_batch_lifecycle_proto`. The caller is
    /// expected to have already loaded an embeddings model into the commons
    /// lifecycle (e.g. via `RunAnywhere.loadModel(_:)` with
    /// `category = .embedding`).
    public static func embedBatchLifecycle(
        _ request: RAEmbeddingsRequest
    ) throws -> RAEmbeddingsResult {
        return try NativeProtoABI.invoke(
            request,
            symbol: EmbeddingsLifecycleProtoABI.embedBatchLifecycle,
            symbolName: EmbeddingsLifecycleProtoABI.embedBatchLifecycleName,
            responseType: RAEmbeddingsResult.self
        )
    }
}
