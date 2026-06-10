package com.runanywhere.runanywhereai.ui.screens.tools

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.runanywhere.runanywhereai.data.settings.SettingsRepository
import com.runanywhere.runanywhereai.util.RACLog
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.getRegisteredTools
import com.runanywhere.sdk.public.types.RAToolDefinition
import kotlinx.coroutines.launch

// Mirrors iOS ToolSettingsViewModel: a persisted master toggle plus the list
// of tools registered with the SDK. Tools themselves are registered at app
// boot (BuiltInTools), so this screen only reads the registry.
class ToolsViewModel : ViewModel() {

    val toolCallingEnabled: Boolean get() = SettingsRepository.settings.toolCallingEnabled

    var tools by mutableStateOf<List<RAToolDefinition>>(emptyList())
        private set

    init {
        viewModelScope.launch {
            tools = runCatching { RunAnywhere.getRegisteredTools() }
                .onFailure { RACLog.w("failed to load registered tools: ${it.message}") }
                .getOrDefault(emptyList())
        }
    }

    fun setEnabled(value: Boolean) = SettingsRepository.setToolCallingEnabled(value)
}
