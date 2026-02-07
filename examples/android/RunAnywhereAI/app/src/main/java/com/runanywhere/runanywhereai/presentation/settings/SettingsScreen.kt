@file:OptIn(kotlin.time.ExperimentalTime::class)

package com.runanywhere.runanywhereai.presentation.settings

import android.content.Intent
import android.net.Uri
import android.text.format.Formatter
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
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
 * Settings screen
 *
 * Section order: Generation Settings, API Configuration, Storage Overview, Downloaded Models,
 * Storage Management, Logging Configuration, About.
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
                .verticalScroll(rememberScrollState()),
    ) {
        // Header
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .padding(horizontal = Dimensions.padding16, vertical = Dimensions.padding16),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                text = "Settings",
                style = MaterialTheme.typography.headlineMedium,
                fontWeight = FontWeight.Bold,
            )
        }

        // 1. Generation Settings
        SettingsSection(title = "Generation Settings") {
            Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text(
                    text = "Temperature: ${"%.2f".format(uiState.temperature)}",
                    style = AppTypography.caption,
                    color = AppColors.textSecondary,
                )
                Slider(
                    value = uiState.temperature,
                    onValueChange = { viewModel.updateTemperature(it) },
                    valueRange = 0f..2f,
                    steps = 19,
                    modifier = Modifier.fillMaxWidth(),
                )
                Row(
                    modifier = Modifier.fillMaxWidth(),
                    horizontalArrangement = Arrangement.SpaceBetween,
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    Text(
                        text = "Max Tokens: ${uiState.maxTokens}",
                        style = MaterialTheme.typography.bodyMedium,
                    )
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        OutlinedButton(
                            onClick = { viewModel.updateMaxTokens((uiState.maxTokens - 500).coerceAtLeast(500)) },
                            contentPadding = PaddingValues(horizontal = 12.dp, vertical = 4.dp),
                            modifier = Modifier.height(32.dp),
                        ) { Text("-", style = AppTypography.caption) }
                        Spacer(modifier = Modifier.width(8.dp))
                        Text(
                            text = "${uiState.maxTokens}",
                            style = AppTypography.caption,
                            modifier = Modifier.widthIn(min = 48.dp),
                        )
                        Spacer(modifier = Modifier.width(8.dp))
                        OutlinedButton(
                            onClick = { viewModel.updateMaxTokens((uiState.maxTokens + 500).coerceAtMost(20000)) },
                            contentPadding = PaddingValues(horizontal = 12.dp, vertical = 4.dp),
                            modifier = Modifier.height(32.dp),
                        ) { Text("+", style = AppTypography.caption) }
                    }
                }
            }
        }

        // 2. API Configuration (Testing)
        SettingsSection(title = "API Configuration (Testing)") {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .clickable { viewModel.showApiConfigSheet() }
                    .padding(vertical = 8.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text("API Key", style = MaterialTheme.typography.bodyMedium)
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
                Text("Base URL", style = MaterialTheme.typography.bodyMedium)
                Text(
                    text = if (uiState.isBaseURLConfigured) "Configured" else "Using Default",
                    style = AppTypography.caption,
                    color = if (uiState.isBaseURLConfigured) AppColors.statusGreen else AppColors.textSecondary,
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
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    Icon(
                        Icons.Outlined.Delete,
                        contentDescription = null,
                        tint = AppColors.primaryRed,
                        modifier = Modifier.size(20.dp),
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
                color = AppColors.textSecondary,
            )
        }

        // 3. Storage Overview - iOS Label(systemImage: "externaldrive") etc.
        SettingsSection(
            title = "Storage Overview",
            trailing = {
                TextButton(onClick = { viewModel.refreshStorage() }) {
                    Text("Refresh", style = AppTypography.caption)
                }
            },
        ) {
            StorageOverviewRow(
                icon = Icons.Outlined.Storage,
                label = "Total Usage",
                value = Formatter.formatFileSize(context, uiState.totalStorageSize),
                valueColor = AppColors.textSecondary,
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
                valueColor = AppColors.textSecondary,
            )
        }

        // 4. Downloaded Models
        SettingsSection(title = "Downloaded Models") {
            if (uiState.downloadedModels.isEmpty()) {
                Text(
                    text = "No models downloaded yet",
                    style = AppTypography.caption,
                    color = AppColors.textSecondary,
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

        // 5. Storage Management - iOS trash icon, red/orange
        SettingsSection(title = "Storage Management") {
            StorageManagementButton(
                title = "Clear Cache",
                subtitle = "Free up space by clearing cached data",
                icon = Icons.Outlined.Delete,
                color = AppColors.primaryRed,
                onClick = { viewModel.clearCache() },
            )
            Spacer(modifier = Modifier.height(12.dp))
            StorageManagementButton(
                title = "Clean Temporary Files",
                subtitle = "Remove temporary files and logs",
                icon = Icons.Outlined.Delete,
                color = AppColors.primaryOrange,
                onClick = { viewModel.cleanTempFiles() },
            )
        }

        // 6. Logging Configuration - iOS Toggle "Log Analytics Locally"
        SettingsSection(title = "Logging Configuration") {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    text = "Log Analytics Locally",
                    style = MaterialTheme.typography.bodyMedium,
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
                color = AppColors.textSecondary,
            )
        }

        // 7. About - iOS Label "RunAnywhere SDK" systemImage "cube", "Documentation" systemImage "book"
        SettingsSection(title = "About") {
            Row(
                modifier = Modifier.padding(vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Icon(
                    Icons.Outlined.Widgets,
                    contentDescription = null,
                    tint = AppColors.primaryAccent,
                    modifier = Modifier.size(24.dp),
                )
                Column {
                    Text(
                        text = "RunAnywhere SDK",
                        style = MaterialTheme.typography.headlineMedium,
                        fontWeight = FontWeight.SemiBold,
                    )
                    Text(
                        text = "Version 0.1",
                        style = AppTypography.caption,
                        color = AppColors.textSecondary,
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
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                Icon(
                    Icons.Outlined.MenuBook,
                    contentDescription = null,
                    tint = AppColors.primaryAccent,
                    modifier = Modifier.size(24.dp),
                )
                Text(
                    text = "Documentation",
                    style = MaterialTheme.typography.bodyMedium,
                    color = AppColors.primaryAccent,
                )
                Spacer(modifier = Modifier.weight(1f))
                Icon(
                    Icons.Default.OpenInNew,
                    contentDescription = "Open link",
                    modifier = Modifier.size(16.dp),
                    tint = AppColors.primaryAccent,
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

    // Restart Required Dialog - iOS exact message
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
            Text(
                text = title,
                style = MaterialTheme.typography.headlineMedium,
                color = AppColors.textSecondary,
            )
            trailing?.invoke()
        }
        Spacer(modifier = Modifier.height(8.dp))
        Surface(
            modifier = Modifier.fillMaxWidth(),
            shape = RoundedCornerShape(Dimensions.cornerRadiusXLarge),
            color = MaterialTheme.colorScheme.surfaceVariant,
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
    valueColor: Color = AppColors.textSecondary,
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
            )
            Text(
                text = Formatter.formatFileSize(context, model.size),
                style = AppTypography.caption2,
                color = AppColors.textSecondary,
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
                color = AppColors.textSecondary,
            )
            IconButton(
                onClick = onDelete,
                modifier = Modifier.size(32.dp),
            ) {
                Icon(
                    Icons.Outlined.Delete,
                    contentDescription = "Delete",
                    modifier = Modifier.size(20.dp),
                    tint = AppColors.primaryRed,
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
        shape = RoundedCornerShape(Dimensions.cornerRadiusRegular),
        color = color.copy(alpha = 0.1f),
        border = androidx.compose.foundation.BorderStroke(
            Dimensions.strokeRegular,
            color.copy(alpha = 0.3f),
        ),
    ) {
        Row(
            modifier = Modifier.padding(12.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.SpaceBetween,
        ) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(
                    imageVector = icon,
                    contentDescription = null,
                    tint = color,
                    modifier = Modifier.size(20.dp),
                )
                Spacer(modifier = Modifier.width(12.dp))
                Text(
                    text = title,
                    style = MaterialTheme.typography.bodyMedium,
                    color = color,
                )
            }
            Text(
                text = subtitle,
                style = AppTypography.caption,
                color = AppColors.textSecondary,
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
                            modifier = Modifier.size(20.dp),
                        )
                        Text(
                            text = "After saving, you must restart the app for changes to take effect. The SDK will reinitialize with your custom configuration.",
                            style = AppTypography.caption,
                            color = AppColors.textSecondary,
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
