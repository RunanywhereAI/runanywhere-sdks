package com.runanywhere.sdk.native.bridge

/**
 * Result codes from the native RunAnywhere Core C API.
 * Maps to ra_result_code enum in runanywhere_bridge.h
 */
enum class NativeResultCode(val value: Int) {
    SUCCESS(0),
    ERROR_INIT_FAILED(1),
    ERROR_MODEL_LOAD_FAILED(2),
    ERROR_INFERENCE_FAILED(3),
    ERROR_INVALID_PARAMS(4),
    ERROR_INVALID_HANDLE(5),
    ERROR_NOT_SUPPORTED(6),
    ERROR_CANCELLED(7),
    ERROR_TIMEOUT(8),
    ERROR_MODEL_NOT_LOADED(9),
    ERROR_OUT_OF_MEMORY(10),
    ERROR_UNKNOWN(-1);

    val isSuccess: Boolean get() = this == SUCCESS

    companion object {
        fun fromValue(value: Int): NativeResultCode {
            return entries.find { it.value == value } ?: ERROR_UNKNOWN
        }
    }
}

/**
 * Capability types from the native RunAnywhere Core C API.
 * Maps to ra_capability_type enum in types.h
 */
enum class NativeCapability(val value: Int) {
    TEXT_GENERATION(0),
    EMBEDDINGS(1),
    SPEECH_TO_TEXT(2),
    TEXT_TO_SPEECH(3),
    VOICE_ACTIVITY_DETECTION(4),
    SPEAKER_DIARIZATION(5),
    UNKNOWN(-1);

    companion object {
        fun fromValue(value: Int): NativeCapability? {
            return entries.find { it.value == value }
        }
    }
}

/**
 * Device types from the native RunAnywhere Core C API.
 * Maps to ra_device_type enum in types.h
 */
enum class NativeDeviceType(val value: Int) {
    CPU(0),
    GPU(1),
    NPU(2),
    UNKNOWN(-1);

    companion object {
        fun fromValue(value: Int): NativeDeviceType {
            return entries.find { it.value == value } ?: UNKNOWN
        }
    }
}

/**
 * Exception thrown when native bridge operations fail.
 */
class NativeBridgeException(
    val resultCode: NativeResultCode,
    message: String
) : Exception("Native error (${resultCode.name}): $message")
