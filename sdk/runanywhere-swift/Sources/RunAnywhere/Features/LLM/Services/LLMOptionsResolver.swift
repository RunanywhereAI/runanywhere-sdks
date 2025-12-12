//
//  LLMOptionsResolver.swift
//  RunAnywhere SDK
//
//  Simple resolver that applies remote configuration constraints to runtime options
//

import Foundation

/// Simple resolver that applies remote configuration constraints to runtime options
///
/// Priority Order (highest to lowest):
/// 1. **Runtime Options** - User-provided values take precedence
/// 2. **Remote Configuration** - Organization defaults from console
/// 3. **SDK Defaults** - Fallback values when nothing else is specified
///
/// This ensures users have control while respecting organizational constraints.
public struct LLMOptionsResolver {

    private let logger = SDKLogger(category: "LLMOptionsResolver")
    private let structuredOutputHandler = StructuredOutputHandler()

    public init() {}

    /// Apply remote configuration constraints to runtime options
    ///
    /// Resolution Rules:
    /// - If user provides a value, it's used (unless it exceeds hard limits)
    /// - If user doesn't provide a value, remote default is used
    /// - If neither exist, SDK defaults are used
    /// - Hard limits (like token budgets) are always enforced
    ///
    /// - Parameters:
    ///   - options: User-provided options (or nil for defaults)
    ///   - remoteConfig: Remote generation configuration
    /// - Returns: Options with remote constraints applied
    public func resolve(
        options: LLMGenerationOptions?,
        remoteConfig: LLMGenerationConfig?
    ) -> LLMGenerationOptions {

        // Start with user options or create defaults
        let baseOptions = options ?? LLMGenerationOptions()

        // If no remote config, return as-is
        guard let remote = remoteConfig else {
            return baseOptions
        }

        // Apply remote constraints and defaults
        var maxTokens = baseOptions.maxTokens
        var temperature = baseOptions.temperature
        var topP = baseOptions.topP

        // If user didn't specify, use remote defaults
        if options == nil {
            maxTokens = remote.defaults.maxTokens
            temperature = Float(remote.defaults.temperature)
            topP = Float(remote.defaults.topP)
        }

        // Apply token budget constraints (these are hard limits)
        if let tokenBudget = remote.tokenBudget {
            if let maxAllowed = tokenBudget.maxTokensPerRequest {
                maxTokens = min(maxTokens, maxAllowed)
                if maxTokens != baseOptions.maxTokens {
                    logger.debug("Applied token limit: \(maxTokens) (was \(baseOptions.maxTokens))")
                }
            }
        }

        // Apply context length constraint
        if maxTokens > remote.maxContextLength {
            maxTokens = remote.maxContextLength
            logger.debug("Applied context limit: \(maxTokens)")
        }

        // Create updated options with constraints applied
        return LLMGenerationOptions(
            maxTokens: maxTokens,
            temperature: temperature,
            topP: topP,
            stopSequences: mergeStopSequences(
                runtime: baseOptions.stopSequences,
                remote: remote.defaults.stopSequences
            ),
            streamingEnabled: baseOptions.streamingEnabled,
            preferredFramework: baseOptions.preferredFramework,
            structuredOutput: baseOptions.structuredOutput,
            systemPrompt: baseOptions.systemPrompt
        )
    }

    /// Prepare prompt with system prompt and structured output formatting
    /// - Parameters:
    ///   - prompt: Original user prompt
    ///   - options: Resolved generation options
    /// - Returns: Formatted prompt ready for generation
    public func preparePrompt(
        _ prompt: String,
        withOptions options: LLMGenerationOptions
    ) -> String {
        var effectivePrompt = prompt

        // Apply structured output formatting first if needed
        if let structuredConfig = options.structuredOutput {
            effectivePrompt = structuredOutputHandler.preparePrompt(
                originalPrompt: effectivePrompt,
                config: structuredConfig
            )
        }

        // Then apply system prompt if provided
        if let systemPrompt = options.systemPrompt {
            effectivePrompt = "\(systemPrompt)\n\n\(effectivePrompt)"
        }

        return effectivePrompt
    }

    /// Merge stop sequences from runtime and remote
    private func mergeStopSequences(runtime: [String], remote: [String]?) -> [String] {
        var sequences = runtime
        if let remoteSequences = remote {
            sequences.append(contentsOf: remoteSequences)
        }
        // Remove duplicates while preserving order
        return sequences.reduce(into: [String]()) { result, sequence in
            if !result.contains(sequence) {
                result.append(sequence)
            }
        }
    }
}
