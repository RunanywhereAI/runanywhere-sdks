package com.runanywhere.sdk.core

import com.runanywhere.sdk.components.base.SDKComponent
import com.runanywhere.sdk.components.llm.LLMServiceProvider
import com.runanywhere.sdk.components.stt.STTConfiguration
import com.runanywhere.sdk.components.stt.STTService
import com.runanywhere.sdk.components.vad.VADConfiguration
import com.runanywhere.sdk.components.vad.VADService
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.models.enums.LLMFramework

/**
 * Central registry for external AI module implementations
 *
 * This allows optional dependencies to register their implementations
 * at runtime, enabling a plugin-based architecture where modules like
 * WhisperCPP, llama.cpp, and other providers can be added as needed.
 *
 * Example usage:
 * ```kotlin
 * // In your app initialization:
 * ModuleRegistry.shared.registerSTT(WhisperSTTProvider())
 * ModuleRegistry.shared.registerLLM(LlamaProvider())
 * ```
 *
 * Thread Safety:
 * All operations are synchronized using a mutex to prevent race conditions
 * during concurrent access. Registration can safely happen from multiple threads.
 */
object ModuleRegistry {

    private val logger = SDKLogger("ModuleRegistry")

    // Provider lists - protected by synchronized blocks for thread safety
    // Matches iOS @MainActor pattern but using Kotlin's synchronized for cross-platform support
    private val _sttProviders = mutableListOf<STTServiceProvider>()
    private val _vadProviders = mutableListOf<VADServiceProvider>()
    private val _llmProviders = mutableListOf<LLMServiceProvider>()
    private val _ttsProviders = mutableListOf<TTSServiceProvider>()
    private val _vlmProviders = mutableListOf<VLMServiceProvider>()
    private val _wakeWordProviders = mutableListOf<WakeWordServiceProvider>()
    private val _speakerDiarizationProviders = mutableListOf<SpeakerDiarizationServiceProvider>()

    // MARK: - Registration Methods

    /**
     * Register a Speech-to-Text provider (e.g., WhisperCPP)
     * Thread-safe: Can be called from any thread
     */
    fun registerSTT(provider: STTServiceProvider) {
        synchronized(_sttProviders) {
            _sttProviders.add(provider)
        }
        logger.info("Registered STT provider: ${provider.name}")
    }

    /**
     * Register a Voice Activity Detection provider
     * Thread-safe: Can be called from any thread
     */
    fun registerVAD(provider: VADServiceProvider) {
        synchronized(_vadProviders) {
            _vadProviders.add(provider)
        }
        logger.info("Registered VAD provider: ${provider.name}")
    }

    /**
     * Register a Language Model provider (e.g., llama.cpp)
     * Thread-safe: Can be called from any thread
     */
    fun registerLLM(provider: LLMServiceProvider) {
        synchronized(_llmProviders) {
            _llmProviders.add(provider)
        }
        logger.info("Registered LLM provider: ${provider.name}")
    }

    /**
     * Register a Text-to-Speech provider
     * Thread-safe: Can be called from any thread
     */
    fun registerTTS(provider: TTSServiceProvider) {
        synchronized(_ttsProviders) {
            _ttsProviders.add(provider)
        }
        logger.info("Registered TTS provider: ${provider.name}")
    }

    /**
     * Register a Vision Language Model provider
     * Thread-safe: Can be called from any thread
     */
    fun registerVLM(provider: VLMServiceProvider) {
        synchronized(_vlmProviders) {
            _vlmProviders.add(provider)
        }
        logger.info("Registered VLM provider: ${provider.name}")
    }

    /**
     * Register a Wake Word Detection provider
     * Thread-safe: Can be called from any thread
     */
    fun registerWakeWord(provider: WakeWordServiceProvider) {
        synchronized(_wakeWordProviders) {
            _wakeWordProviders.add(provider)
        }
        logger.info("Registered Wake Word provider: ${provider.name}")
    }

    /**
     * Register a Speaker Diarization provider
     * Thread-safe: Can be called from any thread
     */
    fun registerSpeakerDiarization(provider: SpeakerDiarizationServiceProvider) {
        synchronized(_speakerDiarizationProviders) {
            _speakerDiarizationProviders.add(provider)
        }
        logger.info("Registered Speaker Diarization provider: ${provider.name}")
    }

    // MARK: - Provider Access

    /**
     * Get an STT provider for the specified model
     * Thread-safe: Can be called from any thread
     */
    fun sttProvider(modelId: String? = null): STTServiceProvider? {
        return synchronized(_sttProviders) {
            if (modelId != null) {
                _sttProviders.firstOrNull { it.canHandle(modelId) }
            } else {
                _sttProviders.firstOrNull()
            }
        }
    }

    /**
     * Get a VAD provider for the specified model
     * Thread-safe: Can be called from any thread
     */
    fun vadProvider(modelId: String? = null): VADServiceProvider? {
        return synchronized(_vadProviders) {
            if (modelId != null) {
                _vadProviders.firstOrNull { it.canHandle(modelId) }
            } else {
                _vadProviders.firstOrNull()
            }
        }
    }

    /**
     * Get an LLM provider for the specified model
     * Thread-safe: Can be called from any thread
     */
    fun llmProvider(modelId: String? = null): LLMServiceProvider? {
        return synchronized(_llmProviders) {
            if (modelId != null) {
                _llmProviders.firstOrNull { it.canHandle(modelId) }
            } else {
                _llmProviders.firstOrNull()
            }
        }
    }

    /**
     * Get a TTS provider for the specified model
     * Thread-safe: Can be called from any thread
     */
    fun ttsProvider(modelId: String? = null): TTSServiceProvider? {
        return synchronized(_ttsProviders) {
            if (modelId != null) {
                _ttsProviders.firstOrNull { it.canHandle(modelId) }
            } else {
                _ttsProviders.firstOrNull()
            }
        }
    }

    /**
     * Get a VLM provider for the specified model
     * Thread-safe: Can be called from any thread
     */
    fun vlmProvider(modelId: String? = null): VLMServiceProvider? {
        return synchronized(_vlmProviders) {
            if (modelId != null) {
                _vlmProviders.firstOrNull { it.canHandle(modelId) }
            } else {
                _vlmProviders.firstOrNull()
            }
        }
    }

    /**
     * Get a Wake Word provider
     * Thread-safe: Can be called from any thread
     */
    fun wakeWordProvider(modelId: String? = null): WakeWordServiceProvider? {
        return synchronized(_wakeWordProviders) {
            if (modelId != null) {
                _wakeWordProviders.firstOrNull { it.canHandle(modelId) }
            } else {
                _wakeWordProviders.firstOrNull()
            }
        }
    }

    /**
     * Get a Speaker Diarization provider
     * Thread-safe: Can be called from any thread
     */
    fun speakerDiarizationProvider(modelId: String? = null): SpeakerDiarizationServiceProvider? {
        return synchronized(_speakerDiarizationProviders) {
            if (modelId != null) {
                _speakerDiarizationProviders.firstOrNull { it.canHandle(modelId) }
            } else {
                _speakerDiarizationProviders.firstOrNull()
            }
        }
    }

    // MARK: - Provider List Access (for framework management)

    /**
     * Get all registered STT providers
     * Thread-safe: Returns a snapshot of the current provider list
     */
    val allSTTProviders: List<STTServiceProvider>
        get() = synchronized(_sttProviders) { _sttProviders.toList() }

    /**
     * Get all registered LLM providers
     * Thread-safe: Returns a snapshot of the current provider list
     */
    val allLLMProviders: List<LLMServiceProvider>
        get() = synchronized(_llmProviders) { _llmProviders.toList() }

    /**
     * Get all registered TTS providers
     * Thread-safe: Returns a snapshot of the current provider list
     */
    val allTTSProviders: List<TTSServiceProvider>
        get() = synchronized(_ttsProviders) { _ttsProviders.toList() }

    /**
     * Get all registered VLM providers
     * Thread-safe: Returns a snapshot of the current provider list
     */
    val allVLMProviders: List<VLMServiceProvider>
        get() = synchronized(_vlmProviders) { _vlmProviders.toList() }

    // MARK: - Availability Checking

    /**
     * Check if STT is available
     * Thread-safe: Can be called from any thread
     */
    val hasSTT: Boolean
        get() = synchronized(_sttProviders) { _sttProviders.isNotEmpty() }

    /**
     * Check if VAD is available
     * Thread-safe: Can be called from any thread
     */
    val hasVAD: Boolean
        get() = synchronized(_vadProviders) { _vadProviders.isNotEmpty() }

    /**
     * Check if LLM is available
     * Thread-safe: Can be called from any thread
     */
    val hasLLM: Boolean
        get() = synchronized(_llmProviders) { _llmProviders.isNotEmpty() }

    /**
     * Check if TTS is available
     * Thread-safe: Can be called from any thread
     */
    val hasTTS: Boolean
        get() = synchronized(_ttsProviders) { _ttsProviders.isNotEmpty() }

    /**
     * Check if VLM is available
     * Thread-safe: Can be called from any thread
     */
    val hasVLM: Boolean
        get() = synchronized(_vlmProviders) { _vlmProviders.isNotEmpty() }

    /**
     * Check if Wake Word Detection is available
     * Thread-safe: Can be called from any thread
     */
    val hasWakeWord: Boolean
        get() = synchronized(_wakeWordProviders) { _wakeWordProviders.isNotEmpty() }

    /**
     * Check if Speaker Diarization is available
     * Thread-safe: Can be called from any thread
     */
    val hasSpeakerDiarization: Boolean
        get() = synchronized(_speakerDiarizationProviders) { _speakerDiarizationProviders.isNotEmpty() }

    /**
     * Get list of all registered modules
     * Thread-safe: Can be called from any thread
     */
    val registeredModules: List<String>
        get() = buildList {
            if (hasSTT) add("STT")
            if (hasVAD) add("VAD")
            if (hasLLM) add("LLM")
            if (hasTTS) add("TTS")
            if (hasVLM) add("VLM")
            if (hasWakeWord) add("WakeWord")
            if (hasSpeakerDiarization) add("SpeakerDiarization")
        }

    /**
     * Singleton instance for convenience
     */
    val shared: ModuleRegistry = this
}

// MARK: - Service Provider Protocols

/**
 * Provider for Speech-to-Text services
 */
interface STTServiceProvider {
    suspend fun createSTTService(configuration: STTConfiguration): STTService
    fun canHandle(modelId: String?): Boolean
    val name: String
    val framework: LLMFramework
}

/**
 * Provider for Voice Activity Detection services
 */
interface VADServiceProvider {
    suspend fun createVADService(configuration: VADConfiguration): VADService
    fun canHandle(modelId: String): Boolean
    val name: String
}

// LLMServiceProvider is now imported from com.runanywhere.sdk.components.llm.LLMServiceProvider

/**
 * Provider for Text-to-Speech services
 */
interface TTSServiceProvider {
    suspend fun synthesize(text: String, options: com.runanywhere.sdk.components.TTSOptions): ByteArray
    fun synthesizeStream(text: String, options: com.runanywhere.sdk.components.TTSOptions): kotlinx.coroutines.flow.Flow<ByteArray>
    fun canHandle(modelId: String): Boolean = true
    val name: String
}

/**
 * Provider for Vision Language Model services
 */
interface VLMServiceProvider {
    suspend fun analyze(image: ByteArray, prompt: String?): com.runanywhere.sdk.components.VLMOutput
    suspend fun generateFromImage(image: ByteArray, prompt: String, options: com.runanywhere.sdk.generation.GenerationOptions): String
    fun canHandle(modelId: String): Boolean = true
    val name: String
}

/**
 * Provider for Wake Word Detection services
 */
interface WakeWordServiceProvider {
    suspend fun createWakeWordService(configuration: Any): Any // TODO: Add WakeWordConfiguration
    fun canHandle(modelId: String): Boolean
    val name: String
}

/**
 * Provider for Speaker Diarization services
 */
interface SpeakerDiarizationServiceProvider {
    suspend fun createSpeakerDiarizationService(configuration: com.runanywhere.sdk.components.speakerdiarization.SpeakerDiarizationConfiguration): com.runanywhere.sdk.components.speakerdiarization.SpeakerDiarizationService
    fun canHandle(modelId: String?): Boolean
    val name: String
}

// MARK: - Module Auto-Registration

/**
 * Protocol for modules that can auto-register themselves
 */
interface AutoRegisteringModule {
    fun register()
}

/**
 * Example implementation for external modules:
 * ```kotlin
 * // In WhisperCPP module
 * object WhisperModule : AutoRegisteringModule {
 *     override fun register() {
 *         ModuleRegistry.shared.registerSTT(WhisperSTTProvider())
 *     }
 * }
 * ```
 */
