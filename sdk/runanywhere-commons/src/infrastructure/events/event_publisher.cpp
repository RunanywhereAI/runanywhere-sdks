/**
 * @file event_publisher.cpp
 * @brief RunAnywhere Commons - Event Publisher Implementation
 *
 * C++ port of Swift's EventPublisher.swift
 * Provides category-based event subscription matching Swift's pattern.
 */

#include <algorithm>
#include <atomic>
#include <cctype>
#include <chrono>
#include <cstring>
#include <deque>
#include <memory>
#include <mutex>
#include <string>
#include <unordered_map>
#include <vector>

#include "rac/core/rac_error.h"
#include "rac/core/rac_logger.h"
#include "rac/core/rac_types.h"
#include "rac/infrastructure/events/rac_sdk_event_stream.h"
#include "rac/infrastructure/events/rac_events.h"

#if defined(RAC_HAVE_PROTOBUF)
#include "hardware_profile.pb.h"
#include "sdk_events.pb.h"
#endif

// =============================================================================
// INTERNAL STORAGE
// =============================================================================

namespace {

struct Subscription {
    uint64_t id;
    rac_event_callback_fn callback;
    void* user_data;
    std::shared_ptr<std::atomic<bool>> alive;
};

struct SDKEventSubscription {
    uint64_t id;
    rac_sdk_event_callback_fn callback;
    void* user_data;
    std::shared_ptr<std::atomic<bool>> alive;
};

std::mutex g_event_mutex;
std::atomic<uint64_t> g_next_subscription_id{1};
std::atomic<uint64_t> g_next_sdk_event_subscription_id{1};

// Subscriptions per category
std::unordered_map<rac_event_category_t, std::vector<Subscription>> g_subscriptions;

// All-events subscriptions
std::vector<Subscription> g_all_subscriptions;

std::mutex g_sdk_event_mutex;
std::vector<SDKEventSubscription> g_sdk_event_subscriptions;
std::deque<std::vector<uint8_t>> g_sdk_event_queue;

uint64_t current_time_ms() {
    using namespace std::chrono;
    return duration_cast<milliseconds>(system_clock::now().time_since_epoch()).count();
}

// Generate a simple UUID-like ID
std::string generate_event_id() {
    static std::atomic<uint64_t> counter{0};
    auto now = current_time_ms();
    auto count = counter.fetch_add(1);
    char buffer[64];
    snprintf(buffer, sizeof(buffer), "%llu-%llu", static_cast<unsigned long long>(now),
             static_cast<unsigned long long>(count));
    return buffer;
}

std::string lowercase(const char* value) {
    std::string out = value ? value : "";
    std::transform(out.begin(), out.end(), out.begin(),
                   [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
    return out;
}

#if defined(RAC_HAVE_PROTOBUF)

runanywhere::v1::EventCategory category_for_error(rac_result_t code) {
    if (code <= -150 && code >= -179) return runanywhere::v1::EVENT_CATEGORY_NETWORK;
    if (code <= -250 && code >= -279) return runanywhere::v1::EVENT_CATEGORY_ERROR;
    if (code <= -110 && code >= -129) return runanywhere::v1::EVENT_CATEGORY_MODEL;
    if (code <= -230 && code >= -249) return runanywhere::v1::EVENT_CATEGORY_COMPONENT;
    if ((code <= -180 && code >= -219) || (code <= -280 && code >= -299)) {
        return runanywhere::v1::EVENT_CATEGORY_STORAGE;
    }
    if (code <= -320 && code >= -329) return runanywhere::v1::EVENT_CATEGORY_AUTH;
    if (code <= -100 && code >= -109) return runanywhere::v1::EVENT_CATEGORY_INITIALIZATION;
    return runanywhere::v1::EVENT_CATEGORY_FAILURE;
}

runanywhere::v1::ErrorCategory error_category_for_code(rac_result_t code) {
    if (code <= -150 && code >= -179) return runanywhere::v1::ERROR_CATEGORY_NETWORK;
    if (code <= -250 && code >= -279) return runanywhere::v1::ERROR_CATEGORY_VALIDATION;
    if (code <= -110 && code >= -129) return runanywhere::v1::ERROR_CATEGORY_MODEL;
    if ((code <= -180 && code >= -219) || (code <= -280 && code >= -299)) {
        return runanywhere::v1::ERROR_CATEGORY_IO;
    }
    if (code <= -320 && code >= -329) return runanywhere::v1::ERROR_CATEGORY_AUTH;
    if (code <= -100 && code >= -109) return runanywhere::v1::ERROR_CATEGORY_CONFIGURATION;
    if ((code <= -230 && code >= -249) || (code <= -300 && code >= -319)) {
        return runanywhere::v1::ERROR_CATEGORY_COMPONENT;
    }
    return runanywhere::v1::ERROR_CATEGORY_INTERNAL;
}

runanywhere::v1::SDKComponent component_from_string(const char* component) {
    const std::string c = lowercase(component);
    if (c == "stt" || c == "asr") return runanywhere::v1::SDK_COMPONENT_STT;
    if (c == "tts") return runanywhere::v1::SDK_COMPONENT_TTS;
    if (c == "vad") return runanywhere::v1::SDK_COMPONENT_VAD;
    if (c == "llm") return runanywhere::v1::SDK_COMPONENT_LLM;
    if (c == "vlm") return runanywhere::v1::SDK_COMPONENT_VLM;
    if (c == "diffusion") return runanywhere::v1::SDK_COMPONENT_DIFFUSION;
    if (c == "rag" || c == "rerank") return runanywhere::v1::SDK_COMPONENT_RAG;
    if (c == "embeddings" || c == "embedding") return runanywhere::v1::SDK_COMPONENT_EMBEDDINGS;
    if (c == "voice_agent" || c == "voice-agent") return runanywhere::v1::SDK_COMPONENT_VOICE_AGENT;
    if (c == "wakeword" || c == "wake_word") return runanywhere::v1::SDK_COMPONENT_WAKEWORD;
    return runanywhere::v1::SDK_COMPONENT_UNSPECIFIED;
}

runanywhere::v1::SDKComponent component_for_primitive(rac_primitive_t primitive) {
    switch (primitive) {
        case RAC_PRIMITIVE_GENERATE_TEXT:
            return runanywhere::v1::SDK_COMPONENT_LLM;
        case RAC_PRIMITIVE_TRANSCRIBE:
            return runanywhere::v1::SDK_COMPONENT_STT;
        case RAC_PRIMITIVE_SYNTHESIZE:
            return runanywhere::v1::SDK_COMPONENT_TTS;
        case RAC_PRIMITIVE_DETECT_VOICE:
            return runanywhere::v1::SDK_COMPONENT_VAD;
        case RAC_PRIMITIVE_EMBED:
            return runanywhere::v1::SDK_COMPONENT_EMBEDDINGS;
        case RAC_PRIMITIVE_RERANK:
            return runanywhere::v1::SDK_COMPONENT_RAG;
        case RAC_PRIMITIVE_VLM:
            return runanywhere::v1::SDK_COMPONENT_VLM;
        case RAC_PRIMITIVE_DIFFUSION:
            return runanywhere::v1::SDK_COMPONENT_DIFFUSION;
        default:
            return runanywhere::v1::SDK_COMPONENT_UNSPECIFIED;
    }
}

runanywhere::v1::InferenceFramework framework_for_engine(const rac_engine_vtable_t* vtable) {
    if (!vtable || !vtable->metadata.name) return runanywhere::v1::INFERENCE_FRAMEWORK_UNSPECIFIED;
    const std::string name = lowercase(vtable->metadata.name);
    if (name.find("onnx") != std::string::npos) return runanywhere::v1::INFERENCE_FRAMEWORK_ONNX;
    if (name.find("llama") != std::string::npos) {
        return runanywhere::v1::INFERENCE_FRAMEWORK_LLAMA_CPP;
    }
    if (name.find("whisperkit") != std::string::npos &&
        name.find("coreml") != std::string::npos) {
        return runanywhere::v1::INFERENCE_FRAMEWORK_WHISPERKIT_COREML;
    }
    if (name.find("coreml") != std::string::npos) return runanywhere::v1::INFERENCE_FRAMEWORK_COREML;
    if (name.find("metal") != std::string::npos) return runanywhere::v1::INFERENCE_FRAMEWORK_METALRT;
    if (name.find("genie") != std::string::npos) return runanywhere::v1::INFERENCE_FRAMEWORK_GENIE;
    if (name.find("sherpa") != std::string::npos) return runanywhere::v1::INFERENCE_FRAMEWORK_SHERPA;
    if (name.find("piper") != std::string::npos) return runanywhere::v1::INFERENCE_FRAMEWORK_PIPER_TTS;
    return runanywhere::v1::INFERENCE_FRAMEWORK_UNKNOWN;
}

void populate_envelope(runanywhere::v1::SDKEvent* event,
                       runanywhere::v1::EventCategory category,
                       runanywhere::v1::EventSeverity severity,
                       runanywhere::v1::SDKComponent component =
                           runanywhere::v1::SDK_COMPONENT_UNSPECIFIED) {
    event->set_timestamp_ms(static_cast<int64_t>(current_time_ms()));
    event->set_id(generate_event_id());
    event->set_category(category);
    event->set_severity(severity);
    event->set_component(component);
    event->set_destination(runanywhere::v1::EVENT_DESTINATION_ALL);
}

void populate_error(runanywhere::v1::SDKError* error,
                    rac_result_t code,
                    const char* message,
                    runanywhere::v1::SDKComponent component,
                    runanywhere::v1::ErrorSeverity severity =
                        runanywhere::v1::ERROR_SEVERITY_ERROR) {
    const int32_t c_code = static_cast<int32_t>(code);
    const int32_t abs_code = c_code < 0 ? -c_code : c_code;
    error->set_code(static_cast<runanywhere::v1::ErrorCode>(abs_code));
    error->set_category(error_category_for_code(code));
    error->set_message(message && message[0] ? message : rac_error_message(code));
    error->set_c_abi_code(c_code);
    error->set_timestamp_ms(static_cast<int64_t>(current_time_ms()));
    error->set_severity(severity);
    error->set_component(runanywhere::v1::SDKComponent_Name(component));
}

rac_result_t publish_message(const runanywhere::v1::SDKEvent& event) {
    const size_t size = event.ByteSizeLong();
    std::vector<uint8_t> bytes(size);
    if (size > 0 &&
        !event.SerializeToArray(bytes.data(), static_cast<int>(bytes.size()))) {
        return RAC_ERROR_EVENT_PUBLISH_FAILED;
    }
    return rac_sdk_event_publish_proto(bytes.data(), bytes.size());
}

#endif

}  // namespace

// =============================================================================
// EVENT SUBSCRIPTION API
// =============================================================================

extern "C" {

uint64_t rac_event_subscribe(rac_event_category_t category, rac_event_callback_fn callback,
                             void* user_data) {
    if (callback == nullptr) {
        return 0;
    }

    std::lock_guard<std::mutex> lock(g_event_mutex);

    Subscription sub;
    sub.id = g_next_subscription_id.fetch_add(1);
    sub.callback = callback;
    sub.user_data = user_data;
    sub.alive = std::make_shared<std::atomic<bool>>(true);

    g_subscriptions[category].push_back(sub);

    return sub.id;
}

uint64_t rac_event_subscribe_all(rac_event_callback_fn callback, void* user_data) {
    if (callback == nullptr) {
        return 0;
    }

    std::lock_guard<std::mutex> lock(g_event_mutex);

    Subscription sub;
    sub.id = g_next_subscription_id.fetch_add(1);
    sub.callback = callback;
    sub.user_data = user_data;
    sub.alive = std::make_shared<std::atomic<bool>>(true);

    g_all_subscriptions.push_back(sub);

    return sub.id;
}

void rac_event_unsubscribe(uint64_t subscription_id) {
    if (subscription_id == 0) {
        return;
    }

    std::lock_guard<std::mutex> lock(g_event_mutex);

    auto remove_from = [subscription_id](std::vector<Subscription>& subs) {
        auto it = std::remove_if(subs.begin(), subs.end(), [subscription_id](Subscription& s) {
            if (s.id == subscription_id) {
                s.alive->store(false);
                return true;
            }
            return false;
        });
        if (it != subs.end()) {
            subs.erase(it, subs.end());
            return true;
        }
        return false;
    };

    // Check all-events subscriptions
    if (remove_from(g_all_subscriptions)) {
        return;
    }

    // Check category-specific subscriptions
    for (auto& pair : g_subscriptions) {
        if (remove_from(pair.second)) {
            return;
        }
    }
}

rac_result_t rac_event_publish(const rac_event_t* event) {
    if (event == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }

    // Create a copy with timestamp if not set
    rac_event_t event_copy = *event;
    if (event_copy.timestamp_ms == 0) {
        event_copy.timestamp_ms = static_cast<int64_t>(current_time_ms());
    }

    // Copy subscriber lists under lock, then invoke callbacks without lock
    // to avoid deadlock if a callback subscribes/unsubscribes/publishes.
    std::vector<Subscription> category_subs;
    std::vector<Subscription> all_subs;

    {
        std::lock_guard<std::mutex> lock(g_event_mutex);

        auto it = g_subscriptions.find(event_copy.category);
        if (it != g_subscriptions.end()) {
            category_subs = it->second;
        }
        all_subs = g_all_subscriptions;
    }

    // Notify category-specific subscribers (skip if unsubscribed after snapshot)
    for (const auto& sub : category_subs) {
        if (sub.alive->load()) {
            sub.callback(&event_copy, sub.user_data);
        }
    }

    // Notify all-events subscribers (skip if unsubscribed after snapshot)
    for (const auto& sub : all_subs) {
        if (sub.alive->load()) {
            sub.callback(&event_copy, sub.user_data);
        }
    }

    return RAC_SUCCESS;
}

rac_result_t rac_event_track(const char* type, rac_event_category_t category,
                             rac_event_destination_t destination, const char* properties_json) {
    if (type == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }

    // Generate event ID
    static thread_local std::string s_event_id;
    s_event_id = generate_event_id();

    rac_event_t event = {};
    event.id = s_event_id.c_str();
    event.type = type;
    event.category = category;
    event.timestamp_ms = static_cast<int64_t>(current_time_ms());
    event.session_id = nullptr;
    event.destination = destination;
    event.properties_json = properties_json;

    return rac_event_publish(&event);
}

const char* rac_event_category_name(rac_event_category_t category) {
    switch (category) {
        case RAC_EVENT_CATEGORY_SDK:
            return "sdk";
        case RAC_EVENT_CATEGORY_MODEL:
            return "model";
        case RAC_EVENT_CATEGORY_LLM:
            return "llm";
        case RAC_EVENT_CATEGORY_STT:
            return "stt";
        case RAC_EVENT_CATEGORY_TTS:
            return "tts";
        case RAC_EVENT_CATEGORY_VOICE:
            return "voice";
        case RAC_EVENT_CATEGORY_STORAGE:
            return "storage";
        case RAC_EVENT_CATEGORY_DEVICE:
            return "device";
        case RAC_EVENT_CATEGORY_NETWORK:
            return "network";
        case RAC_EVENT_CATEGORY_ERROR:
            return "error";
        default:
            return "unknown";
    }
}

}  // extern "C"

// =============================================================================
// CANONICAL SDK EVENT PROTO-BYTE STREAM API
// =============================================================================

extern "C" {

uint64_t rac_sdk_event_subscribe(rac_sdk_event_callback_fn callback, void* user_data) {
    if (callback == nullptr) {
        return 0;
    }

    std::lock_guard<std::mutex> lock(g_sdk_event_mutex);

    SDKEventSubscription sub;
    sub.id = g_next_sdk_event_subscription_id.fetch_add(1);
    sub.callback = callback;
    sub.user_data = user_data;
    sub.alive = std::make_shared<std::atomic<bool>>(true);
    g_sdk_event_subscriptions.push_back(sub);
    return sub.id;
}

void rac_sdk_event_unsubscribe(uint64_t subscription_id) {
    if (subscription_id == 0) {
        return;
    }

    std::lock_guard<std::mutex> lock(g_sdk_event_mutex);
    auto it = std::remove_if(g_sdk_event_subscriptions.begin(), g_sdk_event_subscriptions.end(),
                             [subscription_id](SDKEventSubscription& sub) {
                                 if (sub.id == subscription_id) {
                                     sub.alive->store(false);
                                     return true;
                                 }
                                 return false;
                             });
    g_sdk_event_subscriptions.erase(it, g_sdk_event_subscriptions.end());
}

rac_result_t rac_sdk_event_publish_proto(const uint8_t* proto_bytes, size_t proto_size) {
    if (!proto_bytes && proto_size != 0) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    std::vector<uint8_t> bytes;
    if (proto_size > 0) {
        bytes.assign(proto_bytes, proto_bytes + proto_size);
    }

    std::vector<SDKEventSubscription> subscriptions;
    {
        std::lock_guard<std::mutex> lock(g_sdk_event_mutex);
        g_sdk_event_queue.push_back(bytes);
        subscriptions = g_sdk_event_subscriptions;
    }

    const uint8_t* callback_data = bytes.empty() ? nullptr : bytes.data();
    for (const auto& sub : subscriptions) {
        if (sub.alive->load()) {
            sub.callback(callback_data, bytes.size(), sub.user_data);
        }
    }

    return RAC_SUCCESS;
}

rac_result_t rac_sdk_event_poll(rac_proto_buffer_t* out_event) {
    if (!out_event) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    std::lock_guard<std::mutex> lock(g_sdk_event_mutex);
    if (g_sdk_event_queue.empty()) {
        return RAC_ERROR_NOT_FOUND;
    }

    const auto& bytes = g_sdk_event_queue.front();
    rac_result_t rc = rac_proto_buffer_copy(bytes.empty() ? nullptr : bytes.data(), bytes.size(),
                                            out_event);
    if (rc != RAC_SUCCESS) {
        return rc;
    }

    g_sdk_event_queue.pop_front();
    return RAC_SUCCESS;
}

rac_result_t rac_sdk_event_publish_failure(rac_result_t error_code,
                                           const char* message,
                                           const char* component,
                                           const char* operation,
                                           rac_bool_t recoverable) {
#if defined(RAC_HAVE_PROTOBUF)
    const auto sdk_component = component_from_string(component);
    runanywhere::v1::SDKEvent event;
    populate_envelope(&event, runanywhere::v1::EVENT_CATEGORY_FAILURE,
                      runanywhere::v1::EVENT_SEVERITY_ERROR, sdk_component);
    populate_error(event.mutable_error(), error_code, message, sdk_component);

    auto* failure = event.mutable_failure();
    failure->set_component(sdk_component);
    if (operation) failure->set_operation(operation);
    failure->set_recoverable(recoverable == RAC_TRUE);
    failure->mutable_error()->CopyFrom(event.error());
    return publish_message(event);
#else
    (void)error_code;
    (void)message;
    (void)component;
    (void)operation;
    (void)recoverable;
    return RAC_ERROR_FEATURE_NOT_AVAILABLE;
#endif
}

void rac_sdk_event_clear_queue(void) {
    std::lock_guard<std::mutex> lock(g_sdk_event_mutex);
    g_sdk_event_queue.clear();
}

}  // extern "C"

namespace rac {
namespace events {

rac_result_t publish_initialization_started(void) {
#if defined(RAC_HAVE_PROTOBUF)
    runanywhere::v1::SDKEvent event;
    populate_envelope(&event, runanywhere::v1::EVENT_CATEGORY_INITIALIZATION,
                      runanywhere::v1::EVENT_SEVERITY_INFO);
    event.mutable_initialization()->set_stage(
        runanywhere::v1::INITIALIZATION_STAGE_STARTED);
    return publish_message(event);
#else
    return RAC_ERROR_FEATURE_NOT_AVAILABLE;
#endif
}

rac_result_t publish_initialization_completed(void) {
#if defined(RAC_HAVE_PROTOBUF)
    runanywhere::v1::SDKEvent event;
    populate_envelope(&event, runanywhere::v1::EVENT_CATEGORY_INITIALIZATION,
                      runanywhere::v1::EVENT_SEVERITY_INFO);
    event.mutable_initialization()->set_stage(
        runanywhere::v1::INITIALIZATION_STAGE_COMPLETED);
    return publish_message(event);
#else
    return RAC_ERROR_FEATURE_NOT_AVAILABLE;
#endif
}

rac_result_t publish_initialization_failed(rac_result_t error_code, const char* message) {
#if defined(RAC_HAVE_PROTOBUF)
    runanywhere::v1::SDKEvent event;
    populate_envelope(&event, runanywhere::v1::EVENT_CATEGORY_INITIALIZATION,
                      runanywhere::v1::EVENT_SEVERITY_ERROR);
    auto* init = event.mutable_initialization();
    init->set_stage(runanywhere::v1::INITIALIZATION_STAGE_FAILED);
    if (message) init->set_error(message);
    populate_error(event.mutable_error(), error_code, message,
                   runanywhere::v1::SDK_COMPONENT_UNSPECIFIED);
    return publish_message(event);
#else
    (void)error_code;
    (void)message;
    return RAC_ERROR_FEATURE_NOT_AVAILABLE;
#endif
}

rac_result_t publish_shutdown(void) {
#if defined(RAC_HAVE_PROTOBUF)
    runanywhere::v1::SDKEvent event;
    populate_envelope(&event, runanywhere::v1::EVENT_CATEGORY_SHUTDOWN,
                      runanywhere::v1::EVENT_SEVERITY_INFO);
    event.mutable_initialization()->set_stage(
        runanywhere::v1::INITIALIZATION_STAGE_SHUTDOWN);
    return publish_message(event);
#else
    return RAC_ERROR_FEATURE_NOT_AVAILABLE;
#endif
}

rac_result_t publish_device_registered(const char* device_id) {
#if defined(RAC_HAVE_PROTOBUF)
    runanywhere::v1::SDKEvent event;
    populate_envelope(&event, runanywhere::v1::EVENT_CATEGORY_DEVICE,
                      runanywhere::v1::EVENT_SEVERITY_INFO);
    auto* device = event.mutable_device();
    device->set_kind(runanywhere::v1::DEVICE_EVENT_KIND_DEVICE_REGISTERED);
    if (device_id) device->set_device_id(device_id);
    return publish_message(event);
#else
    (void)device_id;
    return RAC_ERROR_FEATURE_NOT_AVAILABLE;
#endif
}

rac_result_t publish_device_registration_failed(rac_result_t error_code, const char* message) {
#if defined(RAC_HAVE_PROTOBUF)
    runanywhere::v1::SDKEvent event;
    populate_envelope(&event, runanywhere::v1::EVENT_CATEGORY_DEVICE,
                      runanywhere::v1::EVENT_SEVERITY_ERROR);
    auto* device = event.mutable_device();
    device->set_kind(runanywhere::v1::DEVICE_EVENT_KIND_DEVICE_REGISTRATION_FAILED);
    if (message) device->set_error(message);
    populate_error(event.mutable_error(), error_code, message,
                   runanywhere::v1::SDK_COMPONENT_UNSPECIFIED);
    return publish_message(event);
#else
    (void)error_code;
    (void)message;
    return RAC_ERROR_FEATURE_NOT_AVAILABLE;
#endif
}

rac_result_t publish_device_registration_state_changed(bool registered) {
#if defined(RAC_HAVE_PROTOBUF)
    runanywhere::v1::SDKEvent event;
    populate_envelope(&event, runanywhere::v1::EVENT_CATEGORY_DEVICE,
                      runanywhere::v1::EVENT_SEVERITY_INFO);
    auto* device = event.mutable_device();
    device->set_kind(registered ? runanywhere::v1::DEVICE_EVENT_KIND_DEVICE_REGISTERED
                                : runanywhere::v1::DEVICE_EVENT_KIND_DEVICE_STATE_CHANGED);
    device->set_property("registered");
    device->set_new_value(registered ? "true" : "false");
    return publish_message(event);
#else
    (void)registered;
    return RAC_ERROR_FEATURE_NOT_AVAILABLE;
#endif
}

rac_result_t publish_hardware_profile_completed(const uint8_t* profile_bytes,
                                                size_t profile_size) {
#if defined(RAC_HAVE_PROTOBUF)
    runanywhere::v1::SDKEvent event;
    populate_envelope(&event, runanywhere::v1::EVENT_CATEGORY_HARDWARE,
                      runanywhere::v1::EVENT_SEVERITY_INFO);
    auto* hardware = event.mutable_hardware_routing();
    hardware->set_kind(runanywhere::v1::HARDWARE_ROUTING_EVENT_KIND_PROFILE_COMPLETED);
    hardware->set_capability("hardware_profile");
    if (profile_bytes && profile_size > 0) {
        if (!hardware->mutable_hardware_profile()->ParseFromArray(
                profile_bytes, static_cast<int>(profile_size))) {
            hardware->set_error("failed to decode HardwareProfileResult");
            populate_error(event.mutable_error(), RAC_ERROR_DECODING_ERROR,
                           "failed to decode HardwareProfileResult",
                           runanywhere::v1::SDK_COMPONENT_UNSPECIFIED);
            event.set_severity(runanywhere::v1::EVENT_SEVERITY_ERROR);
        }
    }
    return publish_message(event);
#else
    (void)profile_bytes;
    (void)profile_size;
    return RAC_ERROR_FEATURE_NOT_AVAILABLE;
#endif
}

rac_result_t publish_route_selected(rac_primitive_t primitive,
                                    const rac_engine_vtable_t* vtable,
                                    const char* reason) {
#if defined(RAC_HAVE_PROTOBUF)
    const auto component = component_for_primitive(primitive);
    runanywhere::v1::SDKEvent event;
    populate_envelope(&event, runanywhere::v1::EVENT_CATEGORY_ROUTING,
                      runanywhere::v1::EVENT_SEVERITY_INFO, component);
    auto* routing = event.mutable_hardware_routing();
    routing->set_kind(runanywhere::v1::HARDWARE_ROUTING_EVENT_KIND_ROUTE_SELECTED);
    routing->set_component(component);
    routing->set_framework(framework_for_engine(vtable));
    routing->set_capability(rac_primitive_name(primitive));
    if (vtable && vtable->metadata.name) routing->set_route(vtable->metadata.name);
    if (reason) routing->set_reason(reason);
    return publish_message(event);
#else
    (void)primitive;
    (void)vtable;
    (void)reason;
    return RAC_ERROR_FEATURE_NOT_AVAILABLE;
#endif
}

rac_result_t publish_route_failed(rac_primitive_t primitive,
                                  rac_result_t error_code,
                                  const char* reason) {
#if defined(RAC_HAVE_PROTOBUF)
    const auto component = component_for_primitive(primitive);
    runanywhere::v1::SDKEvent event;
    populate_envelope(&event, category_for_error(error_code),
                      runanywhere::v1::EVENT_SEVERITY_ERROR, component);
    auto* routing = event.mutable_hardware_routing();
    routing->set_kind(runanywhere::v1::HARDWARE_ROUTING_EVENT_KIND_FRAMEWORK_CAPABILITY_MISSING);
    routing->set_component(component);
    routing->set_capability(rac_primitive_name(primitive));
    if (reason) {
        routing->set_reason(reason);
        routing->set_error(reason);
    }
    populate_error(event.mutable_error(), error_code, reason, component);
    return publish_message(event);
#else
    (void)primitive;
    (void)error_code;
    (void)reason;
    return RAC_ERROR_FEATURE_NOT_AVAILABLE;
#endif
}

}  // namespace events
}  // namespace rac

// =============================================================================
// INTERNAL RESET (for testing)
// =============================================================================

namespace rac_internal {

void reset_event_publisher() {
    std::lock_guard<std::mutex> lock(g_event_mutex);
    g_subscriptions.clear();
    g_all_subscriptions.clear();
    g_next_subscription_id.store(1);
    {
        std::lock_guard<std::mutex> sdk_lock(g_sdk_event_mutex);
        g_sdk_event_subscriptions.clear();
        g_sdk_event_queue.clear();
        g_next_sdk_event_subscription_id.store(1);
    }
}

}  // namespace rac_internal
