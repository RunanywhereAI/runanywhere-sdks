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
    static func defaults() -> RALLMGenerationOptions {
        RALLMGenerationOptions(
            maxTokens: 100,
            temperature: 0.8,
            topP: 1.0,
            topK: 0,
            repetitionPenalty: 1.0
        )
    }

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

    func toRALLMGenerateRequest(prompt: String) -> RALLMGenerateRequest {
        var request = RALLMGenerateRequest()
        request.prompt = prompt
        request.maxTokens = maxTokens
        request.temperature = temperature
        request.topP = topP
        request.topK = topK
        request.repetitionPenalty = repetitionPenalty
        request.stopSequences = stopSequences
        request.streamingEnabled = streamingEnabled
        request.preferredFramework = preferredFramework.wireString
        if hasSystemPrompt {
            request.systemPrompt = systemPrompt
        }
        if hasJsonSchema {
            request.jsonSchema = jsonSchema
        }
        if hasStructuredOutput {
            request.jsonSchema = structuredOutput.hasJsonSchema
                ? structuredOutput.jsonSchema
                : structuredOutput.schema.jsonSchemaString
            request.responseFormat = structuredOutput.mode == .jsonObject ? "json_object" : "json_schema"
            if !structuredOutput.grammar.isEmpty {
                request.grammar = structuredOutput.grammar
            }
        }
        if hasExecutionTarget {
            request.executionTarget = executionTarget.wireString
        }
        return request
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
        p.openTag = "<think>"
        p.closeTag = "</think>"
        return p
    }

    init(from cPattern: rac_thinking_tag_pattern_t) {
        var p = RAThinkingTagPattern()
        if let o = cPattern.opening_tag { p.openTag = String(cString: o) }
        if let c = cPattern.closing_tag { p.closeTag = String(cString: c) }
        self = p
    }
}

public extension RAExecutionTarget {
    var wireString: String {
        switch self {
        case .onDevice: return "on-device"
        case .cloud: return "cloud"
        case .auto: return "auto"
        default: return ""
        }
    }
}
