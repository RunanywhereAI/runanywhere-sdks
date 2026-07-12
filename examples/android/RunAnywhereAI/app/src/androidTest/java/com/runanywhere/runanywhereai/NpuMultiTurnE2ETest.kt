package com.runanywhere.runanywhereai

import ai.runanywhere.proto.v1.ChatMessage as ProtoChatMessage
import ai.runanywhere.proto.v1.InferenceFramework
import ai.runanywhere.proto.v1.MessageRole
import android.util.Log
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.runanywhere.runanywhereai.data.ModelCatalog
import com.runanywhere.runanywhereai.state.GlobalState
import com.runanywhere.sdk.npu.qhexrt.QHexRT
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.deleteModel
import com.runanywhere.sdk.public.extensions.downloadModel
import com.runanywhere.sdk.public.extensions.generate
import com.runanywhere.sdk.public.extensions.loadModel
import com.runanywhere.sdk.public.extensions.registerModel
import com.runanywhere.sdk.public.types.RALLMGenerateRequest
import com.runanywhere.sdk.public.types.RALLMGenerationOptions
import com.runanywhere.sdk.public.types.RAModelLoadRequest
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * On-device end-to-end proof of the **multi-turn chat history** fix.
 *
 * Loads ONE NPU (QHexRT) LLM once (register -> download -> load), then runs two
 * turns on the SAME loaded model:
 *   Turn 1 — introduces a fact ("My name is Aman.") with empty history.
 *   Turn 2 — asks "What is my name?" passing Turn-1 as history.
 *
 * Pre-fix (history dropped on the public path) Turn 2 cannot recall the name and
 * this FAILS; post-fix (history forwarded via LLMGenerateRequest field 27) the
 * model answers "Aman" and this PASSES.
 *
 * Selection (instrumentation args, `-e key value`), mirroring [NpuModelE2ETest]:
 *   -e modelId <catalog-id>  default `qwen3_0_6b` (optionally _v75/_v79/_v81/_v83)
 *   -e hfToken <hf_...>      download private runanywhere/<name>_HNPU repos
 *
 * NOT product code — androidTest only. Deletes the model in `finally`.
 */
@RunWith(AndroidJUnit4::class)
class NpuMultiTurnE2ETest {

    private val tag = "NPU_E2E"

    private companion object {
        const val LOAD_TIMEOUT_MS = 300_000L
        const val INFER_TIMEOUT_MS = 300_000L
        const val DEFAULT_MODEL_ID = "qwen3_0_6b"
        val ARCH_SUFFIX = Regex("(.+)_(v(?:75|79|81|83))$")
    }

    @Test
    fun multiTurnRemembersName() {
        val args = InstrumentationRegistry.getArguments()
        val rawId = args.getString("modelId")?.takeIf { it.isNotBlank() } ?: DEFAULT_MODEL_ID
        val (logicalId, requestedArch) = logicalIdAndArch(rawId)
        val model = ModelCatalog.npuCatalog.firstOrNull { it.id == rawId }
            ?: ModelCatalog.npuCatalog.firstOrNull { it.id == logicalId }
            ?: run {
                assertTrue("unknown -e modelId '$rawId' (expected a ModelCatalog.npuCatalog id)", false)
                return
            }
        val hfToken = args.getString("hfToken")?.takeIf { it.isNotBlank() }

        runBlocking {
            try {
                awaitSdkReady(180_000)

                // ---- NPU capability + arch match (a v79 bundle will not load on v81) ----
                val npu = QHexRT.probeNpu()
                if (!npu.qhexrt_supported) throw AssertionError("device NPU not supported (arch=${npu.arch_name})")
                val expectedArch = requestedArch ?: npu.arch_name
                if (!npu.arch_name.equals(expectedArch, ignoreCase = true)) {
                    throw AssertionError(
                        "arch mismatch: requested=$expectedArch device=${npu.arch_name} (context binaries are arch-pinned)",
                    )
                }

                if (hfToken != null) RunAnywhere.setHfToken(hfToken)

                val registered = RunAnywhere.registerModel(
                    id = model.id, name = model.name, url = model.url,
                    framework = model.framework, modality = model.category,
                )
                RunAnywhere.downloadModel(registered) { }
                val load = withTimeout(LOAD_TIMEOUT_MS) {
                    RunAnywhere.loadModel(RAModelLoadRequest(model_id = model.id))
                }
                if (!load.success) throw AssertionError(load.error_message.ifBlank { "load success=false" })
                if (load.framework != InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT) {
                    throw AssertionError("expected QHEXRT framework, got ${load.framework.name}")
                }

                // Greedy so the answer is deterministic (disable_thinking to keep it terse).
                val greedy = RALLMGenerationOptions(
                    max_tokens = 48,
                    temperature = 0f,
                    top_p = 1f,
                    disable_thinking = true,
                )

                // ---- Turn 1: introduce the fact, empty history ----
                val turn1Prompt = "My name is Aman. Remember it."
                val reply1 = withTimeout(INFER_TIMEOUT_MS) {
                    RunAnywhere.generate(
                        RALLMGenerateRequest(prompt = turn1Prompt, options = greedy, history = emptyList()),
                    )
                }.text.trim()
                Log.i(tag, "multiturn id=${model.id} reply1=$reply1")
                // Guard greedy luck: if the model already echoes the name in Turn 1, the
                // Turn-2 assertion no longer isolates history recall — log and continue.
                if (reply1.contains("Aman", ignoreCase = true)) {
                    Log.i(tag, "multiturn note: reply1 already contains 'Aman' (Turn-2 gate weakened)")
                }

                // ---- Turn 2: ask on the SAME model, passing Turn 1 as history ----
                val history = listOf(
                    ProtoChatMessage(role = MessageRole.MESSAGE_ROLE_USER, content = turn1Prompt),
                    ProtoChatMessage(role = MessageRole.MESSAGE_ROLE_ASSISTANT, content = reply1),
                )
                val reply2 = withTimeout(INFER_TIMEOUT_MS) {
                    RunAnywhere.generate(
                        RALLMGenerateRequest(prompt = "What is my name?", options = greedy, history = history),
                    )
                }.text.trim()
                Log.i(tag, "multiturn id=${model.id} reply2=$reply2")

                assertTrue(
                    "multi-turn history dropped: reply2 does not mention 'Aman' (reply2=$reply2)",
                    reply2.contains("Aman", ignoreCase = true),
                )
            } finally {
                if (args.getString("keepModel") != "true") runCatching { RunAnywhere.deleteModel(model.id) }
            }
        }
    }

    private fun logicalIdAndArch(rawId: String): Pair<String, String?> {
        val match = ARCH_SUFFIX.matchEntire(rawId) ?: return rawId to null
        return match.groupValues[1] to match.groupValues[2]
    }

    private fun awaitSdkReady(timeoutMs: Long) {
        val deadline = System.currentTimeMillis() + timeoutMs
        while (System.currentTimeMillis() < deadline) {
            if (GlobalState.ready) return
            GlobalState.initError?.let { error("SDK init failed: $it") }
            Thread.sleep(500)
        }
        error("SDK not ready within ${timeoutMs}ms")
    }
}
