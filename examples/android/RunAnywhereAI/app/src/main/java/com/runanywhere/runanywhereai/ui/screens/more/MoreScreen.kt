package com.runanywhere.runanywhereai.ui.screens.more

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.rememberScrollState
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import com.runanywhere.runanywhereai.ui.navigation.Benchmarks
import com.runanywhere.runanywhereai.ui.navigation.CloudProviders
import com.runanywhere.runanywhereai.ui.navigation.Documents
import com.runanywhere.runanywhereai.ui.navigation.Settings
import com.runanywhere.runanywhereai.ui.navigation.Solutions
import com.runanywhere.runanywhereai.ui.navigation.Stt
import com.runanywhere.runanywhereai.ui.navigation.Tools
import com.runanywhere.runanywhereai.ui.navigation.Tts
import com.runanywhere.runanywhereai.ui.navigation.Vad
import com.runanywhere.runanywhereai.ui.navigation.Vision
import com.runanywhere.runanywhereai.ui.theme.LocalDimens
import com.runanywhere.runanywhereai.ui.theme.icons.RACIcons

private data class MoreEntry(
    val label: String,
    val description: String,
    val icon: ImageVector,
    val route: Any? = null,
)

@Composable
fun MoreScreen(onNavigate: (Any) -> Unit) {
    val dimens = LocalDimens.current
    val entries = listOf(
        MoreEntry("Settings", "Generation and storage", RACIcons.Outline.Settings, Settings),
        MoreEntry("Tool Calling", "Let the LLM use registered tools", RACIcons.Outline.Tool, Tools),
        MoreEntry("Text to Speech", "Read text aloud", RACIcons.Outline.Robot, Tts),
        MoreEntry("Speech to Text", "Transcribe audio on-device", RACIcons.Outline.Microphone, Stt),
        MoreEntry("Voice Detection", "Detect speech activity in real-time", RACIcons.Outline.Activity, Vad),
        MoreEntry("Vision", "Describe images with a VLM", RACIcons.Outline.Eye, Vision),
        MoreEntry("Documents", "Chat with your files (RAG)", RACIcons.Outline.Database, Documents),
        MoreEntry("Solutions", "Run prepackaged pipelines from YAML", RACIcons.Outline.Stack, Solutions),
        MoreEntry("Cloud providers", "Register cloud STT backends", RACIcons.Outline.Cloud, CloudProviders),
        MoreEntry("Benchmarks", "Measure model performance", RACIcons.Outline.Cpu, Benchmarks),
    )

    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(dimens.screenPadding),
        verticalArrangement = Arrangement.spacedBy(dimens.spacingSm),
    ) {
        entries.forEach { entry -> MoreRow(entry) { entry.route?.let(onNavigate) } }
    }
}

@Composable
private fun MoreRow(entry: MoreEntry, onClick: () -> Unit) {
    val dimens = LocalDimens.current
    val enabled = entry.route != null
    val contentColor =
        if (enabled) MaterialTheme.colorScheme.onSurface else MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f)

    Surface(
        color = MaterialTheme.colorScheme.surfaceContainerHigh,
        shape = RoundedCornerShape(dimens.radiusLg),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Row(
            modifier = Modifier
                .clip(RoundedCornerShape(dimens.radiusLg))
                .then(if (enabled) Modifier.clickable(onClick = onClick) else Modifier)
                .padding(dimens.spacingLg),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(dimens.spacingMd),
        ) {
            Icon(
                imageVector = entry.icon,
                contentDescription = null,
                tint = if (enabled) MaterialTheme.colorScheme.primary else contentColor,
                modifier = Modifier.size(dimens.iconMd),
            )
            Column(modifier = Modifier.weight(1f)) {
                Text(entry.label, style = MaterialTheme.typography.bodyLarge, color = contentColor)
                Text(
                    entry.description,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = if (enabled) 1f else 0.5f),
                )
            }
            if (enabled) {
                Icon(
                    imageVector = RACIcons.Outline.ChevronRight,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.size(dimens.iconSm),
                )
            } else {
                Text(
                    text = "Soon",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f),
                )
            }
        }
    }
}
