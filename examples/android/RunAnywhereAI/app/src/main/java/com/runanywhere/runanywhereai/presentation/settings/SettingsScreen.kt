@file:OptIn(kotlin.time.ExperimentalTime::class)

package com.runanywhere.runanywhereai.presentation.settings

import android.text.format.Formatter
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.expandVertically
import androidx.compose.animation.shrinkVertically
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
import com.runanywhere.sdk.models.storage.StoredModel
import kotlinx.datetime.Instant
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

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
fun SettingsScreen(
    viewModel: SettingsViewModel = viewModel()
) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    val context = LocalContext.current
    var showApiKeyDialog by remember { mutableStateOf(false) }
    var showDeleteConfirmDialog by remember { mutableStateOf<StoredModel?>(null) }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
    ) {
        // Header
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = 16.dp, vertical = 16.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                text = "Settings",
                style = MaterialTheme.typography.headlineSmall,
                fontWeight = FontWeight.Bold
            )
        }

        // SDK Configuration Section
        // iOS Reference: Section("SDK Configuration")
        SettingsSection(title = "SDK Configuration") {
            RoutingPolicySelector(
                selectedPolicy = uiState.routingPolicy,
                onPolicyChange = { viewModel.updateRoutingPolicy(it) }
            )
        }

        // Generation Settings Section
        // iOS Reference: Section("Generation Settings")
        SettingsSection(title = "Generation Settings") {
            // Temperature slider
            Column(modifier = Modifier.padding(vertical = 8.dp)) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    Text(
                        text = "Temperature",
                        style = MaterialTheme.typography.bodyMedium
                    )
                    Text(
                        text = String.format("%.2f", uiState.temperature),
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
                Slider(
                    value = uiState.temperature,
                    onValueChange = { viewModel.updateTemperature(it) },
                    valueRange = 0f..2f,
                    steps = 19,
                    colors = SliderDefaults.colors(
                        thumbColor = AppColors.primaryAccent,
                        activeTrackColor = AppColors.primaryAccent
                    )
                )
            }

            HorizontalDivider(modifier = Modifier.padding(vertical = 8.dp))

            // Max Tokens stepper
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(vertical = 8.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = "Max Tokens",
                    style = MaterialTheme.typography.bodyMedium
                )
                Row(verticalAlignment = Alignment.CenterVertically) {
                    IconButton(
                        onClick = { viewModel.updateMaxTokens(uiState.maxTokens - 500) },
                        enabled = uiState.maxTokens > 500
                    ) {
                        Icon(Icons.Default.Remove, "Decrease")
                    }
                    Text(
                        text = uiState.maxTokens.toString(),
                        style = MaterialTheme.typography.bodyMedium,
                        modifier = Modifier.padding(horizontal = 8.dp)
                    )
                    IconButton(
                        onClick = { viewModel.updateMaxTokens(uiState.maxTokens + 500) },
                        enabled = uiState.maxTokens < 20000
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
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable { showApiKeyDialog = true }
                    .padding(vertical = 12.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = "API Key",
                    style = MaterialTheme.typography.bodyMedium
                )
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Text(
                        text = if (uiState.isApiKeyConfigured) "Configured" else "Not Set",
                        style = MaterialTheme.typography.bodySmall,
                        color = if (uiState.isApiKeyConfigured) AppColors.statusGreen else AppColors.statusOrange
                    )
                    Icon(
                        Icons.Default.ChevronRight,
                        contentDescription = "Configure",
                        tint = MaterialTheme.colorScheme.onSurfaceVariant
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
            }
        ) {
            StorageOverviewRow(
                icon = Icons.Outlined.Storage,
                label = "Total Usage",
                value = Formatter.formatFileSize(context, uiState.totalStorageSize)
            )
            HorizontalDivider(modifier = Modifier.padding(vertical = 4.dp))
            StorageOverviewRow(
                icon = Icons.Outlined.CloudQueue,
                label = "Available Space",
                value = Formatter.formatFileSize(context, uiState.availableSpace),
                valueColor = AppColors.primaryGreen
            )
            HorizontalDivider(modifier = Modifier.padding(vertical = 4.dp))
            StorageOverviewRow(
                icon = Icons.Outlined.Memory,
                label = "Models Storage",
                value = Formatter.formatFileSize(context, uiState.modelStorageSize),
                valueColor = AppColors.primaryAccent
            )
            HorizontalDivider(modifier = Modifier.padding(vertical = 4.dp))
            StorageOverviewRow(
                icon = Icons.Outlined.Numbers,
                label = "Downloaded Models",
                value = uiState.downloadedModels.size.toString()
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
                    modifier = Modifier.padding(vertical = 8.dp)
                )
            } else {
                uiState.downloadedModels.forEachIndexed { index, model ->
                    StoredModelRow(
                        model = model,
                        onDelete = { showDeleteConfirmDialog = model }
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
                onClick = { viewModel.clearCache() }
            )
            Spacer(modifier = Modifier.height(8.dp))
            StorageManagementButton(
                title = "Clean Temporary Files",
                icon = Icons.Outlined.CleaningServices,
                color = AppColors.primaryOrange,
                onClick = { viewModel.cleanTempFiles() }
            )
        }

        // Logging Configuration Section
        // iOS Reference: Section("Logging Configuration")
        SettingsSection(title = "Logging Configuration") {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(vertical = 8.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Text(
                    text = "Log Analytics Locally",
                    style = MaterialTheme.typography.bodyMedium
                )
                Switch(
                    checked = uiState.analyticsLogToLocal,
                    onCheckedChange = { viewModel.updateAnalyticsLogging(it) },
                    colors = SwitchDefaults.colors(
                        checkedThumbColor = AppColors.primaryAccent,
                        checkedTrackColor = AppColors.primaryAccent.copy(alpha = 0.5f)
                    )
                )
            }
            Text(
                text = "When enabled, analytics events will be logged locally for debugging purposes.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
        }

        // About Section
        // iOS Reference: About section
        SettingsSection(title = "About") {
            Row(
                modifier = Modifier.padding(vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Icon(
                    Icons.Outlined.Widgets,
                    contentDescription = null,
                    tint = AppColors.primaryAccent
                )
                Spacer(modifier = Modifier.width(12.dp))
                Column {
                    Text(
                        text = "RunAnywhere SDK",
                        style = MaterialTheme.typography.titleSmall,
                        fontWeight = FontWeight.SemiBold
                    )
                    Text(
                        text = "Version 0.1",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )
                }
            }

            HorizontalDivider(modifier = Modifier.padding(vertical = 8.dp))

            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable {
                        // TODO: Open documentation URL
                        // iOS equivalent: Link(destination: URL(string: "https://docs.runanywhere.ai")!)
                    }
                    .padding(vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically
            ) {
                Icon(
                    Icons.Outlined.MenuBook,
                    contentDescription = null,
                    tint = AppColors.primaryAccent
                )
                Spacer(modifier = Modifier.width(12.dp))
                Text(
                    text = "Documentation",
                    style = MaterialTheme.typography.bodyMedium,
                    color = AppColors.primaryAccent
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
            }
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
                        viewModel.deleteModel(model.id)
                        showDeleteConfirmDialog = null
                    },
                    colors = ButtonDefaults.textButtonColors(
                        contentColor = MaterialTheme.colorScheme.error
                    )
                ) {
                    Text("Delete")
                }
            },
            dismissButton = {
                TextButton(onClick = { showDeleteConfirmDialog = null }) {
                    Text("Cancel")
                }
            }
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
    content: @Composable ColumnScope.() -> Unit
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp, vertical = 8.dp)
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Text(
                text = title,
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.SemiBold,
                color = MaterialTheme.colorScheme.onSurfaceVariant
            )
            trailing?.invoke()
        }
        Spacer(modifier = Modifier.height(8.dp))
        Surface(
            modifier = Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(12.dp),
            color = MaterialTheme.colorScheme.surfaceVariant
        ) {
            Column(
                modifier = Modifier.padding(16.dp),
                content = content
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
    onPolicyChange: (RoutingPolicy) -> Unit
) {
    Column {
        Text(
            text = "Routing Policy",
            style = MaterialTheme.typography.bodyMedium,
            modifier = Modifier.padding(bottom = 8.dp)
        )
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(8.dp)
        ) {
            RoutingPolicy.values().forEach { policy ->
                FilterChip(
                    selected = policy == selectedPolicy,
                    onClick = { onPolicyChange(policy) },
                    label = {
                        Text(
                            text = policy.displayName,
                            style = MaterialTheme.typography.labelSmall
                        )
                    },
                    colors = FilterChipDefaults.filterChipColors(
                        selectedContainerColor = AppColors.primaryAccent.copy(alpha = 0.2f),
                        selectedLabelColor = AppColors.primaryAccent
                    )
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
    valueColor: Color = MaterialTheme.colorScheme.onSurfaceVariant
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 4.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(
                imageVector = icon,
                contentDescription = null,
                modifier = Modifier.size(18.dp),
                tint = MaterialTheme.colorScheme.onSurfaceVariant
            )
            Spacer(modifier = Modifier.width(8.dp))
            Text(
                text = label,
                style = MaterialTheme.typography.bodyMedium
            )
        }
        Text(
            text = value,
            style = MaterialTheme.typography.bodyMedium,
            color = valueColor
        )
    }
}

/**
 * Stored Model Row with expandable details
 * iOS Reference: StoredModelRow in CombinedSettingsView (lines 620-765)
 * Uses SDK's StoredModel type directly
 *
 * Features:
 * - Model name and badges (format, framework)
 * - File size display
 * - "Details"/"Hide" toggle button (matching iOS)
 * - Expandable details section showing: format, framework, context length, path, created date, last used
 * - Delete button with confirmation
 */
@Composable
private fun StoredModelRow(
    model: StoredModel,
    onDelete: () -> Unit
) {
    val context = LocalContext.current
    var showingDetails by remember { mutableStateOf(false) }

    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(vertical = 8.dp)
    ) {
        // Main row with model info and actions
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.Top
        ) {
            // Left: Model name and badges
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = model.name,
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.Medium
                )
                Row(
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    modifier = Modifier.padding(top = 4.dp)
                ) {
                    // Format badge
                    Surface(
                        shape = RoundedCornerShape(4.dp),
                        color = AppColors.badgeBlue
                    ) {
                        Text(
                            text = model.format.uppercase(),
                            modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp),
                            style = MaterialTheme.typography.labelSmall,
                            color = AppColors.primaryAccent
                        )
                    }
                    // Framework badge if available
                    model.framework?.let { framework ->
                        Surface(
                            shape = RoundedCornerShape(4.dp),
                            color = AppColors.badgeGreen
                        ) {
                            Text(
                                text = framework,
                                modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp),
                                style = MaterialTheme.typography.labelSmall,
                                color = AppColors.primaryGreen
                            )
                        }
                    }
                }
            }

            // Right: Size and action buttons
            Column(horizontalAlignment = Alignment.End) {
                Text(
                    text = Formatter.formatFileSize(context, model.size),
                    style = MaterialTheme.typography.bodySmall,
                    fontWeight = FontWeight.Medium
                )
                // Action buttons row (matching iOS HStack)
                Row(
                    horizontalArrangement = Arrangement.spacedBy(4.dp),
                    modifier = Modifier.padding(top = 4.dp)
                ) {
                    // Details/Hide button (matching iOS Button with .bordered style)
                    OutlinedButton(
                        onClick = { showingDetails = !showingDetails },
                        modifier = Modifier.height(28.dp),
                        contentPadding = PaddingValues(horizontal = 8.dp, vertical = 0.dp)
                    ) {
                        Text(
                            text = if (showingDetails) "Hide" else "Details",
                            style = MaterialTheme.typography.labelSmall
                        )
                    }
                    // Delete button
                    OutlinedButton(
                        onClick = onDelete,
                        modifier = Modifier.size(28.dp),
                        contentPadding = PaddingValues(0.dp),
                        colors = ButtonDefaults.outlinedButtonColors(
                            contentColor = AppColors.primaryRed
                        )
                    ) {
                        Icon(
                            Icons.Outlined.Delete,
                            contentDescription = "Delete",
                            modifier = Modifier.size(16.dp)
                        )
                    }
                }
            }
        }

        // Expandable details section (matching iOS modelDetailsView)
        AnimatedVisibility(
            visible = showingDetails,
            enter = expandVertically(),
            exit = shrinkVertically()
        ) {
            ModelDetailsView(model = model)
        }
    }
}

/**
 * Model Details View - Expandable details section
 * iOS Reference: modelDetailsView in StoredModelRow (lines 702-764)
 *
 * Shows: format, framework, context length, path, created date, last used
 */
@Composable
private fun ModelDetailsView(model: StoredModel) {
    Surface(
        modifier = Modifier
            .fillMaxWidth()
            .padding(top = 8.dp),
        shape = RoundedCornerShape(8.dp),
        color = MaterialTheme.colorScheme.surface
    ) {
        Column(
            modifier = Modifier.padding(12.dp),
            verticalArrangement = Arrangement.spacedBy(6.dp)
        ) {
            // Format
            ModelDetailRow(label = "Format:", value = model.format.uppercase())

            // Framework
            model.framework?.let { framework ->
                ModelDetailRow(label = "Framework:", value = framework)
            }

            // Context Length
            model.contextLength?.let { contextLength ->
                ModelDetailRow(label = "Context Length:", value = "$contextLength tokens")
            }

            // Path
            Column {
                Text(
                    text = "Path:",
                    style = MaterialTheme.typography.labelSmall,
                    fontWeight = FontWeight.Medium
                )
                Text(
                    text = model.path,
                    style = MaterialTheme.typography.labelSmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(top = 2.dp)
                )
            }

            // Created date
            ModelDetailRow(
                label = "Created:",
                value = formatDate(model.createdDate)
            )

            // Last used (relative time like iOS)
            model.lastUsed?.let { lastUsed ->
                ModelDetailRow(
                    label = "Last used:",
                    value = formatRelativeTime(lastUsed)
                )
            }
        }
    }
}

/**
 * Model Detail Row - Single label/value pair
 */
@Composable
private fun ModelDetailRow(label: String, value: String) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        Text(
            text = label,
            style = MaterialTheme.typography.labelSmall,
            fontWeight = FontWeight.Medium
        )
        Text(
            text = value,
            style = MaterialTheme.typography.labelSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant
        )
    }
}

/**
 * Format date for display (matching iOS Text(date, style: .date))
 */
private fun formatDate(instant: Instant): String {
    return try {
        val dateFormat = SimpleDateFormat("MMM d, yyyy", Locale.getDefault())
        dateFormat.format(Date(instant.toEpochMilliseconds()))
    } catch (e: Exception) {
        "Unknown"
    }
}

/**
 * Format relative time for display (matching iOS Text(date, style: .relative))
 */
private fun formatRelativeTime(instant: Instant): String {
    return try {
        val now = System.currentTimeMillis()
        val then = instant.toEpochMilliseconds()
        val diff = now - then

        val seconds = diff / 1000
        val minutes = seconds / 60
        val hours = minutes / 60
        val days = hours / 24
        val weeks = days / 7
        val months = days / 30
        val years = days / 365

        when {
            years > 0 -> if (years == 1L) "1 year ago" else "$years years ago"
            months > 0 -> if (months == 1L) "1 month ago" else "$months months ago"
            weeks > 0 -> if (weeks == 1L) "1 week ago" else "$weeks weeks ago"
            days > 0 -> if (days == 1L) "1 day ago" else "$days days ago"
            hours > 0 -> if (hours == 1L) "1 hour ago" else "$hours hours ago"
            minutes > 0 -> if (minutes == 1L) "1 minute ago" else "$minutes minutes ago"
            else -> "Just now"
        }
    } catch (e: Exception) {
        "Unknown"
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
    onClick: () -> Unit
) {
    Surface(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick),
        shape = RoundedCornerShape(8.dp),
        color = color.copy(alpha = 0.1f)
    ) {
        Row(
            modifier = Modifier.padding(12.dp),
            verticalAlignment = Alignment.CenterVertically
        ) {
            Icon(
                imageVector = icon,
                contentDescription = null,
                tint = color
            )
            Spacer(modifier = Modifier.width(12.dp))
            Text(
                text = title,
                style = MaterialTheme.typography.bodyMedium,
                color = color
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
    onSave: (String) -> Unit
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
                                contentDescription = if (showPassword) "Hide" else "Show"
                            )
                        }
                    },
                    modifier = Modifier.fillMaxWidth()
                )
                Spacer(modifier = Modifier.height(8.dp))
                Text(
                    text = "Your API key is stored securely",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant
                )
            }
        },
        confirmButton = {
            TextButton(
                onClick = { onSave(apiKey) },
                enabled = apiKey.isNotEmpty()
            ) {
                Text("Save")
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) {
                Text("Cancel")
            }
        }
    )
}

// Note: Using android.text.format.Formatter.formatFileSize() for consistent byte formatting
// This matches iOS ByteCountFormatter behavior
