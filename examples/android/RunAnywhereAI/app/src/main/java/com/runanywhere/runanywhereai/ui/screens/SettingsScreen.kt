package com.runanywhere.runanywhereai.ui.screens

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.runanywhere.runanywhereai.llm.GenerationOptions
import com.runanywhere.runanywhereai.llm.LLMFramework
import com.runanywhere.runanywhereai.viewmodels.SettingsViewModel
import com.runanywhere.runanywhereai.ui.components.*

/**
 * Main settings screen with tabbed sections for different setting categories
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SettingsScreen(
    onNavigateBack: () -> Unit,
    viewModel: SettingsViewModel = hiltViewModel()
) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    val isLoading by viewModel.isLoading.collectAsStateWithLifecycle()
    val errorMessage by viewModel.errorMessage.collectAsStateWithLifecycle()

    var selectedTabIndex by remember { mutableIntStateOf(0) }

    Scaffold(
        topBar = {
            TopAppBar(
                title = { Text("Settings") },
                navigationIcon = {
                    IconButton(onClick = onNavigateBack) {
                        Icon(Icons.Default.ArrowBack, contentDescription = "Back")
                    }
                },
                actions = {
                    IconButton(
                        onClick = { viewModel.resetToDefaults() }
                    ) {
                        Icon(Icons.Default.Refresh, contentDescription = "Reset to defaults")
                    }
                }
            )
        }
    ) { paddingValues ->
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(paddingValues)
        ) {
            // Error display
            errorMessage?.let { error ->
                Card(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(16.dp),
                    colors = CardDefaults.cardColors(
                        containerColor = MaterialTheme.colorScheme.errorContainer
                    )
                ) {
                    Row(
                        modifier = Modifier.padding(16.dp),
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Icon(
                            Icons.Default.Warning,
                            contentDescription = null,
                            tint = MaterialTheme.colorScheme.onErrorContainer
                        )
                        Spacer(modifier = Modifier.width(8.dp))
                        Text(
                            text = error,
                            color = MaterialTheme.colorScheme.onErrorContainer,
                            modifier = Modifier.weight(1f)
                        )
                        IconButton(onClick = { viewModel.clearError() }) {
                            Icon(
                                Icons.Default.Close,
                                contentDescription = "Dismiss error",
                                tint = MaterialTheme.colorScheme.onErrorContainer
                            )
                        }
                    }
                }
            }

            // Tab Row
            ScrollableTabRow(
                selectedTabIndex = selectedTabIndex,
                modifier = Modifier.fillMaxWidth()
            ) {
                SettingsTab.entries.forEachIndexed { index, tab ->
                    Tab(
                        selected = selectedTabIndex == index,
                        onClick = { selectedTabIndex = index },
                        text = { Text(tab.title) },
                        icon = { Icon(tab.icon, contentDescription = null) }
                    )
                }
            }

            // Tab Content
            if (isLoading) {
                Box(
                    modifier = Modifier.fillMaxSize(),
                    contentAlignment = Alignment.Center
                ) {
                    CircularProgressIndicator()
                }
            } else {
                when (selectedTabIndex) {
                    0 -> GenerationParametersSettings(
                        options = uiState.generationOptions,
                        onOptionsChanged = viewModel::updateGenerationOptions
                    )
                    1 -> HardwareSettings(
                        preferredFramework = uiState.preferredFramework,
                        enableGPUAcceleration = uiState.enableGPUAcceleration,
                        maxMemoryUsageMB = uiState.maxMemoryUsageMB,
                        onSettingsChanged = viewModel::updateHardwareSettings
                    )
                    2 -> BatterySettings(
                        enableBatteryOptimization = uiState.enableBatteryOptimization,
                        thermalThrottlingEnabled = uiState.thermalThrottlingEnabled,
                        maxBatteryTemperature = uiState.maxBatteryTemperature,
                        onSettingsChanged = viewModel::updateBatterySettings
                    )
                    3 -> PrivacySettings(
                        enableConversationEncryption = uiState.enableConversationEncryption,
                        autoDeleteConversations = uiState.autoDeleteConversations,
                        conversationRetentionDays = uiState.conversationRetentionDays,
                        enableAnalytics = uiState.enableAnalytics,
                        onSettingsChanged = viewModel::updatePrivacySettings
                    )
                    4 -> AdvancedSettings(
                        enableDebugLogging = uiState.enableDebugLogging,
                        modelCacheSizeMB = uiState.modelCacheSizeMB,
                        enableModelPreloading = uiState.enableModelPreloading,
                        concurrentInferencesLimit = uiState.concurrentInferencesLimit,
                        onSettingsChanged = viewModel::updateAdvancedSettings,
                        onExportSettings = viewModel::exportSettings,
                        onImportSettings = viewModel::importSettings
                    )
                }
            }
        }
    }
}

/**
 * Settings tab definitions
 */
enum class SettingsTab(val title: String, val icon: ImageVector) {
    GENERATION("Generation", Icons.Default.Settings),
    HARDWARE("Hardware", Icons.Default.Settings),
    BATTERY("Battery", Icons.Default.Settings),
    PRIVACY("Privacy", Icons.Default.Lock),
    ADVANCED("Advanced", Icons.Default.Build)
}

/**
 * Generation parameters settings section
 */
@Composable
fun GenerationParametersSettings(
    options: GenerationOptions,
    onOptionsChanged: (GenerationOptions) -> Unit
) {
    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        item {
            SettingsSectionHeader("Text Generation Parameters")
        }

        item {
            SliderSetting(
                title = "Max Tokens",
                subtitle = "Maximum number of tokens to generate",
                value = options.maxTokens.toFloat(),
                range = 50f..2048f,
                steps = 39, // (2048-50)/50 steps
                onValueChange = { value ->
                    onOptionsChanged(options.copy(maxTokens = value.toInt()))
                },
                valueFormatter = { "${it.toInt()} tokens" }
            )
        }

        item {
            SliderSetting(
                title = "Temperature",
                subtitle = "Controls randomness in generation (0.0 = deterministic, 1.0 = creative)",
                value = options.temperature,
                range = 0.0f..2.0f,
                steps = 39, // 0.05 increments
                onValueChange = { value ->
                    onOptionsChanged(options.copy(temperature = value))
                },
                valueFormatter = { "%.2f".format(it) }
            )
        }

        item {
            SliderSetting(
                title = "Top P",
                subtitle = "Nucleus sampling threshold",
                value = options.topP,
                range = 0.1f..1.0f,
                steps = 17, // 0.05 increments
                onValueChange = { value ->
                    onOptionsChanged(options.copy(topP = value))
                },
                valueFormatter = { "%.2f".format(it) }
            )
        }

        item {
            SliderSetting(
                title = "Top K",
                subtitle = "Number of top tokens to consider",
                value = options.topK.toFloat(),
                range = 1f..100f,
                steps = 98,
                onValueChange = { value ->
                    onOptionsChanged(options.copy(topK = value.toInt()))
                },
                valueFormatter = { "${it.toInt()}" }
            )
        }

        item {
            SliderSetting(
                title = "Repetition Penalty",
                subtitle = "Penalty for repeating tokens",
                value = options.repetitionPenalty,
                range = 1.0f..2.0f,
                steps = 19, // 0.05 increments
                onValueChange = { value ->
                    onOptionsChanged(options.copy(repetitionPenalty = value))
                },
                valueFormatter = { "%.2f".format(it) }
            )
        }

        item {
            StopSequencesSettings(
                stopSequences = options.stopSequences,
                onStopSequencesChanged = { sequences ->
                    onOptionsChanged(options.copy(stopSequences = sequences))
                }
            )
        }

        item {
            NullableSliderSetting(
                title = "Presence Penalty",
                subtitle = "Penalty for token presence (optional)",
                value = options.presencePenalty,
                range = -2.0f..2.0f,
                onValueChange = { value ->
                    onOptionsChanged(options.copy(presencePenalty = value))
                },
                valueFormatter = { "%.2f".format(it) }
            )
        }

        item {
            NullableSliderSetting(
                title = "Frequency Penalty",
                subtitle = "Penalty for token frequency (optional)",
                value = options.frequencyPenalty,
                range = -2.0f..2.0f,
                onValueChange = { value ->
                    onOptionsChanged(options.copy(frequencyPenalty = value))
                },
                valueFormatter = { "%.2f".format(it) }
            )
        }
    }
}

/**
 * Hardware settings section
 */
@Composable
fun HardwareSettings(
    preferredFramework: LLMFramework?,
    enableGPUAcceleration: Boolean,
    maxMemoryUsageMB: Int,
    onSettingsChanged: (LLMFramework?, Boolean, Int) -> Unit
) {
    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        item {
            SettingsSectionHeader("Hardware Configuration")
        }

        item {
            DropdownSetting(
                title = "Preferred Framework",
                subtitle = "Default LLM framework to use",
                value = preferredFramework?.name ?: "Auto-select",
                options = listOf("Auto-select") + LLMFramework.entries.map { it.name },
                onValueChanged = { selected ->
                    val framework = if (selected == "Auto-select") null else LLMFramework.valueOf(selected)
                    onSettingsChanged(framework, enableGPUAcceleration, maxMemoryUsageMB)
                }
            )
        }

        item {
            SwitchSetting(
                title = "GPU Acceleration",
                subtitle = "Use GPU for faster inference when available",
                checked = enableGPUAcceleration,
                onCheckedChange = { enabled ->
                    onSettingsChanged(preferredFramework, enabled, maxMemoryUsageMB)
                }
            )
        }

        item {
            SliderSetting(
                title = "Max Memory Usage",
                subtitle = "Maximum memory limit for model loading",
                value = maxMemoryUsageMB.toFloat(),
                range = 1024f..8192f,
                steps = 13, // 512MB increments
                onValueChange = { value ->
                    onSettingsChanged(preferredFramework, enableGPUAcceleration, value.toInt())
                },
                valueFormatter = { "${it.toInt()} MB" }
            )
        }
    }
}

/**
 * Battery optimization settings
 */
@Composable
fun BatterySettings(
    enableBatteryOptimization: Boolean,
    thermalThrottlingEnabled: Boolean,
    maxBatteryTemperature: Float,
    onSettingsChanged: (Boolean, Boolean, Float) -> Unit
) {
    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        item {
            SettingsSectionHeader("Battery & Thermal Management")
        }

        item {
            SwitchSetting(
                title = "Battery Optimization",
                subtitle = "Reduce inference speed to preserve battery",
                checked = enableBatteryOptimization,
                onCheckedChange = { enabled ->
                    onSettingsChanged(enabled, thermalThrottlingEnabled, maxBatteryTemperature)
                }
            )
        }

        item {
            SwitchSetting(
                title = "Thermal Throttling",
                subtitle = "Automatically reduce performance when device gets hot",
                checked = thermalThrottlingEnabled,
                onCheckedChange = { enabled ->
                    onSettingsChanged(enableBatteryOptimization, enabled, maxBatteryTemperature)
                }
            )
        }

        item {
            SliderSetting(
                title = "Max Battery Temperature",
                subtitle = "Throttle when battery exceeds this temperature",
                value = maxBatteryTemperature,
                range = 35f..50f,
                steps = 29, // 0.5°C increments
                onValueChange = { temp ->
                    onSettingsChanged(enableBatteryOptimization, thermalThrottlingEnabled, temp)
                },
                valueFormatter = { "%.1f°C".format(it) }
            )
        }
    }
}

/**
 * Privacy and security settings
 */
@Composable
fun PrivacySettings(
    enableConversationEncryption: Boolean,
    autoDeleteConversations: Boolean,
    conversationRetentionDays: Int,
    enableAnalytics: Boolean,
    onSettingsChanged: (Boolean, Boolean, Int, Boolean) -> Unit
) {
    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        item {
            SettingsSectionHeader("Privacy & Security")
        }

        item {
            SwitchSetting(
                title = "Conversation Encryption",
                subtitle = "Encrypt stored conversations for security",
                checked = enableConversationEncryption,
                onCheckedChange = { enabled ->
                    onSettingsChanged(enabled, autoDeleteConversations, conversationRetentionDays, enableAnalytics)
                }
            )
        }

        item {
            SwitchSetting(
                title = "Auto-Delete Conversations",
                subtitle = "Automatically delete old conversations",
                checked = autoDeleteConversations,
                onCheckedChange = { enabled ->
                    onSettingsChanged(enableConversationEncryption, enabled, conversationRetentionDays, enableAnalytics)
                }
            )
        }

        if (autoDeleteConversations) {
            item {
                SliderSetting(
                    title = "Retention Period",
                    subtitle = "Days to keep conversations before deletion",
                    value = conversationRetentionDays.toFloat(),
                    range = 1f..365f,
                    steps = 51, // Variable increments
                    onValueChange = { days ->
                        onSettingsChanged(enableConversationEncryption, autoDeleteConversations, days.toInt(), enableAnalytics)
                    },
                    valueFormatter = { "${it.toInt()} days" }
                )
            }
        }

        item {
            SwitchSetting(
                title = "Analytics",
                subtitle = "Share anonymous usage data to improve the app",
                checked = enableAnalytics,
                onCheckedChange = { enabled ->
                    onSettingsChanged(enableConversationEncryption, autoDeleteConversations, conversationRetentionDays, enabled)
                }
            )
        }
    }
}

/**
 * Advanced settings section
 */
@Composable
fun AdvancedSettings(
    enableDebugLogging: Boolean,
    modelCacheSizeMB: Int,
    enableModelPreloading: Boolean,
    concurrentInferencesLimit: Int,
    onSettingsChanged: (Boolean, Int, Boolean, Int) -> Unit,
    onExportSettings: () -> String?,
    onImportSettings: (String) -> Unit
) {
    var showImportDialog by remember { mutableStateOf(false) }
    var importText by remember { mutableStateOf("") }

    LazyColumn(
        modifier = Modifier.fillMaxSize(),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        item {
            SettingsSectionHeader("Advanced Configuration")
        }

        item {
            SwitchSetting(
                title = "Debug Logging",
                subtitle = "Enable detailed logging for troubleshooting",
                checked = enableDebugLogging,
                onCheckedChange = { enabled ->
                    onSettingsChanged(enabled, modelCacheSizeMB, enableModelPreloading, concurrentInferencesLimit)
                }
            )
        }

        item {
            SliderSetting(
                title = "Model Cache Size",
                subtitle = "Disk space allocated for model caching",
                value = modelCacheSizeMB.toFloat(),
                range = 512f..8192f,
                steps = 14, // 512MB increments
                onValueChange = { size ->
                    onSettingsChanged(enableDebugLogging, size.toInt(), enableModelPreloading, concurrentInferencesLimit)
                },
                valueFormatter = { "${it.toInt()} MB" }
            )
        }

        item {
            SwitchSetting(
                title = "Model Preloading",
                subtitle = "Preload models in background for faster startup",
                checked = enableModelPreloading,
                onCheckedChange = { enabled ->
                    onSettingsChanged(enableDebugLogging, modelCacheSizeMB, enabled, concurrentInferencesLimit)
                }
            )
        }

        item {
            SliderSetting(
                title = "Concurrent Inferences",
                subtitle = "Maximum number of simultaneous model inferences",
                value = concurrentInferencesLimit.toFloat(),
                range = 1f..4f,
                steps = 2,
                onValueChange = { limit ->
                    onSettingsChanged(enableDebugLogging, modelCacheSizeMB, enableModelPreloading, limit.toInt())
                },
                valueFormatter = { "${it.toInt()}" }
            )
        }

        item {
            SettingsSectionHeader("Backup & Restore")
        }

        item {
            ButtonSetting(
                title = "Export Settings",
                subtitle = "Save current settings to encrypted file",
                buttonText = "Export",
                onClick = {
                    onExportSettings()?.let { exported ->
                        // Handle exported settings (copy to clipboard, save to file, etc.)
                    }
                }
            )
        }

        item {
            ButtonSetting(
                title = "Import Settings",
                subtitle = "Restore settings from encrypted file",
                buttonText = "Import",
                onClick = { showImportDialog = true }
            )
        }
    }

    // Import Dialog
    if (showImportDialog) {
        AlertDialog(
            onDismissRequest = { showImportDialog = false },
            title = { Text("Import Settings") },
            text = {
                OutlinedTextField(
                    value = importText,
                    onValueChange = { importText = it },
                    label = { Text("Paste encrypted settings data") },
                    modifier = Modifier.fillMaxWidth(),
                    maxLines = 4
                )
            },
            confirmButton = {
                TextButton(
                    onClick = {
                        if (importText.isNotBlank()) {
                            onImportSettings(importText)
                            showImportDialog = false
                            importText = ""
                        }
                    }
                ) {
                    Text("Import")
                }
            },
            dismissButton = {
                TextButton(onClick = { showImportDialog = false }) {
                    Text("Cancel")
                }
            }
        )
    }
}
