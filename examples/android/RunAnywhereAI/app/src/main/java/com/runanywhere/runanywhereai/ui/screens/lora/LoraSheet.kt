package com.runanywhere.runanywhereai.ui.screens.lora

import ai.runanywhere.proto.v1.LoraAdapterCatalogEntry
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBars
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Slider
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.runanywhere.runanywhereai.ui.screens.models.formatModelSize
import com.runanywhere.runanywhereai.ui.theme.LocalDimens
import com.runanywhere.runanywhereai.ui.theme.icons.RACIcons
import com.runanywhere.runanywhereai.ui.theme.primaryGreen
import java.util.Locale

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LoraSheet(viewModel: LoraViewModel, onDismiss: () -> Unit) {
    val dimens = LocalDimens.current
    val state = viewModel.state
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)

    LaunchedEffect(Unit) { viewModel.refresh() }

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
                .padding(horizontal = dimens.spacingLg)
                .padding(bottom = dimens.spacingXl),
            verticalArrangement = Arrangement.spacedBy(dimens.spacingSm),
        ) {
            Column(modifier = Modifier.padding(vertical = dimens.spacingMd)) {
                Text("LoRA Adapters", style = MaterialTheme.typography.titleMedium)
                viewModel.modelName?.let {
                    Text(
                        text = "for $it",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }

            when {
                state.isLoading -> CenterNote("Loading adapters…", showSpinner = true)
                state.adapters.isEmpty() -> CenterNote("No adapters for this model")
                else -> state.adapters.forEach { entry ->
                    LoraRow(
                        entry = entry,
                        isActive = state.activeId == entry.id,
                        isDownloaded = viewModel.isDownloaded(entry),
                        isBusy = state.busyId == entry.id,
                        progressPercent = if (state.busyId == entry.id) state.progressPercent else null,
                        onDownload = { viewModel.download(entry) },
                        onApply = { scale -> viewModel.apply(entry, scale) },
                        onRemove = viewModel::clear,
                    )
                }
            }

            Text(
                text = "Adapters fine-tune the loaded model's responses. Applying one replaces any active adapter.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(top = dimens.spacingSm),
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
private fun LoraRow(
    entry: LoraAdapterCatalogEntry,
    isActive: Boolean,
    isDownloaded: Boolean,
    isBusy: Boolean,
    progressPercent: Int?,
    onDownload: () -> Unit,
    onApply: (Float) -> Unit,
    onRemove: () -> Unit,
) {
    val dimens = LocalDimens.current
    var scale by rememberSaveable(entry.id) {
        mutableFloatStateOf(entry.default_scale.takeIf { it > 0f } ?: 1f)
    }
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(dimens.radiusLg))
            .background(MaterialTheme.colorScheme.surface)
            .padding(dimens.spacingMd),
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(dimens.spacingSm)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = entry.name,
                        style = MaterialTheme.typography.bodyLarge,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                    )
                    if (entry.description.isNotBlank()) {
                        Text(
                            text = entry.description,
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            maxLines = 2,
                            overflow = TextOverflow.Ellipsis,
                            modifier = Modifier.padding(top = dimens.spacingXs),
                        )
                    }
                    if (entry.size_bytes > 0) {
                        Text(
                            text = formatModelSize(entry.size_bytes),
                            style = MaterialTheme.typography.labelSmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.padding(top = dimens.spacingXs),
                        )
                    }
                }

                Spacer(Modifier.size(dimens.spacingMd))

                LoraAction(
                    isActive = isActive,
                    isDownloaded = isDownloaded,
                    isBusy = isBusy,
                    progressPercent = progressPercent,
                    onDownload = onDownload,
                    onApply = { onApply(scale) },
                    onRemove = onRemove,
                )
            }

            if (isDownloaded && !isActive) {
                StrengthControl(scale = scale, onScaleChange = { scale = it })
            } else if (isActive) {
                Text(
                    text = "Strength ${String.format(Locale.US, "%.2fx", scale)}",
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

@Composable
private fun StrengthControl(scale: Float, onScaleChange: (Float) -> Unit) {
    val dimens = LocalDimens.current
    Column(verticalArrangement = Arrangement.spacedBy(dimens.spacingXs)) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                text = "Strength",
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Text(
                text = String.format(Locale.US, "%.2fx", scale),
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.primary,
            )
        }
        Slider(
            value = scale,
            onValueChange = onScaleChange,
            valueRange = 0.1f..2.0f,
            steps = 18,
        )
    }
}

@Composable
private fun LoraAction(
    isActive: Boolean,
    isDownloaded: Boolean,
    isBusy: Boolean,
    progressPercent: Int?,
    onDownload: () -> Unit,
    onApply: () -> Unit,
    onRemove: () -> Unit,
) {
    val dimens = LocalDimens.current
    when {
        progressPercent != null -> Row(verticalAlignment = Alignment.CenterVertically) {
            CircularProgressIndicator(modifier = Modifier.size(dimens.iconSm), strokeWidth = 2.dp)
            Text(
                text = "$progressPercent%",
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(start = dimens.spacingSm),
            )
        }
        isBusy -> CircularProgressIndicator(modifier = Modifier.size(dimens.iconSm), strokeWidth = 2.dp)
        isActive -> Row(verticalAlignment = Alignment.CenterVertically) {
            Pill("Active", primaryGreen)
            IconButton(onClick = onRemove) {
                Icon(
                    imageVector = RACIcons.Outline.Close,
                    contentDescription = "Remove adapter",
                    tint = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.size(dimens.iconSm),
                )
            }
        }
        isDownloaded -> Pill("Apply", MaterialTheme.colorScheme.primary, onClick = onApply)
        else -> IconButton(onClick = onDownload) {
            Icon(
                imageVector = RACIcons.Outline.Download,
                contentDescription = "Download adapter",
                tint = MaterialTheme.colorScheme.primary,
                modifier = Modifier.size(dimens.iconMd),
            )
        }
    }
}

@Composable
private fun Pill(text: String, color: androidx.compose.ui.graphics.Color, onClick: (() -> Unit)? = null) {
    val dimens = LocalDimens.current
    val base = Modifier
        .clip(RoundedCornerShape(dimens.radiusFull))
        .background(color.copy(alpha = 0.15f))
    Box(
        modifier = if (onClick != null) base.clickable(onClick = onClick) else base,
    ) {
        Text(
            text = text,
            style = MaterialTheme.typography.labelLarge,
            color = color,
            modifier = Modifier.padding(horizontal = dimens.spacingMd, vertical = dimens.spacingXs),
        )
    }
}

@Composable
private fun CenterNote(text: String, showSpinner: Boolean = false) {
    val dimens = LocalDimens.current
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(dimens.spacingLg),
        horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (showSpinner) {
            CircularProgressIndicator(modifier = Modifier.size(dimens.iconSm), strokeWidth = 2.dp)
            Spacer(Modifier.height(dimens.spacingSm))
        }
        Text(
            text = text,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
            modifier = Modifier.padding(start = if (showSpinner) dimens.spacingSm else 0.dp),
        )
    }
}
