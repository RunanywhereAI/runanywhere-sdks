package com.runanywhere.runanywhereai.presentation.navigation

import androidx.compose.foundation.clickable
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.filled.KeyboardArrowRight
import androidx.compose.material.icons.filled.Description
import androidx.compose.material.icons.filled.GraphicEq
import androidx.compose.material.icons.filled.Speed
import androidx.compose.material.icons.filled.Tune
import androidx.compose.material.icons.automirrored.filled.VolumeUp
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp
import com.runanywhere.runanywhereai.presentation.components.ConfigureTopBar
import com.runanywhere.runanywhereai.ui.theme.AppColors
import com.runanywhere.runanywhereai.ui.theme.Dimensions

/**
 * More Hub Screen — matches iOS MoreHubView.
 * Contains additional utility features: STT, TTS, RAG.
 */
@Composable
fun MoreHubScreen(
    onNavigateToSTT: () -> Unit,
    onNavigateToTTS: () -> Unit,
    onNavigateToRAG: () -> Unit,
    onNavigateToBenchmarks: () -> Unit,
    onNavigateToLoraManager: () -> Unit = {},
) {
    ConfigureTopBar(title = "More")

    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = Dimensions.large, vertical = Dimensions.smallMedium),
    ) {
            // Audio AI section
            Text(
                "Audio AI",
                style = MaterialTheme.typography.titleSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(start = Dimensions.xSmall, bottom = Dimensions.smallMedium),
            )

            MoreFeatureCard(
                icon = Icons.Filled.GraphicEq,
                iconColor = AppColors.featureBlue,
                title = "Speech to Text",
                subtitle = "Transcribe audio to text using on-device models",
                onClick = onNavigateToSTT,
            )

            Spacer(modifier = Modifier.height(Dimensions.smallMedium))

            MoreFeatureCard(
                icon = Icons.AutoMirrored.Filled.VolumeUp,
                iconColor = AppColors.featureGreen,
                title = "Text to Speech",
                subtitle = "Convert text to natural-sounding speech",
                onClick = onNavigateToTTS,
            )

            Spacer(modifier = Modifier.height(Dimensions.xxLarge))

            // Document AI section
            Text(
                "Document AI",
                style = MaterialTheme.typography.titleSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(start = Dimensions.xSmall, bottom = Dimensions.smallMedium),
            )

            MoreFeatureCard(
                icon = Icons.Filled.Description,
                iconColor = AppColors.featureDeepPurple,
                title = "Document Q&A",
                subtitle = "Ask questions about your documents using on-device AI",
                onClick = onNavigateToRAG,
            )

            Spacer(modifier = Modifier.height(Dimensions.xxLarge))

            // Model Customization section
            Text(
                "Model Customization",
                style = MaterialTheme.typography.titleSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(start = Dimensions.xSmall, bottom = Dimensions.smallMedium),
            )

            MoreFeatureCard(
                icon = Icons.Filled.Tune,
                iconColor = AppColors.primaryPurple,
                title = "LoRA Adapters",
                subtitle = "Manage and apply LoRA fine-tuning adapters to models",
                onClick = onNavigateToLoraManager,
            )

            Spacer(modifier = Modifier.height(Dimensions.xxLarge))

            // Performance section
            Text(
                "Performance",
                style = MaterialTheme.typography.titleSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(start = Dimensions.xSmall, bottom = Dimensions.smallMedium),
            )

            MoreFeatureCard(
                icon = Icons.Filled.Speed,
                iconColor = AppColors.primaryAccent,
                title = "Benchmarks",
                subtitle = "Measure on-device AI performance across models",
                onClick = onNavigateToBenchmarks,
            )

            Spacer(modifier = Modifier.height(Dimensions.large))

            // Footer
            Text(
                "Additional AI utilities and tools",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(start = Dimensions.xSmall),
            )
    }
}

@Composable
private fun MoreFeatureCard(
    icon: ImageVector,
    iconColor: Color,
    title: String,
    subtitle: String,
    onClick: () -> Unit,
) {
    Card(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick),
        shape = RoundedCornerShape(Dimensions.cornerRadiusXLarge),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceVariant,
        ),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(Dimensions.large),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(
                imageVector = icon,
                contentDescription = null,
                tint = iconColor,
                modifier = Modifier.size(32.dp),
            )
            Spacer(modifier = Modifier.width(Dimensions.large))
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    title,
                    style = MaterialTheme.typography.bodyLarge,
                )
                Text(
                    subtitle,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            Icon(
                imageVector = Icons.AutoMirrored.Filled.KeyboardArrowRight,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}
