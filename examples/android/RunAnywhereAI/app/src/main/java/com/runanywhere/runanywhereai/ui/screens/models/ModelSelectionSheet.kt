package com.runanywhere.runanywhereai.ui.screens.models

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.systemBars
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import com.runanywhere.runanywhereai.ui.theme.LocalDimens
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ModelSelectionSheet(
    viewModel: ModelSelectionViewModel,
    onDismiss: () -> Unit,
) {
    val dimens = LocalDimens.current
    val state = viewModel.state
    val scope = rememberCoroutineScope()
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val device = remember { runCatching { DeviceInfo.current() }.getOrNull() }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        shape = RoundedCornerShape(topStart = dimens.radiusLg, topEnd = dimens.radiusLg),
        containerColor = MaterialTheme.colorScheme.surfaceContainer,
        dragHandle = null,
        contentWindowInsets = { WindowInsets.systemBars },
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(bottom = dimens.spacingXl),
        ) {
            Header(title = viewModel.title, onCancel = onDismiss)

            device?.let {
                SectionLabel("Device")
                Spacer(Modifier.height(dimens.spacingSm))
                DeviceStatusCard(it, Modifier.padding(horizontal = dimens.spacingLg))
                Spacer(Modifier.height(dimens.spacingLg))
            }

            SectionLabel("Available Models")
            Spacer(Modifier.height(dimens.spacingSm))

            when {
                state.isLoading -> CenterNote("Loading models…", showSpinner = true)
                state.models.isEmpty() -> CenterNote("No models available")
                else -> ModelList(viewModel, state, scope, onDismiss)
            }

            Spacer(Modifier.height(dimens.spacingMd))
            Text(
                "All models run privately on your device.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(horizontal = dimens.spacingLg),
            )
        }
    }

    state.error?.let { message ->
        AlertDialog(
            onDismissRequest = viewModel::clearError,
            confirmButton = { TextButton(onClick = viewModel::clearError) { Text("OK") } },
            title = { Text("Error") },
            text = { Text(message) },
        )
    }
}

@Composable
private fun ModelList(
    viewModel: ModelSelectionViewModel,
    state: ModelSelectionState,
    scope: kotlinx.coroutines.CoroutineScope,
    onDismiss: () -> Unit,
) {
    val dimens = LocalDimens.current
    val sorted = state.models.sortedWith(
        compareBy({ if (viewModel.isReady(it)) 0 else 1 }, { it.name }),
    )
    val grouped = sorted.groupBy { it.consumerGroup() }
    ConsumerModelGroup.entries.forEach { group ->
        val models = grouped[group].orEmpty()
        if (models.isEmpty()) return@forEach
        SectionLabel(group.title)
        Spacer(Modifier.height(dimens.spacingSm))
        models.forEach { model ->
            ModelRow(
                model = model,
                isCurrent = state.currentModelId == model.id,
                isReady = viewModel.isReady(model),
                isBusy = state.busyModelId == model.id,
                progressPercent = if (state.busyModelId == model.id) state.progressPercent else null,
                onSelect = {
                    scope.launch {
                        if (viewModel.select(model)) onDismiss()
                    }
                },
                onDownload = { viewModel.download(model) },
                modifier = Modifier.padding(horizontal = dimens.spacingLg),
            )
            Spacer(Modifier.height(dimens.spacingSm))
        }
        Text(
            group.footer,
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(horizontal = dimens.spacingLg),
        )
        Spacer(Modifier.height(dimens.spacingLg))
    }

    if (state.models.any { it.supports_lora }) {
        SectionLabel("LoRA & Adapters")
        Spacer(Modifier.height(dimens.spacingSm))
        Text(
            "Adapters customize a loaded base chat model. Open Adapters from the drawer after choosing a LoRA-ready chat model.",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(horizontal = dimens.spacingLg),
        )
    }
}

@Composable
private fun Header(title: String, onCancel: () -> Unit) {
    val dimens = LocalDimens.current
    Box(modifier = Modifier
        .fillMaxWidth()
        .padding(vertical = dimens.spacingMd)) {
        TextButton(
            onClick = onCancel,
            modifier = Modifier.align(Alignment.CenterStart),
            colors = ButtonDefaults.textButtonColors(contentColor = MaterialTheme.colorScheme.primary)
        ) {
            Text("Cancel", color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        Text(
            title,
            style = MaterialTheme.typography.titleLarge,
            fontWeight = FontWeight.SemiBold,
            modifier = Modifier.align(Alignment.Center),
        )
    }
}

@Composable
private fun SectionLabel(text: String) {
    val dimens = LocalDimens.current
    Text(
        text,
        style = MaterialTheme.typography.bodyMedium,
        fontWeight = FontWeight.Medium,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier.padding(horizontal = dimens.spacingLg),
    )
}

@Composable
private fun CenterNote(text: String, showSpinner: Boolean = false) {
    val dimens = LocalDimens.current
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(dimens.spacingXl),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        if (showSpinner) {
            CircularProgressIndicator()
            Spacer(Modifier.height(dimens.spacingMd))
        }
        Text(
            text,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
}
