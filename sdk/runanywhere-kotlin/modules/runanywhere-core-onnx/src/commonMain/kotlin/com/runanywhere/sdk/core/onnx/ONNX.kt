package com.runanywhere.sdk.core.onnx

import com.runanywhere.sdk.core.CapabilityType
import com.runanywhere.sdk.core.ModuleDiscovery
import com.runanywhere.sdk.core.ModuleRegistry
import com.runanywhere.sdk.core.RunAnywhereModule
import com.runanywhere.sdk.features.stt.STTConfiguration
import com.runanywhere.sdk.features.stt.STTService
import com.runanywhere.sdk.features.tts.TTSConfiguration
import com.runanywhere.sdk.features.tts.TTSService
import com.runanywhere.sdk.features.vad.VADConfiguration
import com.runanywhere.sdk.features.vad.VADService
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.foundation.ServiceContainer
import com.runanywhere.sdk.infrastructure.download.DownloadStrategy
import com.runanywhere.sdk.models.enums.InferenceFramework
import com.runanywhere.sdk.storage.ModelStorageStrategy

/**
 * ONNX Runtime module for STT and TTS services.
 *
 * Provides speech-to-text and text-to-speech capabilities using
 * ONNX Runtime with models like Whisper and Piper.
 *
 * EXACTLY matches iOS ONNX enum implementation.
 * Reference: sdk/runanywhere-swift/Sources/ONNXRuntime/ONNXServiceProvider.swift
 *
 * ## Registration
 *
 * ```kotlin
 * import com.runanywhere.sdk.core.onnx.ONNX
 *
 * // Direct registration (recommended)
 * ONNX.register()
 *
 * // With custom priority
 * ONNX.register(priority = 200)
 * ```
 *
 * ## Adding Models
 *
 * ```kotlin
 * ONNX.register()
 *
 * // Add STT model
 * ONNX.addModel(
 *     name = "Whisper Small (English)",
 *     url = "https://example.com/whisper-small-en.tar.gz",
 *     modality = ModelCategory.SPEECH_RECOGNITION,
 *     memoryRequirement = 500_000_000L
 * )
 *
 * // Add TTS model
 * ONNX.addModel(
 *     name = "Piper English Voice",
 *     url = "https://example.com/piper-en.tar.gz",
 *     modality = ModelCategory.SPEECH_SYNTHESIS,
 *     memoryRequirement = 100_000_000L
 * )
 * ```
 *
 * ## Usage
 *
 * ```kotlin
 * // STT Usage
 * RunAnywhere.loadSTTModel("my-stt-model")
 * val text = RunAnywhere.transcribe(audioData)
 *
 * // TTS Usage
 * RunAnywhere.loadTTSModel("my-tts-model")
 * val audio = RunAnywhere.synthesize("Hello, world!")
 * ```
 */
object ONNX : RunAnywhereModule {
    private val logger = SDKLogger("ONNX")

    // Track if we're already registered to avoid duplicate work
    @Volatile
    private var servicesRegistered = false

    // MARK: - RunAnywhereModule Conformance

    override val moduleId: String = "onnx"

    override val moduleName: String = "ONNX Runtime"

    override val capabilities: Set<CapabilityType> = setOf(CapabilityType.STT, CapabilityType.TTS)

    override val defaultPriority: Int = 100

    /**
     * ONNX uses the ONNX Runtime inference framework
     */
    override val inferenceFramework: InferenceFramework = InferenceFramework.ONNX

    /**
     * Download strategy for ONNX models - handles .tar.gz/.tar.bz2 archive extraction
     * Matches iOS ONNXModelStorageStrategy.downloadStrategy pattern
     */
    override val downloadStrategy: DownloadStrategy = ONNXDownloadStrategy.shared

    /**
     * Storage strategy for detecting ONNX models on disk
     * Handles nested directory structures from sherpa-onnx archives
     */
    override val storageStrategy: ModelStorageStrategy = ONNXDownloadStrategy.shared

    /**
     * Version of ONNX Runtime used
     */
    const val VERSION: String = "1.23.2"

    /**
     * Register ONNX module with the SDK.
     * This is what app code should call: ONNX.register()
     *
     * Matches iOS: LlamaCPP.register() / ONNX.register()
     *
     * @param priority Registration priority (higher values are preferred)
     */
    @JvmStatic
    @JvmOverloads
    fun register(priority: Int = defaultPriority) {
        // Register through ModuleRegistry which stores metadata and calls registerServices
        ModuleRegistry.shared.register(this, priority)
    }

    /**
     * Internal: Register only the services (called by ModuleRegistry)
     * Matches iOS register(priority:) which only registers with ServiceRegistry
     */
    override fun registerServices(priority: Int) {
        if (servicesRegistered) {
            logger.info("ONNX services already registered")
            return
        }

        // Register services using factory closures (matching iOS exactly)
        registerSTT(priority)
        registerTTS(priority)
        registerVAD(priority)

        servicesRegistered = true
        logger.info("ONNX module services registered (STT + TTS + VAD) with priority $priority")
    }

    // MARK: - Individual Service Registration (matching iOS exactly)

    /**
     * Register only ONNX STT service
     */
    @Suppress("UnusedParameter")
    private fun registerSTT(priority: Int = 100) {
        ModuleRegistry.shared.registerSTT(moduleName) { config -> createSTTService(config) }
        logger.info("ONNX STT registered")
    }

    /**
     * Register only ONNX TTS service
     */
    @Suppress("UnusedParameter")
    private fun registerTTS(priority: Int = 100) {
        ModuleRegistry.shared.registerTTS("ONNX TTS") { config -> createTTSService(config) }
        logger.info("ONNX TTS registered")
    }

    /**
     * Register only ONNX VAD service
     */
    @Suppress("UnusedParameter")
    private fun registerVAD(priority: Int = 100) {
        ModuleRegistry.shared.registerVAD("ONNX VAD") { config -> createVADService(config) }
        logger.info("ONNX VAD registered")
    }

    // MARK: - STT Helpers

    /**
     * Create an STT service with the given configuration
     * Matches iOS createSTTService(config:) implementation
     */
    private suspend fun createSTTService(config: STTConfiguration): STTService {
        logger.info("Creating ONNX STT service for model: ${config.modelId ?: "unknown"}")

        var modelPath: String? = null
        if (config.modelId != null) {
            val modelInfo = ServiceContainer.shared.modelRegistry.getModel(config.modelId!!)

            if (modelInfo?.localPath != null) {
                modelPath = modelInfo.localPath
                logger.info("Found local model path: $modelPath")
            } else {
                logger.error("Model '${config.modelId}' is not downloaded")
                throw ONNXError.ModelNotFound(config.modelId!!)
            }
        }

        val service = createONNXSTTService(config)
        logger.info("ONNX STT service created successfully")
        return service
    }

    // MARK: - TTS Helpers

    /**
     * Create a TTS service with the given configuration
     * Matches iOS createTTSService(config:) implementation
     */
    private suspend fun createTTSService(config: TTSConfiguration): TTSService {
        val modelId = config.modelId ?: throw ONNXError.ModelNotFound("No model ID specified")
        logger.info("Creating ONNX TTS service for voice: $modelId")

        // Get the actual model file path from the model registry
        val modelInfo = ServiceContainer.shared.modelRegistry.getModel(modelId)
        val modelPath = modelInfo?.localPath

        if (modelPath != null) {
            logger.info("Found local model path: $modelPath")
            logger.info("Creating ONNXTTSService with path: $modelPath")
        } else {
            logger.error("TTS Model '$modelId' is not downloaded")
            throw ONNXError.ModelNotFound(modelId)
        }

        val service = createONNXTTSService(config)
        logger.info("ONNX TTS service initialized successfully")
        return service
    }

    // MARK: - VAD Helpers

    /**
     * Create a VAD service with the given configuration
     */
    private suspend fun createVADService(config: VADConfiguration): VADService {
        logger.info("Creating ONNX VAD service")
        return createONNXVADService(config)
    }

    // MARK: - Auto-Discovery Registration

    /**
     * Enable auto-discovery for this module.
     * Access this property to trigger registration.
     * Matches iOS: public static let autoRegister: Void
     */
    val autoRegister: Unit by lazy {
        ModuleDiscovery.register(this)
    }

    // Force initialization of auto-register when the object is accessed
    init {
        ModuleDiscovery.register(this)
    }
}

// MARK: - Platform-specific service creation (expect declarations)

/**
 * Create an ONNX STT service with the given configuration.
 * Platform-specific implementation in jvmAndroidMain.
 */
internal expect suspend fun createONNXSTTService(configuration: STTConfiguration): STTService

/**
 * Create an ONNX TTS service with the given configuration.
 * Platform-specific implementation in jvmAndroidMain.
 */
internal expect suspend fun createONNXTTSService(configuration: TTSConfiguration): TTSService

/**
 * Create an ONNX VAD service with the given configuration.
 * Platform-specific implementation in jvmAndroidMain.
 */
internal expect suspend fun createONNXVADService(configuration: VADConfiguration): VADService
