package com.runanywhere.runanywhereai.ui.screens.tts

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import ai.runanywhere.proto.v1.InferenceFramework
import androidx.compose.material3.Button
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Slider
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.lifecycle.viewmodel.compose.viewModel
import com.runanywhere.runanywhereai.ui.screens.models.ModelSelectionContext
import com.runanywhere.runanywhereai.ui.screens.models.ModelSelectionSheet
import com.runanywhere.runanywhereai.ui.screens.models.ModelSelectionViewModel
import com.runanywhere.runanywhereai.ui.theme.LocalDimens
import com.runanywhere.runanywhereai.util.readableWidth
import com.runanywhere.runanywhereai.ui.theme.RACTextStyles
import com.runanywhere.runanywhereai.ui.theme.icons.RACIcons
import java.util.Locale
import kotlin.math.roundToInt

@Composable
fun TtsScreen() {
    val dimens = LocalDimens.current
    val ttsVm: TtsViewModel = viewModel()
    val voiceVm: ModelSelectionViewModel =
        viewModel(factory = ModelSelectionViewModel.Factory(ModelSelectionContext.TTS))
    var showSheet by remember { mutableStateOf(false) }

    DisposableEffect(ttsVm) {
        onDispose { ttsVm.stop() }
    }

    val voice = voiceVm.state.models.firstOrNull { it.id == voiceVm.state.currentModelId }
    val isSystemVoice = voice != null &&
        (voice.id == "system-tts" || voice.framework == InferenceFramework.INFERENCE_FRAMEWORK_SYSTEM_TTS)
    val busy = ttsVm.isGenerating || ttsVm.isSpeaking
    val hasText = ttsVm.text.isNotBlank() && voice != null
    val canGenerate = hasText && !isSystemVoice && !busy
    val canSpeak = hasText && !busy

    Column(
        modifier = Modifier
            .fillMaxSize()
            .readableWidth()
            .verticalScroll(rememberScrollState())
            .padding(dimens.screenPadding),
        verticalArrangement = Arrangement.spacedBy(dimens.spacingLg),
    ) {
        VoiceCard(voiceName = voice?.name, onClick = { showSheet = true })

        OutlinedTextField(
            value = ttsVm.text,
            onValueChange = ttsVm::onTextChange,
            modifier = Modifier.fillMaxWidth(),
            label = { Text("Text to speak") },
            minLines = 4,
            maxLines = 10,
        )

        TextButton(onClick = ttsVm::surpriseMe) {
            Icon(
                imageVector = RACIcons.Outline.Refresh,
                contentDescription = null,
                modifier = Modifier.size(dimens.iconSm),
            )
            Text("Surprise me", modifier = Modifier.padding(start = dimens.spacingSm))
        }

        SliderRow("Speed", String.format(Locale.US, "%.1f×", ttsVm.speed), ttsVm.speed, ttsVm::onSpeedChange)

        Row(horizontalArrangement = Arrangement.spacedBy(dimens.spacingMd)) {
            OutlinedButton(
                onClick = ttsVm::generate,
                enabled = canGenerate,
                modifier = Modifier.weight(1f),
            ) {
                Icon(
                    imageVector = RACIcons.Outline.Bolt,
                    contentDescription = null,
                    modifier = Modifier.size(dimens.iconSm),
                )
                Text(
                    text = if (ttsVm.isGenerating) "Generating…" else "Generate",
                    modifier = Modifier.padding(start = dimens.spacingSm),
                )
            }
            Button(
                onClick = { if (ttsVm.isSpeaking) ttsVm.stop() else ttsVm.speak() },
                enabled = ttsVm.isSpeaking || canSpeak,
                modifier = Modifier.weight(1f),
            ) {
                Icon(
                    imageVector = if (ttsVm.isSpeaking) RACIcons.Outline.PlayerStop else RACIcons.Outline.PlayerPlay,
                    contentDescription = null,
                    modifier = Modifier.size(dimens.iconSm),
                )
                Text(
                    text = if (ttsVm.isSpeaking) "Stop" else "Speak",
                    modifier = Modifier.padding(start = dimens.spacingSm),
                )
            }
        }

        ttsVm.metrics?.let { MetricsCard(it) }
        ttsVm.error?.let {
            Text(it, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.error)
        }
    }

    if (showSheet) {
        ModelSelectionSheet(viewModel = voiceVm, onDismiss = { showSheet = false })
    }
}

@Composable
private fun VoiceCard(voiceName: String?, onClick: () -> Unit) {
    val dimens = LocalDimens.current
    Surface(
        color = MaterialTheme.colorScheme.surfaceContainerHigh,
        shape = RoundedCornerShape(dimens.radiusLg),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Row(
            modifier = Modifier
                .clickable(onClick = onClick)
                .padding(dimens.spacingLg),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(dimens.spacingMd),
        ) {
            Icon(
                imageVector = RACIcons.Outline.Robot,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.primary,
                modifier = Modifier.size(dimens.iconMd),
            )
            Column(modifier = Modifier.weight(1f)) {
                Text("Voice", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                Text(
                    text = voiceName ?: "Select a voice",
                    style = MaterialTheme.typography.bodyLarge,
                )
            }
            Icon(
                imageVector = RACIcons.Outline.ChevronRight,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.size(dimens.iconSm),
            )
        }
    }
}

private fun formatBytes(bytes: Long): String = when {
    bytes >= 1_000_000 -> String.format(Locale.US, "%.1f MB", bytes / 1_000_000.0)
    bytes >= 1_000 -> String.format(Locale.US, "%.0f KB", bytes / 1_000.0)
    else -> "$bytes B"
}

@Composable
private fun MetricsCard(metrics: TtsMetrics) {
    val dimens = LocalDimens.current
    val rows = buildList {
        metrics.durationSec?.let { add("Duration" to String.format(Locale.US, "%.1fs", it)) }
        metrics.charsPerSec?.let { add("Speed" to String.format(Locale.US, "%.0f chars/s", it)) }
        metrics.processingMs?.let { add("Synthesis" to "${it}ms") }
        metrics.sizeBytes?.let { add("Audio size" to formatBytes(it)) }
        metrics.sampleRate?.let { add("Sample rate" to "${it} Hz") }
    }
    if (rows.isEmpty()) return
    Surface(
        color = MaterialTheme.colorScheme.surfaceContainerHigh,
        shape = RoundedCornerShape(dimens.radiusLg),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Column(
            modifier = Modifier.padding(dimens.spacingLg),
            verticalArrangement = Arrangement.spacedBy(dimens.spacingSm),
        ) {
            rows.forEach { (label, value) ->
                Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    Text(label, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                    Text(value, style = RACTextStyles.Metric)
                }
            }
        }
    }
}

@Composable
private fun SliderRow(label: String, valueText: String, value: Float, onValueChange: (Float) -> Unit) {
    Column {
        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Text(label, style = MaterialTheme.typography.bodyLarge)
            Text(valueText, style = RACTextStyles.Metric, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        Slider(
            value = value,
            onValueChange = { onValueChange((it * 10).roundToInt() / 10f) },
            valueRange = 0.5f..2f,
            steps = 14,
        )
    }
}
