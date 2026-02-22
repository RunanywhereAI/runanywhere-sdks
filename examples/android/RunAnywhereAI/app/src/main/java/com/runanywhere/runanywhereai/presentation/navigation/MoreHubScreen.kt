package com.runanywhere.runanywhereai.presentation.navigation

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
import androidx.compose.material.icons.filled.GraphicEq
import androidx.compose.material.icons.filled.Speed
import androidx.compose.material.icons.filled.VolumeUp
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
 * More Hub Screen — matches iOS MoreHubView.
 * Contains additional utility features: STT, TTS, etc.
 *
 * iOS Reference: examples/ios/RunAnywhereAI/.../App/ContentView.swift — MoreHubView
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun MoreHubScreen(
    onNavigateToSTT: () -> Unit,
    onNavigateToTTS: () -> Unit,
    onNavigateToBenchmarks: () -> Unit,
) {
    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("More") },
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
                "Audio AI",
                style = MaterialTheme.typography.titleSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(start = 4.dp, bottom = 8.dp),
            )

            // Speech to Text
            MoreFeatureCard(
                icon = Icons.Filled.GraphicEq,
                iconColor = Color(0xFF2196F3), // Blue
                title = "Speech to Text",
                subtitle = "Transcribe audio to text using on-device models",
                onClick = onNavigateToSTT,
            )

            Spacer(modifier = Modifier.height(8.dp))

            // Text to Speech
            MoreFeatureCard(
                icon = Icons.Filled.VolumeUp,
                iconColor = Color(0xFF4CAF50), // Green
                title = "Text to Speech",
                subtitle = "Convert text to natural-sounding speech",
                onClick = onNavigateToTTS,
            )

            Spacer(modifier = Modifier.height(16.dp))

            // Performance section
            Text(
                "Performance",
                style = MaterialTheme.typography.titleSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(start = 4.dp, bottom = 8.dp),
            )

            // Benchmarks
            MoreFeatureCard(
                icon = Icons.Filled.Speed,
                iconColor = Color(0xFFFF5500), // Brand orange
                title = "Benchmarks",
                subtitle = "Measure on-device AI performance across models",
                onClick = onNavigateToBenchmarks,
            )

            Spacer(modifier = Modifier.height(16.dp))

            // Footer
            Text(
                "Additional AI utilities and tools",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(start = 4.dp),
            )
        }
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
