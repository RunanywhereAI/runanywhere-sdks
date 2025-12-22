@file:OptIn(kotlin.time.ExperimentalTime::class)

package com.runanywhere.runanywhereai.presentation.settings

import android.text.format.Formatter
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.runanywhere.runanywhereai.ui.theme.AppColors

/**
 * Combined Settings & Storage Screen - Matching iOS CombinedSettingsView.swift exactly
 *
 * iOS Reference: examples/ios/RunAnywhereAI/RunAnywhereAI/Features/Settings/CombinedSettingsView.swift
 *
 * Sections:
 * 1. SDK Configuration (Routing Policy)
 * 2. Generation Settings (Temperature, Max Tokens)
 * 3. API Configuration (API Key)
 * 4. Storage Overview
 * 5. Downloaded Models
 * 6. Storage Management
 * 7. Logging Configuration
 * 8. About
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(viewModel: SettingsViewModel = viewModel()) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    val context = LocalContext.current
    var showApiKeyDialog by remember { mutableStateOf(false) }
    var showDeleteConfirmDialog by remember { mutableStateOf<StoredModelInfo?>(null) }

    Column(
        modifier =
            Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState()),
    ) {
        // Header
        Row(
            modifier =
                Modifier
                    .fillMaxWidth()
                    .padding(horizontal = 16.dp, vertical = 16.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                text = "Settings",
                style = MaterialTheme.typography.headlineSmall,
                fontWeight = FontWeight.Bold,
            )
        }

        // SDK Configuration Section
        // iOS Reference: Section("SDK Configuration")
        SettingsSection(title = "SDK Configuration") {
            RoutingPolicySelector(
                selectedPolicy = uiState.routingPolicy,
                onPolicyChange = { viewModel.updateRoutingPolicy(it) },
            )
        }

        // Generation Settings Section
        // iOS Reference: Section("Generation Settings")
        SettingsSection(title = "Generation Settings") {
            // Temperature slider
            Column(modifier = Modifier.padding(vertical = 8.dp)) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                ) {
                    Text(
                        text = "Temperature",
                        style = MaterialTheme.typography.bodyMedium,
                    )
                    Text(
                        text = String.format("%.2f", uiState.temperature),
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                Slider(
                    value = uiState.temperature,
                    onValueChange = { viewModel.updateTemperature(it) },
                    valueRange = 0f..2f,
                    steps = 19,
                    colors =
                        SliderDefaults.colors(
                            thumbColor = AppColors.primaryAccent,
                            activeTrackColor = AppColors.primaryAccent,
                        ),
                )
            }

            HorizontalDivider(modifier = Modifier.padding(vertical = 8.dp))

            // Max Tokens stepper
            Row(
                modifier =
                    Modifier
                        .fillMaxWidth()
                        .padding(vertical = 8.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    text = "Max Tokens",
                    style = MaterialTheme.typography.bodyMedium,
                )
                Row(verticalAlignment = Alignment.CenterVertically) {
                    IconButton(
                        onClick = { viewModel.updateMaxTokens(uiState.maxTokens - 500) },
                        enabled = uiState.maxTokens > 500,
                    ) {
                        Icon(Icons.Default.Remove, "Decrease")
                    }
                    Text(
                        text = uiState.maxTokens.toString(),
                        style = MaterialTheme.typography.bodyMedium,
                        modifier = Modifier.padding(horizontal = 8.dp),
                    )
                    IconButton(
                        onClick = { viewModel.updateMaxTokens(uiState.maxTokens + 500) },
                        enabled = uiState.maxTokens < 20000,
                    ) {
                        Icon(Icons.Default.Add, "Increase")
                    }
                }
            }
        }

        // API Configuration Section
        // iOS Reference: Section("API Configuration")
        SettingsSection(title = "API Configuration") {
            Row(
                modifier =
                    Modifier
                        .fillMaxWidth()
                        .clickable { showApiKeyDialog = true }
                        .padding(vertical = 12.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    text = "API Key",
                    style = MaterialTheme.typography.bodyMedium,
                )
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        text = if (uiState.isApiKeyConfigured) "Configured" else "Not Set",
                        style = MaterialTheme.typography.bodySmall,
                        color = if (uiState.isApiKeyConfigured) AppColors.statusGreen else AppColors.statusOrange,
                    )
                    Icon(
                        Icons.Default.ChevronRight,
                        contentDescription = "Configure",
                        tint = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }

        // Storage Overview Section
        // iOS Reference: Section with storage stats from RunAnywhere.getStorageInfo()
        SettingsSection(
            title = "Storage Overview",
            trailing = {
                TextButton(onClick = { viewModel.refreshStorage() }) {
                    Text("Refresh", style = MaterialTheme.typography.labelMedium)
                }
            },
        ) {
            StorageOverviewRow(
                icon = Icons.Outlined.Storage,
                label = "Total Usage",
                value = Formatter.formatFileSize(context, uiState.totalStorageSize),
            )
            HorizontalDivider(modifier = Modifier.padding(vertical = 4.dp))
            StorageOverviewRow(
                icon = Icons.Outlined.CloudQueue,
                label = "Available Space",
                value = Formatter.formatFileSize(context, uiState.availableSpace),
                valueColor = AppColors.primaryGreen,
            )
            HorizontalDivider(modifier = Modifier.padding(vertical = 4.dp))
            StorageOverviewRow(
                icon = Icons.Outlined.Memory,
                label = "Models Storage",
                value = Formatter.formatFileSize(context, uiState.modelStorageSize),
                valueColor = AppColors.primaryAccent,
            )
            HorizontalDivider(modifier = Modifier.padding(vertical = 4.dp))
            StorageOverviewRow(
                icon = Icons.Outlined.Numbers,
                label = "Downloaded Models",
                value = uiState.downloadedModels.size.toString(),
            )
        }

        // Downloaded Models Section
        // iOS Reference: Section("Downloaded Models")
        SettingsSection(title = "Downloaded Models") {
            if (uiState.downloadedModels.isEmpty()) {
                Text(
                    text = "No models downloaded yet",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(vertical = 8.dp),
                )
            } else {
                uiState.downloadedModels.forEachIndexed { index, model ->
                    StoredModelRow(
                        model = model,
                        onDelete = { showDeleteConfirmDialog = model },
                    )
                    if (index < uiState.downloadedModels.lastIndex) {
                        HorizontalDivider(modifier = Modifier.padding(vertical = 4.dp))
                    }
                }
            }
        }

        // Storage Management Section
        // iOS Reference: Section("Storage Management")
        SettingsSection(title = "Storage Management") {
            StorageManagementButton(
                title = "Clear Cache",
                icon = Icons.Outlined.DeleteSweep,
                color = AppColors.primaryRed,
                onClick = { viewModel.clearCache() },
            )
            Spacer(modifier = Modifier.height(8.dp))
            StorageManagementButton(
                title = "Clean Temporary Files",
                icon = Icons.Outlined.CleaningServices,
                color = AppColors.primaryOrange,
                onClick = { viewModel.cleanTempFiles() },
            )
        }

        // Logging Configuration Section
        // iOS Reference: Section("Logging Configuration")
        SettingsSection(title = "Logging Configuration") {
            Row(
                modifier =
                    Modifier
                        .fillMaxWidth()
                        .padding(vertical = 8.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    text = "Log Analytics Locally",
                    style = MaterialTheme.typography.bodyMedium,
                )
                Switch(
                    checked = uiState.analyticsLogToLocal,
                    onCheckedChange = { viewModel.updateAnalyticsLogging(it) },
                    colors =
                        SwitchDefaults.colors(
                            checkedThumbColor = AppColors.primaryAccent,
                            checkedTrackColor = AppColors.primaryAccent.copy(alpha = 0.5f),
                        ),
                )
            }
            Text(
                text = "When enabled, analytics events will be logged locally for debugging purposes.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }

        // About Section
        // iOS Reference: About section
        SettingsSection(title = "About") {
            Row(
                modifier = Modifier.padding(vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(
                    Icons.Outlined.Widgets,
                    contentDescription = null,
                    tint = AppColors.primaryAccent,
                )
                Spacer(modifier = Modifier.width(12.dp))
                Column {
                    Text(
                        text = "RunAnywhere SDK",
                        style = MaterialTheme.typography.titleSmall,
                        fontWeight = FontWeight.SemiBold,
                    )
                    Text(
                        text = "Version 0.1",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }

            HorizontalDivider(modifier = Modifier.padding(vertical = 8.dp))

            Row(
                modifier =
                    Modifier
                        .fillMaxWidth()
                        .clickable {
                            // TODO: Open documentation URL
                            // iOS equivalent: Link(destination: URL(string: "https://docs.runanywhere.ai")!)
                        }
                        .padding(vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Icon(
                    Icons.Outlined.MenuBook,
                    contentDescription = null,
                    tint = AppColors.primaryAccent,
                )
                Spacer(modifier = Modifier.width(12.dp))
                Text(
                    text = "Documentation",
                    style = MaterialTheme.typography.bodyMedium,
                    color = AppColors.primaryAccent,
                )
            }
        }

        Spacer(modifier = Modifier.height(32.dp))
    }

    // API Key Dialog
    if (showApiKeyDialog) {
        ApiKeyDialog(
            currentApiKey = uiState.apiKey,
            onDismiss = { showApiKeyDialog = false },
            onSave = { apiKey ->
                viewModel.updateApiKey(apiKey)
                showApiKeyDialog = false
            },
        )
    }

    // Delete Confirmation Dialog
    showDeleteConfirmDialog?.let { model ->
        AlertDialog(
            onDismissRequest = { showDeleteConfirmDialog = null },
            title = { Text("Delete Model") },
            text = {
                Text("Are you sure you want to delete ${model.name}? This action cannot be undone.")
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        viewModel.deleteModelById(model.id)
                        showDeleteConfirmDialog = null
                    },
                    colors =
                        ButtonDefaults.textButtonColors(
                            contentColor = MaterialTheme.colorScheme.error,
                        ),
                ) {
                    Text("Delete")
                }
            },
            dismissButton = {
                TextButton(onClick = { showDeleteConfirmDialog = null }) {
                    Text("Cancel")
                }
            },
        )
    }
}

/**
 * Settings Section wrapper
 * iOS Reference: settingsCard ViewBuilder
 */
@Composable
private fun SettingsSection(
    title: String,
    trailing: @Composable (() -> Unit)? = null,
    content: @Composable ColumnScope.() -> Unit,
) {
    Column(
        modifier =
            Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 8.dp),
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                text = title,
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.SemiBold,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            trailing?.invoke()
        }
        Spacer(modifier = Modifier.height(8.dp))
        Surface(
            modifier = Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(12.dp),
            color = MaterialTheme.colorScheme.surfaceVariant,
        ) {
            Column(
                modifier = Modifier.padding(16.dp),
                content = content,
            )
        }
    }
}

/**
 * Routing Policy Selector
 * iOS Reference: Picker for Routing Policy
 */
@Composable
private fun RoutingPolicySelector(
    selectedPolicy: RoutingPolicy,
    onPolicyChange: (RoutingPolicy) -> Unit,
) {
    Column {
        Text(
            text = "Routing Policy",
            style = MaterialTheme.typography.bodyMedium,
            modifier = Modifier.padding(bottom = 8.dp),
        )
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            RoutingPolicy.values().forEach { policy ->
                FilterChip(
                    selected = policy == selectedPolicy,
                    onClick = { onPolicyChange(policy) },
                    label = {
                        Text(
                            text = policy.displayName,
                            style = MaterialTheme.typography.labelSmall,
                        )
                    },
                    colors =
                        FilterChipDefaults.filterChipColors(
                            selectedContainerColor = AppColors.primaryAccent.copy(alpha = 0.2f),
                            selectedLabelColor = AppColors.primaryAccent,
                        ),
                )
            }
        }
    }
}

/**
 * Storage Overview Row
 * iOS Reference: HStack with Label and value
 */
@Composable
private fun StorageOverviewRow(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    label: String,
    value: String,
    valueColor: Color = MaterialTheme.colorScheme.onSurfaceVariant,
) {
    Row(
        modifier =
            Modifier
                .fillMaxWidth()
                .padding(vertical = 4.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(
                imageVector = icon,
                contentDescription = null,
                modifier = Modifier.size(18.dp),
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Spacer(modifier = Modifier.width(8.dp))
            Text(
                text = label,
                style = MaterialTheme.typography.bodyMedium,
            )
        }
        Text(
            text = value,
            style = MaterialTheme.typography.bodyMedium,
            color = valueColor,
        )
    }
}

/**
 * Stored Model Row - Simplified version using local StoredModelInfo
 *
 * Features:
 * - Model name display
 * - File size display
 * - Delete button with confirmation
 */
@Composable
private fun StoredModelRow(
    model: StoredModelInfo,
    onDelete: () -> Unit,
) {
    val context = LocalContext.current

    Row(
        modifier =
            Modifier
                .fillMaxWidth()
                .padding(vertical = 8.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        // Left: Model name
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = model.name,
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.Medium,
            )
            Text(
                text = "ID: ${model.id}",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }

        // Right: Size and delete button
        Row(
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                text = Formatter.formatFileSize(context, model.size),
                style = MaterialTheme.typography.bodySmall,
                fontWeight = FontWeight.Medium,
            )
            // Delete button
            OutlinedButton(
                onClick = onDelete,
                modifier = Modifier.size(28.dp),
                contentPadding = PaddingValues(0.dp),
                colors =
                    ButtonDefaults.outlinedButtonColors(
                        contentColor = AppColors.primaryRed,
                    ),
            ) {
                Icon(
                    Icons.Outlined.Delete,
                    contentDescription = "Delete",
                    modifier = Modifier.size(16.dp),
                )
            }
        }
    }
}

/**
 * Storage Management Button
 * iOS Reference: storageManagementButton in CombinedSettingsView
 */
@Composable
private fun StorageManagementButton(
    title: String,
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    color: Color,
    onClick: () -> Unit,
) {
    Surface(
        modifier =
            Modifier
                .fillMaxWidth()
                .clickable(onClick = onClick),
        shape = RoundedCornerShape(8.dp),
        color = color.copy(alpha = 0.1f),
    ) {
        Row(
            modifier = Modifier.padding(12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(
                imageVector = icon,
                contentDescription = null,
                tint = color,
            )
            Spacer(modifier = Modifier.width(12.dp))
            Text(
                text = title,
                style = MaterialTheme.typography.bodyMedium,
                color = color,
            )
        }
    }
}

/**
 * API Key Dialog
 * iOS Reference: apiKeySheet in CombinedSettingsView
 */
@Composable
private fun ApiKeyDialog(
    currentApiKey: String,
    onDismiss: () -> Unit,
    onSave: (String) -> Unit,
) {
    var apiKey by remember { mutableStateOf(currentApiKey) }
    var showPassword by remember { mutableStateOf(false) }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("RunAnywhere API Key") },
        text = {
            Column {
                OutlinedTextField(
                    value = apiKey,
                    onValueChange = { apiKey = it },
                    label = { Text("Enter API Key") },
                    singleLine = true,
                    visualTransformation = if (showPassword) VisualTransformation.None else PasswordVisualTransformation(),
                    trailingIcon = {
                        IconButton(onClick = { showPassword = !showPassword }) {
                            Icon(
                                imageVector = if (showPassword) Icons.Default.VisibilityOff else Icons.Default.Visibility,
                                contentDescription = if (showPassword) "Hide" else "Show",
                            )
                        }
                    },
                    modifier = Modifier.fillMaxWidth(),
                )
                Spacer(modifier = Modifier.height(8.dp))
                Text(
                    text = "Your API key is stored securely",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        },
        confirmButton = {
            TextButton(
                onClick = { onSave(apiKey) },
                enabled = apiKey.isNotEmpty(),
            ) {
                Text("Save")
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) {
                Text("Cancel")
            }
        },
    )
}

// Note: Using android.text.format.Formatter.formatFileSize() for consistent byte formatting
// This matches iOS ByteCountFormatter behavior
