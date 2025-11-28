import Foundation
import LLM
import RunAnywhere

/// Utility for determining the appropriate LLM template based on model characteristics
public struct LLMSwiftTemplateResolver {
    private static let logger = SDKLogger(category: "TemplateResolver")

    /// Determine the appropriate template for a model
    /// - Parameters:
    ///   - modelPath: Path to the model file
    ///   - systemPrompt: Optional system prompt
    /// - Returns: Appropriate Template for the model
    public static func determineTemplate(from modelPath: String, systemPrompt: String? = nil) -> Template {
        let filename = URL(fileURLWithPath: modelPath).lastPathComponent.lowercased()

        logger.info("🔍 Determining template for filename: \(filename)")
        if let systemPrompt = systemPrompt {
            logger.info("📝 Using system prompt: \(systemPrompt.prefix(100))...")
        }

        if filename.contains("qwen") {
            // Qwen models typically use ChatML format
            logger.info("✅ Using ChatML template for Qwen model")
            return .chatML(systemPrompt)
        } else if filename.contains("chatml") || filename.contains("openai") {
            return .chatML(systemPrompt)
        } else if filename.contains("alpaca") {
            return .alpaca(systemPrompt)
        } else if filename.contains("llama") {
            return .llama(systemPrompt)
        } else if filename.contains("mistral") {
            // Mistral doesn't support system prompts in the same way
            if systemPrompt != nil {
                logger.warning("⚠️ Mistral template doesn't support system prompts, ignoring")
            }
            return .mistral
        } else if filename.contains("gemma") {
            // Gemma doesn't support system prompts in the same way
            if systemPrompt != nil {
                logger.warning("⚠️ Gemma template doesn't support system prompts, ignoring")
            }
            return .gemma
        }

        // Default to ChatML
        logger.info("⚠️ Using default ChatML template")
        return .chatML(systemPrompt)
    }
}
