// GENERATED FILE — DO NOT EDIT.
// Source: idl/http/sdk-openapi.json (the published device-facing API contract)
// Regenerate: python3 idl/codegen/generate_telemetry_vocabulary.py
//
// The accepted values for the telemetry dimensions that used to be free text.
// The backend rejects anything outside these sets, so emitting an unlisted
// value silently drops the event into quarantine — check against these tables
// instead of trusting a string literal.

#ifndef RAC_TELEMETRY_VOCABULARY_H
#define RAC_TELEMETRY_VOCABULARY_H

#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

// Engine that actually executed the work. Published as TelemetryFramework.
#define RAC_TELEMETRY_FRAMEWORK_COUNT 22
static const char* const RAC_TELEMETRY_FRAMEWORK_VALUES[] = {
    "onnx",
    "sherpa",
    "llamacpp",
    "foundation_models",
    "system_tts",
    "fluid_audio",
    "coreml",
    "whisperkit_coreml",
    "mlx",
    "qhexrt",
    "neurt",
    "tflite",
    "executorch",
    "mediapipe",
    "mlc",
    "pico_llm",
    "piper_tts",
    "swift_transformers",
    "cloud",
    "builtin",
    "none",
    "unknown",
};

// OS family — never the binding. Published as TelemetryPlatform.
#define RAC_TELEMETRY_PLATFORM_COUNT 9
static const char* const RAC_TELEMETRY_PLATFORM_VALUES[] = {
    "ios",
    "android",
    "macos",
    "windows",
    "linux",
    "web",
    "tvos",
    "watchos",
    "visionos",
};

// Language binding that produced the event. Published as TelemetrySdkBinding.
#define RAC_TELEMETRY_SDK_BINDING_COUNT 9
static const char* const RAC_TELEMETRY_SDK_BINDING_VALUES[] = {
    "swift",
    "kotlin",
    "flutter",
    "react-native",
    "web",
    "electron",
    "python",
    "cli",
    "cpp",
};

// Battery state at event time. Published as TelemetryBatteryState.
#define RAC_TELEMETRY_BATTERY_STATE_COUNT 4
static const char* const RAC_TELEMETRY_BATTERY_STATE_VALUES[] = {
    "charging",
    "full",
    "unplugged",
    "unknown",
};

// Returns 1 when `value` is in `table`, 0 otherwise (NULL is not a member;
// an absent field is represented by omitting it, not by an empty string).
static inline int rac_telemetry_vocabulary_contains(const char* const* table, size_t count,
                                                   const char* value) {
    if (!value) {
        return 0;
    }
    for (size_t i = 0; i < count; ++i) {
        const char* a = table[i];
        const char* b = value;
        while (*a && *a == *b) {
            ++a;
            ++b;
        }
        if (*a == '\0' && *b == '\0') {
            return 1;
        }
    }
    return 0;
}

#ifdef __cplusplus
}  // extern "C"
#endif

#endif  // RAC_TELEMETRY_VOCABULARY_H
