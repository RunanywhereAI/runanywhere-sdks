// runanywhere_native — N-API addon over the C++ commons proto-byte ABI.
//
// The whole surface is proto bytes in / proto bytes out (plus a few scalars and
// the RAG session integer handles). Each JS method serializes a runanywhere.v1
// request in TS, this layer forwards the bytes to the matching rac_*_proto call,
// and returns the serialized response. Inference and model loading are the
// lifecycle path (one model per component, tracked in commons), so those calls
// carry no handle. Loading is registry-first: register a model, then load it by
// id via rac_model_lifecycle_load_proto(rac_get_model_registry(), ...).
//
// Threading: blocking work (generate, load, download, RAG) runs on a worker
// thread and resolves a Promise; streaming marshals proto-byte events to JS
// through a bounded ThreadSafeFunction (BlockingCall = backpressure). A global
// in-flight counter makes shutdown wait for live ops before rac_shutdown().
#include <napi.h>

#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstring>
#include <functional>
#include <mutex>
#include <string>
#include <thread>
#include <unordered_map>
#include <vector>

#ifdef _WIN32
#include "win32_platform_adapter.h"
#else
#include "posix_platform_adapter.h"
#endif

#include "rac/core/rac_core.h"
#include "rac/core/rac_error.h"
#include "rac/core/rac_model_lifecycle.h"
#include "rac/core/rac_types.h"
#include "rac/foundation/rac_proto_buffer.h"
#include "rac/plugin/rac_plugin_entry.h"
#include "rac/plugin/rac_plugin_entry_neurt.h"
#include "rac/features/llm/rac_llm_service.h"
#include "rac/features/llm/rac_llm_stream.h"
#include "rac/features/llm/rac_llm_structured_output.h"
#include "rac/features/llm/rac_tool_calling.h"
#include "rac/features/vlm/rac_vlm_service.h"
#include "rac/features/stt/rac_stt_service.h"
#include "rac/features/tts/rac_tts_service.h"
#include "rac/features/vad/rac_vad_service.h"
#include "rac/features/vad/rac_vad_component.h"
#include "rac/features/embeddings/rac_embeddings_service.h"
#include "rac/features/diarization/rac_diarization_service.h"
#include "rac/features/segmentation/rac_segmentation_service.h"
#include "rac/features/lora/rac_lora_service.h"
#include "rac/features/diffusion/rac_diffusion_service.h"
#include "rac/features/rag/rac_rag.h"
#include "rac/infrastructure/download/rac_download_orchestrator.h"
#include "rac/infrastructure/model_management/rac_model_paths.h"
#include "rac/infrastructure/model_management/rac_model_registry.h"
#include "rac/router/rac_router_capabilities.h"

#ifdef RAC_ELECTRON_HAVE_DESKTOP
#include "rac/core/rac_sdk_state.h"
#include "rac/desktop/rac_desktop.h"
#include "rac/infrastructure/device/rac_device_identity.h"
#include "rac/infrastructure/network/rac_dev_config.h"
#include "rac/infrastructure/network/rac_environment.h"
#include "rac/infrastructure/network/rac_client_info.h"
#include "rac/infrastructure/network/rac_auth_manager.h"
#include "rac/infrastructure/network/rac_endpoints.h"
#include "rac/infrastructure/http/rac_http_client.h"
#include "rac/infrastructure/http/rac_http_transport.h"
#include "rac/infrastructure/telemetry/rac_telemetry_manager.h"
#include "rac/infrastructure/events/rac_sdk_event_stream.h"
#include "rac/lifecycle/rac_sdk_init.h"
#endif

// Engine backends — linked when present (see native/CMakeLists.txt foreach).
#ifdef RAC_HAVE_BACKEND_LLAMACPP
#include "rac/backends/rac_llm_llamacpp.h"
#endif
#ifdef RAC_HAVE_BACKEND_ONNX
#include "rac/plugin/rac_plugin_entry_onnx.h"
#endif
#ifdef RAC_HAVE_BACKEND_SHERPA
#include "rac/plugin/rac_plugin_entry_sherpa.h"
#endif
extern "C" {
#ifdef RAC_HAVE_BACKEND_QHEXRT
rac_result_t rac_backend_qhexrt_register(void);
#endif
#ifdef RAC_HAVE_BACKEND_CLOUD
rac_result_t rac_backend_cloud_register(void);
#endif
}

namespace {

// The adapter struct is caller-owned and must outlive rac_shutdown().
rac_platform_adapter_t g_adapter;
std::atomic<bool> g_initialized{false};

#ifdef RAC_ELECTRON_HAVE_DESKTOP
rac_telemetry_manager_t* g_telemetry_manager = nullptr;
#endif

// RAG sessions are the only multi-instance native handles the addon owns; every
// other modality uses the single lifecycle-owned model per component. Handles
// are exposed to JS as small integer ids.
std::mutex g_handles_mutex;
std::condition_variable g_inflight_cv;
std::unordered_map<int32_t, int> g_inflight;  // lease id -> active blocking-op count
std::unordered_map<int32_t, rac_handle_t> g_rag_handles;
int32_t g_next_handle_id = 1;

// The built-in energy VAD is a component (no model), created lazily on first use.
// The lifecycle VAD path needs a loaded model; this gives the modelless detector.
rac_handle_t g_vad_handle = nullptr;

// The active tool-calling run-loop handle, published by commons so a JS-side
// cancel can reach it. 0 when no loop is running.
std::atomic<uint64_t> g_tool_handle{0};

// Shared lease id for lifecycle (no-handle) ops, so shutdown waits for a live
// generate/transcribe/etc. to finish before rac_shutdown().
constexpr int32_t kLifecycleLease = 0;

void inflight_inc(int32_t id) {
    std::lock_guard<std::mutex> lock(g_handles_mutex);
    ++g_inflight[id];
}
void inflight_dec(int32_t id) {
    {
        std::lock_guard<std::mutex> lock(g_handles_mutex);
        auto it = g_inflight.find(id);
        if (it != g_inflight.end() && --it->second <= 0) g_inflight.erase(it);
    }
    g_inflight_cv.notify_all();
}

// Mark a RAG handle busy for a blocking op; unload waits for it to go idle.
rac_handle_t begin_op(int32_t id) {
    std::lock_guard<std::mutex> lock(g_handles_mutex);
    auto it = g_rag_handles.find(id);
    if (it == g_rag_handles.end()) return nullptr;
    ++g_inflight[id];
    return it->second;
}
void end_op(int32_t id) { inflight_dec(id); }

struct OpScope {
    int32_t id;
    explicit OpScope(int32_t i) : id(i) {}
    ~OpScope() { end_op(id); }
    OpScope(const OpScope&) = delete;
    OpScope& operator=(const OpScope&) = delete;
};

// Bound so a stuck op cannot freeze destroy forever. nullptr => gone/unavailable.
constexpr auto kTakeHandleIdleTimeout = std::chrono::seconds(60);
rac_handle_t take_rag_handle_when_idle(int32_t id) {
    std::unique_lock<std::mutex> lock(g_handles_mutex);
    const bool idle = g_inflight_cv.wait_for(lock, kTakeHandleIdleTimeout, [&] {
        auto it = g_inflight.find(id);
        return it == g_inflight.end() || it->second == 0;
    });
    if (!idle) return nullptr;
    auto it = g_rag_handles.find(id);
    if (it == g_rag_handles.end()) return nullptr;
    rac_handle_t h = it->second;
    g_rag_handles.erase(it);
    return h;
}

int rac_code_abs(rac_result_t code) {
    int value = static_cast<int>(code);
    return value < 0 ? -value : value;
}

// Structured JS Error carrying the canonical positive ErrorCode + raw rac code,
// with a message that still ends in "failed: <code>" for string-only callers.
Napi::Error make_rac_error(Napi::Env env, rac_result_t code, const std::string& message) {
    Napi::Error error = Napi::Error::New(env, message);
    Napi::Object value = error.Value();
    value.Set("code", Napi::Number::New(env, rac_code_abs(code)));
    value.Set("cAbiCode", Napi::Number::New(env, static_cast<int>(code)));
    return error;
}

void throw_rac_error(Napi::Env env, rac_result_t code, const std::string& context) {
    std::string msg = context.empty() ? ("rac error failed: " + std::to_string(code))
                                      : (context + " failed: " + std::to_string(code));
    make_rac_error(env, code, msg).ThrowAsJavaScriptException();
}

bool is_cancellation(rac_result_t code) {
    return code == RAC_ERROR_CANCELLED || code == RAC_ERROR_GENERATION_CANCELLED ||
           code == RAC_ERROR_STREAM_CANCELLED;
}

Napi::Value not_impl(Napi::Env env, const char* what) {
    make_rac_error(env, RAC_ERROR_NOT_IMPLEMENTED,
                   std::string(what) + " is not yet wired in the proto-byte addon")
        .ThrowAsJavaScriptException();
    return env.Undefined();
}

// Proto helpers — the whole surface reduces to these shapes.
std::vector<uint8_t> bytes_of(const Napi::Value& v) {
    Napi::Uint8Array a = v.As<Napi::Uint8Array>();
    return std::vector<uint8_t>(a.Data(), a.Data() + a.ByteLength());
}

// Convert an out buffer to a JS Buffer, throwing on failure. Frees the buffer.
Napi::Value buffer_to_js(Napi::Env env, rac_proto_buffer_t* buf, const char* what) {
    if (buf->status != RAC_SUCCESS) {
        std::string msg = std::string(what) + " failed: " + std::to_string(buf->status);
        if (buf->error_message) {
            msg += " (";
            msg += buf->error_message;
            msg += ")";
        }
        rac_result_t status = buf->status;
        rac_proto_buffer_free(buf);
        make_rac_error(env, status, msg).ThrowAsJavaScriptException();
        return env.Undefined();
    }
    Napi::Buffer<uint8_t> out =
        Napi::Buffer<uint8_t>::Copy(env, buf->data ? buf->data : nullptr, buf->size);
    rac_proto_buffer_free(buf);
    return out;
}

using ProtoInFn = rac_result_t (*)(const uint8_t*, size_t, rac_proto_buffer_t*);
using ProtoOutFn = rac_result_t (*)(rac_proto_buffer_t*);

// Synchronous (bytes) -> Buffer.
Napi::Value sync_proto_in(const Napi::CallbackInfo& info, ProtoInFn fn, const char* what) {
    Napi::Env env = info.Env();
    if (!g_initialized.load()) {
        Napi::Error::New(env, "not initialized").ThrowAsJavaScriptException();
        return env.Undefined();
    }
    if (info.Length() < 1 || !info[0].IsTypedArray()) {
        Napi::TypeError::New(env, std::string(what) + "(protoBytes) expects a Uint8Array")
            .ThrowAsJavaScriptException();
        return env.Undefined();
    }
    std::vector<uint8_t> in = bytes_of(info[0]);
    rac_proto_buffer_t out;
    rac_proto_buffer_init(&out);
    rac_result_t rc = fn(in.data(), in.size(), &out);
    if (rc != RAC_SUCCESS && out.status == RAC_SUCCESS) out.status = rc;
    return buffer_to_js(env, &out, what);
}

// Synchronous () -> Buffer.
Napi::Value sync_proto_out(Napi::Env env, ProtoOutFn fn, const char* what) {
    if (!g_initialized.load()) {
        Napi::Error::New(env, "not initialized").ThrowAsJavaScriptException();
        return env.Undefined();
    }
    rac_proto_buffer_t out;
    rac_proto_buffer_init(&out);
    rac_result_t rc = fn(&out);
    if (rc != RAC_SUCCESS && out.status == RAC_SUCCESS) out.status = rc;
    return buffer_to_js(env, &out, what);
}

// Worker-thread proto op resolving a Buffer. `run` performs the rac_*_proto call
// into the out buffer. Holds a lifecycle lease so shutdown waits for it.
class ProtoAsyncWorker : public Napi::AsyncWorker {
 public:
    ProtoAsyncWorker(Napi::Env env, std::function<rac_result_t(rac_proto_buffer_t*)> run,
                     const char* what)
        : Napi::AsyncWorker(env),
          deferred_(Napi::Promise::Deferred::New(env)),
          run_(std::move(run)),
          what_(what) {
        inflight_inc(kLifecycleLease);
    }

    Napi::Promise Promise() { return deferred_.Promise(); }

    void Execute() override {
        rac_proto_buffer_t out;
        rac_proto_buffer_init(&out);
        rac_result_t rc = run_(&out);
        if (rc != RAC_SUCCESS && out.status == RAC_SUCCESS) out.status = rc;
        if (out.status == RAC_SUCCESS) {
            if (out.data && out.size > 0) result_.assign(out.data, out.data + out.size);
            ok_ = true;
        } else {
            code_ = out.status;
            err_ = what_ + " failed: " + std::to_string(out.status);
            if (out.error_message) {
                err_ += " (";
                err_ += out.error_message;
                err_ += ")";
            }
        }
        rac_proto_buffer_free(&out);
        inflight_dec(kLifecycleLease);
    }

    void OnOK() override {
        Napi::HandleScope scope(Env());
        if (ok_) {
            deferred_.Resolve(Napi::Buffer<uint8_t>::Copy(Env(), result_.data(), result_.size()));
        } else {
            deferred_.Reject(make_rac_error(Env(), code_, err_).Value());
        }
    }

    void OnError(const Napi::Error& e) override {
        inflight_dec(kLifecycleLease);
        Napi::HandleScope scope(Env());
        deferred_.Reject(e.Value());
    }

 private:
    Napi::Promise::Deferred deferred_;
    std::function<rac_result_t(rac_proto_buffer_t*)> run_;
    std::string what_;
    std::vector<uint8_t> result_;
    std::string err_;
    bool ok_ = false;
    rac_result_t code_ = RAC_SUCCESS;
};

Napi::Value queue_async(Napi::Env env, std::function<rac_result_t(rac_proto_buffer_t*)> run,
                        const char* what) {
    auto* worker = new ProtoAsyncWorker(env, std::move(run), what);
    Napi::Promise promise = worker->Promise();
    try {
        worker->Queue();
    } catch (...) {
        delete worker;  // ProtoAsyncWorker dtor path won't run; balance the lease
        inflight_dec(kLifecycleLease);
        throw;
    }
    return promise;
}

// Worker-thread (bytes) -> Buffer for a plain proto in/out op.
Napi::Value async_proto_in(const Napi::CallbackInfo& info, ProtoInFn fn, const char* what) {
    Napi::Env env = info.Env();
    if (!g_initialized.load()) {
        Napi::Error::New(env, "not initialized").ThrowAsJavaScriptException();
        return env.Undefined();
    }
    if (info.Length() < 1 || !info[0].IsTypedArray()) {
        Napi::TypeError::New(env, std::string(what) + "(protoBytes) expects a Uint8Array")
            .ThrowAsJavaScriptException();
        return env.Undefined();
    }
    std::vector<uint8_t> in = bytes_of(info[0]);
    return queue_async(
        env, [in, fn](rac_proto_buffer_t* out) { return fn(in.data(), in.size(), out); }, what);
}

// Streaming — one worker thread drives a blocking rac_*_stream_proto call and
// marshals each proto-byte event to JS via a bounded TSFN.
struct StreamCtx {
    Napi::ThreadSafeFunction tsfn;
    std::thread worker;
    Napi::Promise::Deferred deferred;
    rac_result_t result = RAC_SUCCESS;
    std::function<rac_result_t(StreamCtx*)> run;
    std::function<void()> quiesce;  // in-flight-callback drain before teardown
    int32_t lease_id = kLifecycleLease;
    explicit StreamCtx(Napi::Env env) : deferred(Napi::Promise::Deferred::New(env)) {}
};

// void-return proto event callback (LLM/VLM/STT/TTS): copy out, marshal to JS.
void stream_event_cb(const uint8_t* bytes, size_t size, void* ud) {
    auto* ctx = static_cast<StreamCtx*>(ud);
    std::vector<uint8_t> copy(bytes, bytes + size);
    ctx->tsfn.BlockingCall([copy](Napi::Env env, Napi::Function cb) {
        cb.Call({Napi::Buffer<uint8_t>::Copy(env, copy.data(), copy.size())});
    });
}

// rac_bool_t-return proto event callback (RAG): napi_closing -> stop streaming.
rac_bool_t stream_event_cb_bool(const uint8_t* bytes, size_t size, void* ud) {
    auto* ctx = static_cast<StreamCtx*>(ud);
    std::vector<uint8_t> copy(bytes, bytes + size);
    napi_status st = ctx->tsfn.BlockingCall([copy](Napi::Env env, Napi::Function cb) {
        cb.Call({Napi::Buffer<uint8_t>::Copy(env, copy.data(), copy.size())});
    });
    return (st == napi_ok) ? RAC_TRUE : RAC_FALSE;
}

Napi::Promise start_stream(Napi::Env env, Napi::Function on_event,
                           std::function<rac_result_t(StreamCtx*)> run,
                           std::function<void()> quiesce, int32_t lease_id, const char* what) {
    auto* ctx = new StreamCtx(env);
    ctx->run = std::move(run);
    ctx->quiesce = std::move(quiesce);
    ctx->lease_id = lease_id;
    std::string what_s = what;
    inflight_inc(lease_id);
    try {
        ctx->tsfn = Napi::ThreadSafeFunction::New(
            env, on_event, "ra-stream", /*maxQueueSize*/ 256, /*initialThreadCount*/ 1, ctx,
            [what_s](Napi::Env env, void*, StreamCtx* c) {
                if (c->worker.joinable()) c->worker.join();
                if (c->quiesce) c->quiesce();  // drain any in-flight callback
                inflight_dec(c->lease_id);
                if (c->result == RAC_SUCCESS || is_cancellation(c->result)) {
                    c->deferred.Resolve(env.Undefined());
                } else {
                    c->deferred.Reject(
                        make_rac_error(env, c->result,
                                       what_s + " failed: " + std::to_string(c->result))
                            .Value());
                }
                delete c;
            },
            static_cast<void*>(nullptr));
        ctx->worker = std::thread([ctx]() {
            rac_result_t rc = ctx->run(ctx);
            if (rc != RAC_SUCCESS && ctx->result == RAC_SUCCESS) ctx->result = rc;
            ctx->tsfn.Release();
        });
    } catch (...) {
        inflight_dec(lease_id);
        delete ctx;
        throw;
    }
    return ctx->deferred.Promise();
}

Napi::Value Initialize(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    if (g_initialized.load()) return env.Undefined();
    if (info.Length() < 1 || !info[0].IsString()) {
        Napi::TypeError::New(env, "initialize(secureDir[, baseDir]) expects a string")
            .ThrowAsJavaScriptException();
        return env.Undefined();
    }
    std::string secure = info[0].As<Napi::String>().Utf8Value();
    std::string base =
        (info.Length() > 1 && info[1].IsString()) ? info[1].As<Napi::String>().Utf8Value() : secure;

#ifdef _WIN32
    rac_electron_fill_win32_adapter(&g_adapter, secure.c_str());
#else
    rac_electron_fill_posix_adapter(&g_adapter, secure.c_str());
#endif

    rac_config_t cfg;
    std::memset(&cfg, 0, sizeof(cfg));
    cfg.platform_adapter = &g_adapter;
    cfg.log_level = RAC_LOG_WARNING;
    if (const char* lvl = std::getenv("RUNANYWHERE_LOG_LEVEL")) {
        if (!std::strcmp(lvl, "trace")) cfg.log_level = RAC_LOG_TRACE;
        else if (!std::strcmp(lvl, "debug")) cfg.log_level = RAC_LOG_DEBUG;
        else if (!std::strcmp(lvl, "info")) cfg.log_level = RAC_LOG_INFO;
        else if (!std::strcmp(lvl, "warning")) cfg.log_level = RAC_LOG_WARNING;
        else if (!std::strcmp(lvl, "error")) cfg.log_level = RAC_LOG_ERROR;
        else if (!std::strcmp(lvl, "fatal")) cfg.log_level = RAC_LOG_FATAL;
    }
    cfg.log_tag = "electron";

    rac_model_paths_set_base_dir(base.c_str());

    rac_result_t rc = rac_init(&cfg);
    if (rc != RAC_SUCCESS) {
        throw_rac_error(env, rc, "rac_init");
        return env.Undefined();
    }

    // Backend/plugin registration is process-global and persists across
    // rac_shutdown(), so register exactly once.
    static bool backends_registered = false;
    if (!backends_registered) {
#ifdef RAC_HAVE_BACKEND_LLAMACPP
        rc = rac_backend_llamacpp_register();
        if (rc != RAC_SUCCESS) {
            rac_shutdown();
            throw_rac_error(env, rc, "rac_backend_llamacpp_register");
            return env.Undefined();
        }
#endif
#ifdef RAC_HAVE_BACKEND_ONNX
        rac_backend_onnx_register();
#endif
#ifdef RAC_HAVE_BACKEND_SHERPA
        rac_backend_sherpa_register();
#endif
#ifdef RAC_HAVE_BACKEND_QHEXRT
        rac_backend_qhexrt_register();
#endif
#ifdef RAC_HAVE_BACKEND_NEURT
        rac_plugin_register(rac_plugin_entry_neurt());
#endif
#ifdef RAC_HAVE_BACKEND_CLOUD
        rac_backend_cloud_register();
#endif
        backends_registered = true;
    }

#ifdef RAC_ELECTRON_HAVE_DESKTOP
    // Register the libcurl transport up front so model downloads work even
    // without the control plane (auth/telemetry). Idempotent.
    rac_desktop_http_transport_register();
#endif

    g_initialized.store(true);
    return env.Undefined();
}

#ifdef RAC_ELECTRON_HAVE_DESKTOP
// Delivers a queued telemetry batch over the desktop HTTP transport. Runs on
// commons' telemetry thread — pure C++, never touches JS.
void electron_telemetry_http_callback(void* user_data, const char* endpoint, const char* json_body,
                                      size_t json_length, rac_bool_t requires_auth) {
    auto* manager = static_cast<rac_telemetry_manager_t*>(user_data);
    const char* base_url = rac_state_get_base_url();
    if (base_url == nullptr || base_url[0] == '\0' ||
        rac_http_transport_is_registered() != RAC_TRUE) {
        if (manager)
            rac_telemetry_manager_http_complete(manager, RAC_FALSE, nullptr,
                                                "telemetry transport unavailable");
        return;
    }
    char url[2048] = {};
    if (rac_build_url(base_url, endpoint, url, sizeof(url)) < 0) {
        if (manager)
            rac_telemetry_manager_http_complete(manager, RAC_FALSE, nullptr,
                                                "telemetry URL build failed");
        return;
    }
    std::vector<rac_http_header_kv_t> headers;
    const rac_http_header_kv_t* defaults = nullptr;
    size_t default_count = 0;
    if (rac_http_default_headers(&defaults, &default_count) == RAC_SUCCESS && defaults) {
        headers.assign(defaults, defaults + default_count);
    }
    std::string auth_value;
    if (requires_auth == RAC_TRUE) {
        const char* token = rac_auth_get_access_token();
        if (token && token[0] != '\0') {
            auth_value = std::string("Bearer ") + token;
            headers.push_back({"Authorization", auth_value.c_str()});
        }
    }
    rac_http_client_t* client = nullptr;
    if (rac_http_client_create(&client) != RAC_SUCCESS) {
        if (manager)
            rac_telemetry_manager_http_complete(manager, RAC_FALSE, nullptr,
                                                "telemetry client create failed");
        return;
    }
    rac_http_request_t request = {};
    request.method = "POST";
    request.url = url;
    request.headers = headers.empty() ? nullptr : headers.data();
    request.header_count = headers.size();
    request.body_bytes = reinterpret_cast<const uint8_t*>(json_body);
    request.body_len = json_length;
    request.timeout_ms = rac_env_default_http_timeout_ms(rac_state_get_environment());
    request.follow_redirects = RAC_FALSE;
    rac_http_response_t response = {};
    const rac_result_t rc = rac_http_request_send(client, &request, &response);
    rac_http_client_destroy(client);
    const bool ok = rc == RAC_SUCCESS && response.status >= 200 && response.status < 300;
    std::string body;
    if (response.body_bytes && response.body_len > 0) {
        body.assign(reinterpret_cast<const char*>(response.body_bytes), response.body_len);
    }
    if (manager) {
        rac_telemetry_manager_http_complete(manager, ok ? RAC_TRUE : RAC_FALSE,
                                            body.empty() ? nullptr : body.c_str(),
                                            ok ? nullptr : "telemetry POST failed");
    }
    rac_http_response_free(&response);
}

void telemetry_teardown_flush() {
    std::lock_guard<std::mutex> lock(g_handles_mutex);
    if (g_telemetry_manager) rac_events_flush_telemetry_sink();
}
void telemetry_teardown_destroy() {
    rac_telemetry_manager_t* mgr = nullptr;
    {
        std::lock_guard<std::mutex> lock(g_handles_mutex);
        mgr = g_telemetry_manager;
        g_telemetry_manager = nullptr;
    }
    if (mgr) {
        rac_events_set_telemetry_sink(nullptr);
        rac_telemetry_manager_destroy(mgr);
    }
}

Napi::Value DevicePersistentId(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    char device_id[RAC_DEVICE_ID_BUFFER_MIN_SIZE] = {};
    if (rac_device_get_or_create_persistent_id(device_id, sizeof(device_id)) != RAC_SUCCESS) {
        return Napi::String::New(env, "");
    }
    return Napi::String::New(env, device_id);
}

Napi::Value DevStagingBaseUrl(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    const char* baked = rac_dev_config_get_staging_base_url();
    if (baked && rac_dev_config_is_usable_http_url(baked)) return Napi::String::New(env, baked);
    return Napi::String::New(env, "");
}

// Runs transport-register + state seed + telemetry sink + two-phase init off the
// JS thread; resolves with the serialized SdkInitResult bytes.
class ControlPlaneWorker : public Napi::AsyncWorker {
 public:
    ControlPlaneWorker(Napi::Env env, int32_t environment, std::string api_key, std::string base_url,
                       std::string device_id, std::string platform, std::string sdk_version,
                       std::string sdk_binding, std::string app_identifier, std::string app_name,
                       std::string app_version, std::vector<uint8_t> phase1,
                       std::vector<uint8_t> phase2)
        : Napi::AsyncWorker(env),
          deferred_(Napi::Promise::Deferred::New(env)),
          env_(environment),
          api_key_(std::move(api_key)),
          base_url_(std::move(base_url)),
          device_id_(std::move(device_id)),
          platform_(std::move(platform)),
          sdk_version_(std::move(sdk_version)),
          sdk_binding_(std::move(sdk_binding)),
          app_identifier_(std::move(app_identifier)),
          app_name_(std::move(app_name)),
          app_version_(std::move(app_version)),
          phase1_(std::move(phase1)),
          phase2_(std::move(phase2)) {}

    Napi::Promise Promise() { return deferred_.Promise(); }

    void Execute() override {
        const auto env = static_cast<rac_environment_t>(env_);
        rac_desktop_http_transport_register();
        rac_state_initialize(env, api_key_.c_str(), base_url_.c_str(), device_id_.c_str());
        // Install native device-info callbacks before phase 1/2, which trigger
        // rac_device_manager_register_if_needed(); without them the backend only
        // gets a placeholder "Unknown" device row.
        rac_desktop_device_callbacks_register();

        rac_sdk_config_t cfg = {};
        cfg.environment = env;
        cfg.api_key = api_key_.c_str();
        cfg.base_url = base_url_.c_str();
        cfg.device_id = device_id_.c_str();
        cfg.platform = platform_.c_str();
        cfg.sdk_version = sdk_version_.c_str();
        cfg.client_info.sdk_binding = sdk_binding_.c_str();
        cfg.client_info.app_identifier = app_identifier_.c_str();
        cfg.client_info.app_name = app_name_.c_str();
        cfg.client_info.app_version = app_version_.c_str();
        rac_sdk_init(&cfg);
        rac_auth_init(nullptr);

        {
            std::lock_guard<std::mutex> lock(g_handles_mutex);
            if (!g_telemetry_manager) {
                g_telemetry_manager = rac_telemetry_manager_create(
                    env, device_id_.c_str(), platform_.c_str(), sdk_version_.c_str());
                if (g_telemetry_manager) {
                    rac_telemetry_manager_set_http_callback(
                        g_telemetry_manager, electron_telemetry_http_callback, g_telemetry_manager);
                    rac_events_set_telemetry_sink(g_telemetry_manager);
                }
            }
        }

        rac_proto_buffer_t p1out;
        rac_proto_buffer_init(&p1out);
        rac_result_t rc = rac_sdk_init_phase1_proto(phase1_.data(), phase1_.size(), &p1out);
        rac_proto_buffer_free(&p1out);
        if (rc != RAC_SUCCESS) {
            code_ = rc;
            err_ = "sdk_init_phase1 failed: " + std::to_string(rc);
            return;
        }
        rac_proto_buffer_t p2out;
        rac_proto_buffer_init(&p2out);
        rc = rac_sdk_init_phase2_proto(phase2_.data(), phase2_.size(), &p2out);
        if (rc != RAC_SUCCESS) {
            rac_proto_buffer_free(&p2out);
            code_ = rc;
            err_ = "sdk_init_phase2 failed: " + std::to_string(rc);
            return;
        }
        if (p2out.data && p2out.size > 0) result_.assign(p2out.data, p2out.data + p2out.size);
        rac_proto_buffer_free(&p2out);
        ok_ = true;
    }

    void OnOK() override {
        Napi::HandleScope scope(Env());
        if (ok_) {
            deferred_.Resolve(Napi::Buffer<uint8_t>::Copy(Env(), result_.data(), result_.size()));
        } else {
            deferred_.Reject(make_rac_error(Env(), code_, err_).Value());
        }
    }
    void OnError(const Napi::Error& e) override {
        Napi::HandleScope scope(Env());
        deferred_.Reject(e.Value());
    }

 private:
    Napi::Promise::Deferred deferred_;
    int32_t env_;
    std::string api_key_, base_url_, device_id_, platform_, sdk_version_, sdk_binding_;
    std::string app_identifier_, app_name_, app_version_;
    std::vector<uint8_t> phase1_, phase2_, result_;
    std::string err_;
    bool ok_ = false;
    rac_result_t code_ = RAC_SUCCESS;
};

Napi::Value ConfigureControlPlane(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    if (!g_initialized.load()) {
        Napi::Error::New(env, "not initialized").ThrowAsJavaScriptException();
        return env.Undefined();
    }
    if (info.Length() < 12 || !info[0].IsNumber() || !info[10].IsTypedArray() ||
        !info[11].IsTypedArray()) {
        Napi::TypeError::New(env, "configureControlPlane(env, apiKey, baseUrl, deviceId, platform, "
                                  "sdkVersion, sdkBinding, appIdentifier, appName, appVersion, "
                                  "phase1Bytes, phase2Bytes) bad args")
            .ThrowAsJavaScriptException();
        return env.Undefined();
    }
    auto str = [&](int i) {
        return info[i].IsString() ? info[i].As<Napi::String>().Utf8Value() : std::string();
    };
    auto* worker = new ControlPlaneWorker(env, info[0].As<Napi::Number>().Int32Value(), str(1),
                                          str(2), str(3), str(4), str(5), str(6), str(7), str(8),
                                          str(9), bytes_of(info[10]), bytes_of(info[11]));
    Napi::Promise promise = worker->Promise();
    worker->Queue();
    return promise;
}
#endif  // RAC_ELECTRON_HAVE_DESKTOP

// Secure key-value store (platform-adapter backed; DPAPI on Windows).
Napi::Value SecureSet(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    if (!g_initialized.load()) {
        Napi::Error::New(env, "not initialized").ThrowAsJavaScriptException();
        return env.Undefined();
    }
    if (info.Length() < 2 || !info[0].IsString() || !info[1].IsString()) {
        Napi::TypeError::New(env, "secureSet(key, value) expects strings")
            .ThrowAsJavaScriptException();
        return env.Undefined();
    }
    if (!g_adapter.secure_set) {
        Napi::Error::New(env, "secure store unavailable").ThrowAsJavaScriptException();
        return env.Undefined();
    }
    std::string key = info[0].As<Napi::String>().Utf8Value();
    std::string value = info[1].As<Napi::String>().Utf8Value();
    rac_result_t rc = g_adapter.secure_set(key.c_str(), value.c_str(), g_adapter.user_data);
    if (rc != RAC_SUCCESS) throw_rac_error(env, rc, "secure_set");
    return env.Undefined();
}

Napi::Value SecureGet(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    if (!g_initialized.load()) {
        Napi::Error::New(env, "not initialized").ThrowAsJavaScriptException();
        return env.Undefined();
    }
    if (info.Length() < 1 || !info[0].IsString()) {
        Napi::TypeError::New(env, "secureGet(key) expects a string").ThrowAsJavaScriptException();
        return env.Undefined();
    }
    if (!g_adapter.secure_get) return env.Null();
    std::string key = info[0].As<Napi::String>().Utf8Value();
    char* out = nullptr;
    rac_result_t rc = g_adapter.secure_get(key.c_str(), &out, g_adapter.user_data);
    if (rc != RAC_SUCCESS || !out) {
        if (out) rac_free(out);
        return env.Null();
    }
    std::string val(out);
    rac_free(out);
    return Napi::String::New(env, val);
}

Napi::Value SecureDelete(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    if (!g_initialized.load()) {
        Napi::Error::New(env, "not initialized").ThrowAsJavaScriptException();
        return env.Undefined();
    }
    if (info.Length() < 1 || !info[0].IsString()) return env.Undefined();
    std::string key = info[0].As<Napi::String>().Utf8Value();
    if (g_adapter.secure_delete) g_adapter.secure_delete(key.c_str(), g_adapter.user_data);
    return env.Undefined();
}

Napi::Value FrameworksForCapability(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    if (!g_initialized.load()) {
        Napi::Error::New(env, "not initialized").ThrowAsJavaScriptException();
        return env.Undefined();
    }
    if (info.Length() < 1 || !info[0].IsTypedArray()) {
        Napi::TypeError::New(env, "frameworksForCapability(protoBytes) bad args")
            .ThrowAsJavaScriptException();
        return env.Undefined();
    }
    std::vector<uint8_t> in = bytes_of(info[0]);
    uint8_t* out = nullptr;
    size_t out_size = 0;
    rac_result_t rc =
        rac_router_frameworks_for_capability_proto(in.data(), in.size(), &out, &out_size);
    if (rc != RAC_SUCCESS) {
        if (out) rac_router_frameworks_for_capability_proto_free(out);
        throw_rac_error(env, rc, "frameworksForCapability");
        return env.Undefined();
    }
    Napi::Buffer<uint8_t> buf = Napi::Buffer<uint8_t>::Copy(env, out ? out : nullptr, out_size);
    rac_router_frameworks_for_capability_proto_free(out);
    return buf;
}

// The GPU backend the addon was compiled with. Compile-time fact, not a runtime
// probe; the SDK adds its own device description on top.
Napi::Value DeviceType(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
#if defined(RAC_GPU_CUDA)
    return Napi::String::New(env, "cuda");
#elif defined(__APPLE__)
    return Napi::String::New(env, "metal");
#else
    return Napi::String::New(env, "cpu");
#endif
}

// Model registry + lifecycle
Napi::Value RegisterModel(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    if (!g_initialized.load()) {
        Napi::Error::New(env, "not initialized").ThrowAsJavaScriptException();
        return env.Undefined();
    }
    if (info.Length() < 1 || !info[0].IsTypedArray()) {
        Napi::TypeError::New(env, "registerModel(protoBytes) bad args").ThrowAsJavaScriptException();
        return env.Undefined();
    }
    std::vector<uint8_t> in = bytes_of(info[0]);
    rac_result_t rc =
        rac_model_registry_register_proto(rac_get_model_registry(), in.data(), in.size());
    if (rc != RAC_SUCCESS) {
        throw_rac_error(env, rc, "registerModel");
        return env.Undefined();
    }
    return env.Undefined();
}

Napi::Value RegisterModelFromUrl(const Napi::CallbackInfo& info) {
    return sync_proto_in(info, rac_register_model_from_url_proto, "registerModelFromUrl");
}

Napi::Value LoadModel(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    if (!g_initialized.load()) {
        Napi::Error::New(env, "not initialized").ThrowAsJavaScriptException();
        return env.Undefined();
    }
    if (info.Length() < 1 || !info[0].IsTypedArray()) {
        Napi::TypeError::New(env, "loadModel(protoBytes) bad args").ThrowAsJavaScriptException();
        return env.Undefined();
    }
    std::vector<uint8_t> in = bytes_of(info[0]);
    return queue_async(
        env,
        [in](rac_proto_buffer_t* out) {
            return rac_model_lifecycle_load_proto(rac_get_model_registry(), in.data(), in.size(),
                                                  out);
        },
        "loadModel");
}

Napi::Value ResolveModelPaths(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    if (!g_initialized.load()) {
        Napi::Error::New(env, "not initialized").ThrowAsJavaScriptException();
        return env.Undefined();
    }
    if (info.Length() < 1 || !info[0].IsTypedArray()) {
        Napi::TypeError::New(env, "resolveModelPaths(protoBytes) bad args")
            .ThrowAsJavaScriptException();
        return env.Undefined();
    }
    std::vector<uint8_t> in = bytes_of(info[0]);
    rac_proto_buffer_t out;
    rac_proto_buffer_init(&out);
    rac_result_t rc =
        rac_model_lifecycle_resolve_paths_proto(rac_get_model_registry(), in.data(), in.size(), &out);
    if (rc != RAC_SUCCESS && out.status == RAC_SUCCESS) out.status = rc;
    return buffer_to_js(env, &out, "resolveModelPaths");
}

Napi::Value UnloadModel(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    if (!g_initialized.load()) {
        Napi::Error::New(env, "not initialized").ThrowAsJavaScriptException();
        return env.Undefined();
    }
    if (info.Length() < 1 || !info[0].IsTypedArray()) {
        Napi::TypeError::New(env, "unloadModel(protoBytes) bad args").ThrowAsJavaScriptException();
        return env.Undefined();
    }
    std::vector<uint8_t> in = bytes_of(info[0]);
    return queue_async(
        env, [in](rac_proto_buffer_t* out) {
            return rac_model_lifecycle_unload_proto(in.data(), in.size(), out);
        },
        "unloadModel");
}

Napi::Value CurrentModel(const Napi::CallbackInfo& info) {
    return sync_proto_in(info, rac_model_lifecycle_current_model_proto, "currentModel");
}

Napi::Value RegisterMultiFile(const Napi::CallbackInfo& info) {
    return sync_proto_in(info, rac_register_multi_file_model_proto, "registerMultiFile");
}

// Registry reads need the model-registry handle, so they can't use sync_proto_in.
Napi::Value ModelList(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    if (!g_initialized.load()) {
        Napi::Error::New(env, "not initialized").ThrowAsJavaScriptException();
        return env.Undefined();
    }
    if (info.Length() < 1 || !info[0].IsTypedArray()) {
        Napi::TypeError::New(env, "modelList(protoBytes) bad args").ThrowAsJavaScriptException();
        return env.Undefined();
    }
    std::vector<uint8_t> in = bytes_of(info[0]);
    rac_proto_buffer_t out;
    rac_proto_buffer_init(&out);
    rac_result_t rc =
        rac_model_registry_list_models_proto(rac_get_model_registry(), in.data(), in.size(), &out);
    if (rc != RAC_SUCCESS && out.status == RAC_SUCCESS) out.status = rc;
    return buffer_to_js(env, &out, "modelList");
}

Napi::Value ModelGet(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    if (!g_initialized.load()) {
        Napi::Error::New(env, "not initialized").ThrowAsJavaScriptException();
        return env.Undefined();
    }
    if (info.Length() < 1 || !info[0].IsTypedArray()) {
        Napi::TypeError::New(env, "modelGet(protoBytes) bad args").ThrowAsJavaScriptException();
        return env.Undefined();
    }
    std::vector<uint8_t> in = bytes_of(info[0]);
    rac_proto_buffer_t out;
    rac_proto_buffer_init(&out);
    rac_result_t rc =
        rac_model_registry_get_model_proto(rac_get_model_registry(), in.data(), in.size(), &out);
    if (rc != RAC_SUCCESS && out.status == RAC_SUCCESS) out.status = rc;
    return buffer_to_js(env, &out, "modelGet");
}

// Registry-metadata removal (matches Swift `models.unregister`). File cleanup on
// disk is a separate concern; this drops the entry so it stops being loadable.
Napi::Value DeleteModel(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    if (!g_initialized.load()) {
        Napi::Error::New(env, "not initialized").ThrowAsJavaScriptException();
        return env.Undefined();
    }
    if (info.Length() < 1 || !info[0].IsString()) {
        Napi::TypeError::New(env, "deleteModel(modelId) bad args").ThrowAsJavaScriptException();
        return env.Undefined();
    }
    std::string model_id = info[0].As<Napi::String>().Utf8Value();
    rac_result_t rc = rac_model_registry_remove_proto(rac_get_model_registry(), model_id.c_str());
    if (rc != RAC_SUCCESS) {
        throw_rac_error(env, rc, "deleteModel");
    }
    return env.Undefined();
}

// LoRA adapters over the loaded LLM. All are proto-in/out against the process-wide
// adapter state, so no handle is needed.
Napi::Value LoraApply(const Napi::CallbackInfo& info) {
    return sync_proto_in(info, rac_lora_apply_proto, "loraApply");
}
Napi::Value LoraRemove(const Napi::CallbackInfo& info) {
    return sync_proto_in(info, rac_lora_remove_proto, "loraRemove");
}
Napi::Value LoraList(const Napi::CallbackInfo& info) {
    return sync_proto_in(info, rac_lora_list_proto, "loraList");
}
Napi::Value LoraState(const Napi::CallbackInfo& info) {
    return sync_proto_in(info, rac_lora_state_proto, "loraState");
}

// Image generation via the loaded diffusion model. Heavy, so it runs on a worker.
// Returns FEATURE_NOT_AVAILABLE from commons when no diffusion engine is linked.
Napi::Value ImageGenerate(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    if (!g_initialized.load()) {
        Napi::Error::New(env, "not initialized").ThrowAsJavaScriptException();
        return env.Undefined();
    }
    if (info.Length() < 1 || !info[0].IsTypedArray()) {
        Napi::TypeError::New(env, "imageGenerate(protoBytes) bad args").ThrowAsJavaScriptException();
        return env.Undefined();
    }
    std::vector<uint8_t> in = bytes_of(info[0]);
    return queue_async(
        env,
        [in](rac_proto_buffer_t* out) {
            return rac_diffusion_generate_lifecycle_proto(in.data(), in.size(), out);
        },
        "imageGenerate");
}

// Download orchestration (commons-driven over the desktop HTTP transport)
Napi::Value DownloadPlan(const Napi::CallbackInfo& info) {
    return sync_proto_in(info, rac_download_plan_proto, "downloadPlan");
}
Napi::Value DownloadStart(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    if (!g_initialized.load()) {
        Napi::Error::New(env, "not initialized").ThrowAsJavaScriptException();
        return env.Undefined();
    }
    if (info.Length() < 1 || !info[0].IsTypedArray()) {
        Napi::TypeError::New(env, "downloadStart(protoBytes) bad args").ThrowAsJavaScriptException();
        return env.Undefined();
    }
    std::vector<uint8_t> in = bytes_of(info[0]);
    return queue_async(
        env, [in](rac_proto_buffer_t* out) {
            return rac_download_start_proto(in.data(), in.size(), out);
        },
        "downloadStart");
}
Napi::Value DownloadCancel(const Napi::CallbackInfo& info) {
    return sync_proto_in(info, rac_download_cancel_proto, "downloadCancel");
}
Napi::Value DownloadResume(const Napi::CallbackInfo& info) {
    return sync_proto_in(info, rac_download_resume_proto, "downloadResume");
}
Napi::Value DownloadProgressPoll(const Napi::CallbackInfo& info) {
    return sync_proto_in(info, rac_download_progress_poll_proto, "downloadProgressPoll");
}

// LLM
Napi::Value LlmGenerate(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    if (!g_initialized.load()) {
        Napi::Error::New(env, "not initialized").ThrowAsJavaScriptException();
        return env.Undefined();
    }
    if (info.Length() < 1 || !info[0].IsTypedArray()) {
        Napi::TypeError::New(env, "llmGenerate(protoBytes) bad args").ThrowAsJavaScriptException();
        return env.Undefined();
    }
    std::vector<uint8_t> in = bytes_of(info[0]);
    return queue_async(
        env, [in](rac_proto_buffer_t* out) {
            return rac_llm_generate_proto(in.data(), in.size(), out);
        },
        "llmGenerate");
}

Napi::Value LlmGenerateStream(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    if (!g_initialized.load()) {
        Napi::Error::New(env, "not initialized").ThrowAsJavaScriptException();
        return env.Undefined();
    }
    if (info.Length() < 2 || !info[0].IsTypedArray() || !info[1].IsFunction()) {
        Napi::TypeError::New(env, "llmGenerateStream(protoBytes, onEvent) bad args")
            .ThrowAsJavaScriptException();
        return env.Undefined();
    }
    auto in = std::make_shared<std::vector<uint8_t>>(bytes_of(info[0]));
    return start_stream(
        env, info[1].As<Napi::Function>(),
        [in](StreamCtx* ctx) {
            return rac_llm_generate_stream_proto(in->data(), in->size(), stream_event_cb, ctx);
        },
        []() { rac_llm_proto_quiesce(); }, kLifecycleLease, "llmGenerateStream");
}

Napi::Value LlmCancel(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    if (!g_initialized.load()) return env.Undefined();
    rac_proto_buffer_t out;
    rac_proto_buffer_init(&out);
    rac_llm_cancel_proto(&out);
    rac_proto_buffer_free(&out);
    return env.Undefined();
}

// Structured output: schema-in-prompt prepare + post-generation parse/validate.
Napi::Value StructuredPreparePrompt(const Napi::CallbackInfo& info) {
    return sync_proto_in(info, rac_structured_output_prepare_prompt_proto, "structuredPreparePrompt");
}
Napi::Value StructuredParse(const Napi::CallbackInfo& info) {
    return sync_proto_in(info, rac_structured_output_parse_proto, "structuredParse");
}
// Tool calling: commons drives the generate -> parse -> execute -> follow-up loop
// (rac_tool_calling_run_loop_proto) and calls back synchronously to execute each
// tool. The loop runs on a worker thread; each execute bridges to the JS executor
// via a blocking TSFN, then waits on a condition variable for the JS result
// (handling a sync Uint8Array or an async Promise<Uint8Array>). This mirrors the
// Swift NSCondition / Kotlin runBlocking round-trip.
struct ToolCtx {
    Napi::ThreadSafeFunction tsfn;  // wraps the JS executor (ToolCall bytes -> ToolResult bytes)
    std::thread worker;
    Napi::Promise::Deferred deferred;
    std::vector<uint8_t> request;
    rac_result_t result = RAC_SUCCESS;
    std::vector<uint8_t> result_bytes;
    std::string err;
    explicit ToolCtx(Napi::Env env) : deferred(Napi::Promise::Deferred::New(env)) {}
};

// One execute round-trip's result slot, filled on the JS thread and awaited on
// the worker thread.
struct ToolExecSlot {
    std::mutex m;
    std::condition_variable cv;
    bool done = false;
    bool ok = false;
    std::vector<uint8_t> result;
};

rac_result_t tool_execute_cb(const uint8_t* call, size_t n, rac_proto_buffer_t* out, void* ud) {
    auto* ctx = static_cast<ToolCtx*>(ud);
    auto slot = std::make_shared<ToolExecSlot>();
    std::vector<uint8_t> call_bytes(call, call + n);
    napi_status st = ctx->tsfn.BlockingCall(
        [call_bytes, slot](Napi::Env env, Napi::Function on_execute) {
            auto finish = [slot](const uint8_t* d, size_t len, bool ok) {
                {
                    std::lock_guard<std::mutex> lk(slot->m);
                    if (d && len) slot->result.assign(d, d + len);
                    slot->ok = ok;
                    slot->done = true;
                }
                slot->cv.notify_all();
            };
            try {
                Napi::Value r = on_execute.Call(
                    {Napi::Buffer<uint8_t>::Copy(env, call_bytes.data(), call_bytes.size())});
                if (r.IsPromise()) {
                    Napi::Promise p = r.As<Napi::Promise>();
                    Napi::Function on_ok = Napi::Function::New(
                        env, [slot, finish](const Napi::CallbackInfo& info) -> Napi::Value {
                            if (info.Length() > 0 && info[0].IsTypedArray()) {
                                Napi::Uint8Array b = info[0].As<Napi::Uint8Array>();
                                finish(b.Data(), b.ByteLength(), true);
                            } else {
                                finish(nullptr, 0, false);
                            }
                            return info.Env().Undefined();
                        });
                    Napi::Function on_err = Napi::Function::New(
                        env, [slot, finish](const Napi::CallbackInfo& info) -> Napi::Value {
                            finish(nullptr, 0, false);
                            return info.Env().Undefined();
                        });
                    p.Get("then").As<Napi::Function>().Call(p, {on_ok, on_err});
                } else if (r.IsTypedArray()) {
                    Napi::Uint8Array b = r.As<Napi::Uint8Array>();
                    finish(b.Data(), b.ByteLength(), true);
                } else {
                    finish(nullptr, 0, false);
                }
            } catch (...) {
                finish(nullptr, 0, false);
            }
        });
    if (st != napi_ok) return RAC_ERROR_INTERNAL;
    std::unique_lock<std::mutex> lk(slot->m);
    slot->cv.wait(lk, [&] { return slot->done; });
    if (!slot->ok) return RAC_ERROR_INTERNAL;
    return rac_proto_buffer_copy(slot->result.data(), slot->result.size(), out);
}

void tool_handle_cb(uint64_t handle, void* /*ud*/) { g_tool_handle.store(handle); }

Napi::Value ToolRunLoop(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    if (!g_initialized.load()) {
        Napi::Error::New(env, "not initialized").ThrowAsJavaScriptException();
        return env.Undefined();
    }
    if (info.Length() < 2 || !info[0].IsTypedArray() || !info[1].IsFunction()) {
        Napi::TypeError::New(env, "toolRunLoop(requestBytes, onExecute) bad args")
            .ThrowAsJavaScriptException();
        return env.Undefined();
    }
    auto* ctx = new ToolCtx(env);
    ctx->request = bytes_of(info[0]);
    inflight_inc(kLifecycleLease);
    try {
        ctx->tsfn = Napi::ThreadSafeFunction::New(
            env, info[1].As<Napi::Function>(), "ra-tool-exec", /*maxQueueSize*/ 16,
            /*initialThreadCount*/ 1, ctx,
            [](Napi::Env env, void*, ToolCtx* c) {
                if (c->worker.joinable()) c->worker.join();
                inflight_dec(kLifecycleLease);
                g_tool_handle.store(0);
                if (c->result == RAC_SUCCESS) {
                    c->deferred.Resolve(
                        Napi::Buffer<uint8_t>::Copy(env, c->result_bytes.data(), c->result_bytes.size()));
                } else {
                    c->deferred.Reject(
                        make_rac_error(env, c->result,
                                       c->err.empty() ? ("tool run loop failed: " + std::to_string(c->result))
                                                      : c->err)
                            .Value());
                }
                delete c;
            },
            static_cast<void*>(nullptr));
        ctx->worker = std::thread([ctx]() {
            rac_proto_buffer_t out;
            rac_proto_buffer_init(&out);
            rac_result_t rc = rac_tool_calling_run_loop_proto(ctx->request.data(), ctx->request.size(),
                                                              tool_execute_cb, ctx, tool_handle_cb,
                                                              ctx, &out);
            if (rc != RAC_SUCCESS && out.status == RAC_SUCCESS) out.status = rc;
            ctx->result = out.status;
            if (out.status == RAC_SUCCESS && out.data) {
                ctx->result_bytes.assign(out.data, out.data + out.size);
            } else if (out.error_message) {
                ctx->err = out.error_message;
            }
            rac_proto_buffer_free(&out);
            ctx->tsfn.Release();
        });
    } catch (...) {
        inflight_dec(kLifecycleLease);
        delete ctx;
        throw;
    }
    return ctx->deferred.Promise();
}

Napi::Value ToolCancel(const Napi::CallbackInfo& info) {
    uint64_t h = g_tool_handle.load();
    if (h) rac_tool_calling_run_loop_cancel_proto(h);
    return info.Env().Undefined();
}

// VLM
Napi::Value VlmGenerate(const Napi::CallbackInfo& info) {
    return async_proto_in(info, rac_vlm_generate_proto, "vlmGenerate");
}
Napi::Value VlmGenerateStream(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    if (!g_initialized.load()) {
        Napi::Error::New(env, "not initialized").ThrowAsJavaScriptException();
        return env.Undefined();
    }
    if (info.Length() < 2 || !info[0].IsTypedArray() || !info[1].IsFunction()) {
        Napi::TypeError::New(env, "vlmGenerateStream(protoBytes, onEvent) bad args")
            .ThrowAsJavaScriptException();
        return env.Undefined();
    }
    auto in = std::make_shared<std::vector<uint8_t>>(bytes_of(info[0]));
    return start_stream(
        env, info[1].As<Napi::Function>(),
        [in](StreamCtx* ctx) {
            return rac_vlm_stream_proto(in->data(), in->size(), stream_event_cb_bool, ctx);
        },
        []() { rac_vlm_proto_quiesce(); }, kLifecycleLease, "vlmGenerateStream");
}
Napi::Value VlmCancel(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    if (!g_initialized.load()) return env.Undefined();
    rac_proto_buffer_t out;
    rac_proto_buffer_init(&out);
    rac_vlm_cancel_lifecycle_proto(&out);
    rac_proto_buffer_free(&out);
    return env.Undefined();
}

// STT — one-shot transcribe + streamed transcribe. The live push session
// (feed audio incrementally) is a separate ABI, deferred to a follow-up.
Napi::Value SttTranscribe(const Napi::CallbackInfo& info) {
    return async_proto_in(info, rac_stt_transcribe_lifecycle_proto, "sttTranscribe");
}
Napi::Value SttTranscribeStream(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    if (!g_initialized.load()) {
        Napi::Error::New(env, "not initialized").ThrowAsJavaScriptException();
        return env.Undefined();
    }
    if (info.Length() < 2 || !info[0].IsTypedArray() || !info[1].IsFunction()) {
        Napi::TypeError::New(env, "sttTranscribeStream(protoBytes, onEvent) bad args")
            .ThrowAsJavaScriptException();
        return env.Undefined();
    }
    auto in = std::make_shared<std::vector<uint8_t>>(bytes_of(info[0]));
    return start_stream(
        env, info[1].As<Napi::Function>(),
        [in](StreamCtx* ctx) {
            return rac_stt_transcribe_stream_lifecycle_proto(in->data(), in->size(),
                                                             stream_event_cb, ctx);
        },
        nullptr, kLifecycleLease, "sttTranscribeStream");
}
Napi::Value SttStreamStart(const Napi::CallbackInfo& info) {
    return not_impl(info.Env(), "sttStreamStart (live push session)");
}
Napi::Value SttStreamFeed(const Napi::CallbackInfo& info) {
    return not_impl(info.Env(), "sttStreamFeed (live push session)");
}
Napi::Value SttStreamStop(const Napi::CallbackInfo& info) {
    return not_impl(info.Env(), "sttStreamStop (live push session)");
}
Napi::Value SttStreamCancel(const Napi::CallbackInfo& info) {
    return not_impl(info.Env(), "sttStreamCancel (live push session)");
}
Napi::Value SttStreamSubscribe(const Napi::CallbackInfo& info) {
    return not_impl(info.Env(), "sttStreamSubscribe (live push session)");
}
Napi::Value SttState(const Napi::CallbackInfo& info) {
    return sync_proto_out(info.Env(), rac_stt_state_lifecycle_proto, "sttState");
}

// TTS
Napi::Value TtsSynthesize(const Napi::CallbackInfo& info) {
    return async_proto_in(info, rac_tts_synthesize_lifecycle_proto, "ttsSynthesize");
}
Napi::Value TtsSynthesizeStream(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    if (!g_initialized.load()) {
        Napi::Error::New(env, "not initialized").ThrowAsJavaScriptException();
        return env.Undefined();
    }
    if (info.Length() < 2 || !info[0].IsTypedArray() || !info[1].IsFunction()) {
        Napi::TypeError::New(env, "ttsSynthesizeStream(protoBytes, onEvent) bad args")
            .ThrowAsJavaScriptException();
        return env.Undefined();
    }
    auto in = std::make_shared<std::vector<uint8_t>>(bytes_of(info[0]));
    return start_stream(
        env, info[1].As<Napi::Function>(),
        [in](StreamCtx* ctx) {
            return rac_tts_synthesize_stream_lifecycle_proto(in->data(), in->size(),
                                                            stream_event_cb, ctx);
        },
        nullptr, kLifecycleLease, "ttsSynthesizeStream");
}
Napi::Value TtsStop(const Napi::CallbackInfo& info) {
    return sync_proto_out(info.Env(), rac_tts_stop_lifecycle_proto, "ttsStop");
}
Napi::Value TtsListVoices(const Napi::CallbackInfo& info) {
    return sync_proto_out(info.Env(), rac_tts_list_voices_lifecycle_proto, "ttsListVoices");
}

// VAD — the built-in energy detector (a component, no model). Created lazily so
// vad.process() works without loading a Silero model.
Napi::Value empty_buffer(Napi::Env env) { return Napi::Buffer<uint8_t>::New(env, 0); }

rac_handle_t ensure_vad(Napi::Env env) {
    std::lock_guard<std::mutex> lock(g_handles_mutex);
    if (!g_vad_handle) {
        rac_result_t rc = rac_vad_component_create(&g_vad_handle);
        if (rc != RAC_SUCCESS || !g_vad_handle) {
            g_vad_handle = nullptr;
            throw_rac_error(env, rc, "vad create");
            return nullptr;
        }
        // create -> initialize (builds the energy vad_service) -> start, so that
        // process() has a running detector (it returns NOT_INITIALIZED otherwise).
        rc = rac_vad_component_initialize(g_vad_handle);
        if (rc == RAC_SUCCESS) rc = rac_vad_component_start(g_vad_handle);
        if (rc != RAC_SUCCESS) {
            rac_vad_component_destroy(g_vad_handle);
            g_vad_handle = nullptr;
            throw_rac_error(env, rc, "vad init");
            return nullptr;
        }
    }
    return g_vad_handle;
}

Napi::Value VadConfigure(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    if (!g_initialized.load()) {
        Napi::Error::New(env, "not initialized").ThrowAsJavaScriptException();
        return env.Undefined();
    }
    if (info.Length() < 1 || !info[0].IsTypedArray()) {
        Napi::TypeError::New(env, "vadConfigure(protoBytes) bad args").ThrowAsJavaScriptException();
        return env.Undefined();
    }
    rac_handle_t h = ensure_vad(env);
    if (!h) return env.Undefined();
    std::vector<uint8_t> in = bytes_of(info[0]);
    rac_result_t rc = rac_vad_component_configure_proto(h, in.data(), in.size());
    if (rc != RAC_SUCCESS) {
        throw_rac_error(env, rc, "vadConfigure");
        return env.Undefined();
    }
    return empty_buffer(env);
}

Napi::Value VadProcess(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    if (!g_initialized.load()) {
        Napi::Error::New(env, "not initialized").ThrowAsJavaScriptException();
        return env.Undefined();
    }
    if (info.Length() < 1 || !info[0].IsTypedArray()) {
        Napi::TypeError::New(env, "vadProcess(protoBytes) bad args").ThrowAsJavaScriptException();
        return env.Undefined();
    }
    rac_handle_t h = ensure_vad(env);
    if (!h) return env.Undefined();
    std::vector<uint8_t> in = bytes_of(info[0]);
    rac_proto_buffer_t out;
    rac_proto_buffer_init(&out);
    rac_result_t rc = rac_vad_component_process_proto(h, in.data(), in.size(), &out);
    if (rc != RAC_SUCCESS && out.status == RAC_SUCCESS) out.status = rc;
    return buffer_to_js(env, &out, "vadProcess");
}

// The energy VAD is per-frame; start/stop are no-ops kept for surface parity.
Napi::Value VadStart(const Napi::CallbackInfo& info) { return empty_buffer(info.Env()); }
Napi::Value VadStop(const Napi::CallbackInfo& info) { return empty_buffer(info.Env()); }
Napi::Value VadReset(const Napi::CallbackInfo& info) {
    if (g_vad_handle) rac_vad_component_reset(g_vad_handle);
    return empty_buffer(info.Env());
}

// Embeddings / diarization / segmentation
Napi::Value Embed(const Napi::CallbackInfo& info) {
    return async_proto_in(info, rac_embeddings_embed_batch_lifecycle_proto, "embed");
}
Napi::Value Diarize(const Napi::CallbackInfo& info) {
    return async_proto_in(info, rac_diarization_diarize_lifecycle_proto, "diarize");
}
Napi::Value Segment(const Napi::CallbackInfo& info) {
    return async_proto_in(info, rac_segmentation_segment_lifecycle_proto, "segment");
}
// Rerank inference is handle-based (rac_rerank_component_rerank_proto) with no
// lifecycle proto entry point, so it needs its own component-handle wiring —
// deferred to a follow-up.
Napi::Value Rerank(const Napi::CallbackInfo& info) { return not_impl(info.Env(), "rerank"); }

// RAG (session handles are integers owned here)
using RagProtoOp = rac_result_t (*)(rac_handle_t, const uint8_t*, size_t, rac_proto_buffer_t*);

class RagCreateSessionWorker : public Napi::AsyncWorker {
 public:
    RagCreateSessionWorker(Napi::Env env, std::vector<uint8_t> config)
        : Napi::AsyncWorker(env),
          deferred_(Napi::Promise::Deferred::New(env)),
          config_(std::move(config)) {}
    Napi::Promise Promise() { return deferred_.Promise(); }
    void Execute() override {
        rac_result_t rc = rac_rag_session_create_proto(config_.data(), config_.size(), &session_);
        code_ = rc;
        ok_ = (rc == RAC_SUCCESS && session_ != nullptr);
        if (!ok_) {
            err_ = "rag session create failed: " + std::to_string(rc);
            session_ = nullptr;
        }
    }
    void OnOK() override {
        Napi::HandleScope scope(Env());
        if (!ok_ || session_ == nullptr) {
            deferred_.Reject(make_rac_error(Env(), code_, err_).Value());
            return;
        }
        int32_t hid;
        {
            std::lock_guard<std::mutex> lock(g_handles_mutex);
            if (!g_initialized.load()) {
                rac_rag_session_destroy_proto(session_);
                deferred_.Reject(make_rac_error(Env(), RAC_ERROR_NOT_INITIALIZED,
                                                "rag session create aborted: SDK shut down")
                                     .Value());
                return;
            }
            hid = g_next_handle_id++;
            g_rag_handles[hid] = session_;
        }
        deferred_.Resolve(Napi::Number::New(Env(), hid));
    }
    void OnError(const Napi::Error& e) override {
        if (session_) rac_rag_session_destroy_proto(session_);
        Napi::HandleScope scope(Env());
        deferred_.Reject(e.Value());
    }

 private:
    Napi::Promise::Deferred deferred_;
    std::vector<uint8_t> config_;
    rac_handle_t session_ = nullptr;
    std::string err_;
    bool ok_ = false;
    rac_result_t code_ = RAC_SUCCESS;
};

Napi::Value RagCreateSession(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    if (info.Length() < 1 || !info[0].IsTypedArray()) {
        Napi::TypeError::New(env, "ragCreateSession(configProtoBytes) bad args")
            .ThrowAsJavaScriptException();
        return env.Undefined();
    }
    auto* worker = new RagCreateSessionWorker(env, bytes_of(info[0]));
    Napi::Promise promise = worker->Promise();
    worker->Queue();
    return promise;
}

class RagProtoWorker : public Napi::AsyncWorker {
 public:
    RagProtoWorker(Napi::Env env, rac_handle_t session, int32_t handle_id,
                   std::vector<uint8_t> input, RagProtoOp op, const char* what)
        : Napi::AsyncWorker(env),
          deferred_(Napi::Promise::Deferred::New(env)),
          session_(session),
          handle_id_(handle_id),
          input_(std::move(input)),
          op_(op),
          what_(what) {}
    Napi::Promise Promise() { return deferred_.Promise(); }
    void Execute() override {
        OpScope scope(handle_id_);
        rac_proto_buffer_t out;
        rac_proto_buffer_init(&out);
        rac_result_t rc = op_(session_, input_.data(), input_.size(), &out);
        if (rc != RAC_SUCCESS && out.status == RAC_SUCCESS) out.status = rc;
        if (out.status == RAC_SUCCESS) {
            if (out.data && out.size > 0) result_.assign(out.data, out.data + out.size);
            ok_ = true;
        } else {
            code_ = out.status;
            err_ = what_ + " failed: " + std::to_string(out.status);
            if (out.error_message) {
                err_ += " (";
                err_ += out.error_message;
                err_ += ")";
            }
        }
        rac_proto_buffer_free(&out);
    }
    void OnOK() override {
        Napi::HandleScope scope(Env());
        if (ok_)
            deferred_.Resolve(Napi::Buffer<uint8_t>::Copy(Env(), result_.data(), result_.size()));
        else
            deferred_.Reject(make_rac_error(Env(), code_, err_).Value());
    }
    void OnError(const Napi::Error& e) override {
        Napi::HandleScope scope(Env());
        deferred_.Reject(e.Value());
    }

 private:
    Napi::Promise::Deferred deferred_;
    rac_handle_t session_;
    int32_t handle_id_;
    std::vector<uint8_t> input_;
    RagProtoOp op_;
    std::string what_;
    std::vector<uint8_t> result_;
    std::string err_;
    bool ok_ = false;
    rac_result_t code_ = RAC_SUCCESS;
};

Napi::Value rag_async_op(const Napi::CallbackInfo& info, RagProtoOp op, const char* what) {
    Napi::Env env = info.Env();
    if (info.Length() < 2 || !info[0].IsNumber() || !info[1].IsTypedArray()) {
        Napi::TypeError::New(env, std::string(what) + "(handleId, protoBytes) bad args")
            .ThrowAsJavaScriptException();
        return env.Undefined();
    }
    int32_t hid = info[0].As<Napi::Number>().Int32Value();
    rac_handle_t h = begin_op(hid);
    if (!h) {
        Napi::Error::New(env, "invalid rag handle").ThrowAsJavaScriptException();
        return env.Undefined();
    }
    auto* worker = new RagProtoWorker(env, h, hid, bytes_of(info[1]), op, what);
    Napi::Promise promise = worker->Promise();
    try {
        worker->Queue();
    } catch (...) {
        end_op(hid);
        delete worker;
        throw;
    }
    return promise;
}

Napi::Value RagIngest(const Napi::CallbackInfo& info) {
    return rag_async_op(info, rac_rag_ingest_proto, "rag ingest");
}
Napi::Value RagQuery(const Napi::CallbackInfo& info) {
    return rag_async_op(info, rac_rag_query_proto, "rag query");
}
Napi::Value RagSearch(const Napi::CallbackInfo& info) {
    return rag_async_op(info, rac_rag_search_proto, "rag search");
}

Napi::Value RagQueryStream(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    if (info.Length() < 3 || !info[0].IsNumber() || !info[1].IsTypedArray() ||
        !info[2].IsFunction()) {
        Napi::TypeError::New(env, "ragQueryStream(handleId, queryProtoBytes, onEvent) bad args")
            .ThrowAsJavaScriptException();
        return env.Undefined();
    }
    int32_t hid = info[0].As<Napi::Number>().Int32Value();
    rac_handle_t h = begin_op(hid);
    if (!h) {
        Napi::Error::New(env, "invalid rag handle").ThrowAsJavaScriptException();
        return env.Undefined();
    }
    auto query = std::make_shared<std::vector<uint8_t>>(bytes_of(info[1]));
    return start_stream(
        env, info[2].As<Napi::Function>(),
        [h, query](StreamCtx* ctx) {
            return rac_rag_query_stream_proto(h, query->data(), query->size(), stream_event_cb_bool,
                                              ctx);
        },
        nullptr, hid, "ragQueryStream");
}

Napi::Value RagStats(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    if (info.Length() < 1 || !info[0].IsNumber()) {
        Napi::TypeError::New(env, "ragStats(handleId) bad args").ThrowAsJavaScriptException();
        return env.Undefined();
    }
    int32_t hid = info[0].As<Napi::Number>().Int32Value();
    rac_handle_t h = begin_op(hid);
    if (!h) {
        Napi::Error::New(env, "invalid rag handle").ThrowAsJavaScriptException();
        return env.Undefined();
    }
    OpScope scope(hid);
    rac_proto_buffer_t out;
    rac_proto_buffer_init(&out);
    rac_result_t rc = rac_rag_stats_proto(h, &out);
    if (rc != RAC_SUCCESS && out.status == RAC_SUCCESS) out.status = rc;
    return buffer_to_js(env, &out, "rag stats");
}

Napi::Value RagClear(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    if (info.Length() < 1 || !info[0].IsNumber()) {
        Napi::TypeError::New(env, "ragClear(handleId) bad args").ThrowAsJavaScriptException();
        return env.Undefined();
    }
    int32_t hid = info[0].As<Napi::Number>().Int32Value();
    rac_handle_t h = begin_op(hid);
    if (!h) {
        Napi::Error::New(env, "invalid rag handle").ThrowAsJavaScriptException();
        return env.Undefined();
    }
    OpScope scope(hid);
    rac_proto_buffer_t out;
    rac_proto_buffer_init(&out);
    rac_result_t rc = rac_rag_clear_proto(h, &out);
    if (rc != RAC_SUCCESS && out.status == RAC_SUCCESS) out.status = rc;
    return buffer_to_js(env, &out, "rag clear");
}

Napi::Value RagCancel(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    if (info.Length() < 1 || !info[0].IsNumber()) return env.Undefined();
    std::lock_guard<std::mutex> lock(g_handles_mutex);
    auto it = g_rag_handles.find(info[0].As<Napi::Number>().Int32Value());
    if (it != g_rag_handles.end()) rac_rag_cancel_proto(it->second);
    return env.Undefined();
}

Napi::Value RagDestroySession(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    if (info.Length() < 1 || !info[0].IsNumber()) return env.Undefined();
    rac_handle_t h = take_rag_handle_when_idle(info[0].As<Napi::Number>().Int32Value());
    if (h) rac_rag_session_destroy_proto(h);
    return env.Undefined();
}

// shutdown
Napi::Value Shutdown(const Napi::CallbackInfo& info) {
    if (g_initialized.exchange(false)) {
        {
            std::unique_lock<std::mutex> lock(g_handles_mutex);
            g_inflight_cv.wait(lock, [] {
                for (auto& kv : g_inflight)
                    if (kv.second > 0) return false;
                return true;
            });
            for (auto& kv : g_rag_handles) rac_rag_session_destroy_proto(kv.second);
            g_rag_handles.clear();
            g_inflight.clear();
            if (g_vad_handle) {
                rac_vad_component_destroy(g_vad_handle);
                g_vad_handle = nullptr;
            }
        }
#ifdef RAC_ELECTRON_HAVE_DESKTOP
        telemetry_teardown_flush();
#endif
        rac_shutdown();
#ifdef RAC_ELECTRON_HAVE_DESKTOP
        telemetry_teardown_destroy();
#endif
    }
    return info.Env().Undefined();
}

Napi::Object Init(Napi::Env env, Napi::Object exports) {
    exports.Set("initialize", Napi::Function::New(env, Initialize));
    exports.Set("shutdown", Napi::Function::New(env, Shutdown));
    exports.Set("version", Napi::String::New(env, rac_sdk_get_version()));
#ifdef RAC_ELECTRON_HAVE_DESKTOP
    exports.Set("hasControlPlane", Napi::Boolean::New(env, true));
    exports.Set("devicePersistentId", Napi::Function::New(env, DevicePersistentId));
    exports.Set("devStagingBaseUrl", Napi::Function::New(env, DevStagingBaseUrl));
    exports.Set("configureControlPlane", Napi::Function::New(env, ConfigureControlPlane));
#else
    exports.Set("hasControlPlane", Napi::Boolean::New(env, false));
    exports.Set("devicePersistentId",
                Napi::Function::New(env, [](const Napi::CallbackInfo& i) -> Napi::Value {
                    return Napi::String::New(i.Env(), "");
                }));
    exports.Set("devStagingBaseUrl",
                Napi::Function::New(env, [](const Napi::CallbackInfo& i) -> Napi::Value {
                    return Napi::String::New(i.Env(), "");
                }));
#endif
    exports.Set("secureSet", Napi::Function::New(env, SecureSet));
    exports.Set("secureGet", Napi::Function::New(env, SecureGet));
    exports.Set("secureDelete", Napi::Function::New(env, SecureDelete));

    exports.Set("frameworksForCapability", Napi::Function::New(env, FrameworksForCapability));
    exports.Set("deviceType", Napi::Function::New(env, DeviceType));
    exports.Set("registerModel", Napi::Function::New(env, RegisterModel));
    exports.Set("registerModelFromUrl", Napi::Function::New(env, RegisterModelFromUrl));
    exports.Set("registerMultiFile", Napi::Function::New(env, RegisterMultiFile));
    exports.Set("modelList", Napi::Function::New(env, ModelList));
    exports.Set("modelGet", Napi::Function::New(env, ModelGet));
    exports.Set("deleteModel", Napi::Function::New(env, DeleteModel));
    exports.Set("loraApply", Napi::Function::New(env, LoraApply));
    exports.Set("loraRemove", Napi::Function::New(env, LoraRemove));
    exports.Set("loraList", Napi::Function::New(env, LoraList));
    exports.Set("loraState", Napi::Function::New(env, LoraState));
    exports.Set("imageGenerate", Napi::Function::New(env, ImageGenerate));
    exports.Set("modelRegistryList", Napi::Function::New(env, [](const Napi::CallbackInfo& i) {
                    return not_impl(i.Env(), "modelRegistryList");
                }));
    exports.Set("modelRegistryQuery", Napi::Function::New(env, [](const Napi::CallbackInfo& i) {
                    return not_impl(i.Env(), "modelRegistryQuery");
                }));

    exports.Set("loadModel", Napi::Function::New(env, LoadModel));
    exports.Set("resolveModelPaths", Napi::Function::New(env, ResolveModelPaths));
    exports.Set("unloadModel", Napi::Function::New(env, UnloadModel));
    exports.Set("currentModel", Napi::Function::New(env, CurrentModel));

    exports.Set("downloadPlan", Napi::Function::New(env, DownloadPlan));
    exports.Set("downloadStart", Napi::Function::New(env, DownloadStart));
    exports.Set("downloadCancel", Napi::Function::New(env, DownloadCancel));
    exports.Set("downloadResume", Napi::Function::New(env, DownloadResume));
    exports.Set("downloadProgressPoll", Napi::Function::New(env, DownloadProgressPoll));

    exports.Set("llmGenerate", Napi::Function::New(env, LlmGenerate));
    exports.Set("llmGenerateStream", Napi::Function::New(env, LlmGenerateStream));
    exports.Set("llmCancel", Napi::Function::New(env, LlmCancel));
    exports.Set("structuredPreparePrompt", Napi::Function::New(env, StructuredPreparePrompt));
    exports.Set("structuredParse", Napi::Function::New(env, StructuredParse));
    exports.Set("toolRunLoop", Napi::Function::New(env, ToolRunLoop));
    exports.Set("toolCancel", Napi::Function::New(env, ToolCancel));

    exports.Set("vlmGenerate", Napi::Function::New(env, VlmGenerate));
    exports.Set("vlmGenerateStream", Napi::Function::New(env, VlmGenerateStream));
    exports.Set("vlmCancel", Napi::Function::New(env, VlmCancel));
    exports.Set("sttTranscribe", Napi::Function::New(env, SttTranscribe));
    exports.Set("sttTranscribeStream", Napi::Function::New(env, SttTranscribeStream));
    exports.Set("sttStreamStart", Napi::Function::New(env, SttStreamStart));
    exports.Set("sttStreamFeed", Napi::Function::New(env, SttStreamFeed));
    exports.Set("sttStreamStop", Napi::Function::New(env, SttStreamStop));
    exports.Set("sttStreamCancel", Napi::Function::New(env, SttStreamCancel));
    exports.Set("sttStreamSubscribe", Napi::Function::New(env, SttStreamSubscribe));
    exports.Set("sttState", Napi::Function::New(env, SttState));
    exports.Set("ttsSynthesize", Napi::Function::New(env, TtsSynthesize));
    exports.Set("ttsSynthesizeStream", Napi::Function::New(env, TtsSynthesizeStream));
    exports.Set("ttsStop", Napi::Function::New(env, TtsStop));
    exports.Set("ttsListVoices", Napi::Function::New(env, TtsListVoices));
    exports.Set("vadConfigure", Napi::Function::New(env, VadConfigure));
    exports.Set("vadProcess", Napi::Function::New(env, VadProcess));
    exports.Set("vadStart", Napi::Function::New(env, VadStart));
    exports.Set("vadStop", Napi::Function::New(env, VadStop));
    exports.Set("vadReset", Napi::Function::New(env, VadReset));
    exports.Set("embed", Napi::Function::New(env, Embed));
    exports.Set("rerank", Napi::Function::New(env, Rerank));
    exports.Set("diarize", Napi::Function::New(env, Diarize));
    exports.Set("segment", Napi::Function::New(env, Segment));

    exports.Set("ragCreateSession", Napi::Function::New(env, RagCreateSession));
    exports.Set("ragIngest", Napi::Function::New(env, RagIngest));
    exports.Set("ragQuery", Napi::Function::New(env, RagQuery));
    exports.Set("ragQueryStream", Napi::Function::New(env, RagQueryStream));
    exports.Set("ragSearch", Napi::Function::New(env, RagSearch));
    exports.Set("ragStats", Napi::Function::New(env, RagStats));
    exports.Set("ragClear", Napi::Function::New(env, RagClear));
    exports.Set("ragCancel", Napi::Function::New(env, RagCancel));
    exports.Set("ragDestroySession", Napi::Function::New(env, RagDestroySession));
    return exports;
}

}  // namespace

NODE_API_MODULE(runanywhere_native, Init)
