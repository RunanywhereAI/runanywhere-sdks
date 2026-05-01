// RN Android copy of commons/src/jni/okhttp_transport_adapter.cpp (Phase H6).
//
// When RAC_HAS_HTTP_TRANSPORT is defined, the bundled librac_commons.so is
// new enough to expose the rac_http_transport_register() ABI; the full adapter
// below is compiled and wired into the vtable. When not defined, this file
// degrades to no-op JNI stubs that return RAC_ERROR_INTERNAL so the build
// keeps linking and RN falls back to libcurl via rac_http_request_send.

#ifdef RAC_HAS_HTTP_TRANSPORT

/**
 * OkHttp Platform HTTP Transport Adapter (v2 close-out Phase H4)
 *
 * JNI bridge between the C `rac_http_transport_ops` vtable and Kotlin's
 * `com.runanywhere.sdk.foundation.http.OkHttpTransport`. When registered,
 * every `rac_http_request_*` call from native code is routed through
 * OkHttp on the Kotlin side — which gives Android consumers:
 *
 *   - system CA trust store (fixes rc=77 SSL on corporate / rooted devices)
 *   - user-installed CAs via NetworkSecurityConfig
 *   - proxy support (including Charles/mitmproxy/debug proxies)
 *   - HTTP/2 multiplexing
 *   - cert pinning and automatic TLS session caching
 *
 * Threading: OkHttp is thread-safe; this adapter can be invoked
 * concurrently from any native thread. Each call does its own
 * AttachCurrentThread / DetachCurrentThread pair via the helper below.
 *
 * Streaming: `request_stream` is implemented as a fallback to the
 * non-streaming path — we call `executeRequest` and forward the full
 * buffered body through the chunk callback in a single invocation.
 * True OkHttp streaming (ResponseBody.source().read(...)) can come in
 * a follow-up once we need SSE / multi-chunk downloads.
 *
 * Resume: left as NULL in the vtable so libcurl handles resumable
 * downloads for now (mirrors the Kotlin download manager path).
 */

#include <jni.h>

#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <mutex>
#include <string>
#include <vector>

#include "rac/core/rac_error.h"
#include "rac/core/rac_logger.h"
#include "rac/core/rac_types.h"
#include "rac/infrastructure/http/rac_http_client.h"
#include "rac/infrastructure/http/rac_http_transport.h"

// =============================================================================
// AttachCurrentThread signature shim (same rationale as the core JNI file).
// =============================================================================
#ifdef __ANDROID__
#define RAC_JNI_ATTACH_ENVPP(envpp) (envpp)
#else
#define RAC_JNI_ATTACH_ENVPP(envpp) (reinterpret_cast<void**>(envpp))
#endif

static const char* OKHTTP_TAG = "OkHttpTransport";
#define LOGi(...) RAC_LOG_INFO(OKHTTP_TAG, __VA_ARGS__)
#define LOGe(...) RAC_LOG_ERROR(OKHTTP_TAG, __VA_ARGS__)
#define LOGw(...) RAC_LOG_WARNING(OKHTTP_TAG, __VA_ARGS__)

// =============================================================================
// Cached JVM handles. Populated in `okhttp_transport_register`.
// =============================================================================
namespace {

struct OkHttpTransportGlobals {
    JavaVM* jvm = nullptr;
    jclass transport_cls = nullptr;         // global ref to OkHttpTransport
    jmethodID execute_request_mid = nullptr;
    jclass response_cls = nullptr;          // global ref to OkHttpTransport$HttpResponse
    jfieldID f_status_code = nullptr;
    jfieldID f_headers = nullptr;
    jfieldID f_body_bytes = nullptr;
    jfieldID f_error_message = nullptr;
    std::mutex mu;
    bool initialized = false;
};

OkHttpTransportGlobals& globals() {
    static OkHttpTransportGlobals g;
    return g;
}

// RAII helper — attaches the current thread on construction (if not
// already attached), and detaches only if WE were the attacher. Safe
// to nest: nested attaches become no-ops.
class ScopedJniEnv {
 public:
    explicit ScopedJniEnv(JavaVM* vm) : vm_(vm) {
        if (vm_ == nullptr) return;
        int status = vm_->GetEnv(reinterpret_cast<void**>(&env_), JNI_VERSION_1_6);
        if (status == JNI_EDETACHED) {
            if (vm_->AttachCurrentThread(RAC_JNI_ATTACH_ENVPP(&env_), nullptr) == JNI_OK) {
                did_attach_ = true;
            } else {
                env_ = nullptr;
            }
        } else if (status != JNI_OK) {
            env_ = nullptr;
        }
    }

    ~ScopedJniEnv() {
        if (did_attach_ && vm_ != nullptr) {
            vm_->DetachCurrentThread();
        }
    }

    JNIEnv* env() const { return env_; }

    ScopedJniEnv(const ScopedJniEnv&) = delete;
    ScopedJniEnv& operator=(const ScopedJniEnv&) = delete;

 private:
    JavaVM* vm_ = nullptr;
    JNIEnv* env_ = nullptr;
    bool did_attach_ = false;
};

// Helper: turn a std::string pair list into a jobjectArray<String> for
// `OkHttpTransport.executeRequest(headersFlat=[k1,v1,...])`.
jobjectArray build_headers_flat(JNIEnv* env, const rac_http_header_kv_t* headers,
                                size_t header_count) {
    jclass strCls = env->FindClass("java/lang/String");
    if (strCls == nullptr) return nullptr;

    jsize total = static_cast<jsize>(header_count * 2);
    jobjectArray arr = env->NewObjectArray(total, strCls, nullptr);
    if (arr == nullptr) {
        env->DeleteLocalRef(strCls);
        return nullptr;
    }
    for (size_t i = 0; i < header_count; ++i) {
        jstring k = env->NewStringUTF(headers[i].name ? headers[i].name : "");
        jstring v = env->NewStringUTF(headers[i].value ? headers[i].value : "");
        env->SetObjectArrayElement(arr, static_cast<jsize>(i * 2), k);
        env->SetObjectArrayElement(arr, static_cast<jsize>(i * 2 + 1), v);
        env->DeleteLocalRef(k);
        env->DeleteLocalRef(v);
    }
    env->DeleteLocalRef(strCls);
    return arr;
}

// Helper: copy a jbyteArray into a freshly-malloced buffer. `*out_ptr`
// is NULL when the array is empty; `*out_len` is always set.
// Returns RAC_SUCCESS on success, RAC_ERROR_OUT_OF_MEMORY otherwise.
rac_result_t copy_jbytes_to_malloc(JNIEnv* env, jbyteArray arr, uint8_t** out_ptr,
                                   size_t* out_len) {
    *out_ptr = nullptr;
    *out_len = 0;
    if (arr == nullptr) return RAC_SUCCESS;

    jsize n = env->GetArrayLength(arr);
    if (n <= 0) return RAC_SUCCESS;

    auto* buf = static_cast<uint8_t*>(std::malloc(static_cast<size_t>(n)));
    if (buf == nullptr) return RAC_ERROR_OUT_OF_MEMORY;

    env->GetByteArrayRegion(arr, 0, n, reinterpret_cast<jbyte*>(buf));
    *out_ptr = buf;
    *out_len = static_cast<size_t>(n);
    return RAC_SUCCESS;
}

// Helper: walk the flat String[] headers returned by Kotlin and copy
// them into a malloced rac_http_header_kv_t[] with each name/value
// duped via strdup. Caller owns the array (freed by rac_http_response_free).
rac_result_t copy_jstring_headers(JNIEnv* env, jobjectArray arr, rac_http_header_kv_t** out,
                                  size_t* out_count) {
    *out = nullptr;
    *out_count = 0;
    if (arr == nullptr) return RAC_SUCCESS;

    jsize len = env->GetArrayLength(arr);
    if (len <= 0) return RAC_SUCCESS;

    // len must be even (flat k,v pairs); drop trailing odd entry defensively.
    size_t pairs = static_cast<size_t>(len / 2);
    if (pairs == 0) return RAC_SUCCESS;

    auto* kvs = static_cast<rac_http_header_kv_t*>(
        std::malloc(pairs * sizeof(rac_http_header_kv_t)));
    if (kvs == nullptr) return RAC_ERROR_OUT_OF_MEMORY;
    std::memset(kvs, 0, pairs * sizeof(rac_http_header_kv_t));

    for (size_t i = 0; i < pairs; ++i) {
        auto k = reinterpret_cast<jstring>(
            env->GetObjectArrayElement(arr, static_cast<jsize>(i * 2)));
        auto v = reinterpret_cast<jstring>(
            env->GetObjectArrayElement(arr, static_cast<jsize>(i * 2 + 1)));
        if (k != nullptr) {
            const char* chars = env->GetStringUTFChars(k, nullptr);
            if (chars != nullptr) {
                kvs[i].name = strdup(chars);
                env->ReleaseStringUTFChars(k, chars);
            }
            env->DeleteLocalRef(k);
        }
        if (v != nullptr) {
            const char* chars = env->GetStringUTFChars(v, nullptr);
            if (chars != nullptr) {
                kvs[i].value = strdup(chars);
                env->ReleaseStringUTFChars(v, chars);
            }
            env->DeleteLocalRef(v);
        }
    }
    *out = kvs;
    *out_count = pairs;
    return RAC_SUCCESS;
}

// =============================================================================
// Vtable callbacks
// =============================================================================

rac_result_t okhttp_request_send(void* /*user_data*/, const rac_http_request_t* req,
                                 rac_http_response_t* out_resp) {
    if (req == nullptr || out_resp == nullptr) return RAC_ERROR_INVALID_ARGUMENT;
    if (req->method == nullptr || req->url == nullptr) return RAC_ERROR_INVALID_ARGUMENT;

    auto& g = globals();
    if (!g.initialized || g.jvm == nullptr || g.transport_cls == nullptr ||
        g.execute_request_mid == nullptr) {
        LOGe("okhttp_request_send: adapter not fully initialized");
        return RAC_ERROR_INTERNAL;
    }

    ScopedJniEnv scope(g.jvm);
    JNIEnv* env = scope.env();
    if (env == nullptr) {
        LOGe("okhttp_request_send: AttachCurrentThread failed");
        return RAC_ERROR_INTERNAL;
    }

    // Build jstring / jobjectArray / jbyteArray args. Always pass a
    // non-null headers array so Kotlin's executeRequest(headersFlat) loop
    // can do a plain `headersFlat.size` check.
    jstring j_method = env->NewStringUTF(req->method);
    jstring j_url = env->NewStringUTF(req->url);
    jobjectArray j_headers = build_headers_flat(env, req->headers, req->header_count);
    if (j_headers == nullptr) {
        jclass strCls = env->FindClass("java/lang/String");
        j_headers = env->NewObjectArray(0, strCls, nullptr);
        if (strCls != nullptr) env->DeleteLocalRef(strCls);
    }

    jbyteArray j_body = nullptr;
    if (req->body_bytes != nullptr && req->body_len > 0) {
        j_body = env->NewByteArray(static_cast<jsize>(req->body_len));
        if (j_body != nullptr) {
            env->SetByteArrayRegion(j_body, 0, static_cast<jsize>(req->body_len),
                                    reinterpret_cast<const jbyte*>(req->body_bytes));
        }
    }

    jlong j_timeout_ms = static_cast<jlong>(req->timeout_ms);

    // Call into Kotlin. OkHttpTransport.executeRequest returns a non-null
    // HttpResponse on any transport outcome (including errors) — a null
    // return only happens on catastrophic JVM state.
    jobject j_resp = env->CallStaticObjectMethod(
        g.transport_cls, g.execute_request_mid, j_method, j_url, j_headers, j_body,
        j_timeout_ms);

    if (env->ExceptionCheck()) {
        env->ExceptionDescribe();
        env->ExceptionClear();
        if (j_method) env->DeleteLocalRef(j_method);
        if (j_url) env->DeleteLocalRef(j_url);
        if (j_headers) env->DeleteLocalRef(j_headers);
        if (j_body) env->DeleteLocalRef(j_body);
        LOGe("okhttp_request_send: executeRequest threw");
        return RAC_ERROR_NETWORK_ERROR;
    }

    if (j_method) env->DeleteLocalRef(j_method);
    if (j_url) env->DeleteLocalRef(j_url);
    if (j_headers) env->DeleteLocalRef(j_headers);
    if (j_body) env->DeleteLocalRef(j_body);

    if (j_resp == nullptr) {
        LOGe("okhttp_request_send: null response object");
        return RAC_ERROR_INTERNAL;
    }

    // Unpack fields.
    jint status_code = env->GetIntField(j_resp, g.f_status_code);
    auto j_headers_out = reinterpret_cast<jobjectArray>(
        env->GetObjectField(j_resp, g.f_headers));
    auto j_body_bytes = reinterpret_cast<jbyteArray>(
        env->GetObjectField(j_resp, g.f_body_bytes));
    auto j_error_msg = reinterpret_cast<jstring>(
        env->GetObjectField(j_resp, g.f_error_message));

    // Transport-level failure: Kotlin sets statusCode=0 + non-null errorMessage.
    if (status_code == 0 && j_error_msg != nullptr) {
        const char* chars = env->GetStringUTFChars(j_error_msg, nullptr);
        std::string msg = chars ? chars : "";
        if (chars) env->ReleaseStringUTFChars(j_error_msg, chars);
        LOGe("okhttp_request_send: transport error: %s", msg.c_str());
        env->DeleteLocalRef(j_resp);
        if (j_headers_out) env->DeleteLocalRef(j_headers_out);
        if (j_body_bytes) env->DeleteLocalRef(j_body_bytes);
        if (j_error_msg) env->DeleteLocalRef(j_error_msg);
        return RAC_ERROR_NETWORK_ERROR;
    }

    // Populate out_resp. All allocations must be freed by the caller via
    // rac_http_response_free(out_resp) — same contract as libcurl default.
    std::memset(out_resp, 0, sizeof(*out_resp));
    out_resp->status = static_cast<int32_t>(status_code);

    rac_result_t rc = copy_jbytes_to_malloc(env, j_body_bytes, &out_resp->body_bytes,
                                            &out_resp->body_len);
    if (rc != RAC_SUCCESS) {
        env->DeleteLocalRef(j_resp);
        if (j_headers_out) env->DeleteLocalRef(j_headers_out);
        if (j_body_bytes) env->DeleteLocalRef(j_body_bytes);
        if (j_error_msg) env->DeleteLocalRef(j_error_msg);
        return rc;
    }

    rc = copy_jstring_headers(env, j_headers_out, &out_resp->headers, &out_resp->header_count);
    if (rc != RAC_SUCCESS) {
        if (out_resp->body_bytes) {
            std::free(out_resp->body_bytes);
            out_resp->body_bytes = nullptr;
            out_resp->body_len = 0;
        }
        env->DeleteLocalRef(j_resp);
        if (j_headers_out) env->DeleteLocalRef(j_headers_out);
        if (j_body_bytes) env->DeleteLocalRef(j_body_bytes);
        if (j_error_msg) env->DeleteLocalRef(j_error_msg);
        return rc;
    }

    env->DeleteLocalRef(j_resp);
    if (j_headers_out) env->DeleteLocalRef(j_headers_out);
    if (j_body_bytes) env->DeleteLocalRef(j_body_bytes);
    if (j_error_msg) env->DeleteLocalRef(j_error_msg);
    return RAC_SUCCESS;
}

// Streaming fallback: run the blocking executeRequest, then forward the
// fully-buffered body through the callback in a single chunk. This keeps
// the vtable honest without needing a second JNI thunk.
rac_result_t okhttp_request_stream(void* user_data, const rac_http_request_t* req,
                                   rac_http_body_chunk_fn cb, void* cb_user_data,
                                   rac_http_response_t* out_resp_meta) {
    if (out_resp_meta == nullptr) return RAC_ERROR_INVALID_ARGUMENT;

    rac_http_response_t buffered{};
    rac_result_t rc = okhttp_request_send(user_data, req, &buffered);
    if (rc != RAC_SUCCESS) {
        return rc;
    }

    // Transfer status + headers into out_resp_meta; keep body inside
    // buffered until we've pushed it through cb.
    std::memset(out_resp_meta, 0, sizeof(*out_resp_meta));
    out_resp_meta->status = buffered.status;
    out_resp_meta->headers = buffered.headers;
    out_resp_meta->header_count = buffered.header_count;
    out_resp_meta->redirected_url = buffered.redirected_url;
    out_resp_meta->elapsed_ms = buffered.elapsed_ms;
    buffered.headers = nullptr;
    buffered.header_count = 0;
    buffered.redirected_url = nullptr;

    if (cb != nullptr && buffered.body_bytes != nullptr && buffered.body_len > 0) {
        uint64_t total = static_cast<uint64_t>(buffered.body_len);
        rac_bool_t keep_going = cb(buffered.body_bytes, buffered.body_len, total, total,
                                   cb_user_data);
        if (keep_going == RAC_FALSE) {
            std::free(buffered.body_bytes);
            buffered.body_bytes = nullptr;
            buffered.body_len = 0;
            return RAC_ERROR_CANCELLED;
        }
    }

    if (buffered.body_bytes != nullptr) {
        std::free(buffered.body_bytes);
        buffered.body_bytes = nullptr;
        buffered.body_len = 0;
    }
    return RAC_SUCCESS;
}

void okhttp_destroy(void* /*user_data*/) {
    auto& g = globals();
    std::lock_guard<std::mutex> lock(g.mu);
    if (!g.initialized) return;

    JNIEnv* env = nullptr;
    if (g.jvm != nullptr) {
        int status = g.jvm->GetEnv(reinterpret_cast<void**>(&env), JNI_VERSION_1_6);
        bool did_attach = false;
        if (status == JNI_EDETACHED) {
            if (g.jvm->AttachCurrentThread(RAC_JNI_ATTACH_ENVPP(&env), nullptr) == JNI_OK) {
                did_attach = true;
            } else {
                env = nullptr;
            }
        }
        if (env != nullptr) {
            if (g.transport_cls != nullptr) {
                env->DeleteGlobalRef(g.transport_cls);
                g.transport_cls = nullptr;
            }
            if (g.response_cls != nullptr) {
                env->DeleteGlobalRef(g.response_cls);
                g.response_cls = nullptr;
            }
        }
        if (did_attach) g.jvm->DetachCurrentThread();
    }
    g.execute_request_mid = nullptr;
    g.f_status_code = nullptr;
    g.f_headers = nullptr;
    g.f_body_bytes = nullptr;
    g.f_error_message = nullptr;
    g.initialized = false;
    LOGi("okhttp_transport: destroyed");
}

// Static vtable. Lives for the lifetime of the process.
rac_http_transport_ops_t kOps = {
    /*request_send*/ okhttp_request_send,
    /*request_stream*/ okhttp_request_stream,
    /*request_resume*/ nullptr,       // libcurl keeps handling resume for now
    /*init*/ nullptr,
    /*destroy*/ okhttp_destroy,
};

}  // namespace

// =============================================================================
// JNI entry points
// =============================================================================
//
// Called from Kotlin's `RunAnywhereBridge.racHttpTransportRegisterOkHttp()`
// during SDK init. Caches all the JVM handles we need, then installs the
// `kOps` vtable via `rac_http_transport_register`.
extern "C" {

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racHttpTransportRegisterOkHttp(
    JNIEnv* env, jclass /*clazz*/) {
    if (env == nullptr) return RAC_ERROR_INVALID_ARGUMENT;

    auto& g = globals();
    std::lock_guard<std::mutex> lock(g.mu);

    if (g.initialized) {
        LOGi("racHttpTransportRegisterOkHttp: already registered");
        return RAC_SUCCESS;
    }

    if (env->GetJavaVM(&g.jvm) != JNI_OK || g.jvm == nullptr) {
        LOGe("racHttpTransportRegisterOkHttp: GetJavaVM failed");
        return RAC_ERROR_INTERNAL;
    }

    // Look up the Kotlin class + method we need to call.
    jclass local_cls =
        env->FindClass("com/runanywhere/sdk/foundation/http/OkHttpTransport");
    if (local_cls == nullptr) {
        LOGe("racHttpTransportRegisterOkHttp: OkHttpTransport class not found");
        if (env->ExceptionCheck()) env->ExceptionClear();
        return RAC_ERROR_INTERNAL;
    }
    g.transport_cls = reinterpret_cast<jclass>(env->NewGlobalRef(local_cls));
    env->DeleteLocalRef(local_cls);
    if (g.transport_cls == nullptr) {
        LOGe("racHttpTransportRegisterOkHttp: NewGlobalRef(transport_cls) failed");
        return RAC_ERROR_OUT_OF_MEMORY;
    }

    // Signature: (Ljava/lang/String; Ljava/lang/String; [Ljava/lang/String; [B J)
    //            Lcom/runanywhere/sdk/foundation/http/OkHttpTransport$HttpResponse;
    g.execute_request_mid = env->GetStaticMethodID(
        g.transport_cls, "executeRequest",
        "(Ljava/lang/String;Ljava/lang/String;[Ljava/lang/String;[BJ)"
        "Lcom/runanywhere/sdk/foundation/http/OkHttpTransport$HttpResponse;");
    if (g.execute_request_mid == nullptr) {
        LOGe("racHttpTransportRegisterOkHttp: executeRequest method not found");
        if (env->ExceptionCheck()) env->ExceptionClear();
        env->DeleteGlobalRef(g.transport_cls);
        g.transport_cls = nullptr;
        return RAC_ERROR_INTERNAL;
    }

    // Cache the HttpResponse class + field IDs.
    jclass local_resp_cls =
        env->FindClass("com/runanywhere/sdk/foundation/http/OkHttpTransport$HttpResponse");
    if (local_resp_cls == nullptr) {
        LOGe("racHttpTransportRegisterOkHttp: HttpResponse class not found");
        if (env->ExceptionCheck()) env->ExceptionClear();
        env->DeleteGlobalRef(g.transport_cls);
        g.transport_cls = nullptr;
        g.execute_request_mid = nullptr;
        return RAC_ERROR_INTERNAL;
    }
    g.response_cls = reinterpret_cast<jclass>(env->NewGlobalRef(local_resp_cls));
    env->DeleteLocalRef(local_resp_cls);

    g.f_status_code = env->GetFieldID(g.response_cls, "statusCode", "I");
    g.f_headers = env->GetFieldID(g.response_cls, "headers", "[Ljava/lang/String;");
    g.f_body_bytes = env->GetFieldID(g.response_cls, "bodyBytes", "[B");
    g.f_error_message = env->GetFieldID(g.response_cls, "errorMessage", "Ljava/lang/String;");

    if (g.f_status_code == nullptr || g.f_headers == nullptr || g.f_body_bytes == nullptr ||
        g.f_error_message == nullptr) {
        LOGe("racHttpTransportRegisterOkHttp: HttpResponse fields not found");
        if (env->ExceptionCheck()) env->ExceptionClear();
        env->DeleteGlobalRef(g.transport_cls);
        env->DeleteGlobalRef(g.response_cls);
        g.transport_cls = nullptr;
        g.response_cls = nullptr;
        g.execute_request_mid = nullptr;
        return RAC_ERROR_INTERNAL;
    }

    g.initialized = true;

    // Install the vtable. Subsequent rac_http_request_* calls go through
    // kOps → Kotlin → OkHttp instead of libcurl.
    rac_result_t rc = rac_http_transport_register(&kOps, nullptr);
    if (rc != RAC_SUCCESS) {
        LOGe("racHttpTransportRegisterOkHttp: rac_http_transport_register failed: %d", rc);
        // Roll back the cached refs; the adapter can't service calls.
        env->DeleteGlobalRef(g.transport_cls);
        env->DeleteGlobalRef(g.response_cls);
        g.transport_cls = nullptr;
        g.response_cls = nullptr;
        g.execute_request_mid = nullptr;
        g.initialized = false;
        return rc;
    }

    LOGi("racHttpTransportRegisterOkHttp: OkHttp transport installed");
    return RAC_SUCCESS;
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racHttpTransportUnregisterOkHttp(
    JNIEnv* /*env*/, jclass /*clazz*/) {
    // Unregister → the router falls back to libcurl for future calls.
    rac_result_t rc = rac_http_transport_register(nullptr, nullptr);
    if (rc != RAC_SUCCESS) {
        LOGw("racHttpTransportUnregisterOkHttp: rac_http_transport_register(NULL) returned %d",
             rc);
    }
    // destroy() will clear the JNI globals.
    return static_cast<jint>(rc);
}

}  // extern "C"

#else  // !RAC_HAS_HTTP_TRANSPORT — stub mode

// -----------------------------------------------------------------------------
// Stubs: the bundled librac_commons.so predates rac_http_transport_register,
// so the adapter can't install a vtable. We still need to resolve the two JNI
// symbols referenced by RunAnywhereBridge.kt; they return an error code so the
// Kotlin side logs a warning and continues using libcurl through the default
// rac_http_request_* path.
// -----------------------------------------------------------------------------
#include <jni.h>

#ifndef RAC_ERROR_INTERNAL
#define RAC_ERROR_INTERNAL (-100)
#endif

extern "C" {

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racHttpTransportRegisterOkHttp(
    JNIEnv* /*env*/, jclass /*clazz*/) {
    // RAC_ERROR_INTERNAL — adapter unavailable; the Kotlin caller logs and
    // carries on with libcurl.
    return static_cast<jint>(RAC_ERROR_INTERNAL);
}

JNIEXPORT jint JNICALL
Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racHttpTransportUnregisterOkHttp(
    JNIEnv* /*env*/, jclass /*clazz*/) {
    // No-op — nothing was registered.
    return 0;
}

}  // extern "C"

#endif  // RAC_HAS_HTTP_TRANSPORT
