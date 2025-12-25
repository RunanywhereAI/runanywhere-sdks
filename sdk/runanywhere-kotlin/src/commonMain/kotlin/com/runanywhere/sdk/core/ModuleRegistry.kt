package com.runanywhere.sdk.core

import com.runanywhere.sdk.data.models.SDKError
import com.runanywhere.sdk.features.llm.LLMConfiguration
import com.runanywhere.sdk.features.llm.LLMService
import com.runanywhere.sdk.features.speakerdiarization.SpeakerDiarizationConfiguration
import com.runanywhere.sdk.features.speakerdiarization.SpeakerDiarizationService
import com.runanywhere.sdk.features.stt.STTConfiguration
import com.runanywhere.sdk.features.stt.STTService
import com.runanywhere.sdk.features.tts.TTSConfiguration
import com.runanywhere.sdk.features.tts.TTSService
import com.runanywhere.sdk.features.vad.VADConfiguration
import com.runanywhere.sdk.features.vad.VADService
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.infrastructure.download.DownloadStrategy
import com.runanywhere.sdk.models.ModelInfo
import com.runanywhere.sdk.models.enums.InferenceFramework
import com.runanywhere.sdk.storage.ModelStorageStrategy

/**
 * Simple service factory type aliases
 */
typealias STTServiceFactory = suspend (STTConfiguration) -> STTService
typealias LLMServiceFactory = suspend (LLMConfiguration) -> LLMService
typealias TTSServiceFactory = suspend (TTSConfiguration) -> TTSService
typealias VADServiceFactory = suspend (VADConfiguration) -> VADService
typealias SpeakerDiarizationServiceFactory = suspend (SpeakerDiarizationConfiguration) -> SpeakerDiarizationService

/**
 * Central registry for modules and their services.
 *
 * Simple architecture:
 * - Modules register themselves with their capabilities
 * - Each module provides service factories for what it supports
 * - Registry finds the right factory and creates the service
 */
object ModuleRegistry {
    private val logger = SDKLogger("ModuleRegistry")

    // Registered modules
    private val modules = mutableMapOf<String, RunAnywhereModule>()

    // Service factories (one per capability, from the module that provides it)
    private var sttFactory: Pair<String, STTServiceFactory>? = null
    private var llmFactory: Pair<String, LLMServiceFactory>? = null
    private var ttsFactory: Pair<String, TTSServiceFactory>? = null
    private var vadFactory: Pair<String, VADServiceFactory>? = null
    private var speakerDiarizationFactory: Pair<String, SpeakerDiarizationServiceFactory>? = null

    // Strategies (from modules)
    private val storageStrategies = mutableMapOf<InferenceFramework, ModelStorageStrategy>()
    private val downloadStrategies = mutableMapOf<InferenceFramework, DownloadStrategy>()

    // MARK: - Module Registration

    /**
     * Register a module with the SDK.
     * This stores the module metadata and calls registerServices() to set up factories.
     *
     * Matches iOS ModuleRegistry.register(_:priority:)
     *
     * @param module The module to register
     * @param priority Override the default priority (optional)
     */
    fun register(module: RunAnywhereModule, priority: Int? = null) {
        val effectivePriority = priority ?: module.defaultPriority

        if (modules.containsKey(module.moduleId)) {
            logger.warning("Module '${module.moduleId}' already registered")
            return
        }

        // Let the module register its services (this should NOT call back to ModuleRegistry)
        module.registerServices(effectivePriority)

        // Store the module
        modules[module.moduleId] = module

        // Store strategies if provided
        module.storageStrategy?.let {
            storageStrategies[module.inferenceFramework] = it
            logger.info("Storage strategy registered for ${module.inferenceFramework.value}")
        }
        module.downloadStrategy?.let {
            downloadStrategies[module.inferenceFramework] = it
            logger.info("Download strategy registered for ${module.inferenceFramework.value}")
        }

        logger.info("Module registered: ${module.moduleName} [${module.moduleId}] with capabilities: ${module.capabilities.map { it.value }.joinToString(", ")}")
    }

    // MARK: - Service Factory Registration (called by modules)

    fun registerSTT(name: String, factory: STTServiceFactory) {
        sttFactory = name to factory
        logger.info("STT service registered: $name")
    }

    fun registerLLM(name: String, factory: LLMServiceFactory) {
        llmFactory = name to factory
        logger.info("LLM service registered: $name")
    }

    fun registerTTS(name: String, factory: TTSServiceFactory) {
        ttsFactory = name to factory
        logger.info("TTS service registered: $name")
    }

    fun registerVAD(name: String, factory: VADServiceFactory) {
        vadFactory = name to factory
        logger.info("VAD service registered: $name")
    }

    fun registerSpeakerDiarization(name: String, factory: SpeakerDiarizationServiceFactory) {
        speakerDiarizationFactory = name to factory
        logger.info("Speaker Diarization service registered: $name")
    }

    // MARK: - Service Creation

    suspend fun createSTT(config: STTConfiguration): STTService {
        val (name, factory) = sttFactory
            ?: throw SDKError.ProviderNotFound("No STT service registered")
        logger.info("Creating STT service: $name")
        return factory(config)
    }

    suspend fun createLLM(config: LLMConfiguration): LLMService {
        val (name, factory) = llmFactory
            ?: throw SDKError.ProviderNotFound("No LLM service registered")
        logger.info("Creating LLM service: $name")
        return factory(config)
    }

    suspend fun createTTS(config: TTSConfiguration): TTSService {
        val (name, factory) = ttsFactory
            ?: throw SDKError.ProviderNotFound("No TTS service registered")
        logger.info("Creating TTS service: $name")
        return factory(config)
    }

    suspend fun createVAD(config: VADConfiguration): VADService {
        val (name, factory) = vadFactory
            ?: throw SDKError.ProviderNotFound("No VAD service registered")
        logger.info("Creating VAD service: $name")
        return factory(config)
    }

    suspend fun createSpeakerDiarization(config: SpeakerDiarizationConfiguration): SpeakerDiarizationService {
        val (name, factory) = speakerDiarizationFactory
            ?: throw SDKError.ProviderNotFound("No Speaker Diarization service registered")
        logger.info("Creating Speaker Diarization service: $name")
        return factory(config)
    }

    // MARK: - Availability

    val hasSTT: Boolean get() = sttFactory != null
    val hasLLM: Boolean get() = llmFactory != null
    val hasTTS: Boolean get() = ttsFactory != null
    val hasVAD: Boolean get() = vadFactory != null
    val hasSpeakerDiarization: Boolean get() = speakerDiarizationFactory != null

    val registeredCapabilities: List<String>
        get() = buildList {
            if (hasSTT) add("STT")
            if (hasLLM) add("LLM")
            if (hasTTS) add("TTS")
            if (hasVAD) add("VAD")
            if (hasSpeakerDiarization) add("SpeakerDiarization")
        }

    // Backward compatibility alias
    val registeredModules: List<String> get() = registeredCapabilities

    // MARK: - Module Queries

    fun isRegistered(moduleId: String): Boolean = modules.containsKey(moduleId)

    fun getModule(moduleId: String): RunAnywhereModule? = modules[moduleId]

    val allModules: List<RunAnywhereModule> get() = modules.values.toList()

    // MARK: - Strategies

    fun storageStrategy(framework: InferenceFramework): ModelStorageStrategy? =
        storageStrategies[framework]

    fun downloadStrategy(framework: InferenceFramework): DownloadStrategy? =
        downloadStrategies[framework]

    fun downloadStrategy(model: ModelInfo): DownloadStrategy? {
        model.preferredFramework?.let { framework ->
            downloadStrategies[framework]?.let { if (it.canHandle(model)) return it }
        }
        for (framework in model.compatibleFrameworks) {
            downloadStrategies[framework]?.let { if (it.canHandle(model)) return it }
        }
        return null
    }

    val allDownloadStrategies: List<DownloadStrategy>
        get() = downloadStrategies.values.toList()

    // MARK: - Reset

    fun reset() {
        modules.clear()
        sttFactory = null
        llmFactory = null
        ttsFactory = null
        vadFactory = null
        speakerDiarizationFactory = null
        storageStrategies.clear()
        downloadStrategies.clear()
        logger.info("Registry reset")
    }

    // Singleton accessor
    val shared: ModuleRegistry get() = this
}
