package com.runanywhere.runanywhereai.presentation.benchmarks.views

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.runanywhere.runanywhereai.ui.theme.AppColors
import com.runanywhere.runanywhereai.ui.theme.AppSpacing

/**
 * Progress overlay shown while benchmarks are running.
 * Matches iOS BenchmarkProgressView exactly.
 */
@Composable
fun BenchmarkProgressDialog(
    progress: Float,
    currentScenario: String,
    currentModel: String,
    completedCount: Int,
    totalCount: Int,
    onCancel: () -> Unit,
) {
    Dialog(
        onDismissRequest = { /* Non-dismissible */ },
        properties = DialogProperties(dismissOnBackPress = false, dismissOnClickOutside = false),
    ) {
        Column(
            modifier = Modifier
                .widthIn(max = 320.dp)
                .shadow(8.dp, RoundedCornerShape(AppSpacing.cornerRadiusMedium))
                .clip(RoundedCornerShape(AppSpacing.cornerRadiusMedium))
                .background(MaterialTheme.colorScheme.surface)
                .padding(AppSpacing.xxLarge),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text(
                text = "Running Benchmarks",
                style = MaterialTheme.typography.headlineSmall,
            )

            Spacer(modifier = Modifier.height(AppSpacing.xxLarge))

            LinearProgressIndicator(
                progress = { progress },
                modifier = Modifier.fillMaxWidth(),
                color = AppColors.primaryAccent,
                trackColor = AppColors.primaryAccent.copy(alpha = 0.12f),
            )

            Spacer(modifier = Modifier.height(AppSpacing.xxLarge))

            Text(
                text = currentScenario,
                style = MaterialTheme.typography.bodyMedium,
                textAlign = TextAlign.Center,
            )

            if (currentModel.isNotEmpty()) {
                Spacer(modifier = Modifier.height(AppSpacing.xSmall))
                Text(
                    text = currentModel,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    textAlign = TextAlign.Center,
                )
            }

            Spacer(modifier = Modifier.height(AppSpacing.small))

            Text(
                text = "$completedCount / $totalCount",
                style = MaterialTheme.typography.bodySmall.copy(fontFamily = FontFamily.Monospace),
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )

            Spacer(modifier = Modifier.height(AppSpacing.xxLarge))

            OutlinedButton(
                onClick = onCancel,
                colors = ButtonDefaults.outlinedButtonColors(contentColor = AppColors.statusRed),
            ) {
                Text("Cancel")
            }
        }
    }
}
