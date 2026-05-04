/**
 * HybridRunAnywhereCore+Events.cpp
 *
 * Domain implementation for HybridRunAnywhereCore.
 */
#include "HybridRunAnywhereCore+Common.hpp"
#include "HybridRunAnywhereCore+ProtoCompat.hpp"

namespace margelo::nitro::runanywhere {

using namespace ::runanywhere::bridges;

namespace {

struct SDKEventProtoRegistration {
    std::function<void(const std::shared_ptr<ArrayBuffer>&)> onEventBytes;
    uint64_t subscriptionId = 0;
    std::atomic<bool> active{true};
};

std::mutex g_sdkEventProtoMutex;
std::unordered_map<uint64_t, SDKEventProtoRegistration*> g_sdkEventProtoRegistrations;

std::vector<uint8_t> copyEventArrayBufferBytes(const std::shared_ptr<ArrayBuffer>& buffer) {
    std::vector<uint8_t> bytes;
    if (!buffer) {
        return bytes;
    }

    uint8_t* data = buffer->data();
    size_t size = buffer->size();
    if (!data || size == 0) {
        return bytes;
    }

    bytes.assign(data, data + size);
    return bytes;
}

std::shared_ptr<ArrayBuffer> emptyEventProtoBuffer() {
    return ArrayBuffer::allocate(0);
}

std::shared_ptr<ArrayBuffer> copyEventProtoBuffer(rac_proto_buffer_t& protoBuffer) {
    if (protoBuffer.status != RAC_SUCCESS) {
        proto_compat::freeBuffer(&protoBuffer);
        return emptyEventProtoBuffer();
    }

    if (!protoBuffer.data || protoBuffer.size == 0) {
        proto_compat::freeBuffer(&protoBuffer);
        return emptyEventProtoBuffer();
    }

    auto buffer = ArrayBuffer::copy(protoBuffer.data, protoBuffer.size);
    proto_compat::freeBuffer(&protoBuffer);
    return buffer;
}

void sdkEventProtoTrampoline(const uint8_t* protoBytes,
                             size_t protoSize,
                             void* userData) {
    if (!userData || !protoBytes || protoSize == 0) {
        return;
    }

    auto* registration = static_cast<SDKEventProtoRegistration*>(userData);
    if (!registration->active.load(std::memory_order_acquire) ||
        !registration->onEventBytes) {
        return;
    }

    auto buffer = ArrayBuffer::copy(protoBytes, protoSize);
    try {
        registration->onEventBytes(buffer);
    } catch (...) {
    }
}

} // namespace

// Events
// ============================================================================
// Events
// ============================================================================

std::shared_ptr<Promise<void>> HybridRunAnywhereCore::emitEvent(
    const std::string& eventJson) {
    return Promise<void>::async([eventJson]() -> void {
        std::string type = extractStringValue(eventJson, "type");
        std::string categoryStr = extractStringValue(eventJson, "category", "sdk");

        EventCategory category = EventCategory::SDK;
        if (categoryStr == "model") category = EventCategory::Model;
        else if (categoryStr == "llm") category = EventCategory::LLM;
        else if (categoryStr == "stt") category = EventCategory::STT;
        else if (categoryStr == "tts") category = EventCategory::TTS;

        EventBridge::shared().trackEvent(type, category, EventDestination::All, eventJson);
    });
}

std::shared_ptr<Promise<std::string>> HybridRunAnywhereCore::pollEvents() {
    // Events are push-based via callback, not polling
    return Promise<std::string>::async([]() -> std::string {
        return "[]";
    });
}

std::shared_ptr<Promise<double>>
HybridRunAnywhereCore::subscribeSDKEventsProto(
    const std::function<void(const std::shared_ptr<ArrayBuffer>&)>& onEventBytes) {
    return Promise<double>::async([onEventBytes]() -> double {
        if (!onEventBytes) {
            return 0.0;
        }

        auto* registration = new SDKEventProtoRegistration();
        registration->onEventBytes = onEventBytes;

        auto subscribe =
            proto_compat::symbol<proto_compat::SDKEventSubscribeFn>(
                "rac_sdk_event_subscribe");
        if (!subscribe) {
            delete registration;
            LOGE("subscribeSDKEventsProto: rac_sdk_event_subscribe unavailable");
            return 0.0;
        }

        uint64_t subscriptionId = subscribe(
            &sdkEventProtoTrampoline,
            registration);
        if (subscriptionId == 0) {
            delete registration;
            LOGE("subscribeSDKEventsProto: subscription failed");
            return 0.0;
        }

        registration->subscriptionId = subscriptionId;
        {
            std::lock_guard<std::mutex> lock(g_sdkEventProtoMutex);
            g_sdkEventProtoRegistrations[subscriptionId] = registration;
        }

        return static_cast<double>(subscriptionId);
    });
}

std::shared_ptr<Promise<void>>
HybridRunAnywhereCore::unsubscribeSDKEventsProto(double subscriptionId) {
    return Promise<void>::async([subscriptionId]() -> void {
        uint64_t id = static_cast<uint64_t>(subscriptionId);
        SDKEventProtoRegistration* registration = nullptr;
        {
            std::lock_guard<std::mutex> lock(g_sdkEventProtoMutex);
            auto it = g_sdkEventProtoRegistrations.find(id);
            if (it != g_sdkEventProtoRegistrations.end()) {
                registration = it->second;
                g_sdkEventProtoRegistrations.erase(it);
            }
        }

        if (auto unsubscribe =
                proto_compat::symbol<proto_compat::SDKEventUnsubscribeFn>(
                    "rac_sdk_event_unsubscribe")) {
            unsubscribe(id);
        } else {
            LOGE("unsubscribeSDKEventsProto: rac_sdk_event_unsubscribe unavailable");
        }
        if (registration) {
            registration->active.store(false, std::memory_order_release);
            delete registration;
        }
    });
}

std::shared_ptr<Promise<bool>>
HybridRunAnywhereCore::publishSDKEventProto(const std::shared_ptr<ArrayBuffer>& eventBytes) {
    auto bytes = copyEventArrayBufferBytes(eventBytes);
    return Promise<bool>::async([bytes = std::move(bytes)]() -> bool {
        if (bytes.empty()) {
            LOGE("publishSDKEventProto: empty payload");
            return false;
        }

        auto publishProto =
            proto_compat::symbol<proto_compat::SDKEventPublishProtoFn>(
                "rac_sdk_event_publish_proto");
        if (!publishProto) {
            LOGE("publishSDKEventProto: rac_sdk_event_publish_proto unavailable");
            return false;
        }

        rac_result_t rc = publishProto(bytes.data(), bytes.size());
        if (rc != RAC_SUCCESS) {
            LOGE("publishSDKEventProto: rc=%d", rc);
            return false;
        }
        return true;
    });
}

std::shared_ptr<Promise<std::shared_ptr<ArrayBuffer>>>
HybridRunAnywhereCore::pollSDKEventProto() {
    return Promise<std::shared_ptr<ArrayBuffer>>::async([]() -> std::shared_ptr<ArrayBuffer> {
        rac_proto_buffer_t out;
        proto_compat::initBuffer(&out);
        auto poll =
            proto_compat::symbol<proto_compat::SDKEventPollFn>(
                "rac_sdk_event_poll");
        if (!poll) {
            LOGE("pollSDKEventProto: rac_sdk_event_poll unavailable");
            return emptyEventProtoBuffer();
        }

        rac_result_t rc = poll(&out);
        if (rc != RAC_SUCCESS) {
            proto_compat::freeBuffer(&out);
            return emptyEventProtoBuffer();
        }
        return copyEventProtoBuffer(out);
    });
}

std::shared_ptr<Promise<bool>>
HybridRunAnywhereCore::publishSDKFailureProto(double errorCode,
                                              const std::string& message,
                                              const std::string& component,
                                              const std::string& operation,
                                              bool recoverable) {
    return Promise<bool>::async([errorCode, message, component, operation, recoverable]() -> bool {
        auto publishFailure =
            proto_compat::symbol<proto_compat::SDKEventPublishFailureFn>(
                "rac_sdk_event_publish_failure");
        if (!publishFailure) {
            LOGE("publishSDKFailureProto: rac_sdk_event_publish_failure unavailable");
            return false;
        }

        rac_result_t rc = publishFailure(
            static_cast<rac_result_t>(errorCode),
            message.c_str(),
            component.c_str(),
            operation.c_str(),
            recoverable ? RAC_TRUE : RAC_FALSE);
        if (rc != RAC_SUCCESS) {
            LOGE("publishSDKFailureProto: rc=%d", rc);
            return false;
        }
        return true;
    });
}

} // namespace margelo::nitro::runanywhere
