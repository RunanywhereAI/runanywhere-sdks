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
                image: image.toVLMImage(),
                options: effective.toVLMProto(prompt: prompt)
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
                image: image.toVLMImage(),
                options: effective.toVLMProto(prompt: prompt)
            )

            return AsyncThrowingStream { continuation in
                let task = Task {
                    var accumulated = ""
                    var tokenCount = 0
                    let startedAt = Date()
                    var firstTokenAt: Date?
                    var requestId = ""
                    var sawCompletion = false

                    for await event in events {
                        if Task.isCancelled { break }
                        if !event.requestID.isEmpty { requestId = event.requestID }
                        switch event.kind {
                        case .started:
                            continuation.yield(.started(requestId: event.requestID))
                        case .token:
                            if !event.token.isEmpty {
                                if firstTokenAt == nil { firstTokenAt = Date() }
                                tokenCount += 1
                                accumulated += event.token
                                continuation.yield(.token(text: event.token, kind: .text))
                            }
                        case .completed:
                            let result = event.hasResult ? event.result : RAVLMResult()
                            continuation.yield(.completed(
                                GenerationResult(proto: result, requestId: event.requestID, model: model)
                            ))
                            sawCompletion = true
                        case .error:
                            continuation.finish(throwing: SDKException(proto: event.error))
                            return
                        default:
                            break
                        }
                    }

                    // Same grammar as `llm.generateStream`: end in `completed`
                    // or throw, never a silent finish.
                    if !sawCompletion, !Task.isCancelled {
                        guard tokenCount > 0 else {
                            continuation.finish(throwing: SDKException(
                                code: .generationFailed,
                                message: "VLM generation ended before producing any output",
                                category: .component
                            ))
                            return
                        }
                        continuation.yield(.completed(RunAnywhere.synthesizeResult(
                            text: accumulated,
                            thinking: "",
                            tokenCount: tokenCount,
                            startedAt: startedAt,
                            firstTokenAt: firstTokenAt,
                            finishReason: "",
                            requestId: requestId,
                            model: model
                        )))
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
