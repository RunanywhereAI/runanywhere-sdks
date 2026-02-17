package com.runanywhere.runanywhereai.presentation.vision

import android.util.Log
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
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.material3.TopAppBar
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/**
 * Vision Hub Screen — Matches iOS VisionHubView exactly.
 *
 * Lists vision-related features:
 * 1. Vision Chat (VLM) — Chat with images using photos
 * 2. Image Generation — Create images from text prompts (placeholder for future)
 *
 * iOS Reference: examples/ios/RunAnywhereAI/.../App/ContentView.swift — VisionHubView
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun VisionHubScreen(
    onNavigateToVLM: () -> Unit,
    onNavigateToImageGeneration: () -> Unit = {},
) {
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Vision") },
            )
        },
    ) { paddingValues ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(paddingValues)
                .padding(horizontal = 16.dp, vertical = 8.dp),
        ) {
            // Section header
            Text(
                "Vision AI",
                style = MaterialTheme.typography.titleSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(start = 4.dp, bottom = 8.dp),
            )

            // Vision Chat (VLM)
            FeatureCard(
                icon = Icons.Filled.CameraAlt,
                iconColor = Color(0xFF9C27B0), // Purple
                title = "Vision Chat",
                subtitle = "Chat with images using your camera or photos",
                onClick = onNavigateToVLM,
            )

            Spacer(modifier = Modifier.height(8.dp))

            // Image Generation (placeholder for future diffusion model support)
            FeatureCard(
                icon = Icons.Filled.PhotoLibrary,
                iconColor = Color(0xFFE91E63), // Pink
                title = "Image Generation",
                subtitle = "Create images from text prompts",
                onClick = onNavigateToImageGeneration,
            )

            Spacer(modifier = Modifier.height(16.dp))

            // Footer
            Text(
                "Understand and create visual content with AI",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(start = 4.dp),
            )
        }
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
            .clickable {
                Log.d("VisionHub", "FeatureCard clicked: $title")
                onClick()
            },
        shape = RoundedCornerShape(12.dp),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceVariant,
        ),
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(16.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(
                imageVector = icon,
                contentDescription = null,
                tint = iconColor,
                modifier = Modifier.size(32.dp),
            )
            Spacer(modifier = Modifier.width(16.dp))
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    title,
                    fontWeight = FontWeight.Medium,
                    fontSize = 16.sp,
                )
                Text(
                    subtitle,
                    fontSize = 13.sp,
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
