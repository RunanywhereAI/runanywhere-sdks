package com.runanywhere.runanywhereai.presentation.lora

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
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
import androidx.compose.material.icons.filled.DeleteForever
import androidx.compose.material.icons.filled.LinkOff
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.runanywhere.runanywhereai.presentation.components.ConfigureTopBar
import com.runanywhere.runanywhereai.ui.theme.AppColors
import com.runanywhere.runanywhereai.ui.theme.Dimensions
import com.runanywhere.sdk.public.extensions.LoraAdapterCatalogEntry

/**
 * Full LoRA adapter manager screen — accessible from More hub.
 * Shows currently loaded adapters and all registered adapters with download/delete.
 */
@Composable
fun LoraManagerScreen(
    onBack: () -> Unit = {},
    loraViewModel: LoraViewModel = viewModel(),
) {
    val state by loraViewModel.uiState.collectAsState()

    ConfigureTopBar(title = "LoRA Adapters", showBack = true, onBack = onBack)

    LazyColumn(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = Dimensions.large),
        verticalArrangement = Arrangement.spacedBy(Dimensions.smallMedium),
    ) {
            // Currently loaded section
            if (state.loadedAdapters.isNotEmpty()) {
                item {
                    Spacer(modifier = Modifier.height(Dimensions.smallMedium))
                    Text(
                        "Currently Loaded",
                        style = MaterialTheme.typography.titleSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        fontWeight = FontWeight.SemiBold,
                    )
                }
                items(state.loadedAdapters, key = { it.path }) { adapter ->
                    Card(
                        modifier = Modifier.fillMaxWidth(),
                        shape = RoundedCornerShape(Dimensions.cornerRadiusXLarge),
                        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant),
                    ) {
                        Row(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(Dimensions.large),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Column(modifier = Modifier.weight(1f)) {
                                Text(
                                    adapter.path.substringAfterLast("/"),
                                    style = MaterialTheme.typography.bodyMedium,
                                    fontWeight = FontWeight.Medium,
                                )
                                Text(
                                    "Scale: ${"%.2f".format(adapter.scale)}  |  ${if (adapter.applied) "Applied" else "Pending"}",
                                    style = MaterialTheme.typography.bodySmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                            }
                            Button(
                                onClick = { loraViewModel.unloadAdapter(adapter.path) },
                                colors = ButtonDefaults.buttonColors(
                                    containerColor = AppColors.primaryRed.copy(alpha = 0.1f),
                                ),
                            ) {
                                Icon(
                                    Icons.Default.LinkOff,
                                    contentDescription = null,
                                    tint = AppColors.primaryRed,
                                    modifier = Modifier.size(16.dp),
                                )
                                Spacer(modifier = Modifier.width(Dimensions.xSmall))
                                Text("Unload", color = AppColors.primaryRed)
                            }
                        }
                    }
                }

                // Clear all button
                item {
                    Button(
                        onClick = { loraViewModel.clearAll() },
                        modifier = Modifier.fillMaxWidth(),
                        colors = ButtonDefaults.buttonColors(containerColor = AppColors.primaryRed.copy(alpha = 0.1f)),
                    ) {
                        Icon(
                            Icons.Default.DeleteForever,
                            contentDescription = null,
                            tint = AppColors.primaryRed,
                            modifier = Modifier.size(18.dp),
                        )
                        Spacer(modifier = Modifier.width(Dimensions.xSmall))
                        Text("Clear All Adapters", color = AppColors.primaryRed)
                    }
                }
            }

            // All registered adapters section
            item {
                Spacer(modifier = Modifier.height(Dimensions.mediumLarge))
                Text(
                    "All Adapters",
                    style = MaterialTheme.typography.titleSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    fontWeight = FontWeight.SemiBold,
                )
            }

            if (state.registeredAdapters.isEmpty()) {
                item {
                    Text(
                        "No adapters registered. Adapters are registered at app startup.",
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(vertical = Dimensions.large),
                    )
                }
            } else {
                items(state.registeredAdapters, key = { it.id }) { entry ->
                    RegisteredAdapterCard(
                        entry = entry,
                        isDownloaded = loraViewModel.isDownloaded(entry),
                        isDownloading = state.downloadingAdapterId == entry.id,
                        downloadProgress = if (state.downloadingAdapterId == entry.id) state.downloadProgress else 0f,
                        onDownload = { loraViewModel.downloadAdapter(entry) },
                        onCancelDownload = { loraViewModel.cancelDownload() },
                        onDelete = { loraViewModel.deleteAdapter(entry) },
                    )
                }
            }

            // Error
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

            item { Spacer(modifier = Modifier.height(Dimensions.xxLarge)) }
    }
}

@Composable
private fun RegisteredAdapterCard(
    entry: LoraAdapterCatalogEntry,
    isDownloaded: Boolean,
    isDownloading: Boolean,
    downloadProgress: Float,
    onDownload: () -> Unit,
    onCancelDownload: () -> Unit,
    onDelete: () -> Unit,
) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(Dimensions.cornerRadiusXLarge),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant),
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .padding(Dimensions.large),
        ) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Column(modifier = Modifier.weight(1f)) {
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
                }

                // LoRA badge
                Text(
                    "LoRA",
                    style = MaterialTheme.typography.labelSmall,
                    color = AppColors.primaryPurple,
                    fontWeight = FontWeight.SemiBold,
                    modifier = Modifier
                        .clip(RoundedCornerShape(Dimensions.cornerRadiusSmall))
                        .background(AppColors.loraBadgeBg)
                        .padding(horizontal = Dimensions.small, vertical = Dimensions.xxSmall),
                )
            }

            Spacer(modifier = Modifier.height(Dimensions.smallMedium))

            // Compatible models chips
            Row(
                horizontalArrangement = Arrangement.spacedBy(Dimensions.xSmall),
            ) {
                entry.compatibleModelIds.forEach { modelId ->
                    Text(
                        modelId,
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier
                            .clip(RoundedCornerShape(Dimensions.cornerRadiusSmall))
                            .background(MaterialTheme.colorScheme.surface)
                            .padding(horizontal = Dimensions.small, vertical = Dimensions.xxSmall),
                    )
                }
            }

            Spacer(modifier = Modifier.height(Dimensions.xSmall))

            // File size
            Text(
                "%.1f MB".format(entry.fileSize / (1024.0 * 1024.0)),
                style = MaterialTheme.typography.labelSmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )

            Spacer(modifier = Modifier.height(Dimensions.smallMedium))

            // Action button
            when {
                isDownloading -> {
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
                            "Downloading ${(downloadProgress * 100).toInt()}%",
                            style = MaterialTheme.typography.bodySmall,
                        )
                        Spacer(modifier = Modifier.width(Dimensions.smallMedium))
                        IconButton(onClick = onCancelDownload, modifier = Modifier.size(24.dp)) {
                            Icon(Icons.Default.Close, contentDescription = "Cancel download", modifier = Modifier.size(16.dp))
                        }
                    }
                }
                isDownloaded -> {
                    Button(
                        onClick = onDelete,
                        modifier = Modifier.fillMaxWidth(),
                        colors = ButtonDefaults.buttonColors(
                            containerColor = AppColors.primaryRed.copy(alpha = 0.1f),
                        ),
                    ) {
                        Icon(
                            Icons.Default.Delete,
                            contentDescription = null,
                            tint = AppColors.primaryRed,
                            modifier = Modifier.size(18.dp),
                        )
                        Spacer(modifier = Modifier.width(Dimensions.xSmall))
                        Text("Delete Download", color = AppColors.primaryRed)
                    }
                }
                else -> {
                    Button(
                        onClick = onDownload,
                        modifier = Modifier.fillMaxWidth(),
                        colors = ButtonDefaults.buttonColors(containerColor = AppColors.primaryAccent),
                    ) {
                        Icon(
                            Icons.Default.CloudDownload,
                            contentDescription = null,
                            modifier = Modifier.size(18.dp),
                        )
                        Spacer(modifier = Modifier.width(Dimensions.xSmall))
                        Text("Download")
                    }
                }
            }
        }
    }
}
