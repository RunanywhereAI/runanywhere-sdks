/*
 * Hybrid Router Demo — ViewModel.
 *
 * Demonstrates the public dev-facing HybridRouter API in
 * com.runanywhere.sdk.public.routing. Pick a local STT model (loaded by the
 * SDK; the load auto-registers it with the router), optionally register
 * Sarvam cloud, then transcribe a recording directly through the router.
 *
 * The router instance is the SDK-wide STT router owned by RouterRegistration —
 * this screen is a thin window onto it, not a separate HybridRouter handle.
 */
package com.runanywhere.runanywhereai.presentation.hybridrouter

import android.content.Context
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.runanywhere.runanywhereai.domain.services.AudioCaptureService
import com.runanywhere.sdk.cloud.sarvam.Sarvam
import com.runanywhere.sdk.public.routing.Policy
import com.runanywhere.sdk.public.routing.RoutingContext
import com.runanywhere.sdk.public.routing.SDKRouters
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import timber.log.Timber
import java.io.ByteArrayOutputStream

enum class RecState { IDLE, RECORDING, PROCESSING }

data class HybridRouterUiState(
    val isModelLoaded: Boolean = false,
    val modelName: String? = null,
    val sarvamRegistered: Boolean = false,
    val backendCount: Int = 0,
    val recState: RecState = RecState.IDLE,
    val audioLevel: Float = 0f,
    val policy: Policy = Policy.PreferLocal,
    val cascadeEnabled: Boolean = true,
    val cascadeThreshold: Float = 0.5f,
    val transcript: String = "",
    val chosenBackend: String? = null,
    val confidence: Float = Float.NaN,
    val primaryConfidence: Float = Float.NaN,
    val wasFallback: Boolean = false,
    val attemptCount: Int = 0,
    /** Non-zero when the cascade tried a cloud backend and it failed. */
    val cascadeErrorCode: Int = 0,
    val cascadeErrorModuleId: String = "",
    val error: String? = null,
)

class HybridRouterViewModel : ViewModel() {

    private val _ui = MutableStateFlow(HybridRouterUiState())
    val ui: StateFlow<HybridRouterUiState> = _ui.asStateFlow()

    private var audio: AudioCaptureService? = null
    private var captureJob: Job? = null
    private val buffer = ByteArrayOutputStream()

    fun init(context: Context) {
        if (audio != null) return
        audio = AudioCaptureService(context)
        refreshRouterState()
    }

    fun onModelLoaded(modelName: String) {
        _ui.update { it.copy(modelName = modelName, isModelLoaded = true, error = null) }
        refreshRouterState()
    }

    fun setPolicy(p: Policy) = _ui.update { it.copy(policy = p) }

    fun setCascade(enabled: Boolean, threshold: Float) {
        _ui.update { it.copy(cascadeEnabled = enabled, cascadeThreshold = threshold) }
        // Apply to the live router so the next request honors it.
        SDKRouters.stt().setCascade(enabled, threshold)
    }

    fun registerSarvam(apiKey: String) {
        viewModelScope.launch {
            withContext(Dispatchers.IO) {
                // The app may have already auto-registered Sarvam at startup with
                // a different (possibly stale) key. Sarvam.register() early-
                // returns when isRegistered=true, so the new key would never
                // reach C++. updateApiKey forces the key in regardless.
                Sarvam.updateApiKey(apiKey)
                Sarvam.register(apiKey)
            }
            _ui.update { it.copy(sarvamRegistered = true, error = null) }
            refreshRouterState()
        }
    }

    fun unregisterSarvam() {
        viewModelScope.launch {
            withContext(Dispatchers.IO) { Sarvam.unregister() }
            _ui.update { it.copy(sarvamRegistered = false) }
            refreshRouterState()
        }
    }

    fun toggleRecord() {
        when (_ui.value.recState) {
            RecState.IDLE -> startRecord()
            RecState.RECORDING -> stopAndTranscribe()
            RecState.PROCESSING -> Unit
        }
    }

    private fun startRecord() {
        val cap = audio ?: return
        if (!cap.hasRecordPermission()) {
            _ui.update { it.copy(error = "Microphone permission required") }
            return
        }
        buffer.reset()
        _ui.update { it.copy(recState = RecState.RECORDING, transcript = "", error = null) }
        captureJob = viewModelScope.launch {
            cap.startCapture().collect { chunk ->
                buffer.write(chunk)
                val rms = cap.calculateRMS(chunk)
                _ui.update { it.copy(audioLevel = rms.coerceIn(0f, 1f)) }
            }
        }
    }

    private fun stopAndTranscribe() {
        audio?.stopCapture()
        captureJob?.cancel()
        captureJob = null
        val pcm = buffer.toByteArray()
        if (pcm.isEmpty()) {
            _ui.update { it.copy(recState = RecState.IDLE, error = "No audio captured") }
            return
        }
        _ui.update { it.copy(recState = RecState.PROCESSING, audioLevel = 0f) }

        viewModelScope.launch {
            try {
                val result = withContext(Dispatchers.IO) {
                    SDKRouters.stt().transcribe(
                        audioData = pcm,
                        context = RoutingContext(
                            isOnline = true,
                            policy = _ui.value.policy,
                        ),
                        optionsJson = """{"sample_rate":16000}""",
                    )
                }
                _ui.update {
                    it.copy(
                        recState = RecState.IDLE,
                        transcript = result.text,
                        chosenBackend = result.chosenModuleId,
                        confidence = result.confidence,
                        primaryConfidence = result.primaryConfidence,
                        wasFallback = result.wasFallback,
                        attemptCount = result.attemptCount,
                        cascadeErrorCode = result.cascadeErrorCode,
                        cascadeErrorModuleId = result.cascadeErrorModuleId,
                    )
                }
            } catch (t: Throwable) {
                Timber.e(t, "router transcribe failed")
                _ui.update { it.copy(recState = RecState.IDLE, error = t.message ?: "Failed") }
            }
        }
    }

    private fun refreshRouterState() {
        _ui.update { it.copy(backendCount = SDKRouters.stt().count()) }
    }

    override fun onCleared() {
        captureJob?.cancel()
        audio?.release()
        super.onCleared()
    }
}
