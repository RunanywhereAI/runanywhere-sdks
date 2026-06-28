package com.runanywhere.runanywhereai.ui.screens.npu.screens

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.runanywhere.runanywhereai.ui.screens.npu.AppState
import com.runanywhere.runanywhereai.ui.screens.npu.Screen
import com.runanywhere.runanywhereai.ui.screens.npu.MetricRow
import com.runanywhere.runanywhereai.ui.screens.npu.SectionCard
import com.runanywhere.runanywhereai.ui.screens.npu.StatusPill
import com.runanywhere.runanywhereai.ui.screens.npu.theme.RaSuccess
import com.runanywhere.runanywhereai.ui.screens.npu.theme.Spacing

@Composable
fun HomeScreen(
    state: AppState,
    onNavigate: (Screen) -> Unit,
) {
    val npu = state.npu
    val supported = npu?.supported == true
    val warnColor = MaterialTheme.colorScheme.tertiary
    Column(
        Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(Spacing.md),
        verticalArrangement = Arrangement.spacedBy(Spacing.md),
    ) {
        Text("RunAnywhere", style = MaterialTheme.typography.displaySmall, fontWeight = FontWeight.Bold)
        Text(
            "On-device Qualcomm Hexagon NPU runtime",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )

        SectionCard(title = "Device") {
            Row(
                Modifier.fillMaxWidth().padding(bottom = Spacing.sm),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    npu?.socModel?.ifBlank { "Unknown SoC" } ?: "Detecting…",
                    style = MaterialTheme.typography.titleLarge,
                )
                StatusPill(
                    label = if (supported) "NPU ${npu?.arch}" else "Unsupported",
                    color = if (supported) RaSuccess else warnColor,
                )
            }
            MetricRow("Hexagon arch", npu?.arch ?: "—")
            MetricRow("SoC id", npu?.socId?.takeIf { it >= 0 }?.toString() ?: "—")
            MetricRow("QHexRT engine", if (state.qhexrtRegistered) "ready" else "unavailable")
        }

        if (!supported) {
            Surface(
                color = warnColor.copy(alpha = 0.10f),
                shape = MaterialTheme.shapes.medium,
                border = BorderStroke(1.dp, warnColor.copy(alpha = 0.5f)),
            ) {
                Text(
                    "QHexRT requires a Hexagon v75, v79 or v81 NPU (Snapdragon 8 Gen 3 or newer). " +
                        "Detected ${npu?.arch ?: "unknown"} — this device is not supported.",
                    style = MaterialTheme.typography.bodyMedium,
                    color = warnColor,
                    modifier = Modifier.padding(Spacing.md),
                )
            }
        }

        SectionCard(title = "Run") {
            Column(verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
                NavRow("Chat", "LLM text generation", Screen.Llm, onNavigate)
                NavRow("Vision", "Image + prompt (VLM)", Screen.Vlm, onNavigate)
                NavRow("Speech to Text", "Transcribe audio (Whisper)", Screen.Stt, onNavigate)
                NavRow("Text to Speech", "Synthesize audio (MeloTTS)", Screen.Tts, onNavigate)
                NavRow("Models", "Download + manage models", Screen.Models, onNavigate)
            }
        }
    }
}

@Composable
private fun NavRow(title: String, subtitle: String, screen: Screen, onNavigate: (Screen) -> Unit) {
    Surface(
        color = MaterialTheme.colorScheme.surfaceContainerHigh,
        shape = MaterialTheme.shapes.small,
        modifier = Modifier.fillMaxWidth().clickable { onNavigate(screen) },
    ) {
        Column(Modifier.padding(Spacing.md)) {
            Text(title, style = MaterialTheme.typography.titleMedium)
            Text(subtitle, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}
