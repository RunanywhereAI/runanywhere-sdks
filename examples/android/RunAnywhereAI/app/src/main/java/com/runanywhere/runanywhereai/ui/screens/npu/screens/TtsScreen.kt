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
import androidx.compose.material3.OutlinedButton
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
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.speak
import com.runanywhere.sdk.public.extensions.stopSpeaking
import com.runanywhere.runanywhereai.ui.screens.npu.MetricStrip
import com.runanywhere.runanywhereai.ui.screens.npu.NpuModality
import com.runanywhere.runanywhereai.ui.screens.npu.NpuModelBar
import com.runanywhere.runanywhereai.ui.screens.npu.NpuModelsViewModel
import com.runanywhere.runanywhereai.ui.screens.npu.SectionCard
import com.runanywhere.runanywhereai.ui.screens.npu.theme.Spacing
import kotlinx.coroutines.launch

@Composable
fun TtsScreen(modelsVm: NpuModelsViewModel) {
    val scope = rememberCoroutineScope()
    var text by remember { mutableStateOf(TextFieldValue("Hello from the RunAnywhere NPU runtime.")) }
    var running by remember { mutableStateOf(false) }
    var error by remember { mutableStateOf<String?>(null) }
    var durationMs by remember { mutableStateOf("—") }
    var rate by remember { mutableStateOf("—") }
    val loadedModelId = modelsVm.loadedId(NpuModality.TTS)

    Column(
        Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(Spacing.md),
        verticalArrangement = Arrangement.spacedBy(Spacing.md),
    ) {
        NpuModelBar(modality = NpuModality.TTS, vm = modelsVm)

        OutlinedTextField(
            value = text,
            onValueChange = { text = it },
            label = { Text("Text") },
            modifier = Modifier.fillMaxWidth(),
            enabled = !running,
        )
        Button(
            onClick = {
                error = null; running = true
                scope.launch {
                    try {
                        val out = RunAnywhere.speak(text.text)
                        durationMs = "${out.duration_ms} ms"
                        rate = if (out.sample_rate > 0) "${out.sample_rate} Hz" else "—"
                    } catch (e: Exception) {
                        error = e.message ?: "synthesis failed"
                    } finally {
                        running = false
                    }
                }
            },
            enabled = !running && text.text.isNotBlank() && loadedModelId != null,
            modifier = Modifier.fillMaxWidth(),
        ) {
            Text(
                when {
                    running -> "Speaking…"
                    loadedModelId == null -> "Load a model to speak"
                    else -> "Speak"
                },
            )
        }
        OutlinedButton(
            onClick = { scope.launch { runCatching { RunAnywhere.stopSpeaking() } } },
            modifier = Modifier.fillMaxWidth(),
        ) {
            Text("Stop")
        }

        MetricStrip(listOf("duration" to durationMs, "sample rate" to rate))

        error?.let { Text(it, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodyMedium) }

        SectionCard(title = "Text to Speech") {
            Text(
                "Synthesizes on-device and plays through the speaker. MeloTTS on NPU, " +
                    "or the CPU TTS engine as fallback.",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}
