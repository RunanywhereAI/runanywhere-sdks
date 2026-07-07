// SPDX-License-Identifier: Apache-2.0
//
// Android Flutter native-port helpers for proto stream callbacks.
//
// Commons callback bytes are borrowed for the duration of the native callback
// only. These helpers copy bytes synchronously inside that callback and post
// owned typed-data messages to Dart ReceivePorts. The Dart bridges prefer these
// helpers over NativeCallable.isolateLocal when present, matching the iOS
// helpers in packages/runanywhere/ios/Classes/*NativePort.mm.

#include <atomic>
#include <cstdint>
#include <cstdlib>
#include <memory>
#include <mutex>
#include <unordered_map>
#include <vector>

namespace {

using rac_result_t = int32_t;
using rac_bool_t = int32_t;
using rac_handle_t = void*;
struct rac_voice_agent;
using rac_voice_agent_handle_t = rac_voice_agent*;

constexpr rac_result_t RAC_SUCCESS = 0;
constexpr rac_result_t RAC_ERROR_INVALID_ARGUMENT = -259;
constexpr rac_bool_t RAC_TRUE = 1;
constexpr rac_bool_t RAC_FALSE = 0;

using Dart_Port = int64_t;

enum Dart_TypedData_Type {
    Dart_TypedData_kByteData = 0,
    Dart_TypedData_kInt8,
    Dart_TypedData_kUint8,
};

enum Dart_CObject_Type {
    Dart_CObject_kNull = 0,
    Dart_CObject_kBool,
    Dart_CObject_kInt32,
    Dart_CObject_kInt64,
    Dart_CObject_kDouble,
    Dart_CObject_kString,
    Dart_CObject_kArray,
    Dart_CObject_kTypedData,
};

struct Dart_CObject;

struct Dart_CObject {
    Dart_CObject_Type type;
    union {
        bool as_bool;
        int32_t as_int32;
        int64_t as_int64;
        double as_double;
        const char* as_string;
        struct {
            intptr_t length;
            Dart_CObject** values;
        } as_array;
        struct {
            Dart_TypedData_Type type;
            intptr_t length;
            const uint8_t* values;
        } as_typed_data;
    } value;
};

using DartPostCObjectFn = bool (*)(Dart_Port port_id, Dart_CObject* message);

using LlmStreamCallback = void (*)(const uint8_t*, size_t, void*);
using VlmStreamCallback = rac_bool_t (*)(const uint8_t*, size_t, void*);
using SttStreamCallback = void (*)(const uint8_t*, size_t, void*);
using TtsStreamCallback = void (*)(const uint8_t*, size_t, void*);
using VoiceAgentCallback = void (*)(const uint8_t*, size_t, void*);

struct NativePortContext {
    Dart_Port port = 0;
    DartPostCObjectFn post = nullptr;
    std::atomic<bool> post_failed{false};
};

template <typename Context>
void post_int32(Context* context, int32_t value) {
    if (!context || !context->post || context->port == 0) {
        return;
    }

    Dart_CObject message;
    message.type = Dart_CObject_kInt32;
    message.value.as_int32 = value;
    if (!context->post(context->port, &message)) {
        context->post_failed.store(true, std::memory_order_relaxed);
    }
}

bool post_typed_data(NativePortContext* context, const uint8_t* event_bytes, size_t event_size) {
    if (!context || !context->post || context->port == 0 || !event_bytes || event_size == 0) {
        return true;
    }

    // Dart_PostCObject copies kTypedData before returning. Keep this vector
    // alive until the post call completes; commons may reuse event_bytes as
    // soon as this callback returns.
    std::vector<uint8_t> owned(event_bytes, event_bytes + event_size);

    Dart_CObject message;
    message.type = Dart_CObject_kTypedData;
    message.value.as_typed_data.type = Dart_TypedData_kUint8;
    message.value.as_typed_data.length = static_cast<intptr_t>(owned.size());
    message.value.as_typed_data.values = owned.data();

    if (!context->post(context->port, &message)) {
        context->post_failed.store(true, std::memory_order_relaxed);
        return false;
    }
    return true;
}

void void_stream_callback(const uint8_t* event_bytes, size_t event_size, void* user_data) {
    (void)post_typed_data(static_cast<NativePortContext*>(user_data), event_bytes, event_size);
}

rac_bool_t bool_stream_callback(const uint8_t* event_bytes, size_t event_size, void* user_data) {
    return post_typed_data(static_cast<NativePortContext*>(user_data), event_bytes, event_size)
               ? RAC_TRUE
               : RAC_FALSE;
}

std::mutex& stt_contexts_mu() {
    static std::mutex mu;
    return mu;
}

std::unordered_map<rac_handle_t, std::unique_ptr<NativePortContext>>& stt_contexts() {
    static std::unordered_map<rac_handle_t, std::unique_ptr<NativePortContext>> map;
    return map;
}

void erase_stt_context(rac_handle_t handle) {
    std::lock_guard<std::mutex> lock(stt_contexts_mu());
    stt_contexts().erase(handle);
}

std::mutex& voice_contexts_mu() {
    static std::mutex mu;
    return mu;
}

std::unordered_map<rac_voice_agent_handle_t, std::unique_ptr<NativePortContext>>&
voice_contexts() {
    static std::unordered_map<rac_voice_agent_handle_t, std::unique_ptr<NativePortContext>> map;
    return map;
}

void erase_voice_context(rac_voice_agent_handle_t handle) {
    std::lock_guard<std::mutex> lock(voice_contexts_mu());
    voice_contexts().erase(handle);
}

}  // namespace

extern "C" {

rac_result_t rac_llm_generate_stream_proto(const uint8_t* request_proto_bytes,
                                           size_t request_proto_size,
                                           LlmStreamCallback callback,
                                           void* user_data);
void rac_llm_proto_quiesce(void);

rac_result_t rac_vlm_stream_proto(const uint8_t* request_proto_bytes,
                                  size_t request_proto_size,
                                  VlmStreamCallback callback,
                                  void* user_data);
void rac_vlm_proto_quiesce(void);

rac_result_t rac_tts_synthesize_stream_lifecycle_proto(const uint8_t* request_proto_bytes,
                                                       size_t request_proto_size,
                                                       TtsStreamCallback callback,
                                                       void* user_data);
void rac_tts_proto_quiesce(void);

rac_result_t rac_stt_set_stream_proto_callback(rac_handle_t handle,
                                               SttStreamCallback callback,
                                               void* user_data);
rac_result_t rac_stt_unset_stream_proto_callback(rac_handle_t handle);
void rac_stt_proto_quiesce(void);

rac_result_t rac_voice_agent_process_turn_proto(rac_voice_agent_handle_t handle,
                                                const uint8_t* request_bytes,
                                                size_t request_size,
                                                VoiceAgentCallback callback,
                                                void* user_data);
rac_result_t rac_voice_agent_set_proto_callback(rac_voice_agent_handle_t handle,
                                                VoiceAgentCallback callback,
                                                void* user_data);
void rac_voice_agent_proto_quiesce(void);

__attribute__((visibility("default"))) int32_t ra_flutter_llm_generate_stream_proto_native_port(
    const uint8_t* request_proto_bytes,
    size_t request_proto_size,
    Dart_Port port,
    DartPostCObjectFn post_cobject) {
    if (!request_proto_bytes || request_proto_size == 0 || port == 0 || !post_cobject) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    NativePortContext context;
    context.port = port;
    context.post = post_cobject;

    const rac_result_t rc = rac_llm_generate_stream_proto(
        request_proto_bytes, request_proto_size, void_stream_callback, &context);
    rac_llm_proto_quiesce();
    post_int32(&context, rc);
    return rc;
}

__attribute__((visibility("default"))) int32_t ra_flutter_vlm_stream_proto_native_port(
    const uint8_t* request_proto_bytes,
    size_t request_proto_size,
    Dart_Port port,
    DartPostCObjectFn post_cobject) {
    if (!request_proto_bytes || request_proto_size == 0 || port == 0 || !post_cobject) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    NativePortContext context;
    context.port = port;
    context.post = post_cobject;

    const rac_result_t rc = rac_vlm_stream_proto(
        request_proto_bytes, request_proto_size, bool_stream_callback, &context);
    rac_vlm_proto_quiesce();
    post_int32(&context, rc);
    return rc;
}

__attribute__((visibility("default"))) int32_t
ra_flutter_tts_synthesize_stream_lifecycle_proto_native_port(
    const uint8_t* request_proto_bytes,
    size_t request_proto_size,
    Dart_Port port,
    DartPostCObjectFn post_cobject) {
    if (!request_proto_bytes || request_proto_size == 0 || port == 0 || !post_cobject) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    NativePortContext context;
    context.port = port;
    context.post = post_cobject;

    const rac_result_t rc = rac_tts_synthesize_stream_lifecycle_proto(
        request_proto_bytes, request_proto_size, void_stream_callback, &context);
    rac_tts_proto_quiesce();
    post_int32(&context, rc);
    return rc;
}

__attribute__((visibility("default"))) int32_t
ra_flutter_stt_unset_stream_proto_native_port(rac_handle_t handle) {
    if (!handle) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    const rac_result_t rc = rac_stt_unset_stream_proto_callback(handle);
    rac_stt_proto_quiesce();
    erase_stt_context(handle);
    return rc;
}

__attribute__((visibility("default"))) int32_t ra_flutter_stt_set_stream_proto_native_port(
    rac_handle_t handle,
    Dart_Port port,
    DartPostCObjectFn post_cobject) {
    if (!handle || port == 0 || !post_cobject) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    (void)ra_flutter_stt_unset_stream_proto_native_port(handle);

    auto context = std::make_unique<NativePortContext>();
    context->port = port;
    context->post = post_cobject;
    auto* raw_context = context.get();

    const rac_result_t rc =
        rac_stt_set_stream_proto_callback(handle, void_stream_callback, raw_context);
    if (rc != RAC_SUCCESS) {
        return rc;
    }

    {
        std::lock_guard<std::mutex> lock(stt_contexts_mu());
        stt_contexts()[handle] = std::move(context);
    }
    return rc;
}

__attribute__((visibility("default"))) int32_t
ra_flutter_voice_agent_process_turn_proto_native_port(rac_voice_agent_handle_t handle,
                                                      const uint8_t* request_proto_bytes,
                                                      size_t request_proto_size,
                                                      Dart_Port port,
                                                      DartPostCObjectFn post_cobject) {
    if (!handle || !request_proto_bytes || request_proto_size == 0 || port == 0 ||
        !post_cobject) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    NativePortContext context;
    context.port = port;
    context.post = post_cobject;

    const rac_result_t rc = rac_voice_agent_process_turn_proto(
        handle, request_proto_bytes, request_proto_size, void_stream_callback, &context);
    rac_voice_agent_proto_quiesce();
    post_int32(&context, rc);
    return rc;
}

__attribute__((visibility("default"))) int32_t
ra_flutter_voice_agent_unset_proto_callback_native_port(rac_voice_agent_handle_t handle) {
    if (!handle) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    const rac_result_t rc = rac_voice_agent_set_proto_callback(handle, nullptr, nullptr);
    rac_voice_agent_proto_quiesce();
    erase_voice_context(handle);
    return rc;
}

__attribute__((visibility("default"))) int32_t
ra_flutter_voice_agent_set_proto_callback_native_port(rac_voice_agent_handle_t handle,
                                                      Dart_Port port,
                                                      DartPostCObjectFn post_cobject) {
    if (!handle || port == 0 || !post_cobject) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    (void)ra_flutter_voice_agent_unset_proto_callback_native_port(handle);

    auto context = std::make_unique<NativePortContext>();
    context->port = port;
    context->post = post_cobject;
    auto* raw_context = context.get();

    const rac_result_t rc =
        rac_voice_agent_set_proto_callback(handle, void_stream_callback, raw_context);
    if (rc != RAC_SUCCESS) {
        return rc;
    }

    {
        std::lock_guard<std::mutex> lock(voice_contexts_mu());
        voice_contexts()[handle] = std::move(context);
    }
    return rc;
}

}  // extern "C"
