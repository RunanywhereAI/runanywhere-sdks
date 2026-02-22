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

    /**
     * VLM-only mode: analyze a screenshot and return a tool call / action decision.
     * Used when LLM is not loaded and VLM drives the agent autonomously.
     *
     * @param screenshotBase64 Base64-encoded JPEG screenshot
     * @param screenElements Compact text list of interactive UI elements
     * @param goal The user's stated goal
     * @param history Formatted action history
     * @param lastActionResult Result of the last executed action
     * @return Raw VLM output containing a tool call or JSON action, or null
     */
    suspend fun decideNextAction(
        screenshotBase64: String,
        screenElements: String,
        goal: String,
        history: String,
        lastActionResult: String?
    ): String? = null

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
 * Uses LFM2-VL 450M to analyze screenshots locally on the device.
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
                    // Action-focused prompt: tell the LLM what to do, not what the screen looks like
                    val prompt = "Look at this Android screen. The user's goal is: $goal\n" +
                            "Which element should they interact with next? " +
                            "Name the element and suggest the action (tap, type, swipe, etc). Be brief."
                    val options = VLMGenerationOptions(maxTokens = 80)

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
     * VLM-only mode: use the VLM to decide the next UI action directly.
     * The VLM sees the screenshot + element list and outputs a tool call.
     */
    override suspend fun decideNextAction(
        screenshotBase64: String,
        screenElements: String,
        goal: String,
        history: String,
        lastActionResult: String?
    ): String? {
        if (!isAvailable) return null

        return withContext(Dispatchers.Default) {
            try {
                val tempFile = decodeBase64ToTempFile(screenshotBase64)
                try {
                    val image = VLMImage.fromFilePath(tempFile.absolutePath)
                    val lastResult = lastActionResult?.let { "\nLAST_RESULT: $it" } ?: ""
                    val prompt = """You are an Android UI agent. Look at this screenshot and the SCREEN_ELEMENTS below.
GOAL: $goal

SCREEN_ELEMENTS:
$screenElements
$lastResult$history

Pick ONE action. Use ui_open_app to launch apps. Use ui_tap(index) to tap elements. Use ui_type(text) then ui_enter() for text fields. Call ui_done when finished.
Output ONLY: <tool_call>{"tool":"tool_name","arguments":{...}}</tool_call>"""

                    val options = VLMGenerationOptions(maxTokens = 100)
                    val result = StringBuilder()
                    RunAnywhere.processImageStream(image, prompt, options).collect { token ->
                        result.append(token)
                    }
                    result.toString().trim().ifEmpty { null }
                } finally {
                    tempFile.delete()
                }
            } catch (e: Exception) {
                Log.w(TAG, "VLM decision failed: ${e.message}")
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
            Log.w(TAG, "VLM load failed, attempting re-download", e)
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
