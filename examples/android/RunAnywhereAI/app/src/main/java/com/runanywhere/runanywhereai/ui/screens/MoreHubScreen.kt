package com.runanywhere.runanywhereai.ui.screens

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.runanywhere.runanywhereai.ui.components.RACard
import com.runanywhere.runanywhereai.ui.icons.RAIcons

@Composable
fun MoreHubScreen(
    onNavigateToStt: () -> Unit,
    onNavigateToTts: () -> Unit,
    onNavigateToRag: () -> Unit,
    onNavigateToLoraManager: () -> Unit,
    onNavigateToBenchmarks: () -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text(
            "Features",
            style = MaterialTheme.typography.titleSmall,
            fontWeight = FontWeight.SemiBold,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(bottom = 4.dp),
        )

        HubCard(
            icon = RAIcons.Mic,
            title = "Speech to Text",
            subtitle = "Transcribe audio with on-device models",
            onClick = onNavigateToStt,
        )

        HubCard(
            icon = RAIcons.Play,
            title = "Text to Speech",
            subtitle = "Generate speech from text on-device",
            onClick = onNavigateToTts,
        )

        HubCard(
            icon = RAIcons.FileText,
            title = "Document Q&A",
            subtitle = "Ask questions about your documents",
            onClick = onNavigateToRag,
        )

        HubCard(
            icon = RAIcons.Puzzle,
            title = "LoRA Adapters",
            subtitle = "Manage fine-tuned model adapters",
            onClick = onNavigateToLoraManager,
        )

        HubCard(
            icon = RAIcons.Gauge,
            title = "Benchmarks",
            subtitle = "Run performance benchmarks",
            onClick = onNavigateToBenchmarks,
        )
    }
}

@Composable
private fun HubCard(
    icon: ImageVector,
    title: String,
    subtitle: String,
    onClick: () -> Unit,
) {
    RACard(
        modifier = Modifier.clickable(onClick = onClick),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(
                imageVector = icon,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.primary,
                modifier = Modifier.size(24.dp),
            )
            Spacer(Modifier.width(14.dp))
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    title,
                    style = MaterialTheme.typography.bodyLarge,
                    fontWeight = FontWeight.Medium,
                )
                Text(
                    subtitle,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            Icon(
                imageVector = RAIcons.ChevronRight,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.5f),
                modifier = Modifier.size(20.dp),
            )
        }
    }
}
