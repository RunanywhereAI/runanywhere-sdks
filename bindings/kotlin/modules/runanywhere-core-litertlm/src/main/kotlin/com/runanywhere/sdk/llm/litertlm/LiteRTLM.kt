package com.runanywhere.sdk.llm.litertlm

import ai.runanywhere.proto.v1.ErrorCode
import com.runanywhere.sdk.infrastructure.logging.SDKLogger
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

// RunAnywhereBridge doesn't expose this one; derived the same way as its
// RAC_ERROR_* constants (signed C ABI value = negated proto-enum magnitude).
private val RAC_ERROR_BACKEND_UNAVAILABLE = -ErrorCode.ERROR_CODE_BACKEND_UNAVAILABLE.value

/**
 * LiteRT-LM module: LLM text generation with `.litertlm` bundles on CPU or GPU.
 *
 * A thin wrapper over the C++ backend registration. Models are registered,
 * downloaded, loaded and streamed through the main SDK APIs:
 *
 * ```kotlin
 * LiteRTLM.register()
 * RunAnywhere.models.register(
 *     ModelRegistration.url(
 *         name = "SmolLM2 135M",
 *         url = "https://huggingface.co/litert-community/SmolLM2-135M-Instruct/resolve/main/SmolLM2_135M_Instruct.litertlm",
 *         framework = InferenceFramework.INFERENCE_FRAMEWORK_LITERT_LM,
 *     ),
 * )
 * ```
 */
object LiteRTLM {
    private val logger = SDKLogger("LiteRTLM")

    /** Human-readable module name. */
    const val moduleName: String = "LiteRT-LM"

    /** Current version of the module, as reported by the native bridge. */
    val version: String
        get() {
            RunAnywhereBridge.ensureNativeLibraryLoaded()
            return if (LiteRTLMBridge.ensureNativeLibraryLoaded()) {
                LiteRTLMBridge.nativeGetVersion()
            } else {
                "unknown"
            }
        }

    /** Whether the backend has registered successfully. */
    @Volatile
    var isRegistered = false
        private set

    private val registrationMutex = Mutex()

    /** Registers the backend once, during SDK bootstrap. A failure is logged, not thrown. */
    suspend fun register() {
        registrationMutex.withLock {
            if (isRegistered) return
            when (val result = registerNative()) {
                RunAnywhereBridge.RAC_SUCCESS,
                RunAnywhereBridge.RAC_ERROR_MODULE_ALREADY_REGISTERED,
                -> {
                    isRegistered = true
                    logger.info("LiteRT-LM backend registered")
                }
                RAC_ERROR_BACKEND_UNAVAILABLE -> {
                    logger.warn("LiteRT-LM not registered: this build has no LiteRT-LM library")
                }
                else -> {
                    logger.error("LiteRT-LM registration failed with code: $result")
                }
            }
        }
    }

    /** Unregisters the backend from the C++ registry. */
    suspend fun unregister() {
        registrationMutex.withLock {
            if (!isRegistered) return
            if (LiteRTLMBridge.ensureNativeLibraryLoaded()) {
                LiteRTLMBridge.nativeUnregister()
            }
            isRegistered = false
        }
    }

    private fun registerNative(): Int {
        RunAnywhereBridge.ensureNativeLibraryLoaded()
        return if (LiteRTLMBridge.ensureNativeLibraryLoaded()) {
            LiteRTLMBridge.nativeRegister()
        } else {
            RAC_ERROR_BACKEND_UNAVAILABLE
        }
    }
}
