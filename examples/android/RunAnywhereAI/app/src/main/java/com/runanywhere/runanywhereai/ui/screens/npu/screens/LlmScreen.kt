package com.runanywhere.runanywhereai.ui.screens.npu.screens

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.TextFieldValue
import com.runanywhere.sdk.npu.qhexrt.NpuInfo
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.aggregateStream
import com.runanywhere.sdk.public.extensions.generate
import com.runanywhere.sdk.public.extensions.generateStream
import com.runanywhere.runanywhereai.data.settings.SettingsRepository
import com.runanywhere.runanywhereai.ui.screens.npu.MetricStrip
import com.runanywhere.runanywhereai.ui.screens.npu.NpuModality
import com.runanywhere.runanywhereai.ui.screens.npu.NpuModelBar
import com.runanywhere.runanywhereai.ui.screens.npu.NpuModelsViewModel
import com.runanywhere.runanywhereai.ui.screens.npu.SectionCard
import com.runanywhere.runanywhereai.ui.screens.npu.theme.Spacing
import com.runanywhere.sdk.public.types.RALLMGenerationOptions
import kotlinx.coroutines.launch

@Composable
fun LlmScreen(modelsVm: NpuModelsViewModel) {
    val scope = rememberCoroutineScope()
    var prompt by remember { mutableStateOf(TextFieldValue("Explain what an NPU is in one sentence.")) }
    var output by remember { mutableStateOf("") }
    var running by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var tps by remember { mutableStateOf("—") }
    var ttft by remember { mutableStateOf("—") }
    var engine by remember { mutableStateOf("—") }
    val loadedModelId = modelsVm.loadedId(NpuModality.LLM)

    Column(
        Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(Spacing.md),
        verticalArrangement = Arrangement.spacedBy(Spacing.md),
    ) {
        NpuModelBar(modality = NpuModality.LLM, vm = modelsVm)

        OutlinedTextField(
            value = prompt,
            onValueChange = { prompt = it },
            label = { Text("Prompt") },
            modifier = Modifier.fillMaxWidth(),
            enabled = !running,
        )
        Button(
            onClick = {
                output = ""; error = null; running = true
                scope.launch {
                    try {
                        // Drive generation from the app-wide Settings (More → Settings),
                        // so the NPU/QHexRT tab honors the same temperature / max tokens /
                        // system prompt / streaming toggle as the rest of the app.
                        val s = SettingsRepository.settings
                        val opts = RALLMGenerationOptions(
                            max_tokens = s.maxTokens,
                            temperature = s.temperature,
                            system_prompt = s.systemPrompt.ifBlank { null },
                            streaming_enabled = s.streaming,
                        )
                        val result = if (s.streaming) {
                            val events = RunAnywhere.generateStream(prompt.text, opts)
                            RunAnywhere.aggregateStream(prompt.text, events) { acc ->
                                output = acc
                            }
                        } else {
                            RunAnywhere.generate(prompt.text, opts)
                        }
                        output = result.text
                        tps = "%.1f".format(result.tokens_per_second)
                        ttft = result.ttft_ms?.let { "%.0f ms".format(it) } ?: "—"
                        engine = result.framework ?: "—"
                    } catch (e: Exception) {
                        error = e.message ?: "generation failed"
                    } finally {
                        running = false
                    }
                }
            },
            enabled = !running && prompt.text.isNotBlank() && loadedModelId != null,
            modifier = Modifier.fillMaxWidth(),
        ) {
            Text(
                when {
                    running -> "Generating…"
                    loadedModelId == null -> "Load a model to generate"
                    else -> "Generate"
                },
            )
        }

        MetricStrip(listOf("tokens/s" to tps, "ttft" to ttft, "engine" to engine))

        error?.let {
            Text(it, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodyMedium)
        }

        SectionCard(title = "Response") {
            Text(
                output.ifBlank { if (running) "…" else "Output appears here." },
                style = MaterialTheme.typography.bodyLarge,
                color = if (output.isBlank()) MaterialTheme.colorScheme.onSurfaceVariant else MaterialTheme.colorScheme.onSurface,
            )
        }
    }
}
