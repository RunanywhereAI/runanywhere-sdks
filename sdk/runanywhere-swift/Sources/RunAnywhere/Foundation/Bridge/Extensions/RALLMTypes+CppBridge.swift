//
//  RALLMTypes+CppBridge.swift
//  RunAnywhere SDK
//
//  C-bridge extensions on proto-generated RA* LLM types.
//

import CRACommons
import Foundation

// MARK: - RALLMConfiguration: ComponentConfiguration

extension RALLMConfiguration: ComponentConfiguration {
    public var modelId: String? { nil }
    public func validate() throws { }
}

// MARK: - RALLMGenerationOptions: C-bridge + convenience

public extension RALLMGenerationOptions {
    init(
        maxTokens: Int = 512,
        temperature: Float = 0.7,
        topP: Float = 0.95,
        topK: Int = 40,
        repetitionPenalty: Float = 1.0,
        stopSequences: [String] = [],
        streamingEnabled: Bool = false,
        preferredFramework: RAInferenceFramework = .unspecified,
        systemPrompt: String? = nil,
        structuredOutput: RAStructuredOutputOptions? = nil
    ) {
        var o = RALLMGenerationOptions()
        o.maxTokens = Int32(maxTokens)
        o.temperature = temperature
        o.topP = topP
        o.topK = Int32(topK)
        o.repetitionPenalty = repetitionPenalty
        o.stopSequences = stopSequences
        o.streamingEnabled = streamingEnabled
        o.preferredFramework = preferredFramework
        if let p = systemPrompt { o.systemPrompt = p }
        if let so = structuredOutput { o.structuredOutput = so }
        self = o
    }

    func withCOptions<T>(_ body: (UnsafePointer<rac_llm_options_t>) throws -> T) rethrows -> T {
        var cOptions = rac_llm_options_t()
        cOptions.max_tokens = maxTokens
        cOptions.temperature = temperature
        cOptions.top_p = topP
        cOptions.streaming_enabled = streamingEnabled ? RAC_TRUE : RAC_FALSE
        cOptions.stop_sequences = nil
        cOptions.num_stop_sequences = 0
        if hasSystemPrompt {
            return try systemPrompt.withCString { ptr in
                cOptions.system_prompt = ptr
                return try body(&cOptions)
            }
        } else {
            cOptions.system_prompt = nil
            return try body(&cOptions)
        }
    }
}

// MARK: - RALLMGenerationResult: C-bridge

public extension RALLMGenerationResult {
    var tokensUsed: Int { Int(tokensGenerated) }
    var latencyMs: TimeInterval { generationTimeMs }
    var timeToFirstTokenMs: Double? { hasTtftMs ? ttftMs : nil }

    init(from cResult: rac_llm_result_t, modelId: String) {
        var r = RALLMGenerationResult()
        r.text = cResult.text.map { String(cString: $0) } ?? ""
        r.inputTokens = cResult.prompt_tokens
        r.tokensGenerated = cResult.completion_tokens
        r.modelUsed = modelId
        r.generationTimeMs = Double(cResult.total_time_ms)
        r.tokensPerSecond = Double(cResult.tokens_per_second)
        if cResult.time_to_first_token_ms > 0 {
            r.ttftMs = Double(cResult.time_to_first_token_ms)
        }
        self = r
    }

    init(from cStreamResult: rac_llm_stream_result_t, modelId: String) {
        let m = cStreamResult.metrics
        var r = RALLMGenerationResult()
        r.text = cStreamResult.text.map { String(cString: $0) } ?? ""
        if let tc = cStreamResult.thinking_content { r.thinkingContent = String(cString: tc) }
        r.inputTokens = m.prompt_tokens
        r.tokensGenerated = m.tokens_generated
        r.modelUsed = modelId
        r.generationTimeMs = Double(m.total_time_ms)
        r.tokensPerSecond = Double(m.tokens_per_second)
        if m.time_to_first_token_ms > 0 { r.ttftMs = Double(m.time_to_first_token_ms) }
        r.thinkingTokens = m.thinking_tokens
        r.responseTokens = m.response_tokens
        self = r
    }
}

// MARK: - RAThinkingTagPattern: C-bridge

public extension RAThinkingTagPattern {
    static var defaultPattern: RAThinkingTagPattern {
        var p = RAThinkingTagPattern()
        p.openingTag = "<think>"
        p.closingTag = "</think>"
        return p
    }

    init(from cPattern: rac_thinking_tag_pattern_t) {
        var p = RAThinkingTagPattern()
        if let o = cPattern.opening_tag { p.openingTag = String(cString: o) }
        if let c = cPattern.closing_tag { p.closingTag = String(cString: c) }
        self = p
    }
}

// MARK: - RALoraAdapterCatalogEntry: C-bridge

public extension RALoraAdapterCatalogEntry {
    init(from cEntry: rac_lora_entry_t) {
        var e = RALoraAdapterCatalogEntry()
        if let id = cEntry.id { e.id = String(cString: id) }
        if let n = cEntry.name { e.name = String(cString: n) }
        if let u = cEntry.download_url { e.url = String(cString: u) }
        if let f = cEntry.filename { e.filename = String(cString: f) }
        if cEntry.compatible_model_count > 0, let ids = cEntry.compatible_model_ids {
            e.compatibleModels = (0..<cEntry.compatible_model_count).compactMap { i in
                ids[i].map { String(cString: $0) }
            }
        }
        self = e
    }
}
