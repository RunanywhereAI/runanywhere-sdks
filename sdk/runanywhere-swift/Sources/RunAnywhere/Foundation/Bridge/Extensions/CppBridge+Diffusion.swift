//
//  CppBridge+Diffusion.swift
//  RunAnywhere SDK
//
//  Diffusion (image generation) bridge over the handle-free lifecycle proto
//  ABI. The Apple CoreML Stable-Diffusion engine serves the DIFFUSION
//  primitive; the model is loaded through the canonical lifecycle
//  (`RunAnywhere.loadModel` with `category = .imageGeneration`), so inference
//  is handle-free — `rac_diffusion_generate_lifecycle_proto` resolves the
//  loaded model internally via commons' `acquire_lifecycle_diffusion`, exactly
//  like the VLM / embeddings lifecycle paths.
//
//  Streaming note: commons' native diffusion stream kickoff
//  (`rac_diffusion_stream_start_proto`) is a documented `RAC_ERROR_NOT_IMPLEMENTED`
//  stub — the engine does not yet dispatch per-step `DiffusionStreamEvent`s, and
//  the C header itself directs SDKs to fall back to the lifecycle/progress
//  entry points until that kickoff lands. `generateStream` therefore adapts the
//  real, working lifecycle generate into an `AsyncStream`: it emits `.started`,
//  runs the CoreML pipeline, then emits a terminal `.completed` (carrying the
//  full `RADiffusionResult`) or `.error`. The generated image is genuine — only
//  intermediate progress is unavailable until commons wires the stream kickoff.
//  When it does, this bridge upgrades to the native path with no public API
//  change.
//

import CRACommons
import Foundation

// C symbol table (dlsym'd at runtime, like every other modality proto binding;
// the symbol is exported by RACommons via exports/RACommons.exports).
private enum DiffusionLifecycleProtoABI {
    typealias GenerateLifecycle = NativeProtoABI.ProtoRequest

    static let generateLifecycleName = "rac_diffusion_generate_lifecycle_proto"

    static let generateLifecycle = NativeProtoABI.load(
        generateLifecycleName,
        as: GenerateLifecycle.self
    )
}

// MARK: - Diffusion Component Bridge

extension CppBridge {

    /// Diffusion (image generation) component manager.
    ///
    /// Provides thread-safe access to the C++ diffusion lifecycle. No component
    /// handle is threaded: commons resolves the lifecycle-loaded diffusion
    /// model internally, mirroring the VLM lifecycle cancel / embeddings
    /// lifecycle embed paths.
    public actor Diffusion {

        /// Shared diffusion component instance.
        public static let shared = Diffusion()

        private let logger = SDKLogger(category: "CppBridge.Diffusion")

        /// The most-recent in-flight streaming task, cancelled by `cancel()`
        /// or by the `AsyncStream` consumer terminating the stream.
        private var activeStreamTask: Task<Void, Never>?

        private init() {}

        // MARK: - Generate

        /// Generate an image from the lifecycle-loaded diffusion model.
        ///
        /// Backed by `rac_diffusion_generate_lifecycle_proto`: serialize a
        /// `RADiffusionGenerationRequest { options }`, decode the returned
        /// `RADiffusionResult`. The blocking native call runs on a detached
        /// task so the shared actor stays responsive for the duration of the
        /// (multi-second) CoreML pipeline.
        public func generate(_ options: RADiffusionGenerationOptions) async throws -> RADiffusionResult {
            var request = RADiffusionGenerationRequest()
            request.options = options
            return try await Task.detached {
                try NativeProtoABI.invoke(
                    request,
                    symbol: DiffusionLifecycleProtoABI.generateLifecycle,
                    symbolName: DiffusionLifecycleProtoABI.generateLifecycleName,
                    responseType: RADiffusionResult.self
                )
            }.value
        }

        // MARK: - Stream

        /// Stream typed `RADiffusionStreamEvent`s for an image generation.
        ///
        /// Yields `.started` → terminal `.completed` (with the `RADiffusionResult`)
        /// or `.error`. See the file header for why this adapts the lifecycle
        /// generate rather than the native `rac_diffusion_stream_start_proto`
        /// stub. The detached task is tracked so `cancel()` (or dropping the
        /// stream) tears it down.
        public func generateStream(
            _ options: RADiffusionGenerationOptions
        ) -> AsyncStream<RADiffusionStreamEvent> {
            let (stream, continuation) = AsyncStream.makeStream(of: RADiffusionStreamEvent.self)

            let task = Task.detached { [logger] in
                var startedEvent = RADiffusionStreamEvent()
                startedEvent.kind = .started
                continuation.yield(startedEvent)

                do {
                    var request = RADiffusionGenerationRequest()
                    request.options = options
                    let result = try NativeProtoABI.invoke(
                        request,
                        symbol: DiffusionLifecycleProtoABI.generateLifecycle,
                        symbolName: DiffusionLifecycleProtoABI.generateLifecycleName,
                        responseType: RADiffusionResult.self
                    )
                    // Honour a consumer/task cancellation that arrived while the
                    // native pipeline was running: skip the terminal event.
                    if Task.isCancelled {
                        continuation.finish()
                        return
                    }
                    var completedEvent = RADiffusionStreamEvent()
                    completedEvent.kind = .completed
                    completedEvent.result = result
                    continuation.yield(completedEvent)
                } catch is CancellationError {
                    // Consumer cancelled — finish quietly, no terminal event.
                } catch let error as SDKException {
                    if !Task.isCancelled {
                        var errorEvent = RADiffusionStreamEvent()
                        errorEvent.kind = .error
                        errorEvent.errorMessage = error.message
                        continuation.yield(errorEvent)
                    }
                } catch {
                    if !Task.isCancelled {
                        logger.warning("Diffusion stream failed: \(error.localizedDescription)")
                        var errorEvent = RADiffusionStreamEvent()
                        errorEvent.kind = .error
                        errorEvent.errorMessage = error.localizedDescription
                        continuation.yield(errorEvent)
                    }
                }
                continuation.finish()
            }

            activeStreamTask = task
            continuation.onTermination = { @Sendable _ in task.cancel() }
            return stream
        }

        // MARK: - Cancel

        /// Cancel the in-flight streaming generation.
        ///
        /// Cancels the tracked stream task. There is no lifecycle-level native
        /// diffusion cancel: `rac_diffusion_cancel_proto` is handle-based and
        /// this facade holds no handle, and `rac_diffusion_stream_cancel_proto`
        /// targets a native session that the (stubbed) stream kickoff never
        /// mints. The single CoreML `generate` call cannot be interrupted
        /// mid-flight, so cancellation takes effect at the next checkpoint
        /// (before the terminal event is emitted).
        public func cancel() {
            activeStreamTask?.cancel()
            activeStreamTask = nil
        }
    }
}
