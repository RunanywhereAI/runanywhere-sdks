package com.runanywhere.runanywhereai.ui.screens.intro

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Button
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextAlign
import com.runanywhere.runanywhereai.ui.theme.LocalDimens

@Composable
fun IntroScreen() {
    val dimens = LocalDimens.current
    Column(
        Modifier.fillMaxSize(),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Text("RunAnywhere AI", style = MaterialTheme.typography.displaySmall)
        Spacer(Modifier.height(dimens.spacingMd))
        LinearProgressIndicator()
    }
}

@Composable
fun InitErrorScreen(message: String, onRetry: () -> Unit) {
    val dimens = LocalDimens.current
    Column(
        Modifier
            .fillMaxSize()
            .padding(dimens.spacingXl),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Text("Initialization Failed", style = MaterialTheme.typography.headlineSmall)
        Spacer(Modifier.height(dimens.spacingMd))
        Text(
            message,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            textAlign = TextAlign.Center,
        )
        Spacer(Modifier.height(dimens.spacingXl))
        Button(onClick = onRetry) {
            Text("Retry")
        }
    }
}