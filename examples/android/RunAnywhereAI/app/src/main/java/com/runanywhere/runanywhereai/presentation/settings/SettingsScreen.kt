@file:OptIn(kotlin.time.ExperimentalTime::class)

package com.runanywhere.runanywhereai.presentation.settings

import android.app.Application
import android.content.Intent
import android.net.Uri
import android.text.format.Formatter
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material.icons.outlined.*
import androidx.compose.material.icons.filled.Analytics
import androidx.compose.material.icons.filled.CleaningServices
import androidx.compose.material.icons.filled.CloudQueue
import androidx.compose.material.icons.filled.Delete
import androidx.compose.material.icons.filled.DeleteSweep
import androidx.compose.material.icons.filled.Download
import androidx.compose.material.icons.filled.Info
import androidx.compose.material.icons.filled.VpnKey
import androidx.compose.material.icons.filled.MenuBook
import androidx.compose.material.icons.filled.Memory
import androidx.compose.material.icons.filled.FormatListNumbered
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material.icons.filled.Storage
import androidx.compose.material.icons.filled.Tune
import androidx.compose.material.icons.filled.OpenInNew
import androidx.compose.material.icons.filled.Widgets
import androidx.compose.material.icons.outlined.Delete
import androidx.compose.material.icons.outlined.RestartAlt
import androidx.compose.material.icons.outlined.Visibility
import androidx.compose.material.icons.outlined.VisibilityOff
import androidx.compose.material.icons.outlined.Warning
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.runanywhere.runanywhereai.ui.theme.AppColors
import com.runanywhere.runanywhereai.ui.theme.AppTypography
import com.runanywhere.runanywhereai.ui.theme.Dimensions

/**
 * Settings & Storage Screen
 *
 * Section order: API Configuration, Generation Settings, Tool Calling,
 * Storage Overview, Downloaded Models, Storage Management, Logging Configuration, About.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(viewModel: SettingsViewModel = viewModel()) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    val context = LocalContext.current
    var showDeleteConfirmDialog by remember { mutableStateOf<StoredModelInfo?>(null) }

    // Refresh storage data when the screen appears
    // This ensures downloaded models and storage metrics are up-to-date
    LaunchedEffect(Unit) {
        viewModel.refreshStorage()
    }

    Column(
        modifier =
            Modifier
                .fillMaxSize()
                .background(MaterialTheme.colorScheme.background)
                .verticalScroll(rememberScrollState()),
    ) {
        // Header
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = Dimensions.padding16, vertical = Dimensions.padding20),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(Dimensions.padding16),
        ) {
            Icon(
                imageVector = Icons.Filled.Settings,
                contentDescription = null,
                tint = AppColors.primaryOrange,
                modifier = Modifier.size(22.dp),
            )
            Text(
                text = "Settings",
                style = MaterialTheme.typography.headlineMedium,
                fontWeight = FontWeight.Bold,
                color = MaterialTheme.colorScheme.onBackground,
            )
        }

        // 1. API Configuration (Testing)
        SettingsSection(title = "API Configuration (Testing)", icon = null) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable { viewModel.showApiConfigSheet() }
                    .padding(vertical = 8.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text("API Key", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurface)
                Text(
                    text = if (uiState.isApiKeyConfigured) "Configured" else "Not Set",
                    style = AppTypography.caption,
                    color = if (uiState.isApiKeyConfigured) AppColors.statusGreen else AppColors.statusOrange,
                )
            }
            HorizontalDivider(modifier = Modifier.padding(vertical = 4.dp))
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(vertical = 8.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text("Base URL", style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurface)
                Text(
                    text = if (uiState.isBaseURLConfigured) "Configured" else "Using Default",
                    style = AppTypography.caption,
                    color = if (uiState.isBaseURLConfigured) AppColors.statusGreen else MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            if (uiState.isApiKeyConfigured && uiState.isBaseURLConfigured) {
                HorizontalDivider(modifier = Modifier.padding(vertical = 4.dp))
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clickable { viewModel.clearApiConfiguration() }
                        .padding(vertical = 8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(12.dp),
                ) {
                    Icon(
                        Icons.Outlined.Delete,
                        contentDescription = null,
                        tint = AppColors.primaryRed,
                        modifier = Modifier.size(22.dp),
                    )
                    Text(
                        text = "Clear Custom Configuration",
                        style = MaterialTheme.typography.bodyMedium,
                        color = AppColors.primaryRed,
                    )
                }
            }
            Spacer(modifier = Modifier.height(8.dp))
            Text(
                text = "Configure custom API key and base URL for testing. Requires app restart to take effect.",
                style = AppTypography.caption,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }

        // 2. Generation Settings Section
        SettingsSection(title = "Generation Settings", icon = null) {
            // Temperature Slider
            Column(modifier = Modifier.fillMaxWidth()) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(
                        text = "Temperature",
                        style = MaterialTheme.typography.bodyLarge,
                    )
                    Text(
                        text = String.format("%.1f", uiState.temperature),
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                Slider(
                    value = uiState.temperature,
                    onValueChange = { viewModel.updateTemperature(it) },
                    valueRange = 0f..2f,
                    steps = 19, // 0.1 increments from 0.0 to 2.0
                    modifier = Modifier.fillMaxWidth(),
                )
            }

            HorizontalDivider(modifier = Modifier.padding(vertical = 4.dp))

            // Max Tokens Slider
            Column(modifier = Modifier.fillMaxWidth()) {
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(
                        text = "Max Tokens",
                        style = MaterialTheme.typography.bodyLarge,
                    )
                    Text(
                        text = uiState.maxTokens.toString(),
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                Slider(
                    value = uiState.maxTokens.toFloat(),
                    onValueChange = { viewModel.updateMaxTokens(it.toInt()) },
                    valueRange = 50f..4096f,
                    steps = 80, // 50-token increments
                    modifier = Modifier.fillMaxWidth(),
                )
            }

            HorizontalDivider(modifier = Modifier.padding(vertical = 4.dp))

            // System Prompt TextField
            OutlinedTextField(
                value = uiState.systemPrompt,
                onValueChange = { viewModel.updateSystemPrompt(it) },
                label = { Text("System Prompt") },
                placeholder = { Text("Enter system prompt (optional)") },
                modifier = Modifier.fillMaxWidth(),
                maxLines = 3,
                textStyle = MaterialTheme.typography.bodyMedium,
            )

            Spacer(modifier = Modifier.height(8.dp))

            // Save Button
            OutlinedButton(
                onClick = { viewModel.saveGenerationSettings() },
                colors = ButtonDefaults.outlinedButtonColors(
                    contentColor = AppColors.primaryAccent,
                ),
            ) {
                Text("Save Settings")
            }

            Spacer(modifier = Modifier.height(8.dp))
            Text(
                text = "These settings affect LLM text generation.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }

        // 3. Tool Calling Section
        ToolSettingsSection()

        // 4. Storage Overview
        SettingsSection(
            title = "Storage Overview",
            icon = null,
            trailing = {
                TextButton(onClick = { viewModel.refreshStorage() }) {
                    Text("Refresh", style = AppTypography.caption)
                }
            },
        ) {
            StorageOverviewRow(
                icon = Icons.Filled.Storage,
                label = "Total Usage",
                value = Formatter.formatFileSize(context, uiState.totalStorageSize),
            )
            HorizontalDivider(modifier = Modifier.padding(vertical = 4.dp))
            StorageOverviewRow(
                icon = Icons.Filled.CloudQueue,
                label = "Available Space",
                value = Formatter.formatFileSize(context, uiState.availableSpace),
                valueColor = AppColors.primaryGreen,
            )
            HorizontalDivider(modifier = Modifier.padding(vertical = 4.dp))
            StorageOverviewRow(
                icon = Icons.Filled.Memory,
                label = "Models Storage",
                value = Formatter.formatFileSize(context, uiState.modelStorageSize),
                valueColor = AppColors.primaryAccent,
            )
            HorizontalDivider(modifier = Modifier.padding(vertical = 4.dp))
            StorageOverviewRow(
                icon = Icons.Filled.FormatListNumbered,
                label = "Downloaded Models",
                value = uiState.downloadedModels.size.toString(),
            )
        }

        // 5. Downloaded Models
        SettingsSection(title = "Downloaded Models", icon = null) {
            if (uiState.downloadedModels.isEmpty()) {
                Text(
                    text = "No models downloaded yet",
                    style = AppTypography.caption,
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

        // 6. Storage Management
        SettingsSection(title = "Storage Management", icon = null) {
            StorageManagementButton(
                title = "Clear Cache",
                subtitle = "",
                icon = Icons.Filled.Delete,
                color = AppColors.primaryOrange,
                onClick = { viewModel.clearCache() },
            )
            HorizontalDivider(modifier = Modifier.padding(vertical = 4.dp))
            StorageManagementButton(
                title = "Clean Temporary Files",
                subtitle = "",
                icon = Icons.Filled.CleaningServices,
                color = AppColors.primaryOrange,
                onClick = { viewModel.cleanTempFiles() },
            )
        }

        // 7. Logging Configuration
        SettingsSection(title = "Logging Configuration", icon = null) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    text = "Log Analytics Locally",
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurface,
                )
                Switch(
                    checked = uiState.analyticsLogToLocal,
                    onCheckedChange = { viewModel.updateAnalyticsLogToLocal(it) },
                )
            }
            Spacer(modifier = Modifier.height(4.dp))
            Text(
                text = "When enabled, analytics events will be saved locally on your device.",
                style = AppTypography.caption,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }

        // 8. About
        SettingsSection(title = "About", icon = null) {
            Row(
                modifier = Modifier.padding(vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(16.dp),
            ) {
                Icon(
                    Icons.Filled.Widgets,
                    contentDescription = null,
                    tint = AppColors.primaryOrange,
                    modifier = Modifier.size(22.dp),
                )
                Column {
                    Text(
                        text = "RunAnywhere SDK",
                        style = MaterialTheme.typography.headlineMedium,
                        fontWeight = FontWeight.SemiBold,
                        color = MaterialTheme.colorScheme.onSurface,
                    )
                    Text(
                        text = "Version 0.1",
                        style = AppTypography.caption,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }

            HorizontalDivider(modifier = Modifier.padding(vertical = 8.dp))

            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable {
                        val intent = Intent(Intent.ACTION_VIEW, Uri.parse("https://docs.runanywhere.ai"))
                        context.startActivity(intent)
                    }
                    .padding(vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(16.dp),
            ) {
                Icon(
                    Icons.Filled.MenuBook,
                    contentDescription = null,
                    tint = AppColors.primaryOrange,
                    modifier = Modifier.size(22.dp),
                )
                Text(
                    text = "Documentation",
                    style = MaterialTheme.typography.bodyMedium,
                    color = AppColors.primaryAccent,
                )
                Spacer(modifier = Modifier.weight(1f))
                Icon(
                    Icons.Filled.OpenInNew,
                    contentDescription = "Open link",
                    modifier = Modifier.size(22.dp),
                    tint = AppColors.primaryOrange,
                )
            }
        }

        Spacer(modifier = Modifier.height(32.dp))
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

    // API Configuration Dialog
    if (uiState.showApiConfigSheet) {
        ApiConfigurationDialog(
            apiKey = uiState.apiKey,
            baseURL = uiState.baseURL,
            onApiKeyChange = { viewModel.updateApiKey(it) },
            onBaseURLChange = { viewModel.updateBaseURL(it) },
            onSave = { viewModel.saveApiConfiguration() },
            onDismiss = { viewModel.hideApiConfigSheet() },
        )
    }

    // Restart Required Dialog
    if (uiState.showRestartDialog) {
        AlertDialog(
            onDismissRequest = { viewModel.dismissRestartDialog() },
            title = { Text("Restart Required") },
            text = {
                Text("Please restart the app for the new API configuration to take effect. The SDK will be reinitialized with your custom settings.")
            },
            confirmButton = {
                TextButton(
                    onClick = { viewModel.dismissRestartDialog() },
                ) {
                    Text("OK")
                }
            },
            icon = {
                Icon(
                    imageVector = Icons.Outlined.RestartAlt,
                    contentDescription = null,
                    tint = AppColors.primaryOrange,
                    modifier = Modifier.size(22.dp),
                )
            },
        )
    }
}

/**
 * Settings Section wrapper
 */
@Composable
private fun SettingsSection(
    title: String,
    icon: androidx.compose.ui.graphics.vector.ImageVector? = null,
    trailing: @Composable (() -> Unit)? = null,
    content: @Composable ColumnScope.() -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = Dimensions.padding16, vertical = 8.dp),
    ) {
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                icon?.let {
                    Icon(
                        imageVector = it,
                        contentDescription = null,
                        tint = AppColors.primaryOrange,
                        modifier = Modifier.size(22.dp),
                    )
                }
                Text(
                    text = title,
                    style = MaterialTheme.typography.headlineMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            trailing?.invoke()
        }
        Spacer(modifier = Modifier.height(8.dp))
        Surface(
            modifier = Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(Dimensions.cornerRadiusXLarge),
            color = MaterialTheme.colorScheme.surface,
        ) {
            Column(
                modifier = Modifier.padding(Dimensions.padding16),
                content = content,
            )
        }
    }
}

/**
 * Storage Overview Row
 */
@Composable
private fun StorageOverviewRow(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    label: String,
    value: String,
    valueColor: Color? = null,
) {
    val resolvedValueColor = valueColor ?: MaterialTheme.colorScheme.onSurfaceVariant
    Row(
        modifier =
            Modifier
                .fillMaxWidth()
                .padding(vertical = 8.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(
                imageVector = icon,
                contentDescription = null,
                modifier = Modifier.size(22.dp),
                tint = AppColors.primaryOrange,
            )
            Spacer(modifier = Modifier.width(12.dp))
            Text(
                text = label,
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurface,
            )
        }
        Text(
            text = value,
            style = MaterialTheme.typography.bodyMedium,
            color = resolvedValueColor,
        )
    }
}

/**
 * Stored Model Row
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
        // Left: Model name - iOS AppTypography.subheadlineMedium, caption2 for size
        Column(modifier = Modifier.weight(1f)) {
            Text(
                text = model.name,
                style = MaterialTheme.typography.bodyMedium,
                fontWeight = FontWeight.Medium,
                color = MaterialTheme.colorScheme.onSurface,
            )
            Text(
                text = Formatter.formatFileSize(context, model.size),
                style = AppTypography.caption2,
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
                style = AppTypography.caption,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            IconButton(
                onClick = onDelete,
                modifier = Modifier.size(44.dp),
            ) {
                Icon(
                    Icons.Outlined.Delete,
                    contentDescription = "Delete",
                    modifier = Modifier.size(22.dp),
                    tint = AppColors.primaryOrange,
                )
            }
        }
    }
}

/**
 * Storage Management Button - iOS StorageManagementButton with icon, title, subtitle
 */
@Composable
private fun StorageManagementButton(
    title: String,
    subtitle: String,
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    color: Color,
    onClick: () -> Unit,
) {
    Surface(
        modifier = Modifier
            .fillMaxWidth()
            .clickable(onClick = onClick),
        color = MaterialTheme.colorScheme.surface,
    ) {
        Row(
            modifier = Modifier.padding(Dimensions.padding16),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween,
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(
                    imageVector = icon,
                    contentDescription = null,
                    tint = color,
                    modifier = Modifier.size(22.dp),
                )
                Spacer(modifier = Modifier.width(16.dp))
                Text(
                    text = title,
                    style = MaterialTheme.typography.bodyMedium,
                    color = color,
                )
            }
            Text(
                text = subtitle,
                style = AppTypography.caption,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}

/**
 * API Configuration Dialog - iOS ApiConfigurationSheet
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun ApiConfigurationDialog(
    apiKey: String,
    baseURL: String,
    onApiKeyChange: (String) -> Unit,
    onBaseURLChange: (String) -> Unit,
    onSave: () -> Unit,
    onDismiss: () -> Unit,
) {
    var showPassword by remember { mutableStateOf(false) }

    AlertDialog(
        onDismissRequest = onDismiss,
        title = { Text("API Configuration") },
        text = {
            Column(
                verticalArrangement = Arrangement.spacedBy(16.dp),
            ) {
                // API Key - iOS SecureField "Enter API Key"
                OutlinedTextField(
                    value = apiKey,
                    onValueChange = onApiKeyChange,
                    label = { Text("API Key") },
                    placeholder = { Text("Enter API Key") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                    visualTransformation = if (showPassword) VisualTransformation.None else PasswordVisualTransformation(),
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
                    trailingIcon = {
                        IconButton(onClick = { showPassword = !showPassword }) {
                            Icon(
                                imageVector = if (showPassword) Icons.Outlined.VisibilityOff else Icons.Outlined.Visibility,
                                contentDescription = if (showPassword) "Hide password" else "Show password",
                            )
                        }
                    },
                    supportingText = {
                        Text("Your API key for authenticating with the backend", style = AppTypography.caption)
                    },
                )

                // Base URL Input
                OutlinedTextField(
                    value = baseURL,
                    onValueChange = onBaseURLChange,
                    label = { Text("Base URL") },
                    placeholder = { Text("https://api.example.com") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri),
                    supportingText = {
                        Text("The backend API URL (e.g., https://api.runanywhere.ai)", style = AppTypography.caption)
                    },
                )

                // Warning
                Surface(
                    color = AppColors.primaryOrange.copy(alpha = 0.1f),
                    shape = RoundedCornerShape(8.dp),
                ) {
                    Row(
                        modifier = Modifier.padding(12.dp),
                        horizontalArrangement = Arrangement.spacedBy(8.dp),
                        verticalAlignment = Alignment.Top,
                    ) {
                        Icon(
                            imageVector = Icons.Outlined.Warning,
                            contentDescription = null,
                            tint = AppColors.primaryOrange,
                            modifier = Modifier.size(22.dp),
                        )
                        Text(
                            text = "After saving, you must restart the app for changes to take effect. The SDK will reinitialize with your custom configuration.",
                            style = AppTypography.caption,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            }
        },
        confirmButton = {
            TextButton(
                onClick = onSave,
                enabled = apiKey.isNotEmpty() && baseURL.isNotEmpty(),
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

// =============================================================================
// Tool Settings Section
// =============================================================================

/**
 * Tool Calling Settings Section
 * * Allows users to:
 * - Enable/disable tool calling
 * - Register demo tools (weather, time, calculator)
 * - Clear all registered tools
 * - View registered tools count
 */
@Composable
fun ToolSettingsSection() {
    val context = LocalContext.current
    val application = context.applicationContext as Application
    val toolViewModel = remember { ToolSettingsViewModel.getInstance(application) }
    val toolState by toolViewModel.uiState.collectAsStateWithLifecycle()
    
    SettingsSection(title = "Tool Calling") {
        // Enable/Disable Toggle
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(vertical = 8.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = "Enable Tool Calling",
                    style = MaterialTheme.typography.bodyLarge,
                )
                Text(
                    text = "Allow LLMs to use registered tools",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            Switch(
                checked = toolState.toolCallingEnabled,
                onCheckedChange = { toolViewModel.setToolCallingEnabled(it) },
                colors = SwitchDefaults.colors(
                    checkedThumbColor = AppColors.primaryAccent,
                    checkedTrackColor = AppColors.primaryAccent.copy(alpha = 0.5f),
                ),
            )
        }
        
        if (toolState.toolCallingEnabled) {
            HorizontalDivider(modifier = Modifier.padding(vertical = 8.dp))
            
            // Registered Tools Count
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(vertical = 4.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Row(
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Icon(
                        imageVector = Icons.Outlined.Build,
                        contentDescription = null,
                        tint = AppColors.primaryAccent,
                        modifier = Modifier.size(20.dp),
                    )
                    Text(
                        text = "Registered Tools",
                        style = MaterialTheme.typography.bodyMedium,
                    )
                }
                Text(
                    text = "${toolState.registeredTools.size}",
                    style = MaterialTheme.typography.bodyMedium,
                    fontWeight = FontWeight.Bold,
                    color = AppColors.primaryAccent,
                )
            }
            
            // Tool List (if any)
            if (toolState.registeredTools.isNotEmpty()) {
                toolState.registeredTools.forEach { tool ->
                    Row(
                        modifier = Modifier
                            .fillMaxWidth()
                            .padding(start = 28.dp, top = 4.dp, bottom = 4.dp),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text(
                            text = "• ${tool.name}",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            }
            
            HorizontalDivider(modifier = Modifier.padding(vertical = 8.dp))
            
            // Action Buttons
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                OutlinedButton(
                    onClick = { toolViewModel.registerDemoTools() },
                    enabled = !toolState.isLoading,
                    colors = ButtonDefaults.outlinedButtonColors(
                        contentColor = AppColors.primaryGreen,
                    ),
                    modifier = Modifier.weight(1f),
                ) {
                    Icon(
                        imageVector = Icons.Outlined.Add,
                        contentDescription = null,
                        modifier = Modifier.size(18.dp),
                    )
                    Spacer(modifier = Modifier.width(4.dp))
                    Text(if (toolState.isLoading) "Loading..." else "Add Demo Tools")
                }
                
                if (toolState.registeredTools.isNotEmpty()) {
                    OutlinedButton(
                        onClick = { toolViewModel.clearAllTools() },
                        enabled = !toolState.isLoading,
                        colors = ButtonDefaults.outlinedButtonColors(
                            contentColor = AppColors.primaryRed,
                        ),
                    ) {
                        Icon(
                            imageVector = Icons.Outlined.Delete,
                            contentDescription = null,
                            modifier = Modifier.size(18.dp),
                        )
                        Spacer(modifier = Modifier.width(4.dp))
                        Text("Clear")
                    }
                }
            }
            
            Spacer(modifier = Modifier.height(8.dp))
            Text(
                text = "Demo tools: get_weather (Open-Meteo API), get_current_time, calculate",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
    }
}