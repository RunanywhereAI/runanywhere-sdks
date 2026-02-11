package com.runanywhere.runanywhereai.presentation.models

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.Download
import androidx.compose.material.icons.outlined.Memory
import androidx.compose.material.icons.outlined.PhoneAndroid
import androidx.compose.material.icons.outlined.Psychology
import androidx.compose.material.icons.outlined.SdStorage
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.runanywhere.runanywhereai.R
import com.runanywhere.runanywhereai.ui.theme.AppColors
import com.runanywhere.runanywhereai.ui.theme.Dimensions
import com.runanywhere.sdk.core.types.InferenceFramework
import com.runanywhere.sdk.models.DeviceInfo
import com.runanywhere.sdk.public.extensions.Models.ModelCategory
import com.runanywhere.sdk.public.extensions.Models.ModelFormat
import com.runanywhere.sdk.public.extensions.Models.ModelInfo
import com.runanywhere.sdk.public.extensions.Models.ModelSelectionContext
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/** Display model for Device Status card. */
private data class DeviceStatus(
    val model: String,
    val chip: String,
    val memory: String,
    val hasNeuralEngine: Boolean,
)

/** Display model for model list row. */
private data class AIModel(
    val name: String,
    val logoResId: Int,
    val format: String,
    val formatColor: Color,
    val size: String,
    val isDownloaded: Boolean,
)

/**
 * Model Selection Bottom Sheet - Context-Aware Implementation
 *
 * Supports context-based filtering (LLM, STT, TTS, VOICE).
 * UI: Header, Device Status card, Choose a Model list, footer note, loading overlay.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ModelSelectionBottomSheet(
    context: ModelSelectionContext = ModelSelectionContext.LLM,
    onDismiss: () -> Unit,
    onModelSelected: suspend (ModelInfo) -> Unit,
    viewModel: ModelSelectionViewModel =
        viewModel(
            key = "ModelSelectionViewModel_${context.name}",
            factory = ModelSelectionViewModel.Factory(context),
        ),
) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    val scope = rememberCoroutineScope()
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    val deviceStatus = uiState.deviceInfo?.let { toDeviceStatus(it) }
        ?: DeviceStatus(model = "—", chip = "—", memory = "—", hasNeuralEngine = false)

    ModalBottomSheet(
        onDismissRequest = { if (!uiState.isLoadingModel) onDismiss() },
        sheetState = sheetState,
        shape = RoundedCornerShape(topStart = 20.dp, topEnd = 20.dp),
        containerColor = MaterialTheme.colorScheme.surfaceContainerLow,
        dragHandle = null,
    ) {
        Box {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .navigationBarsPadding()
                    .verticalScroll(rememberScrollState()),
            ) {
                SheetHeader(title = uiState.context.title, onCancel = { if (!uiState.isLoadingModel) onDismiss() })

                Spacer(modifier = Modifier.height(8.dp))

                SectionLabel("Device Status")
                Spacer(modifier = Modifier.height(8.dp))
                DeviceStatusCard(status = deviceStatus)

                Spacer(modifier = Modifier.height(20.dp))

                SectionLabel("Choose a Model")
                Spacer(modifier = Modifier.height(8.dp))

                if (uiState.isLoading) {
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
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                } else {
                    if (context == ModelSelectionContext.TTS && uiState.frameworks.contains(InferenceFramework.SYSTEM_TTS)) {
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
                        Spacer(modifier = Modifier.height(8.dp))
                    }

                    val sortedModels = uiState.models.sortedWith(
                        compareBy<ModelInfo> { if (it.framework == InferenceFramework.FOUNDATION_MODELS) 0 else if (it.isDownloaded) 1 else 2 }
                            .thenBy { it.name },
                    )
                    sortedModels.forEachIndexed { index, model ->
                        val isBuiltIn = model.framework == InferenceFramework.FOUNDATION_MODELS ||
                            model.framework == InferenceFramework.SYSTEM_TTS
                        val isReady = isBuiltIn || model.isDownloaded
                        ModelCard(
                            model = toAIModel(model),
                            isReady = isReady,
                            isLoading = uiState.isLoadingModel && uiState.selectedModelId == model.id,
                            onCardClick = {
                                if (isReady) {
                                    scope.launch {
                                        viewModel.selectModel(model.id)
                                        var attempts = 0
                                        val maxAttempts = 120
                                        while (viewModel.uiState.value.isLoadingModel && attempts < maxAttempts) {
                                            delay(500)
                                            attempts++
                                        }
                                        if (!viewModel.uiState.value.isLoadingModel) {
                                            onModelSelected(model)
                                        }
                                        onDismiss()
                                    }
                                }
                            },
                            onDownloadClick = {
                                if (!isReady) viewModel.startDownload(model.id)
                            },
                        )
                        if (index < sortedModels.lastIndex) Spacer(modifier = Modifier.height(8.dp))
                    }
                }

                Spacer(modifier = Modifier.height(12.dp))

                Text(
                    text = "All models run privately on your device. Larger models may provide better quality but use more memory.",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(horizontal = 20.dp),
                )

                Spacer(modifier = Modifier.height(24.dp))
            }

            if (uiState.isLoadingModel) {
                LoadingOverlay(
                    modelName = uiState.models.find { it.id == uiState.selectedModelId }?.name ?: "Model",
                    progress = uiState.loadingProgress,
                )
            }
        }
    }
}

private fun toDeviceStatus(info: DeviceInfo): DeviceStatus =
    DeviceStatus(
        model = info.modelName,
        chip = info.architecture,
        memory = "${info.totalMemoryMB} MB",
        hasNeuralEngine = false,
    )

private fun toAIModel(m: ModelInfo): AIModel {
    val formatStr = when (m.framework) {
        InferenceFramework.LLAMA_CPP -> "Fast"
        InferenceFramework.ONNX -> "ONNX"
        InferenceFramework.FOUNDATION_MODELS -> "Apple"
        InferenceFramework.SYSTEM_TTS -> "System"
        else -> m.framework.displayName
    }
    val formatColor = if (m.framework == InferenceFramework.ONNX) AppColors.primaryPurple else AppColors.primaryAccent
    val sizeStr = if (m.downloadSize != null && m.downloadSize!! > 0) formatBytes(m.downloadSize!!) else "—"
    return AIModel(
        name = m.name,
        logoResId = getModelLogoResId(m),
        format = formatStr,
        formatColor = formatColor,
        size = sizeStr,
        isDownloaded = m.isDownloaded || m.framework == InferenceFramework.FOUNDATION_MODELS || m.framework == InferenceFramework.SYSTEM_TTS,
    )
}

/** Drawable resource ID for model logo (matches iOS ModelInfo+Logo). */
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

private fun formatBytes(bytes: Long): String {
    val gb = bytes / (1024.0 * 1024.0 * 1024.0)
    return if (gb >= 1.0) String.format("%.2f GB", gb) else String.format("%.0f MB", bytes / (1024.0 * 1024.0))
}

// ── Header ──

@Composable
private fun SheetHeader(
    title: String,
    onCancel: () -> Unit,
) {
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 14.dp),
    ) {
        TextButton(
            onClick = onCancel,
            modifier = Modifier.align(Alignment.CenterStart),
        ) {
            Text(
                text = "Cancel",
                style = MaterialTheme.typography.bodyLarge,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }

        Text(
            text = title,
            style = MaterialTheme.typography.titleMedium,
            fontWeight = FontWeight.SemiBold,
            modifier = Modifier.align(Alignment.Center),
        )
    }
}

// ── Section Label ──

@Composable
private fun SectionLabel(text: String) {
    Text(
        text = text,
        style = MaterialTheme.typography.bodyMedium,
        fontWeight = FontWeight.Medium,
        color = MaterialTheme.colorScheme.onSurfaceVariant,
        modifier = Modifier.padding(horizontal = 20.dp),
    )
}

// ── Device Status Card ──

@Composable
private fun DeviceStatusCard(status: DeviceStatus) {
    Surface(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp),
        shape = RoundedCornerShape(16.dp),
        color = MaterialTheme.colorScheme.surface,
        tonalElevation = 0.dp,
    ) {
        Column(modifier = Modifier.padding(horizontal = 16.dp)) {
            DeviceStatusRow(
                icon = Icons.Outlined.PhoneAndroid,
                iconTint = AppColors.primaryBlue,
                label = "Model",
                value = status.model,
            )
            RowDivider()
            DeviceStatusRow(
                icon = Icons.Outlined.Memory,
                iconTint = AppColors.primaryBlue,
                label = "Chip",
                value = status.chip,
            )
            RowDivider()
            DeviceStatusRow(
                icon = Icons.Outlined.SdStorage,
                iconTint = AppColors.primaryBlue,
                label = "Memory",
                value = status.memory,
            )
            RowDivider()
            DeviceStatusRow(
                icon = Icons.Outlined.Psychology,
                iconTint = AppColors.primaryBlue,
                label = "Neural Engine",
                trailingContent = {
                    if (status.hasNeuralEngine) {
                        Icon(
                            imageVector = Icons.Outlined.CheckCircle,
                            contentDescription = "Available",
                            modifier = Modifier.size(22.dp),
                            tint = Color(0xFF34C759),
                        )
                    } else {
                        Text(
                            text = "N/A",
                            style = MaterialTheme.typography.bodyMedium,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                },
            )
        }
    }
}

@Composable
private fun DeviceStatusRow(
    icon: ImageVector,
    iconTint: Color,
    label: String,
    value: String? = null,
    trailingContent: @Composable (() -> Unit)? = null,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 14.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            contentAlignment = Alignment.Center,
            modifier = Modifier
                .size(30.dp)
                .clip(RoundedCornerShape(8.dp))
                .background(iconTint.copy(alpha = 0.10f)),
        ) {
            Icon(
                imageVector = icon,
                contentDescription = null,
                modifier = Modifier.size(18.dp),
                tint = iconTint,
            )
        }

        Spacer(modifier = Modifier.width(12.dp))

        Text(
            text = label,
            style = MaterialTheme.typography.bodyLarge,
            fontWeight = FontWeight.Medium,
        )

        Spacer(modifier = Modifier.weight(1f))

        if (trailingContent != null) {
            trailingContent()
        } else if (value != null) {
            Text(
                text = value,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

@Composable
private fun RowDivider() {
    HorizontalDivider(
        color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.5f),
        thickness = 0.5.dp,
        modifier = Modifier.padding(start = 42.dp),
    )
}

// ── Model Card ──

@Composable
private fun ModelCard(
    model: AIModel,
    isReady: Boolean,
    isLoading: Boolean,
    onCardClick: () -> Unit,
    onDownloadClick: () -> Unit,
) {
    Surface(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp)
            .then(
                if (isReady) Modifier.clickable(onClick = onCardClick) else Modifier,
            ),
        shape = RoundedCornerShape(16.dp),
        color = MaterialTheme.colorScheme.surface,
        tonalElevation = 0.dp,
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 14.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Box(
                contentAlignment = Alignment.Center,
                modifier = Modifier
                    .size(40.dp)
                    .clip(RoundedCornerShape(8.dp)),
            ) {
                Image(
                    painter = painterResource(id = model.logoResId),
                    contentDescription = null,
                    modifier = Modifier.fillMaxSize(),
                    contentScale = ContentScale.Fit,
                )
            }

            Spacer(modifier = Modifier.width(12.dp))

            Text(
                text = model.name,
                style = MaterialTheme.typography.bodyLarge,
                fontWeight = FontWeight.SemiBold,
                modifier = Modifier.weight(1f),
            )

            Spacer(modifier = Modifier.width(8.dp))

            Badge(
                text = model.format,
                textColor = model.formatColor,
                backgroundColor = model.formatColor.copy(alpha = 0.10f),
            )

            Spacer(modifier = Modifier.width(8.dp))

            if (model.isDownloaded) {
                Badge(
                    text = "Use",
                    textColor = Color(0xFF34C759),
                    backgroundColor = Color(0xFF34C759).copy(alpha = 0.10f),
                    icon = null,
                )
            } else {
                if (isLoading) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(20.dp),
                        color = AppColors.primaryAccent,
                        strokeWidth = 2.dp,
                    )
                } else {
                    Badge(
                        text = model.size,
                        textColor = AppColors.primaryAccent,
                        backgroundColor = AppColors.primaryAccent.copy(alpha = 0.10f),
                        icon = Icons.Outlined.Download,
                        onClick = onDownloadClick,
                    )
                }
            }
        }
    }
}

// ── Badge ──

@Composable
private fun Badge(
    text: String,
    textColor: Color,
    backgroundColor: Color,
    icon: ImageVector? = null,
    onClick: (() -> Unit)? = null,
) {
    val modifier =
        Modifier
            .clip(RoundedCornerShape(8.dp))
            .background(backgroundColor)
            .then(
                if (onClick != null) Modifier.clickable(onClick = onClick) else Modifier,
            )
            .padding(horizontal = 8.dp, vertical = 4.dp)
    Row(
        verticalAlignment = Alignment.CenterVertically,
        modifier = modifier,
    ) {
        if (icon != null) {
            Icon(
                imageVector = icon,
                contentDescription = null,
                modifier = Modifier.size(14.dp),
                tint = textColor,
            )
            Spacer(modifier = Modifier.width(4.dp))
        }
        Text(
            text = text,
            style = MaterialTheme.typography.labelMedium.copy(fontWeight = FontWeight.SemiBold),
            color = textColor,
        )
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

// SystemTTSRow: card-style row matching ModelCard, "Use" action
@Composable
private fun SystemTTSRow(
    isLoading: Boolean,
    onSelect: () -> Unit,
) {
    Surface(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp)
            .clickable(enabled = !isLoading, onClick = onSelect),
        shape = RoundedCornerShape(16.dp),
        color = MaterialTheme.colorScheme.surface,
        tonalElevation = 0.dp,
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 14.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Box(
                contentAlignment = Alignment.Center,
                modifier = Modifier
                    .size(40.dp)
                    .clip(CircleShape)
                    .background(AppColors.primaryAccent.copy(alpha = 0.08f)),
            ) {
                Text(text = "🔊", style = MaterialTheme.typography.titleSmall)
            }
            Spacer(modifier = Modifier.width(12.dp))
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = "System Voice",
                    style = MaterialTheme.typography.bodyLarge,
                    fontWeight = FontWeight.SemiBold,
                )
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(4.dp),
                ) {
                    Icon(
                        imageVector = Icons.Outlined.CheckCircle,
                        contentDescription = null,
                        modifier = Modifier.size(12.dp),
                        tint = Color(0xFF34C759),
                    )
                    Text(
                        text = "Built-in - Always available",
                        style = MaterialTheme.typography.bodySmall,
                        color = Color(0xFF34C759),
                    )
                }
            }
            Badge(
                text = "System",
                textColor = AppColors.primaryAccent,
                backgroundColor = AppColors.primaryAccent.copy(alpha = 0.10f),
            )
        }
    }
}

private const val SYSTEM_TTS_MODEL_ID = "system-tts"
