//
//  RALLMTypes+CppBridge.swift
//  RunAnywhere SDK
//
//  C-bridge extensions on proto-generated RA* LLM types.
//

import Foundation

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
        // Embed the full options envelope so typed controls such as
        // disableThinking, thinkingPattern, toolCalling, grammar, and
        // structured output reach commons as one canonical payload.
        request.options = self
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
