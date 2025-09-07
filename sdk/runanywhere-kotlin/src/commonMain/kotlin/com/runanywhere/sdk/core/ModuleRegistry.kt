package com.runanywhere.sdk.core

import com.runanywhere.sdk.components.base.SDKComponent
import com.runanywhere.sdk.components.stt.STTConfiguration
import com.runanywhere.sdk.components.stt.STTService
import com.runanywhere.sdk.components.vad.VADConfiguration
import com.runanywhere.sdk.components.vad.VADService
import com.runanywhere.sdk.foundation.SDKLogger

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
 */
object ModuleRegistry {

    private val logger = SDKLogger("ModuleRegistry")

    // Provider lists
    private val sttProviders = mutableListOf<STTServiceProvider>()
    private val vadProviders = mutableListOf<VADServiceProvider>()
    private val llmProviders = mutableListOf<LLMServiceProvider>()
    private val ttsProviders = mutableListOf<TTSServiceProvider>()
    private val vlmProviders = mutableListOf<VLMServiceProvider>()
    private val wakeWordProviders = mutableListOf<WakeWordServiceProvider>()
    private val speakerDiarizationProviders = mutableListOf<SpeakerDiarizationServiceProvider>()

    // MARK: - Registration Methods

    /**
     * Register a Speech-to-Text provider (e.g., WhisperCPP)
     */
    fun registerSTT(provider: STTServiceProvider) {
        sttProviders.add(provider)
        logger.info("Registered STT provider: ${provider.name}")
    }

    /**
     * Register a Voice Activity Detection provider
     */
    fun registerVAD(provider: VADServiceProvider) {
        vadProviders.add(provider)
        logger.info("Registered VAD provider: ${provider.name}")
    }

    /**
     * Register a Language Model provider (e.g., llama.cpp)
     */
    fun registerLLM(provider: LLMServiceProvider) {
        llmProviders.add(provider)
        logger.info("Registered LLM provider: ${provider.name}")
    }

    /**
     * Register a Text-to-Speech provider
     */
    fun registerTTS(provider: TTSServiceProvider) {
        ttsProviders.add(provider)
        logger.info("Registered TTS provider: ${provider.name}")
    }

    /**
     * Register a Vision Language Model provider
     */
    fun registerVLM(provider: VLMServiceProvider) {
        vlmProviders.add(provider)
        logger.info("Registered VLM provider: ${provider.name}")
    }

    /**
     * Register a Wake Word Detection provider
     */
    fun registerWakeWord(provider: WakeWordServiceProvider) {
        wakeWordProviders.add(provider)
        logger.info("Registered Wake Word provider: ${provider.name}")
    }

    /**
     * Register a Speaker Diarization provider
     */
    fun registerSpeakerDiarization(provider: SpeakerDiarizationServiceProvider) {
        speakerDiarizationProviders.add(provider)
        logger.info("Registered Speaker Diarization provider: ${provider.name}")
    }

    // MARK: - Provider Access

    /**
     * Get an STT provider for the specified model
     */
    fun sttProvider(modelId: String? = null): STTServiceProvider? {
        return if (modelId != null) {
            sttProviders.firstOrNull { it.canHandle(modelId) }
        } else {
            sttProviders.firstOrNull()
        }
    }

    /**
     * Get a VAD provider for the specified model
     */
    fun vadProvider(modelId: String? = null): VADServiceProvider? {
        return if (modelId != null) {
            vadProviders.firstOrNull { it.canHandle(modelId) }
        } else {
            vadProviders.firstOrNull()
        }
    }

    /**
     * Get an LLM provider for the specified model
     */
    fun llmProvider(modelId: String? = null): LLMServiceProvider? {
        return if (modelId != null) {
            llmProviders.firstOrNull { it.canHandle(modelId) }
        } else {
            llmProviders.firstOrNull()
        }
    }

    /**
     * Get a TTS provider for the specified model
     */
    fun ttsProvider(modelId: String? = null): TTSServiceProvider? {
        return if (modelId != null) {
            ttsProviders.firstOrNull { it.canHandle(modelId) }
        } else {
            ttsProviders.firstOrNull()
        }
    }

    /**
     * Get a VLM provider for the specified model
     */
    fun vlmProvider(modelId: String? = null): VLMServiceProvider? {
        return if (modelId != null) {
            vlmProviders.firstOrNull { it.canHandle(modelId) }
        } else {
            vlmProviders.firstOrNull()
        }
    }

    /**
     * Get a Wake Word provider
     */
    fun wakeWordProvider(modelId: String? = null): WakeWordServiceProvider? {
        return if (modelId != null) {
            wakeWordProviders.firstOrNull { it.canHandle(modelId) }
        } else {
            wakeWordProviders.firstOrNull()
        }
    }

    /**
     * Get a Speaker Diarization provider
     */
    fun speakerDiarizationProvider(modelId: String? = null): SpeakerDiarizationServiceProvider? {
        return if (modelId != null) {
            speakerDiarizationProviders.firstOrNull { it.canHandle(modelId) }
        } else {
            speakerDiarizationProviders.firstOrNull()
        }
    }

    // MARK: - Availability Checking

    /**
     * Check if STT is available
     */
    val hasSTT: Boolean
        get() = sttProviders.isNotEmpty()

    /**
     * Check if VAD is available
     */
    val hasVAD: Boolean
        get() = vadProviders.isNotEmpty()

    /**
     * Check if LLM is available
     */
    val hasLLM: Boolean
        get() = llmProviders.isNotEmpty()

    /**
     * Check if TTS is available
     */
    val hasTTS: Boolean
        get() = ttsProviders.isNotEmpty()

    /**
     * Check if VLM is available
     */
    val hasVLM: Boolean
        get() = vlmProviders.isNotEmpty()

    /**
     * Check if Wake Word Detection is available
     */
    val hasWakeWord: Boolean
        get() = wakeWordProviders.isNotEmpty()

    /**
     * Check if Speaker Diarization is available
     */
    val hasSpeakerDiarization: Boolean
        get() = speakerDiarizationProviders.isNotEmpty()

    /**
     * Get list of all registered modules
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
    fun canHandle(modelId: String): Boolean
    val name: String
}

/**
 * Provider for Voice Activity Detection services
 */
interface VADServiceProvider {
    suspend fun createVADService(configuration: VADConfiguration): VADService
    fun canHandle(modelId: String): Boolean
    val name: String
}

/**
 * Provider for Language Model services
 */
interface LLMServiceProvider {
    suspend fun generate(prompt: String, options: com.runanywhere.sdk.generation.GenerationOptions): String
    fun generateStream(prompt: String, options: com.runanywhere.sdk.generation.GenerationOptions): kotlinx.coroutines.flow.Flow<String>
    fun canHandle(modelId: String): Boolean = true
    val name: String
}

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
    suspend fun createSpeakerDiarizationService(configuration: Any): Any // TODO: Add SpeakerDiarizationConfiguration
    fun canHandle(modelId: String): Boolean
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
