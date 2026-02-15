package com.runanywhere.runanywhereai.presentation.chat.components

import androidx.compose.animation.core.*
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.runanywhere.runanywhereai.ui.theme.AppColors
import com.runanywhere.runanywhereai.ui.theme.Dimensions
import com.runanywhere.sdk.public.extensions.Models.ModelSelectionContext

/**
 * ModelRequiredOverlay - Displays when a model needs to be selected
 *
 * Ported from iOS ModelStatusComponents.swift
 *
 * Features:
 * - Animated floating circles background
 * - Modality-specific icon, color, and messaging
 * - "Get Started" CTA button
 * - Privacy note footer
 */
@Composable
fun ModelRequiredOverlay(
    modality: ModelSelectionContext = ModelSelectionContext.LLM,
    onSelectModel: () -> Unit,
    modifier: Modifier = Modifier,
) {
    // Animation for floating circles
    val infiniteTransition = rememberInfiniteTransition(label = "floatingCircles")

    val circle1Offset by infiniteTransition.animateFloat(
        initialValue = -100f,
        targetValue = 100f,
        animationSpec = infiniteRepeatable(
            animation = tween(durationMillis = 8000, easing = EaseInOut),
            repeatMode = RepeatMode.Reverse
        ),
        label = "circle1"
    )

    val circle2Offset by infiniteTransition.animateFloat(
        initialValue = 100f,
        targetValue = -100f,
        animationSpec = infiniteRepeatable(
            animation = tween(durationMillis = 8000, easing = EaseInOut),
            repeatMode = RepeatMode.Reverse
        ),
        label = "circle2"
    )

    val circle3Offset by infiniteTransition.animateFloat(
        initialValue = 0f,
        targetValue = 80f,
        animationSpec = infiniteRepeatable(
            animation = tween(durationMillis = 8000, easing = EaseInOut),
            repeatMode = RepeatMode.Reverse
        ),
        label = "circle3"
    )

    val modalityColor = getModalityColor(modality)
    val modalityIcon = getModalityIcon(modality)
    val modalityTitle = getModalityTitle(modality)
    val modalityDescription = getModalityDescription(modality)

    Box(
        modifier = modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.background)
    ) {
        // Animated floating circles background
        Box(modifier = Modifier.fillMaxSize()) {
            // Circle 1 - Top left
            Box(
                modifier = Modifier
                    .size(300.dp)
                    .offset(x = circle1Offset.dp, y = (-200).dp)
                    .blur(80.dp)
                    .clip(CircleShape)
                    .background(modalityColor.copy(alpha = 0.15f))
            )

            // Circle 2 - Bottom right
            Box(
                modifier = Modifier
                    .size(250.dp)
                    .offset(x = circle2Offset.dp, y = 300.dp)
                    .blur(100.dp)
                    .clip(CircleShape)
                    .background(modalityColor.copy(alpha = 0.12f))
            )

            // Circle 3 - Center
            Box(
                modifier = Modifier
                    .size(280.dp)
                    .offset(x = (-circle3Offset).dp, y = circle3Offset.dp)
                    .blur(90.dp)
                    .clip(CircleShape)
                    .background(modalityColor.copy(alpha = 0.08f))
            )
        }

        // Main content
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(horizontal = Dimensions.xLarge),
            horizontalAlignment = Alignment.CenterHorizontally
        ) {
            Spacer(modifier = Modifier.weight(1f))

            // Icon with gradient background
            Box(
                modifier = Modifier
                    .size(120.dp)
                    .clip(CircleShape)
                    .background(
                        Brush.linearGradient(
                            colors = listOf(
                                modalityColor.copy(alpha = 0.2f),
                                modalityColor.copy(alpha = 0.1f)
                            )
                        )
                    ),
                contentAlignment = Alignment.Center
            ) {
                Icon(
                    imageVector = modalityIcon,
                    contentDescription = null,
                    modifier = Modifier.size(48.dp),
                    tint = modalityColor
                )
            }

            Spacer(modifier = Modifier.height(Dimensions.xLarge))

            // Title
            Text(
                text = modalityTitle,
                style = MaterialTheme.typography.titleLarge,
                fontWeight = FontWeight.Bold,
                color = MaterialTheme.colorScheme.onBackground
            )

            Spacer(modifier = Modifier.height(Dimensions.medium))

            // Description
            Text(
                text = modalityDescription,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center,
                modifier = Modifier.padding(horizontal = 40.dp)
            )

            Spacer(modifier = Modifier.weight(1f))

            // Bottom section
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                modifier = Modifier.padding(bottom = Dimensions.large)
            ) {
                // CTA Button
                Button(
                    onClick = onSelectModel,
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(56.dp),
                    shape = RoundedCornerShape(16.dp),
                    colors = ButtonDefaults.buttonColors(
                        containerColor = modalityColor
                    )
                ) {
                    Icon(
                        imageVector = Icons.Default.AutoAwesome,
                        contentDescription = null,
                        modifier = Modifier.size(20.dp)
                    )
                    Spacer(modifier = Modifier.width(8.dp))
                    Text(
                        text = "Get Started",
                        style = MaterialTheme.typography.labelLarge,
                        fontWeight = FontWeight.SemiBold
                    )
                }

                Spacer(modifier = Modifier.height(Dimensions.medium))

                // Privacy note
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.Center
                ) {
                    Icon(
                        imageVector = Icons.Default.Shield,
                        contentDescription = null,
                        modifier = Modifier.size(14.dp),
                        tint = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                    Spacer(modifier = Modifier.width(6.dp))
                    Text(
                        text = "100% Private • Runs on your device",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
        }
    }
}

private fun getModalityIcon(modality: ModelSelectionContext): ImageVector {
    return when (modality) {
        ModelSelectionContext.LLM -> Icons.Default.AutoAwesome
        ModelSelectionContext.STT -> Icons.Default.GraphicEq
        ModelSelectionContext.TTS -> Icons.Default.VolumeUp
        ModelSelectionContext.VOICE -> Icons.Default.Mic
    }
}

private fun getModalityColor(modality: ModelSelectionContext): Color {
    return when (modality) {
        ModelSelectionContext.LLM -> AppColors.primaryAccent
        ModelSelectionContext.STT -> Color(0xFF4CAF50) // Green
        ModelSelectionContext.TTS -> AppColors.primaryPurple
        ModelSelectionContext.VOICE -> AppColors.primaryAccent
    }
}

private fun getModalityTitle(modality: ModelSelectionContext): String {
    return when (modality) {
        ModelSelectionContext.LLM -> "Welcome!"
        ModelSelectionContext.STT -> "Voice to Text"
        ModelSelectionContext.TTS -> "Read Aloud"
        ModelSelectionContext.VOICE -> "Voice Assistant"
    }
}

private fun getModalityDescription(modality: ModelSelectionContext): String {
    return when (modality) {
        ModelSelectionContext.LLM -> "Choose your AI assistant and start chatting. Everything runs privately on your device."
        ModelSelectionContext.STT -> "Transcribe your speech to text with powerful on-device voice recognition."
        ModelSelectionContext.TTS -> "Have any text read aloud with natural-sounding voices."
        ModelSelectionContext.VOICE -> "Talk naturally with your AI assistant. Let's set up the components together."
    }
}
