package com.runanywhere.runanywhereai.presentation.settings

import android.app.Application
import android.util.Log
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import com.runanywhere.runanywhereai.data.SecureStorage
import com.runanywhere.runanywhereai.data.SettingsDataStore
import com.runanywhere.sdk.infrastructure.events.EventBus
import com.runanywhere.sdk.infrastructure.events.SDKModelEvent
import com.runanywhere.sdk.public.extensions.deleteModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.first
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
    PREFER_CLOUD("Prefer Cloud", "preferCloud"),
}

/**
 * Simple stored model info for settings display
 */
data class StoredModelInfo(
    val id: String,
    val name: String,
    val size: Long,
)

/**
 * Settings UI State
 * iOS Reference: State properties in CombinedSettingsView.swift
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
    val errorMessage: String? = null,
)

/**
 * Settings ViewModel matching iOS CombinedSettingsView + StorageViewModel
 *
 * iOS Reference: CombinedSettingsView state management and StorageViewModel
 *
 * This ViewModel manages:
 * - SDK configuration settings (persisted via DataStore)
 * - Generation parameters (persisted via DataStore)
 * - API key management (persisted via EncryptedSharedPreferences)
 * - Storage overview via RunAnywhere.getStorageInfo() (matching iOS exactly)
 * - Model management via RunAnywhere storage APIs
 * - Logging configuration (persisted via DataStore)
 */
class SettingsViewModel(application: Application) : AndroidViewModel(application) {
    private val _uiState = MutableStateFlow(SettingsUiState())
    val uiState: StateFlow<SettingsUiState> = _uiState.asStateFlow()

    // Persistence layers - matching iOS UserDefaults + Keychain
    private val settingsDataStore = SettingsDataStore(application)
    private val secureStorage = SecureStorage(application)

    companion object {
        private const val TAG = "SettingsViewModel"
    }

    init {
        loadCurrentConfiguration()
        loadStorageData()
        subscribeToModelEvents()
        observeSettingsChanges()
    }

    /**
     * Observe DataStore settings changes and update UI state
     * This ensures UI stays in sync with persisted settings
     */
    private fun observeSettingsChanges() {
        viewModelScope.launch {
            settingsDataStore.settingsFlow.collect { settings ->
                _uiState.update {
                    it.copy(
                        routingPolicy = settings.routingPolicy,
                        temperature = settings.temperature,
                        maxTokens = settings.maxTokens,
                        analyticsLogToLocal = settings.analyticsLogToLocal,
                    )
                }
            }
        }
    }

    /**
     * Subscribe to SDK model events to automatically refresh storage when models are downloaded/deleted
     * This ensures the settings screen shows up-to-date storage information
     */
    private fun subscribeToModelEvents() {
        viewModelScope.launch {
            EventBus.modelEvents.collect { event ->
                when (event) {
                    is SDKModelEvent.DownloadCompleted -> {
                        Log.d(TAG, "📥 Model download completed: ${event.modelId}, refreshing storage...")
                        loadStorageData()
                    }
                    is SDKModelEvent.DeleteCompleted -> {
                        Log.d(TAG, "🗑️ Model deleted: ${event.modelId}, refreshing storage...")
                        loadStorageData()
                    }
                    else -> {
                        // Other events don't require storage refresh
                    }
                }
            }
        }
    }

    /**
     * Load current configuration from storage
     *
     * iOS equivalent: loadCurrentConfiguration() in CombinedSettingsView
     * - KeychainService.shared.retrieve(key: "runanywhere_api_key")
     * - UserDefaults.standard.string(forKey: "routingPolicy")
     * - UserDefaults.standard.double(forKey: "defaultTemperature")
     * - UserDefaults.standard.integer(forKey: "defaultMaxTokens")
     */
    private fun loadCurrentConfiguration() {
        viewModelScope.launch {
            try {
                // Load settings from DataStore (equivalent to UserDefaults)
                val settings = settingsDataStore.settingsFlow.first()

                // Load API key from secure storage (equivalent to Keychain)
                val apiKey = secureStorage.getApiKey() ?: ""
                val isApiKeyConfigured = apiKey.isNotEmpty()

                _uiState.update {
                    it.copy(
                        routingPolicy = settings.routingPolicy,
                        temperature = settings.temperature,
                        maxTokens = settings.maxTokens,
                        apiKey = apiKey,
                        isApiKeyConfigured = isApiKeyConfigured,
                        analyticsLogToLocal = settings.analyticsLogToLocal,
                    )
                }

                Log.d(
                    TAG,
                    "Configuration loaded - Policy: ${settings.routingPolicy}, " +
                        "Temperature: ${settings.temperature}, MaxTokens: ${settings.maxTokens}, " +
                        "API Key configured: $isApiKeyConfigured",
                )
            } catch (e: Exception) {
                Log.e(TAG, "Failed to load configuration", e)
                // Keep default values on error
            }
        }
    }

    /**
     * Load storage data
     *
     * TODO: Integrate with SDK storage APIs when available
     * iOS equivalent: StorageViewModel.loadData() which calls:
     *   let storageInfo = await RunAnywhere.getStorageInfo()
     */
    private fun loadStorageData() {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true) }

            try {
                Log.d(TAG, "Loading storage info...")

                // TODO: Use SDK's getStorageInfo() when available
                // For now, get basic device storage info
                val context = getApplication<Application>()
                val filesDir = context.filesDir
                val modelsDir = java.io.File(filesDir, "models")

                val totalSpace = filesDir.totalSpace
                val freeSpace = filesDir.freeSpace
                val modelSize =
                    if (modelsDir.exists()) {
                        modelsDir.walkTopDown().filter { it.isFile }.map { it.length() }.sum()
                    } else {
                        0L
                    }

                // Get list of model files
                val storedModels =
                    if (modelsDir.exists()) {
                        modelsDir.listFiles()?.filter { it.isFile }?.map { file ->
                            StoredModelInfo(
                                id = file.nameWithoutExtension,
                                name = file.nameWithoutExtension,
                                size = file.length(),
                            )
                        } ?: emptyList()
                    } else {
                        emptyList()
                    }

                Log.d(TAG, "Storage info received:")
                Log.d(TAG, "  - Total space: $totalSpace")
                Log.d(TAG, "  - Free space: $freeSpace")
                Log.d(TAG, "  - Model storage size: $modelSize")
                Log.d(TAG, "  - Stored models count: ${storedModels.size}")

                _uiState.update {
                    it.copy(
                        totalStorageSize = totalSpace,
                        availableSpace = freeSpace,
                        modelStorageSize = modelSize,
                        downloadedModels = storedModels,
                        isLoading = false,
                    )
                }

                Log.d(TAG, "Storage data loaded successfully")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to load storage data", e)
                _uiState.update {
                    it.copy(
                        isLoading = false,
                        errorMessage = "Failed to load storage data: ${e.message}",
                    )
                }
            }
        }
    }

    /**
     * Update routing policy
     *
     * iOS equivalent: UserDefaults.standard.set(routingPolicy.rawValue, forKey: "routingPolicy")
     */
    fun updateRoutingPolicy(policy: RoutingPolicy) {
        _uiState.update { it.copy(routingPolicy = policy) }
        viewModelScope.launch {
            settingsDataStore.saveRoutingPolicy(policy)
            Log.d(TAG, "Routing policy updated: ${policy.rawValue}")
        }
    }

    /**
     * Update temperature setting
     *
     * iOS equivalent: UserDefaults.standard.set(defaultTemperature, forKey: "defaultTemperature")
     */
    fun updateTemperature(temperature: Float) {
        _uiState.update { it.copy(temperature = temperature) }
        viewModelScope.launch {
            settingsDataStore.saveTemperature(temperature)
            Log.d(TAG, "Temperature updated: $temperature")
        }
    }

    /**
     * Update max tokens setting
     *
     * iOS equivalent: UserDefaults.standard.set(defaultMaxTokens, forKey: "defaultMaxTokens")
     */
    fun updateMaxTokens(maxTokens: Int) {
        val clampedValue = maxTokens.coerceIn(500, 20000)
        _uiState.update { it.copy(maxTokens = clampedValue) }
        viewModelScope.launch {
            settingsDataStore.saveMaxTokens(clampedValue)
            Log.d(TAG, "Max tokens updated: $clampedValue")
        }
    }

    /**
     * Update API key
     *
     * iOS equivalent: KeychainService.shared.save(key: "runanywhere_api_key", data: apiKeyData)
     */
    fun updateApiKey(apiKey: String) {
        viewModelScope.launch {
            // Save to encrypted storage (equivalent to Keychain)
            if (apiKey.isNotEmpty()) {
                secureStorage.saveApiKey(apiKey)
            } else {
                secureStorage.deleteApiKey()
            }

            _uiState.update {
                it.copy(
                    apiKey = apiKey,
                    isApiKeyConfigured = apiKey.isNotEmpty(),
                )
            }
            Log.d(TAG, "API key updated, configured: ${apiKey.isNotEmpty()}")
        }
    }

    /**
     * Update analytics logging preference
     *
     * iOS equivalent: KeychainHelper.save(key: "analyticsLogToLocal", data: newValue)
     */
    fun updateAnalyticsLogging(enabled: Boolean) {
        _uiState.update { it.copy(analyticsLogToLocal = enabled) }
        viewModelScope.launch {
            settingsDataStore.saveAnalyticsLogToLocal(enabled)
            Log.d(TAG, "Analytics logging updated: $enabled")
        }
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
    fun deleteModelById(modelId: String) {
        viewModelScope.launch {
            try {
                Log.d(TAG, "Deleting model: $modelId")
                // Use SDK's deleteModel extension function
                com.runanywhere.sdk.public.extensions.deleteModel(modelId)
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
     * TODO: Integrate with SDK clearCache() when available
     */
    fun clearCache() {
        viewModelScope.launch {
            try {
                Log.d(TAG, "Clearing cache...")
                // Clear app cache directory
                val context = getApplication<Application>()
                context.cacheDir.deleteRecursively()
                context.cacheDir.mkdirs()
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
     * TODO: Integrate with SDK cleanTempFiles() when available
     */
    fun cleanTempFiles() {
        viewModelScope.launch {
            try {
                Log.d(TAG, "Cleaning temp files...")
                // Clean temp directory
                val context = getApplication<Application>()
                val tempDir = java.io.File(context.filesDir, "temp")
                if (tempDir.exists()) {
                    tempDir.deleteRecursively()
                    tempDir.mkdirs()
                }
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
}
