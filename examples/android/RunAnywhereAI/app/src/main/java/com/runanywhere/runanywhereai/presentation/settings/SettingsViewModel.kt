package com.runanywhere.runanywhereai.presentation.settings

import android.util.Log
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.runanywhere.sdk.models.storage.StoredModel
import com.runanywhere.sdk.public.extensions.clearCache
import com.runanywhere.sdk.public.extensions.cleanTempFiles
import com.runanywhere.sdk.public.extensions.deleteStoredModel
import com.runanywhere.sdk.public.extensions.getStorageInfo
import com.runanywhere.sdk.public.RunAnywhere
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
 * Settings UI State
 * iOS Reference: State properties in CombinedSettingsView.swift
 *
 * Uses SDK's StoredModel directly instead of a custom StoredModelInfo class
 */
@OptIn(kotlin.time.ExperimentalTime::class)
data class SettingsUiState(
    // SDK Configuration
    val routingPolicy: RoutingPolicy = RoutingPolicy.AUTOMATIC,

    // Generation Settings
    val temperature: Float = 0.7f,
    val maxTokens: Int = 10000,

    // API Configuration
    val apiKey: String = "",
    val isApiKeyConfigured: Boolean = false,

    // Storage Overview - populated from SDK's getStorageInfo()
    val totalStorageSize: Long = 0L,
    val availableSpace: Long = 0L,
    val modelStorageSize: Long = 0L,

    // Downloaded Models - using SDK's StoredModel
    val downloadedModels: List<StoredModel> = emptyList(),

    // Logging Configuration
    val analyticsLogToLocal: Boolean = false,

    // Loading states
    val isLoading: Boolean = false,
    val errorMessage: String? = null
)

/**
 * Settings ViewModel matching iOS CombinedSettingsView + StorageViewModel
 *
 * iOS Reference: CombinedSettingsView state management and StorageViewModel
 *
 * This ViewModel manages:
 * - SDK configuration settings
 * - Generation parameters
 * - API key management
 * - Storage overview via RunAnywhere.getStorageInfo() (matching iOS exactly)
 * - Model management via RunAnywhere storage APIs
 * - Logging configuration
 */
class SettingsViewModel : ViewModel() {

    private val _uiState = MutableStateFlow(SettingsUiState())
    val uiState: StateFlow<SettingsUiState> = _uiState.asStateFlow()

    companion object {
        private const val TAG = "SettingsViewModel"
    }

    init {
        loadCurrentConfiguration()
        loadStorageData()
    }

    /**
     * Load current configuration from storage
     *
     * TODO: Integrate with actual storage (SharedPreferences, DataStore)
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
     * Load storage data from SDK
     *
     * iOS equivalent: StorageViewModel.loadData() which calls:
     *   let storageInfo = await RunAnywhere.getStorageInfo()
     *   totalStorageSize = storageInfo.appStorage.totalSize
     *   availableSpace = storageInfo.deviceStorage.freeSpace
     *   modelStorageSize = storageInfo.modelStorage.totalSize
     *   storedModels = storageInfo.storedModels
     */
    private fun loadStorageData() {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true) }

            try {
                Log.d(TAG, "Loading storage info from SDK...")

                // Use SDK's getStorageInfo() - matches iOS exactly
                val storageInfo = RunAnywhere.getStorageInfo()

                Log.d(TAG, "Storage info received:")
                Log.d(TAG, "  - App total size: ${storageInfo.appStorage.totalSize}")
                Log.d(TAG, "  - Device free space: ${storageInfo.deviceStorage.freeSpace}")
                Log.d(TAG, "  - Model storage size: ${storageInfo.modelStorage.totalSize}")
                Log.d(TAG, "  - Stored models count: ${storageInfo.storedModels.size}")

                _uiState.update {
                    it.copy(
                        totalStorageSize = storageInfo.appStorage.totalSize,
                        availableSpace = storageInfo.deviceStorage.freeSpace,
                        modelStorageSize = storageInfo.modelStorage.totalSize,
                        downloadedModels = storageInfo.storedModels,
                        isLoading = false
                    )
                }

                Log.d(TAG, "Storage data loaded successfully")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to load storage data", e)
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
     * iOS equivalent:
     * func deleteModel(_ modelId: String) async {
     *     try await RunAnywhere.deleteStoredModel(modelId)
     *     await refreshData()
     * }
     */
    fun deleteModel(modelId: String) {
        viewModelScope.launch {
            try {
                Log.d(TAG, "Deleting model: $modelId")
                RunAnywhere.deleteStoredModel(modelId)
                Log.d(TAG, "Model deleted successfully: $modelId")

                // Refresh storage data after deletion
                loadStorageData()
            } catch (e: Exception) {
                Log.e(TAG, "Failed to delete model: $modelId", e)
                _uiState.update {
                    it.copy(errorMessage = "Failed to delete model: ${e.message}")
                }
            }
        }
    }

    /**
     * Clear cache
     *
     * iOS equivalent:
     * func clearCache() async {
     *     try await RunAnywhere.clearCache()
     *     await refreshData()
     * }
     */
    fun clearCache() {
        viewModelScope.launch {
            try {
                Log.d(TAG, "Clearing cache...")
                RunAnywhere.clearCache()
                Log.d(TAG, "Cache cleared successfully")

                // Refresh storage data after clearing cache
                loadStorageData()
            } catch (e: Exception) {
                Log.e(TAG, "Failed to clear cache", e)
                _uiState.update {
                    it.copy(errorMessage = "Failed to clear cache: ${e.message}")
                }
            }
        }
    }

    /**
     * Clean temporary files
     *
     * iOS equivalent:
     * func cleanTempFiles() async {
     *     try await RunAnywhere.cleanTempFiles()
     *     await refreshData()
     * }
     */
    fun cleanTempFiles() {
        viewModelScope.launch {
            try {
                Log.d(TAG, "Cleaning temp files...")
                RunAnywhere.cleanTempFiles()
                Log.d(TAG, "Temp files cleaned successfully")

                // Refresh storage data after cleaning
                loadStorageData()
            } catch (e: Exception) {
                Log.e(TAG, "Failed to clean temp files", e)
                _uiState.update {
                    it.copy(errorMessage = "Failed to clean temporary files: ${e.message}")
                }
            }
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
