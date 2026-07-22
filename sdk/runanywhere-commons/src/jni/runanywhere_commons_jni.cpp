/**
 * RunAnywhere Commons JNI Bridge
 *
 * JNI layer that wraps the runanywhere-commons C API (rac_*.h) for Android/JVM.
 * This provides a thin wrapper that exposes all rac_* C API functions via JNI.
 *
 * Package: com.runanywhere.sdk.native.bridge
 * Class: RunAnywhereBridge
 *
 * Design principles:
 * 1. Thin wrapper - minimal logic, just data conversion
 * 2. Direct mapping to C API functions
 * 3. Consistent error handling
 * 4. Memory safety with proper cleanup
 *
 * V2 bridge classification:
 *   - Proto-byte JNI thunks (`rac*Proto` family, e.g.
 *     racLlmGenerateProto, racSttComponentTranscribeProto,
 *     racModelLifecycle*Proto, racDownload*Proto, racStorage*Proto,
 *     racHardwareProfileGet, racVoiceAgent*Proto, racRag*Proto, etc.)
 *     are SDK-facing pass-through. They take/return jbyteArray and call
 *     the matching `rac_*_proto` C ABI through callProtoBufferFn or a
 *     domain-specific `make*ProtoCallResult` helper. Keep them thin.
 *   - Legacy non-proto component JSON thunks (racLlmComponentGenerate*,
 *     racSttComponent{Transcribe,...}, racVlmComponentProcess*,
 *     racVadComponentGetStatistics, racLoraRegistry*, racHardwareGet*,
 *     racStructuredOutputExtractJson, etc.) were deleted
 *     once every Kotlin call site migrated to the `*Proto`
 *     sibling. New non-proto thunks are not accepted.
 *   - Platform adapter callbacks (file manager, archive extraction,
 *     OkHttp transport, secure storage, telemetry batches, model
 *     assignment HTTP) are classified `internal`. They are not SDK
 *     public APIs and stay shaped for the platform contract they
 *     implement.
 */

#include <jni.h>

#include <algorithm>
#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cstring>
#ifndef _WIN32
#include <dlfcn.h>
#endif
#include <exception>
#include <limits>
#include <mutex>
#include <new>
#include <nlohmann/json.hpp>
#include <string>
#include <unordered_map>
#include <vector>

#ifdef __ANDROID__
#include <android/log.h>
#endif

// Include runanywhere-commons C API headers
#include "request_cancellation_relay.h"

#include "../features/vlm/rac_vlm_lifecycle_bridge.h"
#include "../infrastructure/http/rac_http_internal.h"
#include "rac/core/rac_audio_utils.h"
#include "rac/core/rac_core.h"
#include "rac/core/rac_error.h"
#include "rac/core/rac_error_proto.h"
#include "rac/core/rac_logger.h"
#include "rac/core/rac_model_lifecycle.h"
#include "rac/core/rac_platform_adapter.h"
#include "rac/features/diffusion/rac_diffusion_service.h"
#include "rac/features/embeddings/rac_embeddings_service.h"
#include "rac/features/llm/rac_llm_component.h"
#include "rac/features/llm/rac_llm_service.h"
#include "rac/features/llm/rac_tool_calling.h"
#include "rac/features/lora/rac_lora_service.h"
#include "rac/features/diarization/rac_diarization.h"
#include "rac/features/rerank/rac_rerank.h"
#include "rac/features/platform/rac_llm_platform.h"
#include "rac/features/platform/rac_tts_platform.h"
#include "rac/features/segmentation/rac_segmentation_service.h"
#include "rac/features/stt/rac_stt_component.h"
#include "rac/features/stt/rac_stt_service.h"
#include "rac/features/stt/rac_stt_stream.h"
#include "rac/features/tts/rac_tts_component.h"
#include "rac/features/tts/rac_tts_service.h"
#include "rac/features/vad/rac_vad_component.h"
#include "rac/features/vad/rac_vad_service.h"
#include "rac/features/vlm/rac_vlm_component.h"
#include "rac/features/vlm/rac_vlm_service.h"
#include "rac/features/voice_agent/rac_voice_agent.h"
#include "rac/features/voice_agent/rac_voice_event_abi.h"
#include "rac/foundation/rac_proto_buffer.h"
#include "rac/infrastructure/device/rac_device_manager.h"
#include "rac/infrastructure/download/rac_download_orchestrator.h"
#include "rac/infrastructure/file_management/rac_file_manager.h"
#include "rac/infrastructure/http/rac_http_client.h"
#include "rac/infrastructure/model_management/rac_lora_registry.h"
#include "rac/infrastructure/model_management/rac_model_assignment.h"
#include "rac/infrastructure/model_management/rac_model_compatibility.h"
#include "rac/infrastructure/model_management/rac_model_paths.h"
#include "rac/infrastructure/model_management/rac_model_registry.h"
#include "rac/infrastructure/model_management/rac_model_types.h"
#include "rac/solutions/rac_solution.h"
// Proto-byte LLM stream ABI for Kotlin's LLMStreamAdapter.
#include "rac/features/llm/rac_llm_stream.h"
// Proto-byte VAD stream ABI for Kotlin's streamVAD Flow.
#include "rac/features/vad/rac_vad_stream.h"
// Hardware ABI, structured output, VAD statistics.
#include "rac/core/rac_sdk_state.h"
#include "rac/features/llm/rac_llm_schema_to_json.h"
#include "rac/features/llm/rac_llm_structured_output.h"
#include "rac/infrastructure/device/rac_device_identity.h"
#include "rac/infrastructure/events/rac_sdk_emit.h"
#include "rac/infrastructure/events/rac_sdk_event_stream.h"
#include "rac/infrastructure/network/rac_api_types.h"
#include "rac/infrastructure/network/rac_auth_manager.h"
#include "rac/infrastructure/network/rac_dev_config.h"
#include "rac/infrastructure/network/rac_endpoints.h"
#include "rac/infrastructure/network/rac_environment.h"
#include "rac/infrastructure/storage/rac_storage_analyzer.h"
#include "rac/infrastructure/telemetry/rac_telemetry_manager.h"
#include "rac/infrastructure/telemetry/rac_telemetry_types.h"
#include "rac/lifecycle/rac_sdk_init.h"
#include "rac/plugin/rac_plugin_entry.h"
#include "rac/plugin/rac_plugin_loader.h"
#include "rac/router/rac_router_capabilities.h"

// NOTE: Backend headers are NOT included here.
// Backend registration is handled by their respective JNI libraries:
//   - backends/llamacpp/src/jni/rac_backend_llamacpp_jni.cpp
//   - backends/onnx/src/jni/rac_backend_onnx_jni.cpp
extern "C" const rac_engine_vtable_t* rac_plugin_entry_platform(void);

// Route JNI logging through unified RAC_LOG_* system
static const char* JNI_LOG_TAG = "JNI.Commons";
#define LOGi(...) RAC_LOG_INFO(JNI_LOG_TAG, __VA_ARGS__)
#define LOGe(...) RAC_LOG_ERROR(JNI_LOG_TAG, __VA_ARGS__)
#define LOGw(...) RAC_LOG_WARNING(JNI_LOG_TAG, __VA_ARGS__)
#define LOGd(...) RAC_LOG_DEBUG(JNI_LOG_TAG, __VA_ARGS__)

// =============================================================================
// JNI AttachCurrentThread signature shim
// =============================================================================
// The `AttachCurrentThread` parameter type differs between JVM headers:
//   - Android NDK jni.h (r27+):  AttachCurrentThread(JNIEnv**, void*)
//   - Oracle / Temurin  jni.h:   AttachCurrentThread(void**,   void*)
// NDK r27 tightened parameter-type checking, so the previous
// `reinterpret_cast<void**>(&env)` no longer compiles on Android. Pick
// the right cast per platform. `GetEnv` still takes `void**` on both
// platforms and does not need this shim.
#ifdef __ANDROID__
#define RAC_JNI_ATTACH_ENVPP(envpp) (envpp)
#else
#define RAC_JNI_ATTACH_ENVPP(envpp) (reinterpret_cast<void**>(envpp))
#endif

// =============================================================================
// Global State for Platform Adapter JNI Callbacks
// =============================================================================

static JavaVM* g_jvm = nullptr;
static jobject g_platform_adapter = nullptr;
// commons-155: recursive so jni_*_callback can lock around g_platform_adapter
// reads even when the writer (racSetPlatformAdapter) emits log lines while
// already holding the lock — `LOGw(...)` in the writer routes through
// jni_log_callback which now also takes this mutex.
static std::recursive_mutex g_adapter_mutex;

// Kotlin's VLM and RAG APIs wrap synchronous JNI inference in cancellable
// coroutines. These relays close the instruction window between the Kotlin
// lease becoming RUNNING and the backend publishing its own active request.
// Existing JNI/C ABI entry points remain unchanged; only the Kotlin-private
// request-scoped JNI siblings below use this state.
static rac::jni::RequestCancellationRelay g_vlm_request_relay;
static rac::jni::RequestCancellationRelay g_rag_request_relay;

// Method IDs for platform adapter callbacks (cached)
static jmethodID g_method_log = nullptr;
static jmethodID g_method_file_exists = nullptr;
static jmethodID g_method_file_read = nullptr;
static jmethodID g_method_file_write = nullptr;
static jmethodID g_method_file_delete = nullptr;
static jmethodID g_method_secure_get = nullptr;
static jmethodID g_method_secure_set = nullptr;
static jmethodID g_method_secure_delete = nullptr;
static jmethodID g_method_now_ms = nullptr;
// Directory enumeration slots populated by Kotlin adapter so the
// model-registry refresh path (rescan_local) and rac_model_info_make_proto's
// is_downloaded probe for multi-file artifacts work on Android the same way
// they do on Web. See rac_platform_adapter.h for the cross-SDK contract.
static jmethodID g_method_file_list_directory = nullptr;
static jmethodID g_method_is_non_empty_directory = nullptr;

// =============================================================================
// JNI OnLoad/OnUnload
// =============================================================================

// NOLINTNEXTLINE(misc-unused-parameters): `reserved` is part of the JNI ABI.
JNIEXPORT jint JNI_OnLoad(JavaVM* vm, void* reserved) {
    LOGi("JNI_OnLoad: runanywhere_commons_jni loaded");
    g_jvm = vm;
    return JNI_VERSION_1_6;
}

// Forward declarations of the per-listener-map cleanup helpers defined further
// down the file. JNI_OnUnload calls them so every GlobalRef cached by this TU
// is released when the JVM unloads the native library (commons-154).
namespace {
void rac_jni_release_all_listener_global_refs(JNIEnv* env);
// commons-057: release the single per-handle GlobalRef this TU caches for an
// LLM / VAD handle. racLlm/VadComponentDestroy call these so a
// load->stream->destroy cycle that never hits the explicit unset-callback path
// does not leak one GlobalRef per cycle (which eventually overflows the JVM
// global reference table). Defined near the listener maps at the bottom of the
// TU where the maps are in scope.
void rac_jni_erase_llm_stream_listener(JNIEnv* env, uintptr_t handle_key);
void rac_jni_erase_vad_listeners(JNIEnv* env, uintptr_t handle_key);
}  // namespace

// NOLINTNEXTLINE(misc-unused-parameters): `vm`/`reserved` are part of the JNI ABI.
JNIEXPORT void JNI_OnUnload(JavaVM* vm, void* reserved) {
    LOGi("JNI_OnUnload: runanywhere_commons_jni unloading");

    JNIEnv* env = nullptr;
    if (vm->GetEnv(reinterpret_cast<void**>(&env), JNI_VERSION_1_6) != JNI_OK) {
        env = nullptr;
    }

    // commons-154: drain every per-handle / per-subscription GlobalRef map so
    // GlobalRefs are not leaked when the JVM unloads the native library.
    // Mirrors the g_platform_adapter cleanup below.
    if (env != nullptr) {
        rac_jni_release_all_listener_global_refs(env);
    }

    {
        std::lock_guard<std::recursive_mutex> lock(g_adapter_mutex);
        if (g_platform_adapter != nullptr) {
            if (env != nullptr) {
                env->DeleteGlobalRef(g_platform_adapter);
            }
            g_platform_adapter = nullptr;
        }
    }
    g_jvm = nullptr;
}

// =============================================================================
// Helper Functions
// =============================================================================

// Helpers below share the same JNI patterns documented at the extern "C"
// block lower in this file: jboolean -> bool implicit conversion when
// checking JNI status flags, and jlong <-> opaque pointer round-trips.
// NOLINTBEGIN(readability-implicit-bool-conversion,performance-no-int-to-ptr)
static JNIEnv* getJNIEnv() {
    if (g_jvm == nullptr)
        return nullptr;

    JNIEnv* env = nullptr;
    int status = g_jvm->GetEnv(reinterpret_cast<void**>(&env), JNI_VERSION_1_6);

    if (status == JNI_EDETACHED) {
        // Use RAC_JNI_ATTACH_ENVPP to bridge the Android NDK vs Oracle/Temurin
        // parameter-type difference (see shim definition near the top of
        // this file). NDK r27 no longer tolerates the prior `void**` cast.
        if (g_jvm->AttachCurrentThread(RAC_JNI_ATTACH_ENVPP(&env), nullptr) != JNI_OK) {
            return nullptr;
        }
    }
    return env;
}

// commons-056: noexcept by construction — the only throwing call below is the
// `std::string` ctor which can raise std::bad_alloc on memory-constrained
// devices. Letting it escape across the JNI vtable boundary is UB per JNI
// §13.1; we catch and return an empty string instead. Callers that need to
// distinguish "empty input" from "OOM" must check for the input being null
// before calling.
static std::string getCString(JNIEnv* env, jstring str) noexcept {
    if (str == nullptr)
        return std::string();
    const char* chars = env->GetStringUTFChars(str, nullptr);
    if (chars == nullptr)
        return std::string();
    try {
        std::string result(chars);
        env->ReleaseStringUTFChars(str, chars);
        return result;
    } catch (...) {
        env->ReleaseStringUTFChars(str, chars);
        return std::string();
    }
}

static const char* getNullableCString(JNIEnv* env, jstring str, std::string& storage) noexcept {
    if (str == nullptr)
        return nullptr;
    try {
        storage = getCString(env, str);
    } catch (...) {
        storage.clear();
    }
    return storage.c_str();
}

namespace {

constexpr const char* kAndroidSystemTtsBridgeClass =
    "com/runanywhere/sdk/features/TTS/System/AndroidSystemTTSPlatform";

jclass findAndroidSystemTtsBridge(JNIEnv* env) {
    if (env == nullptr) {
        return nullptr;
    }
    jclass clazz = env->FindClass(kAndroidSystemTtsBridgeClass);
    if (env->ExceptionCheck()) {
        env->ExceptionClear();
        return nullptr;
    }
    return clazz;
}

jstring newOptionalString(JNIEnv* env, const char* value) {
    if (env == nullptr || value == nullptr) {
        return nullptr;
    }
    return env->NewStringUTF(value);
}

rac_bool_t jni_platform_tts_can_handle(const char* voice_id, void* /*user_data*/) {
    JNIEnv* env = getJNIEnv();
    jclass clazz = findAndroidSystemTtsBridge(env);
    if (env == nullptr || clazz == nullptr) {
        return RAC_FALSE;
    }
    jmethodID method = env->GetStaticMethodID(clazz, "canHandle", "(Ljava/lang/String;)Z");
    if (method == nullptr || env->ExceptionCheck()) {
        env->ExceptionClear();
        env->DeleteLocalRef(clazz);
        return RAC_FALSE;
    }
    jstring jVoiceId = newOptionalString(env, voice_id);
    jboolean result = env->CallStaticBooleanMethod(clazz, method, jVoiceId);
    if (env->ExceptionCheck()) {
        env->ExceptionClear();
        result = JNI_FALSE;
    }
    if (jVoiceId != nullptr) {
        env->DeleteLocalRef(jVoiceId);
    }
    env->DeleteLocalRef(clazz);
    return result == JNI_TRUE ? RAC_TRUE : RAC_FALSE;
}

rac_handle_t jni_platform_tts_create(const rac_tts_platform_config_t* config, void* /*user_data*/) {
    JNIEnv* env = getJNIEnv();
    jclass clazz = findAndroidSystemTtsBridge(env);
    if (env == nullptr || clazz == nullptr) {
        return nullptr;
    }
    jmethodID method =
        env->GetStaticMethodID(clazz, "create", "(Ljava/lang/String;Ljava/lang/String;)J");
    if (method == nullptr || env->ExceptionCheck()) {
        env->ExceptionClear();
        env->DeleteLocalRef(clazz);
        return nullptr;
    }
    jstring jVoiceId = newOptionalString(env, config != nullptr ? config->voice_id : nullptr);
    jstring jLanguage = newOptionalString(env, config != nullptr ? config->language : nullptr);
    jlong handle = env->CallStaticLongMethod(clazz, method, jVoiceId, jLanguage);
    if (env->ExceptionCheck()) {
        env->ExceptionClear();
        handle = 0;
    }
    if (jVoiceId != nullptr) {
        env->DeleteLocalRef(jVoiceId);
    }
    if (jLanguage != nullptr) {
        env->DeleteLocalRef(jLanguage);
    }
    env->DeleteLocalRef(clazz);
    if (handle <= 0) {
        return nullptr;
    }
    return reinterpret_cast<rac_handle_t>(static_cast<intptr_t>(handle));
}

rac_result_t jni_platform_tts_synthesize(rac_handle_t handle, const char* text,
                                         const rac_tts_platform_options_t* options,
                                         void* /*user_data*/) {
    if (handle == nullptr || text == nullptr) {
        return RAC_ERROR_INVALID_PARAMETER;
    }
    JNIEnv* env = getJNIEnv();
    jclass clazz = findAndroidSystemTtsBridge(env);
    if (env == nullptr || clazz == nullptr) {
        return RAC_ERROR_INTERNAL;
    }
    jmethodID method =
        env->GetStaticMethodID(clazz, "synthesize", "(JLjava/lang/String;FFFLjava/lang/String;)I");
    if (method == nullptr || env->ExceptionCheck()) {
        env->ExceptionClear();
        env->DeleteLocalRef(clazz);
        return RAC_ERROR_INTERNAL;
    }
    jstring jText = newOptionalString(env, text);
    jstring jVoiceId = newOptionalString(env, options != nullptr ? options->voice_id : nullptr);
    const float rate = options != nullptr ? options->rate : 1.0f;
    const float pitch = options != nullptr ? options->pitch : 1.0f;
    const float volume = options != nullptr ? options->volume : 1.0f;
    jint result = env->CallStaticIntMethod(
        clazz, method, static_cast<jlong>(reinterpret_cast<intptr_t>(handle)), jText,
        static_cast<jfloat>(rate), static_cast<jfloat>(pitch), static_cast<jfloat>(volume),
        jVoiceId);
    if (env->ExceptionCheck()) {
        env->ExceptionClear();
        result = RAC_ERROR_INTERNAL;
    }
    if (jText != nullptr) {
        env->DeleteLocalRef(jText);
    }
    if (jVoiceId != nullptr) {
        env->DeleteLocalRef(jVoiceId);
    }
    env->DeleteLocalRef(clazz);
    return static_cast<rac_result_t>(result);
}

void jni_platform_tts_stop(rac_handle_t handle, void* /*user_data*/) {
    JNIEnv* env = getJNIEnv();
    jclass clazz = findAndroidSystemTtsBridge(env);
    if (env == nullptr || clazz == nullptr) {
        return;
    }
    jmethodID method = env->GetStaticMethodID(clazz, "stop", "(J)V");
    if (method != nullptr && !env->ExceptionCheck()) {
        env->CallStaticVoidMethod(clazz, method,
                                  static_cast<jlong>(reinterpret_cast<intptr_t>(handle)));
    }
    if (env->ExceptionCheck()) {
        env->ExceptionClear();
    }
    env->DeleteLocalRef(clazz);
}

void jni_platform_tts_destroy(rac_handle_t handle, void* /*user_data*/) {
    JNIEnv* env = getJNIEnv();
    jclass clazz = findAndroidSystemTtsBridge(env);
    if (env == nullptr || clazz == nullptr) {
        return;
    }
    jmethodID method = env->GetStaticMethodID(clazz, "destroy", "(J)V");
    if (method != nullptr && !env->ExceptionCheck()) {
        env->CallStaticVoidMethod(clazz, method,
                                  static_cast<jlong>(reinterpret_cast<intptr_t>(handle)));
    }
    if (env->ExceptionCheck()) {
        env->ExceptionClear();
    }
    env->DeleteLocalRef(clazz);
}

}  // namespace

static jbyteArray makeModelRegistryProtoByteArray(JNIEnv* env, uint8_t* bytes, size_t size,
                                                  const char* operation) {
    if (size > 0 && bytes == nullptr) {
        LOGe("%s: native proto payload is null with non-zero size %zu", operation, size);
        return nullptr;
    }

    if (size > static_cast<size_t>(std::numeric_limits<jsize>::max())) {
        LOGe("%s: proto payload too large for JNI byte array: %zu", operation, size);
        rac_model_registry_proto_free(bytes);
        return nullptr;
    }

    jbyteArray result = env->NewByteArray(static_cast<jsize>(size));
    if (result == nullptr) {
        LOGe("%s: failed to allocate JNI byte array of size %zu", operation, size);
        rac_model_registry_proto_free(bytes);
        return nullptr;
    }

    if (size > 0) {
        env->SetByteArrayRegion(result, 0, static_cast<jsize>(size),
                                reinterpret_cast<const jbyte*>(bytes));
    }

    rac_model_registry_proto_free(bytes);
    return env->ExceptionCheck() ? nullptr : result;
}

static void throwNativeProtoFailure(JNIEnv* env, const char* operation, rac_result_t status,
                                    const char* message) {
    if (env == nullptr || env->ExceptionCheck()) {
        return;
    }
    const char* detail =
        (message != nullptr && message[0] != '\0') ? message : "native proto API failed";
    char formatted[512];
    std::snprintf(formatted, sizeof(formatted), "%s failed with code %d: %s", operation, status,
                  detail);
    jclass exClass = env->FindClass("java/lang/IllegalStateException");
    if (exClass != nullptr) {
        env->ThrowNew(exClass, formatted);
        env->DeleteLocalRef(exClass);
    }
}

static jbyteArray makeProtoBufferByteArray(JNIEnv* env, rac_proto_buffer_t* buffer,
                                           const char* operation) {
    if (buffer == nullptr) {
        return nullptr;
    }
    if (RAC_FAILED(buffer->status)) {
        LOGe("%s: native proto API failed with code %d (%s)", operation, buffer->status,
             buffer->error_message ? buffer->error_message : "");
        const rac_result_t status = buffer->status;
        const char* message = buffer->error_message;
        rac_proto_buffer_free(buffer);
        throwNativeProtoFailure(env, operation, status, message);
        return nullptr;
    }
    if (buffer->size > 0 && buffer->data == nullptr) {
        LOGe("%s: native proto payload is null with non-zero size %zu", operation, buffer->size);
        rac_proto_buffer_free(buffer);
        return nullptr;
    }
    if (buffer->size > static_cast<size_t>(std::numeric_limits<jsize>::max())) {
        LOGe("%s: proto payload too large for JNI byte array: %zu", operation, buffer->size);
        rac_proto_buffer_free(buffer);
        return nullptr;
    }

    jbyteArray result = env->NewByteArray(static_cast<jsize>(buffer->size));
    if (result == nullptr) {
        LOGe("%s: failed to allocate JNI byte array of size %zu", operation, buffer->size);
        rac_proto_buffer_free(buffer);
        return nullptr;
    }
    if (buffer->size > 0) {
        env->SetByteArrayRegion(result, 0, static_cast<jsize>(buffer->size),
                                reinterpret_cast<const jbyte*>(buffer->data));
    }
    rac_proto_buffer_free(buffer);
    return env->ExceptionCheck() ? nullptr : result;
}

using ModelRegistryProtoWriteFn = rac_result_t (*)(rac_model_registry_handle_t, const uint8_t*,
                                                   size_t);

static jint callModelRegistryProtoWrite(JNIEnv* env, jbyteArray modelInfoProto,
                                        ModelRegistryProtoWriteFn writeFn, const char* operation) {
    if (!modelInfoProto) {
        return RAC_ERROR_NULL_POINTER;
    }

    rac_model_registry_handle_t registry = rac_get_model_registry();
    if (!registry) {
        LOGe("%s: model registry not initialized", operation);
        return RAC_ERROR_NOT_INITIALIZED;
    }

    const jsize length = env->GetArrayLength(modelInfoProto);
    if (length == 0) {
        return static_cast<jint>(writeFn(registry, nullptr, 0));
    }

    jbyte* bytes = env->GetByteArrayElements(modelInfoProto, nullptr);
    if (bytes == nullptr) {
        LOGe("%s: failed to access JNI byte array", operation);
        return RAC_ERROR_OUT_OF_MEMORY;
    }

    rac_result_t result =
        writeFn(registry, reinterpret_cast<const uint8_t*>(bytes), static_cast<size_t>(length));
    env->ReleaseByteArrayElements(modelInfoProto, bytes, JNI_ABORT);
    return static_cast<jint>(result);
}

using ModelRegistryProtoBufferFn = rac_result_t (*)(rac_model_registry_handle_t, const uint8_t*,
                                                    size_t, rac_proto_buffer_t*);

static jbyteArray callModelRegistryProtoBuffer(JNIEnv* env, jbyteArray requestProto,
                                               ModelRegistryProtoBufferFn callFn,
                                               const char* operation) {
    if (requestProto == nullptr) {
        return nullptr;
    }

    rac_model_registry_handle_t registry = rac_get_model_registry();
    if (!registry) {
        LOGe("%s: model registry not initialized", operation);
        return nullptr;
    }

    const jsize length = env->GetArrayLength(requestProto);
    jbyte* bytes = length > 0 ? env->GetByteArrayElements(requestProto, nullptr) : nullptr;
    if (length > 0 && bytes == nullptr) {
        LOGe("%s: failed to access JNI byte array", operation);
        return nullptr;
    }

    rac_proto_buffer_t result = {};
    rac_proto_buffer_init(&result);
    rac_result_t rc = callFn(registry, reinterpret_cast<const uint8_t*>(bytes),
                             static_cast<size_t>(length), &result);
    if (bytes != nullptr) {
        env->ReleaseByteArrayElements(requestProto, bytes, JNI_ABORT);
    }
    if (RAC_FAILED(rc) && result.status == RAC_SUCCESS) {
        rac_proto_buffer_set_error(&result, rc, operation);
    }
    return makeProtoBufferByteArray(env, &result, operation);
}

using ProtoBufferCallFn = rac_result_t (*)(const uint8_t*, size_t, rac_proto_buffer_t*);

static jbyteArray callProtoBufferFn(JNIEnv* env, jbyteArray requestProto, ProtoBufferCallFn callFn,
                                    const char* operation) {
    if (requestProto == nullptr) {
        return nullptr;
    }

    const jsize length = env->GetArrayLength(requestProto);
    jbyte* bytes = length > 0 ? env->GetByteArrayElements(requestProto, nullptr) : nullptr;
    if (length > 0 && bytes == nullptr) {
        LOGe("%s: failed to access JNI byte array", operation);
        return nullptr;
    }

    rac_proto_buffer_t result = {};
    rac_proto_buffer_init(&result);
    rac_result_t rc =
        callFn(reinterpret_cast<const uint8_t*>(bytes), static_cast<size_t>(length), &result);
    if (bytes != nullptr) {
        env->ReleaseByteArrayElements(requestProto, bytes, JNI_ABORT);
    }
    if (RAC_FAILED(rc) && result.status == RAC_SUCCESS) {
        rac_proto_buffer_set_error(&result, rc, operation);
    }
    return makeProtoBufferByteArray(env, &result, operation);
}

static jbyteArray callLifecycleLoadProtoFn(JNIEnv* env, jbyteArray requestProto) {
    static const char* operation = "racModelLifecycleLoadProto";
    if (requestProto == nullptr) {
        return nullptr;
    }

    rac_model_registry_handle_t registry = rac_get_model_registry();
    if (!registry) {
        LOGe("%s: model registry not initialized", operation);
        return nullptr;
    }

    const jsize length = env->GetArrayLength(requestProto);
    jbyte* bytes = length > 0 ? env->GetByteArrayElements(requestProto, nullptr) : nullptr;
    if (length > 0 && bytes == nullptr) {
        LOGe("%s: failed to access JNI byte array", operation);
        return nullptr;
    }

    rac_proto_buffer_t result = {};
    rac_proto_buffer_init(&result);
    rac_result_t rc = rac_model_lifecycle_load_proto(
        registry, reinterpret_cast<const uint8_t*>(bytes), static_cast<size_t>(length), &result);
    if (bytes != nullptr) {
        env->ReleaseByteArrayElements(requestProto, bytes, JNI_ABORT);
    }
    if (RAC_FAILED(rc) && result.status == RAC_SUCCESS) {
        rac_proto_buffer_set_error(&result, rc, operation);
    }
    return makeProtoBufferByteArray(env, &result, operation);
}

static jboolean invokeProtoListener(JNIEnv* env, jobject listener, const uint8_t* bytes,
                                    size_t size, const char* operation) {
    if (env == nullptr || listener == nullptr) {
        return JNI_FALSE;
    }
    if (size > static_cast<size_t>(std::numeric_limits<jsize>::max())) {
        LOGe("%s: callback payload too large: %zu", operation, size);
        return JNI_FALSE;
    }
    jbyteArray jBytes = env->NewByteArray(static_cast<jsize>(size));
    if (jBytes == nullptr) {
        return JNI_FALSE;
    }
    if (size > 0 && bytes != nullptr) {
        env->SetByteArrayRegion(jBytes, 0, static_cast<jsize>(size),
                                reinterpret_cast<const jbyte*>(bytes));
    }
    jclass cls = env->GetObjectClass(listener);
    jmethodID method = env->GetMethodID(cls, "onProgress", "([B)Z");
    env->DeleteLocalRef(cls);
    if (method == nullptr) {
        env->DeleteLocalRef(jBytes);
        return JNI_FALSE;
    }
    jboolean keepGoing = env->CallBooleanMethod(listener, method, jBytes);
    env->DeleteLocalRef(jBytes);
    return env->ExceptionCheck() ? JNI_FALSE : keepGoing;
}

struct JByteArrayView {
    JNIEnv* env = nullptr;
    jbyteArray array = nullptr;
    jbyte* bytes = nullptr;
    jsize length = 0;
    bool ok = false;

    JByteArrayView(JNIEnv* e, jbyteArray a, bool allowNull = false) : env(e), array(a) {
        if (array == nullptr) {
            ok = allowNull;
            return;
        }
        length = env->GetArrayLength(array);
        bytes = length > 0 ? env->GetByteArrayElements(array, nullptr) : nullptr;
        ok = (length == 0 || bytes != nullptr);
    }

    ~JByteArrayView() {
        if (bytes != nullptr) {
            env->ReleaseByteArrayElements(array, bytes, JNI_ABORT);
        }
    }

    const uint8_t* u8() const { return reinterpret_cast<const uint8_t*>(bytes); }

    const void* data() const { return static_cast<const void*>(bytes); }

    size_t size() const { return static_cast<size_t>(length); }
};

// commons-089: callback user-data for the proto-byte stream thunks.
//
// Lifetime contract: the streaming `rac_*_stream_proto` /
// `rac_*_process_turn_proto` C entry points are SYNCHRONOUS — they run the full
// inference inline and fire `callback` zero or more times BEFORE returning (no
// `src/features` proto path spawns a worker thread). That makes it safe for
// racLlmGenerateStreamProto / racSttTranscribeStreamLifecycleProto /
// racTtsSynthesizeStreamLifecycleProto / racVlmStreamProto /
// racStructuredOutputGenerateStreamProto / racVoiceAgentProcessTurnProto to
// stack-allocate this ctx and DeleteGlobalRef
// the listener immediately after the call returns.
//
// The ONLY async case is racToolCallingSessionCreateProto, whose callback fires
// across later step() calls — it heap-allocates this struct and tracks it in
// toolCallingCtxMap() until racToolCallingSessionDestroyProto frees it.
struct ProtoListenerUserData {
    jobject listener;
    const char* operation;
};

static void proto_void_callback(const uint8_t* proto_bytes, size_t proto_size, void* user_data) {
    auto* ctx = static_cast<ProtoListenerUserData*>(user_data);
    if (ctx == nullptr || ctx->listener == nullptr) {
        return;
    }
    JNIEnv* env = getJNIEnv();
    invokeProtoListener(env, ctx->listener, proto_bytes, proto_size, ctx->operation);
}

static rac_bool_t proto_bool_callback(const uint8_t* proto_bytes, size_t proto_size,
                                      void* user_data) {
    auto* ctx = static_cast<ProtoListenerUserData*>(user_data);
    if (ctx == nullptr || ctx->listener == nullptr) {
        return RAC_TRUE;
    }
    JNIEnv* env = getJNIEnv();
    return invokeProtoListener(env, ctx->listener, proto_bytes, proto_size, ctx->operation)
               ? RAC_TRUE
               : RAC_FALSE;
}

static jbyteArray makeProtoCallResult(JNIEnv* env, rac_result_t rc, rac_proto_buffer_t* result,
                                      const char* operation) {
    if (RAC_FAILED(rc) && result != nullptr && result->status == RAC_SUCCESS) {
        rac_proto_buffer_set_error(result, rc, operation);
    }
    return makeProtoBufferByteArray(env, result, operation);
}

static rac_handle_t handleFromJLong(jlong handle) {
    return reinterpret_cast<rac_handle_t>(static_cast<uintptr_t>(handle));
}

template <typename Fn>
static Fn optionalNativeSymbol(const char* name) {
#ifdef _WIN32
    (void)name;
    return nullptr;
#else
    return reinterpret_cast<Fn>(dlsym(RTLD_DEFAULT, name));
#endif
}

static jbyteArray makeFeatureUnavailableResult(JNIEnv* env, const char* operation) {
    rac_proto_buffer_t result = {};
    rac_proto_buffer_init(&result);
    return makeProtoCallResult(env, RAC_ERROR_FEATURE_NOT_AVAILABLE, &result, operation);
}

// Retry-only counterpart to rac_vlm_cancel_lifecycle_proto. It deliberately
// emits no SDK event: a request-scoped JNI cancel emits the public logical
// cancellation once, then uses this helper only to bridge the backend's short
// active-request publication window.
static rac_result_t cancelVlmLifecycleSilently() {
    rac::vlm::LifecycleVlmRef ref;
    rac_result_t rc = rac::vlm::acquire_lifecycle_vlm(&ref);
    if (rc != RAC_SUCCESS) {
        return rc;
    }
    rac::vlm::request_lifecycle_vlm_cancel(&ref);
    if (ref.ops != nullptr && ref.ops->cancel != nullptr) {
        rc = ref.ops->cancel(ref.impl);
    } else {
        rc = RAC_SUCCESS;
    }
    rac::vlm::release_lifecycle_vlm(&ref);
    return rc;
}

// commons-156: a NewStringUTF / NewByteArray failure inside a callback that C++
// invokes leaves a pending OutOfMemoryError. If it is not cleared before the
// next JNI call on this thread, ART aborts the subsequent call with a
// misleading "JNI called with pending exception" error. Callbacks call this
// right after a `New*` that returned NULL, then bail with their own error code.
static bool jniClearPendingException(JNIEnv* env) {
    if (env->ExceptionCheck()) {
        env->ExceptionClear();
        return true;
    }
    return false;
}

static bool decodeUtf8CodePoint(const char* source, size_t length, size_t& index,
                                uint32_t& code_point) {
    const auto first = static_cast<unsigned char>(source[index]);
    if (first < 0x80) {
        code_point = first;
        ++index;
        return true;
    }

    size_t sequence_length = 0;
    uint32_t value = 0;
    uint32_t minimum_value = 0;
    if ((first & 0xe0u) == 0xc0u) {
        sequence_length = 2;
        value = first & 0x1fu;
        minimum_value = 0x80u;
    } else if ((first & 0xf0u) == 0xe0u) {
        sequence_length = 3;
        value = first & 0x0fu;
        minimum_value = 0x800u;
    } else if ((first & 0xf8u) == 0xf0u) {
        sequence_length = 4;
        value = first & 0x07u;
        minimum_value = 0x10000u;
    } else {
        ++index;
        return false;
    }

    if (index + sequence_length > length) {
        ++index;
        return false;
    }

    for (size_t offset = 1; offset < sequence_length; ++offset) {
        const auto next = static_cast<unsigned char>(source[index + offset]);
        if ((next & 0xc0u) != 0x80u) {
            ++index;
            return false;
        }
        value = (value << 6u) | (next & 0x3fu);
    }

    if (value < minimum_value || value > 0x10ffffu || (value >= 0xd800u && value <= 0xdfffu)) {
        ++index;
        return false;
    }

    code_point = value;
    index += sequence_length;
    return true;
}

static std::string jniSafeLogString(const char* value, const char* fallback) {
    const char* source = value != nullptr ? value : fallback;
    if (source == nullptr) {
        return "";
    }

    constexpr size_t kMaxLogChars = 4096;
    const size_t source_length = std::strlen(source);
    std::string output;
    output.reserve(std::min(source_length, kMaxLogChars));

    for (size_t i = 0; i < source_length && output.size() < kMaxLogChars;) {
        const size_t start = i;
        uint32_t code_point = 0;
        if (!decodeUtf8CodePoint(source, source_length, i, code_point)) {
            output.push_back('?');
            continue;
        }

        if (code_point == '\n' || code_point == '\r' || code_point == '\t' || code_point >= 0x20u) {
            const size_t byte_count = i - start;
            if (output.size() + byte_count > kMaxLogChars) {
                break;
            }
            output.append(source + start, byte_count);
        } else {
            output.push_back('?');
        }
    }

    return output;
}

static std::vector<jchar> utf8ToJChars(const std::string& value) {
    std::vector<jchar> chars;
    chars.reserve(value.size());

    for (size_t i = 0; i < value.size();) {
        uint32_t code_point = 0;
        if (!decodeUtf8CodePoint(value.c_str(), value.size(), i, code_point)) {
            code_point = '?';
        }

        if (code_point <= 0xffffu) {
            chars.push_back(static_cast<jchar>(code_point));
        } else {
            code_point -= 0x10000u;
            chars.push_back(static_cast<jchar>(0xd800u + (code_point >> 10u)));
            chars.push_back(static_cast<jchar>(0xdc00u + (code_point & 0x3ffu)));
        }
    }

    return chars;
}

static jstring newSafeLogJString(JNIEnv* env, const std::string& value) {
    const std::vector<jchar> chars = utf8ToJChars(value);
    jstring result =
        env->NewString(chars.empty() ? nullptr : chars.data(), static_cast<jsize>(chars.size()));
    if (result == nullptr) {
        jniClearPendingException(env);
    }
    return result;
}

// =============================================================================
// Platform Adapter C Callbacks (called by C++ library)
// =============================================================================

// Forward declaration of the adapter struct
static rac_platform_adapter_t g_c_adapter;

// End the helper-region NOLINT before the platform-adapter callbacks reopen it
// with the misc-unused-parameters check added.
// NOLINTEND(readability-implicit-bool-conversion,performance-no-int-to-ptr)

// The callback signatures below come from rac_platform_adapter_t. Many of the
// JNI implementations don't need the user_data hand-off because they retrieve
// state via JVM globals; the unused parameters are required by the C ABI.
// NOLINTBEGIN(misc-unused-parameters,readability-implicit-bool-conversion,performance-no-int-to-ptr)
// commons-155: each jni_*_callback takes g_adapter_mutex (now recursive) so a
// concurrent racSetPlatformAdapter cannot DeleteGlobalRef while we are
// mid-CallXxxMethod on the same jobject. Recursion permits LOGw inside the
// writer (which already holds the lock) to re-enter jni_log_callback without
// deadlocking.
static void jni_log_callback(rac_log_level_t level, const char* tag, const char* message,
                             void* user_data) {
    JNIEnv* env = getJNIEnv();
    const std::string safe_tag = jniSafeLogString(tag, "RAC");
    const std::string safe_message = jniSafeLogString(message, "");

    std::lock_guard<std::recursive_mutex> lock(g_adapter_mutex);
    if (env == nullptr || g_platform_adapter == nullptr || g_method_log == nullptr) {
        // Fallback to direct native logging (NOT through RAC_LOG_* to avoid recursion,
        // since this function IS the platform adapter's log callback). Map the
        // rac level to the matching android priority and pass `tag` through as
        // the logcat tag so the message survives default logcat filtering.
#ifdef __ANDROID__
        int prio;
        switch (level) {
            case RAC_LOG_TRACE:
            case RAC_LOG_DEBUG:
                prio = ANDROID_LOG_DEBUG;
                break;
            case RAC_LOG_INFO:
                prio = ANDROID_LOG_INFO;
                break;
            case RAC_LOG_WARNING:
                prio = ANDROID_LOG_WARN;
                break;
            case RAC_LOG_ERROR:
                prio = ANDROID_LOG_ERROR;
                break;
            case RAC_LOG_FATAL:
                prio = ANDROID_LOG_FATAL;
                break;
            default:
                prio = ANDROID_LOG_INFO;
                break;
        }
        __android_log_print(prio, safe_tag.c_str(), "%s", safe_message.c_str());
#else
        fprintf(stdout, "[DEBUG] [%s] %s\n", safe_tag.c_str(), safe_message.c_str());
#endif
        return;
    }

    jstring jTag = newSafeLogJString(env, safe_tag);
    jstring jMessage = newSafeLogJString(env, safe_message);
    if (jTag == nullptr || jMessage == nullptr) {
#ifdef __ANDROID__
        __android_log_print(ANDROID_LOG_WARN, safe_tag.c_str(), "%s", safe_message.c_str());
#else
        fprintf(stdout, "[WARN] [%s] %s\n", safe_tag.c_str(), safe_message.c_str());
#endif
        if (jTag != nullptr) {
            env->DeleteLocalRef(jTag);
        }
        if (jMessage != nullptr) {
            env->DeleteLocalRef(jMessage);
        }
        return;
    }

    env->CallVoidMethod(g_platform_adapter, g_method_log, static_cast<jint>(level), jTag, jMessage);
    jniClearPendingException(env);

    env->DeleteLocalRef(jTag);
    env->DeleteLocalRef(jMessage);
}

static rac_bool_t jni_file_exists_callback(const char* path, void* user_data) {
    JNIEnv* env = getJNIEnv();
    std::lock_guard<std::recursive_mutex> lock(g_adapter_mutex);
    if (env == nullptr || g_platform_adapter == nullptr || g_method_file_exists == nullptr) {
        return RAC_FALSE;
    }

    jstring jPath = env->NewStringUTF(path ? path : "");
    if (jPath == nullptr) {
        jniClearPendingException(env);
        return RAC_FALSE;
    }
    jboolean result = env->CallBooleanMethod(g_platform_adapter, g_method_file_exists, jPath);
    env->DeleteLocalRef(jPath);

    return result ? RAC_TRUE : RAC_FALSE;
}

static rac_result_t jni_file_read_callback(const char* path, void** out_data, size_t* out_size,
                                           void* user_data) {
    JNIEnv* env = getJNIEnv();
    std::lock_guard<std::recursive_mutex> lock(g_adapter_mutex);
    if (env == nullptr || g_platform_adapter == nullptr || g_method_file_read == nullptr) {
        return RAC_ERROR_ADAPTER_NOT_SET;
    }

    jstring jPath = env->NewStringUTF(path ? path : "");
    if (jPath == nullptr) {
        jniClearPendingException(env);
        *out_data = nullptr;
        *out_size = 0;
        return RAC_ERROR_OUT_OF_MEMORY;
    }
    jbyteArray result = static_cast<jbyteArray>(
        env->CallObjectMethod(g_platform_adapter, g_method_file_read, jPath));
    env->DeleteLocalRef(jPath);

    if (result == nullptr) {
        *out_data = nullptr;
        *out_size = 0;
        return RAC_ERROR_FILE_NOT_FOUND;
    }

    jsize len = env->GetArrayLength(result);
    // commons-156: malloc(0) is implementation-defined; treat a zero-byte file
    // as a clean empty read instead of a spurious OOM.
    *out_data = len > 0 ? malloc(static_cast<size_t>(len)) : nullptr;
    if (len > 0 && *out_data == nullptr) {
        *out_size = 0;
        env->DeleteLocalRef(result);
        return RAC_ERROR_OUT_OF_MEMORY;
    }
    *out_size = static_cast<size_t>(len);
    if (len > 0) {
        env->GetByteArrayRegion(result, 0, len, reinterpret_cast<jbyte*>(*out_data));
    }

    env->DeleteLocalRef(result);
    return RAC_SUCCESS;
}

static rac_result_t jni_file_write_callback(const char* path, const void* data, size_t size,
                                            void* user_data) {
    JNIEnv* env = getJNIEnv();
    std::lock_guard<std::recursive_mutex> lock(g_adapter_mutex);
    if (env == nullptr || g_platform_adapter == nullptr || g_method_file_write == nullptr) {
        return RAC_ERROR_ADAPTER_NOT_SET;
    }

    jstring jPath = env->NewStringUTF(path ? path : "");
    if (jPath == nullptr) {
        jniClearPendingException(env);
        return RAC_ERROR_OUT_OF_MEMORY;
    }
    jbyteArray jData = env->NewByteArray(static_cast<jsize>(size));
    if (jData == nullptr) {
        // commons-156: NewByteArray returns NULL on OOM; without this guard the
        // following SetByteArrayRegion dereferences NULL / raises and leaves a
        // pending exception for the next JNI call.
        jniClearPendingException(env);
        env->DeleteLocalRef(jPath);
        return RAC_ERROR_OUT_OF_MEMORY;
    }
    if (size > 0) {
        env->SetByteArrayRegion(jData, 0, static_cast<jsize>(size),
                                reinterpret_cast<const jbyte*>(data));
    }

    jboolean result = env->CallBooleanMethod(g_platform_adapter, g_method_file_write, jPath, jData);

    env->DeleteLocalRef(jPath);
    env->DeleteLocalRef(jData);

    return result ? RAC_SUCCESS : RAC_ERROR_FILE_WRITE_FAILED;
}

static rac_result_t jni_file_delete_callback(const char* path, void* user_data) {
    JNIEnv* env = getJNIEnv();
    std::lock_guard<std::recursive_mutex> lock(g_adapter_mutex);
    if (env == nullptr || g_platform_adapter == nullptr || g_method_file_delete == nullptr) {
        return RAC_ERROR_ADAPTER_NOT_SET;
    }

    jstring jPath = env->NewStringUTF(path ? path : "");
    if (jPath == nullptr) {
        jniClearPendingException(env);
        return RAC_ERROR_OUT_OF_MEMORY;
    }
    jboolean result = env->CallBooleanMethod(g_platform_adapter, g_method_file_delete, jPath);
    env->DeleteLocalRef(jPath);

    return result ? RAC_SUCCESS : RAC_ERROR_FILE_WRITE_FAILED;
}

static rac_result_t jni_secure_get_callback(const char* key, char** out_value, void* user_data) {
    if (out_value == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }
    *out_value = nullptr;

    JNIEnv* env = getJNIEnv();
    std::lock_guard<std::recursive_mutex> lock(g_adapter_mutex);
    if (env == nullptr || g_platform_adapter == nullptr || g_method_secure_get == nullptr) {
        return RAC_ERROR_ADAPTER_NOT_SET;
    }

    jstring jKey = env->NewStringUTF(key ? key : "");
    if (jKey == nullptr) {
        jniClearPendingException(env);
        return RAC_ERROR_OUT_OF_MEMORY;
    }
    jstring result =
        static_cast<jstring>(env->CallObjectMethod(g_platform_adapter, g_method_secure_get, jKey));
    env->DeleteLocalRef(jKey);

    // Kotlin returns null only for a clean miss. Authentication, decoding, and
    // Android Keystore failures throw so Commons can refuse to synthesize a
    // replacement device identity or silently discard persisted auth state.
    if (jniClearPendingException(env)) {
        if (result != nullptr) {
            env->DeleteLocalRef(result);
        }
        return RAC_ERROR_SECURE_STORAGE_FAILED;
    }

    // Contract (rac_platform_adapter.h secure_get): MUST return
    // RAC_ERROR_FILE_NOT_FOUND on a clean key-miss so commons consumers can
    // discriminate misses from real keychain failures. The Kotlin callback
    // returns null for the miss case (see CppBridgePlatformAdapter.secureGetCallback).
    if (result == nullptr) {
        return RAC_ERROR_FILE_NOT_FOUND;
    }

    const char* chars = env->GetStringUTFChars(result, nullptr);
    if (!chars) {
        jniClearPendingException(env);
        env->DeleteLocalRef(result);
        return RAC_ERROR_OUT_OF_MEMORY;
    }
    *out_value = strdup(chars);
    env->ReleaseStringUTFChars(result, chars);
    env->DeleteLocalRef(result);

    if (!*out_value) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }
    return RAC_SUCCESS;
}

static rac_result_t jni_secure_set_callback(const char* key, const char* value, void* user_data) {
    JNIEnv* env = getJNIEnv();
    std::lock_guard<std::recursive_mutex> lock(g_adapter_mutex);
    if (env == nullptr || g_platform_adapter == nullptr || g_method_secure_set == nullptr) {
        return RAC_ERROR_ADAPTER_NOT_SET;
    }

    jstring jKey = env->NewStringUTF(key ? key : "");
    jstring jValue = env->NewStringUTF(value ? value : "");
    if (jKey == nullptr || jValue == nullptr) {
        jniClearPendingException(env);
        if (jKey != nullptr) {
            env->DeleteLocalRef(jKey);
        }
        if (jValue != nullptr) {
            env->DeleteLocalRef(jValue);
        }
        return RAC_ERROR_OUT_OF_MEMORY;
    }
    jboolean result = env->CallBooleanMethod(g_platform_adapter, g_method_secure_set, jKey, jValue);

    env->DeleteLocalRef(jKey);
    env->DeleteLocalRef(jValue);
    if (jniClearPendingException(env)) {
        return RAC_ERROR_SECURE_STORAGE_FAILED;
    }

    return result ? RAC_SUCCESS : RAC_ERROR_SECURE_STORAGE_FAILED;
}

static rac_result_t jni_secure_delete_callback(const char* key, void* user_data) {
    JNIEnv* env = getJNIEnv();
    std::lock_guard<std::recursive_mutex> lock(g_adapter_mutex);
    if (env == nullptr || g_platform_adapter == nullptr || g_method_secure_delete == nullptr) {
        return RAC_ERROR_ADAPTER_NOT_SET;
    }

    jstring jKey = env->NewStringUTF(key ? key : "");
    if (jKey == nullptr) {
        jniClearPendingException(env);
        return RAC_ERROR_OUT_OF_MEMORY;
    }
    jboolean result = env->CallBooleanMethod(g_platform_adapter, g_method_secure_delete, jKey);
    env->DeleteLocalRef(jKey);
    if (jniClearPendingException(env)) {
        return RAC_ERROR_SECURE_STORAGE_FAILED;
    }

    return result ? RAC_SUCCESS : RAC_ERROR_SECURE_STORAGE_FAILED;
}

static int64_t jni_now_ms_callback(void* user_data) {
    JNIEnv* env = getJNIEnv();
    std::lock_guard<std::recursive_mutex> lock(g_adapter_mutex);
    if (env == nullptr || g_platform_adapter == nullptr || g_method_now_ms == nullptr) {
        // Fallback to system time
        return static_cast<int64_t>(time(nullptr)) * 1000;
    }

    return env->CallLongMethod(g_platform_adapter, g_method_now_ms);
}

// Directory enumeration via java.io.File.listFiles().
//
// Two-call semantics (per `rac_file_list_directory_fn`):
//   1. out_entries == NULL -> write total entry count into *in_out_count,
//      return RAC_SUCCESS without touching the entries array.
//   2. out_entries != NULL -> fill up to *in_out_count entries, update
//      *in_out_count to the number written.
//
// Truncation contract (per `rac_directory_entry_t::name`): when a UTF-8 entry
// name (+NUL) would exceed RAC_DIRECTORY_ENTRY_NAME_MAX the Kotlin callback
// MUST skip the entry rather than truncate; we mirror that on the JNI side
// in case the Kotlin layer ever forwards an oversized name (defensive copy
// uses strncpy with explicit NUL-termination so we never produce a half-name
// that aliases a different artifact).
static rac_result_t jni_file_list_directory_callback(const char* dir_path,
                                                     rac_directory_entry_t* out_entries,
                                                     size_t* in_out_count, void* user_data) {
    if (in_out_count == nullptr) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    JNIEnv* env = getJNIEnv();
    std::lock_guard<std::recursive_mutex> lock(g_adapter_mutex);
    if (env == nullptr || g_platform_adapter == nullptr ||
        g_method_file_list_directory == nullptr) {
        return RAC_ERROR_ADAPTER_NOT_SET;
    }

    jstring jPath = env->NewStringUTF(dir_path ? dir_path : "");
    jobjectArray result = static_cast<jobjectArray>(
        env->CallObjectMethod(g_platform_adapter, g_method_file_list_directory, jPath));
    env->DeleteLocalRef(jPath);

    if (env->ExceptionCheck()) {
        env->ExceptionDescribe();
        env->ExceptionClear();
        return RAC_ERROR_INTERNAL;
    }
    // Kotlin returns null to signal "directory does not exist" per the C ABI
    // contract; any other error is mapped to a structured Throwable above.
    if (result == nullptr) {
        return RAC_ERROR_FILE_NOT_FOUND;
    }

    const jsize total = env->GetArrayLength(result);

    // Capacity-query branch: caller wants the entry count.
    if (out_entries == nullptr) {
        *in_out_count = static_cast<size_t>(total);
        env->DeleteLocalRef(result);
        return RAC_SUCCESS;
    }

    // Fill branch: write up to *in_out_count entries.
    const size_t capacity = *in_out_count;
    const size_t write_count = std::min(capacity, static_cast<size_t>(total));

    for (size_t i = 0; i < write_count; ++i) {
        jobject entryObj = env->GetObjectArrayElement(result, static_cast<jsize>(i));
        if (entryObj == nullptr) {
            // Skip null slots defensively — the Kotlin contract should never
            // emit them, but treat as a benign skip rather than abort the
            // whole listing.
            std::memset(out_entries[i].name, 0, RAC_DIRECTORY_ENTRY_NAME_MAX);
            out_entries[i].is_dir = RAC_FALSE;
            out_entries[i].size_bytes = 0;
            continue;
        }

        // Kotlin RacDirectoryEntry is a data class with `name: String`,
        // `isDir: Boolean`, `sizeBytes: Long`. Look up the fields once per
        // entry — class lookup is cheap and the array length is typically
        // small (model-registry rescan_local on a single artifact dir).
        jclass entryClass = env->GetObjectClass(entryObj);
        jfieldID nameField = env->GetFieldID(entryClass, "name", "Ljava/lang/String;");
        jfieldID isDirField = env->GetFieldID(entryClass, "isDir", "Z");
        jfieldID sizeField = env->GetFieldID(entryClass, "sizeBytes", "J");

        jstring jName = static_cast<jstring>(env->GetObjectField(entryObj, nameField));
        jboolean jIsDir = env->GetBooleanField(entryObj, isDirField);
        jlong jSize = env->GetLongField(entryObj, sizeField);

        const char* nameChars =
            (jName != nullptr) ? env->GetStringUTFChars(jName, nullptr) : nullptr;
        if (nameChars != nullptr) {
            const size_t nameLen = std::strlen(nameChars);
            if (nameLen + 1 <= RAC_DIRECTORY_ENTRY_NAME_MAX) {
                std::memcpy(out_entries[i].name, nameChars, nameLen);
                out_entries[i].name[nameLen] = '\0';
            } else {
                // Defensive: Kotlin should already have filtered oversized
                // entries per the truncation contract. Zero-fill so we
                // never expose a half-name to commons.
                std::memset(out_entries[i].name, 0, RAC_DIRECTORY_ENTRY_NAME_MAX);
            }
            env->ReleaseStringUTFChars(jName, nameChars);
        } else {
            std::memset(out_entries[i].name, 0, RAC_DIRECTORY_ENTRY_NAME_MAX);
        }

        out_entries[i].is_dir = jIsDir ? RAC_TRUE : RAC_FALSE;
        out_entries[i].size_bytes = static_cast<int64_t>(jSize);

        if (jName != nullptr) {
            env->DeleteLocalRef(jName);
        }
        env->DeleteLocalRef(entryClass);
        env->DeleteLocalRef(entryObj);
    }

    *in_out_count = write_count;
    env->DeleteLocalRef(result);
    return RAC_SUCCESS;
}

// Cheap directory-probe used by rac_model_info_make_proto's
// is_downloaded gating. Falls back to file_list_directory + entry-count
// inside commons if NULL; we populate it so multi-file artifacts (mmproj +
// GGUF pairs, tokenizer + ONNX bundles) get the fast path on Android.
static rac_bool_t jni_is_non_empty_directory_callback(const char* path, void* user_data) {
    JNIEnv* env = getJNIEnv();
    std::lock_guard<std::recursive_mutex> lock(g_adapter_mutex);
    if (env == nullptr || g_platform_adapter == nullptr ||
        g_method_is_non_empty_directory == nullptr) {
        return RAC_FALSE;
    }

    jstring jPath = env->NewStringUTF(path ? path : "");
    jboolean result =
        env->CallBooleanMethod(g_platform_adapter, g_method_is_non_empty_directory, jPath);
    env->DeleteLocalRef(jPath);

    if (env->ExceptionCheck()) {
        env->ExceptionDescribe();
        env->ExceptionClear();
        return RAC_FALSE;
    }
    return result ? RAC_TRUE : RAC_FALSE;
}
// NOLINTEND(misc-unused-parameters,readability-implicit-bool-conversion,performance-no-int-to-ptr)

// =============================================================================
// JNI FUNCTIONS - Core Initialization
// =============================================================================

// JNI thunks must accept JNIEnv*, jclass/jobject parameters to satisfy the
// JNI calling convention. Many thunks ignore one or more of those — that is
// by design and not a bug. We also intentionally:
//   * Convert jboolean (unsigned char) to bool implicitly when checking JNI
//     status flags (e.g., `env->ExceptionCheck() ? nullptr : result`); JNI's
//     C signatures use jboolean throughout so an explicit cast at every site
//     would only add noise.
//   * Cast jlong handles to opaque pointers via reinterpret_cast — that is
//     the canonical JNI handle-passing idiom and the only way to round-trip
//     a native handle through the JVM.
// Tool-calling session helpers. These return C++-only types
// (std::mutex&, std::unordered_map&) so they must have C++ linkage, even though
// the JNI thunks that call them live in the extern "C" block below.
namespace {
std::mutex& toolCallingCtxMutex() {
    static std::mutex mu;
    return mu;
}
std::unordered_map<uint64_t, ProtoListenerUserData*>& toolCallingCtxMap() {
    static std::unordered_map<uint64_t, ProtoListenerUserData*> m;
    return m;
}

void captureToolCallingSessionHandle(uint64_t handle, void* user_data) {
    if (user_data != nullptr) {
        *static_cast<uint64_t*>(user_data) = handle;
    }
}

// Per-handle proto listener registry. Collapses the identical
// uintptr_t(handle) -> global jobject + mutex triplets (VAD activity, VAD
// stream, LLM stream, STT stream) into one type. At most one listener per
// handle (the C ABI enforces this), so a flat map is sufficient.
//
// Threading: every public method takes the internal mutex. The trampoline
// helper (acquireLocal) hands back a *local* ref created under the lock so the
// caller can invoke it after releasing the lock — identical to the prior
// hand-written callbacks. All GlobalRef lifetime is owned here.
class HandleListenerRegistry {
   public:
    // Replace (or clear when listener==nullptr) the listener for `key`.
    // `env` must be valid.
    void set(JNIEnv* env, uintptr_t key, jobject listener) {
        std::lock_guard<std::mutex> lock(mutex_);
        auto it = map_.find(key);
        if (it != map_.end()) {
            if (it->second != nullptr) {
                env->DeleteGlobalRef(it->second);
            }
            map_.erase(it);
        }
        if (listener != nullptr) {
            map_[key] = env->NewGlobalRef(listener);
        }
    }

    // Erase + release the listener for `key` (no-op if absent).
    void erase(JNIEnv* env, uintptr_t key) {
        std::lock_guard<std::mutex> lock(mutex_);
        auto it = map_.find(key);
        if (it != map_.end()) {
            if (it->second != nullptr) {
                env->DeleteGlobalRef(it->second);
            }
            map_.erase(it);
        }
    }

    // Return a fresh LOCAL ref to the listener for `key` (created under the
    // lock), or nullptr. Caller invokes then DeleteLocalRef.
    jobject acquireLocal(JNIEnv* env, uintptr_t key) {
        std::lock_guard<std::mutex> lock(mutex_);
        auto it = map_.find(key);
        if (it != map_.end() && it->second != nullptr) {
            return env->NewLocalRef(it->second);
        }
        return nullptr;
    }

    // Release every GlobalRef and clear (JNI_OnUnload path).
    void clearAll(JNIEnv* env) {
        std::lock_guard<std::mutex> lock(mutex_);
        for (auto& kv : map_) {
            if (kv.second != nullptr) {
                env->DeleteGlobalRef(kv.second);
            }
        }
        map_.clear();
    }

   private:
    std::mutex mutex_;
    std::unordered_map<uintptr_t, jobject> map_;
};

// Function-local singletons (avoid static-init-order issues), mirroring
// toolCallingCtxMap().
HandleListenerRegistry& vadActivityListeners() {
    static HandleListenerRegistry r;
    return r;
}
HandleListenerRegistry& vadStreamListeners() {
    static HandleListenerRegistry r;
    return r;
}
HandleListenerRegistry& llmStreamListeners() {
    static HandleListenerRegistry r;
    return r;
}
HandleListenerRegistry& sttStreamListeners() {
    static HandleListenerRegistry r;
    return r;
}
HandleListenerRegistry& diarizationStreamListeners() {
    static HandleListenerRegistry r;
    return r;
}

// Shared trampoline body. The per-handle proto callbacks differ only by
// op-name and which registry they read, so route them all through here.
void dispatchHandleListener(HandleListenerRegistry& reg, const uint8_t* proto_bytes,
                            size_t proto_size, void* user_data, const char* op) {
    uintptr_t key = reinterpret_cast<uintptr_t>(user_data);
    JNIEnv* env = getJNIEnv();
    if (env == nullptr) {
        return;
    }
    jobject listener = reg.acquireLocal(env, key);
    if (listener != nullptr) {
        invokeProtoListener(env, listener, proto_bytes, proto_size, op);
        env->DeleteLocalRef(listener);
    }
}
}  // namespace

// =============================================================================
// commons-056: JNI exception-safety macros.
// =============================================================================
// Per JNI Spec §13.1, a C++ exception that escapes a native method invocation
// is undefined behavior: ART's exception slot is left in an inconsistent
// state and subsequent ExceptionCheck calls either silently miss the throw or
// abort with "JNI DETECTED ERROR IN APPLICATION USE OF JNI". On
// memory-constrained Android devices `std::string` construction in the
// helpers below can raise `std::bad_alloc`, so every JNIEXPORT thunk that
// performs C++ allocations should wrap its body with RAC_JNI_TRY /
// RAC_JNI_CATCH_*. The catch arms translate std::bad_alloc to
// RAC_ERROR_OUT_OF_MEMORY and any other std::exception (or unknown type) to
// RAC_ERROR_INTERNAL, mirroring the contract of the rest of the C ABI.
//
// Pure forwarders that only pass primitives through the C ABI do not throw
// and may remain unwrapped. The helpers `getCString` / `getNullableCString`
// above are themselves `noexcept`, so simple ID-string thunks that already
// route through them are protected at the helper layer.
#define RAC_JNI_TRY try
#define RAC_JNI_CATCH_RET(ret_on_oom, ret_on_internal)    \
    catch (const std::bad_alloc& _e) {                    \
        LOGe("JNI thunk: out of memory (%s)", _e.what()); \
        return (ret_on_oom);                              \
    }                                                     \
    catch (const std::exception& _e) {                    \
        LOGe("JNI thunk: %s", _e.what());                 \
        return (ret_on_internal);                         \
    }                                                     \
    catch (...) { /* unknown exception type */            \
        LOGe("JNI thunk: unknown exception");             \
        return (ret_on_internal);                         \
    }
#define RAC_JNI_CATCH_INT()                                       \
    RAC_JNI_CATCH_RET(static_cast<jint>(RAC_ERROR_OUT_OF_MEMORY), \
                      static_cast<jint>(RAC_ERROR_INTERNAL))
#define RAC_JNI_CATCH_PTR() RAC_JNI_CATCH_RET(nullptr, nullptr)
#define RAC_JNI_CATCH_VOID()                              \
    catch (const std::bad_alloc& _e) {                    \
        LOGe("JNI thunk: out of memory (%s)", _e.what()); \
    }                                                     \
    catch (const std::exception& _e) {                    \
        LOGe("JNI thunk: %s", _e.what());                 \
    }                                                     \
    catch (...) {                                         \
        LOGe("JNI thunk: unknown exception");             \
    }

// NOLINTBEGIN(misc-unused-parameters,readability-implicit-bool-conversion,performance-no-int-to-ptr)
extern "C" {

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racInit(JNIEnv* env, jclass clazz) {
    LOGi("racInit called");

    // Check if platform adapter is set
    if (g_platform_adapter == nullptr) {
        LOGe("racInit: Platform adapter not set! Call racSetPlatformAdapter first.");
        return RAC_ERROR_ADAPTER_NOT_SET;
    }

    // Initialize with the C adapter struct
    rac_config_t config = {};
    config.platform_adapter = &g_c_adapter;
    config.log_level = RAC_LOG_DEBUG;
    config.log_tag = "RAC";

    rac_result_t result = rac_init(&config);

    if (result != RAC_SUCCESS) {
        LOGe("racInit failed with code: %d", result);
    } else {
        LOGi("racInit succeeded");
    }

    return static_cast<jint>(result);
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racShutdown(JNIEnv* env, jclass clazz) {
    LOGi("racShutdown called");
    rac_shutdown();
    return RAC_SUCCESS;
}

JNIEXPORT jboolean JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racIsInitialized(JNIEnv* env,
                                                                          jclass clazz) {
    return rac_is_initialized() ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT jstring JNICALL Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racSdkGetVersion(
    JNIEnv* env, jclass clazz) {
    (void)clazz;
    return env->NewStringUTF(rac_sdk_get_version());
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racSetPlatformAdapter(JNIEnv* env,
                                                                               jclass clazz,
                                                                               jobject adapter) {
    LOGi("racSetPlatformAdapter called");

    std::lock_guard<std::recursive_mutex> lock(g_adapter_mutex);

    // Clean up previous adapter
    if (g_platform_adapter != nullptr) {
        env->DeleteGlobalRef(g_platform_adapter);
        g_platform_adapter = nullptr;
    }

    if (adapter == nullptr) {
        LOGw("racSetPlatformAdapter: null adapter provided");
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    // Create global reference to adapter
    g_platform_adapter = env->NewGlobalRef(adapter);

    // Cache method IDs
    jclass adapterClass = env->GetObjectClass(adapter);

    g_method_log =
        env->GetMethodID(adapterClass, "log", "(ILjava/lang/String;Ljava/lang/String;)V");
    g_method_file_exists = env->GetMethodID(adapterClass, "fileExists", "(Ljava/lang/String;)Z");
    g_method_file_read = env->GetMethodID(adapterClass, "fileRead", "(Ljava/lang/String;)[B");
    g_method_file_write = env->GetMethodID(adapterClass, "fileWrite", "(Ljava/lang/String;[B)Z");
    g_method_file_delete = env->GetMethodID(adapterClass, "fileDelete", "(Ljava/lang/String;)Z");
    g_method_secure_get =
        env->GetMethodID(adapterClass, "secureGet", "(Ljava/lang/String;)Ljava/lang/String;");
    g_method_secure_set =
        env->GetMethodID(adapterClass, "secureSet", "(Ljava/lang/String;Ljava/lang/String;)Z");
    g_method_secure_delete =
        env->GetMethodID(adapterClass, "secureDelete", "(Ljava/lang/String;)Z");
    g_method_now_ms = env->GetMethodID(adapterClass, "nowMs", "()J");
    // Optional Kotlin-side directory probes. Method lookup is
    // best-effort — older host apps that haven't been recompiled against the
    // new adapter surface will miss these IDs and commons will fall through
    // to its NULL-callback branches (rescan_local emits a warning,
    // is_downloaded for multi-file artifacts reports false). New builds
    // expose CppBridgePlatformAdapter.fileListDirectory / isNonEmptyDirectory
    // so the model-registry and is_downloaded paths match the Web/Swift
    // behaviour documented in rac_platform_adapter.h.
    g_method_file_list_directory =
        env->GetMethodID(adapterClass, "fileListDirectory",
                         "(Ljava/lang/String;)[Lcom/runanywhere/sdk/foundation/bridge/extensions/"
                         "RacDirectoryEntry;");
    if (env->ExceptionCheck()) {
        env->ExceptionClear();
        g_method_file_list_directory = nullptr;
    }
    g_method_is_non_empty_directory =
        env->GetMethodID(adapterClass, "isNonEmptyDirectory", "(Ljava/lang/String;)Z");
    if (env->ExceptionCheck()) {
        env->ExceptionClear();
        g_method_is_non_empty_directory = nullptr;
    }

    env->DeleteLocalRef(adapterClass);

    // Initialize the C adapter struct with our JNI callbacks
    memset(&g_c_adapter, 0, sizeof(g_c_adapter));
    // ABI guard (W3-hardening): rac_init validates these two head fields and
    // rejects the adapter with RAC_ERROR_ABI_VERSION_MISMATCH if they are unset.
    g_c_adapter.abi_version = RAC_PLATFORM_ADAPTER_ABI_VERSION;
    g_c_adapter.struct_size = sizeof(g_c_adapter);
    g_c_adapter.log = jni_log_callback;
    g_c_adapter.file_exists = jni_file_exists_callback;
    g_c_adapter.file_read = jni_file_read_callback;
    g_c_adapter.file_write = jni_file_write_callback;
    g_c_adapter.file_delete = jni_file_delete_callback;
    g_c_adapter.secure_get = jni_secure_get_callback;
    g_c_adapter.secure_set = jni_secure_set_callback;
    g_c_adapter.secure_delete = jni_secure_delete_callback;
    g_c_adapter.now_ms = jni_now_ms_callback;
    // Populate directory enumeration slots iff the Kotlin
    // adapter exposed the corresponding methods. get_vendor_id intentionally
    // remains NULL — Android has no UIDevice.identifierForVendor analog, so
    // commons synthesizes + persists a UUID via secure_set per the cross-SDK
    // contract in rac_platform_adapter.h.
    g_c_adapter.file_list_directory =
        (g_method_file_list_directory != nullptr) ? jni_file_list_directory_callback : nullptr;
    g_c_adapter.is_non_empty_directory = (g_method_is_non_empty_directory != nullptr)
                                             ? jni_is_non_empty_directory_callback
                                             : nullptr;
    g_c_adapter.user_data = nullptr;

    // Install the populated struct as the commons-wide platform adapter
    // (mirrors Swift's CppBridge.PlatformAdapter.register()). Without this,
    // rac_get_platform_adapter() stays NULL for the whole process — the
    // legacy racInit() was the only caller and the Kotlin SDK's phase1-proto
    // init flow never invokes it — so every adapter-dependent commons path
    // (RAC_LOG forwarding to logcat, registry filesystem reconcile,
    // is_downloaded directory probes) silently no-ops.
    const rac_result_t adapter_rc = rac_set_platform_adapter(&g_c_adapter);
    if (adapter_rc != RAC_SUCCESS) {
        LOGe("racSetPlatformAdapter: rac_set_platform_adapter failed: %d", (int)adapter_rc);
        return adapter_rc;
    }

    LOGi("racSetPlatformAdapter: adapter set successfully");
    return RAC_SUCCESS;
}

JNIEXPORT jobject JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racGetPlatformAdapter(JNIEnv* env,
                                                                               jclass clazz) {
    std::lock_guard<std::recursive_mutex> lock(g_adapter_mutex);
    return g_platform_adapter;
}

JNIEXPORT jint JNICALL Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racConfigureLogging(
    JNIEnv* env, jclass clazz, jint environment) {
    (void)env;
    (void)clazz;
    rac_result_t result = rac_configure_logging(static_cast<rac_environment_t>(environment));
    return static_cast<jint>(result);
}

JNIEXPORT void JNICALL Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racLog(
    JNIEnv* env, jclass clazz, jint level, jstring tag, jstring message) {
    std::string tagStr = getCString(env, tag);
    std::string msgStr = getCString(env, message);

    rac_log(static_cast<rac_log_level_t>(level), tagStr.c_str(), msgStr.c_str());
}

// Delegates the metadata-redaction policy to the commons C ABI so Kotlin
// SDKLogger and the C++ logger apply the same sensitive-substring list.
JNIEXPORT jboolean JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racLogMetadataShouldRedact(JNIEnv* env,
                                                                                    jclass clazz,
                                                                                    jstring key) {
    if (key == nullptr) {
        return JNI_FALSE;
    }
    std::string keyStr = getCString(env, key);
    rac_bool_t out = RAC_FALSE;
    rac_result_t rc = rac_log_metadata_should_redact(keyStr.c_str(), &out);
    if (rc != RAC_SUCCESS) {
        return JNI_FALSE;
    }
    return out != RAC_FALSE ? JNI_TRUE : JNI_FALSE;
}

// Maps a `rac_result_t` to a serialized SDKError proto via the canonical
// commons helper, so Kotlin's SDKException routes the rac_result_t -> proto
// translation through the same single source of truth as Swift
// (RASDKError+Helpers.swift). Returns the serialized SDKError bytes.
JNIEXPORT jbyteArray JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racResultToProtoError(JNIEnv* env,
                                                                               jclass clazz,
                                                                               jint code) {
    rac_proto_buffer_t buffer = {};
    rac_proto_buffer_init(&buffer);
    rac_result_t rc = rac_result_to_proto_error(static_cast<rac_result_t>(code), &buffer);
    return makeProtoCallResult(env, rc, &buffer, "racResultToProtoError");
}

// =============================================================================
// JNI FUNCTIONS - Model Paths (canonical Swift-aligned schema)
// =============================================================================

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racModelPathsSetBaseDir(JNIEnv* env,
                                                                                 jclass clazz,
                                                                                 jstring baseDir) {
    (void)clazz;
    std::string baseDirStr = getCString(env, baseDir);
    rac_result_t result = rac_model_paths_set_base_dir(baseDirStr.c_str());
    return static_cast<jint>(result);
}

JNIEXPORT jstring JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racModelPathsGetBaseDir(JNIEnv* env,
                                                                                 jclass clazz) {
    (void)clazz;
    const char* value = rac_model_paths_get_base_dir();
    return value != nullptr ? env->NewStringUTF(value) : nullptr;
}

JNIEXPORT void JNICALL Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racHttpHfTokenSet(
    JNIEnv* env, jclass clazz, jstring token) {
    (void)clazz;
    std::string storage;
    rac_http_hf_token_set(getNullableCString(env, token, storage));
}

JNIEXPORT jstring JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racModelPathsGetModelFolder(
    JNIEnv* env, jclass clazz, jstring modelId, jint framework) {
    std::string modelIdStr = getCString(env, modelId);
    char buf[2048] = {0};
    rac_result_t result = rac_model_paths_get_model_folder(
        modelIdStr.c_str(), static_cast<rac_inference_framework_t>(framework), buf, sizeof(buf));
    if (result != RAC_SUCCESS) {
        return nullptr;
    }
    return env->NewStringUTF(buf);
}

// =============================================================================
// JNI FUNCTIONS - LLM Component
// =============================================================================

JNIEXPORT jlong JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racLlmComponentCreate(JNIEnv* env,
                                                                               jclass clazz) {
    rac_handle_t handle = RAC_INVALID_HANDLE;
    rac_result_t result = rac_llm_component_create(&handle);
    if (result != RAC_SUCCESS) {
        LOGe("Failed to create LLM component: %d", result);
        return 0;
    }
    return reinterpret_cast<jlong>(handle);
}

JNIEXPORT jboolean JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racLlmComponentIsLoaded(JNIEnv* env,
                                                                                 jclass clazz,
                                                                                 jlong handle) {
    (void)env;
    (void)clazz;
    return rac_llm_component_is_loaded(handleFromJLong(handle)) == RAC_TRUE ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racLlmComponentLoadModel(
    JNIEnv* env, jclass clazz, jlong handle, jstring modelPath, jstring modelId,
    jstring modelName) {
    (void)clazz;
    std::string path = getCString(env, modelPath);
    std::string id = getCString(env, modelId);
    std::string name = getCString(env, modelName);
    return static_cast<jint>(rac_llm_component_load_model(handleFromJLong(handle), path.c_str(),
                                                          id.c_str(), name.c_str()));
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racLlmComponentCleanup(JNIEnv* env,
                                                                                jclass clazz,
                                                                                jlong handle) {
    (void)env;
    (void)clazz;
    return static_cast<jint>(rac_llm_component_cleanup(handleFromJLong(handle)));
}

JNIEXPORT void JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racLlmComponentDestroy(JNIEnv* env,
                                                                                jclass clazz,
                                                                                jlong handle) {
    if (handle != 0) {
        // commons-057: drop the cached stream-listener GlobalRef before
        // destroying the component so an unbalanced setStreamProtoCallback (no
        // matching unset) cannot leak it past the handle's lifetime.
        rac_jni_erase_llm_stream_listener(env, static_cast<uintptr_t>(handle));
        rac_llm_component_destroy(reinterpret_cast<rac_handle_t>(handle));
    }
}

JNIEXPORT void JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racLlmComponentCancel(JNIEnv* env,
                                                                               jclass clazz,
                                                                               jlong handle) {
    if (handle != 0) {
        rac_llm_component_cancel(reinterpret_cast<rac_handle_t>(handle));
    }
}

// =============================================================================
// JNI FUNCTIONS - STT Component
// =============================================================================

JNIEXPORT jlong JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racSttComponentCreate(JNIEnv* env,
                                                                               jclass clazz) {
    rac_handle_t handle = RAC_INVALID_HANDLE;
    rac_result_t result = rac_stt_component_create(&handle);
    if (result != RAC_SUCCESS) {
        LOGe("Failed to create STT component: %d", result);
        return 0;
    }
    return reinterpret_cast<jlong>(handle);
}

JNIEXPORT jboolean JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racSttComponentIsLoaded(JNIEnv* env,
                                                                                 jclass clazz,
                                                                                 jlong handle) {
    (void)env;
    (void)clazz;
    return rac_stt_component_is_loaded(handleFromJLong(handle)) == RAC_TRUE ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racSttComponentLoadModel(
    JNIEnv* env, jclass clazz, jlong handle, jstring modelPath, jstring modelId,
    jstring modelName) {
    (void)clazz;
    std::string path = getCString(env, modelPath);
    std::string id = getCString(env, modelId);
    std::string name = getCString(env, modelName);
    return static_cast<jint>(rac_stt_component_load_model(handleFromJLong(handle), path.c_str(),
                                                          id.c_str(), name.c_str()));
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racSttComponentCleanup(JNIEnv* env,
                                                                                jclass clazz,
                                                                                jlong handle) {
    (void)env;
    (void)clazz;
    return static_cast<jint>(rac_stt_component_cleanup(handleFromJLong(handle)));
}

JNIEXPORT void JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racSttComponentDestroy(JNIEnv* env,
                                                                                jclass clazz,
                                                                                jlong handle) {
    if (handle != 0) {
        rac_stt_component_destroy(reinterpret_cast<rac_handle_t>(handle));
    }
}

JNIEXPORT void JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racSttComponentCancel(JNIEnv* env,
                                                                               jclass clazz,
                                                                               jlong handle) {
    // commons-058: intentional no-op. STT exposes no non-destructive stop/cancel
    // in the C ABI, and component-handle transcription is synchronous and
    // lifecycle-owned (rac_stt_transcribe[_stream]_lifecycle_proto), so there is
    // no in-flight work to interrupt at this layer. The previous
    // rac_stt_component_unload aliasing destructively evicted the loaded model on
    // cancel, forcing a full reload on the next transcribe. iOS Swift exposes no
    // STT cancel at all (CppBridge+STT has only load/unload/destroy).
    (void)handle;
}

// =============================================================================
// JNI FUNCTIONS - TTS Component
// =============================================================================

JNIEXPORT jlong JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racTtsComponentCreate(JNIEnv* env,
                                                                               jclass clazz) {
    rac_handle_t handle = RAC_INVALID_HANDLE;
    rac_result_t result = rac_tts_component_create(&handle);
    if (result != RAC_SUCCESS) {
        LOGe("Failed to create TTS component: %d", result);
        return 0;
    }
    return reinterpret_cast<jlong>(handle);
}

JNIEXPORT jboolean JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racTtsComponentIsLoaded(JNIEnv* env,
                                                                                 jclass clazz,
                                                                                 jlong handle) {
    (void)env;
    (void)clazz;
    return rac_tts_component_is_loaded(handleFromJLong(handle)) == RAC_TRUE ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racTtsComponentLoadVoice(
    JNIEnv* env, jclass clazz, jlong handle, jstring voicePath, jstring voiceId,
    jstring voiceName) {
    (void)clazz;
    std::string path = getCString(env, voicePath);
    std::string id = getCString(env, voiceId);
    std::string name = getCString(env, voiceName);
    return static_cast<jint>(rac_tts_component_load_voice(handleFromJLong(handle), path.c_str(),
                                                          id.c_str(), name.c_str()));
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racTtsComponentCleanup(JNIEnv* env,
                                                                                jclass clazz,
                                                                                jlong handle) {
    (void)env;
    (void)clazz;
    return static_cast<jint>(rac_tts_component_cleanup(handleFromJLong(handle)));
}

JNIEXPORT void JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racTtsComponentDestroy(JNIEnv* env,
                                                                                jclass clazz,
                                                                                jlong handle) {
    if (handle != 0) {
        rac_tts_component_destroy(reinterpret_cast<rac_handle_t>(handle));
    }
}

JNIEXPORT void JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racTtsComponentCancel(JNIEnv* env,
                                                                               jclass clazz,
                                                                               jlong handle) {
    // commons-058: stop the in-flight synthesis without evicting the loaded
    // voice. The previous rac_tts_component_unload aliasing destroyed the model
    // on cancel, forcing a multi-hundred-MB reload on the next synthesize. This
    // mirrors racVadComponentCancel -> rac_vad_component_stop.
    if (handle != 0) {
        rac_tts_component_stop(reinterpret_cast<rac_handle_t>(handle));
    }
}

// =============================================================================
// JNI FUNCTIONS - VAD Component
// =============================================================================

JNIEXPORT jlong JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racVadComponentCreate(JNIEnv* env,
                                                                               jclass clazz) {
    rac_handle_t handle = RAC_INVALID_HANDLE;
    rac_result_t result = rac_vad_component_create(&handle);
    if (result != RAC_SUCCESS) {
        LOGe("Failed to create VAD component: %d", result);
        return 0;
    }
    return reinterpret_cast<jlong>(handle);
}

JNIEXPORT jboolean JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racVadComponentIsLoaded(JNIEnv* env,
                                                                                 jclass clazz,
                                                                                 jlong handle) {
    (void)env;
    (void)clazz;
    return rac_vad_component_is_loaded(handleFromJLong(handle)) == RAC_TRUE ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racVadComponentLoadModel(
    JNIEnv* env, jclass clazz, jlong handle, jstring modelPath, jstring modelId,
    jstring modelName) {
    (void)clazz;
    std::string path = getCString(env, modelPath);
    std::string id = getCString(env, modelId);
    std::string name = getCString(env, modelName);
    return static_cast<jint>(rac_vad_component_load_model(handleFromJLong(handle), path.c_str(),
                                                          id.c_str(), name.c_str()));
}

JNIEXPORT void JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racVadComponentDestroy(JNIEnv* env,
                                                                                jclass clazz,
                                                                                jlong handle) {
    if (handle != 0) {
        // commons-057: release both VAD listener GlobalRefs (activity + stream)
        // for this handle before destroy. Reset intentionally keeps them since
        // the component is reused after a reset.
        rac_jni_erase_vad_listeners(env, static_cast<uintptr_t>(handle));
        rac_vad_component_destroy(reinterpret_cast<rac_handle_t>(handle));
    }
}

JNIEXPORT void JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racVadComponentCancel(JNIEnv* env,
                                                                               jclass clazz,
                                                                               jlong handle) {
    if (handle != 0) {
        rac_vad_component_stop(reinterpret_cast<rac_handle_t>(handle));
    }
}

JNIEXPORT void JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racVadComponentReset(JNIEnv* env,
                                                                              jclass clazz,
                                                                              jlong handle) {
    if (handle != 0) {
        rac_vad_component_reset(reinterpret_cast<rac_handle_t>(handle));
    }
}

// =============================================================================
// JNI FUNCTIONS - Model Registry (mirrors Swift CppBridge+ModelRegistry.swift)
//
// The legacy struct/JSON pipeline (javaModelInfoToC, modelInfoToJson,
// racModelRegistrySave / Get / GetAll / GetDownloaded / Remove /
// UpdateDownloadStatus) was deleted. Kotlin
// has migrated to the `racModelRegistry*Proto` family below.
// =============================================================================

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racModelRegistryRegisterProto(
    JNIEnv* env, jclass clazz, jbyteArray modelInfoProto) {
    return callModelRegistryProtoWrite(env, modelInfoProto, rac_model_registry_register_proto,
                                       "racModelRegistryRegisterProto");
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racModelRegistryUpdateProto(
    JNIEnv* env, jclass clazz, jbyteArray modelInfoProto) {
    return callModelRegistryProtoWrite(env, modelInfoProto, rac_model_registry_update_proto,
                                       "racModelRegistryUpdateProto");
}

JNIEXPORT jbyteArray JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racModelRegistryGetProto(JNIEnv* env,
                                                                                  jclass clazz,
                                                                                  jstring modelId) {
    if (!modelId) {
        return nullptr;
    }

    rac_model_registry_handle_t registry = rac_get_model_registry();
    if (!registry) {
        LOGe("racModelRegistryGetProto: model registry not initialized");
        return nullptr;
    }

    const char* id_str = env->GetStringUTFChars(modelId, nullptr);
    if (!id_str) {
        return nullptr;
    }

    uint8_t* bytes = nullptr;
    size_t size = 0;
    rac_result_t result = rac_model_registry_get_proto(registry, id_str, &bytes, &size);
    env->ReleaseStringUTFChars(modelId, id_str);

    if (result != RAC_SUCCESS) {
        rac_model_registry_proto_free(bytes);
        if (result != RAC_ERROR_NOT_FOUND) {
            LOGe("racModelRegistryGetProto: failed with code %d", result);
        }
        return nullptr;
    }

    return makeModelRegistryProtoByteArray(env, bytes, size, "racModelRegistryGetProto");
}

JNIEXPORT jbyteArray JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racModelRegistryListProto(JNIEnv* env,
                                                                                   jclass clazz) {
    rac_model_registry_handle_t registry = rac_get_model_registry();
    if (!registry) {
        LOGe("racModelRegistryListProto: model registry not initialized");
        return nullptr;
    }

    uint8_t* bytes = nullptr;
    size_t size = 0;
    rac_result_t result = rac_model_registry_list_proto(registry, &bytes, &size);
    if (result != RAC_SUCCESS) {
        rac_model_registry_proto_free(bytes);
        LOGe("racModelRegistryListProto: failed with code %d", result);
        return nullptr;
    }

    return makeModelRegistryProtoByteArray(env, bytes, size, "racModelRegistryListProto");
}

JNIEXPORT jbyteArray JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racModelRegistryQueryProto(
    JNIEnv* env, jclass clazz, jbyteArray queryProto) {
    if (!queryProto) {
        return nullptr;
    }

    rac_model_registry_handle_t registry = rac_get_model_registry();
    if (!registry) {
        LOGe("racModelRegistryQueryProto: model registry not initialized");
        return nullptr;
    }

    const jsize length = env->GetArrayLength(queryProto);
    jbyte* queryBytes = length > 0 ? env->GetByteArrayElements(queryProto, nullptr) : nullptr;
    if (length > 0 && queryBytes == nullptr) {
        LOGe("racModelRegistryQueryProto: failed to access JNI byte array");
        return nullptr;
    }

    uint8_t* bytes = nullptr;
    size_t size = 0;
    rac_result_t result =
        rac_model_registry_query_proto(registry, reinterpret_cast<const uint8_t*>(queryBytes),
                                       static_cast<size_t>(length), &bytes, &size);
    if (queryBytes != nullptr) {
        env->ReleaseByteArrayElements(queryProto, queryBytes, JNI_ABORT);
    }
    if (result != RAC_SUCCESS) {
        rac_model_registry_proto_free(bytes);
        LOGe("racModelRegistryQueryProto: failed with code %d", result);
        return nullptr;
    }

    return makeModelRegistryProtoByteArray(env, bytes, size, "racModelRegistryQueryProto");
}

JNIEXPORT jbyteArray JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racModelRegistryListDownloadedProto(
    JNIEnv* env, jclass clazz) {
    rac_model_registry_handle_t registry = rac_get_model_registry();
    if (!registry) {
        LOGe("racModelRegistryListDownloadedProto: model registry not initialized");
        return nullptr;
    }

    uint8_t* bytes = nullptr;
    size_t size = 0;
    rac_result_t result = rac_model_registry_list_downloaded_proto(registry, &bytes, &size);
    if (result != RAC_SUCCESS) {
        rac_model_registry_proto_free(bytes);
        LOGe("racModelRegistryListDownloadedProto: failed with code %d", result);
        return nullptr;
    }

    return makeModelRegistryProtoByteArray(env, bytes, size, "racModelRegistryListDownloadedProto");
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racModelRegistryRemoveProto(
    JNIEnv* env, jclass clazz, jstring modelId) {
    if (!modelId) {
        return RAC_ERROR_NULL_POINTER;
    }

    rac_model_registry_handle_t registry = rac_get_model_registry();
    if (!registry) {
        LOGe("racModelRegistryRemoveProto: model registry not initialized");
        return RAC_ERROR_NOT_INITIALIZED;
    }

    const char* id_str = env->GetStringUTFChars(modelId, nullptr);
    if (!id_str) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }

    rac_result_t result = rac_model_registry_remove_proto(registry, id_str);
    env->ReleaseStringUTFChars(modelId, id_str);
    return static_cast<jint>(result);
}

JNIEXPORT jbyteArray JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racModelRegistryRefreshProto(
    JNIEnv* env, jclass clazz, jbyteArray requestProto) {
    return callModelRegistryProtoBuffer(env, requestProto, rac_model_registry_refresh_proto,
                                        "racModelRegistryRefreshProto");
}

JNIEXPORT jbyteArray JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racModelCompatibilityCheckProto(
    JNIEnv* env, jclass clazz, jbyteArray requestProto) {
    return callProtoBufferFn(env, requestProto, rac_model_compatibility_check_proto,
                             "racModelCompatibilityCheckProto");
}

JNIEXPORT jbyteArray JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racRegisterModelFromUrlProto(
    JNIEnv* env, jclass clazz, jbyteArray requestBytes) {
    return callProtoBufferFn(env, requestBytes, rac_register_model_from_url_proto,
                             "racRegisterModelFromUrlProto");
}

JNIEXPORT jbyteArray JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racRegisterMultiFileModelProto(
    JNIEnv* env, jclass clazz, jbyteArray requestBytes) {
    return callProtoBufferFn(env, requestBytes, rac_register_multi_file_model_proto,
                             "racRegisterMultiFileModelProto");
}

JNIEXPORT jbyteArray JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racModelFormatFromUrlProto(
    JNIEnv* env, jclass clazz, jbyteArray requestBytes) {
    return callProtoBufferFn(env, requestBytes, rac_model_format_from_url_proto,
                             "racModelFormatFromUrlProto");
}

JNIEXPORT jbyteArray JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racArtifactInferFromUrlProto(
    JNIEnv* env, jclass clazz, jbyteArray requestBytes) {
    return callProtoBufferFn(env, requestBytes, rac_artifact_infer_from_url_proto,
                             "racArtifactInferFromUrlProto");
}

JNIEXPORT jbyteArray JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racModelInfoMakeProto(
    JNIEnv* env, jclass clazz, jbyteArray requestBytes) {
    return callProtoBufferFn(env, requestBytes, rac_model_info_make_proto, "racModelInfoMakeProto");
}

// =============================================================================
// JNI FUNCTIONS - Model Lifecycle Proto ABI (rac_model_lifecycle.h)
// =============================================================================

JNIEXPORT jbyteArray JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racModelLifecycleLoadProto(
    JNIEnv* env, jclass clazz, jbyteArray requestProto) {
    return callLifecycleLoadProtoFn(env, requestProto);
}

JNIEXPORT jbyteArray JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racModelLifecycleUnloadProto(
    JNIEnv* env, jclass clazz, jbyteArray requestProto) {
    return callProtoBufferFn(env, requestProto, rac_model_lifecycle_unload_proto,
                             "racModelLifecycleUnloadProto");
}

JNIEXPORT jbyteArray JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racModelLifecycleCurrentModelProto(
    JNIEnv* env, jclass clazz, jbyteArray requestProto) {
    return callProtoBufferFn(env, requestProto, rac_model_lifecycle_current_model_proto,
                             "racModelLifecycleCurrentModelProto");
}

JNIEXPORT jbyteArray JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racComponentLifecycleSnapshotProto(
    JNIEnv* env, jclass clazz, jint component) {
    rac_proto_buffer_t snapshot = {};
    rac_proto_buffer_init(&snapshot);
    rac_result_t rc =
        rac_component_lifecycle_snapshot_proto(static_cast<uint32_t>(component), &snapshot);
    if (RAC_FAILED(rc) && snapshot.status == RAC_SUCCESS) {
        rac_proto_buffer_set_error(&snapshot, rc, "racComponentLifecycleSnapshotProto");
    }
    return makeProtoBufferByteArray(env, &snapshot, "racComponentLifecycleSnapshotProto");
}

// =============================================================================
// JNI FUNCTIONS - Model Assignment (rac_model_assignment.h)
//
// No JNI callback wiring is needed: when no per-SDK
// rac_assignment_callbacks_t.http_get is registered, model_assignment.cpp
// falls back to its built-in default that routes the fetch through the
// platform HTTP transport registered via `rac_http_transport_register`
// (OkHttp on Android). The racModelAssignment* thunks live further down in
// this file.
// =============================================================================

// =============================================================================
// JNI FUNCTIONS - Audio Utils (rac_audio_utils.h)
// =============================================================================

JNIEXPORT jbyteArray JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racAudioFloat32ToWav(JNIEnv* env,
                                                                              jclass clazz,
                                                                              jbyteArray pcmData,
                                                                              jint sampleRate) {
    if (pcmData == nullptr) {
        LOGe("racAudioFloat32ToWav: null input data");
        return nullptr;
    }

    jsize pcmSize = env->GetArrayLength(pcmData);
    if (pcmSize == 0) {
        LOGe("racAudioFloat32ToWav: empty input data");
        return nullptr;
    }

    LOGi("racAudioFloat32ToWav: converting %d bytes at %d Hz", (int)pcmSize, sampleRate);

    // Get the input data
    jbyte* pcmBytes = env->GetByteArrayElements(pcmData, nullptr);
    if (pcmBytes == nullptr) {
        LOGe("racAudioFloat32ToWav: failed to get byte array elements");
        return nullptr;
    }

    // Convert Float32 PCM to WAV format
    void* wavData = nullptr;
    size_t wavSize = 0;

    rac_result_t result = rac_audio_float32_to_wav(pcmBytes, static_cast<size_t>(pcmSize),
                                                   sampleRate, &wavData, &wavSize);

    env->ReleaseByteArrayElements(pcmData, pcmBytes, JNI_ABORT);

    if (result != RAC_SUCCESS || wavData == nullptr) {
        LOGe("racAudioFloat32ToWav: conversion failed with code %d", result);
        return nullptr;
    }

    LOGi("racAudioFloat32ToWav: conversion successful, output %zu bytes", wavSize);

    // Create Java byte array for output
    jbyteArray jWavData = env->NewByteArray(static_cast<jsize>(wavSize));
    if (jWavData == nullptr) {
        LOGe("racAudioFloat32ToWav: failed to create output byte array");
        rac_free(wavData);
        return nullptr;
    }

    env->SetByteArrayRegion(jWavData, 0, static_cast<jsize>(wavSize),
                            reinterpret_cast<const jbyte*>(wavData));

    // Free the C-allocated memory
    rac_free(wavData);

    return jWavData;
}

JNIEXPORT jbyteArray JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racAudioInt16ToWav(JNIEnv* env,
                                                                            jclass clazz,
                                                                            jbyteArray pcmData,
                                                                            jint sampleRate) {
    if (pcmData == nullptr) {
        LOGe("racAudioInt16ToWav: null input data");
        return nullptr;
    }

    jsize pcmSize = env->GetArrayLength(pcmData);
    if (pcmSize == 0) {
        LOGe("racAudioInt16ToWav: empty input data");
        return nullptr;
    }

    LOGi("racAudioInt16ToWav: converting %d bytes at %d Hz", (int)pcmSize, sampleRate);

    // Get the input data
    jbyte* pcmBytes = env->GetByteArrayElements(pcmData, nullptr);
    if (pcmBytes == nullptr) {
        LOGe("racAudioInt16ToWav: failed to get byte array elements");
        return nullptr;
    }

    // Convert Int16 PCM to WAV format
    void* wavData = nullptr;
    size_t wavSize = 0;

    rac_result_t result = rac_audio_int16_to_wav(pcmBytes, static_cast<size_t>(pcmSize), sampleRate,
                                                 &wavData, &wavSize);

    env->ReleaseByteArrayElements(pcmData, pcmBytes, JNI_ABORT);

    if (result != RAC_SUCCESS || wavData == nullptr) {
        LOGe("racAudioInt16ToWav: conversion failed with code %d", result);
        return nullptr;
    }

    LOGi("racAudioInt16ToWav: conversion successful, output %zu bytes", wavSize);

    // Create Java byte array for output
    jbyteArray jWavData = env->NewByteArray(static_cast<jsize>(wavSize));
    if (jWavData == nullptr) {
        LOGe("racAudioInt16ToWav: failed to create output byte array");
        rac_free(wavData);
        return nullptr;
    }

    env->SetByteArrayRegion(jWavData, 0, static_cast<jsize>(wavSize),
                            reinterpret_cast<const jbyte*>(wavData));

    // Free the C-allocated memory
    rac_free(wavData);

    return jWavData;
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racAudioWavHeaderSize(JNIEnv* env,
                                                                               jclass clazz) {
    return static_cast<jint>(rac_audio_wav_header_size());
}

// =============================================================================
// JNI FUNCTIONS - Device Manager (rac_device_manager.h)
// =============================================================================
// Mirrors Swift SDK's CppBridge+Device.swift

// Global state for device callbacks
static struct {
    jobject callback_obj;
    jmethodID get_device_info_method;
    jmethodID get_device_id_method;
    jmethodID is_registered_method;
    jmethodID set_registered_method;
    jmethodID http_post_method;
    std::mutex mtx;
} g_device_jni_state = {};

// Forward declarations for device C callbacks
static void jni_device_get_info(rac_device_registration_info_t* out_info, void* user_data);
static const char* jni_device_get_id(void* user_data);
static rac_bool_t jni_device_is_registered(void* user_data);
static void jni_device_set_registered(rac_bool_t registered, void* user_data);
static rac_result_t jni_device_http_post(const char* endpoint, const char* json_body,
                                         rac_bool_t requires_auth,
                                         rac_device_http_response_t* out_response, void* user_data);

// Static storage for device ID string (needs to persist across calls)
// Protected by g_device_jni_state.mtx for thread safety
static std::string g_cached_device_id;

// Static storage for device info strings (need to persist for C callbacks)
static struct {
    std::string device_id;
    std::string device_model;
    std::string device_name;
    std::string platform;
    std::string os_version;
    std::string form_factor;
    std::string architecture;
    std::string chip_name;
    std::string gpu_family;
    std::string battery_state;
    std::string device_fingerprint;
    std::string manufacturer;
    std::mutex mtx;
} g_device_info_strings = {};

// Device callback implementations
static void jni_device_get_info(rac_device_registration_info_t* out_info, void* user_data) {
    JNIEnv* env = getJNIEnv();
    if (!env || !g_device_jni_state.callback_obj || !g_device_jni_state.get_device_info_method) {
        LOGe("jni_device_get_info: JNI not ready");
        return;
    }

    // Call Java getDeviceInfo() which returns a JSON string
    jstring jResult = (jstring)env->CallObjectMethod(g_device_jni_state.callback_obj,
                                                     g_device_jni_state.get_device_info_method);

    // Check for Java exception after CallObjectMethod
    if (env->ExceptionCheck()) {
        LOGe("jni_device_get_info: Java exception occurred in getDeviceInfo()");
        env->ExceptionDescribe();
        env->ExceptionClear();
        return;
    }

    if (jResult && out_info) {
        const char* json_str = env->GetStringUTFChars(jResult, nullptr);
        LOGd("jni_device_get_info: parsing JSON: %.200s...", json_str);

        // Parse JSON and extract all fields
        std::lock_guard<std::mutex> lock(g_device_info_strings.mtx);

        try {
            auto j = nlohmann::json::parse(json_str);

            // `j.value(key, def)` throws type_error if the key is present but
            // null (Kotlin emits null for absent optionals such as battery_state).
            // An unguarded throw here aborts the whole block, leaving the integer
            // fields below at 0 and tripping the backend's `total_memory > 0` /
            // `core_count > 0` checks. Read each field by type so a single
            // null/wrong-type value falls back to its default instead.
            auto str_field = [&j](const char* key) -> std::string {
                auto it = j.find(key);
                return (it != j.end() && it->is_string()) ? it->get<std::string>()
                                                          : std::string("");
            };
            auto i64_field = [&j](const char* key) -> int64_t {
                auto it = j.find(key);
                return (it != j.end() && it->is_number()) ? it->get<int64_t>() : (int64_t)0;
            };
            auto i32_field = [&j](const char* key) -> int32_t {
                auto it = j.find(key);
                return (it != j.end() && it->is_number()) ? it->get<int32_t>() : (int32_t)0;
            };
            auto bool_field = [&j](const char* key) -> bool {
                auto it = j.find(key);
                return (it != j.end() && it->is_boolean()) ? it->get<bool>() : false;
            };

            // Extract all string fields from Kotlin's getDeviceInfoCallback() JSON
            g_device_info_strings.device_id = str_field("device_id");
            g_device_info_strings.device_model = str_field("device_model");
            g_device_info_strings.device_name = str_field("device_name");
            g_device_info_strings.platform = str_field("platform");
            g_device_info_strings.os_version = str_field("os_version");
            g_device_info_strings.form_factor = str_field("form_factor");
            g_device_info_strings.architecture = str_field("architecture");
            g_device_info_strings.chip_name = str_field("chip_name");
            g_device_info_strings.gpu_family = str_field("gpu_family");
            g_device_info_strings.battery_state = str_field("battery_state");
            g_device_info_strings.device_fingerprint = str_field("device_fingerprint");
            g_device_info_strings.manufacturer = str_field("manufacturer");

            // Extract integer fields
            out_info->total_memory = i64_field("total_memory");
            out_info->available_memory = i64_field("available_memory");
            out_info->neural_engine_cores = i32_field("neural_engine_cores");
            out_info->core_count = i32_field("core_count");
            out_info->performance_cores = i32_field("performance_cores");
            out_info->efficiency_cores = i32_field("efficiency_cores");

            // Extract boolean fields
            out_info->has_neural_engine = bool_field("has_neural_engine") ? RAC_TRUE : RAC_FALSE;
            out_info->is_low_power_mode = bool_field("is_low_power_mode") ? RAC_TRUE : RAC_FALSE;

            // Extract float field for battery
            auto battery_it = j.find("battery_level");
            out_info->battery_level = (battery_it != j.end() && battery_it->is_number())
                                          ? battery_it->get<float>()
                                          : 0.0f;
        } catch (const nlohmann::json::exception& e) {
            LOGe("Failed to parse device info JSON: %s", e.what());
        }

        // Assign pointers to out_info (C struct uses const char*)
        out_info->device_id = g_device_info_strings.device_id.empty()
                                  ? nullptr
                                  : g_device_info_strings.device_id.c_str();
        out_info->device_model = g_device_info_strings.device_model.empty()
                                     ? nullptr
                                     : g_device_info_strings.device_model.c_str();
        out_info->device_name = g_device_info_strings.device_name.empty()
                                    ? nullptr
                                    : g_device_info_strings.device_name.c_str();
        out_info->platform = g_device_info_strings.platform.empty()
                                 ? "android"
                                 : g_device_info_strings.platform.c_str();
        out_info->os_version = g_device_info_strings.os_version.empty()
                                   ? nullptr
                                   : g_device_info_strings.os_version.c_str();
        out_info->form_factor = g_device_info_strings.form_factor.empty()
                                    ? nullptr
                                    : g_device_info_strings.form_factor.c_str();
        out_info->architecture = g_device_info_strings.architecture.empty()
                                     ? nullptr
                                     : g_device_info_strings.architecture.c_str();
        out_info->chip_name = g_device_info_strings.chip_name.empty()
                                  ? nullptr
                                  : g_device_info_strings.chip_name.c_str();
        out_info->gpu_family = g_device_info_strings.gpu_family.empty()
                                   ? nullptr
                                   : g_device_info_strings.gpu_family.c_str();
        out_info->battery_state = g_device_info_strings.battery_state.empty()
                                      ? nullptr
                                      : g_device_info_strings.battery_state.c_str();
        out_info->device_fingerprint = g_device_info_strings.device_fingerprint.empty()
                                           ? nullptr
                                           : g_device_info_strings.device_fingerprint.c_str();

        LOGi("jni_device_get_info: parsed device_model=%s, os_version=%s, architecture=%s",
             out_info->device_model ? out_info->device_model : "(null)",
             out_info->os_version ? out_info->os_version : "(null)",
             out_info->architecture ? out_info->architecture : "(null)");

        env->ReleaseStringUTFChars(jResult, json_str);
        env->DeleteLocalRef(jResult);
    }
}

static const char* jni_device_get_id(void* user_data) {
    JNIEnv* env = getJNIEnv();
    if (!env || !g_device_jni_state.callback_obj || !g_device_jni_state.get_device_id_method) {
        LOGe("jni_device_get_id: JNI not ready");
        return "";
    }

    jstring jResult = (jstring)env->CallObjectMethod(g_device_jni_state.callback_obj,
                                                     g_device_jni_state.get_device_id_method);

    // Check for Java exception after CallObjectMethod
    if (env->ExceptionCheck()) {
        LOGe("jni_device_get_id: Java exception occurred in getDeviceId()");
        env->ExceptionDescribe();
        env->ExceptionClear();
        return "";
    }

    if (jResult) {
        const char* str = env->GetStringUTFChars(jResult, nullptr);
        if (str == nullptr) {
            env->DeleteLocalRef(jResult);
            return "";
        }

        // Lock mutex to protect g_cached_device_id from concurrent access
        std::lock_guard<std::mutex> lock(g_device_jni_state.mtx);
        g_cached_device_id = str;
        env->ReleaseStringUTFChars(jResult, str);
        env->DeleteLocalRef(jResult);
        return g_cached_device_id.c_str();
    }
    return "";
}

static rac_bool_t jni_device_is_registered(void* user_data) {
    JNIEnv* env = getJNIEnv();
    if (!env || !g_device_jni_state.callback_obj || !g_device_jni_state.is_registered_method) {
        return RAC_FALSE;
    }

    jboolean result = env->CallBooleanMethod(g_device_jni_state.callback_obj,
                                             g_device_jni_state.is_registered_method);

    // Check for Java exception after CallBooleanMethod
    if (env->ExceptionCheck()) {
        LOGe("jni_device_is_registered: Java exception occurred in isRegistered()");
        env->ExceptionDescribe();
        env->ExceptionClear();
        return RAC_FALSE;
    }

    return result ? RAC_TRUE : RAC_FALSE;
}

static void jni_device_set_registered(rac_bool_t registered, void* user_data) {
    JNIEnv* env = getJNIEnv();
    if (!env || !g_device_jni_state.callback_obj || !g_device_jni_state.set_registered_method) {
        return;
    }

    env->CallVoidMethod(g_device_jni_state.callback_obj, g_device_jni_state.set_registered_method,
                        registered == RAC_TRUE ? JNI_TRUE : JNI_FALSE);

    // Check for Java exception after CallVoidMethod
    if (env->ExceptionCheck()) {
        LOGe("jni_device_set_registered: Java exception occurred in setRegistered()");
        env->ExceptionDescribe();
        env->ExceptionClear();
    }
}

static rac_result_t jni_device_http_post(const char* endpoint, const char* json_body,
                                         rac_bool_t requires_auth,
                                         rac_device_http_response_t* out_response,
                                         void* user_data) {
    JNIEnv* env = getJNIEnv();
    if (!env || !g_device_jni_state.callback_obj || !g_device_jni_state.http_post_method) {
        LOGe("jni_device_http_post: JNI not ready");
        if (out_response) {
            out_response->result = RAC_ERROR_ADAPTER_NOT_SET;
            out_response->status_code = -1;
        }
        return RAC_ERROR_ADAPTER_NOT_SET;
    }

    jstring jEndpoint = env->NewStringUTF(endpoint ? endpoint : "");
    jstring jBody = env->NewStringUTF(json_body ? json_body : "");

    // Check for allocation failures (can throw OutOfMemoryError)
    if (env->ExceptionCheck() || !jEndpoint || !jBody) {
        LOGe("jni_device_http_post: Failed to create JNI strings");
        if (env->ExceptionCheck()) {
            env->ExceptionDescribe();
            env->ExceptionClear();
        }
        if (jEndpoint)
            env->DeleteLocalRef(jEndpoint);
        if (jBody)
            env->DeleteLocalRef(jBody);
        if (out_response) {
            out_response->result = RAC_ERROR_OUT_OF_MEMORY;
            out_response->status_code = -1;
        }
        return RAC_ERROR_OUT_OF_MEMORY;
    }

    jint statusCode =
        env->CallIntMethod(g_device_jni_state.callback_obj, g_device_jni_state.http_post_method,
                           jEndpoint, jBody, requires_auth == RAC_TRUE ? JNI_TRUE : JNI_FALSE);

    // Check for Java exception after CallIntMethod
    if (env->ExceptionCheck()) {
        LOGe("jni_device_http_post: Java exception occurred in httpPost()");
        env->ExceptionDescribe();
        env->ExceptionClear();
        env->DeleteLocalRef(jEndpoint);
        env->DeleteLocalRef(jBody);
        if (out_response) {
            out_response->result = RAC_ERROR_NETWORK_ERROR;
            out_response->status_code = -1;
        }
        return RAC_ERROR_NETWORK_ERROR;
    }

    env->DeleteLocalRef(jEndpoint);
    env->DeleteLocalRef(jBody);

    if (out_response) {
        out_response->status_code = statusCode;
        out_response->result =
            (statusCode >= 200 && statusCode < 300) ? RAC_SUCCESS : RAC_ERROR_NETWORK_ERROR;
    }

    return (statusCode >= 200 && statusCode < 300) ? RAC_SUCCESS : RAC_ERROR_NETWORK_ERROR;
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racDeviceManagerSetCallbacks(
    JNIEnv* env, jclass clazz, jobject callbacks) {
    LOGi("racDeviceManagerSetCallbacks called");

    std::lock_guard<std::mutex> lock(g_device_jni_state.mtx);

    // Clean up previous callback
    if (g_device_jni_state.callback_obj != nullptr) {
        env->DeleteGlobalRef(g_device_jni_state.callback_obj);
        g_device_jni_state.callback_obj = nullptr;
    }

    if (callbacks == nullptr) {
        LOGw("racDeviceManagerSetCallbacks: null callbacks");
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    // Create global reference
    g_device_jni_state.callback_obj = env->NewGlobalRef(callbacks);

    // Cache method IDs
    jclass cls = env->GetObjectClass(callbacks);
    g_device_jni_state.get_device_info_method =
        env->GetMethodID(cls, "getDeviceInfo", "()Ljava/lang/String;");
    g_device_jni_state.get_device_id_method =
        env->GetMethodID(cls, "getDeviceId", "()Ljava/lang/String;");
    g_device_jni_state.is_registered_method = env->GetMethodID(cls, "isRegistered", "()Z");
    g_device_jni_state.set_registered_method = env->GetMethodID(cls, "setRegistered", "(Z)V");
    g_device_jni_state.http_post_method =
        env->GetMethodID(cls, "httpPost", "(Ljava/lang/String;Ljava/lang/String;Z)I");
    env->DeleteLocalRef(cls);

    // Verify methods found
    if (!g_device_jni_state.get_device_id_method || !g_device_jni_state.is_registered_method) {
        LOGe("racDeviceManagerSetCallbacks: required methods not found");
        env->DeleteGlobalRef(g_device_jni_state.callback_obj);
        g_device_jni_state.callback_obj = nullptr;
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    // Set up C callbacks
    rac_device_callbacks_t c_callbacks = {};
    c_callbacks.get_device_info = jni_device_get_info;
    c_callbacks.get_device_id = jni_device_get_id;
    c_callbacks.is_registered = jni_device_is_registered;
    c_callbacks.set_registered = jni_device_set_registered;
    c_callbacks.http_post = jni_device_http_post;
    c_callbacks.user_data = nullptr;

    rac_result_t result = rac_device_manager_set_callbacks(&c_callbacks);

    LOGi("racDeviceManagerSetCallbacks result: %d", result);
    return static_cast<jint>(result);
}

JNIEXPORT void JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racDeviceManagerClearCallbacks(
    JNIEnv* env, jclass clazz) {
    {
        // Lock order invariant shared with racDeviceManagerSetCallbacks:
        // JNI state first, then the native device-manager state. Native clear
        // is the quiescence barrier; it waits for in-flight callbacks before
        // we release their global reference below.
        std::lock_guard<std::mutex> lock(g_device_jni_state.mtx);
        rac_device_manager_clear_callbacks();
        if (g_device_jni_state.callback_obj != nullptr) {
            env->DeleteGlobalRef(g_device_jni_state.callback_obj);
            g_device_jni_state.callback_obj = nullptr;
        }
        g_device_jni_state.get_device_info_method = nullptr;
        g_device_jni_state.get_device_id_method = nullptr;
        g_device_jni_state.is_registered_method = nullptr;
        g_device_jni_state.set_registered_method = nullptr;
        g_device_jni_state.http_post_method = nullptr;
        g_cached_device_id.clear();
    }
    std::lock_guard<std::mutex> info_lock(g_device_info_strings.mtx);
    g_device_info_strings.device_id.clear();
    g_device_info_strings.device_model.clear();
    g_device_info_strings.device_name.clear();
    g_device_info_strings.platform.clear();
    g_device_info_strings.os_version.clear();
    g_device_info_strings.form_factor.clear();
    g_device_info_strings.architecture.clear();
    g_device_info_strings.chip_name.clear();
    g_device_info_strings.gpu_family.clear();
    g_device_info_strings.battery_state.clear();
    g_device_info_strings.device_fingerprint.clear();
    g_device_info_strings.manufacturer.clear();
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racDeviceManagerRegisterIfNeeded(
    JNIEnv* env, jclass clazz, jint environment, jstring buildToken) {
    LOGi("racDeviceManagerRegisterIfNeeded called (env=%d)", environment);

    std::string tokenStorage;
    const char* token = getNullableCString(env, buildToken, tokenStorage);

    rac_result_t result =
        rac_device_manager_register_if_needed(static_cast<rac_environment_t>(environment), token);

    LOGi("racDeviceManagerRegisterIfNeeded result: %d", result);
    return static_cast<jint>(result);
}

JNIEXPORT jboolean JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racDeviceManagerIsRegistered(
    JNIEnv* env, jclass clazz) {
    return rac_device_manager_is_registered() == RAC_TRUE ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT void JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racDeviceManagerClearRegistration(
    JNIEnv* env, jclass clazz) {
    LOGi("racDeviceManagerClearRegistration called");
    rac_device_manager_clear_registration();
}

JNIEXPORT jstring JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racDeviceManagerGetDeviceId(JNIEnv* env,
                                                                                     jclass clazz) {
    const char* deviceId = rac_device_manager_get_device_id();
    if (deviceId) {
        return env->NewStringUTF(deviceId);
    }
    return nullptr;
}

// =============================================================================
// JNI FUNCTIONS - Telemetry Manager (rac_telemetry_manager.h)
// =============================================================================
// Mirrors Swift SDK's CppBridge+Telemetry.swift

// Global state for telemetry
static struct {
    rac_telemetry_manager_t* manager;
    jobject http_callback_obj;
    jmethodID http_callback_method;
    std::mutex mtx;
} g_telemetry_jni_state = {};

// Telemetry HTTP callback from C++ to Java
static void jni_telemetry_http_callback(void* user_data, const char* endpoint,
                                        const char* json_body, size_t json_length,
                                        rac_bool_t requires_auth) {
    JNIEnv* env = getJNIEnv();
    if (!env || !g_telemetry_jni_state.http_callback_obj ||
        !g_telemetry_jni_state.http_callback_method) {
        LOGw("jni_telemetry_http_callback: JNI not ready");
        return;
    }

    jstring jEndpoint = env->NewStringUTF(endpoint ? endpoint : "");
    jstring jBody = env->NewStringUTF(json_body ? json_body : "");

    // Check for NewStringUTF allocation failures
    if (!jEndpoint || !jBody) {
        LOGe("jni_telemetry_http_callback: failed to allocate JNI strings");
        if (jEndpoint)
            env->DeleteLocalRef(jEndpoint);
        if (jBody)
            env->DeleteLocalRef(jBody);
        return;
    }

    env->CallVoidMethod(g_telemetry_jni_state.http_callback_obj,
                        g_telemetry_jni_state.http_callback_method, jEndpoint, jBody,
                        static_cast<jint>(json_length),
                        requires_auth == RAC_TRUE ? JNI_TRUE : JNI_FALSE);

    // Check for Java exception after CallVoidMethod
    if (env->ExceptionCheck()) {
        LOGe("jni_telemetry_http_callback: Java exception occurred in HTTP callback");
        env->ExceptionDescribe();
        env->ExceptionClear();
    }

    // Always clean up local references
    env->DeleteLocalRef(jEndpoint);
    env->DeleteLocalRef(jBody);
}

JNIEXPORT jlong JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racTelemetryManagerCreate(
    JNIEnv* env, jclass clazz, jint environment, jstring deviceId, jstring platform,
    jstring sdkVersion) {
    LOGi("racTelemetryManagerCreate called (env=%d)", environment);

    std::string deviceIdStr = getCString(env, deviceId);
    std::string platformStr = getCString(env, platform);
    std::string versionStr = getCString(env, sdkVersion);

    std::lock_guard<std::mutex> lock(g_telemetry_jni_state.mtx);

    // Destroy existing manager if any
    if (g_telemetry_jni_state.manager) {
        rac_telemetry_manager_destroy(g_telemetry_jni_state.manager);
    }

    g_telemetry_jni_state.manager =
        rac_telemetry_manager_create(static_cast<rac_environment_t>(environment),
                                     deviceIdStr.c_str(), platformStr.c_str(), versionStr.c_str());

    LOGi("racTelemetryManagerCreate: manager=%p", (void*)g_telemetry_jni_state.manager);
    return reinterpret_cast<jlong>(g_telemetry_jni_state.manager);
}

JNIEXPORT void JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racTelemetryManagerDestroy(JNIEnv* env,
                                                                                    jclass clazz,
                                                                                    jlong handle) {
    LOGi("racTelemetryManagerDestroy called");

    std::lock_guard<std::mutex> lock(g_telemetry_jni_state.mtx);

    if (handle != 0 &&
        reinterpret_cast<rac_telemetry_manager_t*>(handle) == g_telemetry_jni_state.manager) {
        // Flush before destroying
        rac_telemetry_manager_flush(g_telemetry_jni_state.manager);
        rac_telemetry_manager_destroy(g_telemetry_jni_state.manager);
        g_telemetry_jni_state.manager = nullptr;

        // Clean up callback
        if (g_telemetry_jni_state.http_callback_obj) {
            env->DeleteGlobalRef(g_telemetry_jni_state.http_callback_obj);
            g_telemetry_jni_state.http_callback_obj = nullptr;
        }
    }
}

JNIEXPORT void JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racTelemetryManagerSetDeviceInfo(
    JNIEnv* env, jclass clazz, jlong handle, jstring deviceModel, jstring osVersion) {
    if (handle == 0)
        return;

    std::string modelStr = getCString(env, deviceModel);
    std::string osStr = getCString(env, osVersion);

    rac_telemetry_manager_set_device_info(reinterpret_cast<rac_telemetry_manager_t*>(handle),
                                          modelStr.c_str(), osStr.c_str());

    LOGi("racTelemetryManagerSetDeviceInfo: model=%s, os=%s", modelStr.c_str(), osStr.c_str());
}

JNIEXPORT void JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racTelemetryManagerSetHttpCallback(
    JNIEnv* env, jclass clazz, jlong handle, jobject callback) {
    LOGi("racTelemetryManagerSetHttpCallback called");

    if (handle == 0)
        return;

    std::lock_guard<std::mutex> lock(g_telemetry_jni_state.mtx);

    // Clean up previous callback
    if (g_telemetry_jni_state.http_callback_obj) {
        env->DeleteGlobalRef(g_telemetry_jni_state.http_callback_obj);
        g_telemetry_jni_state.http_callback_obj = nullptr;
    }

    if (callback) {
        g_telemetry_jni_state.http_callback_obj = env->NewGlobalRef(callback);

        // Cache method ID
        jclass cls = env->GetObjectClass(callback);
        g_telemetry_jni_state.http_callback_method =
            env->GetMethodID(cls, "onHttpRequest", "(Ljava/lang/String;Ljava/lang/String;IZ)V");
        env->DeleteLocalRef(cls);

        // Register C callback with telemetry manager
        rac_telemetry_manager_set_http_callback(reinterpret_cast<rac_telemetry_manager_t*>(handle),
                                                jni_telemetry_http_callback, nullptr);
    }
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racTelemetryManagerFlush(JNIEnv* env,
                                                                                  jclass clazz,
                                                                                  jlong handle) {
    LOGi("racTelemetryManagerFlush called");

    if (handle == 0)
        return RAC_ERROR_INVALID_HANDLE;

    return static_cast<jint>(
        rac_telemetry_manager_flush(reinterpret_cast<rac_telemetry_manager_t*>(handle)));
}

// =============================================================================
// JNI FUNCTIONS - Telemetry sink + SDK event emission (canonical proto stream)
// =============================================================================
//
// The legacy struct-based analytics callback was removed. Telemetry is now fed
// by the C++ destination router: the SDK registers the telemetry manager once
// via rac_events_set_telemetry_sink and every event whose destination includes
// the TELEMETRY bit is forwarded automatically. The racAnalyticsEventEmit*
// bridges below build the canonical runanywhere.v1 proto payloads (mirrored
// from the legacy event-type ints supplied by Kotlin) and publish them through
// the same rac::events::emit_* helpers used by the C++ component layer.

// Legacy event-type int constants (the values Kotlin still passes as eventType).
// Kept here as the JNI<->Kotlin wire contract; the C++ side no longer carries a
// rac_event_type_t enum.
namespace {
constexpr jint kEvtLlmModelLoadStarted = 100;
constexpr jint kEvtLlmModelLoadCompleted = 101;
constexpr jint kEvtLlmModelLoadFailed = 102;
constexpr jint kEvtLlmModelUnloaded = 103;
constexpr jint kEvtLlmGenerationStarted = 110;
constexpr jint kEvtLlmGenerationCompleted = 111;
constexpr jint kEvtLlmGenerationFailed = 112;
constexpr jint kEvtLlmFirstToken = 113;
constexpr jint kEvtLlmStreamingUpdate = 114;

constexpr jint kEvtSttTranscriptionStarted = 210;
constexpr jint kEvtSttTranscriptionCompleted = 211;
constexpr jint kEvtSttTranscriptionFailed = 212;

constexpr jint kEvtTtsSynthesisStarted = 310;
constexpr jint kEvtTtsSynthesisCompleted = 311;
constexpr jint kEvtTtsSynthesisFailed = 312;

constexpr jint kEvtVadSpeechStarted = 402;
constexpr jint kEvtVadSpeechEnded = 403;

constexpr jint kEvtModelDownloadStarted = 700;
constexpr jint kEvtModelDownloadProgress = 701;
constexpr jint kEvtModelDownloadCompleted = 702;
constexpr jint kEvtModelDownloadFailed = 703;
constexpr jint kEvtModelDownloadCancelled = 704;
constexpr jint kEvtModelExtractionStarted = 710;
constexpr jint kEvtModelExtractionProgress = 711;
constexpr jint kEvtModelExtractionCompleted = 712;
constexpr jint kEvtModelExtractionFailed = 713;
constexpr jint kEvtModelDeleted = 720;

constexpr jint kEvtSdkInitStarted = 600;
constexpr jint kEvtSdkInitCompleted = 601;
constexpr jint kEvtSdkInitFailed = 602;
constexpr jint kEvtSdkModelsLoaded = 603;
}  // namespace

JNIEXPORT void JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racEventsSetTelemetrySink(
    JNIEnv* env, jclass clazz, jlong telemetryHandle) {
    LOGi("racEventsSetTelemetrySink called (telemetryHandle=%lld)", (long long)telemetryHandle);
    rac_events_set_telemetry_sink(reinterpret_cast<void*>(telemetryHandle));
}

// =============================================================================
// JNI FUNCTIONS - SDK Event Emission (Kotlin-originated)
// =============================================================================
// These functions let Kotlin emit SDK events (e.g. lifecycle/model/download
// events originating from Kotlin). They build the canonical proto payload and
// publish it via rac::events::emit_*, so they reach telemetry through the same
// destination router as C++ component events.

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racAnalyticsEventEmitDownload(
    JNIEnv* env, jclass clazz, jint eventType, jstring modelId, jdouble progress,
    jlong bytesDownloaded, jlong totalBytes, jdouble durationMs, jlong sizeBytes,
    jstring archiveType, jint errorCode, jstring errorMessage) {
    std::string modelIdStr = getCString(env, modelId);
    std::string archiveTypeStorage;
    std::string errorMsgStorage;
    const char* archiveTypePtr = getNullableCString(env, archiveType, archiveTypeStorage);
    const char* errorMsgPtr = getNullableCString(env, errorMessage, errorMsgStorage);
    const char* modelIdPtr = modelIdStr.c_str();

    switch (eventType) {
        case kEvtModelDownloadStarted:
            rac::events::emit_model_download_started(modelIdPtr, totalBytes, archiveTypePtr);
            break;
        case kEvtModelDownloadProgress:
            rac::events::emit_model_download_progress(modelIdPtr, progress, bytesDownloaded,
                                                      totalBytes);
            break;
        case kEvtModelDownloadCompleted:
            rac::events::emit_model_download_completed(modelIdPtr, sizeBytes, durationMs,
                                                       archiveTypePtr);
            break;
        case kEvtModelDownloadFailed:
            rac::events::emit_model_download_failed(
                modelIdPtr, static_cast<rac_result_t>(errorCode), errorMsgPtr);
            break;
        case kEvtModelDownloadCancelled:
            rac::events::emit_model_download_cancelled(modelIdPtr);
            break;
        case kEvtModelExtractionStarted:
            rac::events::emit_model_extraction_started(modelIdPtr, archiveTypePtr);
            break;
        case kEvtModelExtractionProgress:
            rac::events::emit_model_extraction_progress(modelIdPtr, progress);
            break;
        case kEvtModelExtractionCompleted:
            rac::events::emit_model_extraction_completed(modelIdPtr, sizeBytes, durationMs);
            break;
        case kEvtModelExtractionFailed:
            rac::events::emit_model_extraction_failed(
                modelIdPtr, static_cast<rac_result_t>(errorCode), errorMsgPtr);
            break;
        case kEvtModelDeleted:
            rac::events::emit_model_deleted(modelIdPtr, sizeBytes);
            break;
        default:
            break;
    }
    return RAC_SUCCESS;
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racAnalyticsEventEmitSdkLifecycle(
    JNIEnv* env, jclass clazz, jint eventType, jdouble durationMs, jint count, jint errorCode,
    jstring errorMessage) {
    std::string errorMsgStorage;
    const char* errorMsgPtr = getNullableCString(env, errorMessage, errorMsgStorage);

    switch (eventType) {
        case kEvtSdkInitStarted:
            rac::events::emit_sdk_init_started();
            break;
        case kEvtSdkInitCompleted:
            rac::events::emit_sdk_init_completed(durationMs);
            break;
        case kEvtSdkInitFailed:
            rac::events::emit_sdk_init_failed(static_cast<rac_result_t>(errorCode), errorMsgPtr);
            break;
        case kEvtSdkModelsLoaded:
            rac::events::emit_sdk_models_loaded(count, durationMs);
            break;
        default:
            break;
    }
    return RAC_SUCCESS;
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racAnalyticsEventEmitStorage(
    JNIEnv* env, jclass clazz, jint eventType, jlong freedBytes, jint errorCode,
    jstring errorMessage) {
    std::string errorMsgStorage;
    const char* errorMsgPtr = getNullableCString(env, errorMessage, errorMsgStorage);

    // 800 = cache cleared, 801 = cache clear failed, 802 = temp cleaned.
    switch (eventType) {
        case 800:
            rac::events::emit_storage_cache_cleared(freedBytes);
            break;
        case 801:
            rac::events::emit_storage_cache_clear_failed(static_cast<rac_result_t>(errorCode),
                                                         errorMsgPtr);
            break;
        case 802:
            rac::events::emit_storage_temp_cleaned(freedBytes);
            break;
        default:
            break;
    }
    return RAC_SUCCESS;
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racAnalyticsEventEmitDevice(
    JNIEnv* env, jclass clazz, jint eventType, jstring deviceId, jint errorCode,
    jstring errorMessage) {
    std::string deviceIdStr = getCString(env, deviceId);
    std::string errorMsgStorage;
    const char* errorMsgPtr = getNullableCString(env, errorMessage, errorMsgStorage);

    // 900 = device registered, 901 = device registration failed.
    if (eventType == 901) {
        rac::events::emit_device_registration_failed(static_cast<rac_result_t>(errorCode),
                                                     errorMsgPtr);
    } else {
        rac::events::emit_device_registered(deviceIdStr.c_str());
    }
    return RAC_SUCCESS;
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racAnalyticsEventEmitSdkError(
    JNIEnv* env, jclass clazz, jint eventType, jint errorCode, jstring errorMessage,
    jstring operation, jstring context) {
    (void)eventType;
    std::string errorMsgStorage, opStorage, ctxStorage;
    const char* errorMsgPtr = getNullableCString(env, errorMessage, errorMsgStorage);
    const char* opPtr = getNullableCString(env, operation, opStorage);
    const char* ctxPtr = getNullableCString(env, context, ctxStorage);

    rac::events::emit_sdk_error(static_cast<rac_result_t>(errorCode), errorMsgPtr, opPtr, ctxPtr);
    return RAC_SUCCESS;
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racAnalyticsEventEmitNetwork(
    JNIEnv* env, jclass clazz, jint eventType, jboolean isOnline) {
    (void)env;
    (void)clazz;
    (void)eventType;
    rac::events::emit_network_connectivity_changed(isOnline == JNI_TRUE);
    return RAC_SUCCESS;
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racAnalyticsEventEmitLlmGeneration(
    JNIEnv* env, jclass clazz, jint eventType, jstring generationId, jstring modelId,
    jstring modelName, jint inputTokens, jint outputTokens, jdouble durationMs,
    jdouble tokensPerSecond, jboolean isStreaming, jdouble timeToFirstTokenMs, jint framework,
    jfloat temperature, jint maxTokens, jint contextLength, jint errorCode, jstring errorMessage) {
    std::string genIdStr = getCString(env, generationId);
    std::string modelIdStr = getCString(env, modelId);
    std::string modelNameStorage;
    std::string errorMsgStorage;
    const char* modelNamePtr = getNullableCString(env, modelName, modelNameStorage);
    const char* errorMsgPtr = getNullableCString(env, errorMessage, errorMsgStorage);

    const char* genIdPtr = genIdStr.c_str();
    const char* modelIdPtr = modelIdStr.c_str();
    const auto fw = static_cast<rac_inference_framework_t>(framework);

    switch (eventType) {
        case kEvtLlmGenerationStarted:
            rac::events::emit_llm_generation_started(genIdPtr, modelIdPtr, isStreaming == JNI_TRUE,
                                                     fw, temperature, maxTokens, contextLength);
            break;
        case kEvtLlmGenerationCompleted:
            rac::events::emit_llm_generation_completed(genIdPtr, modelIdPtr, inputTokens,
                                                       outputTokens, durationMs, tokensPerSecond,
                                                       isStreaming == JNI_TRUE, timeToFirstTokenMs,
                                                       fw, temperature, maxTokens, contextLength);
            break;
        case kEvtLlmGenerationFailed:
            rac::events::emit_llm_generation_failed(
                genIdPtr, modelIdPtr, static_cast<rac_result_t>(errorCode), errorMsgPtr);
            break;
        case kEvtLlmFirstToken:
            rac::events::emit_llm_first_token(genIdPtr, modelIdPtr, timeToFirstTokenMs, fw);
            break;
        case kEvtLlmStreamingUpdate:
            rac::events::emit_llm_streaming_update(genIdPtr, outputTokens);
            break;
        default:
            break;
    }
    (void)modelNamePtr;
    return RAC_SUCCESS;
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racAnalyticsEventEmitLlmModel(
    JNIEnv* env, jclass clazz, jint eventType, jstring modelId, jstring modelName,
    jlong modelSizeBytes, jdouble durationMs, jint framework, jint errorCode,
    jstring errorMessage) {
    std::string modelIdStr = getCString(env, modelId);
    std::string modelNameStorage;
    std::string errorMsgStorage;
    const char* modelNamePtr = getNullableCString(env, modelName, modelNameStorage);
    const char* errorMsgPtr = getNullableCString(env, errorMessage, errorMsgStorage);

    (void)modelSizeBytes;  // load events carry duration/framework; size is download-only
    const char* modelIdPtr = modelIdStr.c_str();
    const auto fw = static_cast<rac_inference_framework_t>(framework);

    switch (eventType) {
        case kEvtLlmModelLoadCompleted:
            rac::events::emit_llm_model_load_completed(modelIdPtr, modelNamePtr, durationMs, fw);
            break;
        case kEvtLlmModelLoadFailed:
            rac::events::emit_llm_model_load_failed(modelIdPtr, modelNamePtr, durationMs, fw,
                                                    static_cast<rac_result_t>(errorCode),
                                                    errorMsgPtr);
            break;
        case kEvtLlmModelUnloaded:
            rac::events::emit_llm_model_unloaded(modelIdPtr);
            break;
        case kEvtLlmModelLoadStarted:
        default:
            // LOAD_STARTED has no telemetry payload of interest; skip to match the
            // component-side behavior (started carries no metrics).
            break;
    }
    return RAC_SUCCESS;
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racAnalyticsEventEmitSttTranscription(
    JNIEnv* env, jclass clazz, jint eventType, jstring transcriptionId, jstring modelId,
    jstring modelName, jstring text, jfloat confidence, jdouble durationMs, jdouble audioLengthMs,
    jint audioSizeBytes, jint wordCount, jdouble realTimeFactor, jstring language, jint sampleRate,
    jboolean isStreaming, jint framework, jint errorCode, jstring errorMessage) {
    std::string transIdStr = getCString(env, transcriptionId);
    std::string modelIdStr = getCString(env, modelId);
    std::string modelNameStorage, textStorage, langStorage, errorMsgStorage;
    const char* modelNamePtr = getNullableCString(env, modelName, modelNameStorage);
    const char* textPtr = getNullableCString(env, text, textStorage);
    const char* langPtr = getNullableCString(env, language, langStorage);
    const char* errorMsgPtr = getNullableCString(env, errorMessage, errorMsgStorage);

    const char* transIdPtr = transIdStr.c_str();
    const char* modelIdPtr = modelIdStr.c_str();
    (void)modelNamePtr;
    const auto fw = static_cast<rac_inference_framework_t>(framework);

    switch (eventType) {
        case kEvtSttTranscriptionStarted:
            rac::events::emit_stt_transcription_started(transIdPtr, modelIdPtr, audioLengthMs,
                                                        audioSizeBytes, langPtr,
                                                        isStreaming == JNI_TRUE, sampleRate, fw);
            break;
        case kEvtSttTranscriptionCompleted:
            rac::events::emit_stt_transcription_completed(
                transIdPtr, modelIdPtr, textPtr, confidence, durationMs, audioLengthMs,
                audioSizeBytes, wordCount, realTimeFactor, langPtr, sampleRate, fw);
            break;
        case kEvtSttTranscriptionFailed:
            rac::events::emit_stt_transcription_failed(
                transIdPtr, modelIdPtr, static_cast<rac_result_t>(errorCode), errorMsgPtr);
            break;
        default:
            break;
    }
    return RAC_SUCCESS;
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racAnalyticsEventEmitTtsSynthesis(
    JNIEnv* env, jclass clazz, jint eventType, jstring synthesisId, jstring modelId,
    jstring modelName, jint characterCount, jdouble audioDurationMs, jint audioSizeBytes,
    jdouble processingDurationMs, jdouble charactersPerSecond, jint sampleRate, jint framework,
    jint errorCode, jstring errorMessage) {
    std::string synthIdStr = getCString(env, synthesisId);
    std::string modelIdStr = getCString(env, modelId);
    std::string modelNameStorage, errorMsgStorage;
    const char* modelNamePtr = getNullableCString(env, modelName, modelNameStorage);
    const char* errorMsgPtr = getNullableCString(env, errorMessage, errorMsgStorage);

    const char* synthIdPtr = synthIdStr.c_str();
    const char* modelIdPtr = modelIdStr.c_str();
    (void)modelNamePtr;
    const auto fw = static_cast<rac_inference_framework_t>(framework);

    switch (eventType) {
        case kEvtTtsSynthesisStarted:
            rac::events::emit_tts_synthesis_started(synthIdPtr, modelIdPtr, characterCount,
                                                    sampleRate, fw);
            break;
        case kEvtTtsSynthesisCompleted:
            rac::events::emit_tts_synthesis_completed(
                synthIdPtr, modelIdPtr, characterCount, audioDurationMs, audioSizeBytes,
                processingDurationMs, charactersPerSecond, sampleRate, fw);
            break;
        case kEvtTtsSynthesisFailed:
            rac::events::emit_tts_synthesis_failed(
                synthIdPtr, modelIdPtr, static_cast<rac_result_t>(errorCode), errorMsgPtr);
            break;
        default:
            break;
    }
    return RAC_SUCCESS;
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racAnalyticsEventEmitVad(
    JNIEnv* env, jclass clazz, jint eventType, jdouble speechDurationMs, jfloat energyLevel) {
    (void)env;
    (void)clazz;
    if (eventType == kEvtVadSpeechStarted) {
        rac::events::emit_vad_speech_started(energyLevel);
    } else if (eventType == kEvtVadSpeechEnded) {
        rac::events::emit_vad_speech_ended(speechDurationMs, energyLevel);
    }
    return RAC_SUCCESS;
}

// =============================================================================
// DEV CONFIG API (rac_dev_config.h)
// Mirrors Swift SDK's CppBridge+Environment.swift DevConfig
// =============================================================================

JNIEXPORT jboolean JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racDevConfigIsAvailable(JNIEnv* env,
                                                                                 jclass clazz) {
    return rac_dev_config_is_available() ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT jstring JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racDevConfigGetSupabaseUrl(JNIEnv* env,
                                                                                    jclass clazz) {
    const char* url = rac_dev_config_get_supabase_url();
    if (url == nullptr || strlen(url) == 0) {
        return nullptr;
    }
    return env->NewStringUTF(url);
}

JNIEXPORT jstring JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racDevConfigGetSupabaseKey(JNIEnv* env,
                                                                                    jclass clazz) {
    const char* key = rac_dev_config_get_supabase_key();
    if (key == nullptr || strlen(key) == 0) {
        return nullptr;
    }
    return env->NewStringUTF(key);
}

JNIEXPORT jstring JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racDevConfigGetBuildToken(JNIEnv* env,
                                                                                   jclass clazz) {
    const char* token = rac_dev_config_get_build_token();
    if (token == nullptr || strlen(token) == 0) {
        return nullptr;
    }
    return env->NewStringUTF(token);
}

JNIEXPORT jboolean JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racDevConfigIsUsableCredential(
    JNIEnv* env, jclass clazz, jstring value) {
    (void)clazz;
    if (value == nullptr) {
        return JNI_FALSE;
    }
    const char* cValue = env->GetStringUTFChars(value, nullptr);
    const jboolean result = rac_dev_config_is_usable_credential(cValue) ? JNI_TRUE : JNI_FALSE;
    env->ReleaseStringUTFChars(value, cValue);
    return result;
}

JNIEXPORT jboolean JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racDevConfigIsUsableHttpUrl(
    JNIEnv* env, jclass clazz, jstring value) {
    (void)clazz;
    if (value == nullptr) {
        return JNI_FALSE;
    }
    const char* cValue = env->GetStringUTFChars(value, nullptr);
    const jboolean result = rac_dev_config_is_usable_http_url(cValue) ? JNI_TRUE : JNI_FALSE;
    env->ReleaseStringUTFChars(value, cValue);
    return result;
}

// =============================================================================
// SDK Configuration Initialization
// =============================================================================

/**
 * Initialize SDK configuration with version and platform info.
 * This must be called during SDK initialization for device registration
 * to include the correct sdk_version (instead of "unknown").
 *
 * @param environment Environment (0=development, 1=staging, 2=production)
 * @param deviceId Device ID string
 * @param platform Platform string (e.g., "android")
 * @param sdkVersion SDK version string (e.g., "0.1.0")
 * @param apiKey API key (can be empty for development)
 * @param baseUrl Base URL (can be empty for development)
 * @return 0 on success, error code on failure
 */
JNIEXPORT jint JNICALL Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racSdkInit(
    JNIEnv* env, jclass clazz, jint environment, jstring deviceId, jstring platform,
    jstring sdkVersion, jstring apiKey, jstring baseUrl) {
    rac_sdk_config_t config = {};
    config.environment = static_cast<rac_environment_t>(environment);

    std::string deviceIdStr = getCString(env, deviceId);
    std::string platformStr = getCString(env, platform);
    std::string sdkVersionStr = getCString(env, sdkVersion);
    std::string apiKeyStr = getCString(env, apiKey);
    std::string baseUrlStr = getCString(env, baseUrl);

    config.device_id = deviceIdStr.empty() ? nullptr : deviceIdStr.c_str();
    config.platform = platformStr.empty() ? "android" : platformStr.c_str();
    config.sdk_version = sdkVersionStr.empty() ? nullptr : sdkVersionStr.c_str();
    config.api_key = apiKeyStr.empty() ? nullptr : apiKeyStr.c_str();
    config.base_url = baseUrlStr.empty() ? nullptr : baseUrlStr.c_str();

    LOGi("racSdkInit: env=%d, platform=%s, sdk_version=%s", environment,
         config.platform ? config.platform : "(null)",
         config.sdk_version ? config.sdk_version : "(null)");

    rac_validation_result_t result = rac_sdk_init(&config);

    if (result == RAC_VALIDATION_OK) {
        LOGi("racSdkInit: SDK config initialized successfully");
    } else {
        LOGe("racSdkInit: Failed with result %d", result);
    }

    return static_cast<jint>(result);
}

JNIEXPORT void JNICALL Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racSdkSetClientInfo(
    JNIEnv* env, jclass clazz, jstring sdkBinding, jstring appIdentifier, jstring appName,
    jstring appVersion, jstring appBuild, jstring locale, jstring timezone) {
    (void)clazz;

    std::string sdkBindingStr = getCString(env, sdkBinding);
    std::string appIdentifierStr = getCString(env, appIdentifier);
    std::string appNameStr = getCString(env, appName);
    std::string appVersionStr = getCString(env, appVersion);
    std::string appBuildStr = getCString(env, appBuild);
    std::string localeStr = getCString(env, locale);
    std::string timezoneStr = getCString(env, timezone);

    rac_client_info_t info = {};
    info.sdk_binding = sdkBindingStr.empty() ? nullptr : sdkBindingStr.c_str();
    info.app_identifier = appIdentifierStr.empty() ? nullptr : appIdentifierStr.c_str();
    info.app_name = appNameStr.empty() ? nullptr : appNameStr.c_str();
    info.app_version = appVersionStr.empty() ? nullptr : appVersionStr.c_str();
    info.app_build = appBuildStr.empty() ? nullptr : appBuildStr.c_str();
    info.locale = localeStr.empty() ? nullptr : localeStr.c_str();
    info.timezone = timezoneStr.empty() ? nullptr : timezoneStr.c_str();

    rac_sdk_set_client_info(&info);
}

// =============================================================================
// TOOL CALLING API (rac_tool_calling.h)
// Mirrors Swift SDK's CppBridge+ToolCalling.swift
//
// The legacy JSON-stringy family (racToolCallParse, FormatPromptJson,
// FormatPromptJsonWithFormat, FormatPromptJsonWithFormatName,
// BuildInitialPrompt, BuildFollowupPrompt, NormalizeJson) was deleted.
// Kotlin now calls the proto-byte entries
// (`racToolCallParseProto`, `racToolCallFormatPromptProto`,
// `racToolCallValidateProto`).
// =============================================================================

JNIEXPORT jbyteArray JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racToolCallParseProto(
    JNIEnv* env, jclass clazz, jbyteArray requestProto) {
    return callProtoBufferFn(env, requestProto, rac_tool_call_parse_proto, "racToolCallParseProto");
}

JNIEXPORT jbyteArray JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racToolCallFormatPromptProto(
    JNIEnv* env, jclass clazz, jbyteArray requestProto) {
    return callProtoBufferFn(env, requestProto, rac_tool_call_format_prompt_proto,
                             "racToolCallFormatPromptProto");
}

JNIEXPORT jbyteArray JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racToolCallValidateProto(
    JNIEnv* env, jclass clazz, jbyteArray requestProto) {
    return callProtoBufferFn(env, requestProto, rac_tool_call_validate_proto,
                             "racToolCallValidateProto");
}

// =============================================================================
// File Manager JNI Wrappers
// =============================================================================

// Global reference for file callbacks object
static jobject g_file_callbacks_obj = nullptr;
static jmethodID g_fc_create_directory = nullptr;
static jmethodID g_fc_delete_path = nullptr;
static jmethodID g_fc_list_directory = nullptr;
static jmethodID g_fc_path_exists = nullptr;
static jmethodID g_fc_is_directory = nullptr;
static jmethodID g_fc_get_file_size = nullptr;
static jmethodID g_fc_get_available_space = nullptr;
static jmethodID g_fc_get_total_space = nullptr;

// JNI file callback implementations
static rac_result_t jni_fc_create_directory(const char* path, int recursive, void* user_data) {
    JNIEnv* env = getJNIEnv();
    if (env == nullptr || g_file_callbacks_obj == nullptr)
        return RAC_ERROR_NOT_INITIALIZED;
    jstring jPath = env->NewStringUTF(path);
    jint result = env->CallIntMethod(g_file_callbacks_obj, g_fc_create_directory, jPath,
                                     static_cast<jboolean>(recursive != 0));
    env->DeleteLocalRef(jPath);
    return static_cast<rac_result_t>(result);
}

static rac_result_t jni_fc_delete_path(const char* path, int recursive, void* user_data) {
    JNIEnv* env = getJNIEnv();
    if (env == nullptr || g_file_callbacks_obj == nullptr)
        return RAC_ERROR_NOT_INITIALIZED;
    jstring jPath = env->NewStringUTF(path);
    jint result = env->CallIntMethod(g_file_callbacks_obj, g_fc_delete_path, jPath,
                                     static_cast<jboolean>(recursive != 0));
    env->DeleteLocalRef(jPath);
    return static_cast<rac_result_t>(result);
}

static rac_result_t jni_fc_list_directory(const char* path, char*** out_entries, size_t* out_count,
                                          void* user_data) {
    JNIEnv* env = getJNIEnv();
    if (env == nullptr || g_file_callbacks_obj == nullptr)
        return RAC_ERROR_NOT_INITIALIZED;

    jstring jPath = env->NewStringUTF(path);
    jobjectArray jEntries = static_cast<jobjectArray>(
        env->CallObjectMethod(g_file_callbacks_obj, g_fc_list_directory, jPath));
    env->DeleteLocalRef(jPath);

    if (jEntries == nullptr) {
        *out_entries = nullptr;
        *out_count = 0;
        return RAC_ERROR_FILE_NOT_FOUND;
    }

    jsize count = env->GetArrayLength(jEntries);
    auto** entries = static_cast<char**>(std::malloc(count * sizeof(char*)));
    if (entries == nullptr) {
        env->DeleteLocalRef(jEntries);
        return RAC_ERROR_OUT_OF_MEMORY;
    }

    for (jsize i = 0; i < count; i++) {
        auto jEntry = static_cast<jstring>(env->GetObjectArrayElement(jEntries, i));
        const char* entryChars = env->GetStringUTFChars(jEntry, nullptr);
        entries[i] = strdup(entryChars);
        env->ReleaseStringUTFChars(jEntry, entryChars);
        env->DeleteLocalRef(jEntry);
    }

    env->DeleteLocalRef(jEntries);
    *out_entries = entries;
    *out_count = static_cast<size_t>(count);
    return RAC_SUCCESS;
}

static void jni_fc_free_entries(char** entries, size_t count, void* user_data) {
    if (entries == nullptr)
        return;
    for (size_t i = 0; i < count; i++) {
        std::free(entries[i]);
    }
    // free() takes void*; the multilevel cast is intentional.
    // NOLINTNEXTLINE(bugprone-multi-level-implicit-pointer-conversion)
    std::free(entries);
}

static rac_bool_t jni_fc_path_exists(const char* path, rac_bool_t* out_is_directory,
                                     void* user_data) {
    JNIEnv* env = getJNIEnv();
    if (env == nullptr || g_file_callbacks_obj == nullptr)
        return RAC_FALSE;

    jstring jPath = env->NewStringUTF(path);
    jboolean exists = env->CallBooleanMethod(g_file_callbacks_obj, g_fc_path_exists, jPath);

    if (out_is_directory != nullptr && exists) {
        jboolean isDir = env->CallBooleanMethod(g_file_callbacks_obj, g_fc_is_directory, jPath);
        *out_is_directory = isDir ? RAC_TRUE : RAC_FALSE;
    }

    env->DeleteLocalRef(jPath);
    return exists ? RAC_TRUE : RAC_FALSE;
}

static int64_t jni_fc_get_file_size(const char* path, void* user_data) {
    JNIEnv* env = getJNIEnv();
    if (env == nullptr || g_file_callbacks_obj == nullptr)
        return -1;
    jstring jPath = env->NewStringUTF(path);
    jlong size = env->CallLongMethod(g_file_callbacks_obj, g_fc_get_file_size, jPath);
    env->DeleteLocalRef(jPath);
    return static_cast<int64_t>(size);
}

static int64_t jni_fc_get_available_space(void* user_data) {
    JNIEnv* env = getJNIEnv();
    if (env == nullptr || g_file_callbacks_obj == nullptr)
        return -1;
    return static_cast<int64_t>(
        env->CallLongMethod(g_file_callbacks_obj, g_fc_get_available_space));
}

static int64_t jni_fc_get_total_space(void* user_data) {
    JNIEnv* env = getJNIEnv();
    if (env == nullptr || g_file_callbacks_obj == nullptr)
        return -1;
    return static_cast<int64_t>(env->CallLongMethod(g_file_callbacks_obj, g_fc_get_total_space));
}

/**
 * Build rac_file_callbacks_t from registered JNI callbacks.
 */
static rac_file_callbacks_t build_jni_file_callbacks() {
    rac_file_callbacks_t cb = {};
    cb.create_directory = jni_fc_create_directory;
    cb.delete_path = jni_fc_delete_path;
    cb.list_directory = jni_fc_list_directory;
    cb.free_entries = jni_fc_free_entries;
    cb.path_exists = jni_fc_path_exists;
    cb.get_file_size = jni_fc_get_file_size;
    cb.get_available_space = jni_fc_get_available_space;
    cb.get_total_space = jni_fc_get_total_space;
    cb.user_data = nullptr;
    return cb;
}

static int64_t jni_storage_calculate_dir_size(const char* path, void* user_data) {
    rac_file_callbacks_t cb = build_jni_file_callbacks();
    int64_t size = 0;
    rac_result_t result = rac_file_manager_calculate_dir_size(&cb, path ? path : "", &size);
    return RAC_SUCCEEDED(result) ? size : -1;
}

static rac_result_t jni_storage_is_model_loaded(const char* /*model_id*/, rac_bool_t* out_is_loaded,
                                                void* /*user_data*/) {
    if (out_is_loaded != nullptr) {
        *out_is_loaded = RAC_FALSE;
    }
    return RAC_SUCCESS;
}

static rac_result_t jni_storage_unload_model(const char* /*model_id*/, void* /*user_data*/) {
    return RAC_SUCCESS;
}

static rac_storage_callbacks_t build_jni_storage_callbacks() {
    rac_storage_callbacks_t cb = {};
    cb.calculate_dir_size = jni_storage_calculate_dir_size;
    cb.get_file_size = jni_fc_get_file_size;
    cb.path_exists = jni_fc_path_exists;
    cb.get_available_space = jni_fc_get_available_space;
    cb.get_total_space = jni_fc_get_total_space;
    cb.delete_path = jni_fc_delete_path;
    cb.is_model_loaded = jni_storage_is_model_loaded;
    cb.unload_model = jni_storage_unload_model;
    cb.user_data = nullptr;
    return cb;
}

using StorageProtoCallFn = rac_result_t (*)(rac_storage_analyzer_handle_t,
                                            rac_model_registry_handle_t, const uint8_t*, size_t,
                                            rac_proto_buffer_t*);

static jbyteArray callStorageProtoFn(JNIEnv* env, jbyteArray requestProto,
                                     StorageProtoCallFn callFn, const char* operation) {
    if (requestProto == nullptr) {
        return nullptr;
    }

    rac_model_registry_handle_t registry = rac_get_model_registry();
    if (!registry) {
        LOGe("%s: model registry not initialized", operation);
        return nullptr;
    }

    rac_storage_callbacks_t callbacks = build_jni_storage_callbacks();
    rac_storage_analyzer_handle_t analyzer = nullptr;
    rac_result_t createResult = rac_storage_analyzer_create(&callbacks, &analyzer);
    if (RAC_FAILED(createResult) || analyzer == nullptr) {
        LOGe("%s: failed to create storage analyzer: %d", operation, createResult);
        return nullptr;
    }

    const jsize length = env->GetArrayLength(requestProto);
    jbyte* requestBytes = length > 0 ? env->GetByteArrayElements(requestProto, nullptr) : nullptr;
    if (length > 0 && requestBytes == nullptr) {
        rac_storage_analyzer_destroy(analyzer);
        LOGe("%s: failed to access JNI byte array", operation);
        return nullptr;
    }

    rac_proto_buffer_t result = {};
    rac_proto_buffer_init(&result);
    rac_result_t rc = callFn(analyzer, registry, reinterpret_cast<const uint8_t*>(requestBytes),
                             static_cast<size_t>(length), &result);
    if (requestBytes != nullptr) {
        env->ReleaseByteArrayElements(requestProto, requestBytes, JNI_ABORT);
    }
    rac_storage_analyzer_destroy(analyzer);
    if (RAC_FAILED(rc) && result.status == RAC_SUCCESS) {
        rac_proto_buffer_set_error(&result, rc, operation);
    }
    return makeProtoBufferByteArray(env, &result, operation);
}

// Register file callbacks object from Kotlin
JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_nativeFileManagerRegisterCallbacks(
    JNIEnv* env, jobject /* thiz */, jobject callbacksObj) {
    if (callbacksObj == nullptr)
        return RAC_ERROR_NULL_POINTER;

    // Store global reference
    if (g_file_callbacks_obj != nullptr) {
        env->DeleteGlobalRef(g_file_callbacks_obj);
    }
    g_file_callbacks_obj = env->NewGlobalRef(callbacksObj);

    // Cache method IDs
    jclass cls = env->GetObjectClass(callbacksObj);
    g_fc_create_directory = env->GetMethodID(cls, "createDirectory", "(Ljava/lang/String;Z)I");
    g_fc_delete_path = env->GetMethodID(cls, "deletePath", "(Ljava/lang/String;Z)I");
    g_fc_list_directory =
        env->GetMethodID(cls, "listDirectory", "(Ljava/lang/String;)[Ljava/lang/String;");
    g_fc_path_exists = env->GetMethodID(cls, "pathExists", "(Ljava/lang/String;)Z");
    g_fc_is_directory = env->GetMethodID(cls, "isDirectory", "(Ljava/lang/String;)Z");
    g_fc_get_file_size = env->GetMethodID(cls, "getFileSize", "(Ljava/lang/String;)J");
    g_fc_get_available_space = env->GetMethodID(cls, "getAvailableSpace", "()J");
    g_fc_get_total_space = env->GetMethodID(cls, "getTotalSpace", "()J");
    env->DeleteLocalRef(cls);

    LOGi("File manager callbacks registered");
    return RAC_SUCCESS;
}

// Clear cache
JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_nativeFileManagerClearCache(
    JNIEnv* env, jobject /* thiz */) {
    rac_file_callbacks_t cb = build_jni_file_callbacks();
    return static_cast<jint>(rac_file_manager_clear_cache(&cb));
}

// Clear temp
JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_nativeFileManagerClearTemp(
    JNIEnv* env, jobject /* thiz */) {
    rac_file_callbacks_t cb = build_jni_file_callbacks();
    return static_cast<jint>(rac_file_manager_clear_temp(&cb));
}

JNIEXPORT jbyteArray JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racStorageInfoProto(
    JNIEnv* env, jclass clazz, jbyteArray requestProto) {
    return callStorageProtoFn(env, requestProto, rac_storage_analyzer_info_proto,
                              "racStorageInfoProto");
}

JNIEXPORT jbyteArray JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racStorageAvailabilityProto(
    JNIEnv* env, jclass clazz, jbyteArray requestProto) {
    return callStorageProtoFn(env, requestProto, rac_storage_analyzer_availability_proto,
                              "racStorageAvailabilityProto");
}

JNIEXPORT jbyteArray JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racStorageDeletePlanProto(
    JNIEnv* env, jclass clazz, jbyteArray requestProto) {
    return callStorageProtoFn(env, requestProto, rac_storage_analyzer_delete_plan_proto,
                              "racStorageDeletePlanProto");
}

JNIEXPORT jbyteArray JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racStorageDeleteProto(
    JNIEnv* env, jclass clazz, jbyteArray requestProto) {
    return callStorageProtoFn(env, requestProto, rac_storage_analyzer_delete_proto,
                              "racStorageDeleteProto");
}

static std::mutex g_sdk_event_listener_mutex;
static std::unordered_map<uint64_t, jobject> g_sdk_event_listeners;

static void sdk_event_jni_callback(const uint8_t* proto_bytes, size_t proto_size, void* user_data) {
    auto* listener = static_cast<jobject>(user_data);
    JNIEnv* env = getJNIEnv();
    invokeProtoListener(env, listener, proto_bytes, proto_size, "sdkEventCallback");
}

JNIEXPORT jlong JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racSdkEventSubscribe(JNIEnv* env,
                                                                              jclass clazz,
                                                                              jobject listener) {
    if (listener == nullptr) {
        return 0;
    }
    RAC_JNI_TRY {
        jobject globalListener = env->NewGlobalRef(listener);
        if (globalListener == nullptr) {
            return 0;
        }
        uint64_t subscriptionId = rac_sdk_event_subscribe(sdk_event_jni_callback, globalListener);
        if (subscriptionId == 0) {
            env->DeleteGlobalRef(globalListener);
            return 0;
        }
        std::exception_ptr insertionError;
        {
            std::lock_guard<std::mutex> lock(g_sdk_event_listener_mutex);
            // commons-056: map allocation can throw std::bad_alloc on low-mem
            // devices; the surrounding try/catch translates that to 0 (the
            // INVALID_SUBSCRIPTION sentinel) and releases the GlobalRef.
            try {
                g_sdk_event_listeners[subscriptionId] = globalListener;
            } catch (...) {
                insertionError = std::current_exception();
            }
        }
        if (insertionError != nullptr) {
            rac_sdk_event_unsubscribe(subscriptionId);
            rac_sdk_event_quiesce();
            env->DeleteGlobalRef(globalListener);
            std::rethrow_exception(insertionError);
        }
        return static_cast<jlong>(subscriptionId);
    }
    RAC_JNI_CATCH_RET(0L, 0L)
}

JNIEXPORT void JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racSdkEventUnsubscribe(
    JNIEnv* env, jclass clazz, jlong subscriptionId) {
    const uint64_t id = static_cast<uint64_t>(subscriptionId);
    jobject listener = nullptr;
    {
        std::lock_guard<std::mutex> lock(g_sdk_event_listener_mutex);
        auto it = g_sdk_event_listeners.find(id);
        if (it != g_sdk_event_listeners.end()) {
            listener = it->second;
            g_sdk_event_listeners.erase(it);
        }
    }
    rac_sdk_event_unsubscribe(id);
    if (listener != nullptr) {
        rac_sdk_event_quiesce();
        env->DeleteGlobalRef(listener);
    }
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racSdkEventPublishProto(
    JNIEnv* env, jclass clazz, jbyteArray eventProto) {
    if (eventProto == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }
    const jsize length = env->GetArrayLength(eventProto);
    jbyte* bytes = length > 0 ? env->GetByteArrayElements(eventProto, nullptr) : nullptr;
    if (length > 0 && bytes == nullptr) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }
    rac_result_t result = rac_sdk_event_publish_proto(reinterpret_cast<const uint8_t*>(bytes),
                                                      static_cast<size_t>(length));
    if (bytes != nullptr) {
        env->ReleaseByteArrayElements(eventProto, bytes, JNI_ABORT);
    }
    return static_cast<jint>(result);
}

JNIEXPORT jbyteArray JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racSdkEventPoll(JNIEnv* env,
                                                                         jclass clazz) {
    rac_proto_buffer_t event = {};
    rac_proto_buffer_init(&event);
    rac_result_t result = rac_sdk_event_poll(&event);
    if (RAC_FAILED(result)) {
        rac_proto_buffer_free(&event);
        return nullptr;
    }
    return makeProtoBufferByteArray(env, &event, "racSdkEventPoll");
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racSdkEventPublishFailure(
    JNIEnv* env, jclass clazz, jint errorCode, jstring message, jstring component,
    jstring operation, jboolean recoverable) {
    std::string messageStorage = getCString(env, message);
    std::string componentStorage = getCString(env, component);
    std::string operationStorage = getCString(env, operation);
    return static_cast<jint>(rac_sdk_event_publish_failure(
        static_cast<rac_result_t>(errorCode), messageStorage.c_str(), componentStorage.c_str(),
        operationStorage.c_str(), recoverable ? RAC_TRUE : RAC_FALSE));
}

static jobject g_download_proto_listener = nullptr;
static std::mutex g_download_proto_listener_mutex;

static void download_proto_jni_callback(const uint8_t* proto_bytes, size_t proto_size,
                                        void* user_data) {
    JNIEnv* env = getJNIEnv();
    jobject listener = nullptr;
    {
        std::lock_guard<std::mutex> lock(g_download_proto_listener_mutex);
        if (env != nullptr && g_download_proto_listener != nullptr) {
            listener = env->NewLocalRef(g_download_proto_listener);
        }
    }
    invokeProtoListener(env, listener, proto_bytes, proto_size, "downloadProtoCallback");
    if (env != nullptr && listener != nullptr) {
        env->DeleteLocalRef(listener);
    }
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racDownloadSetProgressProtoCallback(
    JNIEnv* env, jclass clazz, jobject listener) {
    std::lock_guard<std::mutex> lock(g_download_proto_listener_mutex);
    if (g_download_proto_listener != nullptr) {
        env->DeleteGlobalRef(g_download_proto_listener);
        g_download_proto_listener = nullptr;
    }
    if (listener == nullptr) {
        return static_cast<jint>(rac_download_set_progress_proto_callback(nullptr, nullptr));
    }
    g_download_proto_listener = env->NewGlobalRef(listener);
    return static_cast<jint>(
        rac_download_set_progress_proto_callback(download_proto_jni_callback, nullptr));
}

JNIEXPORT jbyteArray JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racDownloadPlanProto(
    JNIEnv* env, jclass clazz, jbyteArray requestProto) {
    return callProtoBufferFn(env, requestProto, rac_download_plan_proto, "racDownloadPlanProto");
}

JNIEXPORT jbyteArray JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racDownloadStartProto(
    JNIEnv* env, jclass clazz, jbyteArray requestProto) {
    return callProtoBufferFn(env, requestProto, rac_download_start_proto, "racDownloadStartProto");
}

JNIEXPORT jbyteArray JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racDownloadCancelProto(
    JNIEnv* env, jclass clazz, jbyteArray requestProto) {
    return callProtoBufferFn(env, requestProto, rac_download_cancel_proto,
                             "racDownloadCancelProto");
}

JNIEXPORT jbyteArray JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racDownloadResumeProto(
    JNIEnv* env, jclass clazz, jbyteArray requestProto) {
    return callProtoBufferFn(env, requestProto, rac_download_resume_proto,
                             "racDownloadResumeProto");
}

JNIEXPORT jbyteArray JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racDownloadProgressPollProto(
    JNIEnv* env, jclass clazz, jbyteArray requestProto) {
    return callProtoBufferFn(env, requestProto, rac_download_progress_poll_proto,
                             "racDownloadProgressPollProto");
}

// =============================================================================
// JNI FUNCTIONS - Auth Manager (rac_auth_*)
// =============================================================================
//
// F3 fix: racAuthInit now installs a rac_secure_storage_t vtable backed by
// the existing platform-adapter secure-storage callbacks (secureGet/
// secureSet/secureDelete on CppBridgePlatformAdapter, which delegate to
// AndroidSecureStorage under the hood). Without this wiring,
// rac_auth_save_tokens / rac_auth_clear were no-ops and tokens were lost
// on every process restart.
//
// Previous behavior passed `nullptr` and commented about a "v2.1-2
// follow-up that adds the KeyStoreBridge". The follow-up is this function.
//
// All thunks here are JvmStatic on RunAnywhereBridge (jclass receiver).

// =============================================================================
// rac_secure_storage_t adapter over the JNI platform adapter
// =============================================================================
//
// The rac_platform_adapter_t secure-storage callbacks (jni_secure_*_callback
// above) use base64-encoded bytes via the Kotlin secureGet/secureSet/
// secureDelete instance methods. rac_auth_manager expects plain C strings
// with a `int (*retrieve)(key, buf, buf_size, ctx)` signature that writes
// a NUL-terminated value into the provided buffer and returns the length.
//
// These shims call the platform adapter's JNI methods directly (NOT the
// base64 wrappers) so we pass plain strings end-to-end between the auth
// manager and the Kotlin PlatformSecureStorage delegate.

static int auth_storage_store(const char* key, const char* value, void* /*ctx*/) {
    JNIEnv* env = getJNIEnv();
    std::lock_guard<std::recursive_mutex> lock(g_adapter_mutex);
    if (env == nullptr || g_platform_adapter == nullptr || g_method_secure_set == nullptr) {
        return -1;
    }
    jstring jKey = env->NewStringUTF(key ? key : "");
    if (jKey == nullptr) {
        jniClearPendingException(env);
        return -1;
    }
    // Auth-manager values are already base64-safe (random bytes from JWTs);
    // the platform adapter's secureSet takes base64, so we base64 the value
    // here. We'd pay the same cost either way; doing it here keeps the
    // existing rac_platform_adapter_t contract unchanged.
    jclass base64Class = env->FindClass("android/util/Base64");
    if (base64Class == nullptr) {
        jniClearPendingException(env);
        env->DeleteLocalRef(jKey);
        return -1;
    }
    jmethodID encodeToString =
        env->GetStaticMethodID(base64Class, "encodeToString", "([BI)Ljava/lang/String;");
    if (encodeToString == nullptr) {
        jniClearPendingException(env);
        env->DeleteLocalRef(base64Class);
        env->DeleteLocalRef(jKey);
        return -1;
    }
    const size_t len = value ? strlen(value) : 0;
    if (len > static_cast<size_t>(std::numeric_limits<jsize>::max())) {
        env->DeleteLocalRef(base64Class);
        env->DeleteLocalRef(jKey);
        return -1;
    }
    jbyteArray raw = env->NewByteArray(static_cast<jsize>(len));
    if (raw == nullptr) {
        jniClearPendingException(env);
        env->DeleteLocalRef(base64Class);
        env->DeleteLocalRef(jKey);
        return -1;
    }
    env->SetByteArrayRegion(raw, 0, static_cast<jsize>(len),
                            reinterpret_cast<const jbyte*>(value ? value : ""));
    if (jniClearPendingException(env)) {
        env->DeleteLocalRef(raw);
        env->DeleteLocalRef(base64Class);
        env->DeleteLocalRef(jKey);
        return -1;
    }
    jstring encoded = static_cast<jstring>(
        env->CallStaticObjectMethod(base64Class, encodeToString, raw, /*NO_WRAP=*/2));
    if (jniClearPendingException(env) || encoded == nullptr) {
        env->DeleteLocalRef(raw);
        env->DeleteLocalRef(base64Class);
        env->DeleteLocalRef(jKey);
        return -1;
    }
    const jboolean ok =
        env->CallBooleanMethod(g_platform_adapter, g_method_secure_set, jKey, encoded);
    const bool call_failed = jniClearPendingException(env);
    env->DeleteLocalRef(encoded);
    env->DeleteLocalRef(raw);
    env->DeleteLocalRef(base64Class);
    env->DeleteLocalRef(jKey);
    return !call_failed && ok == JNI_TRUE ? 0 : -1;
}

static int auth_storage_retrieve(const char* key, char* out_value, size_t buffer_size,
                                 void* /*ctx*/) {
    if (out_value == nullptr || buffer_size == 0)
        return RAC_ERROR_INVALID_ARGUMENT;
    JNIEnv* env = getJNIEnv();
    std::lock_guard<std::recursive_mutex> lock(g_adapter_mutex);
    if (env == nullptr || g_platform_adapter == nullptr || g_method_secure_get == nullptr) {
        return RAC_ERROR_ADAPTER_NOT_SET;
    }

    jstring jKey = env->NewStringUTF(key ? key : "");
    if (jKey == nullptr) {
        jniClearPendingException(env);
        return RAC_ERROR_OUT_OF_MEMORY;
    }
    jstring encodedJ =
        static_cast<jstring>(env->CallObjectMethod(g_platform_adapter, g_method_secure_get, jKey));
    env->DeleteLocalRef(jKey);
    if (jniClearPendingException(env)) {
        return RAC_ERROR_SECURE_STORAGE_FAILED;
    }
    if (encodedJ == nullptr) {
        return RAC_ERROR_FILE_NOT_FOUND;
    }

    // Decode the base64 payload back to bytes
    jclass base64Class = env->FindClass("android/util/Base64");
    int written = RAC_ERROR_SECURE_STORAGE_FAILED;
    if (base64Class != nullptr) {
        jmethodID decode = env->GetStaticMethodID(base64Class, "decode", "(Ljava/lang/String;I)[B");
        if (decode != nullptr) {
            jbyteArray raw = static_cast<jbyteArray>(
                env->CallStaticObjectMethod(base64Class, decode, encodedJ, /*NO_WRAP=*/2));
            if (!jniClearPendingException(env) && raw != nullptr) {
                jsize len = env->GetArrayLength(raw);
                if (len <= 0) {
                    written = RAC_ERROR_SECURE_STORAGE_FAILED;
                } else if (static_cast<size_t>(len) + 1 > buffer_size) {
                    written = RAC_ERROR_BUFFER_TOO_SMALL;
                } else {
                    env->GetByteArrayRegion(raw, 0, len, reinterpret_cast<jbyte*>(out_value));
                    if (jniClearPendingException(env)) {
                        written = RAC_ERROR_SECURE_STORAGE_FAILED;
                    } else {
                        out_value[len] = '\0';
                        written = static_cast<int>(len);
                    }
                }
                env->DeleteLocalRef(raw);
            }
        } else {
            jniClearPendingException(env);
        }
        env->DeleteLocalRef(base64Class);
    } else {
        jniClearPendingException(env);
    }
    env->DeleteLocalRef(encodedJ);
    return written;
}

static int auth_storage_delete(const char* key, void* /*ctx*/) {
    JNIEnv* env = getJNIEnv();
    std::lock_guard<std::recursive_mutex> lock(g_adapter_mutex);
    if (env == nullptr || g_platform_adapter == nullptr || g_method_secure_delete == nullptr) {
        return -1;
    }
    jstring jKey = env->NewStringUTF(key ? key : "");
    if (jKey == nullptr) {
        jniClearPendingException(env);
        return -1;
    }
    jboolean ok = env->CallBooleanMethod(g_platform_adapter, g_method_secure_delete, jKey);
    env->DeleteLocalRef(jKey);
    return !jniClearPendingException(env) && ok == JNI_TRUE ? 0 : -1;
}

JNIEXPORT jint JNICALL Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racAuthInit(
    JNIEnv* /*env*/, jclass /*cls*/) {
    // Require the platform adapter to have been registered first so our
    // storage vtable has somewhere to delegate. If the Kotlin SDK forgot to
    // register it, fall back to in-memory only rather than crash.
    if (g_platform_adapter == nullptr) {
        RAC_LOG_WARNING(JNI_LOG_TAG,
                        "racAuthInit called before platform adapter registered — "
                        "tokens will NOT persist across process restart");
        rac_auth_init(nullptr);
        return static_cast<jint>(RAC_ERROR_ADAPTER_NOT_SET);
    }

    rac_secure_storage_t storage = {};
    storage.store = auth_storage_store;
    storage.retrieve = auth_storage_retrieve;
    storage.delete_key = auth_storage_delete;
    storage.context = nullptr;
    rac_auth_init(&storage);

    // Restore any previously persisted tokens into the in-memory auth state.
    const int load_result = rac_auth_load_stored_tokens();
    if (load_result == RAC_SUCCESS) {
        RAC_LOG_INFO(JNI_LOG_TAG, "rac_auth_init: restored tokens from secure storage");
    } else if (load_result == RAC_ERROR_FILE_NOT_FOUND) {
        RAC_LOG_DEBUG(JNI_LOG_TAG, "rac_auth_init: no persisted tokens (first launch or cleared)");
    } else {
        RAC_LOG_ERROR(JNI_LOG_TAG, "rac_auth_init: secure storage read failed (rc=%d)",
                      load_result);
    }
    return static_cast<jint>(load_result);
}

JNIEXPORT void JNICALL Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racAuthReset(
    JNIEnv* /*env*/, jclass /*cls*/) {
    rac_auth_reset();
}

JNIEXPORT jboolean JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racAuthIsAuthenticated(JNIEnv* /*env*/,
                                                                                jclass /*cls*/) {
    return rac_auth_is_authenticated() ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT jboolean JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racAuthNeedsRefresh(JNIEnv* /*env*/,
                                                                             jclass /*cls*/) {
    return rac_auth_needs_refresh() ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT jstring JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racAuthGetAccessToken(JNIEnv* env,
                                                                               jclass /*cls*/) {
    const char* token = rac_auth_get_access_token();
    return token ? env->NewStringUTF(token) : nullptr;
}

JNIEXPORT jstring JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racAuthGetDeviceId(JNIEnv* env,
                                                                            jclass /*cls*/) {
    const char* id = rac_auth_get_device_id();
    return id ? env->NewStringUTF(id) : nullptr;
}

JNIEXPORT jstring JNICALL Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racAuthGetUserId(
    JNIEnv* env, jclass /*cls*/) {
    const char* id = rac_auth_get_user_id();
    return id ? env->NewStringUTF(id) : nullptr;
}

JNIEXPORT jstring JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racAuthGetOrganizationId(JNIEnv* env,
                                                                                  jclass /*cls*/) {
    const char* id = rac_auth_get_organization_id();
    return id ? env->NewStringUTF(id) : nullptr;
}

JNIEXPORT jstring JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racAuthBuildAuthenticateRequest(
    JNIEnv* env, jclass /*cls*/, jstring apiKey, jstring baseUrl, jstring deviceId,
    jstring platform, jstring sdkVersion, jint environment) {
    // Maps Kotlin-side credentials to the C rac_sdk_config_t. Kotlin
    // calls this with the AuthenticationRequest fields it already knows
    // about; the C side builds the JSON request body.
    std::string apiKeyStr = getCString(env, apiKey);
    std::string baseUrlStr = getCString(env, baseUrl);
    std::string deviceIdStr = getCString(env, deviceId);
    std::string platformStr = getCString(env, platform);
    std::string sdkVersionStr = getCString(env, sdkVersion);

    rac_sdk_config_t cfg = {};
    cfg.environment = static_cast<rac_environment_t>(environment);
    cfg.api_key = apiKeyStr.empty() ? nullptr : apiKeyStr.c_str();
    cfg.base_url = baseUrlStr.empty() ? nullptr : baseUrlStr.c_str();
    cfg.device_id = deviceIdStr.empty() ? nullptr : deviceIdStr.c_str();
    cfg.platform = platformStr.empty() ? nullptr : platformStr.c_str();
    cfg.sdk_version = sdkVersionStr.empty() ? nullptr : sdkVersionStr.c_str();

    char* json = rac_auth_build_authenticate_request(&cfg);
    if (!json)
        return nullptr;
    jstring out = env->NewStringUTF(json);
    free(json);  // C ABI says caller frees
    return out;
}

JNIEXPORT jstring JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racAuthBuildRefreshRequest(
    JNIEnv* env, jclass /*cls*/) {
    char* json = rac_auth_build_refresh_request();
    if (!json)
        return nullptr;
    jstring out = env->NewStringUTF(json);
    free(json);
    return out;
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racAuthHandleAuthenticateResponse(
    JNIEnv* env, jclass /*cls*/, jstring jsonResponse) {
    std::string json = getCString(env, jsonResponse);
    return static_cast<jint>(rac_auth_handle_authenticate_response(json.c_str()));
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racAuthHandleRefreshResponse(
    JNIEnv* env, jclass /*cls*/, jstring jsonResponse) {
    std::string json = getCString(env, jsonResponse);
    return static_cast<jint>(rac_auth_handle_refresh_response(json.c_str()));
}

// Returns a 2-element String[]: [token-or-null, "true"/"false" needs_refresh].
// Kotlin unpacks via the existing typed wrapper; this avoids out-param games.
JNIEXPORT jobjectArray JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racAuthGetValidToken(JNIEnv* env,
                                                                              jclass /*cls*/) {
    const char* token = nullptr;
    bool needsRefresh = false;
    int rc = rac_auth_get_valid_token(&token, &needsRefresh);
    if (rc < 0)
        return nullptr;

    // commons-122: guard the JNI allocations and release every local ref so the
    // hot auth-refresh path cannot exhaust the per-frame local-ref budget or
    // dereference a NULL class/array if FindClass / NewObjectArray fail.
    jclass strCls = env->FindClass("java/lang/String");
    if (strCls == nullptr) {
        return nullptr;
    }
    jobjectArray arr = env->NewObjectArray(2, strCls, nullptr);
    env->DeleteLocalRef(strCls);
    if (arr == nullptr) {
        return nullptr;
    }
    if (token != nullptr) {
        jstring jToken = env->NewStringUTF(token);
        if (jToken != nullptr) {
            env->SetObjectArrayElement(arr, 0, jToken);
            env->DeleteLocalRef(jToken);
        }
    }
    jstring jNeedsRefresh = env->NewStringUTF(needsRefresh ? "true" : "false");
    if (jNeedsRefresh != nullptr) {
        env->SetObjectArrayElement(arr, 1, jNeedsRefresh);
        env->DeleteLocalRef(jNeedsRefresh);
    }
    return arr;
}

JNIEXPORT jint JNICALL Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racAuthClear(
    JNIEnv* /*env*/, jclass /*cls*/) {
    return static_cast<jint>(rac_auth_clear());
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racAuthLoadStoredTokens(JNIEnv* /*env*/,
                                                                                 jclass /*cls*/) {
    return static_cast<jint>(rac_auth_load_stored_tokens());
}

JNIEXPORT jint JNICALL Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racAuthSaveTokens(
    JNIEnv* /*env*/, jclass /*cls*/) {
    return static_cast<jint>(rac_auth_save_tokens());
}

// =============================================================================
// JNI FUNCTIONS - VoiceAgentStreamAdapter (rac_voice_agent_set_proto_callback)
// =============================================================================
//
// Closes the broken Kotlin streaming path
// the 3-agent audit flagged: VoiceAgentStreamAdapter.kt declared
// nativeRegisterCallback / nativeUnregisterCallback with no matching JNI
// symbols, which would throw UnsatisfiedLinkError at runtime.
//
// Pattern: one registration = one heap-allocated VaStreamCallbackCtx holding
// a global ref to the Kotlin Function1<ByteArray, Unit> lambda + the cached
// Function1.invoke() method ID. The C trampoline resolves JNIEnv* on the
// fly (audio dispatcher threads are attached via AttachCurrentThread) and
// forwards bytes back to the JVM.
//
// ABI limitation: rac_voice_agent_set_proto_callback has ONE callback slot
// per voice-agent handle. Multiple concurrent stream() calls on the same
// handle will REPLACE each other — documented on the Kotlin companion.

namespace {

struct VaStreamCallbackCtx {
    jobject lambda_ref;    // Global ref to Kotlin Function1<ByteArray, Unit>
    jclass function1_cls;  // Global ref to kotlin.jvm.functions.Function1
    jmethodID invoke_mid;  // Function1.invoke(Object)
};

void va_stream_trampoline(const uint8_t* event_bytes, size_t event_size, void* user_data) {
    if (!user_data || !event_bytes || !g_jvm)
        return;

    auto* ctx = static_cast<VaStreamCallbackCtx*>(user_data);

    JNIEnv* env = nullptr;
    bool needs_detach = false;
    jint getEnvRc = g_jvm->GetEnv(reinterpret_cast<void**>(&env), JNI_VERSION_1_6);
    if (getEnvRc == JNI_EDETACHED) {
        // `void**` cast matches the working GetEnv pattern above and the
        // host-JDK signature on macOS/Linux; Android NDK's `JNIEnv**` is
        // binary-compatible.
        if (g_jvm->AttachCurrentThread(RAC_JNI_ATTACH_ENVPP(&env), nullptr) != JNI_OK) {
            return;
        }
        needs_detach = true;
    } else if (getEnvRc != JNI_OK) {
        return;
    }

    jbyteArray jbytes = env->NewByteArray(static_cast<jsize>(event_size));
    if (jbytes) {
        env->SetByteArrayRegion(jbytes, 0, static_cast<jsize>(event_size),
                                reinterpret_cast<const jbyte*>(event_bytes));
        env->CallObjectMethod(ctx->lambda_ref, ctx->invoke_mid, jbytes);
        if (env->ExceptionCheck()) {
            env->ExceptionDescribe();
            env->ExceptionClear();
        }
        env->DeleteLocalRef(jbytes);
    }

    if (needs_detach) {
        g_jvm->DetachCurrentThread();
    }
}

}  // namespace

JNIEXPORT jlong JNICALL
Java_com_runanywhere_sdk_adapters_VoiceAgentStreamAdapter_00024JniBridge_nativeRegisterCallback(
    JNIEnv* env, jclass /*cls*/, jlong handle, jobject kotlinCallback) {
    if (!kotlinCallback || handle == 0) {
        return 0;  // INVALID_CALLBACK_ID on the Kotlin side
    }

    // 1. Global-ref the lambda so it survives past this thunk.
    jobject lambdaRef = env->NewGlobalRef(kotlinCallback);
    if (!lambdaRef)
        return 0;

    // 2. Resolve + cache Function1.invoke(Object)
    jclass localFunction1 = env->FindClass("kotlin/jvm/functions/Function1");
    if (!localFunction1) {
        env->DeleteGlobalRef(lambdaRef);
        return 0;
    }
    jclass function1Cls = reinterpret_cast<jclass>(env->NewGlobalRef(localFunction1));
    env->DeleteLocalRef(localFunction1);
    jmethodID invokeMid =
        env->GetMethodID(function1Cls, "invoke", "(Ljava/lang/Object;)Ljava/lang/Object;");
    if (!invokeMid) {
        env->DeleteGlobalRef(lambdaRef);
        env->DeleteGlobalRef(function1Cls);
        return 0;
    }

    auto* ctx = new VaStreamCallbackCtx{};
    ctx->lambda_ref = lambdaRef;
    ctx->function1_cls = function1Cls;
    ctx->invoke_mid = invokeMid;

    rac_voice_agent_handle_t racHandle =
        reinterpret_cast<rac_voice_agent_handle_t>(static_cast<uintptr_t>(handle));
    rac_result_t rc = rac_voice_agent_set_proto_callback(racHandle, &va_stream_trampoline, ctx);
    if (rc != RAC_SUCCESS) {
        env->DeleteGlobalRef(ctx->lambda_ref);
        env->DeleteGlobalRef(ctx->function1_cls);
        delete ctx;
        return 0;
    }

    return static_cast<jlong>(reinterpret_cast<uintptr_t>(ctx));
}

JNIEXPORT void JNICALL
Java_com_runanywhere_sdk_adapters_VoiceAgentStreamAdapter_00024JniBridge_nativeUnregisterCallback(
    JNIEnv* env, jclass /*cls*/, jlong handle, jlong callbackId) {
    if (callbackId == 0)
        return;

    rac_voice_agent_handle_t racHandle =
        reinterpret_cast<rac_voice_agent_handle_t>(static_cast<uintptr_t>(handle));
    // commons-059 fix: prevent UAF between in-flight `va_stream_trampoline`
    // and `delete ctx`. The unset clears the slot for FUTURE dispatches but
    // a concurrent dispatcher that already copied the slot can still be
    // mid-CallObjectMethod on `ctx->lambda_ref`. Quiesce spin-waits until
    // every in-flight invocation has returned, mirroring the destroy
    // ordering documented at rac_voice_event_abi.h:97-118 and applied in
    // voice_agent.cpp:250.
    rac_voice_agent_set_proto_callback(racHandle, nullptr, nullptr);
    rac_voice_agent_proto_quiesce();

    auto* ctx = reinterpret_cast<VaStreamCallbackCtx*>(static_cast<uintptr_t>(callbackId));
    if (ctx->lambda_ref)
        env->DeleteGlobalRef(ctx->lambda_ref);
    if (ctx->function1_cls)
        env->DeleteGlobalRef(ctx->function1_cls);
    delete ctx;
}

JNIEXPORT void JNICALL
Java_com_runanywhere_sdk_adapters_VoiceAgentStreamAdapter_00024JniBridge_nativeQuiesce(
    JNIEnv* env, jclass /*cls*/) {
    (void)env;
    rac_voice_agent_proto_quiesce();
}

// =============================================================================
// JNI FUNCTIONS - LLMStreamAdapter (rac_llm_set_stream_proto_callback)
// =============================================================================
//
// commons-161. Mirrors the VoiceAgentStreamAdapter thunks above so the
// generic HandleStreamAdapter can fan one C callback slot out to N Kotlin
// Flow collectors for LLM token streams. Same one-registration-per-handle
// pattern: each register = one heap-allocated LlmStreamCallbackCtx holding a
// global ref to the Kotlin Function1<ByteArray, Unit> lambda + the cached
// Function1.invoke() method ID; the C trampoline resolves JNIEnv* on the fly
// and forwards proto bytes back to the JVM. The matching Kotlin JniBridge
// lives at com.runanywhere.sdk.adapters.LLMStreamAdapter$JniBridge — the
// symbol mangling below ties these thunks to that exact class path.
//
// ABI limitation: rac_llm_set_stream_proto_callback has ONE callback slot per
// LLM handle. Multiple concurrent stream() calls on the same handle REPLACE
// each other — documented on the Kotlin companion.

namespace {

struct LlmStreamCallbackCtx {
    jobject lambda_ref;    // Global ref to Kotlin Function1<ByteArray, Unit>
    jclass function1_cls;  // Global ref to kotlin.jvm.functions.Function1
    jmethodID invoke_mid;  // Function1.invoke(Object)
};

void llm_stream_adapter_trampoline(const uint8_t* event_bytes, size_t event_size, void* user_data) {
    if (!user_data || !event_bytes || !g_jvm)
        return;

    auto* ctx = static_cast<LlmStreamCallbackCtx*>(user_data);

    JNIEnv* env = nullptr;
    bool needs_detach = false;
    jint getEnvRc = g_jvm->GetEnv(reinterpret_cast<void**>(&env), JNI_VERSION_1_6);
    if (getEnvRc == JNI_EDETACHED) {
        // `void**` cast matches the working GetEnv pattern above and the
        // host-JDK signature on macOS/Linux; Android NDK's `JNIEnv**` is
        // binary-compatible.
        if (g_jvm->AttachCurrentThread(RAC_JNI_ATTACH_ENVPP(&env), nullptr) != JNI_OK) {
            return;
        }
        needs_detach = true;
    } else if (getEnvRc != JNI_OK) {
        return;
    }

    jbyteArray jbytes = env->NewByteArray(static_cast<jsize>(event_size));
    if (jbytes) {
        env->SetByteArrayRegion(jbytes, 0, static_cast<jsize>(event_size),
                                reinterpret_cast<const jbyte*>(event_bytes));
        env->CallObjectMethod(ctx->lambda_ref, ctx->invoke_mid, jbytes);
        if (env->ExceptionCheck()) {
            env->ExceptionDescribe();
            env->ExceptionClear();
        }
        env->DeleteLocalRef(jbytes);
    }

    if (needs_detach) {
        g_jvm->DetachCurrentThread();
    }
}

}  // namespace

JNIEXPORT jlong JNICALL
Java_com_runanywhere_sdk_adapters_LLMStreamAdapter_00024JniBridge_nativeRegisterCallback(
    JNIEnv* env, jclass /*cls*/, jlong handle, jobject kotlinCallback) {
    if (!kotlinCallback || handle == 0) {
        return 0;  // INVALID_CALLBACK_ID on the Kotlin side
    }

    // 1. Global-ref the lambda so it survives past this thunk.
    jobject lambdaRef = env->NewGlobalRef(kotlinCallback);
    if (!lambdaRef)
        return 0;

    // 2. Resolve + cache Function1.invoke(Object)
    jclass localFunction1 = env->FindClass("kotlin/jvm/functions/Function1");
    if (!localFunction1) {
        env->DeleteGlobalRef(lambdaRef);
        return 0;
    }
    jclass function1Cls = reinterpret_cast<jclass>(env->NewGlobalRef(localFunction1));
    env->DeleteLocalRef(localFunction1);
    jmethodID invokeMid =
        env->GetMethodID(function1Cls, "invoke", "(Ljava/lang/Object;)Ljava/lang/Object;");
    if (!invokeMid) {
        env->DeleteGlobalRef(lambdaRef);
        env->DeleteGlobalRef(function1Cls);
        return 0;
    }

    auto* ctx = new LlmStreamCallbackCtx{};
    ctx->lambda_ref = lambdaRef;
    ctx->function1_cls = function1Cls;
    ctx->invoke_mid = invokeMid;

    rac_result_t rc = rac_llm_set_stream_proto_callback(handleFromJLong(handle),
                                                        &llm_stream_adapter_trampoline, ctx);
    if (rc != RAC_SUCCESS) {
        env->DeleteGlobalRef(ctx->lambda_ref);
        env->DeleteGlobalRef(ctx->function1_cls);
        delete ctx;
        return 0;
    }

    return static_cast<jlong>(reinterpret_cast<uintptr_t>(ctx));
}

JNIEXPORT void JNICALL
Java_com_runanywhere_sdk_adapters_LLMStreamAdapter_00024JniBridge_nativeUnregisterCallback(
    JNIEnv* env, jclass /*cls*/, jlong handle, jlong callbackId) {
    if (callbackId == 0)
        return;

    // commons-161 / commons-059 parity: prevent UAF between an in-flight
    // `llm_stream_adapter_trampoline` and `delete ctx`. The unset clears the
    // slot for FUTURE dispatches, but a concurrent dispatcher that already
    // copied the slot can still be mid-CallObjectMethod on `ctx->lambda_ref`.
    // Quiesce spin-waits until every in-flight invocation has returned,
    // mirroring the teardown sequence documented at rac_llm_stream.h:88-93 and
    // the VoiceAgent unregister thunk above.
    rac_llm_unset_stream_proto_callback(handleFromJLong(handle));
    rac_llm_proto_quiesce();

    auto* ctx = reinterpret_cast<LlmStreamCallbackCtx*>(static_cast<uintptr_t>(callbackId));
    if (ctx->lambda_ref)
        env->DeleteGlobalRef(ctx->lambda_ref);
    if (ctx->function1_cls)
        env->DeleteGlobalRef(ctx->function1_cls);
    delete ctx;
}

JNIEXPORT void JNICALL
Java_com_runanywhere_sdk_adapters_LLMStreamAdapter_00024JniBridge_nativeQuiesce(JNIEnv* env,
                                                                                jclass /*cls*/) {
    (void)env;
    rac_llm_proto_quiesce();
}

// =============================================================================
// Generated-proto modality ABI thunks
// =============================================================================

JNIEXPORT jbyteArray JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racLlmGenerateProto(
    JNIEnv* env, jclass clazz, jbyteArray requestProto) {
    (void)clazz;
    return callProtoBufferFn(env, requestProto, rac_llm_generate_proto, "racLlmGenerateProto");
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racLlmGenerateStreamProto(
    JNIEnv* env, jclass clazz, jbyteArray requestProto, jobject listener) {
    (void)clazz;
    JByteArrayView request(env, requestProto);
    if (!request.ok)
        return RAC_ERROR_NULL_POINTER;

    jobject globalListener = listener != nullptr ? env->NewGlobalRef(listener) : nullptr;
    ProtoListenerUserData ctx{.listener = globalListener, .operation = "racLlmGenerateStreamProto"};
    rac_result_t rc = rac_llm_generate_stream_proto(
        request.u8(), request.size(), globalListener != nullptr ? proto_void_callback : nullptr,
        globalListener != nullptr ? &ctx : nullptr);
    if (globalListener != nullptr) {
        env->DeleteGlobalRef(globalListener);
    }
    return static_cast<jint>(rc);
}

JNIEXPORT jbyteArray JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racLlmCancelProto(JNIEnv* env,
                                                                           jclass clazz) {
    (void)clazz;
    rac_proto_buffer_t result = {};
    rac_proto_buffer_init(&result);
    rac_result_t rc = rac_llm_cancel_proto(&result);
    return makeProtoCallResult(env, rc, &result, "racLlmCancelProto");
}

// Swift-aligned (Kotlin Bug-11): mirror iOS Swift which uses
// rac_stt_transcribe_lifecycle_proto (no handle, lifecycle-only) for STT
// transcription. Takes a serialized STTTranscriptionRequest and returns
// STTOutput bytes. Resolves the lifecycle-loaded STT model internally.
// The legacy component-handle variants (rac_stt_component_transcribe_proto +
// _stream) are no longer exposed via JNI — Kotlin SDK is lifecycle-only,
// matching Swift.
JNIEXPORT jbyteArray JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racSttTranscribeLifecycleProto(
    JNIEnv* env, jclass clazz, jbyteArray requestProto) {
    (void)clazz;
    JByteArrayView req(env, requestProto);
    if (!req.ok)
        return nullptr;
    rac_proto_buffer_t result = {};
    rac_proto_buffer_init(&result);
    rac_result_t rc = rac_stt_transcribe_lifecycle_proto(req.u8(), req.size(), &result);
    return makeProtoCallResult(env, rc, &result, "racSttTranscribeLifecycleProto");
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racSttTranscribeStreamLifecycleProto(
    JNIEnv* env, jclass clazz, jbyteArray requestProto, jobject listener) {
    (void)clazz;
    JByteArrayView req(env, requestProto);
    if (!req.ok)
        return RAC_ERROR_NULL_POINTER;
    jobject globalListener = listener != nullptr ? env->NewGlobalRef(listener) : nullptr;
    ProtoListenerUserData ctx{.listener = globalListener,
                              .operation = "racSttTranscribeStreamLifecycleProto"};
    rac_result_t rc = rac_stt_transcribe_stream_lifecycle_proto(
        req.u8(), req.size(), globalListener != nullptr ? proto_void_callback : nullptr,
        globalListener != nullptr ? &ctx : nullptr);
    if (globalListener != nullptr) {
        env->DeleteGlobalRef(globalListener);
    }
    return static_cast<jint>(rc);
}

static void stt_stream_proto_trampoline(const uint8_t* proto_bytes, size_t proto_size,
                                        void* user_data) {
    dispatchHandleListener(sttStreamListeners(), proto_bytes, proto_size, user_data,
                           "sttStreamProtoCallback");
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racSttSetStreamProtoCallback(
    JNIEnv* env, jclass clazz, jlong handle, jobject listener) {
    (void)clazz;
    if (handle == 0L) {
        return RAC_ERROR_NULL_POINTER;
    }
    uintptr_t key = static_cast<uintptr_t>(handle);
    RAC_JNI_TRY {
        sttStreamListeners().set(env, key, listener);
        rac_result_t rc = rac_stt_set_stream_proto_callback(
            handleFromJLong(handle), listener != nullptr ? stt_stream_proto_trampoline : nullptr,
            listener != nullptr ? reinterpret_cast<void*>(key) : nullptr);
        if (RAC_FAILED(rc)) {
            sttStreamListeners().erase(env, key);
        }
        return static_cast<jint>(rc);
    }
    RAC_JNI_CATCH_INT()
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racSttUnsetStreamProtoCallback(
    JNIEnv* env, jclass clazz, jlong handle) {
    (void)clazz;
    if (handle == 0L) {
        return RAC_ERROR_NULL_POINTER;
    }
    uintptr_t key = static_cast<uintptr_t>(handle);
    rac_result_t rc = rac_stt_unset_stream_proto_callback(handleFromJLong(handle));
    rac_stt_proto_quiesce();
    sttStreamListeners().erase(env, key);
    return static_cast<jint>(rc);
}

JNIEXPORT void JNICALL Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racSttProtoQuiesce(
    JNIEnv* env, jclass clazz) {
    (void)env;
    (void)clazz;
    rac_stt_proto_quiesce();
}

JNIEXPORT jlong JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racSttStreamStartProto(
    JNIEnv* env, jclass clazz, jlong handle, jbyteArray optionsProto) {
    (void)clazz;
    if (handle == 0L) {
        return static_cast<jlong>(RAC_ERROR_NULL_POINTER);
    }
    JByteArrayView options(env, optionsProto, true);
    if (!options.ok) {
        return static_cast<jlong>(RAC_ERROR_NULL_POINTER);
    }
    uint64_t session_id = 0;
    rac_result_t rc = rac_stt_stream_start_proto(handleFromJLong(handle), options.u8(),
                                                 options.size(), &session_id);
    if (RAC_FAILED(rc)) {
        return static_cast<jlong>(rc);
    }
    return static_cast<jlong>(session_id);
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racSttStreamFeedAudioProto(
    JNIEnv* env, jclass clazz, jlong sessionId, jbyteArray audioData) {
    (void)clazz;
    if (sessionId <= 0) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    JByteArrayView audio(env, audioData);
    if (!audio.ok) {
        return RAC_ERROR_NULL_POINTER;
    }
    return static_cast<jint>(rac_stt_stream_feed_audio_proto(static_cast<uint64_t>(sessionId),
                                                             audio.u8(), audio.size()));
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racSttStreamStopProto(JNIEnv* env,
                                                                               jclass clazz,
                                                                               jlong sessionId) {
    (void)env;
    (void)clazz;
    if (sessionId <= 0) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    return static_cast<jint>(rac_stt_stream_stop_proto(static_cast<uint64_t>(sessionId)));
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racSttStreamCancelProto(JNIEnv* env,
                                                                                 jclass clazz,
                                                                                 jlong sessionId) {
    (void)env;
    (void)clazz;
    if (sessionId <= 0) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    return static_cast<jint>(rac_stt_stream_cancel_proto(static_cast<uint64_t>(sessionId)));
}

// =============================================================================
// SPEAKER DIARIZATION — component handle family + offline lifecycle verb +
// persistent stream-session ABI. Mirrors the STT component + stream thunks
// above (Swift parity: CppBridge+Diarization.swift).
// =============================================================================

JNIEXPORT jlong JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racDiarizationComponentCreate(
    JNIEnv* env, jclass clazz) {
    (void)env;
    (void)clazz;
    rac_handle_t handle = RAC_INVALID_HANDLE;
    rac_result_t result = rac_diarization_component_create(&handle);
    if (result != RAC_SUCCESS) {
        LOGe("Failed to create diarization component: %d", result);
        return 0;
    }
    return reinterpret_cast<jlong>(handle);
}

JNIEXPORT jboolean JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racDiarizationComponentIsLoaded(
    JNIEnv* env, jclass clazz, jlong handle) {
    (void)env;
    (void)clazz;
    return rac_diarization_component_is_loaded(handleFromJLong(handle)) == RAC_TRUE ? JNI_TRUE
                                                                                    : JNI_FALSE;
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racDiarizationComponentLoadModel(
    JNIEnv* env, jclass clazz, jlong handle, jstring modelPath, jstring modelId,
    jstring modelName) {
    (void)clazz;
    std::string path = getCString(env, modelPath);
    std::string id = getCString(env, modelId);
    std::string name = getCString(env, modelName);
    return static_cast<jint>(rac_diarization_component_load_model(
        handleFromJLong(handle), path.c_str(), id.c_str(), name.c_str()));
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racDiarizationComponentUnload(
    JNIEnv* env, jclass clazz, jlong handle) {
    (void)env;
    (void)clazz;
    return static_cast<jint>(rac_diarization_component_unload(handleFromJLong(handle)));
}

JNIEXPORT void JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racDiarizationComponentDestroy(
    JNIEnv* env, jclass clazz, jlong handle) {
    (void)env;
    (void)clazz;
    if (handle != 0) {
        rac_diarization_component_destroy(reinterpret_cast<rac_handle_t>(handle));
    }
}

// Swift-aligned: mirror iOS Swift which uses rac_diarization_diarize_lifecycle_proto
// (no handle, lifecycle-only) for offline diarization.
JNIEXPORT jbyteArray JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racDiarizationDiarizeLifecycleProto(
    JNIEnv* env, jclass clazz, jbyteArray requestProto) {
    (void)clazz;
    JByteArrayView request(env, requestProto);
    if (!request.ok)
        return nullptr;
    rac_proto_buffer_t result = {};
    rac_proto_buffer_init(&result);
    rac_result_t rc =
        rac_diarization_diarize_lifecycle_proto(request.u8(), request.size(), &result);
    return makeProtoCallResult(env, rc, &result, "racDiarizationDiarizeLifecycleProto");
}

static void diarization_stream_proto_trampoline(const uint8_t* proto_bytes, size_t proto_size,
                                                void* user_data) {
    dispatchHandleListener(diarizationStreamListeners(), proto_bytes, proto_size, user_data,
                           "diarizationStreamProtoCallback");
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racDiarizationSetStreamProtoCallback(
    JNIEnv* env, jclass clazz, jlong handle, jobject listener) {
    (void)clazz;
    if (handle == 0L) {
        return RAC_ERROR_NULL_POINTER;
    }
    uintptr_t key = static_cast<uintptr_t>(handle);
    RAC_JNI_TRY {
        diarizationStreamListeners().set(env, key, listener);
        rac_result_t rc = rac_diarization_set_stream_proto_callback(
            handleFromJLong(handle),
            listener != nullptr ? diarization_stream_proto_trampoline : nullptr,
            listener != nullptr ? reinterpret_cast<void*>(key) : nullptr);
        if (RAC_FAILED(rc)) {
            diarizationStreamListeners().erase(env, key);
        }
        return static_cast<jint>(rc);
    }
    RAC_JNI_CATCH_INT()
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racDiarizationUnsetStreamProtoCallback(
    JNIEnv* env, jclass clazz, jlong handle) {
    (void)clazz;
    if (handle == 0L) {
        return RAC_ERROR_NULL_POINTER;
    }
    uintptr_t key = static_cast<uintptr_t>(handle);
    rac_result_t rc = rac_diarization_unset_stream_proto_callback(handleFromJLong(handle));
    rac_diarization_proto_quiesce();
    diarizationStreamListeners().erase(env, key);
    return static_cast<jint>(rc);
}

JNIEXPORT void JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racDiarizationProtoQuiesce(JNIEnv* env,
                                                                                    jclass clazz) {
    (void)env;
    (void)clazz;
    rac_diarization_proto_quiesce();
}

JNIEXPORT jlong JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racDiarizationStreamStartProto(
    JNIEnv* env, jclass clazz, jlong handle, jbyteArray optionsProto) {
    (void)clazz;
    if (handle == 0L) {
        return static_cast<jlong>(RAC_ERROR_NULL_POINTER);
    }
    JByteArrayView options(env, optionsProto, true);
    if (!options.ok) {
        return static_cast<jlong>(RAC_ERROR_NULL_POINTER);
    }
    uint64_t session_id = 0;
    rac_result_t rc = rac_diarization_stream_start_proto(handleFromJLong(handle), options.u8(),
                                                         options.size(), &session_id);
    if (RAC_FAILED(rc)) {
        return static_cast<jlong>(rc);
    }
    return static_cast<jlong>(session_id);
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racDiarizationStreamFeedAudioProto(
    JNIEnv* env, jclass clazz, jlong sessionId, jbyteArray audioData) {
    (void)clazz;
    if (sessionId <= 0) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    JByteArrayView audio(env, audioData);
    if (!audio.ok) {
        return RAC_ERROR_NULL_POINTER;
    }
    return static_cast<jint>(rac_diarization_stream_feed_audio_proto(
        static_cast<uint64_t>(sessionId), audio.u8(), audio.size()));
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racDiarizationStreamStopProto(
    JNIEnv* env, jclass clazz, jlong sessionId) {
    (void)env;
    (void)clazz;
    if (sessionId <= 0) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    return static_cast<jint>(rac_diarization_stream_stop_proto(static_cast<uint64_t>(sessionId)));
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racDiarizationStreamCancelProto(
    JNIEnv* env, jclass clazz, jlong sessionId) {
    (void)env;
    (void)clazz;
    if (sessionId <= 0) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    return static_cast<jint>(rac_diarization_stream_cancel_proto(static_cast<uint64_t>(sessionId)));
}

// =============================================================================
// CROSS-ENCODER RERANK — component handle family + one handle-scoped proto verb.
// Mirrors the diarization component thunks above (Swift parity:
// CppBridge+Rerank.swift). Unlike diarization there is no handle-free
// `*_lifecycle_proto` verb: rac_rerank_component_rerank_proto's acquire is
// owner-scoped, so the Kotlin bridge loads the model into this handle first.
// =============================================================================

JNIEXPORT jlong JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racRerankComponentCreate(
    JNIEnv* env, jclass clazz) {
    (void)env;
    (void)clazz;
    rac_handle_t handle = RAC_INVALID_HANDLE;
    rac_result_t result = rac_rerank_component_create(&handle);
    if (result != RAC_SUCCESS) {
        LOGe("Failed to create rerank component: %d", result);
        return 0;
    }
    return reinterpret_cast<jlong>(handle);
}

JNIEXPORT jboolean JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racRerankComponentIsLoaded(
    JNIEnv* env, jclass clazz, jlong handle) {
    (void)env;
    (void)clazz;
    return rac_rerank_component_is_loaded(handleFromJLong(handle)) == RAC_TRUE ? JNI_TRUE
                                                                               : JNI_FALSE;
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racRerankComponentLoadModel(
    JNIEnv* env, jclass clazz, jlong handle, jstring modelPath, jstring modelId,
    jstring modelName) {
    (void)clazz;
    std::string path = getCString(env, modelPath);
    std::string id = getCString(env, modelId);
    std::string name = getCString(env, modelName);
    return static_cast<jint>(rac_rerank_component_load_model(
        handleFromJLong(handle), path.c_str(), id.c_str(), name.c_str()));
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racRerankComponentUnload(
    JNIEnv* env, jclass clazz, jlong handle) {
    (void)env;
    (void)clazz;
    return static_cast<jint>(rac_rerank_component_unload(handleFromJLong(handle)));
}

JNIEXPORT void JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racRerankComponentDestroy(
    JNIEnv* env, jclass clazz, jlong handle) {
    (void)env;
    (void)clazz;
    if (handle != 0) {
        rac_rerank_component_destroy(reinterpret_cast<rac_handle_t>(handle));
    }
}

// Handle-scoped: score a serialized RerankRequest against the model loaded into
// `handle` via rac_rerank_component_rerank_proto, returning a serialized
// RerankResult.
JNIEXPORT jbyteArray JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racRerankComponentRerankProto(
    JNIEnv* env, jclass clazz, jlong handle, jbyteArray requestProto) {
    (void)clazz;
    JByteArrayView request(env, requestProto);
    if (!request.ok)
        return nullptr;
    rac_proto_buffer_t result = {};
    rac_proto_buffer_init(&result);
    rac_result_t rc = rac_rerank_component_rerank_proto(handleFromJLong(handle), request.u8(),
                                                        request.size(), &result);
    return makeProtoCallResult(env, rc, &result, "racRerankComponentRerankProto");
}

// Swift-aligned: mirror iOS Swift which uses rac_tts_synthesize_lifecycle_proto
// (no handle, lifecycle-only) for TTS synthesis.
JNIEXPORT jbyteArray JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racTtsSynthesizeLifecycleProto(
    JNIEnv* env, jclass clazz, jbyteArray requestProto) {
    (void)clazz;
    JByteArrayView req(env, requestProto);
    if (!req.ok)
        return nullptr;
    rac_proto_buffer_t result = {};
    rac_proto_buffer_init(&result);
    rac_result_t rc = rac_tts_synthesize_lifecycle_proto(req.u8(), req.size(), &result);
    return makeProtoCallResult(env, rc, &result, "racTtsSynthesizeLifecycleProto");
}

JNIEXPORT jbyteArray JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racTtsListVoicesLifecycleProto(
    JNIEnv* env, jclass clazz) {
    (void)clazz;
    rac_proto_buffer_t result = {};
    rac_proto_buffer_init(&result);
    rac_result_t rc = rac_tts_list_voices_lifecycle_proto(&result);
    return makeProtoCallResult(env, rc, &result, "racTtsListVoicesLifecycleProto");
}

// Swift-aligned: exposes rac_tts_stop_lifecycle_proto so Kotlin can stop an
// in-flight lifecycle-owned TTS synthesis. The legacy
// racTtsComponentCancel(handle) only addresses the per-component handle path;
// the v2 lifecycle TTS path (racTtsSynthesizeStreamLifecycleProto) requires
// this stop ABI to terminate synthesis without freeing the loaded voice.
JNIEXPORT jbyteArray JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racTtsStopLifecycleProto(JNIEnv* env,
                                                                                  jclass clazz) {
    (void)clazz;
    rac_proto_buffer_t result = {};
    rac_proto_buffer_init(&result);
    rac_result_t rc = rac_tts_stop_lifecycle_proto(&result);
    return makeProtoCallResult(env, rc, &result, "racTtsStopLifecycleProto");
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racTtsSynthesizeStreamLifecycleProto(
    JNIEnv* env, jclass clazz, jbyteArray requestProto, jobject listener) {
    (void)clazz;
    JByteArrayView req(env, requestProto);
    if (!req.ok)
        return RAC_ERROR_NULL_POINTER;
    jobject globalListener = listener != nullptr ? env->NewGlobalRef(listener) : nullptr;
    ProtoListenerUserData ctx{.listener = globalListener,
                              .operation = "racTtsSynthesizeStreamLifecycleProto"};
    rac_result_t rc = rac_tts_synthesize_stream_lifecycle_proto(
        req.u8(), req.size(), globalListener != nullptr ? proto_void_callback : nullptr,
        globalListener != nullptr ? &ctx : nullptr);
    if (globalListener != nullptr) {
        env->DeleteGlobalRef(globalListener);
    }
    return static_cast<jint>(rc);
}

// =============================================================================
// BEGIN R7.A — Swift-aligned lifecycle-proto thunks for VLM cancel + VAD
// configure/start/stop/reset. Mirror iOS Swift which uses the lifecycle-only
// ABI (no handle) — Kotlin SDK is lifecycle-only matching Swift. Underlying
// C ABI lives in rac_vlm_service.h and rac_vad_service.h.
// =============================================================================

JNIEXPORT jbyteArray JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racVlmCancelLifecycleProto(JNIEnv* env,
                                                                                    jclass clazz) {
    (void)clazz;
    rac_proto_buffer_t result = {};
    rac_proto_buffer_init(&result);
    rac_result_t rc = rac_vlm_cancel_lifecycle_proto(&result);
    return makeProtoCallResult(env, rc, &result, "racVlmCancelLifecycleProto");
}

JNIEXPORT jbyteArray JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racVadConfigureLifecycleProto(
    JNIEnv* env, jclass clazz, jbyteArray requestProto) {
    (void)clazz;
    JByteArrayView req(env, requestProto);
    if (!req.ok)
        return nullptr;
    rac_proto_buffer_t result = {};
    rac_proto_buffer_init(&result);
    rac_result_t rc = rac_vad_configure_lifecycle_proto(req.u8(), req.size(), &result);
    return makeProtoCallResult(env, rc, &result, "racVadConfigureLifecycleProto");
}

JNIEXPORT jbyteArray JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racVadStartLifecycleProto(JNIEnv* env,
                                                                                   jclass clazz) {
    (void)clazz;
    rac_proto_buffer_t result = {};
    rac_proto_buffer_init(&result);
    rac_result_t rc = rac_vad_start_lifecycle_proto(&result);
    return makeProtoCallResult(env, rc, &result, "racVadStartLifecycleProto");
}

JNIEXPORT jbyteArray JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racVadStopLifecycleProto(JNIEnv* env,
                                                                                  jclass clazz) {
    (void)clazz;
    rac_proto_buffer_t result = {};
    rac_proto_buffer_init(&result);
    rac_result_t rc = rac_vad_stop_lifecycle_proto(&result);
    return makeProtoCallResult(env, rc, &result, "racVadStopLifecycleProto");
}

JNIEXPORT jbyteArray JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racVadResetLifecycleProto(JNIEnv* env,
                                                                                   jclass clazz) {
    (void)clazz;
    rac_proto_buffer_t result = {};
    rac_proto_buffer_init(&result);
    rac_result_t rc = rac_vad_reset_lifecycle_proto(&result);
    return makeProtoCallResult(env, rc, &result, "racVadResetLifecycleProto");
}

JNIEXPORT jbyteArray JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racVadProcessLifecycleProto(
    JNIEnv* env, jclass clazz, jbyteArray requestProto) {
    (void)clazz;
    JByteArrayView req(env, requestProto);
    if (!req.ok)
        return nullptr;
    rac_proto_buffer_t result = {};
    rac_proto_buffer_init(&result);
    rac_result_t rc = rac_vad_process_lifecycle_proto(req.u8(), req.size(), &result);
    return makeProtoCallResult(env, rc, &result, "racVadProcessLifecycleProto");
}

// END R7.A
// =============================================================================

// Swift-aligned: rac_tts_component_{list_voices,synthesize,synthesize_stream}
// _proto JNI thunks deleted — Kotlin SDK uses the lifecycle proto path
// (rac_tts_{list_voices,synthesize,synthesize_stream}_lifecycle_proto)
// matching iOS Swift. C++ functions remain for tests / other consumers.

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racVadComponentConfigureProto(
    JNIEnv* env, jclass clazz, jlong handle, jbyteArray configProto) {
    (void)clazz;
    JByteArrayView config(env, configProto);
    if (handle == 0L || !config.ok)
        return RAC_ERROR_NULL_POINTER;
    return static_cast<jint>(
        rac_vad_component_configure_proto(handleFromJLong(handle), config.u8(), config.size()));
}

JNIEXPORT jbyteArray JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racVadComponentProcessProto(
    JNIEnv* env, jclass clazz, jlong handle, jfloatArray samplesArray, jbyteArray optionsProto) {
    (void)clazz;
    if (handle == 0L || samplesArray == nullptr)
        return nullptr;
    const jsize numSamples = env->GetArrayLength(samplesArray);
    jfloat* samples = numSamples > 0 ? env->GetFloatArrayElements(samplesArray, nullptr) : nullptr;
    if (numSamples > 0 && samples == nullptr)
        return nullptr;
    JByteArrayView options(env, optionsProto, true);
    if (!options.ok) {
        if (samples != nullptr)
            env->ReleaseFloatArrayElements(samplesArray, samples, JNI_ABORT);
        return nullptr;
    }

    rac_proto_buffer_t result = {};
    rac_proto_buffer_init(&result);
    rac_result_t rc = rac_vad_component_process_proto(
        handleFromJLong(handle), reinterpret_cast<const float*>(samples),
        static_cast<size_t>(numSamples), options.u8(), options.size(), &result);
    if (samples != nullptr)
        env->ReleaseFloatArrayElements(samplesArray, samples, JNI_ABORT);
    return makeProtoCallResult(env, rc, &result, "racVadComponentProcessProto");
}

JNIEXPORT jbyteArray JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racVadComponentGetStatisticsProto(
    JNIEnv* env, jclass clazz, jlong handle) {
    (void)clazz;
    if (handle == 0L)
        return nullptr;
    rac_proto_buffer_t result = {};
    rac_proto_buffer_init(&result);
    rac_result_t rc = rac_vad_component_get_statistics_proto(handleFromJLong(handle), &result);
    return makeProtoCallResult(env, rc, &result, "racVadComponentGetStatisticsProto");
}

static void vad_activity_proto_callback(const uint8_t* proto_bytes, size_t proto_size,
                                        void* user_data) {
    dispatchHandleListener(vadActivityListeners(), proto_bytes, proto_size, user_data,
                           "vadActivityProtoCallback");
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racVadComponentSetActivityProtoCallback(
    JNIEnv* env, jclass clazz, jlong handle, jobject listener) {
    (void)clazz;
    if (handle == 0L)
        return RAC_ERROR_NULL_POINTER;
    uintptr_t key = static_cast<uintptr_t>(handle);
    RAC_JNI_TRY {
        vadActivityListeners().set(env, key, listener);
        return static_cast<jint>(rac_vad_component_set_activity_proto_callback(
            handleFromJLong(handle), listener != nullptr ? vad_activity_proto_callback : nullptr,
            listener != nullptr ? reinterpret_cast<void*>(key) : nullptr));
    }
    RAC_JNI_CATCH_INT()
}

// =============================================================================
// VAD STREAM PROTO ABI (rac_vad_stream.h)
// =============================================================================

static void vad_stream_proto_callback(const uint8_t* proto_bytes, size_t proto_size,
                                      void* user_data) {
    dispatchHandleListener(vadStreamListeners(), proto_bytes, proto_size, user_data,
                           "vadStreamProtoCallback");
}

extern "C" JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racVadSetStreamProtoCallback(
    JNIEnv* env, jclass clazz, jlong handle, jobject listener) {
    (void)clazz;
    if (handle == 0L)
        return RAC_ERROR_NULL_POINTER;
    uintptr_t key = static_cast<uintptr_t>(handle);
    RAC_JNI_TRY {
        vadStreamListeners().set(env, key, listener);
        return static_cast<jint>(rac_vad_set_stream_proto_callback(
            handleFromJLong(handle), listener != nullptr ? vad_stream_proto_callback : nullptr,
            listener != nullptr ? reinterpret_cast<void*>(key) : nullptr));
    }
    RAC_JNI_CATCH_INT()
}

extern "C" JNIEXPORT jlong JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racVadStreamStartProto(
    JNIEnv* env, jclass clazz, jlong handle, jbyteArray optionsProto) {
    (void)clazz;
    if (handle == 0L)
        return 0L;
    JByteArrayView options(env, optionsProto, true);
    if (!options.ok)
        return 0L;
    uint64_t sessionId = 0;
    rac_result_t rc = rac_vad_stream_start_proto(handleFromJLong(handle), options.u8(),
                                                 options.size(), &sessionId);
    if (rc != RAC_SUCCESS) {
        LOGe("racVadStreamStartProto: failed with code %d", rc);
        return 0L;
    }
    return static_cast<jlong>(sessionId);
}

extern "C" JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racVadStreamFeedAudioProto(
    JNIEnv* env, jclass clazz, jlong sessionId, jbyteArray audioBytes) {
    (void)clazz;
    if (sessionId == 0L)
        return RAC_ERROR_INVALID_ARGUMENT;
    JByteArrayView audio(env, audioBytes, true);
    if (!audio.ok)
        return RAC_ERROR_NULL_POINTER;
    return static_cast<jint>(rac_vad_stream_feed_audio_proto(static_cast<uint64_t>(sessionId),
                                                             audio.u8(), audio.size()));
}

extern "C" JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racVadStreamStopProto(JNIEnv* env,
                                                                               jclass clazz,
                                                                               jlong sessionId) {
    (void)env;
    (void)clazz;
    if (sessionId == 0L)
        return RAC_ERROR_INVALID_ARGUMENT;
    return static_cast<jint>(rac_vad_stream_stop_proto(static_cast<uint64_t>(sessionId)));
}

extern "C" JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racVadStreamCancelProto(JNIEnv* env,
                                                                                 jclass clazz,
                                                                                 jlong sessionId) {
    (void)env;
    (void)clazz;
    if (sessionId == 0L)
        return RAC_ERROR_INVALID_ARGUMENT;
    return static_cast<jint>(rac_vad_stream_cancel_proto(static_cast<uint64_t>(sessionId)));
}

JNIEXPORT jbyteArray JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racVlmGenerateProto(
    JNIEnv* env, jclass clazz, jbyteArray requestProto) {
    (void)clazz;
    JByteArrayView request(env, requestProto);
    if (!request.ok)
        return nullptr;
    rac_proto_buffer_t result = {};
    rac_proto_buffer_init(&result);
    rac_result_t rc = rac_vlm_generate_proto(request.u8(), request.size(), &result);
    return makeProtoCallResult(env, rc, &result, "racVlmGenerateProto");
}

JNIEXPORT jbyteArray JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racVlmGenerateRequestProto(
    JNIEnv* env, jclass clazz, jlong requestId, jbyteArray requestProto) {
    (void)clazz;
    if (requestId <= 0L)
        return nullptr;
    const uint64_t request_id = static_cast<uint64_t>(requestId);
    const auto start = g_vlm_request_relay.start(request_id);
    if (start != rac::jni::RequestCancellationRelay::StartResult::kRun) {
        rac_proto_buffer_t result = {};
        rac_proto_buffer_init(&result);
        const rac_result_t rc = start == rac::jni::RequestCancellationRelay::StartResult::kCancelled
                                    ? RAC_ERROR_CANCELLED
                                    : RAC_ERROR_INVALID_STATE;
        return makeProtoCallResult(env, rc, &result, "racVlmGenerateRequestProto");
    }
    rac::jni::RequestCompletionGuard completion(&g_vlm_request_relay, request_id);

    JByteArrayView request(env, requestProto);
    if (!request.ok)
        return nullptr;
    rac_proto_buffer_t result = {};
    rac_proto_buffer_init(&result);
    rac_result_t rc = rac_vlm_generate_proto(request.u8(), request.size(), &result);
    return makeProtoCallResult(env, rc, &result, "racVlmGenerateRequestProto");
}

JNIEXPORT jint JNICALL Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racVlmStreamProto(
    JNIEnv* env, jclass clazz, jbyteArray requestProto, jobject listener) {
    (void)clazz;
    JByteArrayView request(env, requestProto);
    if (!request.ok)
        return RAC_ERROR_NULL_POINTER;

    // Typed stream ABI: serialized VLMGenerationRequest in, serialized
    // VLMStreamEvent per callback (STARTED → TOKEN* → COMPLETED/ERROR).
    // Lifecycle-owned model — no handle, no out-result buffer.
    jobject globalListener = listener != nullptr ? env->NewGlobalRef(listener) : nullptr;
    ProtoListenerUserData ctx{.listener = globalListener, .operation = "racVlmStreamProto"};
    rac_result_t rc = rac_vlm_stream_proto(
        request.u8(), request.size(), globalListener != nullptr ? proto_bool_callback : nullptr,
        globalListener != nullptr ? &ctx : nullptr);
    if (globalListener != nullptr)
        env->DeleteGlobalRef(globalListener);
    return static_cast<jint>(rc);
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racVlmStreamRequestProto(
    JNIEnv* env, jclass clazz, jlong requestId, jbyteArray requestProto, jobject listener) {
    (void)clazz;
    if (requestId <= 0L)
        return RAC_ERROR_INVALID_ARGUMENT;
    const uint64_t request_id = static_cast<uint64_t>(requestId);
    const auto start = g_vlm_request_relay.start(request_id);
    if (start != rac::jni::RequestCancellationRelay::StartResult::kRun) {
        return start == rac::jni::RequestCancellationRelay::StartResult::kCancelled
                   ? RAC_ERROR_CANCELLED
                   : RAC_ERROR_INVALID_STATE;
    }
    rac::jni::RequestCompletionGuard completion(&g_vlm_request_relay, request_id);

    JByteArrayView request(env, requestProto);
    if (!request.ok)
        return RAC_ERROR_NULL_POINTER;
    jobject globalListener = listener != nullptr ? env->NewGlobalRef(listener) : nullptr;
    ProtoListenerUserData ctx{.listener = globalListener, .operation = "racVlmStreamRequestProto"};
    rac_result_t rc = rac_vlm_stream_proto(
        request.u8(), request.size(), globalListener != nullptr ? proto_bool_callback : nullptr,
        globalListener != nullptr ? &ctx : nullptr);
    if (globalListener != nullptr)
        env->DeleteGlobalRef(globalListener);
    return static_cast<jint>(rc);
}

JNIEXPORT jbyteArray JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racVlmCancelRequestLifecycleProto(
    JNIEnv* env, jclass clazz, jlong requestId) {
    (void)clazz;
    if (requestId <= 0L)
        return nullptr;
    const uint64_t request_id = static_cast<uint64_t>(requestId);
    rac_proto_buffer_t result = {};
    rac_proto_buffer_init(&result);
    rac_result_t logical_rc = RAC_SUCCESS;
    const auto cancel_result = g_vlm_request_relay.request_cancel(
        request_id, [&] { logical_rc = rac_vlm_cancel_lifecycle_proto(&result); });
    if (cancel_result == rac::jni::RequestCancellationRelay::CancelResult::kInvalid ||
        cancel_result == rac::jni::RequestCancellationRelay::CancelResult::kCompleted) {
        rac_proto_buffer_free(&result);
        return nullptr;
    }
    if (cancel_result == rac::jni::RequestCancellationRelay::CancelResult::kActive) {
        auto retry_interval = std::chrono::milliseconds(1);
        constexpr auto kMaxRetryInterval = std::chrono::milliseconds(16);
        while (g_vlm_request_relay.wait_until_retry_or_complete(request_id, retry_interval)) {
            if (!g_vlm_request_relay.pulse_if_active(request_id,
                                                     [] { cancelVlmLifecycleSilently(); })) {
                break;
            }
            retry_interval = std::min(retry_interval * 2, kMaxRetryInterval);
        }
    }
    return makeProtoCallResult(env, logical_rc, &result, "racVlmCancelRequestLifecycleProto");
}

JNIEXPORT jbyteArray JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racEmbeddingsEmbedBatchProto(
    JNIEnv* env, jclass clazz, jlong handle, jbyteArray requestProto) {
    (void)clazz;
    JByteArrayView request(env, requestProto);
    if (handle == 0L || !request.ok)
        return nullptr;
    rac_proto_buffer_t result = {};
    rac_proto_buffer_init(&result);
    rac_result_t rc = rac_embeddings_embed_batch_proto(handleFromJLong(handle), request.u8(),
                                                       request.size(), &result);
    return makeProtoCallResult(env, rc, &result, "racEmbeddingsEmbedBatchProto");
}

// Swift-aligned: mirror iOS Swift / Flutter which use
// rac_embeddings_embed_batch_lifecycle_proto (no handle, lifecycle-only).
// Resolves the lifecycle-loaded embeddings model internally so embed calls
// share the same model-load/registry state as LLM/STT/TTS.
JNIEXPORT jbyteArray JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racEmbeddingsEmbedBatchLifecycleProto(
    JNIEnv* env, jclass clazz, jbyteArray requestProto) {
    (void)clazz;
    JByteArrayView request(env, requestProto);
    if (!request.ok)
        return nullptr;
    rac_proto_buffer_t result = {};
    rac_proto_buffer_init(&result);
    rac_result_t rc =
        rac_embeddings_embed_batch_lifecycle_proto(request.u8(), request.size(), &result);
    return makeProtoCallResult(env, rc, &result, "racEmbeddingsEmbedBatchLifecycleProto");
}

JNIEXPORT void JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racEmbeddingsDestroy(JNIEnv* env,
                                                                              jclass clazz,
                                                                              jlong handle) {
    (void)env;
    (void)clazz;
    if (handle != 0L)
        rac_embeddings_destroy(handleFromJLong(handle));
}

JNIEXPORT jlong JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racRagSessionCreateProto(
    JNIEnv* env, jclass clazz, jbyteArray configProto) {
    (void)clazz;
    JByteArrayView config(env, configProto);
    if (!config.ok)
        return 0L;
    using Fn = rac_result_t (*)(const uint8_t*, size_t, rac_handle_t*);
    Fn createSession = optionalNativeSymbol<Fn>("rac_rag_session_create_proto");
    if (createSession == nullptr)
        return 0L;
    rac_handle_t session = nullptr;
    rac_result_t rc = createSession(config.u8(), config.size(), &session);
    if (RAC_FAILED(rc))
        return 0L;
    return reinterpret_cast<jlong>(session);
}

// commons-123-A: parallel thunk that surfaces the underlying rac_result_t via
// outRc[0] so the Kotlin caller can build a typed SDKException instead of the
// opaque "returned 0" message produced by the legacy primitive-jlong thunk.
// Matches the parity contract Swift's CppBridge.RAG.createPipeline satisfies
// at sdk/runanywhere-swift/.../ModalityProtoABI+Generated.swift:641-654.
JNIEXPORT jlong JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racRagSessionCreateProtoWithError(
    JNIEnv* env, jclass clazz, jbyteArray configProto, jintArray outRc) {
    (void)clazz;
    auto writeRc = [&](rac_result_t rc) {
        if (outRc == nullptr)
            return;
        if (env->GetArrayLength(outRc) < 1)
            return;
        jint tmp = static_cast<jint>(rc);
        env->SetIntArrayRegion(outRc, 0, 1, &tmp);
    };
    JByteArrayView config(env, configProto);
    if (!config.ok) {
        writeRc(RAC_ERROR_INVALID_ARGUMENT);
        return 0L;
    }
    using Fn = rac_result_t (*)(const uint8_t*, size_t, rac_handle_t*);
    Fn createSession = optionalNativeSymbol<Fn>("rac_rag_session_create_proto");
    if (createSession == nullptr) {
        writeRc(RAC_ERROR_FEATURE_NOT_AVAILABLE);
        return 0L;
    }
    rac_handle_t session = nullptr;
    rac_result_t rc = createSession(config.u8(), config.size(), &session);
    writeRc(rc);
    if (RAC_FAILED(rc))
        return 0L;
    return reinterpret_cast<jlong>(session);
}

JNIEXPORT void JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racRagSessionDestroyProto(JNIEnv* env,
                                                                                   jclass clazz,
                                                                                   jlong handle) {
    (void)env;
    (void)clazz;
    if (handle == 0L)
        return;
    using Fn = void (*)(rac_handle_t);
    Fn destroySession = optionalNativeSymbol<Fn>("rac_rag_session_destroy_proto");
    if (destroySession != nullptr)
        destroySession(handleFromJLong(handle));
}

JNIEXPORT jbyteArray JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racRagIngestProto(
    JNIEnv* env, jclass clazz, jlong handle, jbyteArray documentProto) {
    (void)clazz;
    JByteArrayView document(env, documentProto);
    if (handle == 0L || !document.ok)
        return nullptr;
    using Fn = rac_result_t (*)(rac_handle_t, const uint8_t*, size_t, rac_proto_buffer_t*);
    Fn ingest = optionalNativeSymbol<Fn>("rac_rag_ingest_proto");
    if (ingest == nullptr)
        return makeFeatureUnavailableResult(env, "racRagIngestProto");
    rac_proto_buffer_t result = {};
    rac_proto_buffer_init(&result);
    rac_result_t rc = ingest(handleFromJLong(handle), document.u8(), document.size(), &result);
    return makeProtoCallResult(env, rc, &result, "racRagIngestProto");
}

JNIEXPORT jbyteArray JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racRagQueryProto(JNIEnv* env, jclass clazz,
                                                                          jlong handle,
                                                                          jbyteArray queryProto) {
    (void)clazz;
    JByteArrayView query(env, queryProto);
    if (handle == 0L || !query.ok)
        return nullptr;
    using Fn = rac_result_t (*)(rac_handle_t, const uint8_t*, size_t, rac_proto_buffer_t*);
    Fn queryRag = optionalNativeSymbol<Fn>("rac_rag_query_proto");
    if (queryRag == nullptr)
        return makeFeatureUnavailableResult(env, "racRagQueryProto");
    rac_proto_buffer_t result = {};
    rac_proto_buffer_init(&result);
    rac_result_t rc = queryRag(handleFromJLong(handle), query.u8(), query.size(), &result);
    return makeProtoCallResult(env, rc, &result, "racRagQueryProto");
}

JNIEXPORT jbyteArray JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racRagQueryRequestProto(
    JNIEnv* env, jclass clazz, jlong requestId, jlong handle, jbyteArray queryProto) {
    (void)clazz;
    if (requestId <= 0L)
        return nullptr;
    const uint64_t request_id = static_cast<uint64_t>(requestId);
    const auto start = g_rag_request_relay.start(request_id);
    if (start != rac::jni::RequestCancellationRelay::StartResult::kRun) {
        rac_proto_buffer_t result = {};
        rac_proto_buffer_init(&result);
        const rac_result_t rc = start == rac::jni::RequestCancellationRelay::StartResult::kCancelled
                                    ? RAC_ERROR_CANCELLED
                                    : RAC_ERROR_INVALID_STATE;
        return makeProtoCallResult(env, rc, &result, "racRagQueryRequestProto");
    }
    rac::jni::RequestCompletionGuard completion(&g_rag_request_relay, request_id);

    JByteArrayView query(env, queryProto);
    if (handle == 0L || !query.ok)
        return nullptr;
    using Fn = rac_result_t (*)(rac_handle_t, const uint8_t*, size_t, rac_proto_buffer_t*);
    Fn queryRag = optionalNativeSymbol<Fn>("rac_rag_query_proto");
    if (queryRag == nullptr)
        return makeFeatureUnavailableResult(env, "racRagQueryRequestProto");
    rac_proto_buffer_t result = {};
    rac_proto_buffer_init(&result);
    rac_result_t rc = queryRag(handleFromJLong(handle), query.u8(), query.size(), &result);
    return makeProtoCallResult(env, rc, &result, "racRagQueryRequestProto");
}

// Streaming RAG query: blocks on the calling (background) thread, invoking the
// JVM listener with each serialized RAGStreamEvent (TOKEN..., then COMPLETED or
// ERROR). Mirrors racLlmGenerateStreamProto. Request-scoped like the unary path:
// the request relay makes cancellation target this exact stream (via
// racRagCancelRequestProto) instead of any query on the session, so concurrent
// collectors cannot cancel each other. The listener returns false to stop early
// (backpressure), forwarded through proto_bool_callback.
JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racRagQueryStreamRequestProto(
    JNIEnv* env, jclass clazz, jlong requestId, jlong handle, jbyteArray queryProto,
    jobject listener) {
    (void)clazz;
    if (requestId <= 0L)
        return static_cast<jint>(RAC_ERROR_INVALID_STATE);
    const uint64_t request_id = static_cast<uint64_t>(requestId);
    const auto start = g_rag_request_relay.start(request_id);
    if (start != rac::jni::RequestCancellationRelay::StartResult::kRun) {
        return static_cast<jint>(start == rac::jni::RequestCancellationRelay::StartResult::kCancelled
                                     ? RAC_ERROR_CANCELLED
                                     : RAC_ERROR_INVALID_STATE);
    }
    rac::jni::RequestCompletionGuard completion(&g_rag_request_relay, request_id);

    JByteArrayView query(env, queryProto);
    if (handle == 0L || !query.ok)
        return static_cast<jint>(RAC_ERROR_NULL_POINTER);
    using Fn = rac_result_t (*)(rac_handle_t, const uint8_t*, size_t,
                                rac_bool_t (*)(const uint8_t*, size_t, void*), void*);
    Fn streamRag = optionalNativeSymbol<Fn>("rac_rag_query_stream_proto");
    if (streamRag == nullptr)
        return static_cast<jint>(RAC_ERROR_FEATURE_NOT_AVAILABLE);
    jobject globalListener = listener != nullptr ? env->NewGlobalRef(listener) : nullptr;
    ProtoListenerUserData ctx{.listener = globalListener,
                              .operation = "racRagQueryStreamRequestProto"};
    rac_result_t rc = streamRag(handleFromJLong(handle), query.u8(), query.size(),
                                globalListener != nullptr ? proto_bool_callback : nullptr,
                                globalListener != nullptr ? &ctx : nullptr);
    if (globalListener != nullptr) {
        env->DeleteGlobalRef(globalListener);
    }
    return static_cast<jint>(rc);
}

JNIEXPORT jint JNICALL Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racRagCancelProto(
    JNIEnv* env, jclass clazz, jlong handle) {
    (void)env;
    (void)clazz;
    if (handle == 0L)
        return static_cast<jint>(RAC_ERROR_INVALID_HANDLE);
    using Fn = rac_result_t (*)(rac_handle_t);
    Fn cancelRag = optionalNativeSymbol<Fn>("rac_rag_cancel_proto");
    if (cancelRag == nullptr) {
        LOGe("racRagCancelProto: rac_rag_cancel_proto symbol unavailable");
        return static_cast<jint>(RAC_ERROR_FEATURE_NOT_AVAILABLE);
    }
    const rac_result_t rc = cancelRag(handleFromJLong(handle));
    LOGi("racRagCancelProto: handle=%p rc=%d", handleFromJLong(handle), static_cast<int>(rc));
    return static_cast<jint>(rc);
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racRagCancelRequestProto(JNIEnv* env,
                                                                                  jclass clazz,
                                                                                  jlong requestId,
                                                                                  jlong handle) {
    (void)env;
    (void)clazz;
    if (requestId <= 0L || handle == 0L)
        return static_cast<jint>(RAC_ERROR_INVALID_HANDLE);
    using Fn = rac_result_t (*)(rac_handle_t);
    Fn cancelRag = optionalNativeSymbol<Fn>("rac_rag_cancel_proto");
    if (cancelRag == nullptr)
        return static_cast<jint>(RAC_ERROR_FEATURE_NOT_AVAILABLE);

    const uint64_t request_id = static_cast<uint64_t>(requestId);
    rac_result_t logical_rc = RAC_SUCCESS;
    const auto cancel_result = g_rag_request_relay.request_cancel(
        request_id, [&] { logical_rc = cancelRag(handleFromJLong(handle)); });
    if (cancel_result == rac::jni::RequestCancellationRelay::CancelResult::kInvalid) {
        return static_cast<jint>(RAC_ERROR_INVALID_STATE);
    }
    if (cancel_result == rac::jni::RequestCancellationRelay::CancelResult::kCompleted) {
        return static_cast<jint>(RAC_SUCCESS);
    }
    if (cancel_result == rac::jni::RequestCancellationRelay::CancelResult::kActive) {
        auto retry_interval = std::chrono::milliseconds(1);
        constexpr auto kMaxRetryInterval = std::chrono::milliseconds(16);
        while (g_rag_request_relay.wait_until_retry_or_complete(request_id, retry_interval)) {
            if (!g_rag_request_relay.pulse_if_active(
                    request_id, [&] { (void)cancelRag(handleFromJLong(handle)); })) {
                break;
            }
            retry_interval = std::min(retry_interval * 2, kMaxRetryInterval);
        }
    }
    LOGi("racRagCancelRequestProto: request=%llu handle=%p rc=%d",
         static_cast<unsigned long long>(request_id), handleFromJLong(handle),
         static_cast<int>(logical_rc));
    return static_cast<jint>(logical_rc);
}

JNIEXPORT jbyteArray JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racRagClearProto(JNIEnv* env, jclass clazz,
                                                                          jlong handle) {
    (void)clazz;
    if (handle == 0L)
        return nullptr;
    using Fn = rac_result_t (*)(rac_handle_t, rac_proto_buffer_t*);
    Fn clear = optionalNativeSymbol<Fn>("rac_rag_clear_proto");
    if (clear == nullptr)
        return makeFeatureUnavailableResult(env, "racRagClearProto");
    rac_proto_buffer_t result = {};
    rac_proto_buffer_init(&result);
    rac_result_t rc = clear(handleFromJLong(handle), &result);
    return makeProtoCallResult(env, rc, &result, "racRagClearProto");
}

JNIEXPORT jbyteArray JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racRagStatsProto(JNIEnv* env, jclass clazz,
                                                                          jlong handle) {
    (void)clazz;
    if (handle == 0L)
        return nullptr;
    using Fn = rac_result_t (*)(rac_handle_t, rac_proto_buffer_t*);
    Fn stats = optionalNativeSymbol<Fn>("rac_rag_stats_proto");
    if (stats == nullptr)
        return makeFeatureUnavailableResult(env, "racRagStatsProto");
    rac_proto_buffer_t result = {};
    rac_proto_buffer_init(&result);
    rac_result_t rc = stats(handleFromJLong(handle), &result);
    return makeProtoCallResult(env, rc, &result, "racRagStatsProto");
}

JNIEXPORT jbyteArray JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racDiffusionGenerateLifecycleProto(
    JNIEnv* env, jclass clazz, jbyteArray requestProto) {
    (void)clazz;
    JByteArrayView request(env, requestProto);
    if (!request.ok)
        return nullptr;
    rac_proto_buffer_t result = {};
    rac_proto_buffer_init(&result);
    rac_result_t rc = rac_diffusion_generate_lifecycle_proto(request.u8(), request.size(), &result);
    return makeProtoCallResult(env, rc, &result, "racDiffusionGenerateLifecycleProto");
}

JNIEXPORT jbyteArray JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racSegmentationSegmentLifecycleProto(
    JNIEnv* env, jclass clazz, jbyteArray requestProto) {
    (void)clazz;
    JByteArrayView request(env, requestProto);
    if (!request.ok)
        return nullptr;
    rac_proto_buffer_t result = {};
    rac_proto_buffer_init(&result);
    rac_result_t rc =
        rac_segmentation_segment_lifecycle_proto(request.u8(), request.size(), &result);
    return makeProtoCallResult(env, rc, &result, "racSegmentationSegmentLifecycleProto");
}

JNIEXPORT jbyteArray JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racLoraApplyProto(
    JNIEnv* env, jclass clazz, jbyteArray requestProto) {
    (void)clazz;
    JByteArrayView request(env, requestProto);
    if (!request.ok)
        return nullptr;
    rac_proto_buffer_t result = {};
    rac_proto_buffer_init(&result);
    rac_result_t rc = rac_lora_apply_proto(request.u8(), request.size(), &result);
    return makeProtoCallResult(env, rc, &result, "racLoraApplyProto");
}

JNIEXPORT jbyteArray JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racLoraRemoveProto(
    JNIEnv* env, jclass clazz, jbyteArray requestProto) {
    (void)clazz;
    JByteArrayView request(env, requestProto);
    if (!request.ok)
        return nullptr;
    rac_proto_buffer_t result = {};
    rac_proto_buffer_init(&result);
    rac_result_t rc = rac_lora_remove_proto(request.u8(), request.size(), &result);
    return makeProtoCallResult(env, rc, &result, "racLoraRemoveProto");
}

JNIEXPORT jbyteArray JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racLoraListProto(JNIEnv* env, jclass clazz,
                                                                          jbyteArray stateProto) {
    (void)clazz;
    JByteArrayView state(env, stateProto);
    if (!state.ok)
        return nullptr;
    rac_proto_buffer_t result = {};
    rac_proto_buffer_init(&result);
    rac_result_t rc = rac_lora_list_proto(state.u8(), state.size(), &result);
    return makeProtoCallResult(env, rc, &result, "racLoraListProto");
}

JNIEXPORT jbyteArray JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racLoraStateProto(JNIEnv* env,
                                                                           jclass clazz,
                                                                           jbyteArray stateProto) {
    (void)clazz;
    JByteArrayView state(env, stateProto);
    if (!state.ok)
        return nullptr;
    rac_proto_buffer_t result = {};
    rac_proto_buffer_init(&result);
    rac_result_t rc = rac_lora_state_proto(state.u8(), state.size(), &result);
    return makeProtoCallResult(env, rc, &result, "racLoraStateProto");
}

JNIEXPORT jbyteArray JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racLoraCompatibilityProto(
    JNIEnv* env, jclass clazz, jbyteArray configProto) {
    (void)clazz;
    JByteArrayView config(env, configProto);
    if (!config.ok)
        return nullptr;
    rac_proto_buffer_t result = {};
    rac_proto_buffer_init(&result);
    rac_result_t rc = rac_lora_compatibility_proto(config.u8(), config.size(), &result);
    return makeProtoCallResult(env, rc, &result, "racLoraCompatibilityProto");
}

JNIEXPORT jbyteArray JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racLoraRegisterProto(
    JNIEnv* env, jclass clazz, jbyteArray entryProto) {
    (void)clazz;
    JByteArrayView entry(env, entryProto);
    if (!entry.ok)
        return nullptr;
    rac_lora_registry_handle_t registry = rac_get_lora_registry();
    if (!registry)
        return nullptr;
    rac_proto_buffer_t result = {};
    rac_proto_buffer_init(&result);
    rac_result_t rc = rac_lora_register_proto(registry, entry.u8(), entry.size(), &result);
    return makeProtoCallResult(env, rc, &result, "racLoraRegisterProto");
}

// LoRA catalog proto thunks. Kotlin
// `RunAnywhereBridge.racLoraCatalog{List,Query,Get,MarkDownloadCompleted}Proto`
// declared `external fun` for these but no JNI thunks existed, causing
// `UnsatisfiedLinkError` on the first LoRA catalog access from
// `CppBridgeModalityProto.kt`. Mirrors the `racLoraRegisterProto` shape.

JNIEXPORT jbyteArray JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racLoraCatalogListProto(
    JNIEnv* env, jclass clazz, jbyteArray requestProto) {
    (void)clazz;
    JByteArrayView req(env, requestProto);
    if (!req.ok)
        return nullptr;
    rac_lora_registry_handle_t registry = rac_get_lora_registry();
    if (!registry)
        return nullptr;
    rac_proto_buffer_t result = {};
    rac_proto_buffer_init(&result);
    rac_result_t rc = rac_lora_catalog_list_proto(registry, req.u8(), req.size(), &result);
    return makeProtoCallResult(env, rc, &result, "racLoraCatalogListProto");
}

JNIEXPORT jbyteArray JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racLoraCatalogQueryProto(
    JNIEnv* env, jclass clazz, jbyteArray queryProto) {
    (void)clazz;
    JByteArrayView query(env, queryProto);
    if (!query.ok)
        return nullptr;
    rac_lora_registry_handle_t registry = rac_get_lora_registry();
    if (!registry)
        return nullptr;
    rac_proto_buffer_t result = {};
    rac_proto_buffer_init(&result);
    rac_result_t rc = rac_lora_catalog_query_proto(registry, query.u8(), query.size(), &result);
    return makeProtoCallResult(env, rc, &result, "racLoraCatalogQueryProto");
}

JNIEXPORT jbyteArray JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racLoraCatalogGetProto(
    JNIEnv* env, jclass clazz, jbyteArray requestProto) {
    (void)clazz;
    JByteArrayView req(env, requestProto);
    if (!req.ok)
        return nullptr;
    rac_lora_registry_handle_t registry = rac_get_lora_registry();
    if (!registry)
        return nullptr;
    rac_proto_buffer_t result = {};
    rac_proto_buffer_init(&result);
    rac_result_t rc = rac_lora_catalog_get_proto(registry, req.u8(), req.size(), &result);
    return makeProtoCallResult(env, rc, &result, "racLoraCatalogGetProto");
}

JNIEXPORT jbyteArray JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racLoraCatalogMarkDownloadCompletedProto(
    JNIEnv* env, jclass clazz, jbyteArray requestProto) {
    (void)clazz;
    JByteArrayView req(env, requestProto);
    if (!req.ok)
        return nullptr;
    rac_lora_registry_handle_t registry = rac_get_lora_registry();
    if (!registry)
        return nullptr;
    rac_proto_buffer_t result = {};
    rac_proto_buffer_init(&result);
    rac_result_t rc =
        rac_lora_catalog_mark_download_completed_proto(registry, req.u8(), req.size(), &result);
    return makeProtoCallResult(env, rc, &result, "racLoraCatalogMarkDownloadCompletedProto");
}

JNIEXPORT jbyteArray JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racLoraAdapterImportProto(
    JNIEnv* env, jclass clazz, jbyteArray requestProto) {
    (void)clazz;
    JByteArrayView req(env, requestProto);
    if (!req.ok)
        return nullptr;
    rac_lora_registry_handle_t registry = rac_get_lora_registry();
    if (!registry)
        return nullptr;
    rac_proto_buffer_t result = {};
    rac_proto_buffer_init(&result);
    rac_result_t rc = rac_lora_adapter_import_proto(registry, req.u8(), req.size(), &result);
    return makeProtoCallResult(env, rc, &result, "racLoraAdapterImportProto");
}

// Plugin registry thunks. Kotlin
// `RunAnywhere+PluginLoader.jvmAndroid.kt` calls these at module
// registration time (PluginInfo.apiVersion, .count, .load, .unload,
// .registeredNames), but no JNI thunks existed, causing UnsatisfiedLinkError.

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racRegistryGetPluginApiVersion(
    JNIEnv* env, jclass clazz) {
    (void)env;
    (void)clazz;
    return static_cast<jint>(rac_plugin_api_version());
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racRegistryLoadPlugin(JNIEnv* env,
                                                                               jclass clazz,
                                                                               jstring pathStr) {
    (void)clazz;
    if (pathStr == nullptr)
        return static_cast<jint>(RAC_ERROR_NULL_POINTER);
    const char* path = env->GetStringUTFChars(pathStr, nullptr);
    if (path == nullptr)
        return static_cast<jint>(RAC_ERROR_NULL_POINTER);
    rac_result_t rc = rac_registry_load_plugin(path);
    env->ReleaseStringUTFChars(pathStr, path);
    return static_cast<jint>(rc);
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racRegistryUnloadPlugin(JNIEnv* env,
                                                                                 jclass clazz,
                                                                                 jstring nameStr) {
    (void)clazz;
    if (nameStr == nullptr)
        return static_cast<jint>(RAC_ERROR_NULL_POINTER);
    const char* name = env->GetStringUTFChars(nameStr, nullptr);
    if (name == nullptr)
        return static_cast<jint>(RAC_ERROR_NULL_POINTER);
    rac_result_t rc = rac_registry_unload_plugin(name);
    env->ReleaseStringUTFChars(nameStr, name);
    return static_cast<jint>(rc);
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racRegistryGetPluginCount(JNIEnv* env,
                                                                                   jclass clazz) {
    (void)env;
    (void)clazz;
    return static_cast<jint>(rac_registry_plugin_count());
}

JNIEXPORT jobjectArray JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racRegistryGetRegisteredNames(
    JNIEnv* env, jclass clazz) {
    (void)clazz;
    const char** names = nullptr;
    size_t count = 0;
    rac_result_t rc = rac_registry_list_plugins(&names, &count);
    if (rc != RAC_SUCCESS)
        return nullptr;
    jclass stringClass = env->FindClass("java/lang/String");
    jobjectArray arr = env->NewObjectArray(static_cast<jsize>(count), stringClass, nullptr);
    for (size_t i = 0; i < count; ++i) {
        if (names[i] != nullptr) {
            jstring jname = env->NewStringUTF(names[i]);
            env->SetObjectArrayElement(arr, static_cast<jsize>(i), jname);
            env->DeleteLocalRef(jname);
        }
    }
    rac_registry_free_plugin_list(names, count);
    return arr;
}

// =============================================================================
// Voice Agent Handle API (Android sample needs a voice agent
// handle to feed VoiceAgentStreamAdapter. Mirrors Swift's
// CppBridge.VoiceAgent.shared.getHandle() pattern.)
// =============================================================================

JNIEXPORT jlong JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racVoiceAgentCreateStandalone(
    JNIEnv* env, jclass clazz) {
    (void)env;
    (void)clazz;
    rac_voice_agent_handle_t handle = nullptr;
    rac_result_t result = rac_voice_agent_create_standalone(&handle);
    if (result != RAC_SUCCESS) {
        LOGe("racVoiceAgentCreateStandalone failed: %d", result);
        return 0L;
    }
    return reinterpret_cast<jlong>(handle);
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racVoiceAgentInitializeWithLoadedModels(
    JNIEnv* env, jclass clazz, jlong handle) {
    (void)env;
    (void)clazz;
    if (handle == 0L)
        return static_cast<jint>(RAC_ERROR_NULL_POINTER);
    return static_cast<jint>(rac_voice_agent_initialize_with_loaded_models(
        reinterpret_cast<rac_voice_agent_handle_t>(handle)));
}

JNIEXPORT jboolean JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racVoiceAgentIsReady(JNIEnv* env,
                                                                              jclass clazz,
                                                                              jlong handle) {
    (void)env;
    (void)clazz;
    if (handle == 0L)
        return JNI_FALSE;
    rac_bool_t is_ready = RAC_FALSE;
    rac_result_t result =
        rac_voice_agent_is_ready(reinterpret_cast<rac_voice_agent_handle_t>(handle), &is_ready);
    return (result == RAC_SUCCESS && is_ready == RAC_TRUE) ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT void JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racVoiceAgentDestroy(JNIEnv* env,
                                                                              jclass clazz,
                                                                              jlong handle) {
    (void)env;
    (void)clazz;
    if (handle == 0L)
        return;
    rac_voice_agent_destroy(reinterpret_cast<rac_voice_agent_handle_t>(handle));
}

JNIEXPORT jbyteArray JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racVoiceAgentInitializeProto(
    JNIEnv* env, jclass clazz, jlong handle, jbyteArray configProto) {
    (void)clazz;
    JByteArrayView config(env, configProto);
    if (handle == 0L || !config.ok)
        return nullptr;
    rac_proto_buffer_t result = {};
    rac_proto_buffer_init(&result);
    rac_result_t rc = rac_voice_agent_initialize_proto(
        reinterpret_cast<rac_voice_agent_handle_t>(handle), config.u8(), config.size(), &result);
    return makeProtoCallResult(env, rc, &result, "racVoiceAgentInitializeProto");
}

JNIEXPORT jbyteArray JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racVoiceAgentComponentStatesProto(
    JNIEnv* env, jclass clazz, jlong handle) {
    (void)clazz;
    if (handle == 0L)
        return nullptr;
    rac_proto_buffer_t result = {};
    rac_proto_buffer_init(&result);
    rac_result_t rc = rac_voice_agent_component_states_proto(
        reinterpret_cast<rac_voice_agent_handle_t>(handle), &result);
    return makeProtoCallResult(env, rc, &result, "racVoiceAgentComponentStatesProto");
}

JNIEXPORT jbyteArray JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racVoiceAgentProcessVoiceTurnProto(
    JNIEnv* env, jclass clazz, jlong handle, jbyteArray audioData) {
    (void)clazz;
    JByteArrayView audio(env, audioData);
    if (handle == 0L || !audio.ok)
        return nullptr;
    rac_proto_buffer_t result = {};
    rac_proto_buffer_init(&result);
    rac_result_t rc = rac_voice_agent_process_voice_turn_proto(
        reinterpret_cast<rac_voice_agent_handle_t>(handle), audio.data(), audio.size(), &result);
    return makeProtoCallResult(env, rc, &result, "racVoiceAgentProcessVoiceTurnProto");
}

// Full-session voice-agent turn ABI. Accepts the full
// VoiceAgentTurnRequest bytes (request_id, session_id, session_config,
// metadata, audio_data + encoding) and emits a canonical VoiceEvent stream
// via the registered listener.
JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racVoiceAgentProcessTurnProto(
    JNIEnv* env, jclass clazz, jlong handle, jbyteArray requestBytes, jobject listener) {
    (void)clazz;
    JByteArrayView request(env, requestBytes);
    if (handle == 0L || !request.ok || listener == nullptr)
        return RAC_ERROR_NULL_POINTER;

    jobject globalListener = env->NewGlobalRef(listener);
    ProtoListenerUserData ctx{.listener = globalListener,
                              .operation = "racVoiceAgentProcessTurnProto"};
    rac_result_t rc = rac_voice_agent_process_turn_proto(
        reinterpret_cast<rac_voice_agent_handle_t>(handle), request.u8(), request.size(),
        reinterpret_cast<rac_voice_agent_turn_event_callback_fn>(proto_void_callback), &ctx);
    env->DeleteGlobalRef(globalListener);
    return static_cast<jint>(rc);
}

// Streaming raw-frame ingress: the core segments utterances and runs the turn
// pipeline, returning a VoiceAgentResult inline when one completes (empty
// otherwise). VoiceEvents fan out to the handle callback (no per-call
// listener).
JNIEXPORT jbyteArray JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racVoiceAgentFeedAudioProto(
    JNIEnv* env, jclass clazz, jlong handle, jbyteArray audioData, jint sampleRateHz, jint channels,
    jint encoding, jboolean isFinal) {
    (void)clazz;
    JByteArrayView audio(env, audioData);
    if (handle == 0L || !audio.ok)
        return nullptr;
    rac_proto_buffer_t result = {};
    rac_proto_buffer_init(&result);
    rac_result_t rc = rac_voice_agent_feed_audio_proto(
        reinterpret_cast<rac_voice_agent_handle_t>(handle), audio.data(), audio.size(),
        static_cast<int32_t>(sampleRateHz), static_cast<int32_t>(channels),
        static_cast<int32_t>(encoding), isFinal == JNI_TRUE ? RAC_TRUE : RAC_FALSE, &result);
    return makeProtoCallResult(env, rc, &result, "racVoiceAgentFeedAudioProto");
}

JNIEXPORT jbyteArray JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racVoiceAgentTranscribeProto(
    JNIEnv* env, jclass clazz, jlong handle, jbyteArray requestBytes) {
    (void)clazz;
    JByteArrayView request(env, requestBytes);
    if (handle == 0L || !request.ok)
        return nullptr;
    rac_proto_buffer_t result = {};
    rac_proto_buffer_init(&result);
    rac_result_t rc = rac_voice_agent_transcribe_proto(
        reinterpret_cast<rac_voice_agent_handle_t>(handle), request.u8(), request.size(), &result);
    return makeProtoCallResult(env, rc, &result, "racVoiceAgentTranscribeProto");
}

JNIEXPORT jbyteArray JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racVoiceAgentSynthesizeSpeechProto(
    JNIEnv* env, jclass clazz, jlong handle, jbyteArray requestBytes) {
    (void)clazz;
    JByteArrayView request(env, requestBytes);
    if (handle == 0L || !request.ok)
        return nullptr;
    rac_proto_buffer_t result = {};
    rac_proto_buffer_init(&result);
    rac_result_t rc = rac_voice_agent_synthesize_speech_proto(
        reinterpret_cast<rac_voice_agent_handle_t>(handle), request.u8(), request.size(), &result);
    return makeProtoCallResult(env, rc, &result, "racVoiceAgentSynthesizeSpeechProto");
}

// =============================================================================
// Tool-calling session ABI (native orchestration loop).
// =============================================================================
//
// Commons owns the full generate → parse → validate → execute → loop
// cycle. Kotlin keeps only the tool registry + executor callback pipe.

JNIEXPORT jlong JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racToolCallingSessionCreateProto(
    JNIEnv* env, jclass clazz, jbyteArray requestBytes, jobject listener) {
    (void)clazz;
    JByteArrayView request(env, requestBytes);
    if (!request.ok || listener == nullptr)
        return 0L;

    RAC_JNI_TRY {
        // The listener lives for the entire session lifetime. Kotlin side is
        // responsible for calling racToolCallingSessionDestroyProto to release
        // this global ref — see below.
        jobject globalListener = env->NewGlobalRef(listener);
        auto* ctx = new ProtoListenerUserData{.listener = globalListener,
                                              .operation = "racToolCallingSessionCreateProto"};

        uint64_t sessionHandle = 0;
        rac_result_t rc = rac_tool_calling_session_create_proto(
            request.u8(), request.size(),
            reinterpret_cast<rac_tool_calling_session_event_callback_fn>(proto_void_callback), ctx,
            captureToolCallingSessionHandle, &sessionHandle);
        if (rc != RAC_SUCCESS || sessionHandle == 0) {
            if (sessionHandle != 0) {
                (void)rac_tool_calling_session_destroy_proto(sessionHandle);
            }
            env->DeleteGlobalRef(globalListener);
            delete ctx;
            return 0L;
        }
        {
            std::lock_guard<std::mutex> lg(toolCallingCtxMutex());
            // commons-056: map allocation can throw bad_alloc; unwind the
            // already-registered session so we don't leak a dangling ctx.
            try {
                toolCallingCtxMap()[sessionHandle] = ctx;
            } catch (...) {
                rac_tool_calling_session_destroy_proto(sessionHandle);
                env->DeleteGlobalRef(globalListener);
                delete ctx;
                throw;
            }
        }
        return static_cast<jlong>(sessionHandle);
    }
    RAC_JNI_CATCH_RET(0L, 0L)
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racToolCallingSessionStepWithResultProto(
    JNIEnv* env, jclass clazz, jbyteArray requestBytes) {
    (void)clazz;
    JByteArrayView request(env, requestBytes);
    if (!request.ok)
        return RAC_ERROR_NULL_POINTER;
    rac_result_t rc = rac_tool_calling_session_step_with_result_proto(request.u8(), request.size());
    return static_cast<jint>(rc);
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racToolCallingSessionDestroyProto(
    JNIEnv* env, jclass clazz, jlong sessionHandle) {
    (void)clazz;
    if (sessionHandle == 0L)
        return RAC_SUCCESS;
    rac_result_t rc = rac_tool_calling_session_destroy_proto(static_cast<uint64_t>(sessionHandle));
    ProtoListenerUserData* ctx = nullptr;
    {
        std::lock_guard<std::mutex> lg(toolCallingCtxMutex());
        auto& map = toolCallingCtxMap();
        auto it = map.find(static_cast<uint64_t>(sessionHandle));
        if (it != map.end()) {
            ctx = it->second;
            map.erase(it);
        }
    }
    if (ctx != nullptr) {
        if (ctx->listener != nullptr) {
            env->DeleteGlobalRef(ctx->listener);
        }
        delete ctx;
    }
    return static_cast<jint>(rc);
}

// JNI passthrough for the new cancel ABI. Does NOT touch the
// listener registry — cancel is independent of destroy and the caller is
// expected to invoke both (cancel from any thread to interrupt; destroy from
// the orchestration coroutine once the in-flight call has resolved).
JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racToolCallingSessionCancelProto(
    JNIEnv* env, jclass clazz, jlong sessionHandle) {
    (void)env;
    (void)clazz;
    if (sessionHandle == 0L)
        return RAC_ERROR_INVALID_HANDLE;
    return static_cast<jint>(
        rac_tool_calling_session_cancel_proto(static_cast<uint64_t>(sessionHandle)));
}

// =============================================================================
// Tool-calling run loop — single-call native orchestration.
// =============================================================================
//
// The canonical run-loop publishes its just-minted cancellation handle
// synchronously into Kotlin before generation begins. Both the executor and
// handle-publication callbacks fire on the thread that invoked the run-loop,
// so capturing the calling JNIEnv in the context struct is safe.
namespace {
struct RunLoopExecuteCtx {
    JNIEnv* env;
    jobject executor;   // fun interface: executeToolCall([B) -> [B]
    jobject on_handle;  // required fun interface: onHandlePublished(J)
    const char* operation;
};

rac_result_t run_loop_execute_trampoline(const uint8_t* in_tool_call_bytes, size_t in_size,
                                         rac_proto_buffer_t* out_tool_result_bytes,
                                         void* user_data) {
    if (out_tool_result_bytes == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }
    rac_proto_buffer_init(out_tool_result_bytes);
    auto* ctx = static_cast<RunLoopExecuteCtx*>(user_data);
    if (ctx == nullptr || ctx->env == nullptr || ctx->executor == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }
    JNIEnv* env = ctx->env;

    if (in_size > static_cast<size_t>(std::numeric_limits<jsize>::max())) {
        return RAC_ERROR_INVALID_PARAMETER;
    }
    jbyteArray inBytes = env->NewByteArray(static_cast<jsize>(in_size));
    if (inBytes == nullptr) {
        env->ExceptionClear();
        return RAC_ERROR_OUT_OF_MEMORY;
    }
    if (in_size > 0 && in_tool_call_bytes != nullptr) {
        env->SetByteArrayRegion(inBytes, 0, static_cast<jsize>(in_size),
                                reinterpret_cast<const jbyte*>(in_tool_call_bytes));
    }

    jclass cls = env->GetObjectClass(ctx->executor);
    jmethodID method = env->GetMethodID(cls, "executeToolCall", "([B)[B");
    env->DeleteLocalRef(cls);
    if (method == nullptr) {
        env->ExceptionClear();
        env->DeleteLocalRef(inBytes);
        return RAC_ERROR_INTERNAL;
    }
    auto resultBytes =
        static_cast<jbyteArray>(env->CallObjectMethod(ctx->executor, method, inBytes));
    env->DeleteLocalRef(inBytes);
    if (env->ExceptionCheck()) {
        env->ExceptionClear();
        if (resultBytes != nullptr) {
            env->DeleteLocalRef(resultBytes);
        }
        return RAC_ERROR_INTERNAL;
    }
    if (resultBytes == nullptr) {
        return RAC_ERROR_INTERNAL;
    }

    const jsize resultLen = env->GetArrayLength(resultBytes);
    jbyte* bytes = resultLen > 0 ? env->GetByteArrayElements(resultBytes, nullptr) : nullptr;
    rac_result_t rc = rac_proto_buffer_copy(reinterpret_cast<const uint8_t*>(bytes),
                                            static_cast<size_t>(resultLen), out_tool_result_bytes);
    if (bytes != nullptr) {
        env->ReleaseByteArrayElements(resultBytes, bytes, JNI_ABORT);
    }
    env->DeleteLocalRef(resultBytes);
    return rc;
}

void run_loop_handle_published_trampoline(uint64_t run_loop_handle, void* user_data) {
    auto* ctx = static_cast<RunLoopExecuteCtx*>(user_data);
    if (ctx == nullptr || ctx->env == nullptr || ctx->on_handle == nullptr) {
        return;
    }
    JNIEnv* env = ctx->env;
    jclass cls = env->GetObjectClass(ctx->on_handle);
    jmethodID method = env->GetMethodID(cls, "onHandlePublished", "(J)V");
    env->DeleteLocalRef(cls);
    if (method == nullptr) {
        env->ExceptionClear();
        return;
    }
    env->CallVoidMethod(ctx->on_handle, method, static_cast<jlong>(run_loop_handle));
    if (env->ExceptionCheck()) {
        env->ExceptionClear();
    }
}
}  // namespace

JNIEXPORT jbyteArray JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racToolCallingRunLoopProto(
    JNIEnv* env, jclass clazz, jbyteArray requestBytes, jobject executor, jobject onHandle) {
    (void)clazz;
    static const char* operation = "racToolCallingRunLoopProto";
    JByteArrayView request(env, requestBytes);
    if (!request.ok || executor == nullptr || onHandle == nullptr) {
        return makeProtoCallResult(env, RAC_ERROR_NULL_POINTER, nullptr, operation);
    }
    RAC_JNI_TRY {
        RunLoopExecuteCtx ctx{
            .env = env, .executor = executor, .on_handle = onHandle, .operation = operation};
        rac_proto_buffer_t result = {};
        rac_proto_buffer_init(&result);
        rac_result_t rc = rac_tool_calling_run_loop_proto(
            request.u8(), request.size(), run_loop_execute_trampoline, &ctx,
            run_loop_handle_published_trampoline, &ctx, &result);
        return makeProtoCallResult(env, rc, &result, operation);
    }
    RAC_JNI_CATCH_PTR()
}

// cancel the in-flight run loop from any thread. Idempotent —
// a stale/zero handle is a no-op returning RAC_SUCCESS.
JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racToolCallingRunLoopCancelProto(
    JNIEnv* env, jclass clazz, jlong runLoopHandle) {
    (void)env;
    (void)clazz;
    if (runLoopHandle == 0L)
        return RAC_SUCCESS;
    return static_cast<jint>(
        rac_tool_calling_run_loop_cancel_proto(static_cast<uint64_t>(runLoopHandle)));
}

// =============================================================================
// Tool-value JSON bridge (G3) — rac_tool_value_{to,from}_json_proto.
// Replaces the per-SDK recursive ToolValue<->JSON walk. Mirrors Swift's
// ToolCallingTypes.swift which loads the same two symbols.
// =============================================================================

JNIEXPORT jbyteArray JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racToolValueToJsonProto(
    JNIEnv* env, jclass clazz, jbyteArray toolValueProto) {
    return callProtoBufferFn(env, toolValueProto, rac_tool_value_to_json_proto,
                             "racToolValueToJsonProto");
}

JNIEXPORT jbyteArray JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racToolValueFromJsonProto(
    JNIEnv* env, jclass clazz, jbyteArray toolValueJsonProto) {
    return callProtoBufferFn(env, toolValueJsonProto, rac_tool_value_from_json_proto,
                             "racToolValueFromJsonProto");
}

// =============================================================================
// JNI FUNCTIONS - Solutions (rac/solutions/rac_solution.h)
// =============================================================================
//
// Proto-byte / YAML driven L5 solution runtime. One-to-one
// mapping over `rac_solution_*`; the Kotlin handle is the C handle cast
// to jlong. 0 from create_from_* signals failure and the handle was
// never allocated, so destroy is a no-op for it.

JNIEXPORT jlong JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racSolutionCreateFromProto(
    JNIEnv* env, jclass clazz, jbyteArray configBytes) {
    (void)clazz;
    if (configBytes == nullptr)
        return 0L;

    const jsize len = env->GetArrayLength(configBytes);
    jbyte* bytes = env->GetByteArrayElements(configBytes, nullptr);
    if (bytes == nullptr)
        return 0L;

    rac_solution_handle_t handle = nullptr;
    const rac_result_t result = rac_solution_create_from_proto(static_cast<const void*>(bytes),
                                                               static_cast<size_t>(len), &handle);

    env->ReleaseByteArrayElements(configBytes, bytes, JNI_ABORT);

    if (result != RAC_SUCCESS) {
        LOGe("racSolutionCreateFromProto failed: %d", result);
        return 0L;
    }
    return reinterpret_cast<jlong>(handle);
}

JNIEXPORT jlong JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racSolutionCreateFromYaml(
    JNIEnv* env, jclass clazz, jstring yamlText) {
    (void)clazz;
    if (yamlText == nullptr)
        return 0L;

    const char* utf = env->GetStringUTFChars(yamlText, nullptr);
    if (utf == nullptr)
        return 0L;

    rac_solution_handle_t handle = nullptr;
    const rac_result_t result = rac_solution_create_from_yaml(utf, &handle);

    env->ReleaseStringUTFChars(yamlText, utf);

    if (result != RAC_SUCCESS) {
        LOGe("racSolutionCreateFromYaml failed: %d", result);
        return 0L;
    }
    return reinterpret_cast<jlong>(handle);
}

JNIEXPORT jint JNICALL Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racSolutionStart(
    JNIEnv* env, jclass clazz, jlong handle) {
    (void)env;
    (void)clazz;
    if (handle == 0L)
        return static_cast<jint>(RAC_ERROR_NULL_POINTER);
    return static_cast<jint>(rac_solution_start(reinterpret_cast<rac_solution_handle_t>(handle)));
}

JNIEXPORT jint JNICALL Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racSolutionStop(
    JNIEnv* env, jclass clazz, jlong handle) {
    (void)env;
    (void)clazz;
    if (handle == 0L)
        return static_cast<jint>(RAC_ERROR_NULL_POINTER);
    return static_cast<jint>(rac_solution_stop(reinterpret_cast<rac_solution_handle_t>(handle)));
}

JNIEXPORT jint JNICALL Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racSolutionCancel(
    JNIEnv* env, jclass clazz, jlong handle) {
    (void)env;
    (void)clazz;
    if (handle == 0L)
        return static_cast<jint>(RAC_ERROR_NULL_POINTER);
    return static_cast<jint>(rac_solution_cancel(reinterpret_cast<rac_solution_handle_t>(handle)));
}

JNIEXPORT jint JNICALL Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racSolutionFeed(
    JNIEnv* env, jclass clazz, jlong handle, jstring item) {
    (void)clazz;
    if (handle == 0L)
        return static_cast<jint>(RAC_ERROR_NULL_POINTER);
    if (item == nullptr)
        return static_cast<jint>(RAC_ERROR_NULL_POINTER);

    const char* utf = env->GetStringUTFChars(item, nullptr);
    if (utf == nullptr)
        return static_cast<jint>(RAC_ERROR_OUT_OF_MEMORY);

    const rac_result_t result =
        rac_solution_feed(reinterpret_cast<rac_solution_handle_t>(handle), utf);

    env->ReleaseStringUTFChars(item, utf);
    return static_cast<jint>(result);
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racSolutionCloseInput(JNIEnv* env,
                                                                               jclass clazz,
                                                                               jlong handle) {
    (void)env;
    (void)clazz;
    if (handle == 0L)
        return static_cast<jint>(RAC_ERROR_NULL_POINTER);
    return static_cast<jint>(
        rac_solution_close_input(reinterpret_cast<rac_solution_handle_t>(handle)));
}

JNIEXPORT void JNICALL Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racSolutionDestroy(
    JNIEnv* env, jclass clazz, jlong handle) {
    (void)env;
    (void)clazz;
    if (handle == 0L)
        return;
    rac_solution_destroy(reinterpret_cast<rac_solution_handle_t>(handle));
}

// =============================================================================
// JNI FUNCTIONS - Native HTTP request/response
// =============================================================================
//
// Single blocking entrypoint for buffered HTTP request/response. Wraps
// rac_http_client_create + rac_http_request_send + rac_http_response_free
// + rac_http_client_destroy into one call so Kotlin never touches the
// native client lifecycle (matches Swift's HTTPClientAdapter parity layer).
// Requests are executed by the platform transport registered via
// rac_http_transport_register (OkHttpHttpTransport on Android). Kotlin
// callers: CppBridgeAuth.kt (authenticate / refresh) and
// CppBridgeTelemetry.kt (telemetry batches).

namespace {

// Returns a freshly-allocated NativeHttpResponse. Caller-owned local refs.
jobject build_native_http_response(JNIEnv* env, jint statusCode, const uint8_t* body,
                                   size_t body_len, const rac_http_header_kv_t* headers,
                                   size_t header_count, const char* error_message) {
    jclass strCls = env->FindClass("java/lang/String");

    // Body: empty array when the transport layer produced no bytes.
    jbyteArray jBody = env->NewByteArray(static_cast<jsize>(body_len));
    if (body && body_len > 0) {
        env->SetByteArrayRegion(jBody, 0, static_cast<jsize>(body_len),
                                reinterpret_cast<const jbyte*>(body));
    }

    // Headers: parallel String[] arrays (avoids Map<String,String> marshaling
    // and keeps the JNI signature simple).
    jobjectArray jKeys = env->NewObjectArray(static_cast<jsize>(header_count), strCls, nullptr);
    jobjectArray jVals = env->NewObjectArray(static_cast<jsize>(header_count), strCls, nullptr);
    for (size_t i = 0; i < header_count; ++i) {
        if (headers[i].name) {
            jstring k = env->NewStringUTF(headers[i].name);
            env->SetObjectArrayElement(jKeys, static_cast<jsize>(i), k);
            env->DeleteLocalRef(k);
        }
        if (headers[i].value) {
            jstring v = env->NewStringUTF(headers[i].value);
            env->SetObjectArrayElement(jVals, static_cast<jsize>(i), v);
            env->DeleteLocalRef(v);
        }
    }

    jstring jErr = error_message ? env->NewStringUTF(error_message) : nullptr;

    jclass respCls = env->FindClass("com/runanywhere/sdk/native/bridge/NativeHttpResponse");
    if (!respCls) {
        LOGe("build_native_http_response: NativeHttpResponse class not found");
        return nullptr;
    }
    jmethodID ctor = env->GetMethodID(
        respCls, "<init>", "(I[B[Ljava/lang/String;[Ljava/lang/String;Ljava/lang/String;)V");
    if (!ctor) {
        LOGe("build_native_http_response: NativeHttpResponse ctor not found");
        env->DeleteLocalRef(respCls);
        return nullptr;
    }
    jobject obj = env->NewObject(respCls, ctor, statusCode, jBody, jKeys, jVals, jErr);
    env->DeleteLocalRef(respCls);
    return obj;
}

}  // namespace

JNIEXPORT jobject JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racHttpRequestExecute(
    JNIEnv* env, jclass /*clazz*/, jstring jMethod, jstring jUrl, jobjectArray jHeaderKeys,
    jobjectArray jHeaderValues, jbyteArray jBody, jint timeoutMs, jboolean followRedirects) {
    if (!jMethod || !jUrl) {
        return build_native_http_response(env, -1, nullptr, 0, nullptr, 0,
                                          "Invalid argument: method/url is null");
    }

    // Pin Kotlin strings for the request lifetime. rac_http_request_t
    // requires the pointers stay valid until rac_http_request_send returns.
    const char* method = env->GetStringUTFChars(jMethod, nullptr);
    const char* url = env->GetStringUTFChars(jUrl, nullptr);

    // Copy headers into stable std::string storage so the KV array
    // remains valid after we release the Kotlin String handles.
    jsize headerCount = 0;
    if (jHeaderKeys && jHeaderValues) {
        jsize k = env->GetArrayLength(jHeaderKeys);
        jsize v = env->GetArrayLength(jHeaderValues);
        headerCount = k < v ? k : v;
    }
    std::vector<std::string> hNames;
    std::vector<std::string> hValues;
    std::vector<rac_http_header_kv_t> hKVs;
    hNames.reserve(static_cast<size_t>(headerCount));
    hValues.reserve(static_cast<size_t>(headerCount));
    hKVs.reserve(static_cast<size_t>(headerCount));
    for (jsize i = 0; i < headerCount; ++i) {
        auto jk = reinterpret_cast<jstring>(env->GetObjectArrayElement(jHeaderKeys, i));
        auto jv = reinterpret_cast<jstring>(env->GetObjectArrayElement(jHeaderValues, i));
        if (!jk || !jv) {
            if (jk)
                env->DeleteLocalRef(jk);
            if (jv)
                env->DeleteLocalRef(jv);
            continue;
        }
        hNames.emplace_back(getCString(env, jk));
        hValues.emplace_back(getCString(env, jv));
        env->DeleteLocalRef(jk);
        env->DeleteLocalRef(jv);
    }
    for (size_t i = 0; i < hNames.size(); ++i) {
        rac_http_header_kv_t kv{};
        kv.name = hNames[i].c_str();
        kv.value = hValues[i].c_str();
        hKVs.push_back(kv);
    }

    // Body bytes: copy into std::vector so we can safely pass a raw pointer.
    std::vector<uint8_t> bodyBuf;
    if (jBody) {
        jsize n = env->GetArrayLength(jBody);
        bodyBuf.resize(static_cast<size_t>(n));
        if (n > 0) {
            env->GetByteArrayRegion(jBody, 0, n, reinterpret_cast<jbyte*>(bodyBuf.data()));
        }
    }

    rac_http_request_t req{};
    req.method = method;
    req.url = url;
    req.headers = hKVs.empty() ? nullptr : hKVs.data();
    req.header_count = hKVs.size();
    req.body_bytes = bodyBuf.empty() ? nullptr : bodyBuf.data();
    req.body_len = bodyBuf.size();
    req.timeout_ms = timeoutMs > 0 ? timeoutMs : 0;
    req.follow_redirects = followRedirects == JNI_TRUE ? RAC_TRUE : RAC_FALSE;

    // Route through the internal C++ HTTP facade.
    // The facade owns the rac_http_client_t lifecycle internally and
    // routes the send through the registered platform transport when
    // one is installed, else falls back to libcurl.
    rac_http_response_t resp{};
    rac_result_t rc = rac::http::execute(req, resp);

    jobject result = nullptr;
    if (rc != RAC_SUCCESS) {
        const char* errMsg = "HTTP transport error";
        switch (rc) {
            case RAC_ERROR_NETWORK_ERROR:
                errMsg = "Network error";
                break;
            case RAC_ERROR_TIMEOUT:
                errMsg = "Request timeout";
                break;
            case RAC_ERROR_CANCELLED:
                errMsg = "Request cancelled";
                break;
            case RAC_ERROR_INVALID_ARGUMENT:
                errMsg = "Invalid HTTP argument";
                break;
            case RAC_ERROR_OUT_OF_MEMORY:
                errMsg = "Out of memory";
                break;
            default:
                break;
        }
        result = build_native_http_response(env, -1, nullptr, 0, nullptr, 0, errMsg);
    } else {
        result =
            build_native_http_response(env, static_cast<jint>(resp.status), resp.body_bytes,
                                       resp.body_len, resp.headers, resp.header_count, nullptr);
    }

    rac_http_response_free(&resp);

    env->ReleaseStringUTFChars(jMethod, method);
    env->ReleaseStringUTFChars(jUrl, url);

    return result;
}

// =============================================================================
// JNI FUNCTIONS - HTTP default headers (R7.C)
// =============================================================================
//
// Thunk for `rac_http_default_headers`. Marshals commons' canonical SDK
// header list (X-SDK-Client / X-SDK-Version / Content-Type / Accept — the
// "X-Platform" header is intentionally excluded and must be supplied
// per-SDK) as a flat alternating String[] (`[k0, v0, k1, v1, ...]`).
// The Kotlin adapter (HTTPClientAdapter.jvmAndroid.kt) groups consecutive
// pairs back into `List<Pair<String, String>>`.
//
// Returns null on any failure so the Kotlin caller falls back to the
// pre-thunk inlined header policy.
JNIEXPORT jobjectArray JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racHttpDefaultHeaders(JNIEnv* env,
                                                                               jclass /*clazz*/) {
    const rac_http_header_kv_t* kvs = nullptr;
    size_t count = 0;
    rac_result_t rc = rac_http_default_headers(&kvs, &count);
    if (rc != RAC_SUCCESS || kvs == nullptr || count == 0) {
        return nullptr;
    }

    jclass strCls = env->FindClass("java/lang/String");
    if (strCls == nullptr) {
        return nullptr;
    }

    const jsize flatLen = static_cast<jsize>(count * 2);
    jobjectArray result = env->NewObjectArray(flatLen, strCls, nullptr);
    if (result == nullptr) {
        return nullptr;
    }

    for (size_t i = 0; i < count; ++i) {
        const char* name = kvs[i].name != nullptr ? kvs[i].name : "";
        const char* value = kvs[i].value != nullptr ? kvs[i].value : "";
        jstring jName = env->NewStringUTF(name);
        jstring jValue = env->NewStringUTF(value);
        env->SetObjectArrayElement(result, static_cast<jsize>(i * 2), jName);
        env->SetObjectArrayElement(result, static_cast<jsize>(i * 2 + 1), jValue);
        env->DeleteLocalRef(jName);
        env->DeleteLocalRef(jValue);
    }

    return result;
}

// Thunk for `rac_api_error_from_response` (rac_api_types.h). Parses a
// structured API error out of a 4xx/5xx response body — the same commons
// helper Swift's HTTPClientAdapter.mapAPIError consumes. Returns a 3-element
// String[]: [message, code, request_url] (any element may be null when the
// body carried no such field), or null when commons could not parse the
// response at all. The rac_api_error_t buffers are freed here via
// rac_api_error_free before returning.
JNIEXPORT jobjectArray JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racApiErrorFromResponse(
    JNIEnv* env, jclass /*clazz*/, jint statusCode, jstring body, jstring url) {
    std::string bodyStr = getCString(env, body);
    std::string urlStr = getCString(env, url);

    rac_api_error_t apiError;
    if (rac_api_error_from_response(static_cast<int>(statusCode), bodyStr.c_str(), urlStr.c_str(),
                                    &apiError) != 0) {
        return nullptr;
    }

    jclass strCls = env->FindClass("java/lang/String");
    if (strCls == nullptr) {
        rac_api_error_free(&apiError);
        return nullptr;
    }
    jobjectArray arr = env->NewObjectArray(3, strCls, nullptr);
    env->DeleteLocalRef(strCls);
    if (arr == nullptr) {
        rac_api_error_free(&apiError);
        return nullptr;
    }

    const char* fields[3] = {apiError.message, apiError.code, apiError.request_url};
    for (jsize i = 0; i < 3; ++i) {
        if (fields[i] == nullptr) {
            continue;
        }
        jstring jField = env->NewStringUTF(fields[i]);
        if (jField != nullptr) {
            env->SetObjectArrayElement(arr, i, jField);
            env->DeleteLocalRef(jField);
        }
    }
    rac_api_error_free(&apiError);
    return arr;
}

// =============================================================================
// JNI FUNCTIONS - Engine Router Capabilities
//
// `rac_router_frameworks_for_capability_proto` consumes a serialized
// FrameworksForCapabilityRequest and returns a serialized
// FrameworksForCapabilityResponse. Kotlin replaces the local when-mapping
// in RunAnywhere+Frameworks.jvmAndroid.kt with one call here.
// =============================================================================

JNIEXPORT jbyteArray JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racRouterFrameworksForCapabilityProto(
    JNIEnv* env, jclass clazz, jbyteArray requestProto) {
    const jsize length = requestProto != nullptr ? env->GetArrayLength(requestProto) : 0;
    jbyte* requestBytes = length > 0 ? env->GetByteArrayElements(requestProto, nullptr) : nullptr;
    if (length > 0 && requestBytes == nullptr) {
        LOGe("racRouterFrameworksForCapabilityProto: failed to access JNI byte array");
        return nullptr;
    }

    uint8_t* responseBytes = nullptr;
    size_t responseSize = 0;
    rac_result_t rc = rac_router_frameworks_for_capability_proto(
        reinterpret_cast<const uint8_t*>(requestBytes), static_cast<size_t>(length), &responseBytes,
        &responseSize);
    if (requestBytes != nullptr) {
        env->ReleaseByteArrayElements(requestProto, requestBytes, JNI_ABORT);
    }
    if (rc != RAC_SUCCESS) {
        rac_router_frameworks_for_capability_proto_free(responseBytes);
        LOGe("racRouterFrameworksForCapabilityProto: failed with code %d", rc);
        return nullptr;
    }

    jbyteArray jArr = env->NewByteArray(static_cast<jsize>(responseSize));
    if (jArr == nullptr) {
        rac_router_frameworks_for_capability_proto_free(responseBytes);
        LOGe("racRouterFrameworksForCapabilityProto: failed to allocate jbyteArray");
        return nullptr;
    }
    if (responseSize > 0) {
        env->SetByteArrayRegion(jArr, 0, static_cast<jsize>(responseSize),
                                reinterpret_cast<const jbyte*>(responseBytes));
    }
    rac_router_frameworks_for_capability_proto_free(responseBytes);
    return env->ExceptionCheck() ? nullptr : jArr;
}

JNIEXPORT jbyteArray JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racStructuredOutputParseProto(
    JNIEnv* env, jclass clazz, jbyteArray requestProto) {
    return callProtoBufferFn(env, requestProto, rac_structured_output_parse_proto,
                             "racStructuredOutputParseProto");
}

JNIEXPORT jbyteArray JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racStructuredOutputPreparePromptProto(
    JNIEnv* env, jclass clazz, jbyteArray requestProto) {
    return callProtoBufferFn(env, requestProto, rac_structured_output_prepare_prompt_proto,
                             "racStructuredOutputPreparePromptProto");
}

JNIEXPORT jbyteArray JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racStructuredOutputValidateProto(
    JNIEnv* env, jclass clazz, jbyteArray requestProto) {
    return callProtoBufferFn(env, requestProto, rac_structured_output_validate_proto,
                             "racStructuredOutputValidateProto");
}

JNIEXPORT jbyteArray JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racStructuredOutputSchemaToJsonProto(
    JNIEnv* env, jclass clazz, jbyteArray schemaProto) {
    return callProtoBufferFn(env, schemaProto, rac_structured_output_schema_to_json_proto,
                             "racStructuredOutputSchemaToJsonProto");
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racStructuredOutputGenerateStreamProto(
    JNIEnv* env, jclass clazz, jbyteArray requestProto, jobject listener) {
    (void)clazz;
    JByteArrayView request(env, requestProto);
    if (!request.ok)
        return RAC_ERROR_NULL_POINTER;

    jobject globalListener = listener != nullptr ? env->NewGlobalRef(listener) : nullptr;
    ProtoListenerUserData ctx{.listener = globalListener,
                              .operation = "racStructuredOutputGenerateStreamProto"};
    rac_result_t rc = rac_structured_output_generate_stream_proto(
        request.u8(), request.size(), globalListener != nullptr ? proto_void_callback : nullptr,
        globalListener != nullptr ? &ctx : nullptr);
    if (globalListener != nullptr) {
        env->DeleteGlobalRef(globalListener);
    }
    return static_cast<jint>(rc);
}

// =============================================================================
// JNI FUNCTIONS - VAD Statistics
// Swift's setVADStatisticsCallback needs ambientLevel, recentAvg, recentMax.
// =============================================================================

// =============================================================================
// JNI FUNCTIONS - Model Registry Fetch Assignments
//
// The JSON-stringy shim (`racModelRegistryFetchAssignments` returning an
// array of model IDs) was deleted. Kotlin and Web both call
// `racModelRegistryFetchAssignmentsProto` which returns a serialized
// `runanywhere.v1.ModelInfoList`.
// =============================================================================

// =============================================================================
// JNI FUNCTIONS — Swift-alignment
//
// Bulk thunk bootstrap added to unblock the Kotlin SDK's Swift-alignment
// effort. Each thunk is a thin wrapper over the matching rac_* C ABI.
// =============================================================================

// ---------- Component metadata getters --------------------------------

JNIEXPORT jboolean JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racVadComponentIsInitialized(
    JNIEnv* env, jclass clazz, jlong handle) {
    (void)env;
    (void)clazz;
    if (handle == 0L)
        return JNI_FALSE;
    return rac_vad_component_is_initialized(handleFromJLong(handle)) == RAC_TRUE ? JNI_TRUE
                                                                                 : JNI_FALSE;
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racVadComponentUnload(JNIEnv* env,
                                                                               jclass clazz,
                                                                               jlong handle) {
    (void)env;
    (void)clazz;
    if (handle == 0L)
        return RAC_ERROR_NULL_POINTER;
    return static_cast<jint>(rac_vad_component_unload(handleFromJLong(handle)));
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racVadComponentCleanup(JNIEnv* env,
                                                                                jclass clazz,
                                                                                jlong handle) {
    (void)env;
    (void)clazz;
    if (handle == 0L)
        return RAC_ERROR_NULL_POINTER;
    return static_cast<jint>(rac_vad_component_cleanup(handleFromJLong(handle)));
}

JNIEXPORT jboolean JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racSttComponentSupportsStreaming(
    JNIEnv* env, jclass clazz, jlong handle) {
    (void)env;
    (void)clazz;
    if (handle == 0L)
        return JNI_FALSE;
    return rac_stt_component_supports_streaming(handleFromJLong(handle)) == RAC_TRUE ? JNI_TRUE
                                                                                     : JNI_FALSE;
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racSttComponentConfigure(JNIEnv* env,
                                                                                  jclass clazz,
                                                                                  jlong handle,
                                                                                  jint framework) {
    (void)env;
    (void)clazz;
    if (handle == 0L)
        return RAC_ERROR_NULL_POINTER;
    rac_stt_config_t config = RAC_STT_CONFIG_DEFAULT;
    config.preferred_framework = static_cast<int32_t>(framework);
    return static_cast<jint>(rac_stt_component_configure(handleFromJLong(handle), &config));
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racVoiceAgentCleanup(JNIEnv* env,
                                                                              jclass clazz,
                                                                              jlong handle) {
    (void)env;
    (void)clazz;
    if (handle == 0L)
        return RAC_ERROR_NULL_POINTER;
    return static_cast<jint>(
        rac_voice_agent_cleanup(reinterpret_cast<rac_voice_agent_handle_t>(handle)));
}

// ---------- Proto bridges (lifecycle + registry + structured output) --

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racSdkEventClearQueue(JNIEnv* env,
                                                                               jclass clazz) {
    (void)env;
    (void)clazz;
    rac_sdk_event_clear_queue();
    return RAC_SUCCESS;
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racModelLifecycleReset(JNIEnv* env,
                                                                                jclass clazz) {
    (void)env;
    (void)clazz;
    rac_model_lifecycle_reset();
    return RAC_SUCCESS;
}

JNIEXPORT jbyteArray JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racModelRegistryDiscoverProto(
    JNIEnv* env, jclass clazz, jbyteArray req) {
    return callModelRegistryProtoBuffer(env, req, rac_model_registry_discover_proto,
                                        "racModelRegistryDiscoverProto");
}

JNIEXPORT jbyteArray JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racModelRegistryImportProto(
    JNIEnv* env, jclass clazz, jbyteArray req) {
    return callModelRegistryProtoBuffer(env, req, rac_model_registry_import_proto,
                                        "racModelRegistryImportProto");
}

JNIEXPORT jbyteArray JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racStructuredOutputGenerateProto(
    JNIEnv* env, jclass clazz, jlong handle, jbyteArray req) {
    (void)clazz;
    (void)handle;  // current C ABI is handle-less; reserved for forward compatibility
    return callProtoBufferFn(env, req, rac_structured_output_generate_proto,
                             "racStructuredOutputGenerateProto");
}

// Per-handle LLM stream-event proto callback. The trampoline forwards proto
// bytes to the Kotlin NativeProtoProgressListener via the shared
// llmStreamListeners() registry (see HandleListenerRegistry above).
static void llm_stream_proto_trampoline(const uint8_t* proto_bytes, size_t proto_size,
                                        void* user_data) {
    dispatchHandleListener(llmStreamListeners(), proto_bytes, proto_size, user_data,
                           "llmStreamProtoCallback");
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racLlmSetStreamProtoCallback(
    JNIEnv* env, jclass clazz, jlong handle, jobject listener) {
    (void)clazz;
    if (handle == 0L)
        return RAC_ERROR_NULL_POINTER;
    uintptr_t key = static_cast<uintptr_t>(handle);
    RAC_JNI_TRY {
        llmStreamListeners().set(env, key, listener);
        return static_cast<jint>(rac_llm_set_stream_proto_callback(
            handleFromJLong(handle), listener != nullptr ? llm_stream_proto_trampoline : nullptr,
            listener != nullptr ? reinterpret_cast<void*>(key) : nullptr));
    }
    RAC_JNI_CATCH_INT()
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racLlmUnsetStreamProtoCallback(
    JNIEnv* env, jclass clazz, jlong handle) {
    (void)clazz;
    if (handle == 0L)
        return RAC_ERROR_NULL_POINTER;
    uintptr_t key = static_cast<uintptr_t>(handle);
    llmStreamListeners().erase(env, key);
    return static_cast<jint>(rac_llm_unset_stream_proto_callback(handleFromJLong(handle)));
}

// ---------- SDK state accessors ---------------------------------------

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racStateGetEnvironment(JNIEnv* env,
                                                                                jclass clazz) {
    (void)env;
    (void)clazz;
    return static_cast<jint>(rac_state_get_environment());
}

JNIEXPORT jstring JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racStateGetBaseUrl(JNIEnv* env,
                                                                            jclass clazz) {
    (void)clazz;
    const char* value = rac_state_get_base_url();
    return value != nullptr ? env->NewStringUTF(value) : nullptr;
}

JNIEXPORT jstring JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racStateGetApiKey(JNIEnv* env,
                                                                           jclass clazz) {
    (void)clazz;
    const char* value = rac_state_get_api_key();
    return value != nullptr ? env->NewStringUTF(value) : nullptr;
}

JNIEXPORT jstring JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racStateGetDeviceId(JNIEnv* env,
                                                                             jclass clazz) {
    (void)clazz;
    const char* value = rac_state_get_device_id();
    return value != nullptr ? env->NewStringUTF(value) : nullptr;
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racStateSetDeviceRegistered(
    JNIEnv* env, jclass clazz, jboolean registered) {
    (void)env;
    (void)clazz;
    rac_state_set_device_registered(registered == JNI_TRUE);
    return RAC_SUCCESS;
}

JNIEXPORT jboolean JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racStateIsDeviceRegistered(JNIEnv* env,
                                                                                    jclass clazz) {
    (void)env;
    (void)clazz;
    return rac_state_is_device_registered() ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT void JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racStateReset(JNIEnv* env, jclass clazz) {
    (void)env;
    (void)clazz;
    rac_state_reset();
}

JNIEXPORT jstring JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racDeviceGetOrCreatePersistentId(
    JNIEnv* env, jclass clazz, jintArray outRc) {
    (void)clazz;
    auto writeRc = [&](rac_result_t rc) {
        if (outRc == nullptr || env->GetArrayLength(outRc) < 1) {
            return;
        }
        const jint value = static_cast<jint>(rc);
        env->SetIntArrayRegion(outRc, 0, 1, &value);
    };
    char buf[RAC_DEVICE_ID_BUFFER_MIN_SIZE * 2] = {0};
    rac_result_t rc = rac_device_get_or_create_persistent_id(buf, sizeof(buf));
    writeRc(rc);
    if (rc != RAC_SUCCESS) {
        return nullptr;
    }
    return env->NewStringUTF(buf);
}

// ---------- Archive enum mappers --------------------------------------

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racArchiveTypeFromProto(JNIEnv* env,
                                                                                 jclass clazz,
                                                                                 jint value) {
    (void)env;
    (void)clazz;
    rac_archive_type_t out = static_cast<rac_archive_type_t>(0);
    rac_result_t rc = rac_archive_type_from_proto(static_cast<int32_t>(value), &out);
    return rc == RAC_SUCCESS ? static_cast<jint>(out) : -1;
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racArchiveTypeToProto(JNIEnv* env,
                                                                               jclass clazz,
                                                                               jint value) {
    (void)env;
    (void)clazz;
    int32_t out = 0;
    rac_result_t rc = rac_archive_type_to_proto(static_cast<rac_archive_type_t>(value), &out);
    return rc == RAC_SUCCESS ? static_cast<jint>(out) : -1;
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racArchiveStructureFromProto(JNIEnv* env,
                                                                                      jclass clazz,
                                                                                      jint value) {
    (void)env;
    (void)clazz;
    rac_archive_structure_t out = static_cast<rac_archive_structure_t>(0);
    rac_result_t rc = rac_archive_structure_from_proto(static_cast<int32_t>(value), &out);
    return rc == RAC_SUCCESS ? static_cast<jint>(out) : -1;
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racArchiveStructureToProto(JNIEnv* env,
                                                                                    jclass clazz,
                                                                                    jint value) {
    (void)env;
    (void)clazz;
    int32_t out = 0;
    rac_result_t rc =
        rac_archive_structure_to_proto(static_cast<rac_archive_structure_t>(value), &out);
    return rc == RAC_SUCCESS ? static_cast<jint>(out) : -1;
}

// ---------- Model paths -----------------------------------------------

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racModelPathsSetBaseDirectory(
    JNIEnv* env, jclass clazz, jstring path) {
    (void)clazz;
    std::string p = getCString(env, path);
    return static_cast<jint>(rac_model_paths_set_base_dir(p.c_str()));
}

JNIEXPORT jstring JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racModelPathsGetModelsDirectory(
    JNIEnv* env, jclass clazz) {
    (void)clazz;
    char buf[2048] = {0};
    if (rac_model_paths_get_models_directory(buf, sizeof(buf)) != RAC_SUCCESS) {
        return nullptr;
    }
    return env->NewStringUTF(buf);
}

JNIEXPORT jstring JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racModelPathsGetFrameworkDirectory(
    JNIEnv* env, jclass clazz, jint framework) {
    (void)clazz;
    char buf[2048] = {0};
    if (rac_model_paths_get_framework_directory(static_cast<rac_inference_framework_t>(framework),
                                                buf, sizeof(buf)) != RAC_SUCCESS) {
        return nullptr;
    }
    return env->NewStringUTF(buf);
}

JNIEXPORT jstring JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racModelPathsGetExpectedModelPath(
    JNIEnv* env, jclass clazz, jstring modelId, jint framework, jint format) {
    (void)clazz;
    std::string mid = getCString(env, modelId);
    char buf[2048] = {0};
    if (rac_model_paths_get_expected_model_path(
            mid.c_str(), static_cast<rac_inference_framework_t>(framework),
            static_cast<rac_model_format_t>(format), buf, sizeof(buf)) != RAC_SUCCESS) {
        return nullptr;
    }
    return env->NewStringUTF(buf);
}

JNIEXPORT jstring JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racModelPathsGetCacheDirectory(
    JNIEnv* env, jclass clazz) {
    (void)clazz;
    char buf[2048] = {0};
    if (rac_model_paths_get_cache_directory(buf, sizeof(buf)) != RAC_SUCCESS) {
        return nullptr;
    }
    return env->NewStringUTF(buf);
}

JNIEXPORT jstring JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racModelPathsGetDownloadsDirectory(
    JNIEnv* env, jclass clazz) {
    (void)clazz;
    char buf[2048] = {0};
    if (rac_model_paths_get_downloads_directory(buf, sizeof(buf)) != RAC_SUCCESS) {
        return nullptr;
    }
    return env->NewStringUTF(buf);
}

JNIEXPORT jstring JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racModelPathsGetTempDirectory(
    JNIEnv* env, jclass clazz) {
    (void)clazz;
    char buf[2048] = {0};
    if (rac_model_paths_get_temp_directory(buf, sizeof(buf)) != RAC_SUCCESS) {
        return nullptr;
    }
    return env->NewStringUTF(buf);
}

JNIEXPORT jstring JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racModelPathsExtractModelId(JNIEnv* env,
                                                                                     jclass clazz,
                                                                                     jstring path) {
    (void)clazz;
    std::string p = getCString(env, path);
    char buf[512] = {0};
    if (rac_model_paths_extract_model_id(p.c_str(), buf, sizeof(buf)) != RAC_SUCCESS) {
        return nullptr;
    }
    return env->NewStringUTF(buf);
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racModelPathsExtractFramework(
    JNIEnv* env, jclass clazz, jstring path) {
    (void)clazz;
    std::string p = getCString(env, path);
    // -1 sentinel: the extractor below populates `fw` with a valid value.
    // NOLINTNEXTLINE(clang-analyzer-optin.core.EnumCastOutOfRange)
    rac_inference_framework_t fw = static_cast<rac_inference_framework_t>(-1);
    if (rac_model_paths_extract_framework(p.c_str(), &fw) != RAC_SUCCESS) {
        return -1;
    }
    return static_cast<jint>(fw);
}

JNIEXPORT jboolean JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racModelPathsIsModelPath(JNIEnv* env,
                                                                                  jclass clazz,
                                                                                  jstring path) {
    (void)clazz;
    std::string p = getCString(env, path);
    return rac_model_paths_is_model_path(p.c_str()) == RAC_TRUE ? JNI_TRUE : JNI_FALSE;
}

// Single-file role classifier (model-file-role-classifier family). Delegates to
// rac_infer_model_file_role so Kotlin shares the commons heuristic. Takes/returns
// proto ModelCategory / ModelFileRole int values.
JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racInferModelFileRole(JNIEnv* env,
                                                                               jclass clazz,
                                                                               jstring filename,
                                                                               jint modalityProto) {
    (void)clazz;
    std::string name = getCString(env, filename);
    int32_t role = RAC_MODEL_FILE_ROLE_PRIMARY_MODEL;
    rac_infer_model_file_role(name.c_str(), static_cast<int32_t>(modalityProto), &role);
    return static_cast<jint>(role);
}

// Canonical model-id derivation from a download URL. Delegates to
// rac_model_id_from_url — the commons port of Swift's generatedModelID(from:name:)
// — using the same 256-byte buffer Swift passes. Returns null on failure or when
// the URL yields an empty id so Kotlin can fall back to the human-readable name.
JNIEXPORT jstring JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racModelIdFromUrl(JNIEnv* env,
                                                                           jclass clazz,
                                                                           jstring url) {
    (void)clazz;
    std::string u = getCString(env, url);
    char buf[256] = {0};
    if (rac_model_id_from_url(u.c_str(), buf, sizeof(buf)) != RAC_SUCCESS || buf[0] == '\0') {
        return nullptr;
    }
    return env->NewStringUTF(buf);
}

// ---------- File manager (Swift-aligned aliases) ----------------------
//
// These call the rac_file_manager_* C ABI using Swift-aligned naming and a
// model-id-only (framework-implicit) signature, matching how Swift's
// CppBridge+FileManager surface looks. They superseded the older
// nativeFileManager* thunks (calculate/delete/check/info etc.), which have
// been removed.

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racFileManagerCreateDirectoryStructure(
    JNIEnv* env, jclass clazz, jstring rootPath) {
    (void)clazz;
    // rootPath is informational — the underlying ABI uses the registered
    // file callbacks (which know the base directory). We log the requested
    // root for debugging but otherwise forward to the canonical helper.
    if (rootPath != nullptr) {
        std::string r = getCString(env, rootPath);
        LOGd("racFileManagerCreateDirectoryStructure: root=%s", r.c_str());
    }
    rac_file_callbacks_t cb = build_jni_file_callbacks();
    return static_cast<jint>(rac_file_manager_create_directory_structure(&cb));
}

JNIEXPORT jlong JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racFileManagerCalculateDirectorySize(
    JNIEnv* env, jclass clazz, jstring path) {
    (void)clazz;
    std::string p = getCString(env, path);
    rac_file_callbacks_t cb = build_jni_file_callbacks();
    int64_t size = 0;
    rac_result_t rc = rac_file_manager_calculate_dir_size(&cb, p.c_str(), &size);
    return RAC_SUCCEEDED(rc) ? static_cast<jlong>(size) : 0L;
}

JNIEXPORT jlong JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racFileManagerModelsStorageUsed(
    JNIEnv* env, jclass clazz) {
    (void)env;
    (void)clazz;
    rac_file_callbacks_t cb = build_jni_file_callbacks();
    int64_t size = 0;
    rac_result_t rc = rac_file_manager_models_storage_used(&cb, &size);
    return RAC_SUCCEEDED(rc) ? static_cast<jlong>(size) : 0L;
}

JNIEXPORT jlong JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racFileManagerCacheSize(JNIEnv* env,
                                                                                 jclass clazz) {
    (void)env;
    (void)clazz;
    rac_file_callbacks_t cb = build_jni_file_callbacks();
    int64_t size = 0;
    rac_result_t rc = rac_file_manager_cache_size(&cb, &size);
    return RAC_SUCCEEDED(rc) ? static_cast<jlong>(size) : 0L;
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racFileManagerDeleteModel(
    JNIEnv* env, jclass clazz, jstring modelId) {
    (void)clazz;
    std::string mid = getCString(env, modelId);
    rac_file_callbacks_t cb = build_jni_file_callbacks();
    // Framework-implicit form: use UNKNOWN so the registry's path utils
    // strip the framework segment via the canonical layout.
    return static_cast<jint>(
        rac_file_manager_delete_model(&cb, mid.c_str(), static_cast<rac_inference_framework_t>(0)));
}

JNIEXPORT jboolean JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racFileManagerModelFolderExists(
    JNIEnv* env, jclass clazz, jstring modelId) {
    (void)clazz;
    std::string mid = getCString(env, modelId);
    rac_file_callbacks_t cb = build_jni_file_callbacks();
    rac_bool_t exists = RAC_FALSE;
    rac_file_manager_model_folder_exists(
        &cb, mid.c_str(), static_cast<rac_inference_framework_t>(0), &exists, nullptr);
    return exists == RAC_TRUE ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT jboolean JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racFileManagerModelFolderHasContents(
    JNIEnv* env, jclass clazz, jstring modelId) {
    (void)clazz;
    std::string mid = getCString(env, modelId);
    rac_file_callbacks_t cb = build_jni_file_callbacks();
    rac_bool_t exists = RAC_FALSE;
    rac_bool_t hasContents = RAC_FALSE;
    rac_file_manager_model_folder_exists(
        &cb, mid.c_str(), static_cast<rac_inference_framework_t>(0), &exists, &hasContents);
    return (exists == RAC_TRUE && hasContents == RAC_TRUE) ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT jbyteArray JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racFileManagerGetStorageInfo(
    JNIEnv* env, jclass clazz) {
    (void)clazz;
    rac_file_callbacks_t cb = build_jni_file_callbacks();
    rac_file_manager_storage_info_t info = {};
    rac_result_t rc = rac_file_manager_get_storage_info(&cb, &info);
    if (RAC_FAILED(rc)) {
        return nullptr;
    }
    // Encode as a fixed 6 × int64 little-endian payload — callers decode it
    // explicitly. The legacy JSON-returning nativeFileManagerGetStorageInfo
    // thunk has been removed.
    const size_t kFieldCount = 6;
    const size_t kPayloadSize = kFieldCount * sizeof(int64_t);
    int64_t fields[kFieldCount] = {info.device_total, info.device_free, info.models_size,
                                   info.cache_size,   info.temp_size,   info.total_app_size};
    jbyteArray jArr = env->NewByteArray(static_cast<jsize>(kPayloadSize));
    if (jArr == nullptr) {
        return nullptr;
    }
    env->SetByteArrayRegion(jArr, 0, static_cast<jsize>(kPayloadSize),
                            reinterpret_cast<const jbyte*>(fields));
    return env->ExceptionCheck() ? nullptr : jArr;
}

JNIEXPORT jboolean JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racFileManagerCheckStorage(
    JNIEnv* env, jclass clazz, jlong required) {
    (void)env;
    (void)clazz;
    rac_file_callbacks_t cb = build_jni_file_callbacks();
    rac_storage_availability_t availability = {};
    rac_result_t rc =
        rac_file_manager_check_storage(&cb, static_cast<int64_t>(required), &availability);
    bool ok = RAC_SUCCEEDED(rc) && availability.is_available == RAC_TRUE;
    rac_storage_availability_free(&availability);
    return ok ? JNI_TRUE : JNI_FALSE;
}

// ---------- Environment validation + endpoints ------------------------

JNIEXPORT jboolean JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racEnvIsProduction(JNIEnv* env,
                                                                            jclass clazz,
                                                                            jint envValue) {
    (void)env;
    (void)clazz;
    return rac_env_is_production(static_cast<rac_environment_t>(envValue)) ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT jboolean JNICALL Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racEnvIsTesting(
    JNIEnv* env, jclass clazz, jint envValue) {
    (void)env;
    (void)clazz;
    return rac_env_is_testing(static_cast<rac_environment_t>(envValue)) ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT jboolean JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racEnvShouldSendTelemetry(JNIEnv* env,
                                                                                   jclass clazz,
                                                                                   jint envValue) {
    (void)env;
    (void)clazz;
    return rac_env_should_send_telemetry(static_cast<rac_environment_t>(envValue)) ? JNI_TRUE
                                                                                   : JNI_FALSE;
}

JNIEXPORT jboolean JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racEnvShouldSyncWithBackend(
    JNIEnv* env, jclass clazz, jint envValue) {
    (void)env;
    (void)clazz;
    return rac_env_should_sync_with_backend(static_cast<rac_environment_t>(envValue)) ? JNI_TRUE
                                                                                      : JNI_FALSE;
}

JNIEXPORT jboolean JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racEnvRequiresAuth(JNIEnv* env,
                                                                            jclass clazz,
                                                                            jint envValue) {
    (void)env;
    (void)clazz;
    return rac_env_requires_auth(static_cast<rac_environment_t>(envValue)) ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT jboolean JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racEnvRequiresBackendUrl(JNIEnv* env,
                                                                                  jclass clazz,
                                                                                  jint envValue) {
    (void)env;
    (void)clazz;
    return rac_env_requires_backend_url(static_cast<rac_environment_t>(envValue)) ? JNI_TRUE
                                                                                  : JNI_FALSE;
}

JNIEXPORT jboolean JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racEnvValidateApiKey(JNIEnv* env,
                                                                              jclass clazz,
                                                                              jstring key) {
    (void)clazz;
    std::string k = getCString(env, key);
    rac_environment_t currentEnv = rac_state_get_environment();
    return rac_validate_api_key(k.c_str(), currentEnv) == RAC_VALIDATION_OK ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT jboolean JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racEnvValidateBaseUrl(JNIEnv* env,
                                                                               jclass clazz,
                                                                               jstring url) {
    (void)clazz;
    std::string u = getCString(env, url);
    rac_environment_t currentEnv = rac_state_get_environment();
    return rac_validate_base_url(u.c_str(), currentEnv) == RAC_VALIDATION_OK ? JNI_TRUE : JNI_FALSE;
}

JNIEXPORT jstring JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racEnvValidationErrorMessage(
    JNIEnv* env, jclass clazz, jint envValue, jstring key, jstring url) {
    (void)clazz;
    std::string keyStorage;
    std::string urlStorage;
    rac_sdk_config_t config = {};
    config.environment = static_cast<rac_environment_t>(envValue);
    config.api_key = getNullableCString(env, key, keyStorage);
    config.base_url = getNullableCString(env, url, urlStorage);
    config.device_id = nullptr;
    config.platform = nullptr;
    config.sdk_version = nullptr;
    rac_validation_result_t result = rac_validate_config(&config);
    if (result == RAC_VALIDATION_OK) {
        return nullptr;
    }
    const char* msg = rac_validation_error_message(result);
    return msg != nullptr ? env->NewStringUTF(msg) : nullptr;
}

JNIEXPORT jstring JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racEndpointAuthenticate(JNIEnv* env,
                                                                                 jclass clazz) {
    (void)clazz;
    return env->NewStringUTF(RAC_ENDPOINT_AUTHENTICATE);
}

JNIEXPORT jstring JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racEndpointRefresh(JNIEnv* env,
                                                                            jclass clazz) {
    (void)clazz;
    return env->NewStringUTF(RAC_ENDPOINT_REFRESH);
}

JNIEXPORT jstring JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racEndpointHealth(JNIEnv* env,
                                                                           jclass clazz) {
    (void)clazz;
    return env->NewStringUTF(RAC_ENDPOINT_HEALTH);
}

JNIEXPORT jstring JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racEndpointDeviceRegistration(
    JNIEnv* env, jclass clazz, jint envValue) {
    (void)clazz;
    const char* path = rac_endpoint_device_registration(static_cast<rac_environment_t>(envValue));
    return path != nullptr ? env->NewStringUTF(path) : nullptr;
}

JNIEXPORT jstring JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racEndpointModelAssignments(JNIEnv* env,
                                                                                     jclass clazz) {
    (void)clazz;
    const char* path = rac_endpoint_model_assignments();
    return path != nullptr ? env->NewStringUTF(path) : nullptr;
}

// ---------- Model assignment ------------------------------------------
//
// Kotlin registers no rac_assignment_callbacks_t: commons'
// model_assignment.cpp default routes the fetch through the registered
// platform HTTP transport (OkHttp) with control-plane auth headers, so
// racModelAssignmentFetch works without per-SDK callback wiring.

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racModelAssignmentSetCallbacks(
    JNIEnv* env, jclass clazz, jobject cb) {
    (void)env;
    (void)clazz;
    (void)cb;
    // No-op success kept for ABI stability: assignment fetch uses the commons
    // transport-backed default; there is no Kotlin-side callback plumbing.
    return RAC_SUCCESS;
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racModelAssignmentFetch(
    JNIEnv* env, jclass clazz, jboolean forceRefresh) {
    (void)env;
    (void)clazz;
    rac_model_info_t** models = nullptr;
    size_t count = 0;
    rac_result_t rc = rac_model_assignment_fetch(forceRefresh == JNI_TRUE ? RAC_TRUE : RAC_FALSE,
                                                 &models, &count);
    if (models != nullptr) {
        rac_model_info_array_free(models, count);
    }
    return static_cast<jint>(rc);
}

JNIEXPORT jbyteArray JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racModelAssignmentGetByFramework(
    JNIEnv* env, jclass clazz, jint framework) {
    (void)clazz;
    rac_model_info_t** models = nullptr;
    size_t count = 0;
    rac_result_t rc = rac_model_assignment_get_by_framework(
        static_cast<rac_inference_framework_t>(framework), &models, &count);
    if (rc != RAC_SUCCESS || models == nullptr) {
        if (models != nullptr)
            rac_model_info_array_free(models, count);
        return nullptr;
    }
    // Return a placeholder 0-byte payload to signal "result available, count
    // delivered separately". Callers that need typed results must use the
    // proto-based registry queries; this thunk's primary purpose is to
    // expose the symbol for forward compatibility with Swift's
    // CppBridge+ModelAssignment surface.
    rac_model_info_array_free(models, count);
    jbyteArray empty = env->NewByteArray(0);
    return empty;
}

JNIEXPORT jbyteArray JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racModelAssignmentGetByCategory(
    JNIEnv* env, jclass clazz, jint category) {
    (void)clazz;
    rac_model_info_t** models = nullptr;
    size_t count = 0;
    rac_result_t rc = rac_model_assignment_get_by_category(
        static_cast<rac_model_category_t>(category), &models, &count);
    if (rc != RAC_SUCCESS || models == nullptr) {
        if (models != nullptr)
            rac_model_info_array_free(models, count);
        return nullptr;
    }
    rac_model_info_array_free(models, count);
    jbyteArray empty = env->NewByteArray(0);
    return empty;
}

// =============================================================================
// INFERENCE FRAMEWORK display / analytics / raw tables (web-024).
// Replaces the hand-written 22-entry switch tables in Kotlin ModelTypes.kt
// with the canonical commons tables Swift consumes via cWireString. Each
// thunk takes the proto InferenceFramework int, converts to the C enum via
// rac_inference_framework_from_proto, then reads the static literal.
// =============================================================================

namespace {
rac_inference_framework_t frameworkFromProtoInt(int32_t protoValue) {
    rac_inference_framework_t out = RAC_FRAMEWORK_UNKNOWN;
    rac_inference_framework_from_proto(protoValue, &out);
    return out;
}

rac_model_category_t categoryFromProtoInt(int32_t protoValue) {
    rac_model_category_t out = RAC_MODEL_CATEGORY_UNKNOWN;
    rac_model_category_from_proto(protoValue, &out);
    return out;
}
}  // namespace

JNIEXPORT jstring JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racInferenceFrameworkDisplayName(
    JNIEnv* env, jclass clazz, jint frameworkProto) {
    (void)clazz;
    const char* out = nullptr;
    if (rac_inference_framework_display_name(frameworkFromProtoInt(frameworkProto), &out) !=
            RAC_SUCCESS ||
        out == nullptr) {
        return nullptr;
    }
    return env->NewStringUTF(out);
}

JNIEXPORT jstring JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racInferenceFrameworkAnalyticsKey(
    JNIEnv* env, jclass clazz, jint frameworkProto) {
    (void)clazz;
    const char* out = nullptr;
    if (rac_inference_framework_analytics_key(frameworkFromProtoInt(frameworkProto), &out) !=
            RAC_SUCCESS ||
        out == nullptr) {
        return nullptr;
    }
    return env->NewStringUTF(out);
}

JNIEXPORT jstring JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racFrameworkRawValue(JNIEnv* env,
                                                                              jclass clazz,
                                                                              jint frameworkProto) {
    (void)clazz;
    const char* out = rac_framework_raw_value(frameworkFromProtoInt(frameworkProto));
    return out != nullptr ? env->NewStringUTF(out) : nullptr;
}

JNIEXPORT jboolean JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racModelCategoryRequiresContextLength(
    JNIEnv* env, jclass clazz, jint categoryProto) {
    (void)env;
    (void)clazz;
    return rac_model_category_requires_context_length(categoryFromProtoInt(categoryProto)) ==
                   RAC_TRUE
               ? JNI_TRUE
               : JNI_FALSE;
}

JNIEXPORT jboolean JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racModelCategorySupportsThinking(
    JNIEnv* env, jclass clazz, jint categoryProto) {
    (void)env;
    (void)clazz;
    return rac_model_category_supports_thinking(categoryFromProtoInt(categoryProto)) == RAC_TRUE
               ? JNI_TRUE
               : JNI_FALSE;
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racModelCategoryDefaultFramework(
    JNIEnv* env, jclass clazz, jint categoryProto) {
    (void)env;
    (void)clazz;
    const rac_inference_framework_t framework =
        rac_model_category_default_framework(categoryFromProtoInt(categoryProto));
    int32_t proto = 0;
    if (rac_inference_framework_to_proto(framework, &proto) != RAC_SUCCESS) {
        rac_inference_framework_to_proto(RAC_FRAMEWORK_UNKNOWN, &proto);
    }
    return static_cast<jint>(proto);
}

// =============================================================================
// ARCHIVE TYPE helpers — rac_archive_type_from_path /
// rac_archive_type_extension. Detection returns the proto ArchiveType int
// (>=0), or -1 when no archive is detected so the Kotlin caller maps to null.
// =============================================================================

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racArchiveTypeFromPath(JNIEnv* env,
                                                                                jclass clazz,
                                                                                jstring path) {
    (void)clazz;
    if (path == nullptr) {
        return -1;
    }
    std::string storage;
    const char* cPath = getNullableCString(env, path, storage);
    rac_archive_type_t type = RAC_ARCHIVE_TYPE_NONE;
    if (rac_archive_type_from_path(cPath, &type) != RAC_TRUE) {
        return -1;
    }
    int32_t protoValue = 0;
    if (rac_archive_type_to_proto(type, &protoValue) != RAC_SUCCESS) {
        return -1;
    }
    return static_cast<jint>(protoValue);
}

JNIEXPORT jstring JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racArchiveTypeExtension(
    JNIEnv* env, jclass clazz, jint archiveProto) {
    (void)clazz;
    rac_archive_type_t type = RAC_ARCHIVE_TYPE_NONE;
    if (rac_archive_type_from_proto(static_cast<int32_t>(archiveProto), &type) != RAC_SUCCESS) {
        return nullptr;
    }
    const char* out = rac_archive_type_extension(type);
    return out != nullptr ? env->NewStringUTF(out) : nullptr;
}

// =============================================================================
// ARTIFACT expected-files — rac_artifact_expected_files_proto.
// Resolves the canonical ExpectedModelFiles manifest from a
// serialized ModelInfo, mirroring Swift's expectedArtifactFiles.
// =============================================================================

JNIEXPORT jbyteArray JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racArtifactExpectedFilesProto(
    JNIEnv* env, jclass clazz, jbyteArray modelInfoProto) {
    return callProtoBufferFn(env, modelInfoProto, rac_artifact_expected_files_proto,
                             "racArtifactExpectedFilesProto");
}

// =============================================================================
// TWO-PHASE SDK INIT — rac_sdk_init_phase1_proto /
// rac_sdk_init_phase2_proto / rac_sdk_retry_http_proto. Mirrors Swift's
// CppBridge.SdkInit. phase1/phase2 take a serialized request and return a
// serialized SdkInitResult; retryHTTP takes no input.
// =============================================================================

JNIEXPORT jbyteArray JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racSdkInitPhase1Proto(
    JNIEnv* env, jclass clazz, jbyteArray requestProto) {
    return callProtoBufferFn(env, requestProto, rac_sdk_init_phase1_proto, "racSdkInitPhase1Proto");
}

JNIEXPORT jbyteArray JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racSdkInitPhase2Proto(
    JNIEnv* env, jclass clazz, jbyteArray requestProto) {
    return callProtoBufferFn(env, requestProto, rac_sdk_init_phase2_proto, "racSdkInitPhase2Proto");
}

JNIEXPORT jbyteArray JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racSdkRetryHttpProto(JNIEnv* env,
                                                                              jclass clazz) {
    (void)clazz;
    rac_proto_buffer_t result = {};
    rac_proto_buffer_init(&result);
    rac_result_t rc = rac_sdk_retry_http_proto(&result);
    return makeProtoCallResult(env, rc, &result, "racSdkRetryHttpProto");
}

}  // extern "C"
// NOLINTEND(misc-unused-parameters,readability-implicit-bool-conversion,performance-no-int-to-ptr)

// commons-154: definition of the JNI_OnUnload cleanup helper. Each per-handle
// listener map and singleton GlobalRef declared above is drained here so the
// JVM does not leak references when the native library is dlclose'd. Mirrors
// the g_platform_adapter cleanup pattern already present in JNI_OnUnload.
namespace {
void rac_jni_release_all_listener_global_refs(JNIEnv* env) {
    if (env == nullptr) {
        return;
    }

    {
        std::lock_guard<std::mutex> lock(g_sdk_event_listener_mutex);
        for (auto& kv : g_sdk_event_listeners) {
            if (kv.second != nullptr) {
                env->DeleteGlobalRef(kv.second);
            }
        }
        g_sdk_event_listeners.clear();
    }

    {
        std::lock_guard<std::mutex> lock(g_download_proto_listener_mutex);
        if (g_download_proto_listener != nullptr) {
            env->DeleteGlobalRef(g_download_proto_listener);
            g_download_proto_listener = nullptr;
        }
    }

    vadActivityListeners().clearAll(env);
    vadStreamListeners().clearAll(env);
    llmStreamListeners().clearAll(env);
    sttStreamListeners().clearAll(env);
    diarizationStreamListeners().clearAll(env);

    {
        std::lock_guard<std::mutex> lg(toolCallingCtxMutex());
        for (auto& kv : toolCallingCtxMap()) {
            auto* ctx = kv.second;
            if (ctx != nullptr) {
                if (ctx->listener != nullptr) {
                    env->DeleteGlobalRef(ctx->listener);
                }
                delete ctx;
            }
        }
        toolCallingCtxMap().clear();
    }

    if (g_file_callbacks_obj != nullptr) {
        env->DeleteGlobalRef(g_file_callbacks_obj);
        g_file_callbacks_obj = nullptr;
    }
}

void rac_jni_erase_llm_stream_listener(JNIEnv* env, uintptr_t handle_key) {
    if (env == nullptr) {
        return;
    }
    llmStreamListeners().erase(env, handle_key);
}

void rac_jni_erase_vad_listeners(JNIEnv* env, uintptr_t handle_key) {
    if (env == nullptr) {
        return;
    }
    vadActivityListeners().erase(env, handle_key);
    vadStreamListeners().erase(env, handle_key);
}
}  // namespace

// =============================================================================
// NOTE: Backend registration functions have been MOVED to their respective
// backend JNI libraries:
//
//   LlamaCPP: backends/llamacpp/src/jni/rac_backend_llamacpp_jni.cpp
//             -> Java class: com.runanywhere.sdk.llm.llamacpp.LlamaCPPBridge
//
//   ONNX:     backends/onnx/src/jni/rac_backend_onnx_jni.cpp
//             -> Java class: com.runanywhere.sdk.core.onnx.ONNXBridge
//
// This mirrors the Swift SDK architecture where each backend has its own
// XCFramework (RABackendLlamaCPP, RABackendONNX).
// =============================================================================

// NOTE: this and racPlatformUnregister live AFTER the file's `extern "C"` block
// (closed at the platform-TTS section), so they must declare C linkage
// individually — otherwise the C++ compiler mangles the JNI export name and the
// runtime fails with "No implementation found for ...racPlatformRegisterSystemTts".
extern "C" JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racPlatformRegisterSystemTts(
    JNIEnv* env, jclass clazz) {
    (void)env;
    (void)clazz;

    rac_platform_tts_callbacks_t callbacks = {};
    callbacks.can_handle = jni_platform_tts_can_handle;
    callbacks.create = jni_platform_tts_create;
    callbacks.synthesize = jni_platform_tts_synthesize;
    callbacks.stop = jni_platform_tts_stop;
    callbacks.destroy = jni_platform_tts_destroy;
    callbacks.user_data = nullptr;

    rac_result_t result = rac_platform_tts_set_callbacks(&callbacks);
    if (result != RAC_SUCCESS) {
        return static_cast<jint>(result);
    }

    result = rac_backend_platform_register();
    if (result != RAC_SUCCESS && result != RAC_ERROR_MODULE_ALREADY_REGISTERED) {
        return static_cast<jint>(result);
    }

    const rac_engine_vtable_t* vtable = rac_plugin_entry_platform();
    if (vtable == nullptr) {
        return static_cast<jint>(RAC_ERROR_NOT_SUPPORTED);
    }

    result = rac_plugin_register(vtable);
    return static_cast<jint>(result);
}

extern "C" JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racPlatformUnregister(JNIEnv* env,
                                                                               jclass clazz) {
    (void)env;
    (void)clazz;

    rac_result_t plugin_result = rac_plugin_unregister("platform");
    rac_result_t backend_result = rac_backend_platform_unregister();
    if (plugin_result != RAC_SUCCESS && plugin_result != RAC_ERROR_MODULE_NOT_FOUND) {
        return static_cast<jint>(plugin_result);
    }
    return static_cast<jint>(backend_result);
}
