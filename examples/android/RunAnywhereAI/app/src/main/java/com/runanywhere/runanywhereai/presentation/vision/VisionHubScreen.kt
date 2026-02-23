package com.runanywhere.runanywhereai.presentation.vision

import androidx.compose.foundation.clickable
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
import androidx.compose.material.icons.filled.CameraAlt
import androidx.compose.material.icons.filled.PhotoLibrary
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
 * Vision Hub Screen — Matches iOS VisionHubView exactly.
 *
 * Lists vision-related features:
 * 1. Vision Chat (VLM) — Chat with images using photos
 * 2. Image Generation — Create images from text prompts (placeholder for future)
 *
 * iOS Reference: examples/ios/RunAnywhereAI/.../App/ContentView.swift — VisionHubView
 */
@Composable
fun VisionHubScreen(
    onNavigateToVLM: () -> Unit,
    onNavigateToImageGeneration: () -> Unit = {},
) {
    ConfigureTopBar(title = "Vision")

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = Dimensions.large, vertical = Dimensions.smallMedium),
    ) {
            // Section header
            Text(
                "Vision AI",
                style = MaterialTheme.typography.titleSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(start = Dimensions.xSmall, bottom = Dimensions.smallMedium),
            )

            // Vision Chat (VLM)
            FeatureCard(
                icon = Icons.Filled.CameraAlt,
                iconColor = AppColors.featureCamera,
                title = "Vision Chat",
                subtitle = "Chat with images using your camera or photos",
                onClick = onNavigateToVLM,
            )

            Spacer(modifier = Modifier.height(Dimensions.smallMedium))

            // Image Generation (placeholder for future diffusion model support)
            FeatureCard(
                icon = Icons.Filled.PhotoLibrary,
                iconColor = AppColors.featurePink,
                title = "Image Generation",
                subtitle = "Create images from text prompts",
                onClick = onNavigateToImageGeneration,
            )

            Spacer(modifier = Modifier.height(Dimensions.large))

            // Footer
            Text(
                "Understand and create visual content with AI",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(start = Dimensions.xSmall),
            )
    }
}

/**
 * Feature row card — Matches iOS FeatureRow styling.
 */
@Composable
private fun FeatureCard(
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
