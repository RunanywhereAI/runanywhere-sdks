package com.runanywhere.minimal

import android.app.Activity
import android.os.Bundle
import android.widget.Button
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import com.runanywhere.sdk.llm.llamacpp.LlamaCPP
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.api.GenerationEvent
import com.runanywhere.sdk.public.api.InferenceFramework
import com.runanywhere.sdk.public.api.LlmOptions
import com.runanywhere.sdk.public.api.ModelCategory
import com.runanywhere.sdk.public.api.ModelRegistration
import com.runanywhere.sdk.public.api.llm
import com.runanywhere.sdk.public.api.models
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

private const val MODEL_ID = "smollm2-360m-q8_0"
private const val MODEL_URL =
    "https://huggingface.co/prithivMLmods/SmolLM2-360M-GGUF/resolve/main/SmolLM2-360M.Q8_0.gguf"
private const val PROMPT = "Name three colours."

/**
 * One button, one text view. The contributor smoke test for the Kotlin SDK:
 * register a backend, initialize, put one model in the catalog, stream one
 * completion.
 *
 * Download and load are automatic — passing `LlmOptions.model` is enough. Only
 * the catalog entry has to exist first, which is the single `models.register`
 * call in [bootstrap].
 */
class MainActivity : Activity() {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    private lateinit var bootstrap: Deferred<Unit>

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        val output = TextView(this)
        val generate = Button(this).apply { text = "Generate" }
        setContentView(
            LinearLayout(this).apply {
                orientation = LinearLayout.VERTICAL
                addView(generate)
                addView(ScrollView(this@MainActivity).apply { addView(output) })
            },
        )

        bootstrap = scope.async {
            // Register the backend before initialize(), so a concurrent load
            // cannot land while only the platform backend is registered.
            LlamaCPP.register()
            RunAnywhere.initialize(context = this@MainActivity)
            // runCatching: re-registering the same id is not an error worth
            // surfacing.
            runCatching {
                RunAnywhere.models.register(
                    ModelRegistration.url(
                        name = "SmolLM2 360M Q8_0",
                        url = MODEL_URL,
                        framework = InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
                        category = ModelCategory.MODEL_CATEGORY_LANGUAGE,
                        id = MODEL_ID,
                        memoryBytes = 386_404_416L,
                    ),
                )
            }
            Unit
        }

        generate.setOnClickListener {
            generate.isEnabled = false
            output.text = "Loading $MODEL_ID (first run downloads it)...\n\n"
            scope.launch {
                bootstrap.await()
                RunAnywhere.llm
                    .generateStream(PROMPT, LlmOptions(model = MODEL_ID, maxOutputTokens = 128))
                    .collect { event ->
                        when (event) {
                            is GenerationEvent.TextDelta -> output.append(event.text)
                            is GenerationEvent.Completed ->
                                output.append(
                                    "\n\n--- ${event.result.outputTokens} tokens, " +
                                        "${event.result.tokensPerSecond} tok/s",
                                )
                            is GenerationEvent.Failed -> output.append("\n\nfailed: ${event.error.message}")
                            else -> Unit
                        }
                    }
                generate.isEnabled = true
            }
        }
    }

    override fun onDestroy() {
        scope.cancel()
        super.onDestroy()
    }
}
