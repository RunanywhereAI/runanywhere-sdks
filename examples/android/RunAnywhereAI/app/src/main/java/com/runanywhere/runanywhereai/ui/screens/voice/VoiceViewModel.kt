package com.runanywhere.runanywhereai.ui.screens.voice

import ai.runanywhere.proto.v1.PipelineState
import ai.runanywhere.proto.v1.VoiceEvent
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.runanywhere.runanywhereai.util.RACLog
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.cleanupVoiceAgent
import com.runanywhere.sdk.public.extensions.initializeVoiceAgentWithLoadedModels
import com.runanywhere.sdk.public.extensions.streamVoiceAgent
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlin.coroutines.cancellation.CancellationException

enum class VoiceState { IDLE, LISTENING, TRANSCRIBING, THINKING, SPEAKING }

data class VoiceTurn(val text: String, val isUser: Boolean)

class VoiceViewModel : ViewModel() {

    var state by mutableStateOf(VoiceState.IDLE)
        private set
    val turns = mutableStateListOf<VoiceTurn>()
    var error by mutableStateOf<String?>(null)
        private set

    private var job: Job? = null
    private var assistantTurnIndex: Int? = null

    fun toggle() {
        when (state) {
            VoiceState.IDLE -> startConversation()
            else -> stop()
        }
    }

    private fun startConversation() {
        error = null
        job = viewModelScope.launch {
            try {
                state = VoiceState.TRANSCRIBING
                RunAnywhere.initializeVoiceAgentWithLoadedModels()
                state = VoiceState.LISTENING
                RunAnywhere.streamVoiceAgent().collect(::handleEvent)
            } catch (e: CancellationException) {
                // User-driven stop cancels the collector; leave the UI in the stopped state.
            } catch (e: Exception) {
                RACLog.e("voice agent failed", e)
                error = e.message ?: "Something went wrong"
                state = VoiceState.IDLE
            }
        }
    }

    fun stop() {
        job?.cancel()
        job = null
        assistantTurnIndex = null
        state = VoiceState.IDLE
        viewModelScope.launch {
            runCatching { RunAnywhere.cleanupVoiceAgent() }
                .onFailure { RACLog.w("voice agent cleanup failed: ${it.message}") }
        }
    }

    fun clear() {
        stop()
        turns.clear()
        error = null
    }

    private fun handleEvent(event: VoiceEvent) {
        event.state?.current?.let(::handlePipelineState)
        event.vad?.let {
            state = if (it.is_speech) VoiceState.LISTENING else VoiceState.TRANSCRIBING
        }
        event.user_said?.let { userSaid ->
            val text = userSaid.text.trim()
            if (userSaid.is_final && text.isNotBlank()) {
                turns += VoiceTurn(text, isUser = true)
                assistantTurnIndex = null
            }
        }
        event.agent_response_started?.let {
            state = VoiceState.THINKING
            ensureAssistantTurn()
        }
        event.assistant_token?.let { token ->
            if (token.text.isNotEmpty()) {
                state = VoiceState.THINKING
                appendAssistantToken(token.text)
            }
        }
        if (event.audio != null || event.agent_response_completed != null) {
            state = VoiceState.SPEAKING
        }
        event.session_stopped?.let { state = VoiceState.IDLE }
        val message = event.session_error?.message?.takeIf { it.isNotBlank() }
            ?: event.error?.message?.takeIf { it.isNotBlank() }
        if (message != null) {
            error = message
            state = VoiceState.IDLE
        }
    }

    private fun handlePipelineState(pipelineState: PipelineState) {
        state = when (pipelineState) {
            PipelineState.PIPELINE_STATE_IDLE,
            PipelineState.PIPELINE_STATE_STOPPED,
            -> VoiceState.IDLE
            PipelineState.PIPELINE_STATE_LISTENING,
            PipelineState.PIPELINE_STATE_WAITING_WAKEWORD,
            -> VoiceState.LISTENING
            PipelineState.PIPELINE_STATE_PROCESSING_SPEECH -> VoiceState.TRANSCRIBING
            PipelineState.PIPELINE_STATE_THINKING,
            PipelineState.PIPELINE_STATE_GENERATING_RESPONSE,
            -> VoiceState.THINKING
            PipelineState.PIPELINE_STATE_SPEAKING,
            PipelineState.PIPELINE_STATE_PLAYING_TTS,
            -> VoiceState.SPEAKING
            PipelineState.PIPELINE_STATE_ERROR -> VoiceState.IDLE
            PipelineState.PIPELINE_STATE_COOLDOWN,
            PipelineState.PIPELINE_STATE_UNSPECIFIED,
            -> state
        }
    }

    private fun appendAssistantToken(token: String) {
        val index = ensureAssistantTurn()
        turns[index] = turns[index].copy(text = turns[index].text + token)
    }

    private fun ensureAssistantTurn(): Int {
        assistantTurnIndex?.let { if (it in turns.indices) return it }
        turns += VoiceTurn("", isUser = false)
        return turns.lastIndex.also { assistantTurnIndex = it }
    }

    override fun onCleared() {
        stop()
    }
}
