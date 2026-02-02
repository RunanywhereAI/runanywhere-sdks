package com.runanywhere.runanywhereai.presentation.models

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.runanywhere.runanywhereai.ui.theme.AppColors
import com.runanywhere.runanywhereai.ui.theme.AppTypography
import com.runanywhere.runanywhereai.ui.theme.Dimensions
import com.runanywhere.sdk.core.types.InferenceFramework
import com.runanywhere.sdk.models.DeviceInfo
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.Models.ModelCategory
import com.runanywhere.sdk.public.extensions.Models.ModelFormat
import com.runanywhere.sdk.public.extensions.Models.ModelInfo
import com.runanywhere.sdk.public.extensions.Models.ModelSelectionContext
import com.runanywhere.sdk.public.extensions.loadTTSVoice
import kotlinx.coroutines.launch

/**
 * Model Selection Bottom Sheet - Context-Aware Implementation
 * Reference: iOS ModelSelectionSheet.swift
 *
 * Now supports context-based filtering:
 * - LLM: Shows text generation frameworks (llama.cpp, etc.)
 * - STT: Shows speech recognition frameworks (WhisperKit, etc.)
 * - TTS: Shows text-to-speech frameworks (System TTS, etc.)
 * - VOICE: Shows all voice-related frameworks
 *
 * UI Hierarchy:
 * 1. Navigation Bar (Title + Cancel/Add Model buttons)
 * 2. Main Content List:
 *    - Section 1: Device Status
 *    - Section 2: Available Frameworks (filtered by context)
 *    - Section 3: Models for [Framework] (conditional)
 * 3. Loading Overlay (when loading model)
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ModelSelectionBottomSheet(
    context: ModelSelectionContext = ModelSelectionContext.LLM,
    onDismiss: () -> Unit,
    onModelSelected: suspend (ModelInfo) -> Unit,
    viewModel: ModelSelectionViewModel =
        viewModel(
            // CRITICAL: Use context-specific key to prevent ViewModel caching across contexts
            // Without this key, Compose reuses the same ViewModel instance for STT, LLM, and TTS
            // which causes the wrong models to appear when switching between modalities
            key = "ModelSelectionViewModel_${context.name}",
            factory = ModelSelectionViewModel.Factory(context),
        ),
) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    val scope = rememberCoroutineScope()
    val sheetState =
        rememberModalBottomSheetState(
            skipPartiallyExpanded = true,
        )

    ModalBottomSheet(
        onDismissRequest = { if (!uiState.isLoadingModel) onDismiss() },
        sheetState = sheetState,
        containerColor = MaterialTheme.colorScheme.surface,
    ) {
        Box {
            // Main Content
            LazyColumn(
                modifier =
                    Modifier
                        .fillMaxWidth()
                        .padding(bottom = Dimensions.large),
                contentPadding = PaddingValues(Dimensions.large),
                verticalArrangement = Arrangement.spacedBy(Dimensions.large),
            ) {
                // HEADER - Context-aware title
                item {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        // Cancel button
                        TextButton(
                            onClick = { if (!uiState.isLoadingModel) onDismiss() },
                            enabled = !uiState.isLoadingModel,
                        ) {
                            Text("Cancel")
                        }

                        // Title - uses context title
                        Text(
                            text = uiState.context.title,
                            style = MaterialTheme.typography.titleLarge,
                            fontWeight = FontWeight.Bold,
                        )

                        // Add Model button (placeholder for future)
                        TextButton(
                            onClick = { /* TODO: Add model from URL */ },
                            enabled = false,
                        ) {
                            Text("Add Model")
                        }
                    }
                }

                // SECTION 1: DEVICE STATUS
                item {
                    DeviceStatusSection(deviceInfo = uiState.deviceInfo)
                }

                // SECTION 2: AVAILABLE FRAMEWORKS (Context-filtered)
                item {
                    AvailableFrameworksSection(
                        frameworks = uiState.frameworks,
                        expandedFramework = uiState.expandedFramework,
                        isLoading = uiState.isLoading,
                        onToggleFramework = { viewModel.toggleFramework(it) },
                    )
                }

                // SECTION 3: MODELS FOR [FRAMEWORK] (Conditional)
                if (uiState.expandedFramework != null) {
                    val expandedFw = uiState.expandedFramework!!

                    item {
                        Text(
                            text = if (expandedFw == InferenceFramework.SYSTEM_TTS) "System TTS" else "Models for ${expandedFw.displayName}",
                            style = MaterialTheme.typography.headlineMedium,
                            fontWeight = FontWeight.SemiBold,
                            modifier = Modifier.padding(top = Dimensions.small),
                        )
                    }

                    // Special handling for System TTS (matches iOS ModelSelectionSheet.swift)
                    if (expandedFw == InferenceFramework.SYSTEM_TTS) {
                        item {
                            SystemTTSRow(
                                isLoading = uiState.isLoadingModel,
                                onSelect = {
                                    scope.launch {
                                        viewModel.setLoadingModel(true)
                                        try {
                                            // System TTS doesn't require SDK model loading.
                                            val systemTTSModel =
                                                ModelInfo(
                                                    id = SYSTEM_TTS_MODEL_ID,
                                                    name = "System TTS",
                                                    downloadURL = null,
                                                    format = ModelFormat.UNKNOWN,
                                                    category = ModelCategory.SPEECH_SYNTHESIS,
                                                    framework = InferenceFramework.SYSTEM_TTS,
                                                )

                                            onModelSelected(systemTTSModel)
                                            onDismiss()
                                        } finally {
                                            viewModel.setLoadingModel(false)
                                        }
                                    }
                                },
                            )
                        }
                    } else {
                        // Filter models by expanded framework using enum
                        val filteredModels = viewModel.getModelsForFramework(expandedFw)

                        // Debug logging
                        android.util.Log.d("ModelSelectionSheet", "🔍 Filtering models for framework: ${expandedFw.displayName}")
                        android.util.Log.d("ModelSelectionSheet", "📦 Total models: ${uiState.models.size}")
                        android.util.Log.d("ModelSelectionSheet", "✅ Filtered models: ${filteredModels.size}")

                        if (filteredModels.isEmpty()) {
                            // Empty state
                            item {
                                EmptyModelsMessage(framework = expandedFw)
                            }
                        } else {
                            // Model rows
                            items(filteredModels, key = { it.id }) { model ->
                                SelectableModelRow(
                                    model = model,
                                    isSelected = uiState.currentModel?.id == model.id,
                                    isLoading = uiState.isLoadingModel && uiState.selectedModelId == model.id,
                                    onDownloadModel = {
                                        viewModel.startDownload(model.id)
                                    },
                                    onSelectModel = {
                                        scope.launch {
                                            viewModel.selectModel(model.id)
                                            kotlinx.coroutines.delay(500)
                                            onModelSelected(model)
                                            onDismiss()
                                        }
                                    },
                                )
                            }
                        }
                    }
                }
            }

            // LOADING OVERLAY
            if (uiState.isLoadingModel) {
                LoadingOverlay(
                    modelName = uiState.models.find { it.id == uiState.selectedModelId }?.name ?: "Model",
                    progress = uiState.loadingProgress,
                )
            }
        }
    }
}

// ====================
// SECTION 1: DEVICE STATUS
// ====================

@Composable
private fun DeviceStatusSection(deviceInfo: DeviceInfo?) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(Dimensions.mediumLarge),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant),
    ) {
        Column(
            modifier = Modifier.padding(Dimensions.large),
            verticalArrangement = Arrangement.spacedBy(Dimensions.smallMedium),
        ) {
            Text(
                text = "Device Status",
                style = MaterialTheme.typography.headlineMedium,
                fontWeight = FontWeight.SemiBold,
            )

            if (deviceInfo != null) {
                DeviceInfoRowItem(
                    label = "Model",
                    icon = Icons.Default.PhoneAndroid,
                    value = deviceInfo.modelName,
                )
                DeviceInfoRowItem(
                    label = "Platform",
                    icon = Icons.Default.Memory,
                    value = "${deviceInfo.platform} ${deviceInfo.osVersion}",
                )
                DeviceInfoRowItem(
                    label = "Architecture",
                    icon = Icons.Default.Android,
                    value = deviceInfo.architecture,
                )
                DeviceInfoRowItem(
                    label = "CPU Cores",
                    icon = Icons.Default.Settings,
                    value = deviceInfo.processorCount.toString(),
                )
                DeviceInfoRowItem(
                    label = "Memory",
                    icon = Icons.Default.Memory,
                    value = "${deviceInfo.totalMemoryMB} MB",
                )
            } else {
                Row(
                    horizontalArrangement = Arrangement.spacedBy(Dimensions.small),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    CircularProgressIndicator(modifier = Modifier.size(16.dp))
                    Text(
                        text = "Loading device info...",
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }
    }
}

@Composable
private fun DeviceInfoRowItem(
    label: String,
    icon: ImageVector,
    value: String,
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(Dimensions.small)) {
            Icon(
                imageVector = icon,
                contentDescription = label,
                modifier = Modifier.size(Dimensions.iconSmall),
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Text(label, style = MaterialTheme.typography.bodyLarge)
        }
        Text(
            value,
            style = MaterialTheme.typography.bodyLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

// ====================
// SECTION 2: AVAILABLE FRAMEWORKS
// ====================

@Composable
private fun AvailableFrameworksSection(
    frameworks: List<InferenceFramework>,
    expandedFramework: InferenceFramework?,
    isLoading: Boolean,
    onToggleFramework: (InferenceFramework) -> Unit,
) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(Dimensions.mediumLarge),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant),
    ) {
        Column(
            modifier = Modifier.padding(Dimensions.large),
            verticalArrangement = Arrangement.spacedBy(Dimensions.smallMedium),
        ) {
            Text(
                text = "Available Frameworks",
                style = MaterialTheme.typography.headlineMedium,
                fontWeight = FontWeight.SemiBold,
            )

            when {
                isLoading -> {
                    Row(
                        horizontalArrangement = Arrangement.spacedBy(Dimensions.small),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        CircularProgressIndicator(modifier = Modifier.size(16.dp))
                        Text(
                            text = "Loading frameworks...",
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
                frameworks.isEmpty() -> {
                    Column(verticalArrangement = Arrangement.spacedBy(Dimensions.small)) {
                        Text(
                            text = "No framework adapters are currently registered.",
                            style = AppTypography.caption2,
                            color = MaterialTheme.colorScheme.error,
                        )
                        Text(
                            text = "Register framework adapters to see available frameworks.",
                            style = AppTypography.caption2,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
                else -> {
                    frameworks.forEach { framework ->
                        FrameworkRow(
                            framework = framework,
                            isExpanded = expandedFramework == framework,
                            onTap = { onToggleFramework(framework) },
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun FrameworkRow(
    framework: InferenceFramework,
    isExpanded: Boolean,
    onTap: () -> Unit,
) {
    Row(
        modifier =
            Modifier
                .fillMaxWidth()
                .clickable(onClick = onTap)
                .padding(vertical = Dimensions.small),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Row(
            horizontalArrangement = Arrangement.spacedBy(Dimensions.small),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            // Framework icon - context-aware
            Icon(
                imageVector = getFrameworkIcon(framework),
                contentDescription = null,
                modifier = Modifier.size(Dimensions.iconRegular),
                tint = MaterialTheme.colorScheme.primary,
            )

            Column {
                Text(
                    framework.displayName,
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.Medium,
                )
                Text(
                    getFrameworkDescription(framework),
                    style = AppTypography.caption2,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }

        Icon(
            imageVector = if (isExpanded) Icons.Default.ExpandLess else Icons.Default.ExpandMore,
            contentDescription = if (isExpanded) "Collapse" else "Expand",
            tint = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

/**
 * Get icon for framework - matches iOS iconForFramework
 */
private fun getFrameworkIcon(framework: InferenceFramework): ImageVector {
    return when (framework) {
        InferenceFramework.LLAMA_CPP -> Icons.Default.Memory
        InferenceFramework.ONNX -> Icons.Default.Hub
        InferenceFramework.SYSTEM_TTS -> Icons.Default.VolumeUp
        InferenceFramework.FOUNDATION_MODELS -> Icons.Default.AutoAwesome
        InferenceFramework.FLUID_AUDIO -> Icons.Default.Mic
        InferenceFramework.BUILT_IN -> Icons.Default.Settings
        else -> Icons.Default.Settings
    }
}

/**
 * Get description for framework - matches iOS
 */
private fun getFrameworkDescription(framework: InferenceFramework): String {
    return when (framework) {
        InferenceFramework.LLAMA_CPP -> "High-performance LLM inference"
        InferenceFramework.ONNX -> "ONNX Runtime inference"
        InferenceFramework.SYSTEM_TTS -> "Built-in text-to-speech"
        InferenceFramework.FOUNDATION_MODELS -> "Foundation models"
        InferenceFramework.FLUID_AUDIO -> "FluidAudio synthesis"
        InferenceFramework.BUILT_IN -> "Built-in algorithms"
        InferenceFramework.NONE -> "No framework"
        InferenceFramework.UNKNOWN -> "Unknown framework"
    }
}

// ====================
// SECTION 3: MODELS LIST
// ====================

@Composable
private fun EmptyModelsMessage(framework: InferenceFramework) {
    Column(
        verticalArrangement = Arrangement.spacedBy(Dimensions.small),
        modifier = Modifier.padding(vertical = Dimensions.small),
    ) {
        Text(
            text = "No models available for ${framework.displayName}",
            style = AppTypography.caption,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Text(
            text = "Tap 'Add Model' to add a model from URL",
            style = AppTypography.caption2,
            color = MaterialTheme.colorScheme.primary,
        )
    }
}

@Composable
private fun SelectableModelRow(
    model: ModelInfo,
    isSelected: Boolean,
    isLoading: Boolean,
    onDownloadModel: () -> Unit,
    onSelectModel: () -> Unit,
) {
    // State detection - matches iOS logic
    val isDownloaded = model.isDownloaded
    val canDownload = model.downloadURL != null

    Card(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(Dimensions.medium),
        colors =
            CardDefaults.cardColors(
                containerColor = MaterialTheme.colorScheme.surface,
            ),
    ) {
        Row(
            modifier =
                Modifier
                    .fillMaxWidth()
                    .padding(Dimensions.large),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            // LEFT: Model Info
            Column(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(Dimensions.xSmall),
            ) {
                // Model name
                Text(
                    text = model.name,
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = if (isSelected || isLoading) FontWeight.SemiBold else FontWeight.Normal,
                )

                // Badges row
                Row(
                    horizontalArrangement = Arrangement.spacedBy(Dimensions.smallMedium),
                ) {
                    // Size badge
                    val downloadSize = model.downloadSize ?: 0L
                    if (downloadSize > 0) {
                        ModelBadge(
                            text = formatBytes(downloadSize),
                            icon = Icons.Default.Memory,
                        )
                    }

                    // Format badge
                    ModelBadge(text = model.format.name.uppercase())

                    // Thinking badge
                    if (model.supportsThinking) {
                        ModelBadge(
                            text = "THINKING",
                            icon = Icons.Default.Psychology,
                            backgroundColor = MaterialTheme.colorScheme.secondaryContainer,
                            textColor = MaterialTheme.colorScheme.secondary,
                        )
                    }
                }

                // Status indicator
                Row(
                    horizontalArrangement = Arrangement.spacedBy(Dimensions.xSmall),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    when {
                        isSelected -> {
                            Icon(
                                imageVector = Icons.Default.CheckCircle,
                                contentDescription = "Loaded",
                                modifier = Modifier.size(12.dp),
                                tint = Color(0xFF4CAF50),
                            )
                            Text(
                                text = "Loaded",
                                style = AppTypography.caption2,
                                color = Color(0xFF4CAF50),
                            )
                        }
                        isDownloaded -> {
                            Icon(
                                imageVector = Icons.Default.CheckCircle,
                                contentDescription = "Downloaded",
                                modifier = Modifier.size(12.dp),
                                tint = MaterialTheme.colorScheme.tertiary,
                            )
                            Text(
                                text = "Downloaded",
                                style = AppTypography.caption2,
                                color = MaterialTheme.colorScheme.tertiary,
                            )
                        }
                        canDownload -> {
                            Text(
                                text = "Available for download",
                                style = AppTypography.caption2,
                                color = MaterialTheme.colorScheme.primary,
                            )
                        }
                    }
                }
            }

            Spacer(modifier = Modifier.width(Dimensions.smallMedium))

            // RIGHT: Action button
            when {
                isLoading -> {
                    CircularProgressIndicator(modifier = Modifier.size(24.dp))
                }
                isSelected -> {
                    Row(
                        horizontalArrangement = Arrangement.spacedBy(Dimensions.xSmall),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Icon(
                            imageVector = Icons.Default.CheckCircle,
                            contentDescription = "Loaded",
                            tint = Color(0xFF4CAF50),
                            modifier = Modifier.size(20.dp),
                        )
                        Text(
                            text = "Loaded",
                            style = MaterialTheme.typography.bodyMedium,
                            color = Color(0xFF4CAF50),
                            fontWeight = FontWeight.Medium,
                        )
                    }
                }
                isDownloaded -> {
                    Button(
                        onClick = onSelectModel,
                        enabled = !isLoading,
                        colors =
                            ButtonDefaults.buttonColors(
                                containerColor = MaterialTheme.colorScheme.primary,
                            ),
                    ) {
                        Text("Load")
                    }
                }
                canDownload -> {
                    Button(
                        onClick = onDownloadModel,
                        enabled = !isLoading,
                        colors =
                            ButtonDefaults.buttonColors(
                                containerColor = MaterialTheme.colorScheme.primary,
                            ),
                    ) {
                        Text("Download")
                    }
                }
            }
        }
    }
}

@Composable
private fun ModelBadge(
    text: String,
    icon: ImageVector? = null,
    backgroundColor: Color = MaterialTheme.colorScheme.surfaceVariant,
    textColor: Color = MaterialTheme.colorScheme.onSurface,
) {
    Row(
        modifier =
            Modifier
                .background(backgroundColor, RoundedCornerShape(Dimensions.cornerRadiusSmall))
                .padding(horizontal = Dimensions.small, vertical = Dimensions.xxSmall),
        horizontalArrangement = Arrangement.spacedBy(Dimensions.xxSmall),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        icon?.let {
            Icon(
                imageVector = it,
                contentDescription = null,
                modifier = Modifier.size(10.dp),
                tint = textColor,
            )
        }
        Text(
            text = text,
            style = AppTypography.caption2,
            color = textColor,
        )
    }
}

// ====================
// LOADING OVERLAY
// ====================

@Composable
private fun LoadingOverlay(
    @Suppress("UNUSED_PARAMETER") modelName: String,
    progress: String,
) {
    Box(
        modifier =
            Modifier
                .fillMaxSize()
                .background(MaterialTheme.colorScheme.scrim.copy(alpha = 0.5f)),
        contentAlignment = Alignment.Center,
    ) {
        Card(
            modifier = Modifier.padding(Dimensions.xxLarge),
            shape = RoundedCornerShape(Dimensions.cornerRadiusXLarge),
            colors =
                CardDefaults.cardColors(
                    containerColor = MaterialTheme.colorScheme.surface,
                ),
        ) {
            Column(
                modifier = Modifier.padding(Dimensions.xxLarge),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(Dimensions.xLarge),
            ) {
                CircularProgressIndicator()

                Text(
                    text = "Loading Model",
                    style = MaterialTheme.typography.headlineMedium,
                    fontWeight = FontWeight.Bold,
                )

                Text(
                    text = progress,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

// ====================
// SYSTEM TTS ROW (Matches iOS systemTTSRow)
// ====================

/**
 * System TTS selection row - uses built-in Android TextToSpeech
 * iOS Reference: ModelSelectionSheet.swift - systemTTSRow
 */
@Composable
private fun SystemTTSRow(
    isLoading: Boolean,
    onSelect: () -> Unit,
) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(Dimensions.mediumLarge),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant),
    ) {
        Row(
            modifier =
                Modifier
                    .fillMaxWidth()
                    .padding(Dimensions.large),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween,
        ) {
            Column(
                verticalArrangement = Arrangement.spacedBy(Dimensions.xSmall),
                modifier = Modifier.weight(1f),
            ) {
                Text(
                    text = "Default System Voice",
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.Medium,
                )

                Row(
                    horizontalArrangement = Arrangement.spacedBy(Dimensions.small),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Icon(
                        imageVector = Icons.Default.VolumeUp,
                        contentDescription = null,
                        modifier = Modifier.size(14.dp),
                        tint = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Text(
                        text = "Built-in",
                        style = MaterialTheme.typography.labelSmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )

                    Surface(
                        shape = RoundedCornerShape(4.dp),
                        color = MaterialTheme.colorScheme.surfaceContainerHighest,
                    ) {
                        Text(
                            text = "Android TTS",
                            style = MaterialTheme.typography.labelSmall,
                            modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp),
                        )
                    }
                }

                Row(
                    horizontalArrangement = Arrangement.spacedBy(Dimensions.small),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Icon(
                        imageVector = Icons.Default.CheckCircle,
                        contentDescription = null,
                        modifier = Modifier.size(14.dp),
                        tint = AppColors.primaryGreen,
                    )
                    Text(
                        text = "Always available",
                        style = MaterialTheme.typography.labelSmall,
                        color = AppColors.primaryGreen,
                    )
                }
            }

            Button(
                onClick = onSelect,
                enabled = !isLoading,
                colors =
                    ButtonDefaults.buttonColors(
                        containerColor = AppColors.primaryPurple,
                    ),
                contentPadding = PaddingValues(horizontal = 16.dp, vertical = 8.dp),
            ) {
                Text(
                    text = "Select",
                    style = MaterialTheme.typography.labelMedium,
                )
            }
        }
    }
}

private const val SYSTEM_TTS_MODEL_ID = "system-tts"

// ====================
// UTILITY FUNCTIONS
// ====================

private fun formatBytes(bytes: Long): String {
    val gb = bytes / (1024.0 * 1024.0 * 1024.0)
    return if (gb >= 1.0) {
        String.format("%.2f GB", gb)
    } else {
        val mb = bytes / (1024.0 * 1024.0)
        String.format("%.0f MB", mb)
    }
}
