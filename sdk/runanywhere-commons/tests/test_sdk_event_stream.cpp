/**
 * @file test_sdk_event_stream.cpp
 * @brief Canonical SDKEvent proto-byte stream tests.
 */

#include <atomic>
#include <chrono>
#include <cstdio>
#include <mutex>
#include <thread>
#include <vector>

#include "rac/core/rac_error.h"
#include "rac/core/rac_sdk_state.h"
#include "rac/foundation/rac_proto_buffer.h"
#include "rac/infrastructure/events/rac_sdk_event_stream.h"
#include "rac/plugin/rac_plugin_entry.h"
#include "rac/router/rac_hardware_abi.h"
#include "rac/router/rac_route.h"

#if defined(RAC_HAVE_PROTOBUF)
#include "sdk_events.pb.h"
#endif

namespace {

int test_count = 0;
int fail_count = 0;

#define CHECK(cond, label)                                                                       \
    do {                                                                                         \
        ++test_count;                                                                            \
        if (cond) {                                                                              \
            std::fprintf(stdout, "  ok:   %s\n", label);                                         \
        } else {                                                                                 \
            ++fail_count;                                                                        \
            std::fprintf(stderr, "  FAIL: %s (%s:%d) - %s\n", label, __FILE__, __LINE__, #cond); \
        }                                                                                        \
    } while (0)

#if defined(RAC_HAVE_PROTOBUF)

struct Capture {
    std::vector<std::vector<uint8_t>> events;
};

void capture_callback(const uint8_t* bytes, size_t size, void* user_data) {
    auto* capture = static_cast<Capture*>(user_data);
    if (size == 0) {
        capture->events.emplace_back();
        return;
    }
    capture->events.emplace_back(bytes, bytes + size);
}

bool poll_event(runanywhere::v1::SDKEvent* out) {
    rac_proto_buffer_t buffer;
    rac_proto_buffer_init(&buffer);
    const rac_result_t rc = rac_sdk_event_poll(&buffer);
    if (rc != RAC_SUCCESS) {
        return false;
    }
    const bool parsed = out->ParseFromArray(buffer.data, static_cast<int>(buffer.size));
    rac_proto_buffer_free(&buffer);
    return parsed;
}

const int k_sentinel = 0xCAFE;

rac_engine_vtable_t make_llm_vtable(const char* name, int32_t priority) {
    rac_engine_vtable_t v{};
    v.metadata.abi_version = RAC_PLUGIN_API_VERSION;
    v.metadata.name = name;
    v.metadata.display_name = name;
    v.metadata.engine_version = "0.0.0";
    v.metadata.priority = priority;
    v.llm_ops = reinterpret_cast<const struct rac_llm_service_ops*>(&k_sentinel);
    return v;
}

#endif

}  // namespace

int main() {
    std::fprintf(stdout, "test_sdk_event_stream\n");

#if !defined(RAC_HAVE_PROTOBUF)
    std::fprintf(stdout, "  skip: SDKEvent stream proto decode tests (no protobuf)\n");
    return 0;
#else
    CHECK(rac_sdk_event_subscribe(nullptr, nullptr) == 0,
          "null SDKEvent callback returns subscription id 0");

    Capture capture;
    const uint64_t sub = rac_sdk_event_subscribe(capture_callback, &capture);
    CHECK(sub != 0, "SDKEvent subscription returns non-zero id");

    rac_sdk_event_clear_queue();
    rac_result_t rc = rac_sdk_event_publish_failure(RAC_ERROR_INVALID_ARGUMENT, "bad argument",
                                                    "llm", "unitTestOperation", RAC_TRUE);
    CHECK(rc == RAC_SUCCESS, "failure helper publishes SDKEvent bytes");
    CHECK(capture.events.size() == 1, "subscriber receives published SDKEvent bytes");

    runanywhere::v1::SDKEvent callback_event;
    CHECK(callback_event.ParseFromArray(capture.events[0].data(),
                                        static_cast<int>(capture.events[0].size())),
          "callback bytes decode as SDKEvent");
    CHECK(!callback_event.id().empty(), "SDKEvent envelope has id");
    CHECK(callback_event.timestamp_ms() > 0, "SDKEvent envelope has timestamp");
    CHECK(callback_event.category() == runanywhere::v1::EVENT_CATEGORY_FAILURE,
          "failure event category is canonical");
    CHECK(callback_event.severity() == runanywhere::v1::ERROR_SEVERITY_ERROR,
          "failure event severity is error");
    CHECK(callback_event.has_error(), "failure event includes envelope error");
    CHECK(callback_event.has_failure(), "failure event uses typed payload");
    CHECK(callback_event.failure().error().c_abi_code() == RAC_ERROR_INVALID_ARGUMENT,
          "failure payload preserves C ABI error code");
    CHECK(callback_event.failure().operation() == "unitTestOperation",
          "failure payload preserves operation");

    runanywhere::v1::SDKEvent polled_failure;
    CHECK(poll_event(&polled_failure), "poll returns queued SDKEvent bytes");
    CHECK(polled_failure.id() == callback_event.id(), "callback and poll observe same first event");

    rac_sdk_event_unsubscribe(sub);
    capture.events.clear();
    rac_sdk_event_clear_queue();
    rc = rac_sdk_event_publish_failure(RAC_ERROR_INVALID_ARGUMENT, "after unsubscribe", "llm",
                                       "unsubscribe", RAC_FALSE);
    CHECK(rc == RAC_SUCCESS, "publish after unsubscribe succeeds");
    CHECK(capture.events.empty(), "unsubscribed callback is not invoked");

    rac_sdk_event_clear_queue();
    rac_state_shutdown();
    rac_proto_buffer_t uninitialized_shutdown_poll;
    rac_proto_buffer_init(&uninitialized_shutdown_poll);
    CHECK(rac_sdk_event_poll(&uninitialized_shutdown_poll) == RAC_ERROR_NOT_FOUND,
          "state shutdown before initialization emits no SDKEvent");
    rac_proto_buffer_free(&uninitialized_shutdown_poll);

    rac_sdk_event_clear_queue();
    rc =
        rac_state_initialize(RAC_ENV_DEVELOPMENT, "api-key", "https://example.invalid", "device-1");
    CHECK(rc == RAC_SUCCESS, "state initialize succeeds");

    runanywhere::v1::SDKEvent first_state;
    runanywhere::v1::SDKEvent second_state;
    CHECK(poll_event(&first_state), "poll returns initialization started event");
    CHECK(poll_event(&second_state), "poll returns initialization completed event");
    CHECK(first_state.has_initialization() &&
              first_state.initialization().stage() == runanywhere::v1::INITIALIZATION_STAGE_STARTED,
          "state emits initialization started first");
    CHECK(second_state.has_initialization() && second_state.initialization().stage() ==
                                                   runanywhere::v1::INITIALIZATION_STAGE_COMPLETED,
          "state emits initialization completed second");
    rac_proto_buffer_t empty_poll;
    rac_proto_buffer_init(&empty_poll);
    CHECK(rac_sdk_event_poll(&empty_poll) == RAC_ERROR_NOT_FOUND,
          "poll reports empty queue after ordered events are consumed");
    rac_proto_buffer_free(&empty_poll);

    rac_sdk_event_clear_queue();
    rac_state_set_device_registered(true);
    runanywhere::v1::SDKEvent device_registered;
    CHECK(poll_event(&device_registered), "device registration state true publishes SDKEvent");
    CHECK(device_registered.category() == runanywhere::v1::EVENT_CATEGORY_DEVICE,
          "device registration event category is canonical");
    CHECK(device_registered.has_device(), "device registration event uses DeviceEvent");
    CHECK(device_registered.device().kind() == runanywhere::v1::DEVICE_EVENT_KIND_DEVICE_REGISTERED,
          "device registration true event uses registered kind");
    CHECK(device_registered.device().property() == "registered" &&
              device_registered.device().new_value() == "true",
          "device registration true event carries registered=true transition");

    rac_sdk_event_clear_queue();
    rac_state_reset();
    CHECK(!rac_state_is_device_registered(), "state reset clears device registration flag");
    runanywhere::v1::SDKEvent reset_device;
    CHECK(poll_event(&reset_device), "state reset publishes device unregistered transition");
    CHECK(reset_device.has_device(), "state reset event uses DeviceEvent");
    CHECK(reset_device.device().kind() == runanywhere::v1::DEVICE_EVENT_KIND_DEVICE_STATE_CHANGED,
          "state reset event uses state changed kind");
    CHECK(reset_device.device().property() == "registered" &&
              reset_device.device().new_value() == "false",
          "state reset event carries registered=false transition");

    rac_sdk_event_clear_queue();
    rac_state_reset();
    rac_proto_buffer_t noop_reset_poll;
    rac_proto_buffer_init(&noop_reset_poll);
    CHECK(rac_sdk_event_poll(&noop_reset_poll) == RAC_ERROR_NOT_FOUND,
          "state reset without a registration transition emits no SDKEvent");
    rac_proto_buffer_free(&noop_reset_poll);

    rac_state_set_device_registered(true);
    rac_sdk_event_clear_queue();
    rac_state_shutdown();
    CHECK(!rac_state_is_initialized(), "state shutdown clears initialized flag");
    CHECK(!rac_state_is_device_registered(), "state shutdown clears device registration flag");
    runanywhere::v1::SDKEvent shutdown_device;
    runanywhere::v1::SDKEvent shutdown_event;
    CHECK(poll_event(&shutdown_device),
          "state shutdown publishes device unregistered transition first");
    CHECK(poll_event(&shutdown_event), "state shutdown publishes shutdown event");
    CHECK(shutdown_device.has_device() && shutdown_device.device().property() == "registered" &&
              shutdown_device.device().new_value() == "false",
          "state shutdown device event carries registered=false transition");
    CHECK(shutdown_event.category() == runanywhere::v1::EVENT_CATEGORY_SHUTDOWN,
          "state shutdown event category is canonical");
    CHECK(shutdown_event.has_initialization() && shutdown_event.initialization().stage() ==
                                                     runanywhere::v1::INITIALIZATION_STAGE_SHUTDOWN,
          "state shutdown event uses shutdown initialization stage");

    rac_sdk_event_clear_queue();
    rac_state_shutdown();
    rac_proto_buffer_t noop_shutdown_poll;
    rac_proto_buffer_init(&noop_shutdown_poll);
    CHECK(rac_sdk_event_poll(&noop_shutdown_poll) == RAC_ERROR_NOT_FOUND,
          "state shutdown after shutdown emits no SDKEvent");
    rac_proto_buffer_free(&noop_shutdown_poll);

    rac_sdk_event_clear_queue();
    uint8_t* profile_bytes = nullptr;
    size_t profile_size = 0;
    rc = rac_hardware_profile_get(&profile_bytes, &profile_size);
    CHECK(rc == RAC_SUCCESS && profile_bytes != nullptr && profile_size > 0,
          "hardware profile ABI returns proto bytes");
    runanywhere::v1::SDKEvent hardware_event;
    CHECK(poll_event(&hardware_event), "hardware profile query publishes SDKEvent");
    CHECK(hardware_event.category() == runanywhere::v1::EVENT_CATEGORY_HARDWARE,
          "hardware event category is canonical");
    CHECK(hardware_event.has_hardware_routing(), "hardware event uses typed payload");
    CHECK(hardware_event.hardware_routing().kind() ==
              runanywhere::v1::HARDWARE_ROUTING_EVENT_KIND_PROFILE_COMPLETED,
          "hardware event kind is profile completed");
    CHECK(hardware_event.hardware_routing().hardware_profile().has_profile(),
          "hardware event embeds HardwareProfileResult");
    rac_hardware_profile_free(profile_bytes);

    rac_sdk_event_clear_queue();
    auto vtable = make_llm_vtable("llamacpp_test", 100);
    CHECK(rac_plugin_register(&vtable) == RAC_SUCCESS, "test plugin registers");
    const rac_engine_vtable_t* selected = nullptr;
    rc = rac_plugin_route(RAC_PRIMITIVE_GENERATE_TEXT, 0, nullptr, &selected);
    CHECK(rc == RAC_SUCCESS && selected == &vtable, "route selects test plugin");
    runanywhere::v1::SDKEvent route_event;
    CHECK(poll_event(&route_event), "route publishes SDKEvent");
    CHECK(route_event.category() == runanywhere::v1::EVENT_CATEGORY_ROUTING,
          "route event category is canonical");
    CHECK(route_event.has_hardware_routing(), "route event uses typed payload");
    CHECK(route_event.hardware_routing().kind() ==
              runanywhere::v1::HARDWARE_ROUTING_EVENT_KIND_ROUTE_SELECTED,
          "route event kind is route selected");
    CHECK(route_event.hardware_routing().route() == "llamacpp_test",
          "route event carries selected engine");
    rac_plugin_unregister("llamacpp_test");

    rac_state_shutdown();

    // FLUTTER-AND-PROTO-002 / FLUTTER-IOS-006 regression (CLUSTER-15):
    //
    // Async SDK bindings (Flutter Dart `NativeCallable.listener`, React
    // Native NitroModules) cannot safely dereference the pointer that
    // `rac_sdk_event_publish_proto` passes to the subscriber callback,
    // because the publish path serializes into a 64-slot ring (see
    // `event_publisher.cpp:67-82`) that rotates with each emission. By the
    // time the async binding finally runs on its Dart isolate / JS bridge,
    // the slot may have been overwritten by a later event.
    //
    // The robust contract for those bindings is to drain
    // `rac_sdk_event_poll`, which pops from `g_sdk_event_queue` (owned
    // copies). This test pins the queue invariant:
    //
    //   1. After N publishes, exactly N events can be drained via poll().
    //   2. The order is preserved (FIFO).
    //   3. Each polled buffer round-trips through ParseFromArray with the
    //      expected payload, even when the ring has rotated multiple times
    //      (N >> kSdkEventRingSize=64).
    //
    // If this test ever fails, the consumer-side queue drain in
    // `sdk/runanywhere-flutter/.../dart_bridge_events.dart:_sdkEventCallback`
    // will start dropping or corrupting events again.
    rac_sdk_event_clear_queue();
    const uint64_t burst_sub = rac_sdk_event_subscribe(capture_callback, &capture);
    CHECK(burst_sub != 0, "burst subscription succeeds");
    capture.events.clear();

    constexpr int kBurstSize = 256;  // intentionally > ring size (64).
    for (int i = 0; i < kBurstSize; ++i) {
        rac_result_t burst_rc = rac_sdk_event_publish_failure(
            RAC_ERROR_INVALID_ARGUMENT, "burst_payload", "llm", "burstOperation", RAC_FALSE);
        if (burst_rc != RAC_SUCCESS) {
            ++fail_count;
            ++test_count;
            std::fprintf(stderr, "  FAIL: burst publish %d returned %d\n", i, burst_rc);
            break;
        }
    }
    CHECK(capture.events.size() == static_cast<size_t>(kBurstSize),
          "burst subscriber receives every published event (no drop)");

    int decoded = 0;
    while (true) {
        runanywhere::v1::SDKEvent polled;
        if (!poll_event(&polled)) {
            break;
        }
        if (polled.has_failure() && polled.failure().operation() == "burstOperation") {
            ++decoded;
        }
    }
    CHECK(decoded == kBurstSize,
          "burst drain via rac_sdk_event_poll decodes every event (FIFO contract)");

    rac_sdk_event_unsubscribe(burst_sub);
    rac_sdk_event_clear_queue();

    // commons-core-infra-014: concurrent publish from two threads must not
    // invalidate the buffer a subscriber callback is reading. Each publish
    // allocates its own shared_ptr-owned byte buffer; the synchronous
    // callback pins that buffer via the function-local shared_ptr inside
    // `rac_sdk_event_publish_proto`, so a torn read can only happen if the
    // backing storage were aliased (the prior fixed-ring implementation).
    // This test verifies the no-tear contract with a 1ms sleep inside the
    // subscriber to widen the window in which a peer thread could race.
    rac_sdk_event_clear_queue();

    struct ConcurrentCapture {
        std::mutex mtx;
        std::atomic<uint64_t> torn{0};
        std::atomic<uint64_t> observed{0};
    } concurrent;

    auto concurrent_callback = +[](const uint8_t* bytes, size_t size, void* user_data) {
        auto* sink = static_cast<ConcurrentCapture*>(user_data);
        if (size == 0 || bytes == nullptr) {
            return;
        }
        const uint8_t first = bytes[0];
        std::this_thread::sleep_for(std::chrono::microseconds(50));
        if (bytes[0] != first) {
            sink->torn.fetch_add(1, std::memory_order_relaxed);
        }
        sink->observed.fetch_add(1, std::memory_order_relaxed);
    };

    const uint64_t concurrent_sub =
        rac_sdk_event_subscribe(concurrent_callback, &concurrent);
    CHECK(concurrent_sub != 0, "concurrent subscription succeeds");

    constexpr int kPerThread = 200;
    auto producer = [&](const char* op_tag) {
        for (int i = 0; i < kPerThread; ++i) {
            rac_sdk_event_publish_failure(RAC_ERROR_INVALID_ARGUMENT, op_tag, "llm", op_tag,
                                          RAC_FALSE);
        }
    };
    std::thread t1(producer, "concurrentA");
    std::thread t2(producer, "concurrentB");
    t1.join();
    t2.join();

    CHECK(concurrent.observed.load() == static_cast<uint64_t>(kPerThread * 2),
          "every concurrent publish reaches the subscriber");
    CHECK(concurrent.torn.load() == 0,
          "concurrent publishes do not tear the subscriber buffer view");

    rac_sdk_event_unsubscribe(concurrent_sub);
    rac_sdk_event_clear_queue();

    std::fprintf(stdout, "  %d checks, %d failures\n", test_count, fail_count);
    return fail_count == 0 ? 0 : 1;
#endif
}
