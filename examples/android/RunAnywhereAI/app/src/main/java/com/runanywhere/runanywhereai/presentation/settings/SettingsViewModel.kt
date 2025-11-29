package com.runanywhere.runanywhereai.presentation.settings

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

/**
 * Routing Policy enum matching iOS RoutingPolicy
 * iOS Reference: RoutingPolicy enum in CombinedSettingsView.swift
 */
enum class RoutingPolicy(val displayName: String, val rawValue: String) {
    AUTOMATIC("Auto", "automatic"),
    DEVICE_ONLY("Device", "deviceOnly"),
    PREFER_DEVICE("Prefer Device", "preferDevice"),
    PREFER_CLOUD("Prefer Cloud", "preferCloud")
}

/**
 * Stored Model Information
 * iOS Reference: StoredModel in StorageViewModel.swift
 */
data class StoredModelInfo(
    val id: String,
    val name: String,
    val format: String,
    val framework: String?,
    val size: Long,
    val path: String,
    val createdDate: Long,
    val lastUsed: Long? = null,
    val contextLength: Int? = null
)

/**
 * Settings UI State
 * iOS Reference: State properties in CombinedSettingsView.swift
 */
data class SettingsUiState(
    // SDK Configuration
    val routingPolicy: RoutingPolicy = RoutingPolicy.AUTOMATIC,

    // Generation Settings
    val temperature: Float = 0.7f,
    val maxTokens: Int = 10000,

    // API Configuration
    val apiKey: String = "",
    val isApiKeyConfigured: Boolean = false,

    // Storage Overview
    val totalStorageSize: Long = 0L,
    val availableSpace: Long = 0L,
    val modelStorageSize: Long = 0L,

    // Downloaded Models
    val downloadedModels: List<StoredModelInfo> = emptyList(),

    // Logging Configuration
    val analyticsLogToLocal: Boolean = false,

    // Loading states
    val isLoading: Boolean = false,
    val errorMessage: String? = null
)

/**
 * Settings ViewModel
 *
 * iOS Reference: CombinedSettingsView state management and StorageViewModel
 *
 * This ViewModel manages:
 * - SDK configuration settings
 * - Generation parameters
 * - API key management
 * - Storage overview and model management
 * - Logging configuration
 *
 * TODO: Integrate with RunAnywhere SDK for actual settings persistence
 * iOS equivalent: UserDefaults, KeychainService, RunAnywhere SDK
 */
class SettingsViewModel : ViewModel() {

    private val _uiState = MutableStateFlow(SettingsUiState())
    val uiState: StateFlow<SettingsUiState> = _uiState.asStateFlow()

    init {
        loadCurrentConfiguration()
        loadStorageData()
    }

    /**
     * Load current configuration from storage
     *
     * TODO: Integrate with actual storage (SharedPreferences, DataStore, Keychain)
     * iOS equivalent: loadCurrentConfiguration() in CombinedSettingsView
     */
    private fun loadCurrentConfiguration() {
        viewModelScope.launch {
            // TODO: Load from SharedPreferences or DataStore
            // iOS equivalent:
            // - KeychainService.shared.retrieve(key: "runanywhere_api_key")
            // - UserDefaults.standard.string(forKey: "routingPolicy")
            // - UserDefaults.standard.double(forKey: "defaultTemperature")
            // - UserDefaults.standard.integer(forKey: "defaultMaxTokens")

            // Mock configuration for now
            _uiState.update {
                it.copy(
                    routingPolicy = RoutingPolicy.AUTOMATIC,
                    temperature = 0.7f,
                    maxTokens = 10000,
                    isApiKeyConfigured = false,
                    analyticsLogToLocal = false
                )
            }
        }
    }

    /**
     * Load storage data (models, sizes)
     *
     * TODO: Integrate with RunAnywhere SDK for actual storage data
     * iOS equivalent: StorageViewModel.loadData()
     */
    private fun loadStorageData() {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true) }

            try {
                // TODO: Get actual storage data from SDK
                // iOS equivalent:
                // let storedModels = try await RunAnywhere.storedModels()
                // Calculate storage sizes from file system

                // Mock storage data
                delay(500)

                val mockModels = listOf(
                    StoredModelInfo(
                        id = "smollm2-135m",
                        name = "SmolLM2 135M",
                        format = "gguf",
                        framework = "LlamaCpp",
                        size = 135_000_000L,
                        path = "/data/models/smollm2-135m.gguf",
                        createdDate = System.currentTimeMillis() - 86400000,
                        contextLength = 2048
                    ),
                    StoredModelInfo(
                        id = "whisper-tiny",
                        name = "Whisper Tiny",
                        format = "gguf",
                        framework = "WhisperKit",
                        size = 75_000_000L,
                        path = "/data/models/whisper-tiny.gguf",
                        createdDate = System.currentTimeMillis() - 172800000
                    )
                )

                val totalModelSize = mockModels.sumOf { it.size }

                _uiState.update {
                    it.copy(
                        downloadedModels = mockModels,
                        totalStorageSize = totalModelSize + 50_000_000L, // Add cache
                        modelStorageSize = totalModelSize,
                        availableSpace = 10_000_000_000L, // 10 GB mock
                        isLoading = false
                    )
                }
            } catch (e: Exception) {
                _uiState.update {
                    it.copy(
                        isLoading = false,
                        errorMessage = "Failed to load storage data: ${e.message}"
                    )
                }
            }
        }
    }

    /**
     * Update routing policy
     *
     * TODO: Persist to storage
     * iOS equivalent: UserDefaults.standard.set(routingPolicy.rawValue, forKey: "routingPolicy")
     */
    fun updateRoutingPolicy(policy: RoutingPolicy) {
        _uiState.update { it.copy(routingPolicy = policy) }
        saveConfiguration()
    }

    /**
     * Update temperature setting
     *
     * TODO: Persist to storage
     * iOS equivalent: UserDefaults.standard.set(defaultTemperature, forKey: "defaultTemperature")
     */
    fun updateTemperature(temperature: Float) {
        _uiState.update { it.copy(temperature = temperature) }
        saveConfiguration()
    }

    /**
     * Update max tokens setting
     *
     * TODO: Persist to storage
     * iOS equivalent: UserDefaults.standard.set(defaultMaxTokens, forKey: "defaultMaxTokens")
     */
    fun updateMaxTokens(maxTokens: Int) {
        val clampedValue = maxTokens.coerceIn(500, 20000)
        _uiState.update { it.copy(maxTokens = clampedValue) }
        saveConfiguration()
    }

    /**
     * Update API key
     *
     * TODO: Persist to secure storage (EncryptedSharedPreferences)
     * iOS equivalent: KeychainService.shared.save(key: "runanywhere_api_key", data: apiKeyData)
     */
    fun updateApiKey(apiKey: String) {
        viewModelScope.launch {
            // TODO: Save to encrypted storage
            // Android: EncryptedSharedPreferences
            // iOS: KeychainService

            _uiState.update {
                it.copy(
                    apiKey = apiKey,
                    isApiKeyConfigured = apiKey.isNotEmpty()
                )
            }
        }
    }

    /**
     * Update analytics logging preference
     *
     * TODO: Persist to storage
     * iOS equivalent: KeychainHelper.save(key: "analyticsLogToLocal", data: newValue)
     */
    fun updateAnalyticsLogging(enabled: Boolean) {
        _uiState.update { it.copy(analyticsLogToLocal = enabled) }
        // TODO: Persist setting
    }

    /**
     * Refresh storage data
     *
     * TODO: Integrate with RunAnywhere SDK
     * iOS equivalent: storageViewModel.refreshData()
     */
    fun refreshStorage() {
        loadStorageData()
    }

    /**
     * Delete a downloaded model
     *
     * TODO: Integrate with RunAnywhere SDK
     * iOS equivalent: storageViewModel.deleteModel(model.id)
     */
    fun deleteModel(modelId: String) {
        viewModelScope.launch {
            // TODO: Delete model using SDK
            // iOS equivalent:
            // await storageViewModel.deleteModel(model.id)

            _uiState.update { state ->
                state.copy(
                    downloadedModels = state.downloadedModels.filter { it.id != modelId },
                    modelStorageSize = state.downloadedModels
                        .filter { it.id != modelId }
                        .sumOf { it.size }
                )
            }
        }
    }

    /**
     * Clear cache
     *
     * TODO: Integrate with storage management
     * iOS equivalent: storageViewModel.clearCache()
     */
    fun clearCache() {
        viewModelScope.launch {
            // TODO: Clear app cache
            // iOS equivalent: Clear cache directories

            _uiState.update {
                it.copy(
                    totalStorageSize = it.modelStorageSize // Remove cache from total
                )
            }
        }
    }

    /**
     * Clean temporary files
     *
     * TODO: Integrate with storage management
     * iOS equivalent: storageViewModel.cleanTempFiles()
     */
    fun cleanTempFiles() {
        viewModelScope.launch {
            // TODO: Clean temp files
            // iOS equivalent: Remove temporary files and logs
        }
    }

    /**
     * Save configuration to storage
     *
     * TODO: Integrate with actual storage
     * iOS equivalent: updateSDKConfiguration() in CombinedSettingsView
     */
    private fun saveConfiguration() {
        viewModelScope.launch {
            // TODO: Save to SharedPreferences or DataStore
            // iOS equivalent:
            // UserDefaults.standard.set(routingPolicy.rawValue, forKey: "routingPolicy")
            // UserDefaults.standard.set(defaultTemperature, forKey: "defaultTemperature")
            // UserDefaults.standard.set(defaultMaxTokens, forKey: "defaultMaxTokens")

            val state = _uiState.value
            println("Configuration saved - Temperature: ${state.temperature}, MaxTokens: ${state.maxTokens}")
        }
    }
}
