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
        maxOutputTokens: Int = Int(RALLMGenerationOptions.defaults().maxOutputTokens),
        temperature: Float = RALLMGenerationOptions.defaults().temperature,
        topP: Float = RALLMGenerationOptions.defaults().topP,
        topK: Int = Int(RALLMGenerationOptions.defaults().topK),
        // idl/llm_options.proto renamed repetition_penalty -> repeat_penalty
        // (industry name: llama.cpp / Ollama both spell it repeat_penalty).
        repeatPenalty: Float = RALLMGenerationOptions.defaults().repeatPenalty,
        stopSequences: [String] = [],
        preferredFramework: RAInferenceFramework = .unspecified,
        systemPrompt: String? = nil,
        reasoning: RAReasoningOptions? = nil,
        structuredOutput: RAStructuredOutputOptions? = nil
    ) {
        var options = RALLMGenerationOptions()
        options.maxOutputTokens = Int32(maxOutputTokens)
        options.temperature = temperature
        options.topP = topP
        options.topK = Int32(topK)
        options.repeatPenalty = repeatPenalty
        options.stopSequences = stopSequences
        options.preferredFramework = preferredFramework
        if let prompt = systemPrompt { options.systemPrompt = prompt }
        if let reasoning { options.reasoning = reasoning }
        if let so = structuredOutput { options.structuredOutput = so }
        self = options
    }

    // RALLMGenerateRequest.prompt was deleted outright (idl/llm_service.proto):
    // the single request envelope now carries `messages`
    // ([RAChatMessage], oldest first, ending with the turn the model must
    // answer) instead of a bare prompt string + separate history array.
    func toRALLMGenerateRequest(prompt: String) -> RALLMGenerateRequest {
        var request = RALLMGenerateRequest()
        var userTurn = RAChatMessage()
        userTurn.role = .user
        userTurn.content = prompt
        request.messages = [userTurn]
        // LLM generation controls have one canonical wire location; thought
        // emission is governed by options.reasoning.includeInOutput.
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
    var tokensUsed: Int { Int(usage.outputTokens) }
    var latencyMs: TimeInterval { generationTimeMs }
    // ttftMs moved onto the shared RATokenUsage (token_usage.proto) and lost
    // its explicit-presence tracking there (plain Int64, 0 = not reported).
    var timeToFirstTokenMs: Double? { usage.ttftMs > 0 ? Double(usage.ttftMs) : nil }
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
