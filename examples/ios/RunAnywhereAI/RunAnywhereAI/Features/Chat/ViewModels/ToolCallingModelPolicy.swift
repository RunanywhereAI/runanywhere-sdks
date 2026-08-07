//
//  ToolCallingModelPolicy.swift
//  RunAnywhereAI
//
//  App-level tool-calling gate and execution budget. Mirrors the Android
//  example's ToolCallingModelPolicy / ToolCallingExecutionPolicy so both apps
//  route and constrain tool calling identically.
//

import Foundation
import RunAnywhere

/// The generation path selected after tool/model compatibility preflight.
enum ToolCallingRoute {
    case standardGeneration
    case toolGeneration
    case blocked
}

struct ToolCallingAvailability {
    let isAvailable: Bool
    let message: String?

    init(isAvailable: Bool, message: String? = nil) {
        self.isAvailable = isAvailable
        self.message = message
    }
}

struct ToolCallingPreflight {
    let route: ToolCallingRoute
    let availability: ToolCallingAvailability
}

/// App-level production gate for tool calling.
///
/// Tool definitions, format instructions, the user prompt, and follow-up tool
/// results all share the model context window, so a too-small window fails
/// before decoding. A published 1K window is the minimum supported tool
/// configuration; the execution budget below bounds output and loop length so
/// compatible small models stay responsive.
enum ToolCallingModelPolicy {
    static let minimumContextTokens = 1024

    static func evaluate(model: RAModelInfo?) -> ToolCallingAvailability {
        guard let model else {
            return ToolCallingAvailability(
                isAvailable: false,
                message: "Choose a chat model before enabling Web & tools."
            )
        }
        let modelName = firstNonBlank(model.name, model.id, fallback: "The current model")
        let contextLength = model.contextLength
        if contextLength <= 0 {
            return ToolCallingAvailability(
                isAvailable: false,
                message: "\(modelName) does not publish a context-window capability. "
                    + "Choose a model with at least 1,024 tokens for tools."
            )
        }
        if contextLength < Int32(minimumContextTokens) {
            return ToolCallingAvailability(
                isAvailable: false,
                message: "\(modelName) has a \(contextLength)-token context window. "
                    + "Tools require at least 1,024 tokens. Choose a larger-context model."
            )
        }
        return ToolCallingAvailability(isAvailable: true)
    }

    static func preflight(
        toolsRequested: Bool,
        registeredToolCount: Int,
        model: RAModelInfo?
    ) -> ToolCallingPreflight {
        if !toolsRequested || registeredToolCount <= 0 {
            return ToolCallingPreflight(
                route: .standardGeneration,
                availability: evaluate(model: model)
            )
        }
        let availability = evaluate(model: model)
        return ToolCallingPreflight(
            route: availability.isAvailable ? .toolGeneration : .blocked,
            availability: availability
        )
    }

    private static func firstNonBlank(_ values: String..., fallback: String) -> String {
        for value in values where !value.trimmingCharacters(in: .whitespaces).isEmpty {
            return value
        }
        return fallback
    }
}

/// Tool-only limits applied after the normal chat response-budget policy.
///
/// Mirrors the Android ToolCallingExecutionPolicy so both apps behave the same:
/// a concise final synthesis budget, a small tool-call ceiling, and greedy
/// (temperature=0) reproducible tool decisions with reasoning disabled.
enum ToolCallingExecutionPolicy {
    static let maxFinalResponseTokens = 96
    static let maxToolCalls = 2

    /// Tool-loop options mirroring the Android ToolCallingExecutionPolicy:
    /// auto-execute the registered tools (the v3 generate path leaves this false,
    /// so it only leaks a raw tool call), greedy + thinking-off for
    /// reproducible calls, and parallel tool calls so one turn can request
    /// several tools before a single follow-up reply.
    ///
    /// `temperature`/`maxTokens` were deleted outright from
    /// `ToolCallingOptions` (idl/tool_calling.proto: "Sampling temperature
    /// and per-turn output-token cap are NOT duplicated here: the enclosing
    /// LLMGenerationOptions.temperature / max_output_tokens are the one
    /// value for both") -- they now live on `generationOptions(from:)` below.
    static func toolOptions() -> RAToolCallingOptions {
        var options = RAToolCallingOptions()
        options.autoExecute = true
        options.maxToolCalls = Int32(maxToolCalls)
        options.keepToolsAvailable = false
        options.parallelToolCalls = true
        options.disableThinking = true
        return options
    }

    /// Greedy, reasoning-off generation options; final length is bounded by
    /// `maxFinalResponseTokens`, so the decision phase stays unconstrained.
    static func generationOptions(from options: LlmOptions) -> RALLMGenerationOptions {
        var generation = RALLMGenerationOptions()
        if let systemPrompt = options.systemPrompt, !systemPrompt.isEmpty {
            generation.systemPrompt = systemPrompt
        }
        generation.maxOutputTokens = Int32(maxFinalResponseTokens)
        generation.temperature = 0
        generation.topP = 1
        var reasoning = RAReasoningOptions()
        reasoning.mode = .off
        generation.reasoning = reasoning
        return generation
    }
}
