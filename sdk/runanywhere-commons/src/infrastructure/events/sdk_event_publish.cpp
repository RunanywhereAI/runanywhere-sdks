/**
 * @file sdk_event_publish.cpp
 * @brief Implementation of the single canonical SDKEvent publish helper.
 *
 * See sdk_event_publish.h. This is the one place that stamps the SDKEvent
 * envelope and routes serialized bytes through rac_sdk_event_publish_proto.
 */

#include "infrastructure/events/sdk_event_publish.h"

#if defined(RAC_HAVE_PROTOBUF)

#include <atomic>
#include <chrono>
#include <cstdio>
#include <cstdint>
#include <string>
#include <utility>
#include <vector>

#include "rac/infrastructure/events/rac_sdk_event_stream.h"

namespace rac::events {

namespace {

uint64_t current_time_ms() {
    using namespace std::chrono;
    return static_cast<uint64_t>(
        duration_cast<milliseconds>(system_clock::now().time_since_epoch()).count());
}

// Monotonic-counter UUID-like id, matching event_publisher.cpp's scheme so the
// canonical stream presents one consistent id format regardless of which
// emitter produced the event.
std::string generate_event_id() {
    static std::atomic<uint64_t> counter{0};
    const uint64_t now = current_time_ms();
    const uint64_t count = counter.fetch_add(1, std::memory_order_relaxed);
    char buffer[64];
    std::snprintf(buffer, sizeof(buffer), "%llu-%llu", static_cast<unsigned long long>(now),
                  static_cast<unsigned long long>(count));
    return buffer;
}

}  // namespace

rac_result_t publish(runanywhere::v1::SDKEvent& event, runanywhere::v1::SDKComponent component,
                     runanywhere::v1::EventCategory category) {
    // Stamp envelope metadata that every canonical SDKEvent carries. Only fill
    // fields the caller did not already set, so a richer payload (explicit
    // session id, operation id, severity, properties, etc.) is preserved.
    if (event.timestamp_ms() == 0) {
        event.set_timestamp_ms(static_cast<int64_t>(current_time_ms()));
    }
    if (event.id().empty()) {
        event.set_id(generate_event_id());
    }
    event.set_category(category);
    event.set_component(component);
    if (event.destination() == runanywhere::v1::EVENT_DESTINATION_UNSPECIFIED) {
        event.set_destination(runanywhere::v1::EVENT_DESTINATION_ALL);
    }
    if (event.source().empty()) {
        event.set_source("cpp");
    }

    const size_t size = event.ByteSizeLong();
    std::vector<uint8_t> bytes(size);
    if (size > 0 && !event.SerializeToArray(bytes.data(), static_cast<int>(bytes.size()))) {
        return RAC_ERROR_EVENT_PUBLISH_FAILED;
    }
    return rac_sdk_event_publish_proto(bytes.data(), bytes.size());
}

// Each typed overload moves its payload into the matching SDKEvent oneof arm,
// then delegates to the envelope-stamping core overload above.
#define RAC_DEFINE_PUBLISH_OVERLOAD(PayloadType, oneof_field)                                  \
    rac_result_t publish(runanywhere::v1::SDKComponent component,                              \
                         runanywhere::v1::EventCategory category,                              \
                         runanywhere::v1::PayloadType payload) {                               \
        runanywhere::v1::SDKEvent event;                                                       \
        *event.mutable_##oneof_field() = std::move(payload);                                   \
        return publish(event, component, category);                                            \
    }

RAC_DEFINE_PUBLISH_OVERLOAD(InitializationEvent, initialization)
RAC_DEFINE_PUBLISH_OVERLOAD(ConfigurationEvent, configuration)
RAC_DEFINE_PUBLISH_OVERLOAD(GenerationEvent, generation)
RAC_DEFINE_PUBLISH_OVERLOAD(ModelEvent, model)
RAC_DEFINE_PUBLISH_OVERLOAD(PerformanceEvent, performance)
RAC_DEFINE_PUBLISH_OVERLOAD(NetworkEvent, network)
RAC_DEFINE_PUBLISH_OVERLOAD(StorageEvent, storage)
RAC_DEFINE_PUBLISH_OVERLOAD(FrameworkEvent, framework)
RAC_DEFINE_PUBLISH_OVERLOAD(DeviceEvent, device)
RAC_DEFINE_PUBLISH_OVERLOAD(ComponentInitializationEvent, component_init)
RAC_DEFINE_PUBLISH_OVERLOAD(VoiceLifecycleEvent, voice)
RAC_DEFINE_PUBLISH_OVERLOAD(VoiceEvent, voice_pipeline)
RAC_DEFINE_PUBLISH_OVERLOAD(ComponentLifecycleEvent, component_lifecycle)
RAC_DEFINE_PUBLISH_OVERLOAD(SessionEvent, session)
RAC_DEFINE_PUBLISH_OVERLOAD(AuthEvent, auth)
RAC_DEFINE_PUBLISH_OVERLOAD(ModelRegistryEvent, model_registry)
RAC_DEFINE_PUBLISH_OVERLOAD(DownloadEvent, download)
RAC_DEFINE_PUBLISH_OVERLOAD(StorageLifecycleEvent, storage_lifecycle)
RAC_DEFINE_PUBLISH_OVERLOAD(HardwareRoutingEvent, hardware_routing)
RAC_DEFINE_PUBLISH_OVERLOAD(CapabilityOperationEvent, capability)
RAC_DEFINE_PUBLISH_OVERLOAD(TelemetryEvent, telemetry)
RAC_DEFINE_PUBLISH_OVERLOAD(CancellationEvent, cancellation)
RAC_DEFINE_PUBLISH_OVERLOAD(FailureEvent, failure)

#undef RAC_DEFINE_PUBLISH_OVERLOAD

}  // namespace rac::events

#endif  // RAC_HAVE_PROTOBUF
