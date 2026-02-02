package com.runanywhere.runanywhereai.presentation.common

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.tween
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Psychology
import androidx.compose.material.icons.outlined.Warning
import androidx.compose.material3.Button
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.scale
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.runanywhere.runanywhereai.ui.theme.AppColors

/**
 * Loading view shown during SDK initialization.
 * Matches iOS InitializationLoadingView exactly.
 *
 * iOS Reference: RunAnywhereAIApp.swift - InitializationLoadingView
 * - Brain icon with pulsing animation (1.0 to 1.2 scale)
 * - "Initializing RunAnywhere AI" title
 * - "Setting up AI models and services..." subtitle
 * - Circular progress indicator
 */
@Composable
fun InitializationLoadingView() {
    // Pulsing animation state matching iOS pattern
    var isAnimating by remember { mutableStateOf(false) }
    val scale by animateFloatAsState(
        targetValue = if (isAnimating) 1.2f else 1.0f,
        animationSpec =
            infiniteRepeatable(
                animation = tween(durationMillis = 1000),
            ),
        label = "brain_pulse",
    )

    LaunchedEffect(Unit) {
        isAnimating = true
    }

    Surface(
        modifier = Modifier.fillMaxSize(),
        color = MaterialTheme.colorScheme.background,
    ) {
        Column(
            modifier =
                Modifier
                    .fillMaxSize()
                    .padding(40.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center,
        ) {
            // Brain icon with pulsing animation - matches iOS Image(systemName: "brain")
            Icon(
                imageVector = Icons.Outlined.Psychology,
                contentDescription = "AI Brain",
                modifier = Modifier.scale(scale),
                tint = AppColors.primaryAccent,
            )

            Spacer(modifier = Modifier.height(24.dp))

            // Title - matches iOS Text("Initializing RunAnywhere AI")
            Text(
                text = "Initializing RunAnywhere AI",
                style = MaterialTheme.typography.titleLarge,
                color = MaterialTheme.colorScheme.onBackground,
            )

            Spacer(modifier = Modifier.height(8.dp))

            // Subtitle - matches iOS Text("Setting up AI models and services...")
            Text(
                text = "Setting up AI models and services...",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )

            Spacer(modifier = Modifier.height(24.dp))

            // Progress indicator - matches iOS ProgressView()
            CircularProgressIndicator(
                color = AppColors.primaryAccent,
            )
        }
    }
}

/**
 * Error view shown when SDK initialization fails.
 * Matches iOS InitializationErrorView exactly.
 *
 * iOS Reference: RunAnywhereAIApp.swift - InitializationErrorView
 * - Warning triangle icon (orange)
 * - "Initialization Failed" title
 * - Error description
 * - Retry button
 */
@Composable
fun InitializationErrorView(
    error: Throwable,
    onRetry: () -> Unit,
) {
    Surface(
        modifier = Modifier.fillMaxSize(),
        color = MaterialTheme.colorScheme.background,
    ) {
        Column(
            modifier =
                Modifier
                    .fillMaxSize()
                    .padding(40.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalArrangement = Arrangement.Center,
        ) {
            // Warning icon - matches iOS Image(systemName: "exclamationmark.triangle")
            Icon(
                imageVector = Icons.Outlined.Warning,
                contentDescription = "Error",
                tint = AppColors.warningOrange,
            )

            Spacer(modifier = Modifier.height(24.dp))

            // Title - matches iOS Text("Initialization Failed")
            Text(
                text = "Initialization Failed",
                style = MaterialTheme.typography.titleLarge,
                color = MaterialTheme.colorScheme.onBackground,
            )

            Spacer(modifier = Modifier.height(8.dp))

            // Error description - matches iOS Text(error.localizedDescription)
            Text(
                text = error.localizedMessage ?: error.message ?: "Unknown error",
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                textAlign = TextAlign.Center,
            )

            Spacer(modifier = Modifier.height(24.dp))

            // Retry button - matches iOS Button("Retry") { retryAction() }
            Button(onClick = onRetry) {
                Text("Retry")
            }
        }
    }
}
