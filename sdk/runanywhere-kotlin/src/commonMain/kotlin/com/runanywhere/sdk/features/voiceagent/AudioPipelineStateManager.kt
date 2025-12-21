package com.runanywhere.sdk.features.voiceagent

import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.foundation.currentTimeMillis
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/**
 * Represents the current state of the audio pipeline to prevent feedback loops
 *
 * Matches iOS AudioPipelineState enum exactly:
 * - IDLE: System is idle, ready to start listening
 * - LISTENING: Actively listening for speech via VAD
 * - PROCESSING_SPEECH: Processing detected speech with STT
 * - GENERATING_RESPONSE: Generating response with LLM
 * - PLAYING_TTS: Playing TTS output
 * - COOLDOWN: Cooldown period after TTS to prevent feedback
 * - ERROR: Error state requiring reset
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Features/VoiceAgent/Models/AudioPipelineState.swift
 */
enum class AudioPipelineState(val rawValue: String) {
    /** System is idle, ready to start listening */
    IDLE("idle"),

    /** Actively listening for speech via VAD */
    LISTENING("listening"),

    /** Processing detected speech with STT */
    PROCESSING_SPEECH("processingSpeech"),

    /** Generating response with LLM */
    GENERATING_RESPONSE("generatingResponse"),

    /** Playing TTS output */
    PLAYING_TTS("playingTTS"),

    /** Cooldown period after TTS to prevent feedback */
    COOLDOWN("cooldown"),

    /** Error state requiring reset */
    ERROR("error"),
    ;

    companion object {
        val allCases: List<AudioPipelineState> = entries
    }
}

/**
 * Configuration for audio pipeline feedback prevention
 *
 * Matches iOS AudioPipelineStateManager.Configuration exactly
 */
data class AudioPipelineConfiguration(
    /** Duration to wait after TTS before allowing microphone (seconds) */
    val cooldownDuration: Double = 0.8, // 800ms - better feedback prevention while maintaining responsiveness

    /** Whether to enforce strict state transitions */
    val strictTransitions: Boolean = true,

    /** Maximum TTS duration before forced timeout (seconds) */
    val maxTTSDuration: Double = 30.0,
)

/**
 * Manages audio pipeline state transitions and feedback prevention
 *
 * This class provides state machine logic to prevent audio feedback loops
 * in voice agent scenarios where TTS output could be picked up by the microphone.
 *
 * Key features:
 * - State transition validation
 * - Cooldown period after TTS playback
 * - Microphone activation control
 * - State change notifications
 *
 * Matches iOS AudioPipelineStateManager actor exactly.
 * Uses Kotlin's Mutex for thread safety (equivalent to Swift actor).
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Features/VoiceAgent/Models/AudioPipelineState.swift
 */
class AudioPipelineStateManager(
    private val configuration: AudioPipelineConfiguration = AudioPipelineConfiguration(),
) {
    private val logger = SDKLogger("AudioPipelineState")
    private val mutex = Mutex()
    private val scope = CoroutineScope(Dispatchers.Default)

    private var _currentState: AudioPipelineState = AudioPipelineState.IDLE
    private var _lastTTSEndTime: Long? = null
    private var stateChangeHandler: ((AudioPipelineState, AudioPipelineState) -> Unit)? = null

    /**
     * Get the current state
     */
    val state: AudioPipelineState
        get() = _currentState

    /**
     * Set a handler for state changes
     * Handler receives (oldState, newState)
     */
    fun setStateChangeHandler(handler: (AudioPipelineState, AudioPipelineState) -> Unit) {
        stateChangeHandler = handler
    }

    /**
     * Check if microphone can be activated
     * Thread-safe using mutex
     */
    suspend fun canActivateMicrophone(): Boolean = mutex.withLock {
        when (_currentState) {
            AudioPipelineState.IDLE, AudioPipelineState.LISTENING -> {
                // Check cooldown if we recently finished TTS
                _lastTTSEndTime?.let { lastTTSEnd ->
                    val timeSinceTTS = (currentTimeMillis() - lastTTSEnd) / 1000.0
                    return@withLock timeSinceTTS >= configuration.cooldownDuration
                }
                true
            }
            AudioPipelineState.PROCESSING_SPEECH,
            AudioPipelineState.GENERATING_RESPONSE,
            AudioPipelineState.PLAYING_TTS,
            AudioPipelineState.COOLDOWN,
            AudioPipelineState.ERROR,
            -> false
        }
    }

    /**
     * Check if TTS can be played
     * Thread-safe using mutex
     */
    suspend fun canPlayTTS(): Boolean = mutex.withLock {
        _currentState == AudioPipelineState.GENERATING_RESPONSE
    }

    /**
     * Transition to a new state with validation
     * Thread-safe using mutex
     *
     * @param newState The state to transition to
     * @return True if transition was successful, false if invalid
     */
    suspend fun transition(newState: AudioPipelineState): Boolean = mutex.withLock {
        val oldState = _currentState

        // Validate transition
        if (!isValidTransition(oldState, newState)) {
            if (configuration.strictTransitions) {
                logger.warning("Invalid state transition from ${oldState.rawValue} to ${newState.rawValue}")
                return@withLock false
            }
        }

        // Update state
        _currentState = newState
        logger.debug("State transition: ${oldState.rawValue} → ${newState.rawValue}")

        // Handle special state actions
        when (newState) {
            AudioPipelineState.PLAYING_TTS -> {
                // Don't use timeout for System TTS as it manages its own completion
            }

            AudioPipelineState.COOLDOWN -> {
                _lastTTSEndTime = currentTimeMillis()
                // Automatically transition to idle after cooldown
                scope.launch {
                    delay((configuration.cooldownDuration * 1000).toLong())
                    if (_currentState == AudioPipelineState.COOLDOWN) {
                        transition(AudioPipelineState.IDLE)
                    }
                }
            }

            else -> {}
        }

        // Notify handler
        stateChangeHandler?.invoke(oldState, newState)

        true
    }

    /**
     * Force reset to idle state (use in error recovery)
     * Thread-safe using mutex
     */
    suspend fun reset() = mutex.withLock {
        logger.info("Force resetting audio pipeline state to idle")
        _currentState = AudioPipelineState.IDLE
        _lastTTSEndTime = null
    }

    /**
     * Check if a state transition is valid
     */
    private fun isValidTransition(from: AudioPipelineState, to: AudioPipelineState): Boolean {
        return when (from to to) {
            // From idle
            AudioPipelineState.IDLE to AudioPipelineState.LISTENING -> true
            AudioPipelineState.IDLE to AudioPipelineState.COOLDOWN -> true // Allow for quick TTS or cooldown enforcement

            // From listening
            AudioPipelineState.LISTENING to AudioPipelineState.IDLE -> true
            AudioPipelineState.LISTENING to AudioPipelineState.PROCESSING_SPEECH -> true

            // From processing speech
            AudioPipelineState.PROCESSING_SPEECH to AudioPipelineState.IDLE -> true
            AudioPipelineState.PROCESSING_SPEECH to AudioPipelineState.GENERATING_RESPONSE -> true
            AudioPipelineState.PROCESSING_SPEECH to AudioPipelineState.LISTENING -> true

            // From generating response
            AudioPipelineState.GENERATING_RESPONSE to AudioPipelineState.PLAYING_TTS -> true
            AudioPipelineState.GENERATING_RESPONSE to AudioPipelineState.IDLE -> true
            AudioPipelineState.GENERATING_RESPONSE to AudioPipelineState.COOLDOWN -> true // Direct if TTS skipped

            // From playing TTS
            AudioPipelineState.PLAYING_TTS to AudioPipelineState.COOLDOWN -> true
            AudioPipelineState.PLAYING_TTS to AudioPipelineState.IDLE -> true // If cooldown not needed

            // From cooldown
            AudioPipelineState.COOLDOWN to AudioPipelineState.IDLE -> true

            // Error state can transition to idle
            AudioPipelineState.ERROR to AudioPipelineState.IDLE -> true

            // Any state can transition to error
            else -> to == AudioPipelineState.ERROR
        }
    }
}
