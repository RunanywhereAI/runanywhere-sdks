/**
 * @file sdk_event_publish.h
 * @brief Single internal helper for publishing canonical SDKEvent proto events.
 *
 * One place that stamps the `SDKEvent` envelope (id, timestamp_ms, source,
 * destination, category, component) and routes the serialized bytes through
 * `rac_sdk_event_publish_proto`. C++ components build a strongly-typed per-
 * component payload (e.g. `GenerationEvent`, `ModelEvent`, …) and hand it to
 * `rac::events::publish(component, category, payload)`; the matching overload
 * drops the payload into the correct `SDKEvent` oneof arm and emits it.
 *
 * This replaces the per-call boilerplate (construct SDKEvent → populate
 * envelope → set oneof arm → serialize → publish) that was duplicated across
 * the proto-event emitters in event_publisher.cpp. New proto-event emissions
 * SHOULD go through this helper rather than re-deriving the envelope.
 *
 * Internal commons header — not part of any public SDK surface. The typed
 * signatures require protobuf and are compiled out when RAC_HAVE_PROTOBUF is
 * not defined.
 */

#ifndef RAC_INFRASTRUCTURE_EVENTS_SDK_EVENT_PUBLISH_H
#define RAC_INFRASTRUCTURE_EVENTS_SDK_EVENT_PUBLISH_H

#include <cstddef>
#include <cstdint>

#include "rac/core/rac_error.h"
#include "rac/infrastructure/model_management/rac_model_types.h"

#if defined(RAC_HAVE_PROTOBUF)
#include "component_types.pb.h"
#include "sdk_events.pb.h"
#include "voice_events.pb.h"
#endif

namespace rac::events {

#if defined(RAC_HAVE_PROTOBUF)

// ---------------------------------------------------------------------------
// Core envelope-stamping publish. `event` already carries its oneof payload;
// this fills the standard envelope metadata (id, timestamp_ms, source="cpp",
// destination=ALL unless already set) plus the supplied component/category,
// serializes the envelope, and routes it through rac_sdk_event_publish_proto.
//
// Fields the caller already populated on `event` (severity, session_id,
// operation_id, correlation_id, an explicit destination, an explicit error,
// extra properties) are preserved.
// ---------------------------------------------------------------------------
rac_result_t publish(runanywhere::v1::SDKEvent& event, runanywhere::v1::SDKComponent component,
                     runanywhere::v1::EventCategory category);

// ---------------------------------------------------------------------------
// Publish an already-fully-populated SDKEvent. Unlike publish() above this does
// NOT stamp envelope metadata — the caller owns id/timestamp/component/category/
// destination. It serializes the event once, feeds the PUBLIC sink when the
// PUBLIC destination bit is set, then routes to the TELEMETRY + LOG sinks per
// the destination bitmask (same dual-sink path as publish()).
//
// This is the funnel feature modules use for proto events they build by hand
// (LLM generation, VLM/RAG capability ops). Going through here is what gets the
// event to the telemetry sink — calling rac_sdk_event_publish_proto directly
// feeds the PUBLIC sink only and silently drops telemetry.
// ---------------------------------------------------------------------------
rac_result_t publish_prebuilt(const runanywhere::v1::SDKEvent& event);

// ---------------------------------------------------------------------------
// Typed overloads — one per SDKEvent oneof arm. Each moves the strongly-typed
// per-component payload into the matching oneof arm, then stamps + publishes
// via the core overload above. This is the canonical "publish(component,
// category, <the oneof payload>)" entry point requested by the event-system
// consolidation: callers never touch the SDKEvent envelope directly.
// ---------------------------------------------------------------------------
rac_result_t publish(runanywhere::v1::SDKComponent component,
                     runanywhere::v1::EventCategory category,
                     runanywhere::v1::InitializationEvent payload);
rac_result_t publish(runanywhere::v1::SDKComponent component,
                     runanywhere::v1::EventCategory category,
                     runanywhere::v1::ConfigurationEvent payload);
rac_result_t publish(runanywhere::v1::SDKComponent component,
                     runanywhere::v1::EventCategory category,
                     runanywhere::v1::GenerationEvent payload);
rac_result_t publish(runanywhere::v1::SDKComponent component,
                     runanywhere::v1::EventCategory category, runanywhere::v1::ModelEvent payload);
rac_result_t publish(runanywhere::v1::SDKComponent component,
                     runanywhere::v1::EventCategory category,
                     runanywhere::v1::PerformanceEvent payload);
rac_result_t publish(runanywhere::v1::SDKComponent component,
                     runanywhere::v1::EventCategory category,
                     runanywhere::v1::NetworkEvent payload);
rac_result_t publish(runanywhere::v1::SDKComponent component,
                     runanywhere::v1::EventCategory category,
                     runanywhere::v1::StorageEvent payload);
rac_result_t publish(runanywhere::v1::SDKComponent component,
                     runanywhere::v1::EventCategory category,
                     runanywhere::v1::FrameworkEvent payload);
rac_result_t publish(runanywhere::v1::SDKComponent component,
                     runanywhere::v1::EventCategory category, runanywhere::v1::DeviceEvent payload);
rac_result_t publish(runanywhere::v1::SDKComponent component,
                     runanywhere::v1::EventCategory category,
                     runanywhere::v1::ComponentInitializationEvent payload);
rac_result_t publish(runanywhere::v1::SDKComponent component,
                     runanywhere::v1::EventCategory category,
                     runanywhere::v1::VoiceLifecycleEvent payload);
rac_result_t publish(runanywhere::v1::SDKComponent component,
                     runanywhere::v1::EventCategory category,
                     runanywhere::v1::VoiceEvent payload);  // voice_pipeline arm
rac_result_t publish(runanywhere::v1::SDKComponent component,
                     runanywhere::v1::EventCategory category,
                     runanywhere::v1::ComponentLifecycleEvent payload);
rac_result_t publish(runanywhere::v1::SDKComponent component,
                     runanywhere::v1::EventCategory category,
                     runanywhere::v1::SessionEvent payload);
rac_result_t publish(runanywhere::v1::SDKComponent component,
                     runanywhere::v1::EventCategory category, runanywhere::v1::AuthEvent payload);
rac_result_t publish(runanywhere::v1::SDKComponent component,
                     runanywhere::v1::EventCategory category,
                     runanywhere::v1::ModelRegistryEvent payload);
rac_result_t publish(runanywhere::v1::SDKComponent component,
                     runanywhere::v1::EventCategory category,
                     runanywhere::v1::DownloadEvent payload);
rac_result_t publish(runanywhere::v1::SDKComponent component,
                     runanywhere::v1::EventCategory category,
                     runanywhere::v1::StorageLifecycleEvent payload);
rac_result_t publish(runanywhere::v1::SDKComponent component,
                     runanywhere::v1::EventCategory category,
                     runanywhere::v1::HardwareRoutingEvent payload);
rac_result_t publish(runanywhere::v1::SDKComponent component,
                     runanywhere::v1::EventCategory category,
                     runanywhere::v1::CapabilityOperationEvent payload);
rac_result_t publish(runanywhere::v1::SDKComponent component,
                     runanywhere::v1::EventCategory category,
                     runanywhere::v1::TelemetryEvent payload);
rac_result_t publish(runanywhere::v1::SDKComponent component,
                     runanywhere::v1::EventCategory category,
                     runanywhere::v1::CancellationEvent payload);
rac_result_t publish(runanywhere::v1::SDKComponent component,
                     runanywhere::v1::EventCategory category,
                     runanywhere::v1::FailureEvent payload);

// ---------------------------------------------------------------------------
// Destination bitmask helpers. The proto EventDestination values are powers of
// two (PUBLIC=1, TELEMETRY=2, LOG=4) with ALL=PUBLIC|TELEMETRY=3. These mirror
// the legacy rac_event_get_destination semantics in bitmask form so call sites
// don't hardcode bits. (ALL is the publish() default; no helper needed.)
// ---------------------------------------------------------------------------
inline runanywhere::v1::EventDestination legacy_destination_public() {
    return runanywhere::v1::EVENT_DESTINATION_PUBLIC;
}
inline runanywhere::v1::EventDestination legacy_destination_telemetry() {
    return runanywhere::v1::EVENT_DESTINATION_TELEMETRY;
}

// ---------------------------------------------------------------------------
// Convert a rac_inference_framework_t (C enum) to the proto InferenceFramework
// value as an int32, for the `framework` fields on GenerationEvent / ModelEvent
// / VoiceLifecycleEvent. The two enums have different integer values, so this
// maps explicitly (mirrors inference_framework_to_proto in the model layer).
// ---------------------------------------------------------------------------
inline int32_t framework_to_proto_int(rac_inference_framework_t f) {
    switch (f) {
        case RAC_FRAMEWORK_ONNX:
            return runanywhere::v1::INFERENCE_FRAMEWORK_ONNX;
        case RAC_FRAMEWORK_LLAMACPP:
            return runanywhere::v1::INFERENCE_FRAMEWORK_LLAMA_CPP;
        case RAC_FRAMEWORK_FOUNDATION_MODELS:
            return runanywhere::v1::INFERENCE_FRAMEWORK_FOUNDATION_MODELS;
        case RAC_FRAMEWORK_SYSTEM_TTS:
            return runanywhere::v1::INFERENCE_FRAMEWORK_SYSTEM_TTS;
        case RAC_FRAMEWORK_FLUID_AUDIO:
            return runanywhere::v1::INFERENCE_FRAMEWORK_FLUID_AUDIO;
        case RAC_FRAMEWORK_BUILTIN:
            return runanywhere::v1::INFERENCE_FRAMEWORK_BUILT_IN;
        case RAC_FRAMEWORK_NONE:
            return runanywhere::v1::INFERENCE_FRAMEWORK_NONE;
        case RAC_FRAMEWORK_MLX:
            return runanywhere::v1::INFERENCE_FRAMEWORK_MLX;
        case RAC_FRAMEWORK_COREML:
            return runanywhere::v1::INFERENCE_FRAMEWORK_COREML;
        case RAC_FRAMEWORK_SHERPA:
            return runanywhere::v1::INFERENCE_FRAMEWORK_SHERPA;
        case RAC_FRAMEWORK_QHEXRT:
            return runanywhere::v1::INFERENCE_FRAMEWORK_QHEXRT;
        default:
            return runanywhere::v1::INFERENCE_FRAMEWORK_UNKNOWN;
    }
}

// ---------------------------------------------------------------------------
// Convenience publishers for the per-operation voice/generation/model events
// that carry a session/operation id on the SDKEvent envelope (telemetry groups
// by envelope session_id). These set the oneof arm, the envelope session_id,
// and an explicit destination, then delegate to the core publish(). Pass
// session_id=nullptr to leave it unset and EVENT_DESTINATION_UNSPECIFIED to use
// the publish() default (ALL).
// ---------------------------------------------------------------------------
rac_result_t publish_with_session(
    runanywhere::v1::SDKComponent component, runanywhere::v1::EventCategory category,
    runanywhere::v1::GenerationEvent payload, const char* session_id,
    runanywhere::v1::EventDestination destination = runanywhere::v1::EVENT_DESTINATION_UNSPECIFIED);
rac_result_t publish_with_session(
    runanywhere::v1::SDKComponent component, runanywhere::v1::EventCategory category,
    runanywhere::v1::VoiceLifecycleEvent payload, const char* session_id,
    runanywhere::v1::EventDestination destination = runanywhere::v1::EVENT_DESTINATION_UNSPECIFIED);

// ---------------------------------------------------------------------------
// Destination router. Called by publish() after the PUBLIC proto stream has
// been fed: routes the event to TELEMETRY (telemetry_manager_track_proto) and
// LOG (structured log) sinks based on the envelope `destination` bitmask. The
// PUBLIC bit is already satisfied by rac_sdk_event_publish_proto inside
// publish(); this only handles the non-public sinks. `serialized_bytes` is the
// already-serialized SDKEvent (so the router does not re-serialize).
// ---------------------------------------------------------------------------
void route(const runanywhere::v1::SDKEvent& event, const uint8_t* serialized_bytes,
           size_t serialized_size);

#endif  // RAC_HAVE_PROTOBUF

}  // namespace rac::events

#endif  // RAC_INFRASTRUCTURE_EVENTS_SDK_EVENT_PUBLISH_H
