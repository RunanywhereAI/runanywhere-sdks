package com.runanywhere.runanywhereai.ui.screens

import android.content.Intent
import android.net.Uri
import android.text.format.Formatter
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.expandVertically
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.shrinkVertically
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Slider
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.compose.viewModel
import com.runanywhere.runanywhereai.models.SettingsDialogState
import com.runanywhere.runanywhereai.models.SettingsUiState
import com.runanywhere.runanywhereai.ui.components.RAButton
import com.runanywhere.runanywhereai.ui.components.RAButtonStyle
import com.runanywhere.runanywhereai.ui.components.RACard
import com.runanywhere.runanywhereai.ui.components.RAIconButton
import com.runanywhere.runanywhereai.ui.components.RASettingsItem
import com.runanywhere.runanywhereai.ui.components.RASwitch
import com.runanywhere.runanywhereai.ui.icons.RAIcons
import com.runanywhere.runanywhereai.ui.theme.AppMotion
import com.runanywhere.runanywhereai.viewmodels.SettingsViewModel

@Composable
fun SettingsScreen(
    viewModel: SettingsViewModel = viewModel(),
) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    val dialogState by viewModel.dialogState.collectAsStateWithLifecycle()

    when (val state = uiState) {
        is SettingsUiState.Loading -> {
            // Should rarely happen — ViewModel starts in Ready state
            Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
                CircularProgressIndicator(color = MaterialTheme.colorScheme.primary)
            }
        }

        is SettingsUiState.Error -> {
            Box(Modifier.fillMaxSize().padding(24.dp), contentAlignment = Alignment.Center) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    Text("Something went wrong", style = MaterialTheme.typography.titleMedium, color = MaterialTheme.colorScheme.error)
                    Spacer(Modifier.height(8.dp))
                    Text(state.message, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
        }

        is SettingsUiState.Ready -> {
            SettingsReadyContent(state = state, viewModel = viewModel)
        }
    }

    // Dialogs
    SettingsDialogs(dialogState = dialogState, viewModel = viewModel)
}

// =============================================================================
// Ready content
// =============================================================================

@Composable
private fun SettingsReadyContent(
    state: SettingsUiState.Ready,
    viewModel: SettingsViewModel,
) {
    val context = LocalContext.current

    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = 16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Spacer(Modifier.height(4.dp))

        // 1. API Configuration
        SectionHeader("API Configuration (Testing)")
        RACard {
            RASettingsItem(
                title = "API Key",
                leadingIcon = RAIcons.Settings,
                onClick = { viewModel.showApiConfigDialog() },
                showDivider = true,
                trailing = {
                    StatusLabel(configured = state.isApiKeyConfigured)
                },
            )
            RASettingsItem(
                title = "Base URL",
                leadingIcon = RAIcons.HardDrive,
                showDivider = state.isApiKeyConfigured && state.isBaseURLConfigured,
                trailing = {
                    StatusLabel(configured = state.isBaseURLConfigured, unconfiguredText = "Using Default")
                },
            )
            if (state.isApiKeyConfigured && state.isBaseURLConfigured) {
                RASettingsItem(
                    title = "Clear Custom Configuration",
                    leadingIcon = RAIcons.Trash,
                    leadingIconTint = MaterialTheme.colorScheme.error,
                    onClick = { viewModel.clearApiConfiguration() },
                )
            }
            Text(
                text = "Configure custom API key and base URL for testing. Requires app restart.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(top = 4.dp),
            )
        }

        // 2. Generation Settings
        SectionHeader("Generation Settings")
        RACard {
            // Temperature
            SliderSetting(
                label = "Temperature",
                value = state.temperature,
                valueText = String.format("%.1f", state.temperature),
                range = 0f..2f,
                steps = 19,
                onValueChange = { viewModel.updateTemperature(it) },
            )
            HorizontalDivider(Modifier.padding(vertical = 4.dp), color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.3f))

            // Max Tokens
            SliderSetting(
                label = "Max Tokens",
                value = state.maxTokens.toFloat(),
                valueText = state.maxTokens.toString(),
                range = 50f..4096f,
                steps = 80,
                onValueChange = { viewModel.updateMaxTokens(it.toInt()) },
            )
            HorizontalDivider(Modifier.padding(vertical = 4.dp), color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.3f))

            // System Prompt
            OutlinedTextField(
                value = state.systemPrompt,
                onValueChange = { viewModel.updateSystemPrompt(it) },
                label = { Text("System Prompt") },
                placeholder = { Text("Enter system prompt (optional)") },
                modifier = Modifier.fillMaxWidth(),
                maxLines = 3,
                textStyle = MaterialTheme.typography.bodyMedium,
            )

            Spacer(Modifier.height(8.dp))

            RAButton(
                text = "Save Settings",
                onClick = { viewModel.saveGenerationSettings() },
                style = RAButtonStyle.Outlined,
            )

            Text(
                text = "These settings affect LLM text generation.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(top = 8.dp),
            )
        }

        // 3. Tool Calling
        SectionHeader("Tool Calling")
        RACard {
            RASwitch(
                checked = state.toolCallingEnabled,
                onCheckedChange = { viewModel.setToolCallingEnabled(it) },
                label = "Enable Tool Calling",
            )
            Text(
                text = "Allow LLMs to use registered tools",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )

            AnimatedVisibility(
                visible = state.toolCallingEnabled,
                enter = expandVertically(AppMotion.tweenMedium()) + fadeIn(AppMotion.tweenMedium()),
                exit = shrinkVertically(AppMotion.tweenShort()) + fadeOut(AppMotion.tweenShort()),
            ) {
                Column {
                    HorizontalDivider(Modifier.padding(vertical = 8.dp), color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.3f))

                    RASettingsItem(
                        title = "Registered Tools",
                        leadingIcon = RAIcons.Puzzle,
                        trailing = {
                            Text(
                                text = "${state.registeredToolNames.size}",
                                style = MaterialTheme.typography.titleMedium,
                                color = MaterialTheme.colorScheme.primary,
                            )
                        },
                    )

                    // Tool list
                    state.registeredToolNames.forEach { name ->
                        Text(
                            text = "  \u2022 $name",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                            modifier = Modifier.padding(start = 36.dp, bottom = 2.dp),
                        )
                    }

                    HorizontalDivider(Modifier.padding(vertical = 8.dp), color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.3f))

                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        RAButton(
                            text = if (state.isToolLoading) "Loading..." else "Add Demo Tools",
                            onClick = { viewModel.registerDemoTools() },
                            icon = RAIcons.Plus,
                            style = RAButtonStyle.Outlined,
                            enabled = !state.isToolLoading,
                            modifier = Modifier.weight(1f),
                        )
                        if (state.registeredToolNames.isNotEmpty()) {
                            RAButton(
                                text = "Clear",
                                onClick = { viewModel.clearAllTools() },
                                icon = RAIcons.Trash,
                                style = RAButtonStyle.Outlined,
                                enabled = !state.isToolLoading,
                                contentColor = MaterialTheme.colorScheme.error,
                            )
                        }
                    }

                    Text(
                        text = "Demo tools: get_weather (Open-Meteo API), get_current_time, calculate",
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                        modifier = Modifier.padding(top = 8.dp),
                    )
                }
            }
        }

        // 4. Storage Overview
        SectionHeader(
            title = "Storage Overview",
            trailing = {
                TextButton(onClick = { viewModel.refreshStorage() }) {
                    Text("Refresh", style = MaterialTheme.typography.labelMedium)
                }
            },
        )
        RACard {
            StorageRow(icon = RAIcons.HardDrive, label = "Total Usage", value = Formatter.formatFileSize(context, state.totalStorageSize))
            HorizontalDivider(Modifier.padding(vertical = 4.dp), color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.3f))
            StorageRow(icon = RAIcons.Download, label = "Available Space", value = Formatter.formatFileSize(context, state.availableSpace), valueColor = MaterialTheme.colorScheme.tertiary)
            HorizontalDivider(Modifier.padding(vertical = 4.dp), color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.3f))
            StorageRow(icon = RAIcons.Cpu, label = "Models Storage", value = Formatter.formatFileSize(context, state.modelStorageSize), valueColor = MaterialTheme.colorScheme.primary)
            HorizontalDivider(Modifier.padding(vertical = 4.dp), color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.3f))
            StorageRow(icon = RAIcons.FileText, label = "Downloaded Models", value = state.downloadedModels.size.toString())
        }

        // 5. Downloaded Models
        SectionHeader("Downloaded Models")
        RACard {
            if (state.downloadedModels.isEmpty()) {
                Text(
                    text = "No models downloaded yet",
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                    modifier = Modifier.padding(vertical = 8.dp),
                )
            } else {
                state.downloadedModels.forEachIndexed { index, model ->
                    RASettingsItem(
                        title = model.name,
                        subtitle = Formatter.formatFileSize(context, model.size),
                        showDivider = index < state.downloadedModels.lastIndex,
                        trailing = {
                            Row(verticalAlignment = Alignment.CenterVertically) {
                                Text(
                                    text = Formatter.formatFileSize(context, model.size),
                                    style = MaterialTheme.typography.labelSmall,
                                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                                )
                                RAIconButton(
                                    icon = RAIcons.Trash,
                                    contentDescription = "Delete",
                                    tint = MaterialTheme.colorScheme.primary,
                                    onClick = { viewModel.showDeleteModelDialog(model) },
                                )
                            }
                        },
                    )
                }
            }
        }

        // 6. Storage Management
        SectionHeader("Storage Management")
        RACard {
            RASettingsItem(
                title = "Clear Cache",
                leadingIcon = RAIcons.Trash,
                leadingIconTint = MaterialTheme.colorScheme.error,
                onClick = { viewModel.clearCache() },
                showDivider = true,
            )
            RASettingsItem(
                title = "Clean Temporary Files",
                leadingIcon = RAIcons.X,
                leadingIconTint = MaterialTheme.colorScheme.error,
                onClick = { viewModel.cleanTempFiles() },
            )
        }

        // 7. Logging Configuration
        SectionHeader("Logging Configuration")
        RACard {
            RASwitch(
                checked = state.analyticsLogToLocal,
                onCheckedChange = { viewModel.updateAnalyticsLogToLocal(it) },
                label = "Log Analytics Locally",
            )
            Text(
                text = "When enabled, analytics events will be saved locally on your device.",
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
                modifier = Modifier.padding(top = 4.dp),
            )
        }

        // 8. About
        SectionHeader("About")
        RACard {
            Row(
                modifier = Modifier.padding(vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(16.dp),
            ) {
                Icon(
                    RAIcons.Sparkles,
                    contentDescription = null,
                    tint = MaterialTheme.colorScheme.primary,
                    modifier = Modifier.size(22.dp),
                )
                Column {
                    Text("RunAnywhere SDK", style = MaterialTheme.typography.titleMedium)
                    Text("Version 0.1", style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
                }
            }
            HorizontalDivider(Modifier.padding(vertical = 8.dp), color = MaterialTheme.colorScheme.outlineVariant.copy(alpha = 0.3f))
            RASettingsItem(
                title = "Documentation",
                leadingIcon = RAIcons.FileText,
                onClick = {
                    context.startActivity(Intent(Intent.ACTION_VIEW, Uri.parse("https://docs.runanywhere.ai")))
                },
                trailing = {
                    Icon(RAIcons.ChevronRight, contentDescription = null, modifier = Modifier.size(18.dp), tint = MaterialTheme.colorScheme.onSurfaceVariant)
                },
            )
        }

        Spacer(Modifier.height(32.dp))
    }
}

// =============================================================================
// Section header
// =============================================================================

@Composable
private fun SectionHeader(
    title: String,
    trailing: @Composable (() -> Unit)? = null,
) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            text = title,
            style = MaterialTheme.typography.titleSmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        trailing?.invoke()
    }
}

// =============================================================================
// Slider setting row
// =============================================================================

@Composable
private fun SliderSetting(
    label: String,
    value: Float,
    valueText: String,
    range: ClosedFloatingPointRange<Float>,
    steps: Int,
    onValueChange: (Float) -> Unit,
) {
    Column(Modifier.fillMaxWidth()) {
        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
            Text(label, style = MaterialTheme.typography.bodyLarge)
            Text(valueText, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurfaceVariant)
        }
        Slider(value = value, onValueChange = onValueChange, valueRange = range, steps = steps, modifier = Modifier.fillMaxWidth())
    }
}

// =============================================================================
// Storage row
// =============================================================================

@Composable
private fun StorageRow(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    label: String,
    value: String,
    valueColor: androidx.compose.ui.graphics.Color = MaterialTheme.colorScheme.onSurfaceVariant,
) {
    Row(
        modifier = Modifier.fillMaxWidth().padding(vertical = 8.dp),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(icon, contentDescription = null, modifier = Modifier.size(22.dp), tint = MaterialTheme.colorScheme.primary)
            Spacer(Modifier.width(12.dp))
            Text(label, style = MaterialTheme.typography.bodyMedium, color = MaterialTheme.colorScheme.onSurface)
        }
        Text(value, style = MaterialTheme.typography.bodyMedium, color = valueColor)
    }
}

// =============================================================================
// Status label
// =============================================================================

@Composable
private fun StatusLabel(
    configured: Boolean,
    configuredText: String = "Configured",
    unconfiguredText: String = "Not Set",
) {
    Text(
        text = if (configured) configuredText else unconfiguredText,
        style = MaterialTheme.typography.labelSmall,
        color = if (configured) MaterialTheme.colorScheme.tertiary else MaterialTheme.colorScheme.onSurfaceVariant,
    )
}

// =============================================================================
// Dialogs
// =============================================================================

@Composable
private fun SettingsDialogs(
    dialogState: SettingsDialogState,
    viewModel: SettingsViewModel,
) {
    when (dialogState) {
        is SettingsDialogState.None -> { /* nothing */ }

        is SettingsDialogState.ApiConfiguration -> {
            ApiConfigurationDialog(viewModel = viewModel)
        }

        is SettingsDialogState.RestartRequired -> {
            AlertDialog(
                onDismissRequest = { viewModel.dismissDialog() },
                title = { Text("Restart Required") },
                text = { Text("Please restart the app for the new API configuration to take effect. The SDK will be reinitialized with your custom settings.") },
                confirmButton = {
                    TextButton(onClick = { viewModel.dismissDialog() }) { Text("OK") }
                },
            )
        }

        is SettingsDialogState.DeleteModel -> {
            AlertDialog(
                onDismissRequest = { viewModel.dismissDialog() },
                title = { Text("Delete Model") },
                text = { Text("Are you sure you want to delete ${dialogState.model.name}? This action cannot be undone.") },
                confirmButton = {
                    TextButton(
                        onClick = { viewModel.deleteModel(dialogState.model.id) },
                        colors = androidx.compose.material3.ButtonDefaults.textButtonColors(
                            contentColor = MaterialTheme.colorScheme.error,
                        ),
                    ) { Text("Delete") }
                },
                dismissButton = {
                    TextButton(onClick = { viewModel.dismissDialog() }) { Text("Cancel") }
                },
            )
        }
    }
}

@Composable
private fun ApiConfigurationDialog(viewModel: SettingsViewModel) {
    val apiKey by viewModel.apiKey.collectAsStateWithLifecycle()
    val baseURL by viewModel.baseURL.collectAsStateWithLifecycle()
    var showPassword by remember { mutableStateOf(false) }

    AlertDialog(
        onDismissRequest = { viewModel.dismissDialog() },
        title = { Text("API Configuration") },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
                OutlinedTextField(
                    value = apiKey,
                    onValueChange = { viewModel.updateApiKey(it) },
                    label = { Text("API Key") },
                    placeholder = { Text("Enter API Key") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                    visualTransformation = if (showPassword) VisualTransformation.None else PasswordVisualTransformation(),
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password),
                    trailingIcon = {
                        RAIconButton(
                            icon = if (showPassword) RAIcons.Eye else RAIcons.Eye,
                            contentDescription = if (showPassword) "Hide password" else "Show password",
                            onClick = { showPassword = !showPassword },
                        )
                    },
                    supportingText = {
                        Text("Your API key for authenticating with the backend", style = MaterialTheme.typography.bodySmall)
                    },
                )

                OutlinedTextField(
                    value = baseURL,
                    onValueChange = { viewModel.updateBaseURL(it) },
                    label = { Text("Base URL") },
                    placeholder = { Text("https://api.example.com") },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth(),
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri),
                    supportingText = {
                        Text("The backend API URL (e.g., https://api.runanywhere.ai)", style = MaterialTheme.typography.bodySmall)
                    },
                )

                // Warning banner
                RACard(
                    containerColor = MaterialTheme.colorScheme.errorContainer.copy(alpha = 0.3f),
                    contentPadding = 12.dp,
                ) {
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp), verticalAlignment = Alignment.Top) {
                        Icon(RAIcons.AlertCircle, contentDescription = null, tint = MaterialTheme.colorScheme.error, modifier = Modifier.size(20.dp))
                        Text(
                            text = "After saving, you must restart the app for changes to take effect.",
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                }
            }
        },
        confirmButton = {
            TextButton(
                onClick = { viewModel.saveApiConfiguration() },
                enabled = apiKey.isNotEmpty() && baseURL.isNotEmpty(),
            ) { Text("Save") }
        },
        dismissButton = {
            TextButton(onClick = { viewModel.dismissDialog() }) { Text("Cancel") }
        },
    )
}
