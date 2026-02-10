package com.runanywhere.runanywhereai.presentation.chat.components

import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
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
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.clip
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
    val modalityColor = getModalityColor(modality)
    val modalityIcon = getModalityIcon(modality)
    val modalityTitle = getModalityTitle(modality)
    val modalityDescription = getModalityDescription(modality)

    val infiniteTransition = rememberInfiniteTransition(label = "overlay_circles")
    val circle1Offset by infiniteTransition.animateFloat(
        initialValue = -100f,
        targetValue = 100f,
        animationSpec = infiniteRepeatable(
            animation = tween(durationMillis = 4000, easing = LinearEasing),
            repeatMode = RepeatMode.Reverse,
        ),
        label = "c1",
    )
    val circle2Offset by infiniteTransition.animateFloat(
        initialValue = 100f,
        targetValue = -100f,
        animationSpec = infiniteRepeatable(
            animation = tween(durationMillis = 4000, easing = LinearEasing),
            repeatMode = RepeatMode.Reverse,
        ),
        label = "c2",
    )
    val circle3Offset by infiniteTransition.animateFloat(
        initialValue = 0f,
        targetValue = 80f,
        animationSpec = infiniteRepeatable(
            animation = tween(durationMillis = 4000, easing = LinearEasing),
            repeatMode = RepeatMode.Reverse,
        ),
        label = "c3",
    )
    val density = LocalDensity.current
    val c1Dp = with(density) { circle1Offset.toDp() }
    val c2Dp = with(density) { circle2Offset.toDp() }
    val c3Dp = with(density) { circle3Offset.toDp() }

    Box(modifier = modifier.fillMaxSize()) {
        Box(modifier = Modifier.fillMaxSize().blur(32.dp)) {
            Box(
                modifier = Modifier
                    .size(300.dp)
                    .offset(x = c1Dp, y = (-200).dp)
                    .clip(CircleShape)
                    .background(modalityColor.copy(alpha = 0.15f)),
            )
            Box(
                modifier = Modifier
                    .size(250.dp)
                    .offset(x = c2Dp, y = 300.dp)
                    .clip(CircleShape)
                    .background(modalityColor.copy(alpha = 0.12f)),
            )
            Box(
                modifier = Modifier
                    .size(280.dp)
                    .offset(x = -c3Dp, y = c3Dp)
                    .clip(CircleShape)
                    .background(modalityColor.copy(alpha = 0.08f)),
            )
        }
        Column(
            modifier = Modifier.fillMaxSize().padding(horizontal = 20.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Spacer(modifier = Modifier.weight(1f))
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
            Button(
                onClick = onSelectModel,
                colors = ButtonDefaults.buttonColors(containerColor = modalityColor),
                modifier = Modifier.fillMaxWidth(),
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
    }
}

private fun getModalityColor(modality: ModelSelectionContext): Color {
    return when (modality) {
        ModelSelectionContext.LLM -> AppColors.primaryAccent
        ModelSelectionContext.STT -> AppColors.primaryGreen
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
