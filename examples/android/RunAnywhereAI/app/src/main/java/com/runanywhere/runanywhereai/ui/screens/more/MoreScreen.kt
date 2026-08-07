package com.runanywhere.runanywhereai.ui.screens.more

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
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import com.runanywhere.runanywhereai.ui.components.ScreenLede
import com.runanywhere.runanywhereai.ui.navigation.Benchmarks
import com.runanywhere.runanywhereai.ui.HybridBetaCopy
import com.runanywhere.runanywhereai.ui.navigation.CloudProviders
import com.runanywhere.runanywhereai.ui.navigation.Diarization
import com.runanywhere.runanywhereai.ui.navigation.Diffusion
import com.runanywhere.runanywhereai.ui.navigation.Documents
import com.runanywhere.runanywhereai.ui.navigation.Ocr
import com.runanywhere.runanywhereai.ui.navigation.Segmentation
import com.runanywhere.runanywhereai.ui.navigation.Settings
import com.runanywhere.runanywhereai.ui.navigation.Solutions
import com.runanywhere.runanywhereai.ui.navigation.Stt
import com.runanywhere.runanywhereai.ui.navigation.Tools
import com.runanywhere.runanywhereai.ui.navigation.Tts
import com.runanywhere.runanywhereai.ui.navigation.Vad
import com.runanywhere.runanywhereai.ui.navigation.Vision
import com.runanywhere.runanywhereai.ui.theme.LocalDimens
import com.runanywhere.runanywhereai.ui.theme.icons.RACIcons

private enum class AdvancedGroup(val title: String) {
    ASSISTANT("Assistant add-ons"),
    SPEECH("Speech lab"),
    DEVELOPER("Developer diagnostics"),
}

private data class AdvancedEntry(
    val label: String,
    val description: String,
    val icon: ImageVector,
    val group: AdvancedGroup,
    val route: Any,
)

@Composable
fun MoreScreen(onNavigate: (Any) -> Unit) {
    val dimens = LocalDimens.current
    val entries = listOf(
        AdvancedEntry("Settings", "Personalization, privacy, and account controls", RACIcons.Outline.Settings, AdvancedGroup.ASSISTANT, Settings),
        AdvancedEntry("Documents", "Inspect document Q&A setup and sources", RACIcons.Outline.FileText, AdvancedGroup.ASSISTANT, Documents),
        AdvancedEntry("Images & live", "Photo prompts, camera mode, and VLM metrics", RACIcons.Outline.Eye, AdvancedGroup.ASSISTANT, Vision()),
        AdvancedEntry("Document OCR", "Extract text from invoices and scans (Nemotron OCR)", RACIcons.Outline.ScanText, AdvancedGroup.ASSISTANT, Ocr),
        AdvancedEntry("Segmentation", "Semantic image segmentation (SegFormer)", RACIcons.Outline.Layers, AdvancedGroup.ASSISTANT, Segmentation),
        AdvancedEntry("Diarization", "Who spoke when (NVIDIA Sortformer)", RACIcons.Outline.Users, AdvancedGroup.SPEECH, Diarization),
        AdvancedEntry("Image generation", "Text-to-image on the NPU (Cosmos3-Edge diffusion)", RACIcons.Outline.Sparkles, AdvancedGroup.ASSISTANT, Diffusion),
        AdvancedEntry("Read aloud", "Generate speech and preview voices", RACIcons.Outline.Volume, AdvancedGroup.SPEECH, Tts),
        AdvancedEntry("Transcription", HybridBetaCopy.TRANSCRIPTION_ENTRY_DESCRIPTION, RACIcons.Outline.Waveform, AdvancedGroup.SPEECH, Stt),
        AdvancedEntry("Voice activity", "Tune speech detection infrastructure", RACIcons.Outline.Pulse, AdvancedGroup.SPEECH, Vad),
        AdvancedEntry("Web & tools", "Inspect and control assistant tools", RACIcons.Outline.Tool, AdvancedGroup.DEVELOPER, Tools),
        AdvancedEntry("Solutions", "Run YAML-driven SDK pipelines", RACIcons.Outline.Route, AdvancedGroup.DEVELOPER, Solutions),
        AdvancedEntry("Cloud providers", HybridBetaCopy.CLOUD_PROVIDERS_ENTRY_DESCRIPTION, RACIcons.Outline.Cloud, AdvancedGroup.DEVELOPER, CloudProviders),
        AdvancedEntry("Benchmarks", "Measure speed, memory, and device behavior", RACIcons.Outline.Gauge, AdvancedGroup.DEVELOPER, Benchmarks),
    )

    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(dimens.screenPadding),
        verticalArrangement = Arrangement.spacedBy(dimens.spacingLg),
    ) {
        ScreenLede(
            "SDK workbenches and diagnostics live here so the assistant stays simple.",
        )

        AdvancedGroup.entries.forEach { group ->
            AdvancedSection(group.title) {
                entries.filter { it.group == group }.forEach { entry ->
                    AdvancedRow(entry) { onNavigate(entry.route) }
                }
            }
        }
    }
}

@Composable
private fun AdvancedSection(title: String, content: @Composable () -> Unit) {
    val dimens = LocalDimens.current
    Column(verticalArrangement = Arrangement.spacedBy(dimens.spacingSm)) {
        Text(
            text = title,
            style = MaterialTheme.typography.titleSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(horizontal = dimens.spacingXs),
        )
        content()
    }
}

@Composable
private fun AdvancedRow(entry: AdvancedEntry, onClick: () -> Unit) {
    val dimens = LocalDimens.current
    Surface(
        color = MaterialTheme.colorScheme.surfaceContainerHigh,
        shape = RoundedCornerShape(dimens.radiusLg),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Row(
            modifier = Modifier
                .clip(RoundedCornerShape(dimens.radiusLg))
                .clickable(onClick = onClick)
                .padding(dimens.spacingLg),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(dimens.spacingMd),
        ) {
            Icon(
                imageVector = entry.icon,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.primary,
                modifier = Modifier.size(dimens.iconMd),
            )
            Column(modifier = Modifier.weight(1f)) {
                Text(entry.label, style = MaterialTheme.typography.bodyLarge)
                Text(
                    entry.description,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
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
