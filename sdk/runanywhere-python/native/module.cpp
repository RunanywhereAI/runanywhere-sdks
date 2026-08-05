// module.cpp — RunAnywhere Python pybind11 extension (_core).
//
// Binds the rac_* C ABI (reusing the Win32 platform adapter proven by the M0
// harness) for on-device inference in Python. This is the exact behavioral
// port of the Electron N-API addon (addon.cpp): same globals, same handle maps,
// same shutdown semantics, same secure store — only translated from Node-API to
// pybind11, and with snake_case names.
//
// Streaming (generate / generate_vlm) holds a Python callable and runs the
// blocking rac_*_generate_stream on the CALLING thread with the GIL released;
// the C token callback re-acquires the GIL to invoke the callback. All other
// blocking rac calls release the GIL only around the C call, then build the
// numpy / str / tuple results with the GIL held.
//
// Modalities: LLM, VLM, embeddings (ONNX), STT + TTS (sherpa), VAD (built-in),
// diarization + segmentation (ONNX), voice-agent file-PCM turns, and (when
// RAC_HAVE_BACKEND_COREML) diffusion.

#include <pybind11/pybind11.h>
#include <pybind11/numpy.h>
#include <pybind11/stl.h>

#include <atomic>
#include <cctype>
#include <condition_variable>
#include <cstdlib>
#include <cstring>
#include <exception>
#include <functional>
#include <mutex>
#include <optional>
#include <string>
#include <unordered_map>
#include <vector>

#include "win32_platform_adapter.h"

#include "rac/backends/rac_llm_llamacpp.h"
#include "rac/core/rac_core.h"
#include "rac/core/rac_logger.h"
#include "rac/core/rac_types.h"
#include "rac/features/llm/rac_llm_component.h"
#include "rac/features/vlm/rac_vlm_component.h"
#include "rac/features/vlm/rac_vlm_types.h"
#include "rac/features/embeddings/rac_embeddings_service.h"
#include "rac/features/embeddings/rac_embeddings_types.h"
#include "rac/plugin/rac_plugin_entry_onnx.h"
#include "rac/plugin/rac_plugin_entry_sherpa.h"
#include "rac/features/stt/rac_stt_component.h"
#include "rac/features/stt/rac_stt_types.h"
#include "rac/features/tts/rac_tts_component.h"
#include "rac/features/tts/rac_tts_types.h"
#include "rac/features/vad/rac_vad_component.h"
#include "rac/features/vad/rac_vad_types.h"
#include "rac/features/diarization/rac_diarization_service.h"
#include "rac/features/diarization/rac_diarization_types.h"
#include "rac/features/segmentation/rac_segmentation_service.h"
#include "rac/features/segmentation/rac_segmentation_types.h"
#include "rac/features/voice_agent/rac_voice_agent.h"
#if defined(RAC_HAVE_BACKEND_COREML)
#include "rac/features/diffusion/rac_diffusion_service.h"
#include "rac/features/diffusion/rac_diffusion_types.h"
#endif
#include "rac/infrastructure/model_management/rac_model_paths.h"
// Control plane (telemetry + auth). Compiled when the protobuf runtime is present
// (RAC_PY_CONTROL_PLANE, set by native/CMakeLists.txt) since the two-phase init is
// proto-driven. HTTP goes through a Python urllib-backed transport we register —
// no libcurl / no third-party client, per this SDK's stdlib-HTTP rule; this mirrors
// how Swift (URLSession) and Kotlin (OkHttp) supply their own transport to commons.
#ifdef RAC_PY_CONTROL_PLANE
#include "rac/core/rac_sdk_state.h"
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
// Model registry (RAG resolves embedding/LLM model ids -> local_path via the
// global registry) + the proto-byte RAG session ABI + its proto-buffer helpers.
#include "rac/core/rac_error.h"
#include "rac/foundation/rac_proto_buffer.h"
#include "rac/infrastructure/model_management/rac_model_registry.h"
#include "rac/infrastructure/model_management/rac_model_types.h"
#ifdef RAC_HAVE_BACKEND_RAG
#include "rac/features/rag/rac_rag.h"
#endif

namespace py = pybind11;

// Internal (non-proto) embeddings service factory — its header lives under
// commons/src/, not include/, so re-declare the prototype here. The module
// static-links rac_commons, so the symbol resolves at link time.
namespace rac {
namespace embeddings {
rac_result_t create_service(const char* model_id, const char* config_json, rac_handle_t* out_handle);
}  // namespace embeddings
}  // namespace rac

// The POSIX adapter fill symbol (its .cpp is authored per-platform). The Win32
// fill is declared in win32_platform_adapter.h; declare the POSIX counterpart
// here, guarded so the Windows build doesn't reference it.
#ifndef _WIN32
extern "C" void rac_python_fill_posix_adapter(rac_platform_adapter_t* out, const char* secure_dir);
#endif

// Optional engine backends. `native/CMakeLists.txt` links any present `rac_backend_<x>`
// target and defines the matching `RAC_HAVE_BACKEND_<X>`; `rac_backend_<x>_register()` is the
// single entry every RunAnywhere SDK invokes. Declared here (guarded) so the wrapper compiles
// with any subset of backends and a new one (QHexRT on Windows-on-Snapdragon, MLX, ...) drops
// in via a build flag with no wrapper-logic changes. llamacpp/onnx/sherpa keep their existing
// commons headers above; these have no public commons header, so declare them directly.
extern "C" {
#ifdef RAC_HAVE_BACKEND_QHEXRT
rac_result_t rac_backend_qhexrt_register(void);  // Qualcomm Hexagon NPU (Snapdragon)
#endif
#ifdef RAC_HAVE_BACKEND_MLX
rac_result_t rac_backend_mlx_register(void);  // Apple MLX
#endif
#ifdef RAC_HAVE_BACKEND_CLOUD
rac_result_t rac_backend_cloud_register(void);  // Cloud STT provider
#endif
}

#if defined(RAC_HAVE_BACKEND_COREML)
// CoreML has no rac_backend_coreml_register() — it registers via the unified
// plugin entry (see engines/coreml/rac_static_register_coreml.cpp).
#include "rac/plugin/rac_plugin_entry.h"
#include "rac/plugin/rac_plugin_entry_coreml.h"
#endif

namespace {

// The adapter struct is caller-owned and must outlive rac_shutdown().
rac_platform_adapter_t g_adapter;
std::atomic<bool> g_initialized{false};

#ifdef RAC_PY_CONTROL_PLANE
// Owns the telemetry manager for the process lifetime so the terminal flush in
// rac_shutdown() can deliver through our HTTP callback before teardown. Guarded
// by g_handles_mutex on create/destroy.
rac_telemetry_manager_t* g_telemetry_manager = nullptr;

// The Python urllib poster backing the registered HTTP transport. Held by value;
// its refcount is touched only under the GIL. Set once at control-plane bring-up.
py::object g_http_poster;
#endif

// Handles are exposed to Python as small integer ids. Each component family
// uses a distinct rac_*_destroy call, so they live in separate maps.
std::mutex g_handles_mutex;
std::unordered_map<int32_t, rac_handle_t> g_llm_handles;
std::unordered_map<int32_t, rac_handle_t> g_vlm_handles;
std::unordered_map<int32_t, rac_handle_t> g_embed_handles;
std::unordered_map<int32_t, rac_handle_t> g_stt_handles;
std::unordered_map<int32_t, rac_handle_t> g_tts_handles;
std::unordered_map<int32_t, rac_handle_t> g_vad_handles;
std::unordered_map<int32_t, rac_handle_t> g_diar_handles;
std::unordered_map<int32_t, rac_handle_t> g_seg_handles;
std::unordered_map<int32_t, rac_voice_agent_handle_t> g_voice_handles;
#if defined(RAC_HAVE_BACKEND_COREML)
std::unordered_map<int32_t, rac_handle_t> g_diff_handles;
#endif
#ifdef RAC_HAVE_BACKEND_RAG
std::unordered_map<int32_t, rac_handle_t> g_rag_handles;  // RAG session handles
#endif
int32_t g_next_handle_id = 1;

rac_handle_t handle_for(const std::unordered_map<int32_t, rac_handle_t>& map, int32_t id) {
    std::lock_guard<std::mutex> lock(g_handles_mutex);
    auto it = map.find(id);
    return (it == map.end()) ? nullptr : it->second;
}

// Register a live handle under a fresh monotonic id and return the id.
int32_t register_handle(std::unordered_map<int32_t, rac_handle_t>& map, rac_handle_t h) {
    std::lock_guard<std::mutex> lock(g_handles_mutex);
    int32_t hid = g_next_handle_id++;
    map[hid] = h;
    return hid;
}

// Pop a handle out of its map (returns nullptr if the id is unknown).
rac_handle_t take_handle(std::unordered_map<int32_t, rac_handle_t>& map, int32_t id) {
    std::lock_guard<std::mutex> lock(g_handles_mutex);
    auto it = map.find(id);
    if (it == map.end()) return nullptr;
    rac_handle_t h = it->second;
    map.erase(it);
    return h;
}

// =============================================================================
// In-flight operation tracking — prevents destroy-during-call use-after-free.
//
// A blocking rac_* call (generate/generate_vlm/transcribe/synthesize/embed/rag_*)
// runs with the GIL released, often on a worker thread (streaming) or an executor
// thread (async twins), while another thread may call unload_*()/shutdown(). Without
// serialization, destroy could free the component mid-call. We mark a handle busy for
// the duration of every blocking op (keyed by the same globally-unique integer id) and
// make unload_*()/shutdown() WAIT for the handle to go idle before destroying it.
// =============================================================================
std::condition_variable g_inflight_cv;
std::unordered_map<int32_t, int> g_inflight;  // handle id -> active blocking-op count

// Look up a handle AND atomically mark it in-flight, so a concurrent unload cannot slip
// between the lookup and the blocking call. Returns nullptr (and marks nothing) if unknown.
rac_handle_t begin_op(const std::unordered_map<int32_t, rac_handle_t>& map, int32_t id) {
    std::lock_guard<std::mutex> lock(g_handles_mutex);
    auto it = map.find(id);
    if (it == map.end()) return nullptr;
    ++g_inflight[id];
    return it->second;
}

// Clear one in-flight mark and wake any unload/shutdown waiter.
void end_op(int32_t id) {
    {
        std::lock_guard<std::mutex> lock(g_handles_mutex);
        auto it = g_inflight.find(id);
        if (it != g_inflight.end() && --it->second <= 0) g_inflight.erase(it);
    }
    g_inflight_cv.notify_all();
}

// RAII: end_op on scope exit — covers the throwing finish_stream / raise_rac_error paths.
struct OpScope {
    int32_t id;
    explicit OpScope(int32_t i) : id(i) {}
    ~OpScope() { end_op(id); }
    OpScope(const OpScope&) = delete;
    OpScope& operator=(const OpScope&) = delete;
};

// Wait until handle `id` is idle, then remove and return it from `map` (nullptr if unknown).
// The CALLER MUST release the GIL first: a streaming worker's token callback needs the GIL to
// drive the native loop to completion so the in-flight count can drain. Generation is bounded
// (max_tokens) and sync/async stream teardown stops the worker, so the wait is bounded in
// normal use; a caller that abandons a paused stream without closing it is the only way to
// block here, which is a caller-side leak, not a hang we can safely pre-empt.
rac_handle_t take_handle_when_idle(std::unordered_map<int32_t, rac_handle_t>& map, int32_t id) {
    std::unique_lock<std::mutex> lock(g_handles_mutex);
    g_inflight_cv.wait(lock, [&] {
        auto it = g_inflight.find(id);
        return it == g_inflight.end() || it->second == 0;
    });
    auto it = map.find(id);
    if (it == map.end()) return nullptr;
    rac_handle_t h = it->second;
    map.erase(it);
    return h;
}

// Voice-agent handles are a distinct opaque pointer type (not rac_handle_t).
int32_t register_voice_handle(rac_voice_agent_handle_t h) {
    std::lock_guard<std::mutex> lock(g_handles_mutex);
    int32_t hid = g_next_handle_id++;
    g_voice_handles[hid] = h;
    return hid;
}

rac_voice_agent_handle_t begin_voice_op(int32_t id) {
    std::lock_guard<std::mutex> lock(g_handles_mutex);
    auto it = g_voice_handles.find(id);
    if (it == g_voice_handles.end()) return nullptr;
    ++g_inflight[id];
    return it->second;
}

rac_voice_agent_handle_t take_voice_handle_when_idle(int32_t id) {
    std::unique_lock<std::mutex> lock(g_handles_mutex);
    g_inflight_cv.wait(lock, [&] {
        auto it = g_inflight.find(id);
        return it == g_inflight.end() || it->second == 0;
    });
    auto it = g_voice_handles.find(id);
    if (it == g_voice_handles.end()) return nullptr;
    rac_voice_agent_handle_t h = it->second;
    g_voice_handles.erase(it);
    return h;
}

// =============================================================================
// Error mapping
// =============================================================================
// Raise a Python SDKException from a negative rac_result_t by delegating to
// runanywhere.errors.raise_for_rac. If that module isn't importable (e.g. the
// package is only half-installed), fall back to a std::runtime_error carrying
// the numeric code and any context string.
[[noreturn]] void raise_rac_error(rac_result_t code, const std::string& context) {
    try {
        auto errors = py::module_::import("runanywhere.errors");
        // Forward the context (op label or streaming error detail) as the
        // SDKException message so the typed exception carries the specifics.
        if (context.empty())
            errors.attr("raise_for_rac")(static_cast<int>(code));
        else
            errors.attr("raise_for_rac")(static_cast<int>(code), context);
        // raise_for_rac always raises for a negative code; if it somehow returns
        // (non-error code passed), throw a generic Python exception so the caller
        // still fails loudly rather than silently continuing.
        throw py::value_error(context.empty()
                                  ? ("rac error " + std::to_string(code))
                                  : (context + ": " + std::to_string(code)));
    } catch (py::error_already_set&) {
        throw;  // the Python SDKException raised by raise_for_rac
    } catch (const std::exception&) {
        std::string msg = context.empty() ? ("rac error " + std::to_string(code))
                                           : (context + " failed: " + std::to_string(code));
        throw std::runtime_error(msg);
    }
}

// Map RUNANYWHERE_LOG_LEVEL (trace/debug/info/warning/error/fatal) to a rac level.
// Default WARNING so the library is quiet by default: the commons logger otherwise
// defaults to INFO and forwards every message to stderr on each call.
rac_log_level_t py_log_threshold() {
    const char* env = std::getenv("RUNANYWHERE_LOG_LEVEL");
    if (!env) return RAC_LOG_WARNING;
    std::string s(env);
    for (char& c : s) c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
    if (s == "trace") return RAC_LOG_TRACE;
    if (s == "debug") return RAC_LOG_DEBUG;
    if (s == "info") return RAC_LOG_INFO;
    if (s == "error") return RAC_LOG_ERROR;
    if (s == "fatal") return RAC_LOG_FATAL;
    return RAC_LOG_WARNING;  // "warning"/"warn"/unknown
}

// =============================================================================
// initialize(secure_dir, base_dir=None)
// =============================================================================
void initialize(const std::string& secure_dir, std::optional<std::string> base_dir) {
    if (g_initialized.load()) return;
    std::string secure = secure_dir;
    std::string base = base_dir.has_value() ? *base_dir : secure;

#ifdef _WIN32
    rac_python_fill_win32_adapter(&g_adapter, secure.c_str());
#else
    rac_python_fill_posix_adapter(&g_adapter, secure.c_str());
#endif

    rac_config_t cfg;
    std::memset(&cfg, 0, sizeof(cfg));
    cfg.platform_adapter = &g_adapter;
    cfg.log_level = RAC_LOG_WARNING;
    cfg.log_tag = "python";

    rac_model_paths_set_base_dir(base.c_str());

    // Quiet the commons logger by default (it defaults to INFO and forwards every message
    // to stderr, flooding a Python caller on each load/generate; cfg.log_level does not
    // lower the logger's own min level). Set it BEFORE rac_init so init-time logs (registry
    // setup, etc.) are gated too, and again after in case rac_init resets it. Env-overridable
    // via RUNANYWHERE_LOG_LEVEL.
    rac_log_level_t log_min = py_log_threshold();
    rac_logger_set_min_level(log_min);

    rac_result_t rc = rac_init(&cfg);
    if (rc != RAC_SUCCESS) raise_rac_error(rc, "rac_init");

    rac_logger_set_min_level(log_min);

    // Backend/plugin registration is process-global and persists across
    // rac_shutdown(), so register exactly once — re-registering after a
    // shutdown+re-init would fail (already-registered), which is why
    // initialize() must stay safe to call again after shutdown().
    static bool backends_registered = false;
    if (!backends_registered) {
        // Register whichever engine backends this build linked (each gated by the
        // RAC_HAVE_BACKEND_<X> define native/CMakeLists.txt emits for a present
        // rac_backend_<x> target). Selection among registered engines is by the C plugin
        // registry's priority (qhexrt=150 > mlx=110 > llamacpp=100 > sherpa=90 >
        // onnx/cloud=50), so a loaded model auto-routes to the best available engine and
        // adding a backend needs NO facade changes — just link it + one guarded call here.
#ifdef RAC_HAVE_BACKEND_LLAMACPP
        // LLM/VLM engine — treated as required when linked: a failure here is fatal.
        rc = rac_backend_llamacpp_register();
        if (rc != RAC_SUCCESS) {
            rac_shutdown();
            raise_rac_error(rc, "rac_backend_llamacpp_register");
        }
#endif
#ifdef RAC_HAVE_BACKEND_ONNX
        rac_backend_onnx_register();  // embeddings (optional; failure just = unavailable)
#endif
#ifdef RAC_HAVE_BACKEND_SHERPA
        rac_backend_sherpa_register();  // STT / TTS (optional)
#endif
#ifdef RAC_HAVE_BACKEND_QHEXRT
        rac_backend_qhexrt_register();  // Hexagon NPU (Snapdragon; incl. Windows-on-Snapdragon)
#endif
#ifdef RAC_HAVE_BACKEND_MLX
        rac_backend_mlx_register();  // Apple MLX (Apple Silicon)
#endif
#if defined(RAC_HAVE_BACKEND_COREML)
        // Unified plugin entry (no rac_backend_coreml_register symbol).
        (void)rac_plugin_register(rac_plugin_entry_coreml());
#endif
#ifdef RAC_HAVE_BACKEND_CLOUD
        rac_backend_cloud_register();  // cloud STT provider fallback
#endif
#ifdef RAC_HAVE_BACKEND_RAG
        // RAG pipeline (also registers the ONNX embeddings provider it depends
        // on if present). Optional: a failure here just leaves RAG unavailable.
        rac_backend_rag_register();
#endif
        backends_registered = true;
    }
    g_initialized.store(true);
}

#ifdef RAC_PY_CONTROL_PLANE
// =============================================================================
// Control plane: telemetry + auth. Ports rcli's bootstrap (sdk/runanywhere-cli/
// src/bootstrap.cpp: initialize_sdk_metadata + initialize_telemetry_auth), but
// registers a Python urllib-backed HTTP transport instead of commons' libcurl one
// (no third-party client, per this SDK's stdlib-HTTP rule). Auth, model
// assignments, and telemetry all POST through rac_http_client over that transport.
// Phase-1/2 proto requests are built in Python (runanywhere/_proto/sdk_init_pb2)
// and handed in as serialized bytes.
// =============================================================================

// Malloc a NUL-terminated copy for rac_http_response_t fields (freed by
// rac_http_response_free with free(); the module shares commons' CRT heap).
char* http_dup(const std::string& s) {
    char* p = static_cast<char*>(std::malloc(s.size() + 1));
    if (!p) return nullptr;
    std::memcpy(p, s.c_str(), s.size() + 1);
    return p;
}

// rac_http_transport_ops_t::request_send — the one HTTP primitive commons routes
// every request through. Marshals to the Python urllib poster:
//   poster(method, url, [(k,v)...], body: bytes, timeout_ms) ->
//       (status: int, [(k,v)...], body: bytes)  |  None on a network/connect error
// Per the transport contract, ANY HTTP response (incl. 4xx/5xx) is RAC_SUCCESS with
// out->status set; only connect/DNS/TLS/timeout failures return an error code.
rac_result_t py_http_request_send(void* /*ud*/, const rac_http_request_t* req,
                                  rac_http_response_t* out) {
    std::memset(out, 0, sizeof(*out));
    py::gil_scoped_acquire gil;
    if (!g_http_poster || g_http_poster.is_none()) return RAC_ERROR_FEATURE_NOT_AVAILABLE;
    try {
        py::list headers;
        for (size_t i = 0; i < req->header_count; ++i) {
            headers.append(py::make_tuple(req->headers[i].name ? req->headers[i].name : "",
                                          req->headers[i].value ? req->headers[i].value : ""));
        }
        py::bytes body(reinterpret_cast<const char*>(req->body_bytes ? req->body_bytes
                                                                     : (const uint8_t*)""),
                       req->body_len);
        py::object r = g_http_poster(std::string(req->method ? req->method : "GET"),
                                     std::string(req->url ? req->url : ""), headers, body,
                                     req->timeout_ms);
        if (r.is_none()) return RAC_ERROR_NETWORK_ERROR;  // connect/DNS/TLS/timeout
        py::tuple t = r.cast<py::tuple>();
        out->status = t[0].cast<int32_t>();
        std::string rb = t[2].cast<py::bytes>();
        if (!rb.empty()) {
            out->body_bytes = reinterpret_cast<uint8_t*>(http_dup(rb));
            out->body_len = rb.size();
        }
        py::list rh = t[1].cast<py::list>();
        size_t hc = rh.size();
        if (hc) {
            out->headers = static_cast<rac_http_header_kv_t*>(
                std::malloc(hc * sizeof(rac_http_header_kv_t)));
            out->header_count = hc;
            for (size_t i = 0; i < hc; ++i) {
                py::tuple kv = rh[i].cast<py::tuple>();
                out->headers[i].name = http_dup(kv[0].cast<std::string>());
                out->headers[i].value = http_dup(kv[1].cast<std::string>());
            }
        }
        return RAC_SUCCESS;
    } catch (...) {
        return RAC_ERROR_INTERNAL;
    }
}

// Static ops table — must outlive the registration (commons borrows the pointer).
rac_http_transport_ops_t g_py_transport_ops = {py_http_request_send, nullptr, nullptr, nullptr,
                                               nullptr};

// Delivers a queued telemetry batch over the registered HTTP transport. Wired via
// rac_telemetry_manager_set_http_callback (user_data = the manager); reports the
// outcome back through rac_telemetry_manager_http_complete. Runs on commons'
// telemetry thread — pure C++, never touches Python state or the GIL.
void py_telemetry_http_callback(void* user_data, const char* endpoint, const char* json_body,
                                size_t json_length, rac_bool_t requires_auth) {
    auto* manager = static_cast<rac_telemetry_manager_t*>(user_data);
    const char* base_url = rac_state_get_base_url();
    if (base_url == nullptr || base_url[0] == '\0' ||
        rac_http_transport_is_registered() != RAC_TRUE) {
        if (manager) rac_telemetry_manager_http_complete(manager, RAC_FALSE, nullptr,
                                                         "telemetry transport unavailable");
        return;
    }

    char url[2048] = {};
    if (rac_build_url(base_url, endpoint, url, sizeof(url)) < 0) {
        if (manager) rac_telemetry_manager_http_complete(manager, RAC_FALSE, nullptr,
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
        if (manager) rac_telemetry_manager_http_complete(manager, RAC_FALSE, nullptr,
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

// The persistent per-device id commons mints (36-char UUID). Callers pass this
// as SdkInitPhase1Request.device_id and the telemetry manager device id.
std::string device_persistent_id() {
    char device_id[RAC_DEVICE_ID_BUFFER_MIN_SIZE] = {};
    if (rac_device_get_or_create_persistent_id(device_id, sizeof(device_id)) != RAC_SUCCESS) {
        return {};
    }
    return device_id;
}

// The baked staging backend URL used by keyless DEVELOPMENT builds; empty when
// none is configured. Mirrors rcli's dev base-URL fallback.
std::string dev_staging_base_url() {
    const char* baked = rac_dev_config_get_staging_base_url();
    if (baked && rac_dev_config_is_usable_http_url(baked)) return baked;
    return {};
}

// Run the full desktop control-plane bring-up: register the libcurl transport,
// seed runtime state + client info, create the telemetry sink, then drive the
// canonical two-phase init. `environment` is a rac_environment_t (0=dev, 2=prod).
// `phase1_bytes` / `phase2_bytes` are serialized SdkInit{Phase1,Phase2}Request.
// Returns the serialized SdkInitResult from phase 2 (empty on a phase failure).
// Best-effort: HTTP/auth failures are non-fatal (the SDK stays usable offline),
// matching commons' Phase-2 contract.
py::bytes configure_control_plane(py::function http_poster, int32_t environment,
                                  const std::string& api_key, const std::string& base_url,
                                  const std::string& device_id, const std::string& platform,
                                  const std::string& sdk_version, const std::string& sdk_binding,
                                  const std::string& app_identifier, const std::string& app_name,
                                  const std::string& app_version, const std::string& phase1_bytes,
                                  const std::string& phase2_bytes) {
    if (!g_initialized.load()) throw std::runtime_error("not initialized");
    const auto env = static_cast<rac_environment_t>(environment);

    // Install the urllib poster + register our transport before any HTTP runs.
    g_http_poster = http_poster;
    rac_http_transport_register(&g_py_transport_ops, nullptr);

    // Runtime state first (the auth/device/telemetry paths read env + creds from
    // rac_state), then the copied SDK configuration + client info.
    rac_state_initialize(env, api_key.c_str(), base_url.c_str(), device_id.c_str());

    rac_sdk_config_t sdk_config = {};
    sdk_config.environment = env;
    sdk_config.api_key = api_key.c_str();
    sdk_config.base_url = base_url.c_str();
    sdk_config.device_id = device_id.c_str();
    sdk_config.platform = platform.c_str();
    sdk_config.sdk_version = sdk_version.c_str();
    sdk_config.client_info.sdk_binding = sdk_binding.c_str();
    sdk_config.client_info.app_identifier = app_identifier.c_str();
    sdk_config.client_info.app_name = app_name.c_str();
    sdk_config.client_info.app_version = app_version.c_str();
    rac_sdk_init(&sdk_config);

    // Per-run auth (NULL secure storage: tokens aren't persisted across runs,
    // like rcli). Authentication still runs when Phase 2 expects a key.
    rac_auth_init(nullptr);

    // Create + register the telemetry sink BEFORE Phase 2 so its flush has a
    // sink; delivery runs through py_telemetry_http_callback over libcurl. The
    // terminal batch flushes in rac_shutdown() during teardown.
    {
        std::lock_guard<std::mutex> lock(g_handles_mutex);
        if (!g_telemetry_manager) {
            g_telemetry_manager = rac_telemetry_manager_create(env, device_id.c_str(),
                                                               platform.c_str(),
                                                               sdk_version.c_str());
            if (g_telemetry_manager) {
                rac_telemetry_manager_set_http_callback(g_telemetry_manager,
                                                        py_telemetry_http_callback,
                                                        g_telemetry_manager);
                rac_events_set_telemetry_sink(g_telemetry_manager);
            }
        }
    }

    rac_result_t rc;
    {
        py::gil_scoped_release release;
        rac_proto_buffer_t phase1_out;
        rac_proto_buffer_init(&phase1_out);
        rc = rac_sdk_init_phase1_proto(reinterpret_cast<const uint8_t*>(phase1_bytes.data()),
                                       phase1_bytes.size(), &phase1_out);
        rac_proto_buffer_free(&phase1_out);
    }
    if (rc != RAC_SUCCESS) raise_rac_error(rc, "sdk_init_phase1");

    rac_proto_buffer_t phase2_out;
    rac_proto_buffer_init(&phase2_out);
    {
        py::gil_scoped_release release;
        rc = rac_sdk_init_phase2_proto(reinterpret_cast<const uint8_t*>(phase2_bytes.data()),
                                       phase2_bytes.size(), &phase2_out);
    }
    if (rc != RAC_SUCCESS) {
        rac_proto_buffer_free(&phase2_out);
        raise_rac_error(rc, "sdk_init_phase2");
    }
    py::bytes result(reinterpret_cast<const char*>(phase2_out.data ? phase2_out.data
                                                                    : (const uint8_t*)""),
                     phase2_out.data ? phase2_out.size : 0);
    rac_proto_buffer_free(&phase2_out);
    return result;
}

// Detach + destroy the telemetry manager. Called from shutdown() after
// rac_shutdown() has flushed the terminal batch through the sink.
void telemetry_teardown() {
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
    // Unregister our transport and drop the Python poster (GIL held here).
    rac_http_transport_register(nullptr, nullptr);
    g_http_poster = py::none();
}
#endif  // RAC_PY_CONTROL_PLANE

// =============================================================================
// Streaming core — shared by LLM generate + VLM generate_vlm.
//
// Both rac_*_generate_stream calls block the calling thread and deliver a char*
// token trio via C callbacks. We run them on the calling (Python) thread with
// the GIL RELEASED; the token callback re-acquires the GIL to invoke the Python
// on_token. If on_token returns Python False -> stop; if it raises -> capture
// the exception and stop, rethrowing after the stream returns.
// =============================================================================
struct StreamCtx {
    py::function on_token;
    std::exception_ptr py_exc;  // set if the Python callback raised
    rac_result_t error_code = RAC_SUCCESS;
    std::string error_msg;
};

rac_bool_t stream_token_cb(const char* token, void* ud) {
    auto* ctx = static_cast<StreamCtx*>(ud);
    std::string tok = token ? token : "";  // copy out — the buffer is transient
    py::gil_scoped_acquire gil;
    try {
        py::object ret = ctx->on_token(tok);
        // A callback that explicitly returns False requests an early stop.
        if (py::isinstance<py::bool_>(ret) && !ret.cast<bool>()) {
            return RAC_FALSE;
        }
        return RAC_TRUE;
    } catch (py::error_already_set&) {
        ctx->py_exc = std::current_exception();  // rethrow on the main thread
        return RAC_FALSE;
    } catch (...) {
        ctx->py_exc = std::current_exception();
        return RAC_FALSE;
    }
}

void stream_error_cb(rac_result_t code, const char* msg, void* ud) {
    auto* ctx = static_cast<StreamCtx*>(ud);
    ctx->error_code = code;
    ctx->error_msg = msg ? msg : "generation error";
}

void stream_llm_complete_cb(const rac_llm_result_t*, void* ud) {
    static_cast<StreamCtx*>(ud)->error_code = RAC_SUCCESS;
}

void stream_vlm_complete_cb(const rac_vlm_result_t*, void* ud) {
    static_cast<StreamCtx*>(ud)->error_code = RAC_SUCCESS;
}

// After a streaming run returns (GIL re-held), surface whatever went wrong:
// a captured Python exception takes precedence, then a rac error.
void finish_stream(StreamCtx& ctx, rac_result_t rc, const char* what) {
    if (ctx.py_exc) std::rethrow_exception(ctx.py_exc);
    if (rc != RAC_SUCCESS && ctx.error_code == RAC_SUCCESS) ctx.error_code = rc;
    // Always surface a typed SDKException (uniform with non-streaming failures);
    // pass the callback-supplied detail through as the message when present.
    if (ctx.error_code != RAC_SUCCESS)
        raise_rac_error(ctx.error_code, ctx.error_msg.empty() ? what : ctx.error_msg);
}

// =============================================================================
// LLM: load_model / generate / unload_model
// =============================================================================
int32_t load_model(const std::string& path, std::optional<std::string> id,
                   std::optional<std::string> name) {
    if (!g_initialized.load()) throw std::runtime_error("not initialized");
    std::string model_id = id.has_value() ? *id : path;
    std::string model_name = name.has_value() ? *name : model_id;

    rac_handle_t h = nullptr;
    rac_result_t rc;
    {
        py::gil_scoped_release release;
        rc = rac_llm_component_create(&h);
    }
    if (rc != RAC_SUCCESS) raise_rac_error(rc, "llm_component_create");
    {
        py::gil_scoped_release release;
        rc = rac_llm_component_load_model(h, path.c_str(), model_id.c_str(), model_name.c_str());
    }
    if (rc != RAC_SUCCESS) {
        rac_llm_component_destroy(h);
        raise_rac_error(rc, "load_model");
    }
    return register_handle(g_llm_handles, h);
}

void generate(int32_t handle, const std::string& prompt, py::function on_token,
              std::optional<int32_t> max_tokens, std::optional<float> temperature,
              std::optional<float> top_p, std::optional<int32_t> top_k,
              std::optional<std::string> system_prompt, std::optional<std::string> grammar,
              std::optional<bool> disable_thinking) {
    rac_handle_t h = begin_op(g_llm_handles, handle);
    if (!h) throw std::runtime_error("invalid handle");
    OpScope op(handle);  // keep the handle alive vs a concurrent unload/shutdown

    // Hold the option strings by value so their c_str() stays valid for the
    // whole streaming call.
    std::string sys_str = system_prompt.value_or(std::string());
    std::string gram_str = grammar.value_or(std::string());

    rac_llm_options_t opts = RAC_LLM_OPTIONS_DEFAULT;
    if (max_tokens.has_value()) opts.max_tokens = *max_tokens;
    if (temperature.has_value()) opts.temperature = *temperature;
    if (top_p.has_value()) opts.top_p = *top_p;
    if (top_k.has_value()) opts.top_k = *top_k;
    if (!sys_str.empty()) opts.system_prompt = sys_str.c_str();
    if (!gram_str.empty()) opts.grammar = gram_str.c_str();
    // disable_thinking suppresses the model's <think> phase: commons prepends
    // the model's no-think directive at the prompt level (the Python host-side
    // splitter still strips any tags the engine emits regardless).
    if (disable_thinking.has_value())
        opts.disable_thinking = *disable_thinking ? RAC_TRUE : RAC_FALSE;

    StreamCtx ctx;
    ctx.on_token = std::move(on_token);

    rac_result_t rc;
    {
        py::gil_scoped_release release;
        rc = rac_llm_component_generate_stream(h, prompt.c_str(), &opts, stream_token_cb,
                                               stream_llm_complete_cb, stream_error_cb, &ctx);
    }
    finish_stream(ctx, rc, "generate");
}

void unload_model(int32_t handle) {
    rac_handle_t h;
    {
        py::gil_scoped_release release;  // let an in-flight generate's callback drain
        h = take_handle_when_idle(g_llm_handles, handle);
    }
    if (h) rac_llm_component_destroy(h);
}

void cancel_generate(int32_t handle) {
    // Best-effort: invalid / already-unloaded handles are a no-op so stream teardown
    // can call cancel without racing unload.
    rac_handle_t h = handle_for(g_llm_handles, handle);
    if (!h) return;
    rac_result_t rc = rac_llm_component_cancel(h);
    if (rc != RAC_SUCCESS) raise_rac_error(rc, "cancel_generate");
}

// =============================================================================
// LoRA adapters on a loaded LLM (rac_llm_component_{load,remove,clear}_lora).
// Backend-agnostic dispatch inside commons (llm_module.cpp); LlamaCPP is the only
// engine that currently wires load_lora/remove_lora/clear_lora ops, so a non-LlamaCPP
// resident model surfaces RAC_ERROR_NOT_SUPPORTED here rather than failing to bind.
// The C ABI is write-only (no read-back) — same shape as the Electron addon
// (addon.cpp's g_lora_applied) — so the Python side mirrors the applied set itself
// (see runanywhere/_handles.py's LLMModel).
// =============================================================================
void lora_apply(int32_t handle, const std::string& adapter_path, std::optional<float> scale) {
    rac_handle_t h = begin_op(g_llm_handles, handle);
    if (!h) throw std::runtime_error("invalid handle");
    OpScope op(handle);  // keep the handle alive vs a concurrent unload/shutdown
    rac_result_t rc;
    {
        py::gil_scoped_release release;
        rc = rac_llm_component_load_lora(h, adapter_path.c_str(), scale.value_or(1.0f));
    }
    if (rc != RAC_SUCCESS) raise_rac_error(rc, "lora_apply");
}

void lora_remove(int32_t handle, const std::string& adapter_path) {
    rac_handle_t h = begin_op(g_llm_handles, handle);
    if (!h) throw std::runtime_error("invalid handle");
    OpScope op(handle);  // keep the handle alive vs a concurrent unload/shutdown
    rac_result_t rc;
    {
        py::gil_scoped_release release;
        rc = rac_llm_component_remove_lora(h, adapter_path.c_str());
    }
    if (rc != RAC_SUCCESS) raise_rac_error(rc, "lora_remove");
}

void lora_remove_all(int32_t handle) {
    rac_handle_t h = begin_op(g_llm_handles, handle);
    if (!h) throw std::runtime_error("invalid handle");
    OpScope op(handle);  // keep the handle alive vs a concurrent unload/shutdown
    rac_result_t rc;
    {
        py::gil_scoped_release release;
        rc = rac_llm_component_clear_lora(h);
    }
    if (rc != RAC_SUCCESS) raise_rac_error(rc, "lora_remove_all");
}

// =============================================================================
// VLM: load_vlm_model / generate_vlm / unload_vlm_model
// =============================================================================
int32_t load_vlm_model(const std::string& model_path, const std::string& mmproj_path,
                       std::optional<std::string> id, std::optional<std::string> name) {
    if (!g_initialized.load()) throw std::runtime_error("not initialized");
    std::string model_id = id.has_value() ? *id : model_path;
    std::string model_name = name.has_value() ? *name : model_id;

    rac_handle_t h = nullptr;
    rac_result_t rc;
    {
        py::gil_scoped_release release;
        rc = rac_vlm_component_create(&h);
    }
    if (rc != RAC_SUCCESS) raise_rac_error(rc, "vlm_component_create");
    {
        py::gil_scoped_release release;
        rc = rac_vlm_component_load_model(h, model_path.c_str(), mmproj_path.c_str(),
                                          model_id.c_str(), model_name.c_str());
    }
    if (rc != RAC_SUCCESS) {
        rac_vlm_component_destroy(h);
        raise_rac_error(rc, "vlm load_model");
    }
    return register_handle(g_vlm_handles, h);
}

void generate_vlm(int32_t handle, const std::string& image_path, const std::string& prompt,
                  py::function on_token, std::optional<int32_t> max_tokens,
                  std::optional<float> temperature, std::optional<float> top_p,
                  std::optional<int32_t> top_k, std::optional<std::string> system_prompt) {
    rac_handle_t h = begin_op(g_vlm_handles, handle);
    if (!h) throw std::runtime_error("invalid vlm handle");
    OpScope op(handle);  // keep the handle alive vs a concurrent unload/shutdown

    std::string sys_str = system_prompt.value_or(std::string());

    StreamCtx ctx;
    ctx.on_token = std::move(on_token);

    rac_result_t rc;
    {
        py::gil_scoped_release release;
        rac_vlm_image_t image;
        std::memset(&image, 0, sizeof(image));
        image.format = RAC_VLM_IMAGE_FORMAT_FILE_PATH;
        image.file_path = image_path.c_str();
        // Pass explicit defaults: NULL options leaves the VLM sampler config
        // (top_k / seed / ...) reading uninitialized memory, which can crash.
        rac_vlm_options_t opts = RAC_VLM_OPTIONS_DEFAULT;
        if (max_tokens.has_value()) opts.max_tokens = *max_tokens;
        if (temperature.has_value()) opts.temperature = *temperature;
        if (top_p.has_value()) opts.top_p = *top_p;
        if (top_k.has_value()) opts.top_k = *top_k;
        if (!sys_str.empty()) opts.system_prompt = sys_str.c_str();
        rc = rac_vlm_component_process_stream(h, &image, prompt.c_str(), &opts, stream_token_cb,
                                              stream_vlm_complete_cb, stream_error_cb, &ctx);
    }
    finish_stream(ctx, rc, "generate_vlm");
}

void cancel_generate_vlm(int32_t handle) {
    rac_handle_t h = handle_for(g_vlm_handles, handle);
    if (!h) return;
    rac_result_t rc = rac_vlm_component_cancel(h);
    if (rc != RAC_SUCCESS) raise_rac_error(rc, "cancel_generate_vlm");
}

void unload_vlm_model(int32_t handle) {
    rac_handle_t h;
    {
        py::gil_scoped_release release;
        h = take_handle_when_idle(g_vlm_handles, handle);
    }
    if (h) rac_vlm_component_destroy(h);
}

// =============================================================================
// Embeddings: load_embedding_model / embed / unload_embedding_model  (ONNX)
// =============================================================================
int32_t load_embedding_model(const std::string& path) {
    if (!g_initialized.load()) throw std::runtime_error("not initialized");
    rac_handle_t h = nullptr;
    rac_result_t rc;
    {
        py::gil_scoped_release release;
        rc = rac::embeddings::create_service(path.c_str(), nullptr, &h);
    }
    if (rc != RAC_SUCCESS) raise_rac_error(rc, "embeddings create_service");
    return register_handle(g_embed_handles, h);
}

py::array_t<float> embed(int32_t handle, const std::string& text) {
    rac_handle_t h = begin_op(g_embed_handles, handle);
    if (!h) throw std::runtime_error("invalid embedding handle");
    OpScope op(handle);  // keep the handle alive vs a concurrent unload/shutdown

    rac_embeddings_result_t result;
    std::memset(&result, 0, sizeof(result));
    rac_result_t rc;
    {
        py::gil_scoped_release release;
        rc = rac_embeddings_embed(h, text.c_str(), nullptr, &result);
    }
    if (rc != RAC_SUCCESS) raise_rac_error(rc, "embed");
    if (result.num_embeddings == 0 || result.embeddings == nullptr ||
        result.embeddings[0].data == nullptr) {
        rac_embeddings_result_free(&result);
        throw std::runtime_error("no embedding produced");
    }
    size_t dim = result.embeddings[0].dimension;
    py::array_t<float> arr(static_cast<py::ssize_t>(dim));
    std::memcpy(arr.mutable_data(), result.embeddings[0].data, dim * sizeof(float));
    rac_embeddings_result_free(&result);
    return arr;
}


py::list embed_batch(int32_t handle, const std::vector<std::string>& texts) {
    rac_handle_t h = begin_op(g_embed_handles, handle);
    if (!h) throw std::runtime_error("invalid embedding handle");
    OpScope op(handle);

    std::vector<const char*> ptrs;
    ptrs.reserve(texts.size());
    for (const auto& t : texts) ptrs.push_back(t.c_str());

    rac_embeddings_result_t result;
    std::memset(&result, 0, sizeof(result));
    rac_result_t rc;
    {
        py::gil_scoped_release release;
        rc = rac_embeddings_embed_batch(h, ptrs.data(), ptrs.size(), nullptr, &result);
    }
    if (rc != RAC_SUCCESS) raise_rac_error(rc, "embed_batch");

    py::list out;
    for (size_t i = 0; i < result.num_embeddings; ++i) {
        if (!result.embeddings || !result.embeddings[i].data) {
            rac_embeddings_result_free(&result);
            throw std::runtime_error("no embedding produced");
        }
        size_t dim = result.embeddings[i].dimension;
        py::array_t<float> arr(static_cast<py::ssize_t>(dim));
        std::memcpy(arr.mutable_data(), result.embeddings[i].data, dim * sizeof(float));
        out.append(arr);
    }
    rac_embeddings_result_free(&result);
    return out;
}

void unload_embedding_model(int32_t handle) {
    rac_handle_t h;
    {
        py::gil_scoped_release release;
        h = take_handle_when_idle(g_embed_handles, handle);
    }
    if (h) rac_embeddings_destroy(h);
}

// =============================================================================
// Model registry: register_model(id, path, framework, category)
//
// The RAG session ABI carries *model ids* (RAGConfiguration.embedding_model_id
// / llm_model_id) and resolves them to on-disk paths through the GLOBAL model
// registry (rac_get_model -> info->local_path). The Python SDK otherwise loads
// models purely by path and never populates that registry, so create_rag first
// registers each resolved model here. Not RAG-gated — it is generally useful
// and links against core commons only.
// =============================================================================

// Duplicate a std::string into a malloc'd C string owned by the rac_model_info
// (rac_model_info_free uses free()). The module static-links commons so both
// sides share one CRT heap.
char* dup_cstr(const std::string& s) {
    char* p = static_cast<char*>(std::malloc(s.size() + 1));
    if (!p) throw std::bad_alloc();
    std::memcpy(p, s.c_str(), s.size() + 1);
    return p;
}

void register_model(const std::string& model_id, const std::string& local_path, int32_t framework,
                    int32_t category) {
    if (!g_initialized.load()) throw std::runtime_error("not initialized");
    rac_model_registry_handle_t reg = rac_get_model_registry();
    if (!reg) throw std::runtime_error("global model registry unavailable");

    rac_model_info_t* info = rac_model_info_alloc();
    if (!info) throw std::bad_alloc();
    // isDownloaded is derived from local_path being set; the RAG resolver reads
    // info->local_path directly, so a non-empty local_path is what matters.
    info->id = dup_cstr(model_id);
    info->name = dup_cstr(model_id);
    info->local_path = dup_cstr(local_path);
    info->framework = static_cast<rac_inference_framework_t>(framework);
    info->category = static_cast<rac_model_category_t>(category);
    info->source = RAC_MODEL_SOURCE_LOCAL;

    rac_result_t rc;
    {
        py::gil_scoped_release release;
        rc = rac_model_registry_save(reg, info);
    }
    rac_model_info_free(info);  // save deep-copies; free our transient struct
    if (rc != RAC_SUCCESS) raise_rac_error(rc, "register_model");
}


py::dict model_info_to_dict(const rac_model_info_t* info) {
    py::dict d;
    d["id"] = info->id ? info->id : "";
    d["name"] = info->name ? info->name : "";
    d["local_path"] = info->local_path ? info->local_path : "";
    d["framework"] = static_cast<int32_t>(info->framework);
    d["category"] = static_cast<int32_t>(info->category);
    return d;
}

py::object get_model(const std::string& model_id) {
    if (!g_initialized.load()) throw std::runtime_error("not initialized");
    rac_model_registry_handle_t reg = rac_get_model_registry();
    if (!reg) throw std::runtime_error("global model registry unavailable");
    rac_model_info_t* info = nullptr;
    rac_result_t rc;
    {
        py::gil_scoped_release release;
        rc = rac_model_registry_get(reg, model_id.c_str(), &info);
    }
    if (rc == RAC_ERROR_NOT_FOUND || rc == RAC_ERROR_MODEL_NOT_FOUND) {
        return py::none();
    }
    if (rc != RAC_SUCCESS) raise_rac_error(rc, "get_model");
    py::dict d = model_info_to_dict(info);
    rac_model_info_free(info);
    return d;
}

py::list list_models() {
    if (!g_initialized.load()) throw std::runtime_error("not initialized");
    rac_model_registry_handle_t reg = rac_get_model_registry();
    if (!reg) throw std::runtime_error("global model registry unavailable");
    rac_model_info_t** models = nullptr;
    size_t count = 0;
    rac_result_t rc;
    {
        py::gil_scoped_release release;
        rc = rac_model_registry_get_all(reg, &models, &count);
    }
    if (rc != RAC_SUCCESS) raise_rac_error(rc, "list_models");
    py::list out;
    for (size_t i = 0; i < count; ++i) {
        if (models[i]) out.append(model_info_to_dict(models[i]));
    }
    rac_model_info_array_free(models, count);
    return out;
}

void remove_model(const std::string& model_id) {
    if (!g_initialized.load()) throw std::runtime_error("not initialized");
    rac_model_registry_handle_t reg = rac_get_model_registry();
    if (!reg) throw std::runtime_error("global model registry unavailable");
    rac_result_t rc;
    {
        py::gil_scoped_release release;
        rc = rac_model_registry_remove(reg, model_id.c_str());
    }
    if (rc != RAC_SUCCESS) raise_rac_error(rc, "remove_model");
}

#ifdef RAC_HAVE_BACKEND_RAG
// =============================================================================
// RAG: proto-bytes session ABI (rac_rag_*_proto).
//
// Every call is bytes-in / bytes-out over serialized runanywhere.v1.* messages;
// the Python `runanywhere.rag` facade owns the (de)serialization via the
// generated _pb2 classes. Session handles reuse the integer-id handle machinery
// under a dedicated g_rag_handles map. Guarded by RAC_HAVE_BACKEND_RAG so a
// build without the RAG backend simply omits these bindings (the facade then
// raises a friendly "rebuild with [rag]" hint).
// =============================================================================

// Turn a returned rac_proto_buffer_t into py::bytes, or raise. Prefers the
// buffer's own negative status/message, else the function return code. Frees
// the buffer either way. Must run with the GIL held.
py::bytes finish_proto_out(rac_result_t rc, rac_proto_buffer_t* buf, const char* what) {
    rac_result_t code = (buf->status != RAC_SUCCESS) ? buf->status : rc;
    if (code != RAC_SUCCESS) {
        std::string msg = buf->error_message ? std::string(buf->error_message) : std::string(what);
        rac_proto_buffer_free(buf);
        raise_rac_error(code, msg);
    }
    py::bytes out(reinterpret_cast<const char*>(buf->data), buf->size);
    rac_proto_buffer_free(buf);
    return out;
}

int32_t rag_session_create(const std::string& config_bytes) {
    if (!g_initialized.load()) throw std::runtime_error("not initialized");
    rac_handle_t session = nullptr;
    rac_result_t rc;
    {
        py::gil_scoped_release release;
        rc = rac_rag_session_create_proto(reinterpret_cast<const uint8_t*>(config_bytes.data()),
                                          config_bytes.size(), &session);
    }
    if (rc != RAC_SUCCESS) raise_rac_error(rc, "rag_session_create");
    if (!session) throw std::runtime_error("rag_session_create returned a null session");
    return register_handle(g_rag_handles, session);
}

py::bytes rag_ingest(int32_t handle, const std::string& document_bytes) {
    rac_handle_t h = begin_op(g_rag_handles, handle);
    if (!h) throw std::runtime_error("invalid rag handle");
    OpScope op(handle);  // keep the session alive vs a concurrent destroy/shutdown
    rac_proto_buffer_t out;
    rac_proto_buffer_init(&out);
    rac_result_t rc;
    {
        py::gil_scoped_release release;
        rc = rac_rag_ingest_proto(h, reinterpret_cast<const uint8_t*>(document_bytes.data()),
                                  document_bytes.size(), &out);
    }
    return finish_proto_out(rc, &out, "rag_ingest");
}

py::bytes rag_query(int32_t handle, const std::string& query_bytes) {
    rac_handle_t h = begin_op(g_rag_handles, handle);
    if (!h) throw std::runtime_error("invalid rag handle");
    OpScope op(handle);  // keep the session alive vs a concurrent destroy/shutdown
    rac_proto_buffer_t out;
    rac_proto_buffer_init(&out);
    rac_result_t rc;
    {
        py::gil_scoped_release release;
        rc = rac_rag_query_proto(h, reinterpret_cast<const uint8_t*>(query_bytes.data()),
                                 query_bytes.size(), &out);
    }
    return finish_proto_out(rc, &out, "rag_query");
}

py::bytes rag_search(int32_t handle, const std::string& request_bytes) {
    rac_handle_t h = begin_op(g_rag_handles, handle);
    if (!h) throw std::runtime_error("invalid rag handle");
    OpScope op(handle);  // keep the session alive vs a concurrent destroy/shutdown
    rac_proto_buffer_t out;
    rac_proto_buffer_init(&out);
    rac_result_t rc;
    {
        py::gil_scoped_release release;
        rc = rac_rag_search_proto(h, reinterpret_cast<const uint8_t*>(request_bytes.data()),
                                  request_bytes.size(), &out);
    }
    return finish_proto_out(rc, &out, "rag_search");
}

// Streaming query: each serialized RAGStreamEvent is delivered to on_event(bytes),
// which returns False to stop early. Same GIL discipline as the LLM stream.
struct RagStreamCtx {
    py::function on_event;
    std::exception_ptr py_exc;  // set if the Python callback raised
};

rac_bool_t rag_stream_event_cb(const uint8_t* event_bytes, size_t event_size, void* ud) {
    auto* ctx = static_cast<RagStreamCtx*>(ud);
    py::gil_scoped_acquire gil;
    try {
        py::bytes ev(reinterpret_cast<const char*>(event_bytes), event_size);
        py::object ret = ctx->on_event(ev);
        if (py::isinstance<py::bool_>(ret) && !ret.cast<bool>()) return RAC_FALSE;
        return RAC_TRUE;
    } catch (py::error_already_set&) {
        ctx->py_exc = std::current_exception();
        return RAC_FALSE;
    } catch (...) {
        ctx->py_exc = std::current_exception();
        return RAC_FALSE;
    }
}

void rag_query_stream(int32_t handle, const std::string& query_bytes, py::function on_event) {
    rac_handle_t h = begin_op(g_rag_handles, handle);
    if (!h) throw std::runtime_error("invalid rag handle");
    OpScope op(handle);  // keep the session alive vs a concurrent destroy/shutdown
    RagStreamCtx ctx;
    ctx.on_event = std::move(on_event);
    rac_result_t rc;
    {
        py::gil_scoped_release release;
        rc = rac_rag_query_stream_proto(h, reinterpret_cast<const uint8_t*>(query_bytes.data()),
                                        query_bytes.size(), rag_stream_event_cb, &ctx);
    }
    if (ctx.py_exc) std::rethrow_exception(ctx.py_exc);  // callback raised -> resurface
    if (rc != RAC_SUCCESS) raise_rac_error(rc, "rag_query_stream");
}

void rag_cancel(int32_t handle) {
    // Cancel must reach a session that already holds an in-flight lease (query/stream),
    // so look up without taking another lease — destroy still waits for active ops.
    rac_handle_t h = handle_for(g_rag_handles, handle);
    if (!h) throw std::runtime_error("invalid rag handle");
    rac_result_t rc;
    {
        py::gil_scoped_release release;
        rc = rac_rag_cancel_proto(h);
    }
    if (rc != RAC_SUCCESS) raise_rac_error(rc, "rag_cancel");
}

py::bytes rag_clear(int32_t handle) {
    rac_handle_t h = begin_op(g_rag_handles, handle);
    if (!h) throw std::runtime_error("invalid rag handle");
    OpScope op(handle);  // keep the session alive vs a concurrent destroy/shutdown
    rac_proto_buffer_t out;
    rac_proto_buffer_init(&out);
    rac_result_t rc;
    {
        py::gil_scoped_release release;
        rc = rac_rag_clear_proto(h, &out);
    }
    return finish_proto_out(rc, &out, "rag_clear");
}

py::bytes rag_stats(int32_t handle) {
    rac_handle_t h = begin_op(g_rag_handles, handle);
    if (!h) throw std::runtime_error("invalid rag handle");
    OpScope op(handle);  // keep the session alive vs a concurrent destroy/shutdown
    rac_proto_buffer_t out;
    rac_proto_buffer_init(&out);
    rac_result_t rc;
    {
        py::gil_scoped_release release;
        rc = rac_rag_stats_proto(h, &out);
    }
    return finish_proto_out(rc, &out, "rag_stats");
}

void rag_session_destroy(int32_t handle) {
    rac_handle_t h;
    {
        py::gil_scoped_release release;
        h = take_handle_when_idle(g_rag_handles, handle);
    }
    if (h) rac_rag_session_destroy_proto(h);
}
#endif  // RAC_HAVE_BACKEND_RAG

// =============================================================================
// STT: load_stt_model / transcribe / unload_stt_model   (sherpa)
// =============================================================================
int32_t load_stt_model(const std::string& dir, std::optional<std::string> id,
                        std::optional<std::string> name) {
    if (!g_initialized.load()) throw std::runtime_error("not initialized");
    std::string model_id = id.has_value() ? *id : dir;
    std::string model_name = name.has_value() ? *name : model_id;

    rac_handle_t h = nullptr;
    rac_result_t rc;
    {
        py::gil_scoped_release release;
        rc = rac_stt_component_create(&h);
    }
    if (rc != RAC_SUCCESS) raise_rac_error(rc, "stt_component_create");
    {
        py::gil_scoped_release release;
        rc = rac_stt_component_load_model(h, dir.c_str(), model_id.c_str(), model_name.c_str());
    }
    if (rc != RAC_SUCCESS) {
        rac_stt_component_destroy(h);
        raise_rac_error(rc, "stt load_model");
    }
    return register_handle(g_stt_handles, h);
}

// transcribe(handle, pcm16) -> text. Audio = 16 kHz mono PCM16.
// Accepts any buffer-protocol object (bytes, bytearray, memoryview, numpy uint8
// array), mirroring the Electron addon's "Buffer OR TypedArray" acceptance.
std::string transcribe(int32_t handle, const py::buffer& pcm16) {
    rac_handle_t h = begin_op(g_stt_handles, handle);
    if (!h) throw std::runtime_error("invalid stt handle");
    OpScope op(handle);  // keep the handle alive vs a concurrent unload/shutdown

    // Borrow the raw bytes without copying; the buffer stays alive for the call.
    py::buffer_info info = pcm16.request();
    const uint8_t* pcm_data = reinterpret_cast<const uint8_t*>(info.ptr);
    size_t pcm_len = static_cast<size_t>(info.size) * static_cast<size_t>(info.itemsize);

    rac_stt_result_t result;
    std::memset(&result, 0, sizeof(result));
    rac_result_t rc;
    {
        py::gil_scoped_release release;
        rc = rac_stt_component_transcribe(h, pcm_data, pcm_len, nullptr, &result);
    }
    if (rc != RAC_SUCCESS) raise_rac_error(rc, "transcribe");
    std::string text = result.text ? result.text : "";
    rac_stt_result_free(&result);
    return text;
}

void unload_stt_model(int32_t handle) {
    rac_handle_t h;
    {
        py::gil_scoped_release release;
        h = take_handle_when_idle(g_stt_handles, handle);
    }
    if (h) rac_stt_component_destroy(h);
}

// =============================================================================
// TTS: load_tts_voice / synthesize / unload_tts_voice   (sherpa)
// =============================================================================
int32_t load_tts_voice(const std::string& dir, std::optional<std::string> id,
                        std::optional<std::string> name) {
    if (!g_initialized.load()) throw std::runtime_error("not initialized");
    std::string voice_id = id.has_value() ? *id : dir;
    std::string voice_name = name.has_value() ? *name : voice_id;

    rac_handle_t h = nullptr;
    rac_result_t rc;
    {
        py::gil_scoped_release release;
        rc = rac_tts_component_create(&h);
    }
    if (rc != RAC_SUCCESS) raise_rac_error(rc, "tts_component_create");
    {
        py::gil_scoped_release release;
        rc = rac_tts_component_load_voice(h, dir.c_str(), voice_id.c_str(), voice_name.c_str());
    }
    if (rc != RAC_SUCCESS) {
        rac_tts_component_destroy(h);
        raise_rac_error(rc, "tts load_voice");
    }
    return register_handle(g_tts_handles, h);
}

// synthesize(handle, text) -> (samples float32 ndarray, sample_rate int).
py::tuple synthesize(int32_t handle, const std::string& text) {
    rac_handle_t h = begin_op(g_tts_handles, handle);
    if (!h) throw std::runtime_error("invalid tts handle");
    OpScope op(handle);  // keep the handle alive vs a concurrent unload/shutdown

    rac_tts_result_t result;
    std::memset(&result, 0, sizeof(result));
    rac_result_t rc;
    {
        py::gil_scoped_release release;
        rc = rac_tts_component_synthesize(h, text.c_str(), nullptr, &result);
    }
    if (rc != RAC_SUCCESS) raise_rac_error(rc, "synthesize");

    size_t n = result.audio_size / sizeof(float);  // audio_data is float32 PCM
    py::array_t<float> samples(static_cast<py::ssize_t>(n));
    if (result.audio_data && n) std::memcpy(samples.mutable_data(), result.audio_data, n * sizeof(float));
    int32_t sr = result.sample_rate;
    rac_tts_result_free(&result);
    return py::make_tuple(samples, sr);
}

void unload_tts_voice(int32_t handle) {
    rac_handle_t h;
    {
        py::gil_scoped_release release;
        h = take_handle_when_idle(g_tts_handles, handle);
    }
    if (h) rac_tts_component_destroy(h);
}

// =============================================================================
// Voice activity detection (built-in energy VAD; no model required).
// =============================================================================
int32_t create_vad(std::optional<float> threshold) {
    if (!g_initialized.load()) throw std::runtime_error("not initialized");
    rac_handle_t h = nullptr;
    if (rac_vad_component_create(&h) != RAC_SUCCESS || !h) {
        throw std::runtime_error("vad create failed");
    }
    rac_vad_config_t cfg = RAC_VAD_CONFIG_DEFAULT;
    if (threshold.has_value()) cfg.energy_threshold = *threshold;
    if (rac_vad_component_configure(h, &cfg) != RAC_SUCCESS ||
        rac_vad_component_initialize(h) != RAC_SUCCESS) {
        rac_vad_component_destroy(h);
        throw std::runtime_error("vad configure/initialize failed");
    }
    return register_handle(g_vad_handles, h);
}

// vad_process(handle, float32 ndarray) -> bool (speech in this frame).
bool vad_process(int32_t handle, py::array_t<float, py::array::c_style | py::array::forcecast> samples) {
    rac_handle_t h = handle_for(g_vad_handles, handle);
    if (!h) throw std::runtime_error("invalid vad handle");
    auto buf = samples.request();
    const float* data = static_cast<const float*>(buf.ptr);
    size_t count = static_cast<size_t>(buf.size);
    rac_bool_t is_speech = RAC_FALSE;
    rac_result_t rc = rac_vad_component_process(h, data, count, &is_speech);
    if (rc != RAC_SUCCESS) raise_rac_error(rc, "vad process");
    return is_speech == RAC_TRUE;
}

bool vad_is_active(int32_t handle) {
    rac_handle_t h = handle_for(g_vad_handles, handle);
    if (!h) return false;
    return rac_vad_component_is_speech_active(h) == RAC_TRUE;
}

void vad_set_threshold(int32_t handle, float threshold) {
    rac_handle_t h = handle_for(g_vad_handles, handle);
    if (h) rac_vad_component_set_energy_threshold(h, threshold);
}

void vad_reset(int32_t handle) {
    rac_handle_t h = handle_for(g_vad_handles, handle);
    if (h) rac_vad_component_reset(h);
}


void load_vad_model(int32_t handle, const std::string& model_path,
                    std::optional<std::string> id, std::optional<std::string> name) {
    rac_handle_t h = handle_for(g_vad_handles, handle);
    if (!h) throw std::runtime_error("invalid vad handle");
    std::string mid = id.has_value() ? *id : model_path;
    std::string mname = name.has_value() ? *name : mid;
    rac_result_t rc;
    {
        py::gil_scoped_release release;
        rc = rac_vad_component_load_model(h, model_path.c_str(), mid.c_str(), mname.c_str());
    }
    if (rc != RAC_SUCCESS) raise_rac_error(rc, "load_vad_model");
}

void unload_vad(int32_t handle) {
    rac_handle_t h = take_handle_when_idle(g_vad_handles, handle);
    if (h) rac_vad_component_destroy(h);
}

// =============================================================================
// Speaker diarization: load_diarization_model / diarize / unload_diarization_model.
//
// The rac_diarization_* service ABI is thin (create/initialize/diarize/cleanup/destroy —
// the same shape the Electron addon binds), and offline batch diarize is routed to the
// ONNX Sortformer provider registered by rac_backend_onnx_register() (already called in
// initialize() when RAC_HAVE_BACKEND_ONNX). Bound unconditionally, like embed()/embed_batch()
// above: a build without the ONNX backend registered simply surfaces RAC_ERROR_NOT_SUPPORTED
// at call time rather than failing to bind.
// =============================================================================
int32_t load_diarization_model(const std::string& model_path, std::optional<std::string> id) {
    if (!g_initialized.load()) throw std::runtime_error("not initialized");
    std::string model_id = id.has_value() ? *id : model_path;

    rac_handle_t h = nullptr;
    rac_result_t rc;
    {
        py::gil_scoped_release release;
        rc = rac_diarization_create(model_id.c_str(), &h);
    }
    if (rc != RAC_SUCCESS) raise_rac_error(rc, "diarization_create");
    {
        py::gil_scoped_release release;
        rc = rac_diarization_initialize(h, model_path.c_str());
    }
    if (rc != RAC_SUCCESS) {
        rac_diarization_destroy(h);
        raise_rac_error(rc, "diarization_initialize");
    }
    return register_handle(g_diar_handles, h);
}

// diarize(handle, float32 samples, sample_rate_hz=16000, threshold=None,
//         minimum_duration_ms=None, merge_gap_ms=None) ->
//   {segments: [{start_ms, end_ms, speaker_index, speaker_id}], speaker_count, duration_ms}.
py::dict diarize(int32_t handle,
                 py::array_t<float, py::array::c_style | py::array::forcecast> samples,
                 std::optional<int32_t> sample_rate_hz, std::optional<float> threshold,
                 std::optional<int64_t> minimum_duration_ms, std::optional<int64_t> merge_gap_ms) {
    rac_handle_t h = begin_op(g_diar_handles, handle);
    if (!h) throw std::runtime_error("invalid diarization handle");
    OpScope op(handle);  // keep the handle alive vs a concurrent unload/shutdown

    auto buf = samples.request();
    const float* data = static_cast<const float*>(buf.ptr);
    size_t count = static_cast<size_t>(buf.size);

    rac_diarization_options_t opts = RAC_DIARIZATION_OPTIONS_DEFAULT;
    if (sample_rate_hz.has_value()) opts.sample_rate_hz = *sample_rate_hz;
    if (threshold.has_value()) opts.threshold = *threshold;
    if (minimum_duration_ms.has_value()) opts.minimum_duration_ms = *minimum_duration_ms;
    if (merge_gap_ms.has_value()) opts.merge_gap_ms = *merge_gap_ms;

    rac_diarization_result_t result;
    std::memset(&result, 0, sizeof(result));
    rac_result_t rc;
    {
        py::gil_scoped_release release;
        rc = rac_diarization_diarize(h, data, count, &opts, &result);
    }
    if (rc != RAC_SUCCESS) raise_rac_error(rc, "diarize");

    py::list segments;
    for (size_t i = 0; i < result.segment_count; ++i) {
        py::dict seg;
        seg["start_ms"] = result.segments[i].start_ms;
        seg["end_ms"] = result.segments[i].end_ms;
        seg["speaker_index"] = result.segments[i].speaker_index;
        seg["speaker_id"] = result.segments[i].speaker_id ? result.segments[i].speaker_id : "";
        segments.append(seg);
    }
    py::dict out;
    out["segments"] = segments;
    out["speaker_count"] = result.speaker_count;
    out["duration_ms"] = result.audio_duration_ms;
    rac_diarization_result_free(&result);
    return out;
}

void unload_diarization_model(int32_t handle) {
    rac_handle_t h;
    {
        py::gil_scoped_release release;
        h = take_handle_when_idle(g_diar_handles, handle);
    }
    if (h) {
        rac_diarization_cleanup(h);
        rac_diarization_destroy(h);
    }
}

// =============================================================================
// Semantic segmentation: load_segmentation_model / segment / unload_segmentation_model.
//
// Same create/initialize/segment/cleanup/destroy shape the Electron addon binds as
// loadSegmentationModel / segment / unloadSegmentationModel. Offline batch routes
// through the ONNX segmentation provider registered by rac_backend_onnx_register().
// Bound unconditionally (like diarization): a build without ONNX surfaces
// RAC_ERROR_NOT_SUPPORTED at call time.
// =============================================================================
int32_t load_segmentation_model(const std::string& model_path, std::optional<std::string> id) {
    if (!g_initialized.load()) throw std::runtime_error("not initialized");
    std::string model_id = id.has_value() ? *id : model_path;

    rac_handle_t h = nullptr;
    rac_result_t rc;
    {
        py::gil_scoped_release release;
        rc = rac_segmentation_create(model_id.c_str(), &h);
    }
    if (rc != RAC_SUCCESS) raise_rac_error(rc, "segmentation_create");
    {
        py::gil_scoped_release release;
        rc = rac_segmentation_initialize(h, model_path.c_str());
    }
    if (rc != RAC_SUCCESS) {
        rac_segmentation_destroy(h);
        raise_rac_error(rc, "segmentation_initialize");
    }
    return register_handle(g_seg_handles, h);
}

// segment(handle, data, width, height, pixel_format=1, stride_bytes=0,
//         include_diagnostic_rgba=False) ->
//   {width, height, class_mask: uint16 ndarray, classes: [...], diagnostic_rgba?: bytes}.
py::dict segment(int32_t handle, const py::buffer& data, int32_t width, int32_t height,
                 std::optional<int32_t> pixel_format, std::optional<int64_t> stride_bytes,
                 std::optional<bool> include_diagnostic_rgba) {
    rac_handle_t h = begin_op(g_seg_handles, handle);
    if (!h) throw std::runtime_error("invalid segmentation handle");
    OpScope op(handle);

    py::buffer_info info = data.request();
    const uint8_t* bytes = reinterpret_cast<const uint8_t*>(info.ptr);
    size_t nbytes = static_cast<size_t>(info.size) * static_cast<size_t>(info.itemsize);

    rac_segmentation_image_t image;
    std::memset(&image, 0, sizeof(image));
    image.data = bytes;
    image.data_size = nbytes;
    image.width = static_cast<uint32_t>(width);
    image.height = static_cast<uint32_t>(height);
    image.pixel_format = pixel_format.has_value()
                             ? static_cast<rac_segmentation_pixel_format_t>(*pixel_format)
                             : RAC_SEGMENTATION_PIXEL_FORMAT_RGB8;
    image.stride_bytes = stride_bytes.has_value() ? static_cast<size_t>(*stride_bytes) : 0;

    rac_segmentation_options_t opts = RAC_SEGMENTATION_OPTIONS_DEFAULT;
    if (include_diagnostic_rgba.has_value() && *include_diagnostic_rgba) {
        opts.include_diagnostic_rgba = RAC_TRUE;
    }

    rac_segmentation_result_t result;
    std::memset(&result, 0, sizeof(result));
    rac_result_t rc;
    {
        py::gil_scoped_release release;
        rc = rac_segmentation_segment(h, &image, &opts, &result);
    }
    if (rc != RAC_SUCCESS) raise_rac_error(rc, "segment");

    py::array_t<uint16_t> mask(static_cast<py::ssize_t>(result.class_mask_count));
    if (result.class_mask && result.class_mask_count) {
        std::memcpy(mask.mutable_data(), result.class_mask,
                    result.class_mask_count * sizeof(uint16_t));
    }
    py::list classes;
    for (size_t i = 0; i < result.class_summary_count; ++i) {
        py::dict c;
        c["class_id"] = result.class_summaries[i].class_id;
        c["pixel_count"] = static_cast<uint64_t>(result.class_summaries[i].pixel_count);
        c["fraction"] = result.class_summaries[i].fraction;
        c["label"] = result.class_summaries[i].label ? result.class_summaries[i].label : "";
        classes.append(c);
    }
    py::dict out;
    out["width"] = result.width;
    out["height"] = result.height;
    out["class_mask"] = mask;
    out["classes"] = classes;
    if (result.diagnostic_rgba && result.diagnostic_rgba_size) {
        out["diagnostic_rgba"] =
            py::bytes(reinterpret_cast<const char*>(result.diagnostic_rgba),
                      result.diagnostic_rgba_size);
    }
    rac_segmentation_result_free(&result);
    return out;
}

void unload_segmentation_model(int32_t handle) {
    rac_handle_t h;
    {
        py::gil_scoped_release release;
        h = take_handle_when_idle(g_seg_handles, handle);
    }
    if (h) {
        rac_segmentation_cleanup(h);
        rac_segmentation_destroy(h);
    }
}

// =============================================================================
// Voice agent (file-PCM turn): create / initialize / process_voice_turn / destroy.
//
// Composes STT → LLM → TTS via rac_voice_agent_* (no mic / WebRTC / wake-word).
// process_voice_turn feeds one complete PCM16 utterance and decodes the returned
// VoiceAgentResult proto into a Python dict (key fields only — avoids linking the
// generated C++ protobuf into this module).
// =============================================================================

// Minimal protobuf wire reader for VoiceAgentResult key fields.
static bool pb_read_varint(const uint8_t*& p, const uint8_t* end, uint64_t* out) {
    uint64_t value = 0;
    int shift = 0;
    while (p < end && shift < 64) {
        uint8_t byte = *p++;
        value |= static_cast<uint64_t>(byte & 0x7f) << shift;
        if ((byte & 0x80) == 0) {
            *out = value;
            return true;
        }
        shift += 7;
    }
    return false;
}

static bool pb_skip_field(const uint8_t*& p, const uint8_t* end, uint32_t wire_type) {
    switch (wire_type) {
        case 0: {  // varint
            uint64_t tmp;
            return pb_read_varint(p, end, &tmp);
        }
        case 1:  // 64-bit
            if (static_cast<size_t>(end - p) < 8) return false;
            p += 8;
            return true;
        case 2: {  // length-delimited
            uint64_t len = 0;
            if (!pb_read_varint(p, end, &len)) return false;
            if (static_cast<uint64_t>(end - p) < len) return false;
            p += static_cast<size_t>(len);
            return true;
        }
        case 5:  // 32-bit
            if (static_cast<size_t>(end - p) < 4) return false;
            p += 4;
            return true;
        default:
            return false;
    }
}

static py::dict decode_voice_agent_result(const uint8_t* data, size_t size) {
    py::dict out;
    out["speech_detected"] = false;
    out["transcription"] = py::str("");
    out["assistant_response"] = py::str("");
    out["synthesized_audio"] = py::bytes();
    out["sample_rate_hz"] = 0;
    out["channels"] = 0;
    out["stt_time_ms"] = static_cast<int64_t>(0);
    out["llm_time_ms"] = static_cast<int64_t>(0);
    out["tts_time_ms"] = static_cast<int64_t>(0);
    out["total_time_ms"] = static_cast<int64_t>(0);

    const uint8_t* p = data;
    const uint8_t* end = data + size;
    while (p < end) {
        uint64_t tag = 0;
        if (!pb_read_varint(p, end, &tag)) break;
        uint32_t field = static_cast<uint32_t>(tag >> 3);
        uint32_t wire = static_cast<uint32_t>(tag & 0x7);
        if (wire == 0) {
            uint64_t v = 0;
            if (!pb_read_varint(p, end, &v)) break;
            if (field == 1) out["speech_detected"] = (v != 0);
            else if (field == 7) out["sample_rate_hz"] = static_cast<int32_t>(v);
            else if (field == 8) out["channels"] = static_cast<int32_t>(v);
            else if (field == 12) out["stt_time_ms"] = static_cast<int64_t>(v);
            else if (field == 13) out["llm_time_ms"] = static_cast<int64_t>(v);
            else if (field == 14) out["tts_time_ms"] = static_cast<int64_t>(v);
            else if (field == 15) out["total_time_ms"] = static_cast<int64_t>(v);
        } else if (wire == 2) {
            uint64_t len = 0;
            if (!pb_read_varint(p, end, &len)) break;
            if (static_cast<uint64_t>(end - p) < len) break;
            const char* s = reinterpret_cast<const char*>(p);
            if (field == 2) out["transcription"] = py::str(s, static_cast<size_t>(len));
            else if (field == 3) out["assistant_response"] = py::str(s, static_cast<size_t>(len));
            else if (field == 5) out["synthesized_audio"] = py::bytes(s, static_cast<size_t>(len));
            p += static_cast<size_t>(len);
        } else {
            if (!pb_skip_field(p, end, wire)) break;
        }
    }
    return out;
}

int32_t create_voice_agent() {
    if (!g_initialized.load()) throw std::runtime_error("not initialized");
    rac_voice_agent_handle_t h = nullptr;
    rac_result_t rc;
    {
        py::gil_scoped_release release;
        rc = rac_voice_agent_create_standalone(&h);
    }
    if (rc != RAC_SUCCESS) raise_rac_error(rc, "voice_agent_create");
    if (!h) throw std::runtime_error("voice_agent_create returned null");
    return register_voice_handle(h);
}

void initialize_voice_agent(int32_t handle, const std::string& stt_path, const std::string& llm_path,
                            const std::string& tts_path, std::optional<std::string> stt_id,
                            std::optional<std::string> llm_id, std::optional<std::string> tts_id,
                            std::optional<std::string> stt_name, std::optional<std::string> llm_name,
                            std::optional<std::string> tts_name) {
    rac_voice_agent_handle_t h = begin_voice_op(handle);
    if (!h) throw std::runtime_error("invalid voice agent handle");
    OpScope op(handle);

    std::string stt_model_id = stt_id.has_value() ? *stt_id : stt_path;
    std::string llm_model_id = llm_id.has_value() ? *llm_id : llm_path;
    std::string tts_voice_id = tts_id.has_value() ? *tts_id : tts_path;
    std::string stt_model_name = stt_name.has_value() ? *stt_name : stt_model_id;
    std::string llm_model_name = llm_name.has_value() ? *llm_name : llm_model_id;
    std::string tts_voice_name = tts_name.has_value() ? *tts_name : tts_voice_id;

    rac_voice_agent_config_t config = RAC_VOICE_AGENT_CONFIG_DEFAULT;
    config.stt_config.model_path = stt_path.c_str();
    config.stt_config.model_id = stt_model_id.c_str();
    config.stt_config.model_name = stt_model_name.c_str();
    config.llm_config.model_path = llm_path.c_str();
    config.llm_config.model_id = llm_model_id.c_str();
    config.llm_config.model_name = llm_model_name.c_str();
    config.tts_config.voice_path = tts_path.c_str();
    config.tts_config.voice_id = tts_voice_id.c_str();
    config.tts_config.voice_name = tts_voice_name.c_str();

    rac_result_t rc;
    {
        py::gil_scoped_release release;
        rc = rac_voice_agent_initialize(h, &config);
    }
    if (rc != RAC_SUCCESS) raise_rac_error(rc, "voice_agent_initialize");
}

// process_voice_turn(handle, pcm16) -> dict with transcription / response / audio.
py::dict process_voice_turn(int32_t handle, const py::buffer& pcm16) {
    rac_voice_agent_handle_t h = begin_voice_op(handle);
    if (!h) throw std::runtime_error("invalid voice agent handle");
    OpScope op(handle);

    py::buffer_info info = pcm16.request();
    const void* audio_data = info.ptr;
    size_t audio_size = static_cast<size_t>(info.size) * static_cast<size_t>(info.itemsize);

    rac_proto_buffer_t out;
    rac_proto_buffer_init(&out);
    rac_result_t rc;
    {
        py::gil_scoped_release release;
        rc = rac_voice_agent_process_voice_turn_proto(h, audio_data, audio_size, &out);
    }
    rac_result_t code = (out.status != RAC_SUCCESS) ? out.status : rc;
    if (code != RAC_SUCCESS) {
        std::string msg = out.error_message ? std::string(out.error_message) : "process_voice_turn";
        rac_proto_buffer_free(&out);
        raise_rac_error(code, msg);
    }
    py::dict result = decode_voice_agent_result(out.data, out.size);
    rac_proto_buffer_free(&out);
    return result;
}

void destroy_voice_agent(int32_t handle) {
    rac_voice_agent_handle_t h;
    {
        py::gil_scoped_release release;
        h = take_voice_handle_when_idle(handle);
    }
    if (h) {
        rac_voice_agent_cleanup(h);
        rac_voice_agent_destroy(h);
    }
}

#if defined(RAC_HAVE_BACKEND_COREML)
// =============================================================================
// Diffusion (CoreML): load_diffusion_model / generate_image / unload_diffusion_model.
//
// Compile-gated: the desktop wheels typically link no diffusion backend. When
// rac_backend_coreml is present, these export; otherwise capabilities() reports
// images unavailable via hasattr(core, "load_diffusion_model").
// =============================================================================
int32_t load_diffusion_model(const std::string& model_path, std::optional<std::string> id) {
    if (!g_initialized.load()) throw std::runtime_error("not initialized");
    std::string model_id = id.has_value() ? *id : model_path;

    rac_handle_t h = nullptr;
    rac_result_t rc;
    {
        py::gil_scoped_release release;
        rc = rac_diffusion_create(model_id.c_str(), &h);
    }
    if (rc != RAC_SUCCESS) raise_rac_error(rc, "diffusion_create");
    {
        py::gil_scoped_release release;
        rc = rac_diffusion_initialize(h, model_path.c_str(), nullptr);
    }
    if (rc != RAC_SUCCESS) {
        rac_diffusion_destroy(h);
        raise_rac_error(rc, "diffusion_initialize");
    }
    return register_handle(g_diff_handles, h);
}

py::dict generate_image(int32_t handle, const std::string& prompt,
                        std::optional<std::string> negative_prompt, std::optional<int32_t> width,
                        std::optional<int32_t> height, std::optional<int32_t> steps,
                        std::optional<float> guidance_scale, std::optional<int64_t> seed) {
    rac_handle_t h = begin_op(g_diff_handles, handle);
    if (!h) throw std::runtime_error("invalid diffusion handle");
    OpScope op(handle);

    rac_diffusion_options_t opts = RAC_DIFFUSION_OPTIONS_DEFAULT;
    opts.prompt = prompt.c_str();
    std::string neg;
    if (negative_prompt.has_value()) {
        neg = *negative_prompt;
        opts.negative_prompt = neg.c_str();
    }
    if (width.has_value()) opts.width = *width;
    if (height.has_value()) opts.height = *height;
    if (steps.has_value()) opts.steps = *steps;
    if (guidance_scale.has_value()) opts.guidance_scale = *guidance_scale;
    if (seed.has_value()) opts.seed = *seed;

    rac_diffusion_result_t result;
    std::memset(&result, 0, sizeof(result));
    rac_result_t rc;
    {
        py::gil_scoped_release release;
        rc = rac_diffusion_generate(h, &opts, &result);
    }
    if (rc != RAC_SUCCESS) {
        rac_diffusion_result_free(&result);
        raise_rac_error(rc, "diffusion_generate");
    }

    py::dict out;
    out["width"] = result.width;
    out["height"] = result.height;
    out["seed"] = result.seed_used;
    out["generation_time_ms"] = result.generation_time_ms;
    out["safety_flagged"] = result.safety_flagged == RAC_TRUE;
    if (result.image_data && result.image_size) {
        out["image_data"] =
            py::bytes(reinterpret_cast<const char*>(result.image_data), result.image_size);
    } else {
        out["image_data"] = py::bytes();
    }
    rac_diffusion_result_free(&result);
    return out;
}

void unload_diffusion_model(int32_t handle) {
    rac_handle_t h;
    {
        py::gil_scoped_release release;
        h = take_handle_when_idle(g_diff_handles, handle);
    }
    if (h) {
        rac_diffusion_cleanup(h);
        rac_diffusion_destroy(h);
    }
}
#endif  // RAC_HAVE_BACKEND_COREML

// =============================================================================
// shutdown()
// =============================================================================
void shutdown() {
    if (g_initialized.exchange(false)) {
        // Destroy every still-loaded component and clear the handle maps so no id
        // outlives the runtime — a later unload/use can't touch freed native
        // state, and a re-init starts from a clean slate.
        {
            // Release the GIL and wait for every in-flight blocking op to drain before freeing
            // its component — otherwise destroy / rac_shutdown() could race a live rac_* call on
            // a worker or executor thread (use-after-free). Normally client.shutdown() has already
            // unloaded each model (each unload_*() waited + freed), so this drains only stragglers.
            // RAG ingest/query/stream/clear/stats take g_inflight leases; VAD unload waits via
            // take_handle_when_idle (vad_process itself holds the GIL for the whole call).
            py::gil_scoped_release release;
            std::unique_lock<std::mutex> lock(g_handles_mutex);
            g_inflight_cv.wait(lock, [] {
                for (auto& kv : g_inflight) {
                    if (kv.second > 0) return false;
                }
                return true;
            });
#ifdef RAC_HAVE_BACKEND_RAG
            // Destroy RAG sessions first — each owns its internal embedding/LLM
            // services, independent of the user-loaded handle maps below.
            for (auto& kv : g_rag_handles) rac_rag_session_destroy_proto(kv.second);
            g_rag_handles.clear();
#endif
            for (auto& kv : g_llm_handles) rac_llm_component_destroy(kv.second);
            for (auto& kv : g_vlm_handles) rac_vlm_component_destroy(kv.second);
            for (auto& kv : g_embed_handles) rac_embeddings_destroy(kv.second);
            for (auto& kv : g_stt_handles) rac_stt_component_destroy(kv.second);
            for (auto& kv : g_tts_handles) rac_tts_component_destroy(kv.second);
            for (auto& kv : g_vad_handles) rac_vad_component_destroy(kv.second);
            for (auto& kv : g_diar_handles) {
                rac_diarization_cleanup(kv.second);
                rac_diarization_destroy(kv.second);
            }
            for (auto& kv : g_seg_handles) {
                rac_segmentation_cleanup(kv.second);
                rac_segmentation_destroy(kv.second);
            }
            for (auto& kv : g_voice_handles) {
                rac_voice_agent_cleanup(kv.second);
                rac_voice_agent_destroy(kv.second);
            }
#if defined(RAC_HAVE_BACKEND_COREML)
            for (auto& kv : g_diff_handles) {
                rac_diffusion_cleanup(kv.second);
                rac_diffusion_destroy(kv.second);
            }
#endif
            g_llm_handles.clear();
            g_vlm_handles.clear();
            g_embed_handles.clear();
            g_stt_handles.clear();
            g_tts_handles.clear();
            g_vad_handles.clear();
            g_diar_handles.clear();
            g_seg_handles.clear();
            g_voice_handles.clear();
#if defined(RAC_HAVE_BACKEND_COREML)
            g_diff_handles.clear();
#endif
            g_inflight.clear();
        }
#ifdef RAC_PY_CONTROL_PLANE
        // Flush queued telemetry while the HTTP transport is still registered:
        // rac_shutdown() tears the transport down before its own terminal flush,
        // which would otherwise drop the last batch ("transport unavailable").
        {
            std::lock_guard<std::mutex> lock(g_handles_mutex);
            if (g_telemetry_manager) rac_events_flush_telemetry_sink();
        }
#endif
        rac_shutdown();
#ifdef RAC_PY_CONTROL_PLANE
        // Detach + destroy the telemetry manager after the runtime is down.
        telemetry_teardown();
#endif
    }
}

// =============================================================================
// Secure key-value store (DPAPI-backed on Windows via the platform adapter).
// Requires initialize() first. Values are encrypted at rest.
// =============================================================================
void secure_set(const std::string& key, const std::string& value) {
    if (!g_initialized.load()) throw std::runtime_error("not initialized");
    if (!g_adapter.secure_set) throw std::runtime_error("secure store unavailable");
    rac_result_t rc = g_adapter.secure_set(key.c_str(), value.c_str(), g_adapter.user_data);
    if (rc != RAC_SUCCESS) raise_rac_error(rc, "secure_set");
}

py::object secure_get(const std::string& key) {
    if (!g_initialized.load()) throw std::runtime_error("not initialized");
    if (!g_adapter.secure_get) return py::none();
    char* out = nullptr;
    rac_result_t rc = g_adapter.secure_get(key.c_str(), &out, g_adapter.user_data);
    if (rc != RAC_SUCCESS || !out) {
        if (out) rac_free(out);
        return py::none();  // clean miss
    }
    std::string val(out);
    rac_free(out);
    return py::str(val);
}

void secure_delete(const std::string& key) {
    if (!g_initialized.load()) throw std::runtime_error("not initialized");
    if (g_adapter.secure_delete) g_adapter.secure_delete(key.c_str(), g_adapter.user_data);
}

// =============================================================================
// version()
// =============================================================================
std::string version() {
    const char* v = rac_sdk_get_version();
    return v ? v : "";
}

// The engine backends compiled into this build (from the RAC_HAVE_BACKEND_<X> defines the
// CMake backend loop emits). The plugin registry auto-selects the highest-priority registered
// backend per modality, so this is what a loaded model can route to on this host.
std::vector<std::string> backends() {
    std::vector<std::string> out;
#ifdef RAC_HAVE_BACKEND_LLAMACPP
    out.push_back("llamacpp");
#endif
#ifdef RAC_HAVE_BACKEND_ONNX
    out.push_back("onnx");
#endif
#ifdef RAC_HAVE_BACKEND_SHERPA
    out.push_back("sherpa");
#endif
#ifdef RAC_HAVE_BACKEND_QHEXRT
    out.push_back("qhexrt");
#endif
#ifdef RAC_HAVE_BACKEND_MLX
    out.push_back("mlx");
#endif
#ifdef RAC_HAVE_BACKEND_COREML
    out.push_back("coreml");
#endif
#ifdef RAC_HAVE_BACKEND_CLOUD
    out.push_back("cloud");
#endif
#ifdef RAC_HAVE_BACKEND_RAG
    out.push_back("rag");
#endif
    return out;
}

}  // namespace

PYBIND11_MODULE(_core, m) {
    m.doc() = "RunAnywhere native core (rac_* C ABI bound via pybind11).";

    m.def("version", &version, "Return the RunAnywhere SDK version string.");
    m.def("backends", &backends, "List the engine backends compiled into this build.");

    m.def("initialize", &initialize, py::arg("secure_dir"), py::arg("base_dir") = py::none(),
          "Initialize the runtime: fill the platform adapter, set the base dir, "
          "call rac_init, and register backends once.");
    m.def("shutdown", &shutdown, "Destroy all live handles and shut the runtime down.");

#ifdef RAC_PY_CONTROL_PLANE
    // Desktop control plane (telemetry + auth). Present only when the desktop
    // libcurl transport is linked into commons (RAC_DESKTOP_ADAPTER=ON).
    m.attr("has_control_plane") = true;
    m.def("device_persistent_id", &device_persistent_id,
          "The persistent per-device UUID commons mints.");
    m.def("dev_staging_base_url", &dev_staging_base_url,
          "Baked staging backend URL for keyless development (empty when none).");
    m.def("configure_control_plane", &configure_control_plane, py::arg("http_poster"),
          py::arg("environment"), py::arg("api_key"), py::arg("base_url"), py::arg("device_id"),
          py::arg("platform"), py::arg("sdk_version"), py::arg("sdk_binding"),
          py::arg("app_identifier"), py::arg("app_name"), py::arg("app_version"),
          py::arg("phase1_bytes"), py::arg("phase2_bytes"),
          "Register the urllib HTTP transport (http_poster), seed state, and run the "
          "two-phase init (telemetry + auth). Returns serialized SdkInitResult bytes.");
#else
    m.attr("has_control_plane") = false;
#endif

    // LLM
    m.def("load_model", &load_model, py::arg("path"), py::arg("id") = py::none(),
          py::arg("name") = py::none(), "Load an LLM model; returns an integer handle.");
    m.def("generate", &generate, py::arg("handle"), py::arg("prompt"), py::arg("on_token"),
          py::arg("max_tokens") = py::none(), py::arg("temperature") = py::none(),
          py::arg("top_p") = py::none(), py::arg("top_k") = py::none(),
          py::arg("system_prompt") = py::none(), py::arg("grammar") = py::none(),
          py::arg("disable_thinking") = py::none(),
          "Stream tokens from an LLM handle; on_token(str) is called per token and "
          "may return False to stop.");
    m.def("cancel_generate", &cancel_generate, py::arg("handle"),
          "Request cancellation of an in-flight LLM generation.");
    m.def("unload_model", &unload_model, py::arg("handle"), "Unload an LLM handle.");

    // LoRA (LlamaCPP backend only; write-only — no read-back)
    m.def("lora_apply", &lora_apply, py::arg("handle"), py::arg("adapter_path"),
          py::arg("scale") = py::none(),
          "Load and apply a LoRA adapter onto an LLM handle (recreates context, clears KV cache).");
    m.def("lora_remove", &lora_remove, py::arg("handle"), py::arg("adapter_path"),
          "Remove one LoRA adapter previously applied to an LLM handle.");
    m.def("lora_remove_all", &lora_remove_all, py::arg("handle"),
          "Remove every LoRA adapter applied to an LLM handle.");

    // VLM
    m.def("load_vlm_model", &load_vlm_model, py::arg("model_path"), py::arg("mmproj_path"),
          py::arg("id") = py::none(), py::arg("name") = py::none(),
          "Load a VLM model + mmproj; returns an integer handle.");
    m.def("generate_vlm", &generate_vlm, py::arg("handle"), py::arg("image_path"), py::arg("prompt"),
          py::arg("on_token"), py::arg("max_tokens") = py::none(), py::arg("temperature") = py::none(),
          py::arg("top_p") = py::none(), py::arg("top_k") = py::none(),
          py::arg("system_prompt") = py::none(),
          "Stream tokens from a VLM handle over an image + prompt; on_token(str) per token.");
    m.def("cancel_generate_vlm", &cancel_generate_vlm, py::arg("handle"),
          "Request cancellation of an in-flight VLM generation.");
    m.def("unload_vlm_model", &unload_vlm_model, py::arg("handle"), "Unload a VLM handle.");

    // Embeddings
    m.def("load_embedding_model", &load_embedding_model, py::arg("path"),
          "Load an embedding model (ONNX); returns an integer handle.");
    m.def("embed", &embed, py::arg("handle"), py::arg("text"),
          "Embed text; returns a float32 numpy array.");
    m.def("embed_batch", &embed_batch, py::arg("handle"), py::arg("texts"),
          "Embed a batch of texts; returns a list of float32 numpy arrays.");
    m.def("unload_embedding_model", &unload_embedding_model, py::arg("handle"),
          "Unload an embedding handle.");

    // Model registry (id -> local_path) so RAG can resolve model ids to paths.
    m.def("register_model", &register_model, py::arg("model_id"), py::arg("local_path"),
          py::arg("framework"), py::arg("category"),
          "Register a model (id -> local_path + framework/category ints) into the "
          "global model registry so the RAG session ABI can resolve it.");
    m.def("get_model", &get_model, py::arg("model_id"),
          "Look up a registered model by id; returns a dict or None.");
    m.def("list_models", &list_models, "List all registered models as dicts.");
    m.def("remove_model", &remove_model, py::arg("model_id"),
          "Remove a model from the global registry.");

#ifdef RAC_HAVE_BACKEND_RAG
    // RAG — proto-bytes in / proto-bytes out (serialized runanywhere.v1.* msgs).
    m.def("rag_session_create", &rag_session_create, py::arg("config_bytes"),
          "Create a RAG session from RAGConfiguration bytes; returns an integer handle.");
    m.def("rag_ingest", &rag_ingest, py::arg("handle"), py::arg("document_bytes"),
          "Ingest one RAGDocument (bytes); returns RAGStatistics bytes.");
    m.def("rag_query", &rag_query, py::arg("handle"), py::arg("query_bytes"),
          "Query with RAGQueryOptions bytes; returns RAGResult bytes.");
    m.def("rag_search", &rag_search, py::arg("handle"), py::arg("request_bytes"),
          "Retrieval-only search with RAGSearchRequest bytes; returns RAGSearchResponse bytes.");
    m.def("rag_query_stream", &rag_query_stream, py::arg("handle"), py::arg("query_bytes"),
          py::arg("on_event"),
          "Stream a RAG query; on_event(RAGStreamEvent bytes) per event, may return False to stop.");
    m.def("rag_cancel", &rag_cancel, py::arg("handle"),
          "Request cancellation of the query running on a RAG session.");
    m.def("rag_clear", &rag_clear, py::arg("handle"),
          "Clear the RAG index; returns RAGStatistics bytes.");
    m.def("rag_stats", &rag_stats, py::arg("handle"),
          "Return RAGStatistics bytes for a RAG session.");
    m.def("rag_session_destroy", &rag_session_destroy, py::arg("handle"),
          "Destroy a RAG session handle.");
#endif

    // STT
    m.def("load_stt_model", &load_stt_model, py::arg("dir"), py::arg("id") = py::none(),
          py::arg("name") = py::none(), "Load an STT model dir (sherpa); returns an integer handle.");
    m.def("transcribe", &transcribe, py::arg("handle"), py::arg("pcm16"),
          "Transcribe 16 kHz mono PCM16 bytes; returns the text.");
    m.def("unload_stt_model", &unload_stt_model, py::arg("handle"), "Unload an STT handle.");

    // TTS
    m.def("load_tts_voice", &load_tts_voice, py::arg("dir"), py::arg("id") = py::none(),
          py::arg("name") = py::none(), "Load a TTS voice dir (sherpa); returns an integer handle.");
    m.def("synthesize", &synthesize, py::arg("handle"), py::arg("text"),
          "Synthesize speech; returns (float32 samples ndarray, sample_rate int).");
    m.def("unload_tts_voice", &unload_tts_voice, py::arg("handle"), "Unload a TTS handle.");

    // VAD
    m.def("create_vad", &create_vad, py::arg("threshold") = py::none(),
          "Create an energy VAD; returns an integer handle.");
    m.def("vad_process", &vad_process, py::arg("handle"), py::arg("samples"),
          "Process a float32 sample frame; returns True if speech is present.");
    m.def("vad_is_active", &vad_is_active, py::arg("handle"),
          "Return True if speech is currently active.");
    m.def("vad_set_threshold", &vad_set_threshold, py::arg("handle"), py::arg("threshold"),
          "Set the VAD energy threshold.");
    m.def("vad_reset", &vad_reset, py::arg("handle"), "Reset the VAD state.");
    m.def("load_vad_model", &load_vad_model, py::arg("handle"), py::arg("model_path"),
          py::arg("id") = py::none(), py::arg("name") = py::none(),
          "Load a Silero/sherpa VAD model onto an existing energy VAD handle.");
    m.def("unload_vad", &unload_vad, py::arg("handle"), "Unload a VAD handle.");

    // Diarization (offline batch; ONNX Sortformer)
    m.def("load_diarization_model", &load_diarization_model, py::arg("model_path"),
          py::arg("id") = py::none(),
          "Create + initialize a diarization model (file or directory); returns an integer handle.");
    m.def("diarize", &diarize, py::arg("handle"), py::arg("samples"),
          py::arg("sample_rate_hz") = py::none(), py::arg("threshold") = py::none(),
          py::arg("minimum_duration_ms") = py::none(), py::arg("merge_gap_ms") = py::none(),
          "Diarize float32 mono samples; returns {segments, speaker_count, duration_ms}.");
    m.def("unload_diarization_model", &unload_diarization_model, py::arg("handle"),
          "Unload a diarization handle.");

    // Segmentation (offline batch; ONNX)
    m.def("load_segmentation_model", &load_segmentation_model, py::arg("model_path"),
          py::arg("id") = py::none(),
          "Create + initialize a segmentation model (file or directory); returns an integer handle.");
    m.def("segment", &segment, py::arg("handle"), py::arg("data"), py::arg("width"),
          py::arg("height"), py::arg("pixel_format") = py::none(),
          py::arg("stride_bytes") = py::none(), py::arg("include_diagnostic_rgba") = py::none(),
          "Segment raw image pixels; returns {width, height, class_mask, classes}.");
    m.def("unload_segmentation_model", &unload_segmentation_model, py::arg("handle"),
          "Unload a segmentation handle.");

    // Voice agent (file-PCM turn; STT→LLM→TTS — no mic/WebRTC/wake-word)
    m.def("create_voice_agent", &create_voice_agent,
          "Create a standalone voice agent; returns an integer handle.");
    m.def("initialize_voice_agent", &initialize_voice_agent, py::arg("handle"),
          py::arg("stt_path"), py::arg("llm_path"), py::arg("tts_path"),
          py::arg("stt_id") = py::none(), py::arg("llm_id") = py::none(),
          py::arg("tts_id") = py::none(), py::arg("stt_name") = py::none(),
          py::arg("llm_name") = py::none(), py::arg("tts_name") = py::none(),
          "Initialize a voice agent with STT/LLM/TTS model paths (loads components).");
    m.def("process_voice_turn", &process_voice_turn, py::arg("handle"), py::arg("pcm16"),
          "Run one STT→LLM→TTS turn over 16 kHz mono PCM16; returns a decoded result dict.");
    m.def("destroy_voice_agent", &destroy_voice_agent, py::arg("handle"),
          "Cleanup + destroy a voice agent handle.");

#if defined(RAC_HAVE_BACKEND_COREML)
    // Diffusion (CoreML) — only exported when the CoreML backend is linked.
    m.def("load_diffusion_model", &load_diffusion_model, py::arg("model_path"),
          py::arg("id") = py::none(),
          "Create + initialize a diffusion model; returns an integer handle.");
    m.def("generate_image", &generate_image, py::arg("handle"), py::arg("prompt"),
          py::arg("negative_prompt") = py::none(), py::arg("width") = py::none(),
          py::arg("height") = py::none(), py::arg("steps") = py::none(),
          py::arg("guidance_scale") = py::none(), py::arg("seed") = py::none(),
          "Generate an image; returns {image_data, width, height, seed, ...}.");
    m.def("unload_diffusion_model", &unload_diffusion_model, py::arg("handle"),
          "Unload a diffusion handle.");
#endif

    // Secure store
    m.def("secure_set", &secure_set, py::arg("key"), py::arg("value"),
          "Store a key/value pair in the platform secure store (DPAPI on Windows; plaintext 0600 on POSIX).");
    m.def("secure_get", &secure_get, py::arg("key"),
          "Read a secure value; returns str or None on a miss.");
    m.def("secure_delete", &secure_delete, py::arg("key"), "Delete a secure key.");
}
