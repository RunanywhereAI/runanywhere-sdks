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
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.lifecycle.viewmodel.compose.viewModel
import com.runanywhere.runanywhereai.ui.theme.AppTypography
import com.runanywhere.runanywhereai.ui.theme.Dimensions
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import kotlinx.coroutines.launch

/**
 * Model Selection Bottom Sheet - EXACT iOS Implementation
 * Reference: iOS ModelSelectionSheet.swift
 *
 * UI Hierarchy:
 * 1. Navigation Bar (Title + Cancel/Add Model buttons)
 * 2. Main Content List:
 *    - Section 1: Device Status
 *    - Section 2: Available Frameworks (expandable)
 *    - Section 3: Models for [Framework] (conditional - when framework expanded)
 * 3. Loading Overlay (when loading model)
 *
 * Flow:
 * - User taps "Select Model" from chat screen
 * - Sheet shows device info + available frameworks
 * - User taps framework → expands to show models
 * - User can download (if not downloaded) or select (if downloaded/built-in)
 * - On select: model loads with progress overlay
 * - On success: sheet dismisses, chat updates
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ModelSelectionBottomSheet(
    onDismiss: () -> Unit,
    onModelSelected: suspend (com.runanywhere.sdk.models.ModelInfo) -> Unit,
    viewModel: ModelSelectionViewModel = viewModel()
) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    val scope = rememberCoroutineScope()
    val sheetState = rememberModalBottomSheetState(
        skipPartiallyExpanded = true
    )

    ModalBottomSheet(
        onDismissRequest = { if (!uiState.isLoadingModel) onDismiss() },
        sheetState = sheetState,
        containerColor = MaterialTheme.colorScheme.surface
    ) {
        Box {
            // Main Content
            LazyColumn(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(bottom = Dimensions.large),
                contentPadding = PaddingValues(Dimensions.large),
                verticalArrangement = Arrangement.spacedBy(Dimensions.large)
            ) {
                // HEADER - "Select Model"
                item {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        // Cancel button
                        TextButton(
                            onClick = { if (!uiState.isLoadingModel) onDismiss() },
                            enabled = !uiState.isLoadingModel
                        ) {
                            Text("Cancel")
                        }

                        // Title
                        Text(
                            text = "Select Model",
                            style = MaterialTheme.typography.titleLarge,
                            fontWeight = FontWeight.Bold
                        )

                        // Add Model button (placeholder for future)
                        TextButton(
                            onClick = { /* TODO: Add model from URL */ },
                            enabled = false
                        ) {
                            Text("Add Model")
                        }
                    }
                }

                // SECTION 1: DEVICE STATUS
                item {
                    DeviceStatusSection(deviceInfo = uiState.deviceInfo)
                }

                // SECTION 2: AVAILABLE FRAMEWORKS
                item {
                    AvailableFrameworksSection(
                        frameworks = uiState.frameworks,
                        expandedFramework = uiState.expandedFramework,
                        isLoading = uiState.isLoading,
                        onToggleFramework = { viewModel.toggleFramework(it) }
                    )
                }

                // SECTION 3: MODELS FOR [FRAMEWORK] (Conditional)
                if (uiState.expandedFramework != null) {
                    item {
                        Text(
                            text = "Models for ${uiState.expandedFramework}",
                            style = MaterialTheme.typography.headlineMedium,
                            fontWeight = FontWeight.SemiBold,
                            modifier = Modifier.padding(top = Dimensions.small)
                        )
                    }

                    // Filter models by expanded framework
                    // CRITICAL: Use displayName to match framework names from ViewModel
                    val filteredModels = uiState.models.filter { model ->
                        model.compatibleFrameworks.map { it.displayName }
                            .contains(uiState.expandedFramework)
                    }

                    // Debug logging
                    android.util.Log.d("ModelSelectionSheet", "🔍 Filtering models for framework: ${uiState.expandedFramework}")
                    android.util.Log.d("ModelSelectionSheet", "📦 Total models: ${uiState.models.size}")
                    android.util.Log.d("ModelSelectionSheet", "✅ Filtered models: ${filteredModels.size}")
                    filteredModels.forEach { model ->
                        android.util.Log.d("ModelSelectionSheet", "   - ${model.name} (${model.compatibleFrameworks.map { it.displayName }})")
                    }

                    if (filteredModels.isEmpty()) {
                        // Empty state
                        item {
                            EmptyModelsMessage(framework = uiState.expandedFramework!!)
                        }
                    } else {
                        // Model rows
                        items(filteredModels, key = { it.id }) { model ->
                            SelectableModelRow(
                                model = model,
                                isLoading = uiState.isLoadingModel && uiState.selectedModelId == model.id,
                                onDownloadModel = {
                                    viewModel.downloadModel(model.id)
                                },
                                onSelectModel = {
                                    scope.launch {
                                        viewModel.selectModel(model.id)
                                        // Wait a bit to show success message
                                        kotlinx.coroutines.delay(500)
                                        onModelSelected(model)
                                        onDismiss()
                                    }
                                }
                            )
                        }
                    }
                }
            }

            // LOADING OVERLAY - Matches iOS exactly
            if (uiState.isLoadingModel) {
                LoadingOverlay(
                    modelName = uiState.models.find { it.id == uiState.selectedModelId }?.name ?: "Model",
                    progress = uiState.loadingProgress
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
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant)
    ) {
        Column(
            modifier = Modifier.padding(Dimensions.large),
            verticalArrangement = Arrangement.spacedBy(Dimensions.smallMedium)
        ) {
            Text(
                text = "Device Status",
                style = MaterialTheme.typography.headlineMedium,
                fontWeight = FontWeight.SemiBold
            )

            if (deviceInfo != null) {
                DeviceInfoRowItem(
                    label = "Model",
                    icon = Icons.Default.PhoneAndroid,
                    value = deviceInfo.model
                )
                DeviceInfoRowItem(
                    label = "Processor",
                    icon = Icons.Default.Memory,
                    value = deviceInfo.processor
                )
                DeviceInfoRowItem(
                    label = "Android",
                    icon = Icons.Default.Android,
                    value = deviceInfo.androidVersion
                )
                DeviceInfoRowItem(
                    label = "Cores",
                    icon = Icons.Default.Settings,
                    value = deviceInfo.cores.toString()
                )
            } else {
                Row(
                    horizontalArrangement = Arrangement.spacedBy(Dimensions.small),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    CircularProgressIndicator(modifier = Modifier.size(16.dp))
                    Text(
                        text = "Loading device info...",
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }
        }
    }
}

@Composable
private fun DeviceInfoRowItem(
    label: String,
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    value: String
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(Dimensions.small)) {
            Icon(
                imageVector = icon,
                contentDescription = label,
                modifier = Modifier.size(Dimensions.iconSmall),
                tint = MaterialTheme.colorScheme.onSurfaceVariant
            )
            Text(label, style = MaterialTheme.typography.bodyLarge)
        }
        Text(
            value,
            style = MaterialTheme.typography.bodyLarge,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
}

// ====================
// SECTION 2: AVAILABLE FRAMEWORKS
// ====================

@Composable
private fun AvailableFrameworksSection(
    frameworks: List<String>,
    expandedFramework: String?,
    isLoading: Boolean,
    onToggleFramework: (String) -> Unit
) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(Dimensions.mediumLarge),
        colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surfaceVariant)
    ) {
        Column(
            modifier = Modifier.padding(Dimensions.large),
            verticalArrangement = Arrangement.spacedBy(Dimensions.smallMedium)
        ) {
            Text(
                text = "Available Frameworks",
                style = MaterialTheme.typography.headlineMedium,
                fontWeight = FontWeight.SemiBold
            )

            when {
                isLoading -> {
                    Row(
                        horizontalArrangement = Arrangement.spacedBy(Dimensions.small),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        CircularProgressIndicator(modifier = Modifier.size(16.dp))
                        Text(
                            text = "Loading frameworks...",
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                }
                frameworks.isEmpty() -> {
                    Column(verticalArrangement = Arrangement.spacedBy(Dimensions.small)) {
                        Text(
                            text = "No framework adapters are currently registered.",
                            style = AppTypography.caption2,
                            color = MaterialTheme.colorScheme.error
                        )
                        Text(
                            text = "Register framework adapters to see available frameworks.",
                            style = AppTypography.caption2,
                            color = MaterialTheme.colorScheme.onSurfaceVariant
                        )
                    }
                }
                else -> {
                    frameworks.forEach { framework ->
                        FrameworkRow(
                            framework = framework,
                            isExpanded = expandedFramework == framework,
                            onTap = { onToggleFramework(framework) }
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun FrameworkRow(
    framework: String,
    isExpanded: Boolean,
    onTap: () -> Unit
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onTap)
            .padding(vertical = Dimensions.small),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Row(
            horizontalArrangement = Arrangement.spacedBy(Dimensions.small),
            verticalAlignment = Alignment.CenterVertically
        ) {
            // Framework icon
            Icon(
                imageVector = when (framework.uppercase()) {
                    "LLAMACPP", "LLAMA_CPP" -> Icons.Default.Memory
                    "MEDIAPIPE" -> Icons.Default.Psychology
                    else -> Icons.Default.Settings
                },
                contentDescription = null,
                modifier = Modifier.size(Dimensions.iconRegular),
                tint = MaterialTheme.colorScheme.primary
            )

            Column {
                Text(
                    framework,
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.Medium
                )
                Text(
                    "High-performance inference",
                    style = AppTypography.caption2,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }

        Icon(
            imageVector = if (isExpanded) Icons.Default.ExpandLess else Icons.Default.ExpandMore,
            contentDescription = if (isExpanded) "Collapse" else "Expand",
            tint = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
}

// ====================
// SECTION 3: MODELS LIST
// ====================

@Composable
private fun EmptyModelsMessage(framework: String) {
    Column(
        verticalArrangement = Arrangement.spacedBy(Dimensions.small),
        modifier = Modifier.padding(vertical = Dimensions.small)
    ) {
        Text(
            text = "No models available for this framework",
            style = AppTypography.caption,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
        Text(
            text = "Tap 'Add Model' to add a model from URL",
            style = AppTypography.caption2,
            color = MaterialTheme.colorScheme.primary
        )
    }
}

@Composable
private fun SelectableModelRow(
    model: com.runanywhere.sdk.models.ModelInfo,
    isLoading: Boolean,
    onDownloadModel: () -> Unit,
    onSelectModel: () -> Unit
) {
    val isDownloaded = model.localPath != null
    val canDownload = model.downloadURL != null

    Card(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(Dimensions.medium),
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surface
        )
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(Dimensions.large),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            // LEFT: Model Info
            Column(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(Dimensions.xSmall)
            ) {
                // Model name
                Text(
                    text = model.name,
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = if (isLoading) FontWeight.SemiBold else FontWeight.Normal
                )

                // Badges row
                Row(
                    horizontalArrangement = Arrangement.spacedBy(Dimensions.smallMedium)
                ) {
                    // Size badge
                    val memReq = model.memoryRequired ?: 0L
                    if (memReq > 0) {
                        ModelBadge(
                            text = formatBytes(memReq),
                            icon = Icons.Default.Memory
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
                            textColor = MaterialTheme.colorScheme.secondary
                        )
                    }
                }

                // Status indicator
                Row(
                    horizontalArrangement = Arrangement.spacedBy(Dimensions.xSmall),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    when {
                        isDownloaded -> {
                            Icon(
                                imageVector = Icons.Default.CheckCircle,
                                contentDescription = "Downloaded",
                                modifier = Modifier.size(12.dp),
                                tint = MaterialTheme.colorScheme.tertiary
                            )
                            Text(
                                text = "Downloaded",
                                style = AppTypography.caption2,
                                color = MaterialTheme.colorScheme.tertiary
                            )
                        }
                        canDownload -> {
                            Text(
                                text = "Available for download",
                                style = AppTypography.caption2,
                                color = MaterialTheme.colorScheme.primary
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
                isDownloaded -> {
                    Button(
                        onClick = onSelectModel,
                        enabled = !isLoading,
                        colors = ButtonDefaults.buttonColors(
                            containerColor = MaterialTheme.colorScheme.primary
                        )
                    ) {
                        Text("Select")
                    }
                }
                canDownload -> {
                    Button(
                        onClick = onDownloadModel,
                        enabled = !isLoading,
                        colors = ButtonDefaults.buttonColors(
                            containerColor = MaterialTheme.colorScheme.primary
                        )
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
    icon: androidx.compose.ui.graphics.vector.ImageVector? = null,
    backgroundColor: Color = MaterialTheme.colorScheme.surfaceVariant,
    textColor: Color = MaterialTheme.colorScheme.onSurface
) {
    Row(
        modifier = Modifier
            .background(backgroundColor, RoundedCornerShape(Dimensions.cornerRadiusSmall))
            .padding(horizontal = Dimensions.small, vertical = Dimensions.xxSmall),
        horizontalArrangement = Arrangement.spacedBy(Dimensions.xxSmall),
        verticalAlignment = Alignment.CenterVertically
    ) {
        icon?.let {
            Icon(
                imageVector = it,
                contentDescription = null,
                modifier = Modifier.size(10.dp),
                tint = textColor
            )
        }
        Text(
            text = text,
            style = AppTypography.caption2,
            color = textColor
        )
    }
}

// ====================
// LOADING OVERLAY - Matches iOS
// ====================

@Composable
private fun LoadingOverlay(
    modelName: String,
    progress: String
) {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(MaterialTheme.colorScheme.scrim.copy(alpha = 0.5f)),
        contentAlignment = Alignment.Center
    ) {
        Card(
            modifier = Modifier.padding(Dimensions.xxLarge),
            shape = RoundedCornerShape(Dimensions.cornerRadiusXLarge),
            colors = CardDefaults.cardColors(
                containerColor = MaterialTheme.colorScheme.surface
            )
        ) {
            Column(
                modifier = Modifier.padding(Dimensions.xxLarge),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(Dimensions.xLarge)
            ) {
                CircularProgressIndicator()

                Text(
                    text = "Loading Model",
                    style = MaterialTheme.typography.headlineMedium,
                    fontWeight = FontWeight.Bold
                )

                Text(
                    text = progress,
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        }
    }
}

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
