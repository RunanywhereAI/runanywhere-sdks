package com.runanywhere.sdk.core.onnx

import com.runanywhere.sdk.core.CapabilityType
import com.runanywhere.sdk.core.ModuleDiscovery
import com.runanywhere.sdk.core.ModuleRegistryMetadata
import com.runanywhere.sdk.core.RunAnywhereModule
import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.models.enums.InferenceFramework
import com.runanywhere.sdk.storage.ModelStorageStrategy

/**
 * ONNX Runtime module for STT and TTS services.
 *
 * Provides speech-to-text and text-to-speech capabilities using
 * ONNX Runtime with models like Whisper and Piper.
 *
 * Matches iOS ONNX enum exactly.
 *
 * ## Registration
 *
 * ```kotlin
 * import com.runanywhere.sdk.core.onnx.ONNX
 *
 * // Option 1: Direct registration
 * ONNX.register()
 *
 * // Option 2: Via ModuleDiscovery (auto-discovery)
 * ModuleDiscovery.registerDiscoveredModules()
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
 *
 * Reference: sdk/runanywhere-swift/Sources/ONNXRuntime/ONNXServiceProvider.swift
 */
object ONNX : RunAnywhereModule {
    private val logger = SDKLogger("ONNX")

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
     * Storage strategy for ONNX models (handles nested directory structures)
     * Matches iOS: public static let storageStrategy: ModelStorageStrategy? = ONNXModelStorageStrategy()
     */
    override val storageStrategy: ModelStorageStrategy = ONNXModelStorageStrategy()

    /**
     * Register all ONNX services with the SDK
     * Matches iOS: @MainActor public static func register(priority: Int)
     *
     * @param priority Registration priority (higher values are preferred)
     */
    override fun register(priority: Int) {
        // Check for duplicate registration
        if (ModuleRegistryMetadata.isRegistered(moduleId)) {
            logger.warning("ONNX module already registered, skipping")
            return
        }

        // Register individual services
        registerSTT(priority)
        registerTTS(priority)
        registerVAD(priority)

        // Register module metadata for tracking
        ModuleRegistryMetadata.registerModule(this, priority)

        logger.info("ONNX module registered (STT + TTS + VAD) with priority $priority")
    }

    // MARK: - Individual Service Registration

    /**
     * Register only ONNX STT service
     * Matches iOS: @MainActor public static func registerSTT(priority: Int = 100)
     */
    fun registerSTT(priority: Int = 100) {
        ONNXSTTServiceProvider.register(priority)
        logger.info("ONNX STT registered with priority $priority")
    }

    /**
     * Register only ONNX TTS service
     * Matches iOS: @MainActor public static func registerTTS(priority: Int = 100)
     */
    fun registerTTS(priority: Int = 100) {
        ONNXTTSServiceProvider.register(priority)
        logger.info("ONNX TTS registered with priority $priority")
    }

    /**
     * Register only ONNX VAD service
     */
    fun registerVAD(priority: Int = 100) {
        ONNXVADServiceProvider.register(priority)
        logger.info("ONNX VAD registered with priority $priority")
    }

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
