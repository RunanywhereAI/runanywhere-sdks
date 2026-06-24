package com.runanywhere.runanywhereai.ui.screens.npu

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.runanywhere.sdk.npu.qhexrt.NpuInfo
import com.runanywhere.sdk.npu.qhexrt.QHexRT
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

data class AppState(
    val bootstrapping: Boolean = true,
    val npu: NpuInfo? = null,
    val qhexrtRegistered: Boolean = false,
    val error: String? = null,
)

/**
 * App-level state for the NPU-only demo: probes the Hexagon NPU and registers
 * QHexRT when the chip is v79/v81. There is no CPU path — on unsupported parts
 * the app surfaces the requirement and inference stays disabled.
 */
class AppViewModel : ViewModel() {
    private val _state = MutableStateFlow(AppState())
    val state: StateFlow<AppState> = _state.asStateFlow()

    init {
        bootstrap()
    }

    private fun bootstrap() {
        viewModelScope.launch {
            try {
                val npu = withContext(Dispatchers.IO) { QHexRT.probeNpu() }
                var registered = false
                if (npu.supported) {
                    QHexRT.register()
                    registered = true
                }
                _state.value = _state.value.copy(
                    bootstrapping = false,
                    npu = npu,
                    qhexrtRegistered = registered,
                )
            } catch (e: Exception) {
                _state.value = _state.value.copy(bootstrapping = false, error = e.message)
            }
        }
    }
}
