package com.runanywhere.runanywhereai.presentation.chat.components

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.Spring
import androidx.compose.animation.core.spring
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.runanywhere.runanywhereai.ui.theme.AppColors
import com.runanywhere.runanywhereai.ui.theme.AppTypography
import kotlinx.coroutines.delay

/**
 * Model Loaded Toast - matches iOS ModelLoadedToast.swift
 *
 * Shows a brief notification when a model finishes loading.
 * - Green checkmark + "Model Ready" + model name
 * - Slides in from top with spring animation
 * - Auto-dismisses after 3 seconds
 */
@Composable
fun ModelLoadedToast(
    modelName: String,
    isVisible: Boolean,
    onDismiss: () -> Unit,
    modifier: Modifier = Modifier,
) {
    // Auto-dismiss after 3 seconds
    LaunchedEffect(isVisible) {
        if (isVisible) {
            delay(3000)
            onDismiss()
        }
    }

    Box(
        modifier = modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 8.dp),
        contentAlignment = Alignment.TopCenter,
    ) {
        AnimatedVisibility(
            visible = isVisible,
            enter = slideInVertically(
                initialOffsetY = { -it },
                animationSpec = spring(
                    dampingRatio = Spring.DampingRatioMediumBouncy,
                    stiffness = Spring.StiffnessLow,
                ),
            ) + fadeIn(),
            exit = slideOutVertically(
                targetOffsetY = { -it },
            ) + fadeOut(),
        ) {
            ToastContent(modelName = modelName)
        }
    }
}

@Composable
private fun ToastContent(modelName: String) {
    val shape = RoundedCornerShape(16.dp)

    Row(
        modifier = Modifier
            .shadow(
                elevation = 16.dp,
                shape = shape,
                ambientColor = AppColors.shadowMedium,
                spotColor = AppColors.shadowMedium,
            )
            .background(
                color = MaterialTheme.colorScheme.surface,
                shape = shape,
            )
            .border(
                width = 0.5.dp,
                color = MaterialTheme.colorScheme.outline.copy(alpha = 0.2f),
                shape = shape,
            )
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.Start,
    ) {
        Icon(
            imageVector = Icons.Filled.CheckCircle,
            contentDescription = "Model Ready",
            modifier = Modifier.size(20.dp),
            tint = AppColors.primaryGreen,
        )

        Spacer(modifier = Modifier.width(12.dp))

        Column {
            Text(
                text = "Model Ready",
                style = AppTypography.caption.copy(fontWeight = FontWeight.SemiBold),
                color = MaterialTheme.colorScheme.onSurface,
            )
            Text(
                text = "'$modelName' is loaded",
                style = AppTypography.caption2,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}
