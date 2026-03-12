package com.runanywhere.runanywhereai.ui.components

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.PrimaryTabRow
import androidx.compose.material3.Tab
import androidx.compose.material3.Text
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.runanywhere.runanywhereai.ui.icons.RAIcons
import com.runanywhere.runanywhereai.viewmodels.DownloadInfo
import com.runanywhere.runanywhereai.viewmodels.ModelSelectionUiState
import com.runanywhere.sdk.core.types.InferenceFramework
import com.runanywhere.sdk.models.DeviceInfo
import com.runanywhere.sdk.public.extensions.LoraAdapterCatalogEntry
import com.runanywhere.sdk.public.extensions.Models.ModelInfo

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ModelSelectionSheet(
    state: ModelSelectionUiState,
    onDismiss: () -> Unit,
    onSelectModel: (String) -> Unit,
    onDownloadModel: (String) -> Unit,
    onCancelModelDownload: () -> Unit,
    onLoadLora: (String) -> Unit,
    onUnloadLora: (String) -> Unit,
    onDownloadLora: (LoraAdapterCatalogEntry) -> Unit,
    onCancelLoraDownload: () -> Unit,
    isLoraDownloaded: (String) -> Boolean,
    isLoraLoaded: (String) -> Boolean,
    modifier: Modifier = Modifier,
) {
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val showTabs = state.selectedModelSupportsLora || state.loraAdapters.isNotEmpty()
    var selectedTab by remember { mutableIntStateOf(0) }

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        shape = RoundedCornerShape(topStart = 20.dp, topEnd = 20.dp),
        containerColor = MaterialTheme.colorScheme.surfaceContainerLow,
        modifier = modifier,
    ) {
        Column(
            modifier = Modifier
                .fillMaxWidth()
                .navigationBarsPadding(),
        ) {
            // Title
            Text(
                text = state.context.title,
                style = MaterialTheme.typography.titleMedium,
                fontWeight = FontWeight.SemiBold,
                modifier = Modifier.padding(horizontal = 20.dp, vertical = 8.dp),
            )

            // Device hardware info card
            if (state.deviceInfo != null) {
                DeviceInfoCard(deviceInfo = state.deviceInfo)
                Spacer(modifier = Modifier.height(12.dp))
            }

            // Error banner
            if (state.error != null) {
                ErrorBanner(message = state.error)
            }

            // Tab layout (Models | LoRA) for LLM context, or just model list for others
            if (showTabs) {
                PrimaryTabRow(
                    selectedTabIndex = selectedTab,
                    modifier = Modifier.fillMaxWidth(),
                    containerColor = MaterialTheme.colorScheme.surfaceContainerLow,
                ) {
                    Tab(
                        selected = selectedTab == 0,
                        onClick = { selectedTab = 0 },
                        text = { Text("Models") },
                    )
                    Tab(
                        selected = selectedTab == 1,
                        onClick = { selectedTab = 1 },
                        text = {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Text("LoRA")
                                if (state.hasActiveLoraAdapters) {
                                    Spacer(modifier = Modifier.width(6.dp))
                                    Surface(
                                        shape = RoundedCornerShape(4.dp),
                                        color = MaterialTheme.colorScheme.tertiary,
                                    ) {
                                        Text(
                                            text = "${state.loadedLoraAdapters.size}",
                                            style = MaterialTheme.typography.labelSmall,
                                            color = MaterialTheme.colorScheme.onTertiary,
                                            modifier = Modifier.padding(horizontal = 5.dp, vertical = 1.dp),
                                        )
                                    }
                                }
                            }
                        },
                    )
                }

                when (selectedTab) {
                    0 -> ModelList(
                        state = state,
                        onSelectModel = onSelectModel,
                        onDownloadModel = onDownloadModel,
                        onCancelModelDownload = onCancelModelDownload,
                    )
                    1 -> LoraList(
                        state = state,
                        onLoadLora = onLoadLora,
                        onUnloadLora = onUnloadLora,
                        onDownloadLora = onDownloadLora,
                        onCancelLoraDownload = onCancelLoraDownload,
                        isLoraDownloaded = isLoraDownloaded,
                        isLoraLoaded = isLoraLoaded,
                    )
                }
            } else {
                ModelList(
                    state = state,
                    onSelectModel = onSelectModel,
                    onDownloadModel = onDownloadModel,
                    onCancelModelDownload = onCancelModelDownload,
                )
            }
        }
    }
}

// -- Device Info Card --

@Composable
private fun DeviceInfoCard(deviceInfo: DeviceInfo) {
    Surface(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp),
        shape = RoundedCornerShape(16.dp),
        color = MaterialTheme.colorScheme.surfaceContainer,
    ) {
        Column(modifier = Modifier.padding(horizontal = 16.dp)) {
            DeviceRow(
                icon = RAIcons.Smartphone,
                label = "Device",
                value = deviceInfo.modelName,
            )
            RowDivider()
            DeviceRow(
                icon = RAIcons.Cpu,
                label = "Architecture",
                value = "${deviceInfo.architecture} \u00B7 ${deviceInfo.processorCount} cores",
            )
            RowDivider()
            DeviceRow(
                icon = RAIcons.HardDrive,
                label = "Memory",
                value = "${deviceInfo.totalMemoryMB} MB",
            )
        }
    }
}

@Composable
private fun DeviceRow(
    icon: ImageVector,
    label: String,
    value: String,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            contentAlignment = Alignment.Center,
            modifier = Modifier
                .size(30.dp)
                .clip(RoundedCornerShape(8.dp))
                .background(MaterialTheme.colorScheme.primary.copy(alpha = 0.1f)),
        ) {
            Icon(
                imageVector = icon,
                contentDescription = null,
                modifier = Modifier.size(18.dp),
                tint = MaterialTheme.colorScheme.primary,
            )
        }
        Spacer(modifier = Modifier.width(12.dp))
        Text(
            text = label,
            style = MaterialTheme.typography.bodyMedium,
            fontWeight = FontWeight.Medium,
        )
        Spacer(modifier = Modifier.weight(1f))
        Text(
            text = value,
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

@Composable
private fun RowDivider() {
    HorizontalDivider(
        color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.3f),
        thickness = 0.5.dp,
    )
}

// -- Error Banner --

@Composable
private fun ErrorBanner(message: String) {
    Surface(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 4.dp),
        shape = RoundedCornerShape(8.dp),
        color = MaterialTheme.colorScheme.errorContainer,
    ) {
        Row(
            modifier = Modifier.padding(12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(
                imageVector = RAIcons.AlertCircle,
                contentDescription = null,
                modifier = Modifier.size(16.dp),
                tint = MaterialTheme.colorScheme.error,
            )
            Spacer(modifier = Modifier.width(8.dp))
            Text(
                text = message,
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onErrorContainer,
            )
        }
    }
}

// -- Model List --

@Composable
private fun ModelList(
    state: ModelSelectionUiState,
    onSelectModel: (String) -> Unit,
    onDownloadModel: (String) -> Unit,
    onCancelModelDownload: () -> Unit,
) {
    LazyColumn(
        contentPadding = PaddingValues(top = 8.dp, bottom = 32.dp),
    ) {
        items(
            items = state.models,
            key = { it.id },
            contentType = { "model" },
        ) { model ->
            val isDownloading = state.downloadingModelId == model.id
            ModelRow(
                model = model,
                isSelected = model.id == state.selectedModelId,
                isLoading = state.loadingModelId == model.id,
                isDownloading = isDownloading,
                downloadInfo = if (isDownloading) state.modelDownloadInfo else null,
                onSelect = { onSelectModel(model.id) },
                onDownload = { onDownloadModel(model.id) },
                onCancelDownload = onCancelModelDownload,
            )
        }

        item(key = "footer") {
            Text(
                text = "All models run privately on your device.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f),
                modifier = Modifier.padding(horizontal = 20.dp, vertical = 12.dp),
            )
        }
    }
}

// -- LoRA List --

@Composable
private fun LoraList(
    state: ModelSelectionUiState,
    onLoadLora: (String) -> Unit,
    onUnloadLora: (String) -> Unit,
    onDownloadLora: (LoraAdapterCatalogEntry) -> Unit,
    onCancelLoraDownload: () -> Unit,
    isLoraDownloaded: (String) -> Boolean,
    isLoraLoaded: (String) -> Boolean,
) {
    LazyColumn(
        contentPadding = PaddingValues(top = 8.dp, bottom = 32.dp),
    ) {
        if (state.loraAdapters.isEmpty()) {
            item(key = "empty") {
                Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(40.dp),
                    contentAlignment = Alignment.Center,
                ) {
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Icon(
                            imageVector = RAIcons.Sparkles,
                            contentDescription = null,
                            modifier = Modifier.size(32.dp),
                            tint = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.4f),
                        )
                        Spacer(modifier = Modifier.height(8.dp))
                        Text(
                            text = "No compatible adapters",
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.6f),
                        )
                        Text(
                            text = "Select a LoRA-compatible model first",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.4f),
                        )
                    }
                }
            }
        } else {
            items(
                items = state.loraAdapters,
                key = { "lora_${it.id}" },
                contentType = { "lora" },
            ) { adapter ->
                val isDownloading = state.downloadingAdapterId == adapter.id
                LoraRow(
                    adapter = adapter,
                    isDownloaded = isLoraDownloaded(adapter.id),
                    isLoaded = isLoraLoaded(adapter.id),
                    isDownloading = isDownloading,
                    downloadInfo = if (isDownloading) state.loraDownloadInfo else null,
                    onLoad = { onLoadLora(adapter.id) },
                    onUnload = { onUnloadLora(adapter.id) },
                    onDownload = { onDownloadLora(adapter) },
                    onCancelDownload = onCancelLoraDownload,
                )
            }
        }
    }
}

// -- Row Components --

@Composable
private fun ModelRow(
    model: ModelInfo,
    isSelected: Boolean,
    isLoading: Boolean,
    isDownloading: Boolean,
    downloadInfo: DownloadInfo?,
    onSelect: () -> Unit,
    onDownload: () -> Unit,
    onCancelDownload: () -> Unit,
) {
    Surface(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 3.dp),
        shape = RoundedCornerShape(12.dp),
        color = if (isSelected) {
            MaterialTheme.colorScheme.primaryContainer.copy(alpha = 0.4f)
        } else {
            MaterialTheme.colorScheme.surface
        },
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        text = model.name,
                        style = MaterialTheme.typography.bodyMedium,
                        fontWeight = FontWeight.Medium,
                        maxLines = 1,
                        overflow = TextOverflow.Ellipsis,
                        modifier = Modifier.weight(1f, fill = false),
                    )
                    if (model.id.contains("lfm") && model.category == com.runanywhere.sdk.public.extensions.Models.ModelCategory.MULTIMODAL) {
                        Spacer(modifier = Modifier.width(6.dp))
                        Surface(
                            shape = RoundedCornerShape(4.dp),
                            color = Color(0xFF87CEEB),
                        ) {
                            Text(
                                text = "Fastest",
                                style = MaterialTheme.typography.labelSmall,
                                color = Color(0xFF1A3A4A),
                                modifier = Modifier.padding(horizontal = 5.dp, vertical = 1.dp),
                            )
                        }
                    }
                    if (model.framework == InferenceFramework.GENIE) {
                        Spacer(modifier = Modifier.width(6.dp))
                        TagBadge(text = "NPU", color = NpuBlue)
                        Spacer(modifier = Modifier.width(6.dp))
                        TagBadge(text = "SD 8 Gen 2+", color = NpuBlue)
                    }
                    if (model.supportsLora) {
                        Spacer(modifier = Modifier.width(6.dp))
                        Surface(
                            shape = RoundedCornerShape(4.dp),
                            color = MaterialTheme.colorScheme.tertiaryContainer,
                        ) {
                            Text(
                                text = "LoRA",
                                style = MaterialTheme.typography.labelSmall,
                                color = MaterialTheme.colorScheme.onTertiaryContainer,
                                modifier = Modifier.padding(horizontal = 5.dp, vertical = 1.dp),
                            )
                        }
                    }
                }

                if (isDownloading && downloadInfo != null) {
                    Text(
                        text = downloadInfo.formattedProgress,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.primary.copy(alpha = 0.8f),
                    )
                    Spacer(modifier = Modifier.height(4.dp))
                    LinearProgressIndicator(
                        progress = { downloadInfo.progress },
                        modifier = Modifier.fillMaxWidth(),
                        trackColor = MaterialTheme.colorScheme.surfaceContainerHighest,
                    )
                } else {
                    val sizeText = model.downloadSize?.let { formatFileSize(it) }
                    if (sizeText != null) {
                        Text(
                            text = sizeText,
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.7f),
                        )
                    }
                }
            }

            Spacer(modifier = Modifier.width(12.dp))

            when {
                isSelected -> {
                    Icon(
                        imageVector = RAIcons.CircleCheck,
                        contentDescription = "Active",
                        modifier = Modifier.size(22.dp),
                        tint = MaterialTheme.colorScheme.primary,
                    )
                }
                isLoading -> {
                    CircularProgressIndicator(
                        modifier = Modifier.size(22.dp),
                        strokeWidth = 2.dp,
                        color = MaterialTheme.colorScheme.primary,
                    )
                }
                isDownloading -> {
                    IconButton(onClick = onCancelDownload, modifier = Modifier.size(32.dp)) {
                        Icon(
                            imageVector = RAIcons.X,
                            contentDescription = "Cancel",
                            modifier = Modifier.size(18.dp),
                            tint = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
                model.isDownloaded -> {
                    Button(
                        onClick = onSelect,
                        contentPadding = PaddingValues(horizontal = 12.dp, vertical = 0.dp),
                        modifier = Modifier.height(32.dp),
                    ) {
                        Text("Use", style = MaterialTheme.typography.labelMedium)
                    }
                }
                else -> {
                    OutlinedButton(
                        onClick = onDownload,
                        contentPadding = PaddingValues(horizontal = 10.dp, vertical = 0.dp),
                        modifier = Modifier.height(32.dp),
                    ) {
                        Icon(RAIcons.Download, contentDescription = null, modifier = Modifier.size(14.dp))
                        Spacer(modifier = Modifier.width(4.dp))
                        Text(
                            text = model.downloadSize?.let { formatFileSize(it) } ?: "Get",
                            style = MaterialTheme.typography.labelMedium,
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun LoraRow(
    adapter: LoraAdapterCatalogEntry,
    isDownloaded: Boolean,
    isLoaded: Boolean,
    isDownloading: Boolean,
    downloadInfo: DownloadInfo?,
    onLoad: () -> Unit,
    onUnload: () -> Unit,
    onDownload: () -> Unit,
    onCancelDownload: () -> Unit,
) {
    Surface(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 3.dp),
        shape = RoundedCornerShape(12.dp),
        color = if (isLoaded) {
            MaterialTheme.colorScheme.tertiaryContainer.copy(alpha = 0.3f)
        } else {
            MaterialTheme.colorScheme.surface
        },
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = adapter.name,
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.Medium,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
                if (isDownloading && downloadInfo != null) {
                    Text(
                        text = downloadInfo.formattedProgress,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.primary.copy(alpha = 0.8f),
                    )
                    Spacer(modifier = Modifier.height(4.dp))
                    LinearProgressIndicator(
                        progress = { downloadInfo.progress },
                        modifier = Modifier.fillMaxWidth(),
                        trackColor = MaterialTheme.colorScheme.surfaceContainerHighest,
                    )
                } else {
                    Text(
                        text = adapter.description,
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant.copy(alpha = 0.7f),
                        maxLines = 2,
                        overflow = TextOverflow.Ellipsis,
                    )
                }
            }

            Spacer(modifier = Modifier.width(12.dp))

            when {
                isLoaded -> {
                    OutlinedButton(
                        onClick = onUnload,
                        contentPadding = PaddingValues(horizontal = 10.dp, vertical = 0.dp),
                        modifier = Modifier.height(30.dp),
                        colors = ButtonDefaults.outlinedButtonColors(contentColor = MaterialTheme.colorScheme.error),
                    ) {
                        Text("Remove", style = MaterialTheme.typography.labelSmall)
                    }
                }
                isDownloading -> {
                    IconButton(onClick = onCancelDownload, modifier = Modifier.size(30.dp)) {
                        Icon(RAIcons.X, contentDescription = "Cancel", modifier = Modifier.size(16.dp))
                    }
                }
                isDownloaded -> {
                    Button(
                        onClick = onLoad,
                        contentPadding = PaddingValues(horizontal = 10.dp, vertical = 0.dp),
                        modifier = Modifier.height(30.dp),
                        colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.tertiary),
                    ) {
                        Text("Apply", style = MaterialTheme.typography.labelSmall)
                    }
                }
                else -> {
                    OutlinedButton(
                        onClick = onDownload,
                        contentPadding = PaddingValues(horizontal = 10.dp, vertical = 0.dp),
                        modifier = Modifier.height(30.dp),
                    ) {
                        Icon(RAIcons.Download, contentDescription = null, modifier = Modifier.size(14.dp))
                        Spacer(modifier = Modifier.width(4.dp))
                        Text(formatFileSize(adapter.fileSize), style = MaterialTheme.typography.labelSmall)
                    }
                }
            }
        }
    }
}

// -- Tag Badge --

private val NpuBlue = Color(0xFF2196F3)

@Composable
private fun TagBadge(text: String, color: Color) {
    Surface(
        shape = RoundedCornerShape(4.dp),
        color = color.copy(alpha = 0.15f),
    ) {
        Text(
            text = text,
            style = MaterialTheme.typography.labelSmall,
            color = color,
            modifier = Modifier.padding(horizontal = 5.dp, vertical = 1.dp),
        )
    }
}

// -- Utilities --

private fun formatFileSize(bytes: Long): String {
    return when {
        bytes >= 1_000_000_000 -> "%.1f GB".format(bytes / 1_000_000_000.0)
        bytes >= 1_000_000 -> "%.0f MB".format(bytes / 1_000_000.0)
        bytes >= 1_000 -> "%.0f KB".format(bytes / 1_000.0)
        else -> "$bytes B"
    }
}
