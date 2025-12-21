package com.runanywhere.sdk.core

import com.runanywhere.sdk.core.frameworks.UnifiedFrameworkAdapter
import com.runanywhere.sdk.data.models.SDKError
import com.runanywhere.sdk.features.llm.LLMConfiguration
import com.runanywhere.sdk.features.llm.LLMService
import com.runanywhere.sdk.features.llm.LLMServiceProvider
import com.runanywhere.sdk.features.speakerdiarization.SpeakerDiarizationConfiguration
import com.runanywhere.sdk.features.speakerdiarization.SpeakerDiarizationService
import com.runanywhere.sdk.features.stt.STTConfiguration
import com.runanywhere.sdk.features.stt.STTService
import com.runanywhere.sdk.features.tts.TTSConfiguration
import com.runanywhere.sdk.features.tts.TTSService
import com.runanywhere.sdk.features.vad.VADConfiguration
import com.runanywhere.sdk.features.vad.VADService
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.foundation.currentTimeMillis
import com.runanywhere.sdk.models.ModelInfo
import com.runanywhere.sdk.models.enums.FrameworkModality
import com.runanywhere.sdk.models.enums.InferenceFramework

// MARK: - Factory Type Aliases (matches iOS ServiceRegistry.swift lines 12-26)

/**
 * Factory closure types for service creation
 * Matches iOS pattern: typealias STTServiceFactory = @Sendable (STTConfiguration) async throws -> STTService
 */
typealias STTServiceFactory = suspend (STTConfiguration) -> STTService
typealias LLMServiceFactory = suspend (LLMConfiguration) -> LLMService
typealias TTSServiceFactory = suspend (TTSConfiguration) -> TTSService
typealias VADServiceFactory = suspend (VADConfiguration) -> VADService
typealias SpeakerDiarizationServiceFactory = suspend (SpeakerDiarizationConfiguration) -> SpeakerDiarizationService

/**
 * Registration structure for service factories
 * Matches iOS ServiceRegistration<Factory> structure (lines 30-47)
 *
 * @param name Display name of the provider
 * @param priority Priority for selection (higher = selected first)
 * @param canHandle Closure to check if this provider can handle a model ID
 * @param factory Closure to create the service
 */
data class ServiceRegistration<Factory>(
    val name: String,
    val priority: Int,
    val canHandle: (String?) -> Boolean,
    val factory: Factory,
    val registrationTime: Long = currentTimeMillis(),
)

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
 *
 * // Or register a full framework adapter:
 * ModuleRegistry.shared.registerFrameworkAdapter(ONNXAdapter())
 * ```
 *
 * Thread Safety:
 * All operations are synchronized using a mutex to prevent race conditions
 * during concurrent access. Registration can safely happen from multiple threads.
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Core/ModuleRegistry.swift
 */
object ModuleRegistry {
    private val logger = SDKLogger("ModuleRegistry")

    /**
     * Wrapper for registered adapters with priority and registration time
     * Matches iOS PrioritizedProvider pattern
     */
    private data class RegisteredAdapter(
        val adapter: UnifiedFrameworkAdapter,
        val priority: Int,
        val registrationTime: Long = currentTimeMillis(),
    )

    // Framework adapter storage - protected by synchronized blocks
    private val _frameworkAdapters = mutableListOf<RegisteredAdapter>()
    private val _adaptersByFramework = mutableMapOf<InferenceFramework, UnifiedFrameworkAdapter>()
    private val _adaptersByModality = mutableMapOf<FrameworkModality, MutableList<RegisteredAdapter>>()

    /**
     * Wrapper for registered providers with priority
     * Matches iOS ServiceRegistry.PrioritizedProvider pattern
     */
    private data class PrioritizedProvider<T>(
        val provider: T,
        val priority: Int,
        val registrationTime: Long = currentTimeMillis(),
    )

    // Provider lists - protected by synchronized blocks for thread safety
    // Matches iOS @MainActor pattern but using Kotlin's synchronized for cross-platform support
    // Now using PrioritizedProvider for priority-based selection
    private val _sttProviders = mutableListOf<PrioritizedProvider<STTServiceProvider>>()
    private val _vadProviders = mutableListOf<PrioritizedProvider<VADServiceProvider>>()
    private val _llmProviders = mutableListOf<PrioritizedProvider<LLMServiceProvider>>()
    private val _ttsProviders = mutableListOf<PrioritizedProvider<TTSServiceProvider>>()
    private val _speakerDiarizationProviders = mutableListOf<PrioritizedProvider<SpeakerDiarizationServiceProvider>>()

    // MARK: - Factory-Based Registrations (iOS Pattern - ServiceRegistry.swift lines 77-90)

    /**
     * Factory-based service registrations matching iOS ServiceRegistry pattern
     * These allow for closure-based service creation with direct createXXX methods
     */
    private val _sttRegistrations = mutableListOf<ServiceRegistration<STTServiceFactory>>()
    private val _llmRegistrations = mutableListOf<ServiceRegistration<LLMServiceFactory>>()
    private val _ttsRegistrations = mutableListOf<ServiceRegistration<TTSServiceFactory>>()
    private val _vadRegistrations = mutableListOf<ServiceRegistration<VADServiceFactory>>()
    private val _speakerDiarizationRegistrations = mutableListOf<ServiceRegistration<SpeakerDiarizationServiceFactory>>()

    // MARK: - Registration Methods

    /**
     * Default priority for providers (matches iOS defaultPriority = 100)
     */
    const val DEFAULT_PRIORITY = 100

    /**
     * Register a Speech-to-Text provider (e.g., WhisperCPP)
     * Thread-safe: Can be called from any thread
     *
     * @param provider The STT provider to register
     * @param priority Priority for selection (higher = selected first). Default is 100.
     */
    fun registerSTT(provider: STTServiceProvider, priority: Int = DEFAULT_PRIORITY) {
        synchronized(_sttProviders) {
            _sttProviders.add(PrioritizedProvider(provider, priority))
            // Sort by priority descending, then registration time ascending
            _sttProviders.sortWith(
                compareByDescending<PrioritizedProvider<STTServiceProvider>> { it.priority }
                    .thenBy { it.registrationTime },
            )
        }
        logger.info("Registered STT provider: ${provider.name} with priority $priority")
    }

    /**
     * Register a Voice Activity Detection provider
     * Thread-safe: Can be called from any thread
     *
     * @param provider The VAD provider to register
     * @param priority Priority for selection (higher = selected first). Default is 100.
     */
    fun registerVAD(provider: VADServiceProvider, priority: Int = DEFAULT_PRIORITY) {
        synchronized(_vadProviders) {
            _vadProviders.add(PrioritizedProvider(provider, priority))
            _vadProviders.sortWith(
                compareByDescending<PrioritizedProvider<VADServiceProvider>> { it.priority }
                    .thenBy { it.registrationTime },
            )
        }
        logger.info("Registered VAD provider: ${provider.name} with priority $priority")
    }

    /**
     * Register a Language Model provider (e.g., llama.cpp)
     * Thread-safe: Can be called from any thread
     *
     * @param provider The LLM provider to register
     * @param priority Priority for selection (higher = selected first). Default is 100.
     */
    fun registerLLM(provider: LLMServiceProvider, priority: Int = DEFAULT_PRIORITY) {
        synchronized(_llmProviders) {
            _llmProviders.add(PrioritizedProvider(provider, priority))
            _llmProviders.sortWith(
                compareByDescending<PrioritizedProvider<LLMServiceProvider>> { it.priority }
                    .thenBy { it.registrationTime },
            )
        }
        logger.info("Registered LLM provider: ${provider.name} with priority $priority")
    }

    /**
     * Register a Text-to-Speech provider
     * Thread-safe: Can be called from any thread
     *
     * @param provider The TTS provider to register
     * @param priority Priority for selection (higher = selected first). Default is 100.
     */
    fun registerTTS(provider: TTSServiceProvider, priority: Int = DEFAULT_PRIORITY) {
        synchronized(_ttsProviders) {
            _ttsProviders.add(PrioritizedProvider(provider, priority))
            _ttsProviders.sortWith(
                compareByDescending<PrioritizedProvider<TTSServiceProvider>> { it.priority }
                    .thenBy { it.registrationTime },
            )
        }
        logger.info("Registered TTS provider: ${provider.name} with priority $priority")
    }

    /**
     * Register a Speaker Diarization provider
     * Thread-safe: Can be called from any thread
     *
     * @param provider The Speaker Diarization provider to register
     * @param priority Priority for selection (higher = selected first). Default is 100.
     */
    fun registerSpeakerDiarization(provider: SpeakerDiarizationServiceProvider, priority: Int = DEFAULT_PRIORITY) {
        synchronized(_speakerDiarizationProviders) {
            _speakerDiarizationProviders.add(PrioritizedProvider(provider, priority))
            _speakerDiarizationProviders.sortWith(
                compareByDescending<PrioritizedProvider<SpeakerDiarizationServiceProvider>> { it.priority }
                    .thenBy { it.registrationTime },
            )
        }
        logger.info("Registered Speaker Diarization provider: ${provider.name} with priority $priority")
    }

    // MARK: - Factory-Based Registration (iOS Pattern)

    /**
     * Register an STT service factory with closure-based creation
     * Matches iOS ServiceRegistry.registerSTT(name:priority:canHandle:factory:)
     *
     * @param name Display name of the provider
     * @param priority Priority for selection (higher = selected first)
     * @param canHandle Closure to check if this provider can handle a model ID
     * @param factory Closure to create the STT service
     */
    fun registerSTTFactory(
        name: String,
        priority: Int = DEFAULT_PRIORITY,
        canHandle: (String?) -> Boolean = { true },
        factory: STTServiceFactory,
    ) {
        synchronized(_sttRegistrations) {
            val registration = ServiceRegistration(name, priority, canHandle, factory)
            _sttRegistrations.add(registration)
            _sttRegistrations.sortWith(
                compareByDescending<ServiceRegistration<STTServiceFactory>> { it.priority }
                    .thenBy { it.registrationTime },
            )
        }
        logger.info("Registered STT factory: $name with priority $priority")
    }

    /**
     * Register an LLM service factory with closure-based creation
     * Matches iOS ServiceRegistry.registerLLM(name:priority:canHandle:factory:)
     */
    fun registerLLMFactory(
        name: String,
        priority: Int = DEFAULT_PRIORITY,
        canHandle: (String?) -> Boolean = { true },
        factory: LLMServiceFactory,
    ) {
        synchronized(_llmRegistrations) {
            val registration = ServiceRegistration(name, priority, canHandle, factory)
            _llmRegistrations.add(registration)
            _llmRegistrations.sortWith(
                compareByDescending<ServiceRegistration<LLMServiceFactory>> { it.priority }
                    .thenBy { it.registrationTime },
            )
        }
        logger.info("Registered LLM factory: $name with priority $priority")
    }

    /**
     * Register a TTS service factory with closure-based creation
     * Matches iOS ServiceRegistry.registerTTS(name:priority:canHandle:factory:)
     */
    fun registerTTSFactory(
        name: String,
        priority: Int = DEFAULT_PRIORITY,
        canHandle: (String?) -> Boolean = { true },
        factory: TTSServiceFactory,
    ) {
        synchronized(_ttsRegistrations) {
            val registration = ServiceRegistration(name, priority, canHandle, factory)
            _ttsRegistrations.add(registration)
            _ttsRegistrations.sortWith(
                compareByDescending<ServiceRegistration<TTSServiceFactory>> { it.priority }
                    .thenBy { it.registrationTime },
            )
        }
        logger.info("Registered TTS factory: $name with priority $priority")
    }

    /**
     * Register a VAD service factory with closure-based creation
     * Matches iOS ServiceRegistry.registerVAD(name:priority:canHandle:factory:)
     */
    fun registerVADFactory(
        name: String,
        priority: Int = DEFAULT_PRIORITY,
        canHandle: (String?) -> Boolean = { true },
        factory: VADServiceFactory,
    ) {
        synchronized(_vadRegistrations) {
            val registration = ServiceRegistration(name, priority, canHandle, factory)
            _vadRegistrations.add(registration)
            _vadRegistrations.sortWith(
                compareByDescending<ServiceRegistration<VADServiceFactory>> { it.priority }
                    .thenBy { it.registrationTime },
            )
        }
        logger.info("Registered VAD factory: $name with priority $priority")
    }

    /**
     * Register a Speaker Diarization service factory with closure-based creation
     */
    fun registerSpeakerDiarizationFactory(
        name: String,
        priority: Int = DEFAULT_PRIORITY,
        canHandle: (String?) -> Boolean = { true },
        factory: SpeakerDiarizationServiceFactory,
    ) {
        synchronized(_speakerDiarizationRegistrations) {
            val registration = ServiceRegistration(name, priority, canHandle, factory)
            _speakerDiarizationRegistrations.add(registration)
            _speakerDiarizationRegistrations.sortWith(
                compareByDescending<ServiceRegistration<SpeakerDiarizationServiceFactory>> { it.priority }
                    .thenBy { it.registrationTime },
            )
        }
        logger.info("Registered Speaker Diarization factory: $name with priority $priority")
    }

    // MARK: - Direct Service Creation (iOS Pattern)

    /**
     * Create an STT service for the specified model
     * Matches iOS ServiceRegistry.createSTT(for:config:)
     *
     * @param modelId Optional model ID to match against providers
     * @param config Configuration for the STT service
     * @return The created STT service
     * @throws SDKError.ProviderNotFound if no provider can handle the model
     */
    suspend fun createSTT(
        modelId: String? = null,
        config: STTConfiguration,
    ): STTService {
        val registration =
            synchronized(_sttRegistrations) {
                _sttRegistrations.firstOrNull { it.canHandle(modelId) }
            } ?: throw SDKError.ProviderNotFound("STT provider for model: ${modelId ?: "default"}")

        logger.info("Creating STT service: ${registration.name} for model: ${modelId ?: "default"}")
        return registration.factory(config)
    }

    /**
     * Create an LLM service for the specified model
     * Matches iOS ServiceRegistry.createLLM(for:config:)
     */
    suspend fun createLLM(
        modelId: String? = null,
        config: LLMConfiguration,
    ): LLMService {
        val registration =
            synchronized(_llmRegistrations) {
                _llmRegistrations.firstOrNull { it.canHandle(modelId) }
            } ?: throw SDKError.ProviderNotFound("LLM provider for model: ${modelId ?: "default"}")

        logger.info("Creating LLM service: ${registration.name} for model: ${modelId ?: "default"}")
        return registration.factory(config)
    }

    /**
     * Create a TTS service for the specified model
     * Matches iOS ServiceRegistry.createTTS(for:config:)
     */
    suspend fun createTTS(
        modelId: String? = null,
        config: TTSConfiguration,
    ): TTSService {
        val registration =
            synchronized(_ttsRegistrations) {
                _ttsRegistrations.firstOrNull { it.canHandle(modelId) }
            } ?: throw SDKError.ProviderNotFound("TTS provider for model: ${modelId ?: "default"}")

        logger.info("Creating TTS service: ${registration.name} for model: ${modelId ?: "default"}")
        return registration.factory(config)
    }

    /**
     * Create a VAD service for the specified model
     * Matches iOS ServiceRegistry.createVAD(config:)
     */
    suspend fun createVAD(
        modelId: String? = null,
        config: VADConfiguration,
    ): VADService {
        val registration =
            synchronized(_vadRegistrations) {
                _vadRegistrations.firstOrNull { it.canHandle(modelId) }
            } ?: throw SDKError.ProviderNotFound("VAD provider for model: ${modelId ?: "default"}")

        logger.info("Creating VAD service: ${registration.name} for model: ${modelId ?: "default"}")
        return registration.factory(config)
    }

    /**
     * Create a Speaker Diarization service for the specified model
     */
    suspend fun createSpeakerDiarization(
        modelId: String? = null,
        config: SpeakerDiarizationConfiguration,
    ): SpeakerDiarizationService {
        val registration =
            synchronized(_speakerDiarizationRegistrations) {
                _speakerDiarizationRegistrations.firstOrNull { it.canHandle(modelId) }
            } ?: throw SDKError.ProviderNotFound("Speaker Diarization provider for model: ${modelId ?: "default"}")

        logger.info("Creating Speaker Diarization service: ${registration.name} for model: ${modelId ?: "default"}")
        return registration.factory(config)
    }

    // MARK: - Factory Registration Availability

    /**
     * Check if any STT factories are registered
     */
    val hasSTTFactory: Boolean
        get() = synchronized(_sttRegistrations) { _sttRegistrations.isNotEmpty() }

    /**
     * Check if any LLM factories are registered
     */
    val hasLLMFactory: Boolean
        get() = synchronized(_llmRegistrations) { _llmRegistrations.isNotEmpty() }

    /**
     * Check if any TTS factories are registered
     */
    val hasTTSFactory: Boolean
        get() = synchronized(_ttsRegistrations) { _ttsRegistrations.isNotEmpty() }

    /**
     * Check if any VAD factories are registered
     */
    val hasVADFactory: Boolean
        get() = synchronized(_vadRegistrations) { _vadRegistrations.isNotEmpty() }

    /**
     * Check if any Speaker Diarization factories are registered
     */
    val hasSpeakerDiarizationFactory: Boolean
        get() = synchronized(_speakerDiarizationRegistrations) { _speakerDiarizationRegistrations.isNotEmpty() }

    // MARK: - Framework Adapter Registration

    /**
     * Register a unified framework adapter with priority
     * The adapter's onRegistration() callback will be invoked to register service providers
     *
     * @param adapter The framework adapter to register
     * @param priority Priority for selection (higher = selected first). Default is 100.
     */
    fun registerFrameworkAdapter(
        adapter: UnifiedFrameworkAdapter,
        priority: Int = 100,
    ) {
        synchronized(_frameworkAdapters) {
            val registered = RegisteredAdapter(adapter, priority)

            // Add to main list
            _frameworkAdapters.add(registered)

            // Index by framework
            _adaptersByFramework[adapter.framework] = adapter

            // Index by each supported modality
            for (modality in adapter.supportedModalities) {
                val modalityList = _adaptersByModality.getOrPut(modality) { mutableListOf() }
                modalityList.add(registered)
                // Sort by priority (descending) then registration time (ascending)
                modalityList.sortWith(
                    compareByDescending<RegisteredAdapter> { it.priority }
                        .thenBy { it.registrationTime },
                )
            }
        }

        // Call the adapter's registration callback to register its service providers
        adapter.onRegistration()

        logger.info("Registered framework adapter: ${adapter.framework.displayName} with priority $priority")
    }

    /**
     * Get adapter for a specific framework
     * @param framework The framework to get adapter for
     * @return The adapter or null if not registered
     */
    fun adapterForFramework(framework: InferenceFramework): UnifiedFrameworkAdapter? =
        synchronized(_adaptersByFramework) {
            _adaptersByFramework[framework]
        }

    /**
     * Get all adapters that support a specific modality, sorted by priority
     * @param modality The modality to filter by
     * @return List of adapters supporting the modality
     */
    fun adaptersForModality(modality: FrameworkModality): List<UnifiedFrameworkAdapter> =
        synchronized(_adaptersByModality) {
            _adaptersByModality[modality]?.map { it.adapter } ?: emptyList()
        }

    /**
     * Find adapters that can handle a specific model for a modality
     * @param model The model to check
     * @param modality The modality to use
     * @return List of compatible adapters, sorted by priority
     */
    fun findAdapters(
        model: ModelInfo,
        modality: FrameworkModality,
    ): List<UnifiedFrameworkAdapter> =
        synchronized(_adaptersByModality) {
            _adaptersByModality[modality]
                ?.filter { it.adapter.canHandle(model) }
                ?.map { it.adapter }
                ?: emptyList()
        }

    /**
     * Find the best adapter for a model and modality
     * Selection strategy:
     * 1. Model's preferred framework (if set and available)
     * 2. First compatible framework from model's compatibleFrameworks
     * 3. First compatible adapter by priority
     *
     * @param model The model to check
     * @param modality The modality to use
     * @return Best matching adapter or null
     */
    fun findBestAdapter(
        model: ModelInfo,
        modality: FrameworkModality,
    ): UnifiedFrameworkAdapter? {
        return synchronized(_adaptersByModality) {
            val compatibleAdapters =
                _adaptersByModality[modality]
                    ?.filter { it.adapter.canHandle(model) }
                    ?: return null

            if (compatibleAdapters.isEmpty()) return null

            // Strategy 1: Check model's preferred framework
            model.preferredFramework?.let { preferred ->
                compatibleAdapters.find { it.adapter.framework == preferred }?.let {
                    return it.adapter
                }
            }

            // Strategy 2: Check model's compatible frameworks in order
            for (framework in model.compatibleFrameworks) {
                compatibleAdapters.find { it.adapter.framework == framework }?.let {
                    return it.adapter
                }
            }

            // Strategy 3: Return highest priority adapter
            compatibleAdapters.firstOrNull()?.adapter
        }
    }

    /**
     * Get all registered framework adapters
     * @return List of all adapters
     */
    val allFrameworkAdapters: List<UnifiedFrameworkAdapter>
        get() = synchronized(_frameworkAdapters) { _frameworkAdapters.map { it.adapter } }

    /**
     * Get all registered frameworks
     * @return Set of frameworks that have adapters registered
     */
    val registeredFrameworks: Set<InferenceFramework>
        get() = synchronized(_adaptersByFramework) { _adaptersByFramework.keys.toSet() }

    /**
     * Check if a framework has a registered adapter
     * @param framework The framework to check
     * @return True if an adapter is registered
     */
    fun hasFramework(framework: InferenceFramework): Boolean =
        synchronized(_adaptersByFramework) { _adaptersByFramework.containsKey(framework) }

    /**
     * Get model storage strategy for a specific framework
     * @param framework The framework to get storage strategy for
     * @return Storage strategy if available, null otherwise
     */
    fun getStorageStrategy(framework: InferenceFramework): com.runanywhere.sdk.core.frameworks.ModelStorageStrategy? =
        synchronized(_adaptersByFramework) {
            _adaptersByFramework[framework]?.getModelStorageStrategy()
        }

    /**
     * Get all registered model storage strategies
     * @return Map of framework to storage strategy
     */
    val allStorageStrategies: Map<InferenceFramework, com.runanywhere.sdk.core.frameworks.ModelStorageStrategy>
        get() =
            synchronized(_adaptersByFramework) {
                _adaptersByFramework
                    .mapNotNull { (framework, adapter) ->
                        adapter.getModelStorageStrategy()?.let { framework to it }
                    }.toMap()
            }

    // MARK: - Provider Access

    /**
     * Get an STT provider for the specified model
     * Returns the highest-priority provider that can handle the model
     * Thread-safe: Can be called from any thread
     */
    fun sttProvider(modelId: String? = null): STTServiceProvider? =
        synchronized(_sttProviders) {
            if (modelId != null) {
                _sttProviders.firstOrNull { it.provider.canHandle(modelId) }?.provider
            } else {
                _sttProviders.firstOrNull()?.provider
            }
        }

    /**
     * Get a VAD provider for the specified model
     * Returns the highest-priority provider that can handle the model
     * Thread-safe: Can be called from any thread
     */
    fun vadProvider(modelId: String? = null): VADServiceProvider? =
        synchronized(_vadProviders) {
            if (modelId != null) {
                _vadProviders.firstOrNull { it.provider.canHandle(modelId) }?.provider
            } else {
                _vadProviders.firstOrNull()?.provider
            }
        }

    /**
     * Get an LLM provider for the specified model
     * Returns the highest-priority provider that can handle the model
     * Thread-safe: Can be called from any thread
     */
    fun llmProvider(modelId: String? = null): LLMServiceProvider? =
        synchronized(_llmProviders) {
            if (modelId != null) {
                _llmProviders.firstOrNull { it.provider.canHandle(modelId) }?.provider
            } else {
                _llmProviders.firstOrNull()?.provider
            }
        }

    /**
     * Get a TTS provider for the specified model
     * Returns the highest-priority provider that can handle the model
     * Thread-safe: Can be called from any thread
     */
    fun ttsProvider(modelId: String? = null): TTSServiceProvider? =
        synchronized(_ttsProviders) {
            if (modelId != null) {
                _ttsProviders.firstOrNull { it.provider.canHandle(modelId) }?.provider
            } else {
                _ttsProviders.firstOrNull()?.provider
            }
        }

    /**
     * Get a Speaker Diarization provider
     * Returns the highest-priority provider that can handle the model
     * Thread-safe: Can be called from any thread
     */
    fun speakerDiarizationProvider(modelId: String? = null): SpeakerDiarizationServiceProvider? =
        synchronized(_speakerDiarizationProviders) {
            if (modelId != null) {
                _speakerDiarizationProviders.firstOrNull { it.provider.canHandle(modelId) }?.provider
            } else {
                _speakerDiarizationProviders.firstOrNull()?.provider
            }
        }

    // MARK: - Provider List Access (for framework management)

    /**
     * Get all registered STT providers, sorted by priority
     * Thread-safe: Returns a snapshot of the current provider list
     */
    val allSTTProviders: List<STTServiceProvider>
        get() = synchronized(_sttProviders) { _sttProviders.map { it.provider } }

    /**
     * Get all registered LLM providers, sorted by priority
     * Thread-safe: Returns a snapshot of the current provider list
     */
    val allLLMProviders: List<LLMServiceProvider>
        get() = synchronized(_llmProviders) { _llmProviders.map { it.provider } }

    /**
     * Get all registered TTS providers, sorted by priority
     * Thread-safe: Returns a snapshot of the current provider list
     */
    val allTTSProviders: List<TTSServiceProvider>
        get() = synchronized(_ttsProviders) { _ttsProviders.map { it.provider } }

    /**
     * Get all registered VAD providers, sorted by priority
     * Thread-safe: Returns a snapshot of the current provider list
     */
    val allVADProviders: List<VADServiceProvider>
        get() = synchronized(_vadProviders) { _vadProviders.map { it.provider } }

    /**
     * Get all registered Speaker Diarization providers, sorted by priority
     * Thread-safe: Returns a snapshot of the current provider list
     */
    val allSpeakerDiarizationProviders: List<SpeakerDiarizationServiceProvider>
        get() = synchronized(_speakerDiarizationProviders) { _speakerDiarizationProviders.map { it.provider } }

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
        get() =
            buildList {
                if (hasSTT) add("STT")
                if (hasVAD) add("VAD")
                if (hasLLM) add("LLM")
                if (hasTTS) add("TTS")
                if (hasSpeakerDiarization) add("SpeakerDiarization")
            }

    /**
     * Get provider count for each capability
     * Returns a summary of all registered providers with their counts
     */
    val providerSummary: Map<String, Int>
        get() =
            mapOf(
                "STT" to synchronized(_sttProviders) { _sttProviders.size },
                "VAD" to synchronized(_vadProviders) { _vadProviders.size },
                "LLM" to synchronized(_llmProviders) { _llmProviders.size },
                "TTS" to synchronized(_ttsProviders) { _ttsProviders.size },
                "SpeakerDiarization" to synchronized(_speakerDiarizationProviders) { _speakerDiarizationProviders.size },
            )

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
    val framework: InferenceFramework
}

/**
 * Provider for Voice Activity Detection services
 */
interface VADServiceProvider {
    suspend fun createVADService(configuration: VADConfiguration): VADService

    fun canHandle(modelId: String): Boolean

    val name: String
}

// LLMServiceProvider is now imported from com.runanywhere.sdk.features.llm.LLMServiceProvider

/**
 * Provider for Text-to-Speech services
 */
interface TTSServiceProvider {
    suspend fun synthesize(
        text: String,
        options: com.runanywhere.sdk.features.tts.TTSOptions,
    ): ByteArray

    fun synthesizeStream(
        text: String,
        options: com.runanywhere.sdk.features.tts.TTSOptions,
    ): kotlinx.coroutines.flow.Flow<ByteArray>

    fun canHandle(modelId: String): Boolean = true

    val name: String

    /** Framework this provider supports */
    val framework: InferenceFramework
}

/**
 * Provider for Speaker Diarization services
 */
interface SpeakerDiarizationServiceProvider {
    suspend fun createSpeakerDiarizationService(
        configuration: com.runanywhere.sdk.features.speakerdiarization.SpeakerDiarizationConfiguration,
    ): com.runanywhere.sdk.features.speakerdiarization.SpeakerDiarizationService

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
