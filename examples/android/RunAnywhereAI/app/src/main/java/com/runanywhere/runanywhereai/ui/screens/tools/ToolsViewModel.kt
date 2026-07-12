package com.runanywhere.runanywhereai.ui.screens.tools

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.runanywhere.runanywhereai.BuildConfig
import com.runanywhere.runanywhereai.data.settings.SettingsRepository
import com.runanywhere.runanywhereai.data.settings.WebSearchConsentPolicy
import com.runanywhere.runanywhereai.data.settings.WebSearchConsentState
import com.runanywhere.runanywhereai.util.RACLog
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.getRegisteredTools
import com.runanywhere.sdk.public.types.RAToolDefinition
import kotlinx.coroutines.launch

// Mirrors iOS ToolSettingsViewModel: a persisted master toggle plus the list
// of tools registered with the SDK. Tools themselves are registered at app
// boot (BuiltInTools), so this screen only reads the registry.
class ToolsViewModel : ViewModel() {

    val toolCallingEnabled: Boolean
        get() = WebSearchConsentPolicy.permitsTransfer(
            WebSearchConsentState(
                toolsEnabled = SettingsRepository.settings.toolCallingEnabled,
                acceptedScope = SettingsRepository.settings.webSearchConsentScope,
                currentScope = WebSearchConsentPolicy.routeFor(BuildConfig.WEB_SEARCH_URL)?.scope,
            ),
        )

    var showWebSearchDisclosure by mutableStateOf(false)
        private set

    var tools by mutableStateOf<List<RAToolDefinition>>(emptyList())
        private set

    init {
        viewModelScope.launch {
            tools = runCatching { RunAnywhere.getRegisteredTools() }
                .onFailure { RACLog.w("failed to load registered tools: ${it.message}") }
                .getOrDefault(emptyList())
        }
    }

    fun setEnabled(value: Boolean) {
        if (value) {
            showWebSearchDisclosure = true
        } else {
            SettingsRepository.setWebToolsTransferEnabled(false)
        }
    }

    fun acceptWebSearchDisclosure() {
        SettingsRepository.setWebToolsTransferEnabled(true)
        showWebSearchDisclosure = false
    }

    fun dismissWebSearchDisclosure() {
        showWebSearchDisclosure = false
    }
}
