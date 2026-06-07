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

#include "rac/core/rac_error.h"

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
rac_result_t publish(runanywhere::v1::SDKEvent& event,
                     runanywhere::v1::SDKComponent component,
                     runanywhere::v1::EventCategory category);

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
                     runanywhere::v1::EventCategory category,
                     runanywhere::v1::ModelEvent payload);
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
                     runanywhere::v1::EventCategory category,
                     runanywhere::v1::DeviceEvent payload);
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
                     runanywhere::v1::EventCategory category,
                     runanywhere::v1::AuthEvent payload);
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

#endif  // RAC_HAVE_PROTOBUF

}  // namespace rac::events

#endif  // RAC_INFRASTRUCTURE_EVENTS_SDK_EVENT_PUBLISH_H
