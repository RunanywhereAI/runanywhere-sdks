package com.runanywhere.agent.providers

/**
 * Abstraction for screen understanding via Vision Language Models (VLM).
 *
 * Returns enhanced context from screenshots to improve the agent's
 * decision quality. The returned text is injected into the LLM prompt
 * alongside the accessibility tree elements.
 *
 * Drop-in replaceable: implement this interface with an on-device VLM
 * (e.g., a multimodal model via RunAnywhere SDK) to enable vision-based
 * reasoning without any changes to the agent kernel or LLM provider.
 *
 * Example on-device VLM implementation:
 * ```
 * class OnDeviceVisionProvider(private val vlmModelId: String) : VisionProvider {
 *     override val isAvailable: Boolean = true
 *
 *     override suspend fun analyzeScreen(
 *         screenshotBase64: String,
 *         screenElements: String,
 *         goal: String
 *     ): String {
 *         // Decode base64 → image, feed to VLM with prompt
 *         return RunAnywhere.generateFromImage(screenshotBase64, "Describe the Android screen...")
 *     }
 * }
 * ```
 */
interface VisionProvider {

    /**
     * Analyze a screenshot and return a text description of the screen.
     *
     * @param screenshotBase64 Base64-encoded JPEG screenshot
     * @param screenElements Compact text list of interactive UI elements
     * @param goal The user's stated goal (for context-aware analysis)
     * @return A text description of the screen, or null if analysis is unavailable
     */
    suspend fun analyzeScreen(
        screenshotBase64: String,
        screenElements: String,
        goal: String
    ): String?

    /** Whether this provider can actually analyze screenshots. */
    val isAvailable: Boolean
}

/**
 * Text-only fallback when no VLM is available.
 * Returns null, causing the agent to rely solely on the accessibility tree.
 * Replace with an on-device VLM implementation when ready.
 */
class TextOnlyVisionProvider : VisionProvider {
    override val isAvailable: Boolean = false

    override suspend fun analyzeScreen(
        screenshotBase64: String,
        screenElements: String,
        goal: String
    ): String? = null
}
