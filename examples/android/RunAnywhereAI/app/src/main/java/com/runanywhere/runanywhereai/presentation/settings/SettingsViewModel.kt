package com.runanywhere.runanywhereai.presentation.settings

import android.app.Application
import android.content.Context
import android.util.Log
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.events.EventBus
import com.runanywhere.sdk.public.events.ModelEvent
import com.runanywhere.sdk.public.extensions.clearCache
import com.runanywhere.sdk.public.extensions.deleteModel
import com.runanywhere.sdk.public.extensions.storageInfo
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.filterIsInstance
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

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
 */
@OptIn(kotlin.time.ExperimentalTime::class)
data class SettingsUiState(
    // Storage Overview
    val totalStorageSize: Long = 0L,
    val availableSpace: Long = 0L,
    val modelStorageSize: Long = 0L,
    // Downloaded Models
    val downloadedModels: List<StoredModelInfo> = emptyList(),
    // API Configuration
    val apiKey: String = "",
    val baseURL: String = "",
    val isApiKeyConfigured: Boolean = false,
    val isBaseURLConfigured: Boolean = false,
    val showApiConfigSheet: Boolean = false,
    val showRestartDialog: Boolean = false,
    // Loading states
    val isLoading: Boolean = false,
    val errorMessage: String? = null,
)

/**
 * Settings ViewModel
 *
 * This ViewModel manages:
 * - Storage overview via RunAnywhere.getStorageInfo()
 * - Model management via RunAnywhere storage APIs
 * - API configuration (API key and base URL)
 */
class SettingsViewModel(application: Application) : AndroidViewModel(application) {
    private val _uiState = MutableStateFlow(SettingsUiState())
    val uiState: StateFlow<SettingsUiState> = _uiState.asStateFlow()

    private val encryptedPrefs by lazy {
        val masterKey = MasterKey.Builder(application)
            .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
            .build()
        EncryptedSharedPreferences.create(
            application,
            ENCRYPTED_PREFS_FILE,
            masterKey,
            EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
            EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
        )
    }

    companion object {
        private const val TAG = "SettingsViewModel"
        private const val ENCRYPTED_PREFS_FILE = "runanywhere_secure_prefs"
        private const val KEY_API_KEY = "runanywhere_api_key"
        private const val KEY_BASE_URL = "runanywhere_base_url"
        private const val KEY_DEVICE_REGISTERED = "com.runanywhere.sdk.deviceRegistered"

        /**
         * Get stored API key (for use at app launch)
         */
        fun getStoredApiKey(context: Context): String? {
            return try {
                val masterKey = MasterKey.Builder(context)
                    .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
                    .build()
                val prefs = EncryptedSharedPreferences.create(
                    context,
                    ENCRYPTED_PREFS_FILE,
                    masterKey,
                    EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
                    EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
                )
                val value = prefs.getString(KEY_API_KEY, null)
                if (value.isNullOrEmpty()) null else value
            } catch (e: Exception) {
                Log.e(TAG, "Failed to get stored API key", e)
                null
            }
        }

        /**
         * Get stored base URL (for use at app launch)
         * Automatically adds https:// if no scheme is present
         */
        fun getStoredBaseURL(context: Context): String? {
            return try {
                val masterKey = MasterKey.Builder(context)
                    .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
                    .build()
                val prefs = EncryptedSharedPreferences.create(
                    context,
                    ENCRYPTED_PREFS_FILE,
                    masterKey,
                    EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
                    EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
                )
                val value = prefs.getString(KEY_BASE_URL, null)
                if (value.isNullOrEmpty()) return null

                // Normalize URL by adding https:// if no scheme present
                val trimmed = value.trim()
                if (trimmed.startsWith("http://") || trimmed.startsWith("https://")) {
                    trimmed
                } else {
                    "https://$trimmed"
                }
            } catch (e: Exception) {
                Log.e(TAG, "Failed to get stored base URL", e)
                null
            }
        }

        /**
         * Check if custom configuration is set
         */
        fun hasCustomConfiguration(context: Context): Boolean {
            return getStoredApiKey(context) != null && getStoredBaseURL(context) != null
        }
    }

    init {
        loadApiConfiguration()
        loadStorageData()
        subscribeToModelEvents()
    }

    /**
     * Subscribe to SDK model events to automatically refresh storage when models are downloaded/deleted
     */
    private fun subscribeToModelEvents() {
        viewModelScope.launch {
            EventBus.events
                .filterIsInstance<ModelEvent>()
                .collect { event ->
                    when (event.eventType) {
                        ModelEvent.ModelEventType.DOWNLOAD_COMPLETED -> {
                            Log.d(TAG, "📥 Model download completed: ${event.modelId}, refreshing storage...")
                            loadStorageData()
                        }
                        ModelEvent.ModelEventType.DELETED -> {
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
     * Load storage data using SDK's storageInfo() API
     */
    private fun loadStorageData() {
        viewModelScope.launch {
            _uiState.update { it.copy(isLoading = true) }

            try {
                Log.d(TAG, "Loading storage info via storageInfo()...")

                // Use SDK's storageInfo()
                val storageInfo = RunAnywhere.storageInfo()

                // Map stored models to UI model
                val storedModels =
                    storageInfo.storedModels.map { model ->
                        StoredModelInfo(
                            id = model.id,
                            name = model.name,
                            size = model.size,
                        )
                    }

                Log.d(TAG, "Storage info received:")
                Log.d(TAG, "  - Total space: ${storageInfo.deviceStorage.totalSpace}")
                Log.d(TAG, "  - Free space: ${storageInfo.deviceStorage.freeSpace}")
                Log.d(TAG, "  - Model storage size: ${storageInfo.totalModelsSize}")
                Log.d(TAG, "  - Stored models count: ${storedModels.size}")

                _uiState.update {
                    it.copy(
                        totalStorageSize = storageInfo.deviceStorage.totalSpace,
                        availableSpace = storageInfo.deviceStorage.freeSpace,
                        modelStorageSize = storageInfo.totalModelsSize,
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
     * Refresh storage data
     */
    fun refreshStorage() {
        loadStorageData()
    }

    /**
     * Delete a downloaded model
     */
    fun deleteModelById(modelId: String) {
        viewModelScope.launch {
            try {
                Log.d(TAG, "Deleting model: $modelId")
                // Use SDK's deleteModel extension function
                RunAnywhere.deleteModel(modelId)
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
     * Clear cache using SDK's clearCache() API
     */
    fun clearCache() {
        viewModelScope.launch {
            try {
                Log.d(TAG, "Clearing cache via clearCache()...")
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
     */
    fun cleanTempFiles() {
        viewModelScope.launch {
            try {
                Log.d(TAG, "Cleaning temp files (via clearing cache)...")
                // Clean temp files by clearing cache
                RunAnywhere.clearCache()
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

    // ========== API Configuration Management ==========

    /**
     * Load API configuration from secure storage
     */
    private fun loadApiConfiguration() {
        try {
            val storedApiKey = encryptedPrefs.getString(KEY_API_KEY, "") ?: ""
            val storedBaseURL = encryptedPrefs.getString(KEY_BASE_URL, "") ?: ""

            _uiState.update {
                it.copy(
                    apiKey = storedApiKey,
                    baseURL = storedBaseURL,
                    isApiKeyConfigured = storedApiKey.isNotEmpty(),
                    isBaseURLConfigured = storedBaseURL.isNotEmpty()
                )
            }
            Log.d(TAG, "API configuration loaded - apiKey configured: ${storedApiKey.isNotEmpty()}, baseURL configured: ${storedBaseURL.isNotEmpty()}")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to load API configuration", e)
        }
    }

    /**
     * Update API key in UI state
     */
    fun updateApiKey(value: String) {
        _uiState.update { it.copy(apiKey = value) }
    }

    /**
     * Update base URL in UI state
     */
    fun updateBaseURL(value: String) {
        _uiState.update { it.copy(baseURL = value) }
    }

    /**
     * Normalize base URL by adding https:// if no scheme is present
     */
    private fun normalizeBaseURL(url: String): String {
        val trimmed = url.trim()
        if (trimmed.isEmpty()) return trimmed

        return if (trimmed.startsWith("http://") || trimmed.startsWith("https://")) {
            trimmed
        } else {
            "https://$trimmed"
        }
    }

    /**
     * Save API configuration to secure storage
     */
    fun saveApiConfiguration() {
        viewModelScope.launch {
            try {
                val currentState = _uiState.value
                val apiKey = currentState.apiKey
                val normalizedURL = normalizeBaseURL(currentState.baseURL)

                encryptedPrefs.edit()
                    .putString(KEY_API_KEY, apiKey)
                    .putString(KEY_BASE_URL, normalizedURL)
                    .apply()

                _uiState.update {
                    it.copy(
                        baseURL = normalizedURL,
                        isApiKeyConfigured = apiKey.isNotEmpty(),
                        isBaseURLConfigured = normalizedURL.isNotEmpty(),
                        showApiConfigSheet = false,
                        showRestartDialog = true
                    )
                }

                Log.d(TAG, "API configuration saved successfully - URL: $normalizedURL")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to save API configuration", e)
                _uiState.update {
                    it.copy(errorMessage = "Failed to save API configuration: ${e.message}")
                }
            }
        }
    }

    /**
     * Clear API configuration from secure storage
     */
    fun clearApiConfiguration() {
        viewModelScope.launch {
            try {
                encryptedPrefs.edit()
                    .remove(KEY_API_KEY)
                    .remove(KEY_BASE_URL)
                    .apply()

                // Also clear device registration so it re-registers with new config
                clearDeviceRegistration()

                _uiState.update {
                    it.copy(
                        apiKey = "",
                        baseURL = "",
                        isApiKeyConfigured = false,
                        isBaseURLConfigured = false,
                        showRestartDialog = true
                    )
                }

                Log.d(TAG, "API configuration cleared successfully")
            } catch (e: Exception) {
                Log.e(TAG, "Failed to clear API configuration", e)
                _uiState.update {
                    it.copy(errorMessage = "Failed to clear API configuration: ${e.message}")
                }
            }
        }
    }

    /**
     * Clear device registration status (forces re-registration on next launch)
     */
    private fun clearDeviceRegistration() {
        val context = getApplication<Application>()
        context.getSharedPreferences("runanywhere_sdk", Context.MODE_PRIVATE)
            .edit()
            .remove(KEY_DEVICE_REGISTERED)
            .apply()
        Log.d(TAG, "Device registration cleared - will re-register on next launch")
    }

    /**
     * Show the API configuration sheet
     */
    fun showApiConfigSheet() {
        _uiState.update { it.copy(showApiConfigSheet = true) }
    }

    /**
     * Hide the API configuration sheet
     */
    fun hideApiConfigSheet() {
        // Reload saved configuration when canceling
        loadApiConfiguration()
        _uiState.update { it.copy(showApiConfigSheet = false) }
    }

    /**
     * Dismiss the restart dialog
     */
    fun dismissRestartDialog() {
        _uiState.update { it.copy(showRestartDialog = false) }
    }

    /**
     * Check if API configuration is complete (both key and URL set)
     */
    fun isApiConfigurationComplete(): Boolean {
        val state = _uiState.value
        return state.isApiKeyConfigured && state.isBaseURLConfigured
    }
}
