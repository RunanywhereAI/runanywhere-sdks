package com.runanywhere.sdk.npu.qhexrt

import ai.runanywhere.proto.v1.ErrorCode
import ai.runanywhere.proto.v1.HexagonArch
import ai.runanywhere.proto.v1.ModelInfo
import ai.runanywhere.proto.v1.NpuCapability
import ai.runanywhere.proto.v1.RegisterModelFromUrlRequest
import com.runanywhere.sdk.infrastructure.logging.SDKLogger
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

// RunAnywhereBridge doesn't expose this one; derived the same way as its
// RAC_ERROR_* constants (signed C ABI value = negated proto-enum magnitude).
private val RAC_ERROR_BACKEND_UNAVAILABLE = -ErrorCode.ERROR_CODE_BACKEND_UNAVAILABLE.value
private val RAC_ERROR_CAPABILITY_UNSUPPORTED = -ErrorCode.ERROR_CODE_CAPABILITY_UNSUPPORTED.value

/**
 * QHexRT module — RunAnywhere's private Qualcomm Hexagon NPU backend.
 *
 * Runs prebuilt QNN context binaries on Snapdragon V75/V79/V81 NPUs, serving
 * LLM, VLM, STT and TTS through the standard SDK APIs once registered. A thin
 * wrapper over C++ backend registration; all inference lives in the C++
 * commons layer.
 *
 * ## Pre-flight
 * ```kotlin
 * val npu = QHexRT.probeNpu()
 * if (!npu.qhexrt_supported) { /* warn; fall back to CPU engines */ }
 * ```
 *
 * ## Registration
 * ```kotlin
 * QHexRT.register()   // once during bootstrap, on a supported device
 * ```
 */
object QHexRT {
    private val logger = SDKLogger("QHexRT")

    /** Current version of the QHexRT module, as reported by the native bridge. */
    val version: String
        get() {
            RunAnywhereBridge.ensureNativeLibraryLoaded()
            return if (QHexRTBridge.ensureNativeLibraryLoaded()) {
                QHexRTBridge.nativeGetVersion()
            } else {
                "unknown"
            }
        }

    /** Human-readable module name. */
    const val moduleName: String = "QHexRT"

    @Volatile
    private var isRegistered = false
    private val registrationMutex = Mutex()
    private val registrationLock = Any()

    /**
     * Probe the device's Hexagon NPU without loading QNN. Safe to call on any
     * device; returns the all-default [NpuCapability] (unknown arch,
     * `qhexrt_supported = false`) on unsupported/unknown parts or probe
     * failure.
     */
    fun probeNpu(): NpuCapability {
        RunAnywhereBridge.ensureNativeLibraryLoaded()
        if (!QHexRTBridge.ensureNativeLibraryLoaded()) {
            logger.info("QHexRT native library unavailable; reporting unsupported NPU")
            return NpuCapability()
        }
        return try {
            NpuCapability.ADAPTER.decode(QHexRTBridge.nativeProbeNpuProto())
        } catch (e: Exception) {
            logger.error("Failed to decode NPU probe proto: ${e.message}", throwable = e)
            NpuCapability()
        }
    }

    /**
     * Return whether [arch] is supported by this QHexRT build.
     *
     * The support boundary is owned by `librac_backend_qhexrt.so`; Kotlin
     * forwards the generated protobuf enum value without duplicating the
     * V75/V79/V81 set.
     */
    fun isArchitectureSupported(arch: HexagonArch): Boolean {
        RunAnywhereBridge.ensureNativeLibraryLoaded()
        if (!QHexRTBridge.ensureNativeLibraryLoaded()) return false
        return QHexRTBridge.nativeArchIsSupported(arch.value)
    }

    /**
     * Match native product catalog policy for [modelId] against [arch].
     */
    fun modelSupportsArchitecture(
        modelId: String,
        arch: HexagonArch,
    ): Boolean {
        RunAnywhereBridge.ensureNativeLibraryLoaded()
        if (!QHexRTBridge.ensureNativeLibraryLoaded()) return false
        return QHexRTBridge.nativeCatalogModelSupportsArch(modelId, arch.value)
    }

    /** Whether native product policy marks [modelId] as HF-authenticated. */
    fun modelRequiresHfAuth(modelId: String): Boolean {
        RunAnywhereBridge.ensureNativeLibraryLoaded()
        if (!QHexRTBridge.ensureNativeLibraryLoaded()) return false
        return QHexRTBridge.nativeCatalogModelRequiresHfAuth(modelId)
    }

    /**
     * Register [request] only when native product policy allows it here.
     *
     * The app remains the source of the model URL and presentation metadata.
     * QHexRT owns device probing and architecture selection, then composes the
     * shared C++ URL-registration/download pipeline. Returns `null` for the
     * normal "model is not eligible on this device" outcome.
     */
    suspend fun registerModelForDevice(request: RegisterModelFromUrlRequest): ModelInfo? {
        RunAnywhereBridge.ensureNativeLibraryLoaded()
        if (!QHexRTBridge.ensureNativeLibraryLoaded()) return null
        val bytes =
            QHexRTBridge.nativeCatalogRegisterModelProto(QHexRTCatalogWire.encodeRequest(request))
                ?: return null
        return QHexRTCatalogWire.decodeModel(bytes)
    }

    /**
     * Register the QHexRT backend with the C++ plugin registry. Suspend so
     * callers can await module bootstrap from a coroutine scope. Safe to call on
     * unsupported devices — registration is rejected and the app falls back to
     * CPU engines.
     */
    suspend fun register() {
        registrationMutex.withLock { registerInternal() }
    }

    /** Unregister the QHexRT backend from the C++ registry. */
    suspend fun unregister() {
        registrationMutex.withLock {
            if (!isRegistered) return
            unregisterNative()
            isRegistered = false
            logger.info("QHexRT backend unregistered")
        }
    }

    private fun registerInternal() {
        if (isRegistered) {
            logger.debug("QHexRT already registered, returning")
            return
        }
        logger.info("Registering QHexRT backend with C++ registry...")
        when (val result = registerNative()) {
            RunAnywhereBridge.RAC_SUCCESS,
            RunAnywhereBridge.RAC_ERROR_MODULE_ALREADY_REGISTERED,
            -> {
                isRegistered = true
                logger.info("QHexRT backend registered successfully (LLM/VLM/STT/TTS)")
            }
            RAC_ERROR_BACKEND_UNAVAILABLE,
            RAC_ERROR_CAPABILITY_UNSUPPORTED,
            -> {
                logger.info("QHexRT not registered: no supported Hexagon NPU on this device")
            }
            else -> {
                logger.error("QHexRT registration failed with code: $result")
            }
        }
    }

    /**
     * Enable auto-registration. Access this property to trigger C++ backend
     * registration once.
     */
    val autoRegister: Unit by lazy {
        synchronized(registrationLock) { registerInternal() }
    }
}

/** Byte/enum transport only; all QHexRT catalog policy stays native. */
internal object QHexRTCatalogWire {
    fun encodeRequest(request: RegisterModelFromUrlRequest): ByteArray =
        RegisterModelFromUrlRequest.ADAPTER.encode(request)

    fun decodeModel(bytes: ByteArray): ModelInfo = ModelInfo.ADAPTER.decode(bytes)
}

private val logger = SDKLogger("QHexRT")

internal fun QHexRT.registerNative(): Int {
    RunAnywhereBridge.ensureNativeLibraryLoaded()
    val skelDirectory = QHexRTSkelInstaller.installIfAvailable()
    if (!QHexRTBridge.ensureNativeLibraryLoaded()) {
        logger.info("QHexRT native library unavailable; skipping backend registration")
        return RAC_ERROR_BACKEND_UNAVAILABLE
    }
    QHexRTBridge.nativeSetSkelDirectory(skelDirectory)
    return QHexRTBridge.nativeRegister()
}

internal fun QHexRT.unregisterNative(): Int =
    if (QHexRTBridge.ensureNativeLibraryLoaded()) {
        QHexRTBridge.nativeUnregister()
    } else {
        RAC_ERROR_BACKEND_UNAVAILABLE
    }
