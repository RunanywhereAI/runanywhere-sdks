/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * CppBridge extension for diffusion image generation.
 * Manages the C++ rac_diffusion_component lifecycle via JNI.
 *
 * Mirrors Swift CppBridge+Diffusion.swift exactly.
 */

package com.runanywhere.sdk.foundation.bridge.extensions

import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge
import com.runanywhere.sdk.public.extensions.Diffusion.DiffusionConfiguration
import com.runanywhere.sdk.public.extensions.Diffusion.DiffusionGenerationOptions
import com.runanywhere.sdk.public.extensions.Diffusion.DiffusionInfo
import com.runanywhere.sdk.public.extensions.Diffusion.DiffusionModelVariant
import com.runanywhere.sdk.public.extensions.Diffusion.DiffusionProgress
import com.runanywhere.sdk.public.extensions.Diffusion.DiffusionResult

/**
 * Bridge between Kotlin diffusion API and C++ rac_diffusion_component.
 *
 * Manages handle lifecycle, state transitions, and JNI calls.
 * Thread-safe via synchronized blocks (mirrors Swift actor pattern).
 */
object CppBridgeDiffusion {
    private const val TAG = "CppBridge.Diffusion"

    // ========================================================================
    // STATE
    // ========================================================================

    object DiffusionState {
        const val NOT_CREATED = 0
        const val CREATED = 1
        const val LOADING = 2
        const val READY = 3
        const val GENERATING = 4
        const val UNLOADING = 5
        const val ERROR = 6

        fun getName(state: Int): String = when (state) {
            NOT_CREATED -> "NOT_CREATED"
            CREATED -> "CREATED"
            LOADING -> "LOADING"
            READY -> "READY"
            GENERATING -> "GENERATING"
            UNLOADING -> "UNLOADING"
            ERROR -> "ERROR"
            else -> "UNKNOWN($state)"
        }

        fun isReady(state: Int): Boolean = state == READY
    }

    @Volatile private var state: Int = DiffusionState.NOT_CREATED
    @Volatile private var handle: Long = 0
    @Volatile private var loadedModelId: String? = null
    @Volatile private var loadedModelPath: String? = null
    @Volatile private var isCancelled: Boolean = false
    private val lock = Any()

    private val logger = SDKLogger(TAG)

    val shared: CppBridgeDiffusion = this

    // ========================================================================
    // LIFECYCLE
    // ========================================================================

    fun create(): Boolean {
        synchronized(lock) {
            if (handle != 0L) {
                logger.debug("Diffusion component already created")
                return true
            }

            if (!RunAnywhereBridge.ensureNativeLibraryLoaded()) {
                logger.error("Native library not loaded")
                return false
            }

            handle = RunAnywhereBridge.racDiffusionComponentCreate()
            if (handle == 0L) {
                logger.error("Failed to create diffusion component")
                state = DiffusionState.ERROR
                return false
            }

            state = DiffusionState.CREATED
            logger.info("Diffusion component created (handle=$handle)")
            return true
        }
    }

    fun configure(configuration: DiffusionConfiguration): Boolean {
        synchronized(lock) {
            if (handle == 0L && !create()) return false

            val json = configuration.toJson()
            val result = RunAnywhereBridge.racDiffusionComponentConfigure(handle, json)
            if (result != RunAnywhereBridge.RAC_SUCCESS) {
                logger.error("Configure failed: $result")
                return false
            }
            logger.debug("Configured: $json")
            return true
        }
    }

    fun loadModel(modelPath: String, modelId: String, modelName: String? = null): Boolean {
        synchronized(lock) {
            if (handle == 0L && !create()) return false

            state = DiffusionState.LOADING
            logger.info("Loading diffusion model: $modelId at $modelPath")

            val result = RunAnywhereBridge.racDiffusionComponentLoadModel(
                handle, modelPath, modelId, modelName,
            )

            if (result != RunAnywhereBridge.RAC_SUCCESS) {
                logger.error("Load model failed: $result")
                state = DiffusionState.ERROR
                return false
            }

            loadedModelId = modelId
            loadedModelPath = modelPath
            state = DiffusionState.READY
            logger.info("Diffusion model loaded: $modelId")
            return true
        }
    }

    fun unload(): Boolean {
        synchronized(lock) {
            if (handle == 0L) return true

            state = DiffusionState.UNLOADING
            val result = RunAnywhereBridge.racDiffusionComponentUnload(handle)
            loadedModelId = null
            loadedModelPath = null
            state = DiffusionState.CREATED

            if (result != RunAnywhereBridge.RAC_SUCCESS) {
                logger.error("Unload failed: $result")
                return false
            }
            logger.info("Diffusion model unloaded")
            return true
        }
    }

    fun destroy() {
        synchronized(lock) {
            if (handle == 0L) return
            RunAnywhereBridge.racDiffusionComponentDestroy(handle)
            handle = 0
            state = DiffusionState.NOT_CREATED
            loadedModelId = null
            loadedModelPath = null
            logger.info("Diffusion component destroyed")
        }
    }

    // ========================================================================
    // GENERATION
    // ========================================================================

    fun generate(options: DiffusionGenerationOptions): DiffusionResult? {
        synchronized(lock) {
            if (handle == 0L || !DiffusionState.isReady(state)) {
                logger.error("Cannot generate: state=${DiffusionState.getName(state)}")
                return null
            }

            state = DiffusionState.GENERATING
            isCancelled = false
        }

        try {
            val optionsJson = options.toJson()
            val resultJson = RunAnywhereBridge.racDiffusionComponentGenerate(handle, optionsJson)
                ?: run {
                    synchronized(lock) { state = DiffusionState.READY }
                    return null
                }

            // Parse result JSON
            return parseGenerationResult(resultJson)
        } finally {
            synchronized(lock) {
                if (state == DiffusionState.GENERATING) {
                    state = DiffusionState.READY
                }
            }
        }
    }

    fun cancel() {
        synchronized(lock) {
            isCancelled = true
            if (handle != 0L) {
                RunAnywhereBridge.racDiffusionComponentCancel(handle)
            }
        }
    }

    // ========================================================================
    // INFO
    // ========================================================================

    val isLoaded: Boolean
        get() = synchronized(lock) {
            handle != 0L && RunAnywhereBridge.racDiffusionComponentIsLoaded(handle)
        }

    val isReady: Boolean
        get() = DiffusionState.isReady(state)

    fun getCapabilities(): Int {
        synchronized(lock) {
            if (handle == 0L) return 0
            return RunAnywhereBridge.racDiffusionComponentGetCapabilities(handle)
        }
    }

    fun getInfo(): DiffusionInfo? {
        synchronized(lock) {
            if (handle == 0L) return null
            val json = RunAnywhereBridge.racDiffusionComponentGetInfo(handle) ?: return null
            return parseInfo(json)
        }
    }

    // ========================================================================
    // PARSING HELPERS
    // ========================================================================

    private fun parseGenerationResult(json: String): DiffusionResult? {
        try {
            // Simple JSON parsing without external dependency
            val width = extractInt(json, "width") ?: return null
            val height = extractInt(json, "height") ?: return null
            val seedUsed = extractLong(json, "seed_used") ?: -1L
            val generationTimeMs = extractLong(json, "generation_time_ms") ?: 0L
            val safetyFlagged = extractBool(json, "safety_flagged")
            val imageSize = extractInt(json, "image_size") ?: 0
            val imageDataPtr = extractLong(json, "image_data_ptr") ?: 0L

            if (imageDataPtr == 0L || imageSize <= 0) {
                logger.error("No image data in result")
                return null
            }

            // Retrieve actual image bytes from native memory
            val imageData = RunAnywhereBridge.racDiffusionResultGetImageData(imageDataPtr, imageSize)
                ?: run {
                    logger.error("Failed to retrieve image data from native memory")
                    return null
                }

            return DiffusionResult(
                imageData = imageData,
                width = width,
                height = height,
                seedUsed = seedUsed,
                generationTimeMs = generationTimeMs,
                safetyFlagged = safetyFlagged,
            )
        } catch (e: Exception) {
            logger.error("Failed to parse generation result: ${e.message}")
            return null
        }
    }

    private fun parseInfo(json: String): DiffusionInfo? {
        try {
            return DiffusionInfo(
                isReady = extractBool(json, "is_ready"),
                modelVariant = DiffusionModelVariant.fromRawValue(
                    extractInt(json, "model_variant") ?: 0,
                ) ?: DiffusionModelVariant.SD_1_5,
                supportsTextToImage = extractBool(json, "supports_text_to_image"),
                supportsImageToImage = extractBool(json, "supports_image_to_image"),
                supportsInpainting = extractBool(json, "supports_inpainting"),
                safetyCheckerEnabled = extractBool(json, "safety_checker_enabled"),
                maxWidth = extractInt(json, "max_width") ?: 2048,
                maxHeight = extractInt(json, "max_height") ?: 2048,
            )
        } catch (e: Exception) {
            logger.error("Failed to parse info: ${e.message}")
            return null
        }
    }

    // Simple JSON value extractors (avoiding extra dependencies)
    private fun extractInt(json: String, key: String): Int? {
        val pattern = "\"$key\"\\s*:\\s*(-?\\d+)".toRegex()
        return pattern.find(json)?.groupValues?.get(1)?.toIntOrNull()
    }

    private fun extractLong(json: String, key: String): Long? {
        val pattern = "\"$key\"\\s*:\\s*(-?\\d+)".toRegex()
        return pattern.find(json)?.groupValues?.get(1)?.toLongOrNull()
    }

    private fun extractBool(json: String, key: String): Boolean {
        val pattern = "\"$key\"\\s*:\\s*(true|false)".toRegex()
        return pattern.find(json)?.groupValues?.get(1) == "true"
    }
}
