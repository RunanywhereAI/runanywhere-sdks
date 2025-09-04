package com.runanywhere.runanywhereai.presentation.settings

import androidx.lifecycle.ViewModel
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject

/**
 * ViewModel for Settings screen
 * TODO: Implement settings management when SDK configuration features are available
 */
@HiltViewModel
class SettingsViewModel @Inject constructor(
    // TODO: Inject settings repository when available
    // private val settingsRepository: SettingsRepository
) : ViewModel() {

    // TODO: Implement settings state management
    /*
    private val _apiKey = MutableStateFlow("")
    val apiKey: StateFlow<String> = _apiKey.asStateFlow()

    private val _selectedModel = MutableStateFlow("")
    val selectedModel: StateFlow<String> = _selectedModel.asStateFlow()

    fun updateApiKey(key: String) {
        _apiKey.value = key
        // Save to secure storage
    }

    fun selectModel(modelId: String) {
        _selectedModel.value = modelId
    }
    */
}
