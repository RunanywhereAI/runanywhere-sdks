//
//  RALLMTypes+CppBridge.swift
//  RunAnywhere SDK
//
//  C-bridge extensions on proto-generated RA* LLM types.
//

import Foundation

// MARK: - RALLMGenerationOptions: C-bridge + convenience

public extension RALLMGenerationOptions {
    // `defaults()` is generated into RAConvenience.swift from the rac_default
    // annotations in idl/llm_options.proto. The hand-written copy that used to
    // live here disagreed with the initializer below it — 100/0.8/1.0/0 versus
    // 512/0.7/0.95/40 — so which values a caller got depended on which entry
    // point they happened to use.

    init(
        maxTokens: Int = Int(RALLMGenerationOptions.defaults().maxTokens),
        temperature: Float = RALLMGenerationOptions.defaults().temperature,
        topP: Float = RALLMGenerationOptions.defaults().topP,
        topK: Int = Int(RALLMGenerationOptions.defaults().topK),
        repetitionPenalty: Float = RALLMGenerationOptions.defaults().repetitionPenalty,
        stopSequences: [String] = [],
        streamingEnabled: Bool = false,
        preferredFramework: RAInferenceFramework = .unspecified,
        systemPrompt: String? = nil,
        structuredOutput: RAStructuredOutputOptions? = nil
    ) {
        var options = RALLMGenerationOptions()
        options.maxTokens = Int32(maxTokens)
        options.temperature = temperature
        options.topP = topP
        options.topK = Int32(topK)
        options.repetitionPenalty = repetitionPenalty
        options.stopSequences = stopSequences
        options.streamingEnabled = streamingEnabled
        options.preferredFramework = preferredFramework
        if let prompt = systemPrompt { options.systemPrompt = prompt }
        if let so = structuredOutput { options.structuredOutput = so }
        self = options
    }

    func toRALLMGenerateRequest(prompt: String) -> RALLMGenerateRequest {
        var request = RALLMGenerateRequest()
        request.prompt = prompt
        // Commons already classifies streamed output into ANSWER / THOUGHT
        // token kinds and resolves a model's thinking tags from the registry,
        // so a request-local thinking pattern is NOT required. Surface thought
        // events whenever thinking is enabled (i.e. not explicitly disabled) so
        // default catalog models still stream reasoning.
        request.emitThoughts = !disableThinking
        // LLM generation controls have one canonical wire location.
        request.options = self
        return request
    }
}

// MARK: - RALLMGenerationResult: proto-convenience accessors
//
// The `init(from cResult:)` / `init(from cStreamResult:)` constructors that
// used to live here were orphaned after Phase 6h moved LLM generation to the
// proto-byte ABI (`rac_llm_generate_proto`). Results now arrive as proto bytes
// and decode directly into `RALLMGenerationResult`; no C-struct marshaling
// path remains. Deleted per swift.md SWIFT-DUP-RACTYPES-CPPBRIDGE-DEAD.

public extension RALLMGenerationResult {
    var tokensUsed: Int { Int(tokensGenerated) }
    var latencyMs: TimeInterval { generationTimeMs }
    var timeToFirstTokenMs: Double? { hasTtftMs ? ttftMs : nil }
}

// MARK: - RAThinkingTagPattern: defaults

public extension RAThinkingTagPattern {
    static var defaultPattern: RAThinkingTagPattern {
        var proto = RAThinkingTagPattern()
        proto.openTag = "<think>"
        proto.closeTag = "</think>"
        return proto
    }
}
