package com.runanywhere.runanywhereai.presentation.lora

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.filled.CloudDownload
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.LinkOff
import androidx.compose.material.icons.filled.PlayArrow
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Slider
import androidx.compose.material3.SliderDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.runanywhere.runanywhereai.ui.theme.AppColors
import com.runanywhere.runanywhereai.ui.theme.Dimensions
import com.runanywhere.sdk.public.extensions.LoraAdapterCatalogEntry
import com.runanywhere.sdk.public.extensions.LLM.LoRAAdapterInfo

/**
 * Bottom sheet for picking and managing LoRA adapters for the current model.
 * Shows active adapters with remove option, and compatible adapters with download/apply.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun LoraAdapterPickerSheet(
    loraViewModel: LoraViewModel,
    onDismiss: () -> Unit,
) {
    val state by loraViewModel.uiState.collectAsState()

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = Dimensions.large),
        ) {
            // Header
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    "LoRA Adapters",
                    style = MaterialTheme.typography.titleLarge,
                    fontWeight = FontWeight.Bold,
                )
                TextButton(onClick = onDismiss) {
                    Text("Done")
                }
            }

            Spacer(modifier = Modifier.height(Dimensions.mediumLarge))

            LazyColumn(
                verticalArrangement = Arrangement.spacedBy(Dimensions.smallMedium),
            ) {
                // Active adapters section
                if (state.loadedAdapters.isNotEmpty()) {
                    item {
                        SectionHeader("Active Adapters")
                    }
                    items(state.loadedAdapters, key = { it.path }) { adapter ->
                        LoadedAdapterRow(
                            adapter = adapter,
                            onRemove = { loraViewModel.unloadAdapter(adapter.path) },
                        )
                    }
                    item {
                        Spacer(modifier = Modifier.height(Dimensions.small))
                        HorizontalDivider()
                        Spacer(modifier = Modifier.height(Dimensions.small))
                    }
                }

                // Compatible adapters section
                item {
                    SectionHeader("Compatible Adapters")
                }

                if (state.compatibleAdapters.isEmpty()) {
                    item {
                        Text(
                            "No compatible adapters found for this model.",
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.padding(vertical = Dimensions.mediumLarge),
                        )
                    }
                } else {
                    items(state.compatibleAdapters, key = { it.id }) { entry ->
                        CatalogAdapterRow(
                            entry = entry,
                            isDownloaded = loraViewModel.isDownloaded(entry),
                            isLoaded = loraViewModel.isLoaded(entry),
                            isDownloading = state.downloadingAdapterId == entry.id,
                            downloadProgress = if (state.downloadingAdapterId == entry.id) state.downloadProgress else 0f,
                            onDownload = { loraViewModel.downloadAdapter(entry) },
                            onCancelDownload = { loraViewModel.cancelDownload() },
                            onApply = { scale ->
                                val path = loraViewModel.localPath(entry) ?: return@CatalogAdapterRow
                                loraViewModel.loadAdapter(path, scale)
                            },
                            onRemove = {
                                val path = loraViewModel.localPath(entry) ?: return@CatalogAdapterRow
                                loraViewModel.unloadAdapter(path)
                            },
                        )
                    }
                }

                // Error display
                state.error?.let { error ->
                    item {
                        Text(
                            error,
                            color = AppColors.primaryRed,
                            style = MaterialTheme.typography.bodySmall,
                            modifier = Modifier.padding(vertical = Dimensions.small),
                        )
                    }
                }

                // Bottom spacing
                item { Spacer(modifier = Modifier.height(Dimensions.xxLarge)) }
            }
        }
    }
}

@Composable
private fun SectionHeader(title: String) {
    Text(
        title,
        style = MaterialTheme.typography.titleSmall,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        fontWeight = FontWeight.SemiBold,
        modifier = Modifier.padding(vertical = Dimensions.xSmall),
    )
}

@Composable
private fun LoadedAdapterRow(
    adapter: LoRAAdapterInfo,
    onRemove: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(Dimensions.cornerRadiusRegular))
            .background(MaterialTheme.colorScheme.surfaceVariant)
            .padding(Dimensions.mediumLarge),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Column(modifier = Modifier.weight(1f)) {
            Text(
                adapter.path.substringAfterLast("/"),
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.Medium,
            )
            Text(
                "Scale: %.2f".format(adapter.scale),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        IconButton(onClick = onRemove) {
            Icon(
                Icons.Default.Close,
                contentDescription = "Remove",
                tint = AppColors.primaryRed,
                modifier = Modifier.size(20.dp),
            )
        }
    }
}

@Composable
private fun CatalogAdapterRow(
    entry: LoraAdapterCatalogEntry,
    isDownloaded: Boolean,
    isLoaded: Boolean,
    isDownloading: Boolean,
    downloadProgress: Float,
    onDownload: () -> Unit,
    onCancelDownload: () -> Unit,
    onApply: (Float) -> Unit,
    onRemove: () -> Unit,
) {
    var scale by remember(entry.id, entry.defaultScale) { mutableFloatStateOf(entry.defaultScale) }

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(Dimensions.cornerRadiusRegular))
            .background(MaterialTheme.colorScheme.surfaceVariant)
            .padding(Dimensions.mediumLarge),
    ) {
        // Name + description
        Text(
            entry.name,
            style = MaterialTheme.typography.bodyLarge,
            fontWeight = FontWeight.Medium,
        )
        Text(
            entry.description,
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )

        Spacer(modifier = Modifier.height(Dimensions.smallMedium))

        // File size
        Text(
            "Size: %.1f MB".format(entry.fileSize / (1024.0 * 1024.0)),
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )

        Spacer(modifier = Modifier.height(Dimensions.smallMedium))

        if (isDownloaded && !isLoaded) {
            // Scale slider + Apply button
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text("Scale:", style = MaterialTheme.typography.labelSmall)
                Spacer(modifier = Modifier.width(Dimensions.smallMedium))
                Slider(
                    value = scale,
                    onValueChange = { scale = it },
                    valueRange = 0f..2f,
                    modifier = Modifier
                        .weight(1f)
                        .height(Dimensions.loraScaleSliderHeight),
                    colors = SliderDefaults.colors(
                        thumbColor = AppColors.primaryPurple,
                        activeTrackColor = AppColors.primaryPurple,
                    ),
                )
                Spacer(modifier = Modifier.width(Dimensions.xSmall))
                Text("%.1f".format(scale), style = MaterialTheme.typography.labelSmall)
            }
            Button(
                onClick = { onApply(scale) },
                modifier = Modifier.fillMaxWidth(),
                colors = ButtonDefaults.buttonColors(containerColor = AppColors.primaryPurple),
            ) {
                Icon(Icons.Default.PlayArrow, contentDescription = null, modifier = Modifier.size(18.dp))
                Spacer(modifier = Modifier.width(Dimensions.xSmall))
                Text("Apply")
            }
        } else if (isLoaded) {
            // Already loaded — show unload
            Button(
                onClick = onRemove,
                modifier = Modifier.fillMaxWidth(),
                colors = ButtonDefaults.buttonColors(
                    containerColor = AppColors.primaryRed.copy(alpha = 0.1f),
                ),
            ) {
                Icon(Icons.Default.LinkOff, contentDescription = null, tint = AppColors.primaryRed, modifier = Modifier.size(18.dp))
                Spacer(modifier = Modifier.width(Dimensions.xSmall))
                Text("Unload", color = AppColors.primaryRed)
            }
        } else if (isDownloading) {
            // Download progress
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.Center,
            ) {
                CircularProgressIndicator(
                    progress = { downloadProgress },
                    modifier = Modifier.size(24.dp),
                    strokeWidth = 2.dp,
                    color = AppColors.primaryPurple,
                )
                Spacer(modifier = Modifier.width(Dimensions.smallMedium))
                Text(
                    "${(downloadProgress * 100).toInt()}%",
                    style = MaterialTheme.typography.bodySmall,
                )
                Spacer(modifier = Modifier.width(Dimensions.smallMedium))
                IconButton(onClick = onCancelDownload, modifier = Modifier.size(24.dp)) {
                    Icon(Icons.Default.Close, contentDescription = "Cancel download", modifier = Modifier.size(16.dp))
                }
            }
        } else {
            // Not downloaded — show download button
            Button(
                onClick = onDownload,
                modifier = Modifier.fillMaxWidth(),
                colors = ButtonDefaults.buttonColors(containerColor = AppColors.primaryAccent),
            ) {
                Icon(Icons.Default.CloudDownload, contentDescription = null, modifier = Modifier.size(18.dp))
                Spacer(modifier = Modifier.width(Dimensions.xSmall))
                Text("Download")
            }
        }
    }
}
