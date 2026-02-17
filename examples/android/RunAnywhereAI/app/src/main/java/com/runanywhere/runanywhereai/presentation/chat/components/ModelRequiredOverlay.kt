package com.runanywhere.runanywhereai.presentation.chat.components

import androidx.compose.animation.core.EaseInOut
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.AutoAwesome
import androidx.compose.material.icons.filled.GraphicEq
import androidx.compose.material.icons.filled.Lock
import androidx.compose.material.icons.filled.Mic
import androidx.compose.material.icons.filled.VolumeUp
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.runanywhere.runanywhereai.ui.theme.AppColors
import com.runanywhere.sdk.public.extensions.Models.ModelSelectionContext

/**
 * ModelRequiredOverlay - Displays when a model needs to be selected
 *
 * Ported from iOS ModelStatusComponents.swift
 *
 * Features:
 * - Animated floating circles background (easeInOut, 8s duration — matches iOS)
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
    val modalityColor = getModalityColor(modality)
    val modalityIcon = getModalityIcon(modality)
    val modalityTitle = getModalityTitle(modality)
    val modalityDescription = getModalityDescription(modality)

    // iOS uses .easeInOut(duration: 8).repeatForever(autoreverses: true)
    val infiniteTransition = rememberInfiniteTransition(label = "overlay_circles")

    val circle1Offset by infiniteTransition.animateFloat(
        initialValue = -100f,
        targetValue = 100f,
        animationSpec = infiniteRepeatable(
            animation = tween(durationMillis = 8000, easing = EaseInOut),
            repeatMode = RepeatMode.Reverse,
        ),
        label = "c1",
    )
    val circle2Offset by infiniteTransition.animateFloat(
        initialValue = 100f,
        targetValue = -100f,
        animationSpec = infiniteRepeatable(
            animation = tween(durationMillis = 8000, easing = EaseInOut),
            repeatMode = RepeatMode.Reverse,
        ),
        label = "c2",
    )
    val circle3Offset by infiniteTransition.animateFloat(
        initialValue = 0f,
        targetValue = 80f,
        animationSpec = infiniteRepeatable(
            animation = tween(durationMillis = 8000, easing = EaseInOut),
            repeatMode = RepeatMode.Reverse,
        ),
        label = "c3",
    )

    val density = LocalDensity.current

    Box(modifier = modifier.fillMaxSize()) {
        // Animated floating circles background using Canvas + RadialGradient
        // RadialGradient reliably produces soft glow on all Android devices
        // unlike .blur() which fails on many devices
        Canvas(modifier = Modifier.fillMaxSize()) {
            val c1XPx = with(density) { circle1Offset.dp.toPx() }
            val c2XPx = with(density) { circle2Offset.dp.toPx() }
            val c3Px = with(density) { circle3Offset.dp.toPx() }

            // Circle 1 - Top left, iOS: 300pt size, blur 80
            // Total visual radius ≈ (300/2) + 80 = 230
            val c1Center = Offset(x = size.width * 0.25f + c1XPx, y = -size.height * 0.05f)
            val c1Radius = with(density) { 230.dp.toPx() }
            drawCircle(
                brush = Brush.radialGradient(
                    colors = listOf(
                        modalityColor.copy(alpha = 0.10f),
                        modalityColor.copy(alpha = 0.04f),
                        Color.Transparent,
                    ),
                    center = c1Center,
                    radius = c1Radius,
                ),
                radius = c1Radius,
                center = c1Center,
            )

            // Circle 2 - Bottom right, iOS: 250pt size, blur 100
            // Total visual radius ≈ (250/2) + 100 = 225
            val c2Center = Offset(x = size.width * 0.7f + c2XPx, y = size.height * 0.75f)
            val c2Radius = with(density) { 225.dp.toPx() }
            drawCircle(
                brush = Brush.radialGradient(
                    colors = listOf(
                        modalityColor.copy(alpha = 0.08f),
                        modalityColor.copy(alpha = 0.03f),
                        Color.Transparent,
                    ),
                    center = c2Center,
                    radius = c2Radius,
                ),
                radius = c2Radius,
                center = c2Center,
            )

            // Circle 3 - Center, iOS: 280pt size, blur 90
            // Total visual radius ≈ (280/2) + 90 = 230
            val c3Center = Offset(x = size.width * 0.4f - c3Px, y = size.height * 0.5f + c3Px)
            val c3Radius = with(density) { 230.dp.toPx() }
            drawCircle(
                brush = Brush.radialGradient(
                    colors = listOf(
                        modalityColor.copy(alpha = 0.06f),
                        modalityColor.copy(alpha = 0.02f),
                        Color.Transparent,
                    ),
                    center = c3Center,
                    radius = c3Radius,
                ),
                radius = c3Radius,
                center = c3Center,
            )
        }

        Column(
            modifier = Modifier.fillMaxSize().padding(horizontal = 20.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Spacer(modifier = Modifier.weight(1f))

            // Friendly icon with gradient background
            Box(
                contentAlignment = Alignment.Center,
                modifier = Modifier
                    .size(120.dp)
                    .clip(CircleShape)
                    .background(
                        Brush.linearGradient(
                            listOf(
                                modalityColor.copy(alpha = 0.2f),
                                modalityColor.copy(alpha = 0.1f),
                            ),
                        ),
                    ),
            ) {
                Icon(
                    imageVector = modalityIcon,
                    contentDescription = null,
                    modifier = Modifier.size(48.dp),
                    tint = modalityColor,
                )
            }

            Spacer(modifier = Modifier.height(20.dp))

            Text(
                text = modalityTitle,
                style = MaterialTheme.typography.titleLarge,
            )

            Spacer(modifier = Modifier.height(12.dp))

            Text(
                text = modalityDescription,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center,
            )

            Spacer(modifier = Modifier.weight(1f))

            // Glass effect CTA button (matches iOS .thinMaterial + glassEffect)
            Button(
                onClick = onSelectModel,
                colors = ButtonDefaults.buttonColors(containerColor = modalityColor),
                modifier = Modifier.fillMaxWidth().heightIn(45.dp),
            ) {
                Icon(Icons.Default.AutoAwesome, contentDescription = null, modifier = Modifier.size(20.dp), tint = Color.White)
                Spacer(modifier = Modifier.width(8.dp))
                Text("Get Started", style = MaterialTheme.typography.titleMedium, color = Color.White)
            }

            Spacer(modifier = Modifier.height(16.dp))

            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.Center,
                modifier = Modifier.padding(bottom = 16.dp),
            ) {
                Icon(Icons.Default.Lock, contentDescription = null, modifier = Modifier.size(14.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
                Spacer(modifier = Modifier.width(6.dp))
                Text(
                    text = "100% Private • Runs on your device",
                    style = MaterialTheme.typography.labelMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
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
        ModelSelectionContext.VLM -> Icons.Default.Visibility
    }
}

private fun getModalityColor(modality: ModelSelectionContext): Color {
    return when (modality) {
        ModelSelectionContext.LLM -> AppColors.primaryAccent
        ModelSelectionContext.STT -> AppColors.primaryGreen
        ModelSelectionContext.TTS -> AppColors.primaryPurple
        ModelSelectionContext.VOICE -> AppColors.primaryAccent
        ModelSelectionContext.VLM -> AppColors.primaryPurple
    }
}

private fun getModalityTitle(modality: ModelSelectionContext): String {
    return when (modality) {
        ModelSelectionContext.LLM -> "Welcome!"
        ModelSelectionContext.STT -> "Voice to Text"
        ModelSelectionContext.TTS -> "Read Aloud"
        ModelSelectionContext.VOICE -> "Voice Assistant"
        ModelSelectionContext.VLM -> "Vision Chat"
    }
}

private fun getModalityDescription(modality: ModelSelectionContext): String {
    return when (modality) {
        ModelSelectionContext.LLM -> "Choose your AI assistant and start chatting. Everything runs privately on your device."
        ModelSelectionContext.STT -> "Transcribe your speech to text with powerful on-device voice recognition."
        ModelSelectionContext.TTS -> "Have any text read aloud with natural-sounding voices."
        ModelSelectionContext.VOICE -> "Talk naturally with your AI assistant. Let's set up the components together."
        ModelSelectionContext.VLM -> "Chat with images using your device's camera or photo library."
    }
}
