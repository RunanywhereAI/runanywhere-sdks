package com.runanywhere.sdk.native.bridge

/**
 * Capability types supported by RunAnywhere Core native backends.
 * Maps directly to ra_capability_type in runanywhere_bridge.h
 *
 * This is a generic definition used by all native backends (ONNX, TFLite, CoreML, etc.)
 */
enum class NativeCapability(
    val value: Int,
) {
    TEXT_GENERATION(0),
    EMBEDDINGS(1),
    STT(2),
    TTS(3),
    VAD(4),
    DIARIZATION(5),
    ;

    companion object {
        fun fromValue(value: Int): NativeCapability? = entries.find { it.value == value }
    }
}

/**
 * Device types used by native backends.
 * Maps directly to ra_device_type in types.h
 */
enum class NativeDeviceType(
    val value: Int,
) {
    CPU(0),
    GPU(1),
    NEURAL_ENGINE(2),
    METAL(3),
    CUDA(4),
    VULKAN(5),
    COREML(6),
    TFLITE(7),
    ONNX(8),
    ;

    companion object {
        fun fromValue(value: Int): NativeDeviceType = entries.find { it.value == value } ?: CPU
    }
}

/**
 * Result codes from C API operations.
 * Maps directly to ra_result_code in types.h
 */
enum class NativeResultCode(
    val value: Int,
) {
    SUCCESS(0),
    ERROR_INIT_FAILED(-1),
    ERROR_MODEL_LOAD_FAILED(-2),
    ERROR_INFERENCE_FAILED(-3),
    ERROR_INVALID_HANDLE(-4),
    ERROR_INVALID_PARAMS(-5),
    ERROR_OUT_OF_MEMORY(-6),
    ERROR_NOT_IMPLEMENTED(-7),
    ERROR_CANCELLED(-8),
    ERROR_TIMEOUT(-9),
    ERROR_IO(-10),
    ERROR_UNKNOWN(-99),
    ;

    val isSuccess: Boolean get() = this == SUCCESS

    companion object {
        fun fromValue(value: Int): NativeResultCode = entries.find { it.value == value } ?: ERROR_UNKNOWN
    }
}
