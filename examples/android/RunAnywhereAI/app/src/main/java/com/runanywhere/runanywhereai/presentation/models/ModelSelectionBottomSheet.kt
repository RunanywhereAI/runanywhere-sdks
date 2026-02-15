package com.runanywhere.runanywhereai.presentation.models

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.layout.ContentScale
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material.icons.outlined.Download
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.runanywhere.runanywhereai.R
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
                // HEADER - toolbar: Cancel only, title in center
                item {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        TextButton(
                            onClick = { if (!uiState.isLoadingModel) onDismiss() },
                            enabled = !uiState.isLoadingModel,
                        ) {
                            Text("Cancel", style = AppTypography.caption, fontWeight = FontWeight.Medium)
                        }
                        Text(
                            text = uiState.context.title,
                            style = MaterialTheme.typography.titleMedium,
                            fontWeight = FontWeight.SemiBold,
                        )
                        Spacer(modifier = Modifier.width(64.dp))
                    }
                }

                // SECTION 1: Device Status
                item {
                    DeviceStatusSection(deviceInfo = uiState.deviceInfo)
                }

                // SECTION 2: Choose a Model
                item {
                    Text(
                        text = "Choose a Model",
                        style = MaterialTheme.typography.headlineMedium,
                        fontWeight = FontWeight.SemiBold,
                        color = MaterialTheme.colorScheme.onSurface,
                    )
                }

                if (uiState.isLoading) {
                    item {
                        Column(
                            modifier = Modifier
                                .fillMaxWidth()
                                .padding(vertical = Dimensions.xLarge),
                            horizontalAlignment = Alignment.CenterHorizontally,
                            verticalArrangement = Arrangement.spacedBy(Dimensions.mediumLarge),
                        ) {
                            CircularProgressIndicator(modifier = Modifier.size(24.dp))
                            Text(
                                text = "Loading available models...",
                                style = MaterialTheme.typography.bodyMedium,
                                color = AppColors.textSecondary,
                            )
                        }
                    }
                } else {
                    // System TTS row first when TTS context
                    if (context == ModelSelectionContext.TTS && uiState.frameworks.contains(InferenceFramework.SYSTEM_TTS)) {
                        item {
                            SystemTTSRow(
                                isLoading = uiState.isLoadingModel,
                                onSelect = {
                                    scope.launch {
                                        viewModel.setLoadingModel(true)
                                        try {
                                            val systemTTSModel = ModelInfo(
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
                    }

                    val sortedModels = uiState.models.sortedWith(
                        compareBy<ModelInfo> { if (it.framework == InferenceFramework.FOUNDATION_MODELS) 0 else if (it.isDownloaded) 1 else 2 }
                            .thenBy { it.name },
                    )
                    items(sortedModels, key = { it.id }) { model ->
                        SelectableModelRow(
                            model = model,
                            isSelected = uiState.currentModel?.id == model.id,
                            isLoading = uiState.isLoadingModel && uiState.selectedModelId == model.id,
                            onDownloadModel = { viewModel.startDownload(model.id) },
                            onSelectModel = {
                                scope.launch {
                                    viewModel.selectModel(model.id)
                                    // Wait for model to actually finish loading instead of fixed delay
                                    // Poll until loading completes (with timeout to prevent infinite wait)
                                    var attempts = 0
                                    val maxAttempts = 120 // 60 seconds max (500ms * 120)
                                    while (viewModel.uiState.value.isLoadingModel && attempts < maxAttempts) {
                                        kotlinx.coroutines.delay(500)
                                        attempts++
                                    }
                                    // Only notify success if loading completed (not timed out while still loading)
                                    if (!viewModel.uiState.value.isLoadingModel) {
                                        onModelSelected(model)
                                    }
                                    onDismiss()
                                }
                            },
                        )
                    }

                    item {
                        Text(
                            text = "All models run privately on your device. Larger models may provide better quality but use more memory.",
                            style = AppTypography.caption,
                            color = AppColors.textSecondary,
                            modifier = Modifier.padding(top = Dimensions.mediumLarge),
                        )
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

// Device Status section
@Composable
private fun DeviceStatusSection(deviceInfo: DeviceInfo?) {
    Column(
        modifier = Modifier.fillMaxWidth(),
        verticalArrangement = Arrangement.spacedBy(Dimensions.smallMedium),
    ) {
        Text(
            text = "Device Status",
            style = MaterialTheme.typography.headlineMedium,
            fontWeight = FontWeight.SemiBold,
            color = MaterialTheme.colorScheme.onSurface,
        )

        if (deviceInfo != null) {
            // Device info: Model, Chip, Memory
            DeviceInfoRow(label = "Model", icon = Icons.Default.PhoneAndroid, value = deviceInfo.modelName)
            DeviceInfoRow(label = "Chip", icon = Icons.Default.Memory, value = deviceInfo.architecture)
            DeviceInfoRow(
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
                    style = MaterialTheme.typography.bodyMedium,
                    color = AppColors.textSecondary,
                )
            }
        }
    }
}

// DeviceInfoRow: Label + Spacer + Text(value).foregroundColor(AppColors.textSecondary)
@Composable
private fun DeviceInfoRow(
    label: String,
    icon: ImageVector,
    value: String,
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Row(
            horizontalArrangement = Arrangement.spacedBy(Dimensions.small),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(
                imageVector = icon,
                contentDescription = label,
                modifier = Modifier.size(Dimensions.iconRegular),
                tint = MaterialTheme.colorScheme.onSurface,
            )
            Text(label, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurface)
        }
        Text(
            value,
            style = MaterialTheme.typography.bodyMedium,
            color = AppColors.textSecondary,
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
 * Get drawable resource ID for model logo - matches iOS ModelInfo+Logo.swift logoAssetName
 */
private fun getModelLogoResId(model: ModelInfo): Int {
    val name = model.name.lowercase()
    return when {
        model.framework == InferenceFramework.FOUNDATION_MODELS ||
            model.framework == InferenceFramework.SYSTEM_TTS -> R.drawable.foundation_models_logo
        name.contains("llama") -> R.drawable.llama_logo
        name.contains("mistral") -> R.drawable.mistral_logo
        name.contains("qwen") -> R.drawable.qwen_logo
        name.contains("liquid") -> R.drawable.liquid_ai_logo
        name.contains("piper") -> R.drawable.hugging_face_logo
        name.contains("whisper") -> R.drawable.hugging_face_logo
        name.contains("sherpa") -> R.drawable.hugging_face_logo
        else -> R.drawable.hugging_face_logo
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

// FlatModelRow-style row
@Composable
private fun SelectableModelRow(
    model: ModelInfo,
    isSelected: Boolean,
    isLoading: Boolean,
    onDownloadModel: () -> Unit,
    onSelectModel: () -> Unit,
) {
    val isBuiltIn =
        model.framework == InferenceFramework.FOUNDATION_MODELS ||
            model.framework == InferenceFramework.SYSTEM_TTS
    val isDownloaded = model.isDownloaded
    val canDownload = model.downloadURL != null

    val frameworkColor = when (model.framework) {
        InferenceFramework.LLAMA_CPP -> AppColors.primaryAccent
        InferenceFramework.ONNX -> AppColors.primaryPurple
        InferenceFramework.FOUNDATION_MODELS -> MaterialTheme.colorScheme.primary
        InferenceFramework.SYSTEM_TTS -> AppColors.primaryAccent
        else -> AppColors.statusGray
    }
    val frameworkName = when (model.framework) {
        InferenceFramework.LLAMA_CPP -> "Fast"
        InferenceFramework.ONNX -> "ONNX"
        InferenceFramework.FOUNDATION_MODELS -> "Apple"
        InferenceFramework.SYSTEM_TTS -> "System"
        else -> model.framework.displayName
    }

    val statusIcon = Icons.Default.CheckCircle
    val statusColor = if (isBuiltIn || isDownloaded) AppColors.statusGreen else AppColors.primaryAccent
    val statusText = when {
        isBuiltIn -> "Built-in"
        isDownloaded -> "Ready"
        else -> ""
    }

    Row(
        modifier =
            Modifier
                .fillMaxWidth()
                .padding(vertical = Dimensions.smallMedium)
                .then(Modifier.alpha(if (isLoading && !isSelected) 0.6f else 1f)),
        horizontalArrangement = Arrangement.spacedBy(Dimensions.mediumLarge),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        // Model logo
        Box(
            modifier =
                Modifier
                    .size(40.dp)
                    .clip(RoundedCornerShape(Dimensions.cornerRadiusRegular)),
        ) {
            Image(
                painter = painterResource(id = getModelLogoResId(model)),
                contentDescription = null,
                modifier = Modifier.fillMaxSize(),
                contentScale = ContentScale.Fit,
            )
        }

        // Model name + framework badge + status row
        Column(
            modifier = Modifier.weight(1f),
            verticalArrangement = Arrangement.spacedBy(Dimensions.xSmall),
        ) {
            Row(
                horizontalArrangement = Arrangement.spacedBy(Dimensions.smallMedium),
                verticalAlignment = Alignment.CenterVertically,
                modifier = Modifier.fillMaxWidth(),
            ) {
                Text(
                    text = model.name,
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.Medium,
                    color = MaterialTheme.colorScheme.onSurface,
                    maxLines = 2,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f),
                )
                Surface(
                    shape = RoundedCornerShape(Dimensions.cornerRadiusSmall),
                    color = frameworkColor.copy(alpha = 0.15f),
                ) {
                    Text(
                        text = frameworkName,
                        style = AppTypography.caption2,
                        fontWeight = FontWeight.Medium,
                        color = frameworkColor,
                        modifier = Modifier.padding(horizontal = Dimensions.small, vertical = Dimensions.xxSmall),
                    )
                }
            }
            Row(
                horizontalArrangement = Arrangement.spacedBy(Dimensions.smallMedium),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                if (statusText.isNotEmpty()) {
                    Row(
                        horizontalArrangement = Arrangement.spacedBy(Dimensions.xxSmall),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Icon(
                            imageVector = statusIcon,
                            contentDescription = null,
                            modifier = Modifier.size(12.dp),
                            tint = statusColor,
                        )
                        Text(
                            text = statusText,
                            style = AppTypography.caption2,
                            color = statusColor,
                        )
                    }
                }
                if (model.supportsThinking) {
                    Surface(
                        shape = RoundedCornerShape(Dimensions.cornerRadiusSmall),
                        color = AppColors.badgePurple,
                    ) {
                        Row(
                            modifier = Modifier.padding(horizontal = Dimensions.small, vertical = Dimensions.xxSmall),
                            horizontalArrangement = Arrangement.spacedBy(Dimensions.xxSmall),
                            verticalAlignment = Alignment.CenterVertically,
                        ) {
                            Icon(
                                imageVector = Icons.Default.Psychology,
                                contentDescription = null,
                                modifier = Modifier.size(10.dp),
                                tint = AppColors.primaryPurple,
                            )
                            Text(
                                text = "Smart",
                                style = AppTypography.caption2,
                                color = AppColors.primaryPurple,
                            )
                        }
                    }
                }
            }
        }

        // Action button: "Use" (borderedProminent primaryAccent) or "Get" (bordered primaryAccent)
        when {
            isLoading -> CircularProgressIndicator(modifier = Modifier.size(24.dp), color = AppColors.primaryAccent)
            isBuiltIn || isDownloaded -> {
                Button(
                    onClick = onSelectModel,
                    enabled = !isLoading && !isSelected,
                    colors = ButtonDefaults.buttonColors(containerColor = AppColors.primaryAccent),
                    contentPadding = PaddingValues(horizontal = 12.dp, vertical = 6.dp),
                ) {
                    Text("Use", style = AppTypography.caption, fontWeight = FontWeight.SemiBold)
                }
            }
            canDownload -> {
                Button(
                    onClick = onDownloadModel,
                    enabled = !isLoading,
                    colors = ButtonDefaults.outlinedButtonColors(contentColor = AppColors.primaryAccent),
                    contentPadding = PaddingValues(horizontal = 12.dp, vertical = 6.dp),
                ) {
                    Row(
                        horizontalArrangement = Arrangement.spacedBy(Dimensions.xxSmall),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Icon(
                            imageVector = Icons.Outlined.Download,
                            contentDescription = null,
                            modifier = Modifier.size(14.dp),
                        )
                        Text(
                            text =
                                if ((model.downloadSize ?: 0) > 0) {
                                    formatBytes(model.downloadSize!!)
                                } else {
                                    "Get"
                                },
                            style = AppTypography.caption,
                            fontWeight = FontWeight.SemiBold,
                        )
                    }
                }
            }
        }
    }
}

// ====================
// LOADING OVERLAY
// ====================

// LoadingModelOverlay: overlayMedium, card backgroundPrimary, headline + subheadline textSecondary
@Composable
private fun LoadingOverlay(
    @Suppress("UNUSED_PARAMETER") modelName: String,
    progress: String,
) {
    Box(
        modifier =
            Modifier
                .fillMaxSize()
                .background(AppColors.overlayMedium),
        contentAlignment = Alignment.Center,
    ) {
        Card(
            modifier = Modifier.padding(Dimensions.xxLarge),
            shape = RoundedCornerShape(Dimensions.cornerRadiusXLarge),
            colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface),
            elevation = CardDefaults.cardElevation(defaultElevation = Dimensions.shadowXLarge),
        ) {
            Column(
                modifier = Modifier.padding(Dimensions.xxLarge),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(Dimensions.xLarge),
            ) {
                CircularProgressIndicator(
                    modifier = Modifier.size(36.dp),
                    color = AppColors.primaryAccent,
                )
                Text(
                    text = "Loading Model",
                    style = MaterialTheme.typography.headlineMedium,
                    fontWeight = FontWeight.SemiBold,
                    color = MaterialTheme.colorScheme.onSurface,
                )
                Text(
                    text = progress,
                    style = MaterialTheme.typography.bodyMedium,
                    color = AppColors.textSecondary,
                )
            }
        }
    }
}

// ====================
// SYSTEM TTS ROW
// ====================

// SystemTTSRow: "System Voice", "System" badge, "Built-in - Always available", "Use" button primaryAccent
@Composable
private fun SystemTTSRow(
    isLoading: Boolean,
    onSelect: () -> Unit,
) {
    Row(
        modifier =
            Modifier
                .fillMaxWidth()
                .padding(vertical = Dimensions.smallMedium),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.SpaceBetween,
    ) {
        Column(
            modifier = Modifier.weight(1f),
            verticalArrangement = Arrangement.spacedBy(Dimensions.xSmall),
        ) {
            Row(
                horizontalArrangement = Arrangement.spacedBy(Dimensions.smallMedium),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    text = "System Voice",
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.Medium,
                    color = MaterialTheme.colorScheme.onSurface,
                )
                Surface(
                    shape = RoundedCornerShape(Dimensions.cornerRadiusSmall),
                    color = AppColors.primaryAccent.copy(alpha = 0.1f),
                ) {
                    Text(
                        text = "System",
                        style = AppTypography.caption2,
                        fontWeight = FontWeight.Medium,
                        color = AppColors.primaryAccent,
                        modifier = Modifier.padding(horizontal = Dimensions.small, vertical = Dimensions.xxSmall),
                    )
                }
            }
            Row(
                horizontalArrangement = Arrangement.spacedBy(Dimensions.xxSmall),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(
                    imageVector = Icons.Default.CheckCircle,
                    contentDescription = null,
                    modifier = Modifier.size(12.dp),
                    tint = AppColors.statusGreen,
                )
                Text(
                    text = "Built-in - Always available",
                    style = AppTypography.caption2,
                    color = AppColors.statusGreen,
                )
            }
        }
        Button(
            onClick = onSelect,
            enabled = !isLoading,
            colors = ButtonDefaults.buttonColors(containerColor = AppColors.primaryAccent),
            contentPadding = PaddingValues(horizontal = 12.dp, vertical = 6.dp),
        ) {
            Text("Use", style = AppTypography.caption, fontWeight = FontWeight.SemiBold)
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
