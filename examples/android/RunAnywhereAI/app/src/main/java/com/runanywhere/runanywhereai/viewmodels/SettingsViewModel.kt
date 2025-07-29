package com.runanywhere.runanywhereai.viewmodels

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.runanywhere.runanywhereai.data.repository.PreferencesRepository
import com.runanywhere.runanywhereai.llm.GenerationOptions
import com.runanywhere.runanywhereai.llm.LLMFramework
import com.runanywhere.runanywhereai.security.EncryptionManager
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import javax.inject.Inject

/**
 * ViewModel for managing application settings
 * 
 * Handles all app settings including:
 * - Generation parameters (temperature, max tokens, etc.)
 * - Hardware preferences (CPU/GPU selection)
 * - Memory management settings
 * - Battery optimization settings
 * - Privacy and security settings
 * - Advanced framework-specific settings
 */
@HiltViewModel
class SettingsViewModel @Inject constructor(
    private val preferencesRepository: PreferencesRepository,
    private val encryptionManager: EncryptionManager
) : ViewModel() {

    // Settings state
    private val _uiState = MutableStateFlow(SettingsUiState())
    val uiState: StateFlow<SettingsUiState> = _uiState.asStateFlow()

    private val _isLoading = MutableStateFlow(false)
    val isLoading: StateFlow<Boolean> = _isLoading.asStateFlow()

    private val _errorMessage = MutableStateFlow<String?>(null)
    val errorMessage: StateFlow<String?> = _errorMessage.asStateFlow()

    init {
        loadSettings()
    }

    /**
     * Load all settings from encrypted preferences
     */
    private fun loadSettings() {
        viewModelScope.launch {
            try {
                _isLoading.value = true
                
                val generationOptions = GenerationOptions(
                    maxTokens = preferencesRepository.getMaxTokens(),
                    temperature = preferencesRepository.getTemperature(),
                    topP = preferencesRepository.getTopP(),
                    topK = preferencesRepository.getTopK(),
                    repetitionPenalty = preferencesRepository.getRepetitionPenalty(),
                    stopSequences = preferencesRepository.getStopSequences(),
                    presencePenalty = preferencesRepository.getPresencePenalty(),
                    frequencyPenalty = preferencesRepository.getFrequencyPenalty()
                )

                _uiState.value = SettingsUiState(
                    // Generation Parameters
                    generationOptions = generationOptions,
                    
                    // Hardware Settings
                    preferredFramework = preferencesRepository.getPreferredFramework(),
                    enableGPUAcceleration = preferencesRepository.getEnableGPUAcceleration(),
                    maxMemoryUsageMB = preferencesRepository.getMaxMemoryUsage(),
                    
                    // Battery Settings
                    enableBatteryOptimization = preferencesRepository.getEnableBatteryOptimization(),
                    thermalThrottlingEnabled = preferencesRepository.getThermalThrottlingEnabled(),
                    maxBatteryTemperature = preferencesRepository.getMaxBatteryTemperature(),
                    
                    // Privacy Settings
                    enableConversationEncryption = preferencesRepository.getEnableConversationEncryption(),
                    autoDeleteConversations = preferencesRepository.getAutoDeleteConversations(),
                    conversationRetentionDays = preferencesRepository.getConversationRetentionDays(),
                    enableAnalytics = preferencesRepository.getEnableAnalytics(),
                    
                    // Advanced Settings
                    enableDebugLogging = preferencesRepository.getEnableDebugLogging(),
                    modelCacheSizeMB = preferencesRepository.getModelCacheSize(),
                    enableModelPreloading = preferencesRepository.getEnableModelPreloading(),
                    concurrentInferencesLimit = preferencesRepository.getConcurrentInferencesLimit()
                )
            } catch (e: Exception) {
                _errorMessage.value = "Failed to load settings: ${e.message}"
            } finally {
                _isLoading.value = false
            }
        }
    }

    /**
     * Update generation parameters
     */
    fun updateGenerationOptions(options: GenerationOptions) {
        viewModelScope.launch {
            try {
                preferencesRepository.setMaxTokens(options.maxTokens)
                preferencesRepository.setTemperature(options.temperature)
                preferencesRepository.setTopP(options.topP)
                preferencesRepository.setTopK(options.topK)
                preferencesRepository.setRepetitionPenalty(options.repetitionPenalty)
                preferencesRepository.setStopSequences(options.stopSequences)
                preferencesRepository.setPresencePenalty(options.presencePenalty)
                preferencesRepository.setFrequencyPenalty(options.frequencyPenalty)
                
                _uiState.value = _uiState.value.copy(generationOptions = options)
            } catch (e: Exception) {
                _errorMessage.value = "Failed to update generation settings: ${e.message}"
            }
        }
    }

    /**
     * Update hardware preferences
     */
    fun updateHardwareSettings(
        preferredFramework: LLMFramework?,
        enableGPUAcceleration: Boolean,
        maxMemoryUsageMB: Int
    ) {
        viewModelScope.launch {
            try {
                preferencesRepository.setPreferredFramework(preferredFramework)
                preferencesRepository.setEnableGPUAcceleration(enableGPUAcceleration)
                preferencesRepository.setMaxMemoryUsage(maxMemoryUsageMB)
                
                _uiState.value = _uiState.value.copy(
                    preferredFramework = preferredFramework,
                    enableGPUAcceleration = enableGPUAcceleration,
                    maxMemoryUsageMB = maxMemoryUsageMB
                )
            } catch (e: Exception) {
                _errorMessage.value = "Failed to update hardware settings: ${e.message}"
            }
        }
    }

    /**
     * Update battery optimization settings
     */
    fun updateBatterySettings(
        enableBatteryOptimization: Boolean,
        thermalThrottlingEnabled: Boolean,
        maxBatteryTemperature: Float
    ) {
        viewModelScope.launch {
            try {
                preferencesRepository.setEnableBatteryOptimization(enableBatteryOptimization)
                preferencesRepository.setThermalThrottlingEnabled(thermalThrottlingEnabled)
                preferencesRepository.setMaxBatteryTemperature(maxBatteryTemperature)
                
                _uiState.value = _uiState.value.copy(
                    enableBatteryOptimization = enableBatteryOptimization,
                    thermalThrottlingEnabled = thermalThrottlingEnabled,
                    maxBatteryTemperature = maxBatteryTemperature
                )
            } catch (e: Exception) {
                _errorMessage.value = "Failed to update battery settings: ${e.message}"
            }
        }
    }

    /**
     * Update privacy and security settings
     */
    fun updatePrivacySettings(
        enableConversationEncryption: Boolean,
        autoDeleteConversations: Boolean,
        conversationRetentionDays: Int,
        enableAnalytics: Boolean
    ) {
        viewModelScope.launch {
            try {
                preferencesRepository.setEnableConversationEncryption(enableConversationEncryption)
                preferencesRepository.setAutoDeleteConversations(autoDeleteConversations)
                preferencesRepository.setConversationRetentionDays(conversationRetentionDays)
                preferencesRepository.setEnableAnalytics(enableAnalytics)
                
                _uiState.value = _uiState.value.copy(
                    enableConversationEncryption = enableConversationEncryption,
                    autoDeleteConversations = autoDeleteConversations,
                    conversationRetentionDays = conversationRetentionDays,
                    enableAnalytics = enableAnalytics
                )
            } catch (e: Exception) {
                _errorMessage.value = "Failed to update privacy settings: ${e.message}"
            }
        }
    }

    /**
     * Update advanced settings
     */
    fun updateAdvancedSettings(
        enableDebugLogging: Boolean,
        modelCacheSizeMB: Int,
        enableModelPreloading: Boolean,
        concurrentInferencesLimit: Int
    ) {
        viewModelScope.launch {
            try {
                preferencesRepository.setEnableDebugLogging(enableDebugLogging)
                preferencesRepository.setModelCacheSize(modelCacheSizeMB)
                preferencesRepository.setEnableModelPreloading(enableModelPreloading)
                preferencesRepository.setConcurrentInferencesLimit(concurrentInferencesLimit)
                
                _uiState.value = _uiState.value.copy(
                    enableDebugLogging = enableDebugLogging,
                    modelCacheSizeMB = modelCacheSizeMB,
                    enableModelPreloading = enableModelPreloading,
                    concurrentInferencesLimit = concurrentInferencesLimit
                )
            } catch (e: Exception) {
                _errorMessage.value = "Failed to update advanced settings: ${e.message}"
            }
        }
    }

    /**
     * Reset all settings to defaults
     */
    fun resetToDefaults() {
        viewModelScope.launch {
            try {
                _isLoading.value = true
                preferencesRepository.clearAllSettings()
                loadSettings() // Reload default values
            } catch (e: Exception) {
                _errorMessage.value = "Failed to reset settings: ${e.message}"
            } finally {
                _isLoading.value = false
            }
        }
    }

    /**
     * Export settings to encrypted file
     */
    fun exportSettings(): String? {
        return try {
            preferencesRepository.exportSettings()
        } catch (e: Exception) {
            _errorMessage.value = "Failed to export settings: ${e.message}"
            null
        }
    }

    /**
     * Import settings from encrypted file
     */
    fun importSettings(settingsData: String) {
        viewModelScope.launch {
            try {
                _isLoading.value = true
                preferencesRepository.importSettings(settingsData)
                loadSettings() // Reload imported settings
            } catch (e: Exception) {
                _errorMessage.value = "Failed to import settings: ${e.message}"
            } finally {
                _isLoading.value = false
            }
        }
    }

    /**
     * Clear error message
     */
    fun clearError() {
        _errorMessage.value = null
    }
}

/**
 * UI state for settings screen
 */
data class SettingsUiState(
    // Generation Parameters
    val generationOptions: GenerationOptions = GenerationOptions(),
    
    // Hardware Settings
    val preferredFramework: LLMFramework? = null,
    val enableGPUAcceleration: Boolean = true,
    val maxMemoryUsageMB: Int = 4096,
    
    // Battery Settings
    val enableBatteryOptimization: Boolean = true,
    val thermalThrottlingEnabled: Boolean = true,
    val maxBatteryTemperature: Float = 40.0f,
    
    // Privacy Settings
    val enableConversationEncryption: Boolean = true,
    val autoDeleteConversations: Boolean = false,
    val conversationRetentionDays: Int = 30,
    val enableAnalytics: Boolean = false,
    
    // Advanced Settings
    val enableDebugLogging: Boolean = false,
    val modelCacheSizeMB: Int = 2048,
    val enableModelPreloading: Boolean = true,
    val concurrentInferencesLimit: Int = 2
)