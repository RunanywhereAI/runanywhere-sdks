//
//  VLMNamespace.swift
//  RunAnywhere SDK
//
//  `RunAnywhere.vlm` — image + prompt generation. Same options and results as
//  `llm`; the prompt is a parameter, never a field inside options.
//

import Foundation

public extension RunAnywhere {

    /// Vision-language generation.
    static var vlm: VLM { VLM() }

    /// Describe, read, or reason about an image.
    struct VLM: Sendable {

        /// Answer `prompt` about `image`.
        ///
        /// ```swift
        /// let result = try await RunAnywhere.vlm.generate(image: .file(path), prompt: "What is this?")
        /// print(result.text)
        /// ```
        ///
        /// - Throws: `SDKException` when no VLM model can be loaded or generation fails.
        public func generate(
            image: ImageInput,
            prompt: String,
            options: LlmOptions? = nil
        ) async throws -> GenerationResult {
            let effective = options ?? LlmOptions()
            let model = try await RunAnywhere.ensureLoaded(
                modelId: effective.model,
                category: .multimodal,
                fallbackCategories: [.vision]
            )
            let result = try await CppBridge.VLM.shared.process(
                effective.toVLMRequest(prompt: prompt, images: [image.toVLMImage()])
            )
            try RunAnywhere.throwIfVLMFailed(result)
            return GenerationResult(proto: result, requestId: "", model: model)
        }

        /// Answer `prompt` about `image`, streaming tokens as they arrive.
        ///
        /// - Throws: `SDKException` from this call when the model cannot be
        ///   loaded, and into the returned stream when generation fails.
        public func generateStream(
            image: ImageInput,
            prompt: String,
            options: LlmOptions? = nil
        ) async throws -> AsyncThrowingStream<GenerationEvent, Error> {
            let effective = options ?? LlmOptions()
            let model = try await RunAnywhere.ensureLoaded(
                modelId: effective.model,
                category: .multimodal,
                fallbackCategories: [.vision]
            )
            let events = try await CppBridge.VLM.shared.processStream(
                effective.toVLMRequest(prompt: prompt, images: [image.toVLMImage()])
            )

            return mapVLMStream(events, model: model)
        }

        private func mapVLMStream(
            _ events: AsyncStream<RAVLMStreamEvent>,
            model: String
        ) -> AsyncThrowingStream<GenerationEvent, Error> {
            let textItemId = UUID().uuidString
            return AsyncThrowingStream { continuation in
                let task = Task {
                    var sawStart = false
                    var accumulated = ""
                    var requestId = ""
                    var sawTerminal = false
                    var sequence: Int64 = 0
                    func nextSequence() -> Int64 {
                        sequence += 1
                        return sequence
                    }

                    for await event in events {
                        if Task.isCancelled { break }
                        if !event.requestID.isEmpty { requestId = event.requestID }
                        switch event.kind {
                        case .started:
                            sawStart = true
                            continuation.yield(.started(requestId: event.requestID))
                        case .token:
                            if !event.token.isEmpty {
                                accumulated += event.token
                                continuation.yield(.textDelta(
                                    requestId: requestId,
                                    sequence: nextSequence(),
                                    itemId: textItemId,
                                    index: 0,
                                    text: event.token
                                ))
                            }
                        case .completed:
                            let result = event.hasResult ? event.result : RAVLMResult()
                            continuation.yield(.completed(
                                requestId: requestId,
                                result: GenerationResult(proto: result, requestId: event.requestID, model: model)
                            ))
                            sawTerminal = true
                        case .error:
                            continuation.yield(.failed(
                                requestId: requestId,
                                partial: accumulated.isEmpty ? nil : accumulated,
                                error: SDKException(proto: event.error)
                            ))
                            sawTerminal = true
                        default:
                            break
                        }
                    }

                    // Same grammar as `llm.generateStream`: end in `completed`,
                    // `failed`, or `cancelled` — never a fabricated `completed`
                    // when the producer never reported one.
                    if !sawTerminal {
                        Self.emitVLMTerminalFallback(
                            continuation,
                            requestId: requestId,
                            partial: accumulated.isEmpty ? nil : accumulated,
                            sawStart: sawStart,
                            isCancelled: Task.isCancelled
                        )
                    }
                    continuation.finish()
                }
                continuation.onTermination = { @Sendable termination in
                    task.cancel()
                    if case .cancelled = termination {
                        Task { await CppBridge.VLM.shared.cancel() }
                    }
                }
            }
        }

        private static func emitVLMTerminalFallback(
            _ continuation: AsyncThrowingStream<GenerationEvent, Error>.Continuation,
            requestId: String,
            partial: String?,
            sawStart: Bool,
            isCancelled: Bool
        ) {
            if isCancelled {
                continuation.yield(.cancelled(requestId: requestId, partial: partial))
            } else if sawStart {
                continuation.yield(.failed(
                    requestId: requestId,
                    partial: partial,
                    error: SDKException(
                        code: .generationFailed,
                        message: "VLM generation stream ended before a terminal event",
                        category: .component
                    )
                ))
            } else {
                continuation.yield(.failed(
                    requestId: requestId,
                    partial: nil,
                    error: SDKException(
                        code: .generationFailed,
                        message: "VLM generation ended before producing any output",
                        category: .component
                    )
                ))
            }
        }
    }
}

// MARK: - Internal proto-level helpers

extension RunAnywhere {

    internal static func throwIfVLMFailed(_ result: RAVLMResult) throws {
        guard result.hasError else { return }
        throw SDKException(proto: result.error)
    }

    internal static func requireVLMModel() throws {
        guard isReady else {
            throw SDKException(code: .notInitialized, message: "SDK not initialized", category: .internal)
        }
        guard firstLoadedModelSnapshot(categories: [.multimodal, .vision]) != nil else {
            throw SDKException(code: .modelNotLoaded, message: "VLM model not loaded", category: .component)
        }
    }
}
