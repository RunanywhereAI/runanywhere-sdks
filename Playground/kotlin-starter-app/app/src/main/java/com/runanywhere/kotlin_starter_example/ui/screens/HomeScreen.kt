package com.runanywhere.kotlin_starter_example.ui.screens

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.grid.GridCells
import androidx.compose.foundation.lazy.grid.LazyVerticalGrid
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import com.runanywhere.kotlin_starter_example.ui.components.FeatureCard
import com.runanywhere.kotlin_starter_example.ui.theme.*

@Composable
fun HomeScreen(
    onNavigateToChat: () -> Unit,
    onNavigateToSTT: () -> Unit,
    onNavigateToTTS: () -> Unit,
    onNavigateToVoicePipeline: () -> Unit,
    modifier: Modifier = Modifier
) {
    Box(
        modifier = modifier
            .fillMaxSize()
            .background(
                brush = Brush.linearGradient(
                    colors = listOf(
                        PrimaryDark,
                        Color(0xFF0F1629),
                        PrimaryMid
                    )
                )
            )
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(24.dp)
        ) {
            Spacer(modifier = Modifier.height(20.dp))
            
            // Header
            Header()
            
            Spacer(modifier = Modifier.height(40.dp))
            
            // Privacy info
            PrivacyInfoCard()
            
            Spacer(modifier = Modifier.height(32.dp))
            
            // Feature grid
            LazyVerticalGrid(
                columns = GridCells.Fixed(2),
                horizontalArrangement = Arrangement.spacedBy(16.dp),
                verticalArrangement = Arrangement.spacedBy(16.dp),
                modifier = Modifier.height(700.dp)
            ) {
                item {
                    FeatureCard(
                        title = "Chat",
                        subtitle = "LLM Text Generation",
                        icon = Icons.Rounded.Chat,
                        gradientColors = listOf(AccentCyan, Color(0xFF0EA5E9)),
                        onClick = onNavigateToChat
                    )
                }
                
                item {
                    FeatureCard(
                        title = "Speech",
                        subtitle = "Speech to Text",
                        icon = Icons.Rounded.Mic,
                        gradientColors = listOf(AccentViolet, Color(0xFF7C3AED)),
                        onClick = onNavigateToSTT
                    )
                }
                
                item {
                    FeatureCard(
                        title = "Voice",
                        subtitle = "Text to Speech",
                        icon = Icons.Rounded.VolumeUp,
                        gradientColors = listOf(AccentPink, Color(0xFFDB2777)),
                        onClick = onNavigateToTTS
                    )
                }
                
                item {
                    FeatureCard(
                        title = "Pipeline",
                        subtitle = "Voice Agent",
                        icon = Icons.Rounded.AutoAwesome,
                        gradientColors = listOf(AccentGreen, Color(0xFF059669)),
                        onClick = onNavigateToVoicePipeline
                    )
                }
            }
            
            Spacer(modifier = Modifier.height(32.dp))
            
            // Model info
            ModelInfoSection()
            
            Spacer(modifier = Modifier.height(24.dp))
        }
    }
}

@Composable
private fun Header() {
    Row(
        verticalAlignment = Alignment.CenterVertically
    ) {
        // Icon
        Box(
            modifier = Modifier
                .size(56.dp)
                .clip(RoundedCornerShape(16.dp))
                .background(
                    brush = Brush.linearGradient(
                        colors = listOf(AccentCyan, AccentViolet)
                    )
                ),
            contentAlignment = Alignment.Center
        ) {
            Icon(
                imageVector = Icons.Rounded.Bolt,
                contentDescription = null,
                tint = Color.White,
                modifier = Modifier.size(32.dp)
            )
        }
        
        Spacer(modifier = Modifier.width(16.dp))
        
        // Title
        Column {
            Text(
                text = "RunAnywhere",
                style = MaterialTheme.typography.headlineLarge,
                color = TextPrimary
            )
            Text(
                text = "Kotlin SDK Starter",
                style = MaterialTheme.typography.bodyMedium,
                color = AccentCyan
            )
        }
    }
}

@Composable
private fun PrivacyInfoCard() {
    Card(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(16.dp),
        colors = CardDefaults.cardColors(
            containerColor = SurfaceCard.copy(alpha = 0.6f)
        )
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(20.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Icon(
                imageVector = Icons.Rounded.PrivacyTip,
                contentDescription = null,
                tint = AccentCyan.copy(alpha = 0.8f),
                modifier = Modifier.size(28.dp)
            )
            
            Spacer(modifier = Modifier.width(16.dp))
            
            Column {
                Text(
                    text = "Privacy-First On-Device AI",
                    style = MaterialTheme.typography.titleMedium,
                    color = TextPrimary
                )
                Spacer(modifier = Modifier.height(4.dp))
                Text(
                    text = "All AI processing happens locally on your device. No data ever leaves your phone.",
                    style = MaterialTheme.typography.bodySmall,
                    color = TextMuted
                )
            }
        }
    }
}

@Composable
private fun ModelInfoSection() {
    Card(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(16.dp),
        colors = CardDefaults.cardColors(
            containerColor = SurfaceCard.copy(alpha = 0.5f)
        )
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(20.dp)
        ) {
            ModelInfoRow(
                icon = Icons.Rounded.Memory,
                title = "LLM",
                value = "SmolLM2 360M"
            )
            Spacer(modifier = Modifier.height(12.dp))
            ModelInfoRow(
                icon = Icons.Rounded.Hearing,
                title = "STT",
                value = "Whisper Tiny"
            )
            Spacer(modifier = Modifier.height(12.dp))
            ModelInfoRow(
                icon = Icons.Rounded.RecordVoiceOver,
                title = "TTS",
                value = "Piper Lessac"
            )
        }
    }
}

@Composable
private fun ModelInfoRow(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    title: String,
    value: String
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(
                imageVector = icon,
                contentDescription = null,
                tint = TextMuted,
                modifier = Modifier.size(20.dp)
            )
            Spacer(modifier = Modifier.width(12.dp))
            Text(
                text = title,
                style = MaterialTheme.typography.bodyMedium,
                color = TextPrimary
            )
        }
        
        Text(
            text = value,
            style = MaterialTheme.typography.bodySmall,
            color = AccentCyan
        )
    }
}
