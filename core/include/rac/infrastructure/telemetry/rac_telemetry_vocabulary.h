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

// Every event type the SDK may emit. Published as TelemetryEventType.
#define RAC_TELEMETRY_EVENT_TYPE_COUNT 106
static const char* const RAC_TELEMETRY_EVENT_TYPE_VALUES[] = {
    "auth.device_registered",
    "auth.device_registration_failed",
    "auth.failed",
    "auth.requested",
    "auth.succeeded",
    "auth.token_expired",
    "auth.token_refreshed",
    "cancellation.acknowledged",
    "cancellation.completed",
    "cancellation.failed",
    "cancellation.requested",
    "capability",
    "component",
    "component.model.loaded",
    "component.model.unloaded",
    "component.state.changed",
    "device",
    "device.registered",
    "device.registration.failed",
    "embeddings.embed.completed",
    "embeddings.embed.failed",
    "embeddings.embed.started",
    "failure",
    "imagegen.generate.completed",
    "imagegen.generate.failed",
    "imagegen.generate.progress",
    "imagegen.generate.started",
    "llm.generation",
    "llm.generation.cancelled",
    "llm.generation.completed",
    "llm.generation.failed",
    "llm.generation.first_token",
    "llm.generation.started",
    "llm.generation.streaming",
    "llm.model.load.completed",
    "llm.model.load.failed",
    "llm.model.load.started",
    "lora.attach.completed",
    "lora.detach.completed",
    "lora.failed",
    "model",
    "model.deleted",
    "model.download.cancelled",
    "model.download.completed",
    "model.download.failed",
    "model.download.progress",
    "model.download.started",
    "model.extraction.completed",
    "model.extraction.failed",
    "model.extraction.progress",
    "model.extraction.started",
    "network",
    "network.connectivity.changed",
    "network.request.completed",
    "network.request.failed",
    "network.request.started",
    "network.request.timeout",
    "rag.ingestion.completed",
    "rag.ingestion.started",
    "rag.query.completed",
    "rag.query.failed",
    "rag.query.started",
    "sdk.error",
    "sdk.init",
    "sdk.init.completed",
    "sdk.init.failed",
    "sdk.init.started",
    "sdk.models.loaded",
    "storage",
    "storage.cache.clear_failed",
    "storage.cache.cleared",
    "storage.temp.cleaned",
    "stt.model.load.completed",
    "stt.model.load.failed",
    "stt.model.load.started",
    "stt.transcription.completed",
    "stt.transcription.failed",
    "stt.transcription.partial",
    "stt.transcription.started",
    "tts.synthesis.chunk",
    "tts.synthesis.completed",
    "tts.synthesis.failed",
    "tts.synthesis.started",
    "tts.voice.load.completed",
    "tts.voice.load.failed",
    "tts.voice.load.started",
    "vad.paused",
    "vad.process",
    "vad.resumed",
    "vad.speech.ended",
    "vad.speech.started",
    "vad.started",
    "vad.stopped",
    "vlm.generation",
    "vlm.generation.cancelled",
    "vlm.generation.completed",
    "vlm.generation.failed",
    "vlm.generation.first_token",
    "vlm.generation.started",
    "vlm.generation.streaming",
    "vlm.process.completed",
    "vlm.process.failed",
    "vlm.process.started",
    "voice",
    "voice.pipeline",
    "voice.turn.metrics",
};

// Backend (engine) that actually executed the work. Published as TelemetryBackend.
#define RAC_TELEMETRY_BACKEND_COUNT 22
static const char* const RAC_TELEMETRY_BACKEND_VALUES[] = {
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

// Where the model came from. Published as TelemetryModelSource.
#define RAC_TELEMETRY_MODEL_SOURCE_COUNT 3
static const char* const RAC_TELEMETRY_MODEL_SOURCE_VALUES[] = {
    "catalog",
    "builtin",
    "user",
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
