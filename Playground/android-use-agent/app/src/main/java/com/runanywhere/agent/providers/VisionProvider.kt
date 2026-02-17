package com.runanywhere.agent.providers

import android.content.Context
import android.util.Base64
import android.util.Log
import com.runanywhere.agent.AgentApplication
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.VLM.VLMGenerationOptions
import com.runanywhere.sdk.public.extensions.VLM.VLMImage
import com.runanywhere.sdk.public.extensions.downloadModel
import com.runanywhere.sdk.public.extensions.isVLMModelLoaded
import com.runanywhere.sdk.public.extensions.loadVLMModel
import com.runanywhere.sdk.public.extensions.processImageStream
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File
import java.io.FileOutputStream

/**
 * Abstraction for screen understanding via Vision Language Models (VLM).
 *
 * Returns enhanced context from screenshots to improve the agent's
 * decision quality. The returned text is injected into the LLM prompt
 * alongside the accessibility tree elements.
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
 */
class TextOnlyVisionProvider : VisionProvider {
    override val isAvailable: Boolean = false

    override suspend fun analyzeScreen(
        screenshotBase64: String,
        screenElements: String,
        goal: String
    ): String? = null
}

/**
 * On-device VLM implementation using the RunAnywhere SDK.
 *
 * Uses SmolVLM 256M to analyze screenshots locally on the device.
 * The VLM model must be downloaded and loaded before use — call
 * [ensureModelReady] during agent startup.
 */
class OnDeviceVisionProvider(
    private val vlmModelId: String = AgentApplication.VLM_MODEL_ID,
    private val context: Context
) : VisionProvider {

    companion object {
        private const val TAG = "OnDeviceVisionProvider"
    }

    override val isAvailable: Boolean
        get() = RunAnywhere.isVLMModelLoaded

    override suspend fun analyzeScreen(
        screenshotBase64: String,
        screenElements: String,
        goal: String
    ): String? {
        if (!isAvailable) return null

        return withContext(Dispatchers.Default) {
            try {
                // Decode base64 screenshot to a temp JPEG file
                val tempFile = decodeBase64ToTempFile(screenshotBase64)
                try {
                    val image = VLMImage.fromFilePath(tempFile.absolutePath)
                    val prompt = "Briefly describe this Android screen. " +
                            "Focus on the main content, key UI elements, and what app is showing. " +
                            "The user wants to: $goal"
                    val options = VLMGenerationOptions(maxTokens = 150)

                    val result = StringBuilder()
                    RunAnywhere.processImageStream(image, prompt, options).collect { token ->
                        result.append(token)
                    }
                    result.toString().trim().ifEmpty { null }
                } finally {
                    tempFile.delete()
                }
            } catch (e: Exception) {
                Log.w(TAG, "VLM screen analysis failed: ${e.message}")
                null
            }
        }
    }

    /**
     * Download (if needed) and load the VLM model.
     * Call this before the agent loop starts.
     *
     * @param onProgress called with download progress (0.0 to 1.0)
     * @param onLog called with status messages
     */
    suspend fun ensureModelReady(
        onProgress: (Float) -> Unit = {},
        onLog: (String) -> Unit = {}
    ) {
        if (isAvailable) return

        try {
            RunAnywhere.loadVLMModel(vlmModelId)
        } catch (e: Exception) {
            onLog("Downloading VLM model...")
            var lastPercent = -1
            RunAnywhere.downloadModel(vlmModelId).collect { progress ->
                val percent = (progress.progress * 100).toInt()
                onProgress(progress.progress)
                if (percent != lastPercent && percent % 10 == 0) {
                    lastPercent = percent
                    onLog("VLM download... $percent%")
                }
            }
            RunAnywhere.loadVLMModel(vlmModelId)
        }
        onLog("VLM model ready")
    }

    private fun decodeBase64ToTempFile(base64: String): File {
        val bytes = Base64.decode(base64, Base64.DEFAULT)
        val tempFile = File(context.cacheDir, "vlm_screenshot_${System.currentTimeMillis()}.jpg")
        FileOutputStream(tempFile).use { it.write(bytes) }
        return tempFile
    }
}
