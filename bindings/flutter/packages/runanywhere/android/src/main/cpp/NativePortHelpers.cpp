// SPDX-License-Identifier: Apache-2.0
//
// Android Flutter native-port helpers for proto stream callbacks.
//
// Commons callback bytes are borrowed for the duration of the native callback
// only. These helpers copy bytes synchronously inside that callback and post
// owned typed-data messages to Dart ReceivePorts. The Dart bridges prefer these
// helpers over NativeCallable.isolateLocal when present, matching the iOS
// helpers in packages/runanywhere/ios/Classes/*NativePort.mm.

#include <jni.h>

#include <atomic>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <limits>
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
constexpr rac_result_t RAC_ERROR_FILE_NOT_FOUND = -183;
constexpr rac_result_t RAC_ERROR_INVALID_ARGUMENT = -259;
constexpr rac_result_t RAC_ERROR_BUFFER_TOO_SMALL = -261;
constexpr rac_result_t RAC_ERROR_SECURE_STORAGE_FAILED = -333;
constexpr rac_bool_t RAC_TRUE = 1;
constexpr rac_bool_t RAC_FALSE = 0;

JavaVM* g_java_vm = nullptr;
jclass g_secure_storage_class = nullptr;
jmethodID g_secure_storage_set = nullptr;
jmethodID g_secure_storage_get = nullptr;
jmethodID g_secure_storage_delete = nullptr;

class ScopedJniEnv {
   public:
    ScopedJniEnv() {
        if (!g_java_vm) {
            return;
        }
        const jint status = g_java_vm->GetEnv(reinterpret_cast<void**>(&env_), JNI_VERSION_1_6);
        if (status == JNI_EDETACHED && g_java_vm->AttachCurrentThread(&env_, nullptr) == JNI_OK) {
            attached_ = true;
        } else if (status != JNI_OK) {
            env_ = nullptr;
        }
    }

    ~ScopedJniEnv() {
        if (attached_) {
            g_java_vm->DetachCurrentThread();
        }
    }

    JNIEnv* get() const { return env_; }

   private:
    JNIEnv* env_ = nullptr;
    bool attached_ = false;
};

bool clear_jni_exception(JNIEnv* env) {
    if (!env || !env->ExceptionCheck()) {
        return false;
    }
    env->ExceptionClear();
    return true;
}

bool secure_storage_jni_ready() {
    return g_secure_storage_class && g_secure_storage_set && g_secure_storage_get &&
           g_secure_storage_delete;
}

jbyteArray new_utf8_bytes(JNIEnv* env, const char* value) {
    if (!env || !value) {
        return nullptr;
    }
    const size_t size = std::strlen(value);
    if (size > static_cast<size_t>(std::numeric_limits<jsize>::max())) {
        return nullptr;
    }
    jbyteArray bytes = env->NewByteArray(static_cast<jsize>(size));
    if (!bytes || clear_jni_exception(env)) {
        return nullptr;
    }
    if (size > 0) {
        env->SetByteArrayRegion(bytes, 0, static_cast<jsize>(size),
                                reinterpret_cast<const jbyte*>(value));
        if (clear_jni_exception(env)) {
            env->DeleteLocalRef(bytes);
            return nullptr;
        }
    }
    return bytes;
}

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

JNIEXPORT jint JNICALL JNI_OnLoad(JavaVM* vm, void*) {
    if (!vm) {
        return JNI_ERR;
    }

    JNIEnv* env = nullptr;
    if (vm->GetEnv(reinterpret_cast<void**>(&env), JNI_VERSION_1_6) != JNI_OK || !env) {
        return JNI_ERR;
    }

    jclass local_class = env->FindClass("ai/runanywhere/sdk/FlutterSecureStorageBridge");
    if (!local_class || clear_jni_exception(env)) {
        return JNI_ERR;
    }

    g_secure_storage_class = static_cast<jclass>(env->NewGlobalRef(local_class));
    env->DeleteLocalRef(local_class);
    if (!g_secure_storage_class) {
        clear_jni_exception(env);
        return JNI_ERR;
    }

    g_secure_storage_set =
        env->GetStaticMethodID(g_secure_storage_class, "set", "([B[B)Z");
    g_secure_storage_get =
        env->GetStaticMethodID(g_secure_storage_class, "get", "([B)[B");
    g_secure_storage_delete =
        env->GetStaticMethodID(g_secure_storage_class, "delete", "([B)Z");
    if (clear_jni_exception(env) || !secure_storage_jni_ready()) {
        env->DeleteGlobalRef(g_secure_storage_class);
        g_secure_storage_class = nullptr;
        g_secure_storage_set = nullptr;
        g_secure_storage_get = nullptr;
        g_secure_storage_delete = nullptr;
        return JNI_ERR;
    }

    g_java_vm = vm;
    return JNI_VERSION_1_6;
}

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

// RAG streaming query — bool-returning control callback (RAC_FALSE stops
// generation early). Runs synchronously: all RAGStreamEvents fire before the
// call returns, so no quiesce is needed.
rac_result_t rac_rag_query_stream_proto(rac_handle_t session,
                                        const uint8_t* query_proto_bytes,
                                        size_t query_proto_size,
                                        VlmStreamCallback callback,
                                        void* user_data);

__attribute__((visibility("default"))) int32_t ra_flutter_secure_storage_store(const char* key,
                                                                               const char* value) {
    if (!key || !value) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    ScopedJniEnv scoped_env;
    JNIEnv* env = scoped_env.get();
    if (!env || !secure_storage_jni_ready()) {
        return RAC_ERROR_SECURE_STORAGE_FAILED;
    }

    jbyteArray java_key = new_utf8_bytes(env, key);
    jbyteArray java_value = new_utf8_bytes(env, value);
    if (!java_key || !java_value || clear_jni_exception(env)) {
        if (java_key) env->DeleteLocalRef(java_key);
        if (java_value) env->DeleteLocalRef(java_value);
        return RAC_ERROR_SECURE_STORAGE_FAILED;
    }

    const jboolean stored = env->CallStaticBooleanMethod(
        g_secure_storage_class, g_secure_storage_set, java_key, java_value);
    const bool failed = clear_jni_exception(env);
    env->DeleteLocalRef(java_value);
    env->DeleteLocalRef(java_key);
    return !failed && stored == JNI_TRUE ? RAC_SUCCESS : RAC_ERROR_SECURE_STORAGE_FAILED;
}

__attribute__((visibility("default"))) int32_t
ra_flutter_secure_storage_retrieve(const char* key, char* out_value, size_t buffer_size) {
    if (!key || !out_value || buffer_size == 0) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    out_value[0] = '\0';

    ScopedJniEnv scoped_env;
    JNIEnv* env = scoped_env.get();
    if (!env || !secure_storage_jni_ready()) {
        return RAC_ERROR_SECURE_STORAGE_FAILED;
    }

    jbyteArray java_key = new_utf8_bytes(env, key);
    if (!java_key || clear_jni_exception(env)) {
        if (java_key) env->DeleteLocalRef(java_key);
        return RAC_ERROR_SECURE_STORAGE_FAILED;
    }
    auto* java_value = static_cast<jbyteArray>(
        env->CallStaticObjectMethod(g_secure_storage_class, g_secure_storage_get, java_key));
    env->DeleteLocalRef(java_key);
    if (clear_jni_exception(env)) {
        return RAC_ERROR_SECURE_STORAGE_FAILED;
    }
    if (!java_value) {
        return RAC_ERROR_FILE_NOT_FOUND;
    }

    const jsize java_value_size = env->GetArrayLength(java_value);
    if (clear_jni_exception(env) || java_value_size < 0) {
        env->DeleteLocalRef(java_value);
        return RAC_ERROR_SECURE_STORAGE_FAILED;
    }
    const size_t value_size = static_cast<size_t>(java_value_size);
    if (value_size + 1 > buffer_size) {
        env->DeleteLocalRef(java_value);
        return RAC_ERROR_BUFFER_TOO_SMALL;
    }

    if (value_size > 0) {
        env->GetByteArrayRegion(java_value, 0, java_value_size,
                                reinterpret_cast<jbyte*>(out_value));
        if (clear_jni_exception(env)) {
            env->DeleteLocalRef(java_value);
            return RAC_ERROR_SECURE_STORAGE_FAILED;
        }
    }
    out_value[value_size] = '\0';
    env->DeleteLocalRef(java_value);
    return value_size == 0 ? RAC_ERROR_SECURE_STORAGE_FAILED
                           : static_cast<int32_t>(value_size);
}

__attribute__((visibility("default"))) int32_t ra_flutter_secure_storage_delete(const char* key) {
    if (!key) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    ScopedJniEnv scoped_env;
    JNIEnv* env = scoped_env.get();
    if (!env || !secure_storage_jni_ready()) {
        return RAC_ERROR_SECURE_STORAGE_FAILED;
    }

    jbyteArray java_key = new_utf8_bytes(env, key);
    if (!java_key || clear_jni_exception(env)) {
        if (java_key) env->DeleteLocalRef(java_key);
        return RAC_ERROR_SECURE_STORAGE_FAILED;
    }
    const jboolean deleted =
        env->CallStaticBooleanMethod(g_secure_storage_class, g_secure_storage_delete, java_key);
    const bool failed = clear_jni_exception(env);
    env->DeleteLocalRef(java_key);
    return !failed && deleted == JNI_TRUE ? RAC_SUCCESS : RAC_ERROR_SECURE_STORAGE_FAILED;
}

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
ra_flutter_rag_query_stream_proto_native_port(rac_handle_t session,
                                              const uint8_t* query_proto_bytes,
                                              size_t query_proto_size,
                                              Dart_Port port,
                                              DartPostCObjectFn post_cobject) {
    if (!session || !query_proto_bytes || query_proto_size == 0 || port == 0 ||
        !post_cobject) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    NativePortContext context;
    context.port = port;
    context.post = post_cobject;

    // bool_stream_callback returns RAC_FALSE if a post fails, which stops the
    // native generation loop (backpressure).
    const rac_result_t rc = rac_rag_query_stream_proto(
        session, query_proto_bytes, query_proto_size, bool_stream_callback, &context);
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
