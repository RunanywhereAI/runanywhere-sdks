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
import com.runanywhere.runanywhereai.ui.theme.AppColors
import com.runanywhere.runanywhereai.ui.theme.AppTypography
import com.runanywhere.runanywhereai.ui.theme.Dimensions
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import kotlinx.coroutines.launch

/**
 * Model Selection Bottom Sheet - Matches iOS ModelSelectionSheet.swift
 *
 * Features:
 * - Device information section
 * - Available frameworks section (expandable)
 * - Models list filtered by framework
 * - Download/Load/Select actions matching iOS
 * - Loading overlay during model loading
 *
 * Reference: iOS ModelSelectionSheet.swift
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
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)

    ModalBottomSheet(
        onDismissRequest = onDismiss,
        sheetState = sheetState,
        containerColor = AppColors.backgroundPrimary
    ) {
        Box {
            LazyColumn(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(bottom = Dimensions.large),
                contentPadding = PaddingValues(Dimensions.large),
                verticalArrangement = Arrangement.spacedBy(Dimensions.large)
            ) {
                // Title
                item {
                    Text(
                        text = "Select Model",
                        style = MaterialTheme.typography.titleLarge,
                        fontWeight = FontWeight.Bold
                    )
                }

                // Device Information Section - Matching iOS
                item {
                    DeviceInformationSection(deviceInfo = uiState.deviceInfo)
                }

                // Available Frameworks Section - Matching iOS
                item {
                    if (uiState.frameworks.isNotEmpty()) {
                        AvailableFrameworksSection(
                            frameworks = uiState.frameworks,
                            expandedFramework = uiState.expandedFramework,
                            onToggleFramework = { viewModel.toggleFramework(it) }
                        )
                    }
                }

                // Models Section - Filtered by expanded framework
                if (uiState.expandedFramework != null) {
                    item {
                        Text(
                            text = "Models for ${uiState.expandedFramework}",
                            style = MaterialTheme.typography.headlineMedium,
                            fontWeight = FontWeight.SemiBold
                        )
                    }

                    val filteredModels = uiState.models.filter { model ->
                        model.compatibleFrameworks.map { it.toString() }.contains(uiState.expandedFramework)
                    }

                    if (filteredModels.isEmpty()) {
                        item {
                            Text(
                                text = "No models available for this framework.\nTap 'Add Model' to add a model from URL.",
                                style = AppTypography.caption,
                                color = AppColors.statusBlue
                            )
                        }
                    } else {
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
                                        onModelSelected(model)
                                        onDismiss()
                                    }
                                }
                            )
                        }
                    }
                }
            }

            // Loading Overlay - Matching iOS
            if (uiState.isLoadingModel) {
                LoadingOverlay(
                    loadingProgress = uiState.loadingProgress
                )
            }
        }
    }
}

/**
 * Device Information Section - Matches iOS deviceStatusSection
 */
@Composable
private fun DeviceInformationSection(deviceInfo: DeviceInfo?) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(Dimensions.mediumLarge),
        colors = CardDefaults.cardColors(containerColor = AppColors.backgroundGray6)
    ) {
        Column(
            modifier = Modifier.padding(Dimensions.large),
            verticalArrangement = Arrangement.spacedBy(Dimensions.smallMedium)
        ) {
            Text(
                text = "Device Information",
                style = MaterialTheme.typography.headlineMedium,
                fontWeight = FontWeight.SemiBold
            )

            if (deviceInfo != null) {
                DeviceInfoRowLocal(label = "Device", icon = Icons.Default.PhoneAndroid, value = deviceInfo.model)
                DeviceInfoRowLocal(label = "Processor", icon = Icons.Default.Memory, value = deviceInfo.processor)
                DeviceInfoRowLocal(label = "Android", icon = Icons.Default.Android, value = deviceInfo.androidVersion)
                DeviceInfoRowLocal(label = "Cores", icon = Icons.Default.Settings, value = deviceInfo.cores.toString())
            } else {
                Row(
                    horizontalArrangement = Arrangement.spacedBy(Dimensions.small),
                    verticalAlignment = Alignment.CenterVertically
                ) {
                    CircularProgressIndicator(modifier = Modifier.size(16.dp))
                    Text("Loading device info...", color = AppColors.textSecondary)
                }
            }
        }
    }
}

@Composable
private fun DeviceInfoRowLocal(label: String, icon: androidx.compose.ui.graphics.vector.ImageVector, value: String) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween
    ) {
        Row(horizontalArrangement = Arrangement.spacedBy(Dimensions.small)) {
            Icon(
                imageVector = icon,
                contentDescription = label,
                modifier = Modifier.size(Dimensions.iconSmall),
                tint = AppColors.textSecondary
            )
            Text(label, style = MaterialTheme.typography.bodyLarge)
        }
        Text(value, style = MaterialTheme.typography.bodyLarge, color = AppColors.textSecondary)
    }
}

/**
 * Available Frameworks Section - Matches iOS frameworksSection
 */
@Composable
private fun AvailableFrameworksSection(
    frameworks: List<String>,
    expandedFramework: String?,
    onToggleFramework: (String) -> Unit
) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(Dimensions.mediumLarge),
        colors = CardDefaults.cardColors(containerColor = AppColors.backgroundGray6)
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

            if (frameworks.isEmpty()) {
                Text(
                    text = "No framework adapters are currently registered. Register framework adapters to see available frameworks.",
                    style = AppTypography.caption2,
                    color = AppColors.statusOrange
                )
            } else {
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
        Column {
            Text(framework, style = MaterialTheme.typography.bodyMedium, fontWeight = FontWeight.Medium)
            Text("High-performance inference", style = AppTypography.caption2, color = AppColors.textSecondary)
        }
        Icon(
            imageVector = if (isExpanded) Icons.Default.ExpandLess else Icons.Default.ExpandMore,
            contentDescription = if (isExpanded) "Collapse" else "Expand"
        )
    }
}

/**
 * Selectable Model Row - Matches iOS SelectableModelRow
 */
@Composable
private fun SelectableModelRow(
    model: com.runanywhere.sdk.models.ModelInfo,
    isLoading: Boolean,
    onDownloadModel: () -> Unit,
    onSelectModel: () -> Unit
) {
    Card(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(Dimensions.medium),
        colors = CardDefaults.cardColors(containerColor = AppColors.backgroundGray5)
    ) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(Dimensions.large),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Column(
                modifier = Modifier.weight(1f),
                verticalArrangement = Arrangement.spacedBy(Dimensions.xSmall)
            ) {
                Text(
                    text = model.name,
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = if (isLoading) FontWeight.SemiBold else FontWeight.Normal
                )

                Row(
                    horizontalArrangement = Arrangement.spacedBy(Dimensions.smallMedium)
                ) {
                    // Size badge
                    val memReq = model.memoryRequired ?: 0L
                    if (memReq > 0) {
                        Badge(
                            text = formatBytes(memReq),
                            icon = Icons.Default.Memory,
                            backgroundColor = AppColors.badgeGray
                        )
                    }

                    // Format badge
                    Badge(
                        text = model.format.name.uppercase(),
                        backgroundColor = AppColors.badgeGray
                    )

                    // Thinking badge
                    if (model.supportsThinking) {
                        Badge(
                            text = "THINKING",
                            icon = Icons.Default.Psychology,
                            backgroundColor = AppColors.badgePurple,
                            textColor = AppColors.primaryPurple
                        )
                    }
                }

                // Download status
                if (model.localPath == null && model.downloadURL != null) {
                    Text(
                        text = "Available for download",
                        style = AppTypography.caption2,
                        color = AppColors.statusBlue
                    )
                } else if (model.localPath != null) {
                    Row(horizontalArrangement = Arrangement.spacedBy(Dimensions.xSmall)) {
                        Icon(
                            imageVector = Icons.Default.CheckCircle,
                            contentDescription = "Downloaded",
                            modifier = Modifier.size(12.dp),
                            tint = AppColors.statusGreen
                        )
                        Text(
                            text = "Downloaded",
                            style = AppTypography.caption2,
                            color = AppColors.statusGreen
                        )
                    }
                }
            }

            Spacer(modifier = Modifier.width(Dimensions.smallMedium))

            // Action button
            if (model.localPath == null && model.downloadURL != null) {
                Button(
                    onClick = onDownloadModel,
                    enabled = !isLoading,
                    colors = ButtonDefaults.buttonColors(containerColor = AppColors.primaryBlue)
                ) {
                    Text("Download")
                }
            } else if (model.localPath != null) {
                Button(
                    onClick = onSelectModel,
                    enabled = !isLoading,
                    colors = ButtonDefaults.buttonColors(containerColor = AppColors.primaryBlue)
                ) {
                    Text("Select")
                }
            }
        }
    }
}

@Composable
private fun Badge(
    text: String,
    icon: androidx.compose.ui.graphics.vector.ImageVector? = null,
    backgroundColor: Color,
    textColor: Color = AppColors.textPrimary
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

/**
 * Loading Overlay - Matches iOS loadingOverlay
 */
@Composable
private fun LoadingOverlay(loadingProgress: String) {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(Color.Black.copy(alpha = 0.5f)),
        contentAlignment = Alignment.Center
    ) {
        Card(
            modifier = Modifier.padding(Dimensions.xxLarge),
            shape = RoundedCornerShape(Dimensions.cornerRadiusXLarge),
            colors = CardDefaults.cardColors(containerColor = AppColors.backgroundPrimary)
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
                    text = loadingProgress,
                    style = MaterialTheme.typography.bodyMedium,
                    color = AppColors.textSecondary
                )
            }
        }
    }
}

private fun formatBytes(bytes: Long): String {
    val gb = bytes / (1024.0 * 1024.0 * 1024.0)
    return if (gb >= 1.0) {
        String.format("%.2f GB", gb)
    } else {
        val mb = bytes / (1024.0 * 1024.0)
        String.format("%.0f MB", mb)
    }
}
