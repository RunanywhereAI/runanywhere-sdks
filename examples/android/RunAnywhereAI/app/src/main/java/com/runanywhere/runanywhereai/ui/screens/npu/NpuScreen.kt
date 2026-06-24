package com.runanywhere.runanywhereai.ui.screens.npu

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.runanywhere.runanywhereai.ui.navigation.Chat
import com.runanywhere.runanywhereai.ui.navigation.Stt
import com.runanywhere.runanywhereai.ui.navigation.Tts
import com.runanywhere.runanywhereai.ui.navigation.Vision
import com.runanywhere.runanywhereai.ui.theme.LocalDimens
import com.runanywhere.runanywhereai.ui.theme.icons.RACIcons
import com.runanywhere.runanywhereai.util.readableWidth
import com.runanywhere.sdk.npu.qhexrt.NpuInfo
import com.runanywhere.sdk.npu.qhexrt.QHexRT
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

private data class Modality(val label: String, val description: String, val route: Any)

private val MODALITIES = listOf(
    Modality("Chat (LLM)", "Text generation on the NPU", Chat),
    Modality("Vision (VLM)", "Describe images", Vision),
    Modality("Speech to Text", "Transcribe audio", Stt),
    Modality("Text to Speech", "Synthesize speech", Tts),
)

@Composable
fun NpuScreen(onNavigate: (Any) -> Unit) {
    val dimens = LocalDimens.current

    // Probe off the main thread; null while loading.
    val npu: NpuInfo? by produceState<NpuInfo?>(initialValue = null) {
        value = withContext(Dispatchers.IO) { QHexRT.probeNpu() }
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .readableWidth()
            .verticalScroll(rememberScrollState())
            .padding(dimens.screenPadding),
        verticalArrangement = Arrangement.spacedBy(dimens.spacingLg),
    ) {
        DeviceCard(npu)

        Text(
            "Run on the NPU",
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.SemiBold,
        )
        Text(
            "Load a QHexRT model, then use any modality below — it routes through the NPU backend.",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )

        MODALITIES.forEach { m -> ModalityRow(m, onNavigate) }
    }
}

@Composable
private fun DeviceCard(npu: NpuInfo?) {
    val supported = npu?.supported == true
    Surface(
        color = MaterialTheme.colorScheme.surfaceVariant,
        shape = RoundedCornerShape(16.dp),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            StatusPill(
                label = when {
                    npu == null -> "Detecting…"
                    supported -> "NPU supported"
                    else -> "Unsupported"
                },
                tone = if (supported) MaterialTheme.colorScheme.primary else MaterialTheme.colorScheme.error,
            )
            MetricRow("SoC model", npu?.socModel?.ifBlank { "Unknown SoC" } ?: "—")
            MetricRow("Hexagon arch", npu?.arch ?: "—")
            MetricRow("SoC id", npu?.socId?.takeIf { it >= 0 }?.toString() ?: "—")

            if (npu != null && !supported) {
                Surface(
                    color = MaterialTheme.colorScheme.errorContainer,
                    shape = RoundedCornerShape(12.dp),
                    modifier = Modifier.fillMaxWidth(),
                ) {
                    Text(
                        "QHexRT requires a Hexagon v79 or v81 NPU (Snapdragon 8 Elite / 8 Gen 3 class). " +
                            "This device reports ${npu.arch} — NPU inference may be unavailable; the " +
                            "SDK falls back to other backends.",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onErrorContainer,
                        modifier = Modifier.padding(12.dp),
                    )
                }
            }
        }
    }
}

@Composable
private fun StatusPill(label: String, tone: Color) {
    Surface(color = tone.copy(alpha = 0.12f), shape = CircleShape) {
        Row(
            Modifier.padding(horizontal = 12.dp, vertical = 6.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(6.dp),
        ) {
            Box(Modifier.size(8.dp).clip(CircleShape).background(tone))
            Text(label, style = MaterialTheme.typography.labelLarge, color = tone)
        }
    }
}

@Composable
private fun MetricRow(label: String, value: String) {
    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
        Text(label, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        Text(value, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.SemiBold)
    }
}

@Composable
private fun ModalityRow(m: Modality, onNavigate: (Any) -> Unit) {
    Surface(
        color = MaterialTheme.colorScheme.surfaceVariant,
        shape = RoundedCornerShape(16.dp),
        modifier = Modifier.fillMaxWidth().clickable { onNavigate(m.route) },
    ) {
        Row(
            Modifier.padding(16.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            Icon(RACIcons.Outline.Cpu, contentDescription = null, tint = MaterialTheme.colorScheme.primary)
            Column(Modifier.weight(1f)) {
                Text(m.label, style = MaterialTheme.typography.bodyLarge)
                Text(
                    m.description,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            Icon(RACIcons.Outline.ChevronRight, contentDescription = null, tint = MaterialTheme.colorScheme.onSurfaceVariant)
        }
    }
}
