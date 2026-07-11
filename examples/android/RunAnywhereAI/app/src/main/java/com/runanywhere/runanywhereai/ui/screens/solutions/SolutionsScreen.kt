package com.runanywhere.runanywhereai.ui.screens.solutions

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.lifecycle.viewmodel.compose.viewModel
import com.runanywhere.runanywhereai.ui.theme.LocalDimens
import com.runanywhere.runanywhereai.ui.theme.RACTextStyles
import com.runanywhere.runanywhereai.ui.theme.icons.RACIcons
import com.runanywhere.runanywhereai.util.readableWidth

@Composable
fun SolutionsScreen(viewModel: SolutionsViewModel = viewModel()) {
    val dimens = LocalDimens.current

    Column(
        modifier = Modifier
            .fillMaxSize()
            .readableWidth()
            .padding(dimens.screenPadding),
        verticalArrangement = Arrangement.spacedBy(dimens.spacingLg),
    ) {
        Text(
            text = "Run a prepackaged pipeline (voice agent or RAG) " +
                "by handing a YAML config to RunAnywhere.solutions.run.",
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )

        Row(horizontalArrangement = Arrangement.spacedBy(dimens.spacingMd)) {
            RunButton(
                label = "Voice Agent",
                icon = RACIcons.Outline.Microphone,
                enabled = !viewModel.isRunning && viewModel.voiceReady,
                modifier = Modifier.weight(1f),
                onClick = viewModel::runVoiceSolution,
            )
            RunButton(
                label = "RAG",
                icon = RACIcons.Outline.FileText,
                enabled = !viewModel.isRunning && viewModel.ragReady,
                modifier = Modifier.weight(1f),
                onClick = viewModel::runRagSolution,
            )
        }

        if (viewModel.isCheckingModels || !viewModel.voiceReady || !viewModel.ragReady) {
            Surface(
                color = MaterialTheme.colorScheme.surfaceContainerHigh,
                shape = RoundedCornerShape(dimens.radiusLg),
                modifier = Modifier.fillMaxWidth(),
            ) {
                Column(
                    modifier = Modifier.padding(dimens.spacingMd),
                    verticalArrangement = Arrangement.spacedBy(dimens.spacingXs),
                ) {
                    if (viewModel.isCheckingModels) {
                        Text("Checking downloaded models…")
                    } else {
                        Text("Download the required models before running a solution.")
                        if (!viewModel.voiceReady) {
                            Text(
                                "Voice Agent: ${viewModel.missingVoiceModels.joinToString()}",
                                style = RACTextStyles.CodeSmall,
                            )
                        }
                        if (!viewModel.ragReady) {
                            Text(
                                "RAG: ${viewModel.missingRagModels.joinToString()}",
                                style = RACTextStyles.CodeSmall,
                            )
                        }
                    }
                    TextButton(
                        onClick = viewModel::refreshRequirements,
                        enabled = !viewModel.isCheckingModels,
                    ) {
                        Text(if (viewModel.isCheckingModels) "Checking…" else "Refresh")
                    }
                }
            }
        }

        LogCard(lines = viewModel.log, modifier = Modifier.weight(1f))
    }
}

@Composable
private fun RunButton(
    label: String,
    icon: ImageVector,
    enabled: Boolean,
    modifier: Modifier = Modifier,
    onClick: () -> Unit,
) {
    val dimens = LocalDimens.current
    Button(onClick = onClick, enabled = enabled, modifier = modifier) {
        Icon(
            imageVector = icon,
            contentDescription = null,
            modifier = Modifier.size(dimens.iconSm),
        )
        Text(label, modifier = Modifier.padding(start = dimens.spacingSm))
    }
}

@Composable
private fun LogCard(lines: List<String>, modifier: Modifier = Modifier) {
    val dimens = LocalDimens.current
    Surface(
        color = MaterialTheme.colorScheme.surfaceContainerHigh,
        shape = RoundedCornerShape(dimens.radiusLg),
        modifier = modifier.fillMaxWidth(),
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(dimens.spacingMd),
            verticalArrangement = Arrangement.spacedBy(dimens.spacingXs),
        ) {
            lines.forEach { line ->
                Text(text = line, style = RACTextStyles.CodeSmall)
            }
        }
    }
}
