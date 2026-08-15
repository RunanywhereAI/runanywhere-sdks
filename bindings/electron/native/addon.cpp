// addon.cpp — RunAnywhere Electron N-API addon.
//
// Binds the rac_* C ABI (reusing the Win32 platform adapter proven by the M0
// harness) for on-device inference in Node/Electron. Node-API only, so one
// prebuilt spans Node/Electron versions. Streaming uses a bounded
// Napi::ThreadSafeFunction on a worker thread (BlockingCall = backpressure) and
// resolves a Promise in the TSFN finalizer.
//
// Modalities: LLM (generate) and VLM (generateVlm, image + prompt) — both
// served by the already-linked llama.cpp engine.

#include <napi.h>

#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstdlib>
#include <cstring>
#include <functional>
#include <memory>
#include <mutex>
#include <sstream>
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
// RAC_LOG_* is used unconditionally (load_plugins_from_env), so it cannot ride
// in on the desktop-adapter block below. Without this, a build with
// RAC_DESKTOP_ADAPTER=OFF — the win-arm64 / QHexRT lane — still sees the
// `rac_log_level_t` enum via rac_core.h but not the macro, so
// `RAC_LOG_WARNING(...)` parses as a call on an enum constant and fails with
// "C2064: term does not evaluate to a function taking 4 arguments".
#include "rac/core/rac_logger.h"
#include "rac/plugin/rac_plugin_loader.h"
#ifdef RAC_HAVE_BACKEND_NEURT
#include "rac/plugin/rac_plugin_entry.h"
#include "rac/plugin/rac_plugin_entry_neurt.h"
#endif
#include "audio_bridge.h"
#include "data_bridge.h"
#include "download_bridge.h"
#include "llm_bridge.h"
#include "logging_bridge.h"
#include "lora_bridge.h"
#include "model_bridge.h"
#include "proto_bridge.h"
#include "speech_bridge.h"
#include "tool_bridge.h"
#include "vlm_bridge.h"
#include "voice_bridge.h"

#include "rac/core/rac_types.h"
#include "rac/features/diarization/rac_diarization_service.h"
#include "rac/features/diarization/rac_diarization_types.h"
#include "rac/features/embeddings/rac_embeddings_service.h"
#include "rac/features/embeddings/rac_embeddings_types.h"
#include "rac/features/llm/rac_llm_component.h"
#include "rac/features/rag/rac_rag.h"
#include "rac/features/rerank/rac_rerank_service.h"
#include "rac/features/rerank/rac_rerank_types.h"
#include "rac/features/segmentation/rac_segmentation_service.h"
#include "rac/features/segmentation/rac_segmentation_types.h"
#include "rac/features/stt/rac_stt_component.h"
#include "rac/features/stt/rac_stt_types.h"
#include "rac/features/tts/rac_tts_component.h"
#include "rac/features/tts/rac_tts_types.h"
#include "rac/features/vad/rac_vad_component.h"
#include "rac/features/vad/rac_vad_stream.h"
#include "rac/features/vad/rac_vad_types.h"
#include "rac/features/vlm/rac_vlm_component.h"
#include "rac/features/vlm/rac_vlm_types.h"
#include "rac/foundation/rac_proto_buffer.h"
#include "rac/infrastructure/http/rac_http_client.h"
#include "rac/infrastructure/model_management/rac_model_paths.h"
#include "rac/infrastructure/model_management/rac_model_registry.h"
#include "rac/infrastructure/model_management/rac_model_types.h"
// Desktop control plane (telemetry + auth). Compiled only when the desktop
// adapter — which carries the libcurl HTTP transport — is linked into commons
// (RAC_ELECTRON_HAVE_DESKTOP, set by native/CMakeLists.txt when
// RAC_DESKTOP_ADAPTER=ON).
#ifdef RAC_ELECTRON_HAVE_DESKTOP
#include "rac/core/rac_sdk_state.h"
#include "rac/desktop/rac_desktop.h"
#include "rac/infrastructure/device/rac_device_identity.h"
#include "rac/infrastructure/device/rac_device_manager.h"
#include "rac/infrastructure/events/rac_sdk_event_stream.h"
#include "rac/infrastructure/http/rac_http_client.h"
#include "rac/infrastructure/http/rac_http_transport.h"
#include "rac/infrastructure/network/rac_auth_manager.h"
#include "rac/infrastructure/network/rac_client_info.h"
#include "rac/infrastructure/network/rac_dev_config.h"
#include "rac/infrastructure/network/rac_endpoints.h"
#include "rac/infrastructure/network/rac_environment.h"
#include "rac/infrastructure/telemetry/rac_telemetry_manager.h"
#include "rac/lifecycle/rac_sdk_init.h"
#endif

// Engine backends — linked when present (see native/CMakeLists.txt foreach).
// Required backends keep their commons headers; optional ones declare register
// only.
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
#ifdef RAC_HAVE_BACKEND_MLX
rac_result_t rac_backend_mlx_register(void);
#endif
#ifdef RAC_HAVE_BACKEND_CLOUD
rac_result_t rac_backend_cloud_register(void);
#endif
}

// Internal (non-proto) embeddings service factory — its header lives under
// commons/src/, not include/, so re-declare the prototype here. The addon
// static-links rac_commons, so the symbol resolves at link time.
namespace rac {
namespace embeddings {
rac_result_t create_service(const char* model_id, const char* config_json,
                            rac_handle_t* out_handle);
}  // namespace embeddings
}  // namespace rac

namespace {

using rac_electron::RunNativeCall;

// The adapter struct is caller-owned and must outlive rac_shutdown().
rac_platform_adapter_t g_adapter;
std::atomic<bool> g_initialized{false};

#ifdef RAC_ELECTRON_HAVE_DESKTOP
// Owns the telemetry manager for the process lifetime so the flush at shutdown
// can deliver through our HTTP callback before teardown. Guarded by
// g_handles_mutex on create/destroy.
rac_telemetry_manager_t* g_telemetry_manager = nullptr;
#endif

// Handles are exposed to JS as small integer ids. LLM and VLM components use
// distinct rac_*_component_destroy calls, so they live in separate maps.
std::mutex g_handles_mutex;
std::unordered_map<int32_t, rac_handle_t> g_llm_handles;
std::unordered_map<int32_t, rac_handle_t> g_vlm_handles;
std::unordered_map<int32_t, rac_handle_t> g_embed_handles;
std::unordered_map<int32_t, rac_handle_t> g_stt_handles;
std::unordered_map<int32_t, rac_handle_t> g_tts_handles;
std::unordered_map<int32_t, rac_handle_t> g_vad_handles;
std::unordered_map<int32_t, rac_handle_t> g_rag_handles;
std::unordered_map<int32_t, rac_handle_t> g_rerank_handles;
std::unordered_map<int32_t, rac_handle_t> g_diar_handles;
std::unordered_map<int32_t, rac_handle_t> g_seg_handles;
int32_t g_next_handle_id = 1;

// Adapters applied to a live LLM component, tracked per handle so lora.list()
// can report state the C ABI does not query back (no rac_llm_component_*_lora
// getter exists — apply/remove/clear are write-only).
std::unordered_map<int32_t, std::vector<std::pair<std::string, float>>> g_lora_applied;

rac_handle_t handle_for(const std::unordered_map<int32_t, rac_handle_t>& map, int32_t id) {
    std::lock_guard<std::mutex> lock(g_handles_mutex);
    auto it = map.find(id);
    return (it == map.end()) ? nullptr : it->second;
}

// =============================================================================
// In-flight operation tracking — prevents destroy-during-call use-after-free.
//
// Blocking rac_* calls (generate/embed/transcribe/synthesize/rag_*) may run on
// a worker thread while another thread calls unload_*()/shutdown(). Mark a
// handle busy for every blocking op (keyed by the globally-unique integer id)
// and make unload/shutdown WAIT for the handle to go idle before destroying it.
// =============================================================================
std::condition_variable g_inflight_cv;
std::unordered_map<int32_t, int> g_inflight;  // handle id -> active blocking-op count

// A component is not re-entrant. While every blocking op ran on the JS thread
// the event loop serialised them for free; now that they run on the libuv pool,
// two awaited-in-parallel calls could reach one engine at once, so each handle
// carries a gate the worker holds for the duration of its rac_* call.
std::unordered_map<int32_t, std::shared_ptr<std::mutex>> g_op_gates;

rac_handle_t begin_op(const std::unordered_map<int32_t, rac_handle_t>& map, int32_t id) {
    std::lock_guard<std::mutex> lock(g_handles_mutex);
    auto it = map.find(id);
    if (it == map.end())
        return nullptr;
    ++g_inflight[id];
    return it->second;
}

void end_op(int32_t id) {
    {
        std::lock_guard<std::mutex> lock(g_handles_mutex);
        auto it = g_inflight.find(id);
        if (it != g_inflight.end() && --it->second <= 0) {
            g_inflight.erase(it);
            g_op_gates.erase(id);
        }
    }
    g_inflight_cv.notify_all();
}

// Take the in-flight lease (so unload waits) and the gate that serialises this
// handle. False means the id is unknown; the caller reports an invalid handle.
bool begin_worker_op(const std::unordered_map<int32_t, rac_handle_t>& map, int32_t id,
                     rac_handle_t* out_handle, std::shared_ptr<std::mutex>* out_gate) {
    std::lock_guard<std::mutex> lock(g_handles_mutex);
    auto it = map.find(id);
    if (it == map.end())
        return false;
    ++g_inflight[id];
    auto& gate = g_op_gates[id];
    if (!gate)
        gate = std::make_shared<std::mutex>();
    *out_handle = it->second;
    *out_gate = gate;
    return true;
}

struct OpScope {
    int32_t id;
    explicit OpScope(int32_t i) : id(i) {}
    ~OpScope() { end_op(id); }
    OpScope(const OpScope&) = delete;
    OpScope& operator=(const OpScope&) = delete;
};

// Bound so a stuck in-flight op cannot freeze the sync JS unload/destroy path
// forever. Callers treat nullptr as "gone / unavailable" and skip destroy.
constexpr auto kTakeHandleIdleTimeout = std::chrono::seconds(60);

rac_handle_t take_handle_when_idle(std::unordered_map<int32_t, rac_handle_t>& map, int32_t id) {
    std::unique_lock<std::mutex> lock(g_handles_mutex);
    const bool idle = g_inflight_cv.wait_for(lock, kTakeHandleIdleTimeout, [&] {
        auto it = g_inflight.find(id);
        return it == g_inflight.end() || it->second == 0;
    });
    if (!idle)
        return nullptr;
    auto it = map.find(id);
    if (it == map.end())
        return nullptr;
    rac_handle_t h = it->second;
    map.erase(it);
    return h;
}

int rac_code_abs(rac_result_t code) {
    int value = static_cast<int>(code);
    return value < 0 ? -value : value;
}

// Build a structured JS Error for a rac_result_t so the TS layer can recover a
// typed SDKException without depending on string parsing alone.
Napi::Error make_rac_error(Napi::Env env, rac_result_t code, const std::string& message) {
    Napi::Error error = Napi::Error::New(env, message);
    Napi::Object value = error.Value();
    value.Set("code", Napi::Number::New(env, rac_code_abs(code)));  // canonical positive ErrorCode
    value.Set("cAbiCode", Napi::Number::New(env, static_cast<int>(code)));  // raw rac_result_t
    return error;
}

// Throw a structured Error whose message still ends with "failed: <rac_code>"
// so older string-only callers remain parseable too.
void throw_rac_error(Napi::Env env, rac_result_t code, const std::string& context) {
    std::string msg = context.empty() ? ("rac error failed: " + std::to_string(code))
                                      : (context + " failed: " + std::to_string(code));
    make_rac_error(env, code, msg).ThrowAsJavaScriptException();
}

// Idempotent wrapper: a second load of the same plugin (host pre-load + env
// replay inside initialize, or a re-fork that already registered) is success.
rac_result_t load_plugin_path(const char* path) {
    if (path == nullptr || path[0] == '\0')
        return RAC_ERROR_NULL_POINTER;
    rac_result_t rc = rac_registry_load_plugin(path);
    if (rc == RAC_ERROR_PLUGIN_DUPLICATE)
        return RAC_SUCCESS;
    return rc;
}

#ifdef RAC_ELECTRON_THIN_ADDON
// Path list separator matches Node's `path.delimiter` (Unix `:` / Windows `;`).
#ifdef _WIN32
constexpr char kPluginPathDelimiter = ';';
#else
constexpr char kPluginPathDelimiter = ':';
#endif

// Load every absolute path in RUNANYWHERE_PLUGIN_PATHS. Main sets this before
// forking the utility host; it is NEVER an RPC argument (renderer must not be
// able to dlopen arbitrary native code). Compiled only for thin builds — fat
// builds may still receive the env for forward-compat but skip loading here.
//
// Delegates the loop to commons' rac_registry_load_plugins so per-plugin
// isolation is a property of the loader every SDK shares, not of this file.
// It previously returned on the first failure, which made initialize() call
// rac_shutdown() and fail — one unloadable backend took the whole SDK with it.
void load_plugins_from_env() {
    const char* raw = std::getenv("RUNANYWHERE_PLUGIN_PATHS");
    if (raw == nullptr || raw[0] == '\0')
        return;
    std::string list(raw);
    std::string path;
    std::istringstream stream(list);
    std::vector<std::string> paths;
    while (std::getline(stream, path, kPluginPathDelimiter)) {
        if (!path.empty())
            paths.push_back(path);
    }
    if (paths.empty())
        return;
    std::vector<const char*> c_paths;
    c_paths.reserve(paths.size());
    for (const auto& p : paths)
        c_paths.push_back(p.c_str());
    size_t loaded = 0;
    (void)rac_registry_load_plugins(c_paths.data(), c_paths.size(), &loaded);
    if (loaded < c_paths.size()) {
        // Not an error return: the backends that DID load must keep serving.
        // listUnavailablePlugins() carries which ones failed and why.
        RAC_LOG_WARNING("ElectronAddon", "%zu of %zu plugins loaded; the rest are unavailable",
                        loaded, c_paths.size());
    }
}
#endif  // RAC_ELECTRON_THIN_ADDON

// =============================================================================
// loadPlugin(absolutePath) — host / main only. Not on the RPC allowlist.
// =============================================================================
Napi::Value LoadPlugin(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    if (info.Length() < 1 || !info[0].IsString()) {
        Napi::TypeError::New(env, "loadPlugin(absolutePath) expects a string")
            .ThrowAsJavaScriptException();
        return env.Undefined();
    }
    std::string path = info[0].As<Napi::String>().Utf8Value();
    return RunNativeCall(env, "rac_registry_load_plugin",
                         [path]() { return load_plugin_path(path.c_str()); });
}

// listPlugins() -> string[] of currently registered engine names (runtime).
Napi::Value ListPlugins(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    (void)info;
    const char** names = nullptr;
    size_t count = 0;
    rac_result_t rc = rac_registry_list_plugins(&names, &count);
    if (rc != RAC_SUCCESS) {
        throw_rac_error(env, rc, "rac_registry_list_plugins");
        return env.Undefined();
    }
    Napi::Array out = Napi::Array::New(env, count);
    for (size_t i = 0; i < count; ++i) {
        out.Set(i, Napi::String::New(env, names[i] != nullptr ? names[i] : ""));
    }
    rac_registry_free_plugin_list(names, count);
    return out;
}

// listUnavailablePlugins() -> [{ name, path, status }] for every backend that
// asked to register and was refused. The complement of listPlugins(): together
// they answer "what is serving" and "what is missing, and why" — which is what
// lets one broken backend be a reported degradation instead of a dead SDK.
Napi::Value ListUnavailablePlugins(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    (void)info;
    rac_plugin_unavailable_t* items = nullptr;
    size_t count = 0;
    rac_result_t rc = rac_registry_list_unavailable_plugins(&items, &count);
    if (rc != RAC_SUCCESS) {
        throw_rac_error(env, rc, "rac_registry_list_unavailable_plugins");
        return env.Undefined();
    }
    Napi::Array out = Napi::Array::New(env, count);
    for (size_t i = 0; i < count; ++i) {
        Napi::Object entry = Napi::Object::New(env);
        entry.Set("name", Napi::String::New(env, items[i].name != nullptr ? items[i].name : ""));
        entry.Set("path", Napi::String::New(env, items[i].path != nullptr ? items[i].path : ""));
        entry.Set("status", Napi::Number::New(env, static_cast<int>(items[i].status)));
        out.Set(i, entry);
    }
    rac_registry_free_unavailable_plugins(items, count);
    return out;
}

// pluginApiVersion() — commons' RAC_PLUGIN_API_VERSION as a runtime number.
Napi::Value PluginApiVersion(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    (void)info;
    return Napi::Number::New(env, static_cast<double>(rac_plugin_api_version()));
}

// =============================================================================
// initialize(secureDir[, baseDir])
// =============================================================================
Napi::Value Initialize(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    if (info.Length() < 1 || !info[0].IsString()) {
        Napi::TypeError::New(env, "initialize(secureDir[, baseDir]) expects a string")
            .ThrowAsJavaScriptException();
        return env.Undefined();
    }
    std::string secure = info[0].As<Napi::String>().Utf8Value();
    std::string base =
        (info.Length() > 1 && info[1].IsString()) ? info[1].As<Napi::String>().Utf8Value() : secure;

    return RunNativeCall(env, "rac_init", [secure, base]() -> rac_result_t {
        if (g_initialized.load())
            return RAC_SUCCESS;

#ifdef _WIN32
        rac_electron_fill_win32_adapter(&g_adapter, secure.c_str());
#else
        rac_electron_fill_posix_adapter(&g_adapter, secure.c_str());
#endif
        // The adapter's own `log` writes straight to stderr. Commons routes every
        // record through this slot, so replacing it here is what gives the
        // `logging` namespace something to subscribe to — and what puts the
        // stderr write itself behind `logging.setLocalEnabled`. The adapter files
        // stay untouched because the M0 harness links them without this bridge.
        g_adapter.log = [](rac_log_level_t level, const char* category, const char* message,
                           void*) { rac_electron::ForwardLog(level, category, message); };

        rac_config_t cfg;
        std::memset(&cfg, 0, sizeof(cfg));
        cfg.platform_adapter = &g_adapter;
        cfg.log_level = RAC_LOG_WARNING;
        cfg.log_tag = "electron";

        rac_model_paths_set_base_dir(base.c_str());

        rac_result_t rc = rac_init(&cfg);
        if (rc != RAC_SUCCESS)
            return rc;

#ifdef RAC_ELECTRON_HAVE_DESKTOP
        // D4 — desktop HTTP path. Platform adapters leave http_download NULL on
        // purpose (that slot is the Web/Emscripten async driver). Model downloads,
        // HF fetches inside the orchestrator, and control-plane POSTs all need the
        // process-wide libcurl transport vtable. Register it here at initialize()
        // — not only inside configureControlPlane() — so downloads work before
        // any API key / phase-2 handshake.
        rc = rac_desktop_http_transport_register();
        if (rc != RAC_SUCCESS) {
            rac_shutdown();
            return rc;
        }
#endif

        // Backend/plugin registration is process-global and persists across
        // rac_shutdown(), so register exactly once — re-registering after a
        // shutdown+re-init would fail (RAC already-registered), which is why
        // initialize() must be safe to call again after shutdown().
        //
        // FAT builds: each call is gated by RAC_HAVE_BACKEND_<X> from
        // native/CMakeLists.txt (zero macros ⇒ empty block in thin mode).
        // THIN builds: engines arrive via rac_registry_load_plugin — either an
        // explicit loadPlugin() from the host, or RUNANYWHERE_PLUGIN_PATHS set
        // by main before the utility fork (never an RPC argument).
        static bool backends_registered = false;
        if (!backends_registered) {
            // Every linked backend gets the same treatment: try it, and if it
            // declines, record WHICH one and why, then move on to the next.
            //
            // Two bugs are closed here at once. llamacpp used to rac_shutdown()
            // and fail initialize() on any non-success — one backend taking
            // down the entire SDK, including ONNX, Sherpa and every
            // non-inference API. The others went the opposite way and discarded
            // their result entirely, so a backend could go missing with no
            // code, no reason, and nothing for the app to report.
            //
            // "Already registered" is NOT a failure: RAC_ERROR_PLUGIN_DUPLICATE
            // and RAC_ERROR_MODULE_ALREADY_REGISTERED both mean the backend is
            // in the registry and serving — a static-init ctor, a prior
            // loadPlugin(), or an env replay simply got there first. Commons'
            // own batch loader counts DUPLICATE as loaded
            // (rac_registry_load_plugins), so recording either here would put a
            // working backend on the unavailability ledger and make
            // capabilities() report it as missing.
            const auto try_register = [](const char* name, rac_result_t result) {
                if (result == RAC_SUCCESS || result == RAC_ERROR_PLUGIN_DUPLICATE ||
                    result == RAC_ERROR_MODULE_ALREADY_REGISTERED)
                    return;
                rac_registry_record_plugin_unavailable(name, nullptr, result);
            };
            (void)try_register;
#ifdef RAC_HAVE_BACKEND_LLAMACPP
            try_register("llamacpp", rac_backend_llamacpp_register());
#endif
#ifdef RAC_HAVE_BACKEND_ONNX
            try_register("onnx", rac_backend_onnx_register());  // embeddings (optional)
#endif
#ifdef RAC_HAVE_BACKEND_SHERPA
            try_register("sherpa", rac_backend_sherpa_register());  // STT / TTS (optional)
#endif
#ifdef RAC_HAVE_BACKEND_QHEXRT
            // Hexagon NPU. Routable on Snapdragon Android and Windows on ARM64 when a
            // matching prebuilt is linked; the not-routable shell otherwise, which
            // registers and then declines every primitive.
            try_register("qhexrt", rac_backend_qhexrt_register());
#endif
#ifdef RAC_HAVE_BACKEND_MLX
            try_register("mlx", rac_backend_mlx_register());
#endif
#ifdef RAC_HAVE_BACKEND_NEURT
            // The neurt engine has no bespoke rac_backend_*_register() fn; register
            // its plugin entry directly, like rcli's bootstrap does.
            try_register("neurt", rac_plugin_register(rac_plugin_entry_neurt()));
#endif
#ifdef RAC_HAVE_BACKEND_CLOUD
            try_register("cloud", rac_backend_cloud_register());
#endif
#ifdef RAC_ELECTRON_THIN_ADDON
            // Runtime plugins (thin addon only). Fat/static builds ignore the env
            // — rac_registry_load_plugin returns FEATURE_NOT_AVAILABLE there, and
            // backends are already linked via RAC_HAVE_BACKEND_*. Idempotent with
            // a prior host loadPlugin() thanks to DUPLICATE→success.
            load_plugins_from_env();
#endif
            backends_registered = true;
        }
        g_initialized.store(true);
        return RAC_SUCCESS;
    });
}

// memoryInfo() -> { totalBytes, availableBytes, usedBytes } straight from the
// platform adapter commons itself reads. Stays synchronous: it is a sysctl /
// GlobalMemoryStatusEx probe, and the residency policy asks for it on the path
// into a load, where an extra tick of latency would be pure overhead.
Napi::Value MemoryInfo(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    Napi::Object out = Napi::Object::New(env);
    rac_memory_info_t mem;
    std::memset(&mem, 0, sizeof(mem));
    if (g_adapter.get_memory_info == nullptr ||
        g_adapter.get_memory_info(&mem, g_adapter.user_data) != RAC_SUCCESS) {
        // Unknown is 0 across the board — the same convention commons uses, and
        // what rac_model_check_compatibility reads as "requirement satisfied".
        std::memset(&mem, 0, sizeof(mem));
    }
    out.Set("totalBytes", Napi::Number::New(env, static_cast<double>(mem.total_bytes)));
    out.Set("availableBytes", Napi::Number::New(env, static_cast<double>(mem.available_bytes)));
    out.Set("usedBytes", Napi::Number::New(env, static_cast<double>(mem.used_bytes)));
    return out;
}

// hfTokenSet(token) — the process-wide Hugging Face bearer. Commons attaches it
// as `Authorization: Bearer` to https requests whose host is exactly
// huggingface.co / hf.co (downloads, the HEAD size preflight, and the Hub tree
// API), never to a CDN/LFS redirect target and never over a caller-supplied
// Authorization header. Without it a gated or private repo 401s.
//
// null restores the environment fallback commons resolves for itself (HF_TOKEN,
// then $HF_TOKEN_PATH, then $HF_HOME/token, then ~/.cache/huggingface/token);
// an empty string is an explicit opt-out that suppresses that fallback too.
// Synchronous: the C entry point is a mutex and a string copy.
Napi::Value HfTokenSet(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    if (info.Length() < 1 || info[0].IsNull() || info[0].IsUndefined()) {
        rac_http_hf_token_set(nullptr);
        return env.Undefined();
    }
    if (!info[0].IsString()) {
        throw Napi::TypeError::New(env, "hfTokenSet(token) expects a string or null");
    }
    const std::string token = info[0].As<Napi::String>().Utf8Value();
    rac_http_hf_token_set(token.c_str());
    return env.Undefined();
}

// hfTokenConfigured() — whether a non-empty token is active, resolved exactly
// the way the request dispatcher resolves it. The token itself is deliberately
// unreadable across this boundary, so this is the only thing a caller can ask.
Napi::Value HfTokenConfigured(const Napi::CallbackInfo& info) {
    return Napi::Boolean::New(info.Env(), rac_http_hf_token_is_configured() == RAC_TRUE);
}

#ifdef RAC_ELECTRON_HAVE_DESKTOP
// =============================================================================
// Desktop control plane: telemetry + auth over the libcurl HTTP transport.
//
// A behavioral port of rcli's bootstrap (rcli/src/bootstrap.cpp)
// and the Electron/Python-mirrored module.cpp. The desktop adapter linked into
// commons provides the libcurl transport, so telemetry HTTP is delivered
// entirely in C++ (rac_http_client_* over the registered transport) — never on
// the JS thread. Phase-1/2 proto requests are built in TS (ts-proto sdk_init)
// and handed in as Buffers. The two-phase init runs on an AsyncWorker so the
// auth network round-trip never blocks the utility-host JS event loop.
// =============================================================================

// Delivers a queued telemetry batch over the desktop HTTP transport. Wired via
// rac_telemetry_manager_set_http_callback (user_data = the manager); reports
// the outcome back through rac_telemetry_manager_http_complete. Runs on
// commons' telemetry thread — pure C++, never touches JS or a
// ThreadSafeFunction.
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

// The auth manager's persistence vtable, backed by the same secure store the
// public `secure` namespace uses (DPAPI on Windows, owner-only files
// elsewhere). Without it rac_auth_save_tokens is a no-op, every process start
// re-authenticates from scratch, and the refresh token is unusable — which is
// what Electron did before this. The slots follow rac_secure_storage_t's own
// return convention, which is NOT rac_result_t: 0/length for success,
// RAC_ERROR_FILE_NOT_FOUND for a clean miss, negative for a real failure.
int auth_storage_store(const char* key, const char* value, void*) {
    if (!key || !value || !g_adapter.secure_set)
        return -1;
    return g_adapter.secure_set(key, value, g_adapter.user_data) == RAC_SUCCESS ? 0 : -1;
}

int auth_storage_retrieve(const char* key, char* out_value, size_t buffer_size, void*) {
    if (!key || !out_value || buffer_size == 0)
        return RAC_ERROR_INVALID_ARGUMENT;
    if (!g_adapter.secure_get)
        return RAC_ERROR_FILE_NOT_FOUND;
    char* stored = nullptr;
    const rac_result_t rc = g_adapter.secure_get(key, &stored, g_adapter.user_data);
    if (rc != RAC_SUCCESS || !stored) {
        if (stored)
            rac_free(stored);
        return rc == RAC_ERROR_FILE_NOT_FOUND ? RAC_ERROR_FILE_NOT_FOUND
                                              : RAC_ERROR_SECURE_STORAGE_FAILED;
    }
    const size_t len = std::strlen(stored);
    if (len == 0) {
        rac_free(stored);
        return RAC_ERROR_SECURE_STORAGE_FAILED;  // an empty value is a corrupt one
    }
    if (len + 1 > buffer_size) {
        rac_free(stored);
        return RAC_ERROR_BUFFER_TOO_SMALL;
    }
    std::memcpy(out_value, stored, len + 1);
    rac_free(stored);
    return static_cast<int>(len);
}

int auth_storage_delete(const char* key, void*) {
    if (!key || !g_adapter.secure_delete)
        return -1;
    return g_adapter.secure_delete(key, g_adapter.user_data) == RAC_SUCCESS ? 0 : -1;
}

// Commons flushes on batch size and on a five-second timeout, but that timeout
// is only evaluated when the next event arrives — a queue that goes quiet holds
// its events until shutdown, and a crash loses them. This thread is the wall
// clock commons does not have.
constexpr std::chrono::seconds kTelemetryFlushInterval{30};
std::thread g_telemetry_flush_thread;
std::condition_variable g_telemetry_flush_cv;
std::mutex g_telemetry_flush_mutex;
bool g_telemetry_flush_stop = false;

void telemetry_flush_thread_start() {
    if (g_telemetry_flush_thread.joinable())
        return;
    {
        std::lock_guard<std::mutex> lock(g_telemetry_flush_mutex);
        g_telemetry_flush_stop = false;
    }
    g_telemetry_flush_thread = std::thread([]() {
        for (;;) {
            std::unique_lock<std::mutex> lock(g_telemetry_flush_mutex);
            if (g_telemetry_flush_cv.wait_for(lock, kTelemetryFlushInterval,
                                              [] { return g_telemetry_flush_stop; })) {
                return;
            }
            lock.unlock();
            rac_telemetry_manager_t* manager = nullptr;
            {
                std::lock_guard<std::mutex> handles(g_handles_mutex);
                manager = g_telemetry_manager;
            }
            if (manager)
                rac_telemetry_manager_flush(manager);
        }
    });
}

void telemetry_flush_thread_stop() {
    if (!g_telemetry_flush_thread.joinable())
        return;
    {
        std::lock_guard<std::mutex> lock(g_telemetry_flush_mutex);
        g_telemetry_flush_stop = true;
    }
    g_telemetry_flush_cv.notify_all();
    g_telemetry_flush_thread.join();
}

// Detach + destroy the telemetry manager. Flush first (while the transport is
// up) so the last batch is delivered; then detach the sink so no shutdown-time
// event routes to a torn-down transport.
void telemetry_teardown_flush() {
    std::lock_guard<std::mutex> lock(g_handles_mutex);
    if (g_telemetry_manager)
        rac_events_flush_telemetry_sink();
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

// devicePersistentId(): the persistent per-device UUID commons mints.
Napi::Value DevicePersistentId(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    char device_id[RAC_DEVICE_ID_BUFFER_MIN_SIZE] = {};
    if (rac_device_get_or_create_persistent_id(device_id, sizeof(device_id)) != RAC_SUCCESS) {
        return Napi::String::New(env, "");
    }
    return Napi::String::New(env, device_id);
}

// devStagingBaseUrl(): baked staging backend URL for keyless dev (empty if
// none).
Napi::Value DevStagingBaseUrl(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    const char* baked = rac_dev_config_get_staging_base_url();
    if (baked && rac_dev_config_is_usable_http_url(baked))
        return Napi::String::New(env, baked);
    return Napi::String::New(env, "");
}

// Runs transport-register + state seed + telemetry sink + two-phase init off
// the JS thread; resolves with the serialized SdkInitResult bytes.
class ControlPlaneWorker : public Napi::AsyncWorker {
   public:
    ControlPlaneWorker(Napi::Env env, int32_t environment, std::string api_key,
                       std::string base_url, std::string device_id, std::string platform,
                       std::string sdk_version, std::string sdk_binding, std::string app_identifier,
                       std::string app_name, std::string app_version, std::vector<uint8_t> phase1,
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
        const rac_result_t transport_rc = rac_desktop_http_transport_register();
        if (transport_rc != RAC_SUCCESS) {
            code_ = transport_rc;
            err_ = "desktop HTTP/device bootstrap failed: " + std::to_string(transport_rc);
            return;
        }

        // Runtime state first (auth/device/telemetry read env + creds from it),
        // then the copied SDK configuration + client info.
        rac_state_initialize(env, api_key_.c_str(), base_url_.c_str(), device_id_.c_str());

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

        // Auth persistence must be installed before phase 1: phase 1 writes the
        // API key and base URL through this same vtable.
        static const rac_secure_storage_t auth_storage = {auth_storage_store, auth_storage_retrieve,
                                                          auth_storage_delete, nullptr};
        rac_auth_init(&auth_storage);
        // Restore tokens from the previous run. A miss is first launch; anything
        // else is a real storage failure worth reporting, but not worth refusing
        // to start over — the handshake below just re-authenticates.
        const int load_rc = rac_auth_load_stored_tokens();
        if (load_rc != RAC_SUCCESS && load_rc != RAC_ERROR_FILE_NOT_FOUND) {
            RAC_LOG_WARNING("Electron", "stored auth tokens unreadable (%d); re-authenticating",
                            load_rc);
        }

        {
            std::lock_guard<std::mutex> lock(g_handles_mutex);
            if (!g_telemetry_manager) {
                g_telemetry_manager = rac_telemetry_manager_create(
                    env, device_id_.c_str(), platform_.c_str(), sdk_version_.c_str());
                if (g_telemetry_manager) {
                    rac_telemetry_manager_set_device_info(
                        g_telemetry_manager, rac_desktop_device_model(), rac_desktop_os_version());
                    rac_telemetry_manager_set_http_callback(
                        g_telemetry_manager, electron_telemetry_http_callback, g_telemetry_manager);
                    rac_events_set_telemetry_sink(g_telemetry_manager);
                }
            }
        }
        telemetry_flush_thread_start();

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
        if (p2out.data && p2out.size > 0) {
            result_.assign(p2out.data, p2out.data + p2out.size);
        }
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

// configureControlPlane(env, apiKey, baseUrl, deviceId, platform, sdkVersion,
//   sdkBinding, appIdentifier, appName, appVersion, phase1Bytes, phase2Bytes)
//   -> Promise<Buffer>  (serialized SdkInitResult)
Napi::Value ConfigureControlPlane(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    if (!g_initialized.load()) {
        Napi::Error::New(env, "not initialized").ThrowAsJavaScriptException();
        return env.Undefined();
    }
    if (info.Length() < 12 || !info[0].IsNumber() || !info[10].IsTypedArray() ||
        !info[11].IsTypedArray()) {
        Napi::TypeError::New(env,
                             "configureControlPlane(env, apiKey, baseUrl, deviceId, platform, "
                             "sdkVersion, sdkBinding, appIdentifier, appName, appVersion, "
                             "phase1Bytes, phase2Bytes) bad args")
            .ThrowAsJavaScriptException();
        return env.Undefined();
    }
    auto str = [&](int i) {
        return info[i].IsString() ? info[i].As<Napi::String>().Utf8Value() : std::string();
    };
    Napi::Uint8Array p1 = info[10].As<Napi::Uint8Array>();
    Napi::Uint8Array p2 = info[11].As<Napi::Uint8Array>();
    std::vector<uint8_t> phase1(p1.Data(), p1.Data() + p1.ByteLength());
    std::vector<uint8_t> phase2(p2.Data(), p2.Data() + p2.ByteLength());

    auto* worker = new ControlPlaneWorker(env, info[0].As<Napi::Number>().Int32Value(), str(1),
                                          str(2), str(3), str(4), str(5), str(6), str(7), str(8),
                                          str(9), std::move(phase1), std::move(phase2));
    Napi::Promise promise = worker->Promise();
    worker->Queue();
    return promise;
}

// retryControlPlane() -> Promise<Buffer> (serialized SdkInitResult).
//
// The recovery path for a run that started offline: commons re-runs the auth
// handshake using the api key and base URL it already cached, then flushes the
// telemetry queued during the offline window. Idempotent — an authenticated
// process gets the fast path with no network round-trip.
Napi::Value RetryControlPlane(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    if (!g_initialized.load()) {
        Napi::Error::New(env, "not initialized").ThrowAsJavaScriptException();
        return env.Undefined();
    }
    return rac_electron::RunProtoCall(env, "sdk_retry_http", [](rac_proto_buffer_t* out) {
        return rac_sdk_retry_http_proto(out);
    });
}

// telemetryFlush() -> Promise<void>. Drains the queue through the same HTTP
// callback the periodic thread uses; commons keeps a failed batch in its retry
// queue rather than dropping it.
Napi::Value TelemetryFlush(const Napi::CallbackInfo& info) {
    return RunNativeCall(info.Env(), "telemetry_flush", []() -> rac_result_t {
        rac_telemetry_manager_t* manager = nullptr;
        {
            std::lock_guard<std::mutex> lock(g_handles_mutex);
            manager = g_telemetry_manager;
        }
        if (!manager)
            return RAC_SUCCESS;  // no control plane configured; nothing queued
        rac_telemetry_manager_flush(manager);
        return RAC_SUCCESS;
    });
}

// authState() -> { authenticated, needsRefresh, expiresAtUnixSec, userId,
//   organizationId, deviceRegistered }. Every field is read straight out of the
// auth manager and rac_state, so an app can tell an authenticated run from an
// offline one instead of guessing. Synchronous: these are in-memory reads.
Napi::Value AuthState(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    Napi::Object out = Napi::Object::New(env);
    auto text = [&](const char* value) { return Napi::String::New(env, value ? value : ""); };
    out.Set("authenticated", Napi::Boolean::New(env, rac_auth_is_authenticated()));
    out.Set("needsRefresh", Napi::Boolean::New(env, rac_auth_needs_refresh()));
    out.Set("expiresAtUnixSec",
            Napi::Number::New(env, static_cast<double>(rac_auth_get_token_expires_at())));
    out.Set("userId", text(rac_auth_get_user_id()));
    out.Set("organizationId", text(rac_auth_get_organization_id()));
    out.Set("deviceRegistered",
            Napi::Boolean::New(env, rac_device_manager_is_registered() == RAC_TRUE));
    return out;
}

// clearAuth() -> Promise<void>. Drops the tokens in memory and in the secure
// store, so the next initialize() authenticates from scratch.
Napi::Value ClearAuth(const Napi::CallbackInfo& info) {
    return RunNativeCall(info.Env(), "auth_clear", []() { return rac_auth_clear(); });
}
#endif  // RAC_ELECTRON_HAVE_DESKTOP

// =============================================================================
// Streaming core — shared by LLM generate + VLM process (both stream a char*
// token trio and block their calling thread, so we drive them on a worker
// thread and marshal tokens to JS via a bounded ThreadSafeFunction).
// =============================================================================
// Metrics copied out of the engine's completion callback. The rac_*_result_t
// the callback receives is only valid for the duration of the call, so every
// field is copied by value here and handed to JS from the TSFN finalizer.
struct StreamMetrics {
    bool present = false;
    int32_t prompt_tokens = 0;
    int32_t completion_tokens = 0;
    int32_t total_tokens = 0;
    int64_t time_to_first_token_ms = 0;
    int64_t total_time_ms = 0;
    float tokens_per_second = 0.0f;
};

struct StreamCtx {
    Napi::ThreadSafeFunction tsfn;
    std::thread worker;
    Napi::Promise::Deferred deferred;
    rac_result_t result = RAC_SUCCESS;
    std::string error_msg;
    std::function<rac_result_t(StreamCtx*)> run;  // performs the rac streaming call
    int32_t lease_id = 0;                         // begin_op id; end_op when the worker finishes
    bool leased = false;
    std::shared_ptr<std::mutex> gate;  // held for the whole stream (see g_op_gates)
    StreamMetrics metrics;
    explicit StreamCtx(Napi::Env env) : deferred(Napi::Promise::Deferred::New(env)) {}
};

bool is_cancellation(rac_result_t code) {
    return code == RAC_ERROR_CANCELLED || code == RAC_ERROR_GENERATION_CANCELLED ||
           code == RAC_ERROR_STREAM_CANCELLED;
}

Napi::Object metrics_to_js(Napi::Env env, const StreamMetrics& m, bool cancelled) {
    Napi::Object out = Napi::Object::New(env);
    out.Set("cancelled", Napi::Boolean::New(env, cancelled));
    out.Set("hasMetrics", Napi::Boolean::New(env, m.present));
    out.Set("inputTokens", Napi::Number::New(env, m.prompt_tokens));
    out.Set("outputTokens", Napi::Number::New(env, m.completion_tokens));
    out.Set("totalTokens", Napi::Number::New(env, m.total_tokens));
    out.Set("timeToFirstTokenMs",
            Napi::Number::New(env, static_cast<double>(m.time_to_first_token_ms)));
    out.Set("totalTimeMs", Napi::Number::New(env, static_cast<double>(m.total_time_ms)));
    out.Set("tokensPerSecond", Napi::Number::New(env, m.tokens_per_second));
    return out;
}

rac_bool_t stream_token_cb(const char* token, void* ud) {
    auto* ctx = static_cast<StreamCtx*>(ud);
    std::string tok = token ? token : "";  // copy out — the buffer is transient
    napi_status st = ctx->tsfn.BlockingCall([tok](Napi::Env env, Napi::Function jsCb) {
        jsCb.Call({Napi::String::New(env, tok)});  // JS values built on the JS thread
    });
    return (st == napi_ok) ? RAC_TRUE : RAC_FALSE;  // napi_closing -> stop
}

void stream_error_cb(rac_result_t code, const char* msg, void* ud) {
    auto* ctx = static_cast<StreamCtx*>(ud);
    ctx->result = code;
    // Keep a parseable "… failed: <code>" form for asSDKException / raiseForRac.
    if (msg && msg[0]) {
        ctx->error_msg = std::string(msg) + " failed: " + std::to_string(code);
    } else {
        ctx->error_msg = "stream failed: " + std::to_string(code);
    }
}

void stream_llm_complete_cb(const rac_llm_result_t* r, void* ud) {
    auto* ctx = static_cast<StreamCtx*>(ud);
    ctx->result = RAC_SUCCESS;
    if (!r)
        return;
    ctx->metrics.present = true;
    ctx->metrics.prompt_tokens = r->prompt_tokens;
    ctx->metrics.completion_tokens = r->completion_tokens;
    ctx->metrics.total_tokens = r->total_tokens;
    ctx->metrics.time_to_first_token_ms = r->time_to_first_token_ms;
    ctx->metrics.total_time_ms = r->total_time_ms;
    ctx->metrics.tokens_per_second = r->tokens_per_second;
}

void stream_vlm_complete_cb(const rac_vlm_result_t* r, void* ud) {
    auto* ctx = static_cast<StreamCtx*>(ud);
    ctx->result = RAC_SUCCESS;
    if (!r)
        return;
    ctx->metrics.present = true;
    ctx->metrics.prompt_tokens = r->prompt_tokens;
    ctx->metrics.completion_tokens = r->completion_tokens;
    ctx->metrics.total_tokens = r->total_tokens;
    ctx->metrics.time_to_first_token_ms = r->time_to_first_token_ms;
    ctx->metrics.total_time_ms = r->total_time_ms;
    ctx->metrics.tokens_per_second = r->tokens_per_second;
}

// Create the TSFN + worker thread; resolve/reject the returned Promise in the
// finalizer (JS loop, after the producer thread Release()d).
// When lease_id != 0, the caller already took the in-flight lease; we end_op
// when the worker finishes (covers unload-during-generate). `gate` is that
// handle's serialisation mutex and is held for the whole stream.
Napi::Promise start_stream(Napi::Env env, Napi::Function on_token,
                           std::function<rac_result_t(StreamCtx*)> run, int32_t lease_id = 0,
                           std::shared_ptr<std::mutex> gate = nullptr) {
    auto* ctx = new StreamCtx(env);
    ctx->run = std::move(run);
    ctx->lease_id = lease_id;
    ctx->leased = lease_id != 0;
    ctx->gate = std::move(gate);
    try {
        ctx->tsfn = Napi::ThreadSafeFunction::New(
            env, on_token, "ra-stream", /*maxQueueSize*/ 256,
            /*initialThreadCount*/ 1, ctx,
            [](Napi::Env env, void* /*data*/, StreamCtx* c) {
                if (c->worker.joinable())
                    c->worker.join();
                // Safety net if the worker aborted before releasing the lease.
                if (c->leased) {
                    end_op(c->lease_id);
                    c->leased = false;
                }
                // A cancelled stream is a normal outcome (the consumer broke the
                // iterator), so it resolves with cancelled:true instead of
                // rejecting — callers get the partial text plus a CANCELLED
                // finishReason rather than an exception they must filter.
                if (c->result == RAC_SUCCESS || is_cancellation(c->result)) {
                    c->deferred.Resolve(metrics_to_js(env, c->metrics, is_cancellation(c->result)));
                } else {
                    std::string msg = c->error_msg.empty()
                                          ? ("stream failed: " + std::to_string(c->result))
                                          : c->error_msg;
                    c->deferred.Reject(make_rac_error(env, c->result, msg).Value());
                }
                delete c;
            },
            static_cast<void*>(nullptr));

        ctx->worker = std::thread([ctx]() {
            rac_result_t rc = RAC_SUCCESS;
            if (ctx->gate) {
                std::lock_guard<std::mutex> serialize(*ctx->gate);
                rc = ctx->run(ctx);
            } else {
                rc = ctx->run(ctx);
            }
            if (rc != RAC_SUCCESS && ctx->result == RAC_SUCCESS)
                ctx->result = rc;
            if (ctx->leased) {
                end_op(ctx->lease_id);
                ctx->leased = false;
            }
            ctx->tsfn.Release();  // last TSFN call from this thread -> finalizer on JS loop
        });
    } catch (...) {
        if (ctx->leased)
            end_op(ctx->lease_id);
        delete ctx;
        throw;
    }
    return ctx->deferred.Promise();
}

// =============================================================================
// LLM: loadModel / generate / unloadModel
// =============================================================================
Napi::Value LoadModel(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    if (!g_initialized.load()) {
        Napi::Error::New(env, "not initialized").ThrowAsJavaScriptException();
        return env.Undefined();
    }
    if (info.Length() < 1 || !info[0].IsString()) {
        Napi::TypeError::New(env, "loadModel(path) expects a string").ThrowAsJavaScriptException();
        return env.Undefined();
    }
    std::string path = info[0].As<Napi::String>().Utf8Value();
    std::string id =
        (info.Length() > 1 && info[1].IsString()) ? info[1].As<Napi::String>().Utf8Value() : path;
    std::string name =
        (info.Length() > 2 && info[2].IsString()) ? info[2].As<Napi::String>().Utf8Value() : id;

    // Optional load-time placement: rac_llm_config_t is the only pre-load knob
    // the component layer exposes (thread count and GPU offload live on the
    // llamacpp-direct API, which bypasses the plugin registry, so they are not
    // settable here). Read here, on the JS thread; applied on the worker.
    bool has_framework = false;
    int32_t framework = 0;
    bool has_context = false;
    int32_t context_length = 0;
    if (info.Length() > 3 && info[3].IsObject()) {
        Napi::Object cfg_obj = info[3].As<Napi::Object>();
        if (cfg_obj.Has("framework") && cfg_obj.Get("framework").IsNumber()) {
            framework = cfg_obj.Get("framework").As<Napi::Number>().Int32Value();
            has_framework = true;
        }
        if (cfg_obj.Has("contextLength") && cfg_obj.Get("contextLength").IsNumber()) {
            context_length = cfg_obj.Get("contextLength").As<Napi::Number>().Int32Value();
            has_context = true;
        }
    }

    auto slot = std::make_shared<int32_t>(0);
    return RunNativeCall(
        env, "load_model",
        [path, id, name, has_framework, framework, has_context, context_length,
         slot]() -> rac_result_t {
            rac_handle_t h = nullptr;
            rac_result_t rc = rac_llm_component_create(&h);
            if (rc != RAC_SUCCESS)
                return rc;
            if (has_framework || has_context) {
                rac_llm_config_t cfg = RAC_LLM_CONFIG_DEFAULT;
                cfg.model_id = id.c_str();
                if (has_framework)
                    cfg.preferred_framework = framework;
                if (has_context)
                    cfg.context_length = context_length;
                rc = rac_llm_component_configure(h, &cfg);
                if (rc != RAC_SUCCESS) {
                    rac_llm_component_destroy(h);
                    return rc;
                }
            }
            rc = rac_llm_component_load_model(h, path.c_str(), id.c_str(), name.c_str());
            if (rc != RAC_SUCCESS) {
                rac_llm_component_destroy(h);
                return rc;
            }
            std::lock_guard<std::mutex> lock(g_handles_mutex);
            *slot = g_next_handle_id++;
            g_llm_handles[*slot] = h;
            return RAC_SUCCESS;
        },
        [slot](Napi::Env e) { return Napi::Number::New(e, *slot); });
}

// Optional per-request generation options (from a JS object). Strings and
// string vectors are held by value so the pointers handed to rac_* stay valid
// for the whole streaming call, which runs on a worker thread.
struct GenOpts {
    bool has_max = false;
    int32_t max_tokens = 0;
    bool has_temp = false;
    float temperature = 0.0f;
    bool has_top_p = false;
    float top_p = 0.0f;
    bool has_top_k = false;
    int32_t top_k = 0;
    bool has_min_p = false;
    float min_p = 0.0f;
    bool has_frequency_penalty = false;
    float frequency_penalty = 0.0f;
    bool has_presence_penalty = false;
    float presence_penalty = 0.0f;
    bool has_repetition_penalty = false;
    float repetition_penalty = 0.0f;
    bool has_seed = false;
    int64_t seed = 0;
    bool has_threads = false;
    int32_t n_threads = 0;
    bool has_disable_thinking = false;
    bool disable_thinking = false;
    std::string system_prompt;
    std::string grammar;
    std::vector<std::string> stop_sequences;
    std::vector<std::string> history;
    // Pointer views over the vectors above; rebuilt by apply_*_opts because a
    // copy of this struct must not carry pointers into the source's storage.
    std::vector<const char*> stop_ptrs;
    std::vector<const char*> history_ptrs;
};

std::vector<std::string> parse_string_array(const Napi::Object& obj, const char* key) {
    std::vector<std::string> out;
    if (!obj.Has(key))
        return out;
    Napi::Value v = obj.Get(key);
    if (!v.IsArray())
        return out;
    Napi::Array arr = v.As<Napi::Array>();
    for (uint32_t i = 0; i < arr.Length(); ++i) {
        Napi::Value item = arr.Get(i);
        if (item.IsString())
            out.push_back(item.As<Napi::String>().Utf8Value());
    }
    return out;
}

GenOpts parse_gen_opts(const Napi::Value& v) {
    GenOpts o;
    if (!v.IsObject())
        return o;
    Napi::Object obj = v.As<Napi::Object>();
    if (obj.Has("maxTokens")) {
        o.max_tokens = obj.Get("maxTokens").ToNumber().Int32Value();
        o.has_max = true;
    }
    if (obj.Has("temperature")) {
        o.temperature = obj.Get("temperature").ToNumber().FloatValue();
        o.has_temp = true;
    }
    if (obj.Has("topP")) {
        o.top_p = obj.Get("topP").ToNumber().FloatValue();
        o.has_top_p = true;
    }
    if (obj.Has("topK")) {
        o.top_k = obj.Get("topK").ToNumber().Int32Value();
        o.has_top_k = true;
    }
    if (obj.Has("minP")) {
        o.min_p = obj.Get("minP").ToNumber().FloatValue();
        o.has_min_p = true;
    }
    if (obj.Has("frequencyPenalty")) {
        o.frequency_penalty = obj.Get("frequencyPenalty").ToNumber().FloatValue();
        o.has_frequency_penalty = true;
    }
    if (obj.Has("presencePenalty")) {
        o.presence_penalty = obj.Get("presencePenalty").ToNumber().FloatValue();
        o.has_presence_penalty = true;
    }
    if (obj.Has("repetitionPenalty")) {
        o.repetition_penalty = obj.Get("repetitionPenalty").ToNumber().FloatValue();
        o.has_repetition_penalty = true;
    }
    if (obj.Has("seed")) {
        o.seed = static_cast<int64_t>(obj.Get("seed").ToNumber().Int64Value());
        o.has_seed = true;
    }
    if (obj.Has("nThreads")) {
        o.n_threads = obj.Get("nThreads").ToNumber().Int32Value();
        o.has_threads = true;
    }
    if (obj.Has("disableThinking")) {
        o.disable_thinking = obj.Get("disableThinking").ToBoolean().Value();
        o.has_disable_thinking = true;
    }
    if (obj.Has("systemPrompt"))
        o.system_prompt = obj.Get("systemPrompt").ToString().Utf8Value();
    if (obj.Has("grammar"))
        o.grammar = obj.Get("grammar").ToString().Utf8Value();
    o.stop_sequences = parse_string_array(obj, "stopSequences");
    o.history = parse_string_array(obj, "history");
    return o;
}

void apply_gen_opts(rac_llm_options_t& opts, GenOpts& o) {
    if (o.has_max)
        opts.max_tokens = o.max_tokens;
    if (o.has_temp)
        opts.temperature = o.temperature;
    if (o.has_top_p)
        opts.top_p = o.top_p;
    if (o.has_top_k)
        opts.top_k = o.top_k;
    if (o.has_min_p)
        opts.min_p = o.min_p;
    if (o.has_frequency_penalty)
        opts.frequency_penalty = o.frequency_penalty;
    if (o.has_presence_penalty)
        opts.presence_penalty = o.presence_penalty;
    if (o.has_repetition_penalty)
        opts.repetition_penalty = o.repetition_penalty;
    if (o.has_seed)
        opts.seed = o.seed;
    if (o.has_threads)
        opts.n_threads = o.n_threads;
    if (o.has_disable_thinking)
        opts.disable_thinking = o.disable_thinking ? RAC_TRUE : RAC_FALSE;
    if (!o.system_prompt.empty())
        opts.system_prompt = o.system_prompt.c_str();
    if (!o.grammar.empty())
        opts.grammar = o.grammar.c_str();
    o.stop_ptrs.clear();
    for (const std::string& s : o.stop_sequences)
        o.stop_ptrs.push_back(s.c_str());
    if (!o.stop_ptrs.empty()) {
        opts.stop_sequences = o.stop_ptrs.data();
        opts.num_stop_sequences = o.stop_ptrs.size();
    }
    o.history_ptrs.clear();
    for (const std::string& s : o.history)
        o.history_ptrs.push_back(s.c_str());
    if (!o.history_ptrs.empty()) {
        opts.history = o.history_ptrs.data();
        opts.n_history = static_cast<int32_t>(o.history_ptrs.size());
    }
}

// The VLM sampler shares most knobs with the LLM one but has no grammar,
// frequency/presence penalty, or thinking toggle (see rac_vlm_options_t).
void apply_vlm_opts(rac_vlm_options_t& opts, GenOpts& o) {
    if (o.has_max)
        opts.max_tokens = o.max_tokens;
    if (o.has_temp)
        opts.temperature = o.temperature;
    if (o.has_top_p)
        opts.top_p = o.top_p;
    if (o.has_top_k)
        opts.top_k = o.top_k;
    if (o.has_min_p)
        opts.min_p = o.min_p;
    if (o.has_repetition_penalty)
        opts.repetition_penalty = o.repetition_penalty;
    if (o.has_seed)
        opts.seed = o.seed;
    if (o.has_threads)
        opts.n_threads = o.n_threads;
    if (!o.system_prompt.empty())
        opts.system_prompt = o.system_prompt.c_str();
    o.stop_ptrs.clear();
    for (const std::string& s : o.stop_sequences)
        o.stop_ptrs.push_back(s.c_str());
    if (!o.stop_ptrs.empty()) {
        opts.stop_sequences = o.stop_ptrs.data();
        opts.num_stop_sequences = o.stop_ptrs.size();
    }
}

// generate(handle, prompt, onToken) OR generate(handle, prompt, options,
// onToken).
Napi::Value Generate(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    if (info.Length() < 3 || !info[0].IsNumber() || !info[1].IsString()) {
        Napi::TypeError::New(env, "generate(handleId, prompt[, options], onToken) bad args")
            .ThrowAsJavaScriptException();
        return env.Undefined();
    }
    int32_t hid = info[0].As<Napi::Number>().Int32Value();
    rac_handle_t h = nullptr;
    std::shared_ptr<std::mutex> gate;
    if (!begin_worker_op(g_llm_handles, hid, &h, &gate)) {
        Napi::Error::New(env, "invalid handle").ThrowAsJavaScriptException();
        return env.Undefined();
    }
    std::string prompt = info[1].As<Napi::String>().Utf8Value();

    GenOpts o;
    Napi::Function on_token;
    if (info[2].IsFunction()) {
        on_token = info[2].As<Napi::Function>();
    } else {
        o = parse_gen_opts(info[2]);
        if (info.Length() < 4 || !info[3].IsFunction()) {
            end_op(hid);
            Napi::TypeError::New(env, "generate: onToken callback required")
                .ThrowAsJavaScriptException();
            return env.Undefined();
        }
        on_token = info[3].As<Napi::Function>();
    }

    try {
        return start_stream(
            env, on_token,
            [h, prompt, o](StreamCtx* c) mutable {
                rac_llm_options_t opts = RAC_LLM_OPTIONS_DEFAULT;
                apply_gen_opts(opts, o);
                return rac_llm_component_generate_stream(h, prompt.c_str(), &opts, stream_token_cb,
                                                         stream_llm_complete_cb, stream_error_cb,
                                                         c);
            },
            hid, gate);
    } catch (...) {
        end_op(hid);
        throw;
    }
}

// cancelGenerate(handleId) — asks the engine to stop the in-flight generation.
// Safe to call from the JS thread while a worker streams: it only sets a flag
// the engine polls, so it takes handle_for (no idle wait) rather than a lease.
Napi::Value CancelGenerate(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    if (info.Length() < 1 || !info[0].IsNumber())
        return env.Undefined();
    rac_handle_t h = handle_for(g_llm_handles, info[0].As<Napi::Number>().Int32Value());
    if (h)
        rac_llm_component_cancel(h);
    return env.Undefined();
}

// Unload runs on a worker because take_handle_when_idle() waits for in-flight
// generation to finish — up to kTakeHandleIdleTimeout. Every unload below is
// async for the same reason.
Napi::Value UnloadModel(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    if (info.Length() < 1 || !info[0].IsNumber()) {
        return RunNativeCall(env, "unload_model", []() { return RAC_SUCCESS; });
    }
    int32_t hid = info[0].As<Napi::Number>().Int32Value();
    return RunNativeCall(env, "unload_model", [hid]() {
        rac_handle_t h = take_handle_when_idle(g_llm_handles, hid);
        if (h)
            rac_llm_component_destroy(h);
        std::lock_guard<std::mutex> lock(g_handles_mutex);
        g_lora_applied.erase(hid);
        return RAC_SUCCESS;
    });
}

// =============================================================================
// LoRA adapters on a loaded LLM (rac_llm_component_{load,remove,clear}_lora).
// The C ABI has no read-back, so the applied set is mirrored here for loraList.
// =============================================================================
Napi::Value LoraApply(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    if (info.Length() < 2 || !info[0].IsNumber() || !info[1].IsString()) {
        Napi::TypeError::New(env, "loraApply(handleId, adapterPath[, scale]) bad args")
            .ThrowAsJavaScriptException();
        return env.Undefined();
    }
    int32_t hid = info[0].As<Napi::Number>().Int32Value();
    rac_handle_t h = nullptr;
    std::shared_ptr<std::mutex> gate;
    if (!begin_worker_op(g_llm_handles, hid, &h, &gate)) {
        Napi::Error::New(env, "invalid handle").ThrowAsJavaScriptException();
        return env.Undefined();
    }
    std::string path = info[1].As<Napi::String>().Utf8Value();
    float scale =
        (info.Length() > 2 && info[2].IsNumber()) ? info[2].As<Napi::Number>().FloatValue() : 1.0f;
    return RunNativeCall(
        env, "lora apply",
        [h, gate, hid, path, scale]() {
            std::lock_guard<std::mutex> serialize(*gate);
            rac_result_t rc = rac_llm_component_load_lora(h, path.c_str(), scale);
            if (rc != RAC_SUCCESS)
                return rc;
            std::lock_guard<std::mutex> lock(g_handles_mutex);
            auto& applied = g_lora_applied[hid];
            for (auto& entry : applied) {
                if (entry.first == path) {
                    entry.second = scale;
                    return RAC_SUCCESS;
                }
            }
            applied.emplace_back(path, scale);
            return RAC_SUCCESS;
        },
        nullptr, [hid]() { end_op(hid); });
}

Napi::Value LoraRemove(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    if (info.Length() < 1 || !info[0].IsNumber()) {
        Napi::TypeError::New(env, "loraRemove(handleId[, adapterPath]) bad args")
            .ThrowAsJavaScriptException();
        return env.Undefined();
    }
    int32_t hid = info[0].As<Napi::Number>().Int32Value();
    rac_handle_t h = nullptr;
    std::shared_ptr<std::mutex> gate;
    if (!begin_worker_op(g_llm_handles, hid, &h, &gate)) {
        Napi::Error::New(env, "invalid handle").ThrowAsJavaScriptException();
        return env.Undefined();
    }
    const bool all = info.Length() < 2 || !info[1].IsString();
    std::string path = all ? std::string() : info[1].As<Napi::String>().Utf8Value();
    return RunNativeCall(
        env, "lora remove",
        [h, gate, hid, all, path]() {
            std::lock_guard<std::mutex> serialize(*gate);
            rac_result_t rc = all ? rac_llm_component_clear_lora(h)
                                  : rac_llm_component_remove_lora(h, path.c_str());
            if (rc != RAC_SUCCESS)
                return rc;
            std::lock_guard<std::mutex> lock(g_handles_mutex);
            if (all) {
                g_lora_applied.erase(hid);
                return RAC_SUCCESS;
            }
            auto& applied = g_lora_applied[hid];
            for (auto it = applied.begin(); it != applied.end(); ++it) {
                if (it->first == path) {
                    applied.erase(it);
                    break;
                }
            }
            return RAC_SUCCESS;
        },
        nullptr, [hid]() { end_op(hid); });
}

// loraList(handleId) -> [{ id, scale }] for the adapters applied to that
// handle.
Napi::Value LoraList(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    std::vector<std::pair<std::string, float>> applied;
    if (info.Length() >= 1 && info[0].IsNumber()) {
        std::lock_guard<std::mutex> lock(g_handles_mutex);
        auto it = g_lora_applied.find(info[0].As<Napi::Number>().Int32Value());
        if (it != g_lora_applied.end())
            applied = it->second;
    }
    Napi::Array out = Napi::Array::New(env, applied.size());
    for (size_t i = 0; i < applied.size(); ++i) {
        Napi::Object entry = Napi::Object::New(env);
        entry.Set("id", Napi::String::New(env, applied[i].first));
        entry.Set("scale", Napi::Number::New(env, applied[i].second));
        out.Set(static_cast<uint32_t>(i), entry);
    }
    return out;
}

// =============================================================================
// VLM: loadVlmModel / generateVlm / unloadVlmModel
// =============================================================================
Napi::Value LoadVlmModel(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    if (!g_initialized.load()) {
        Napi::Error::New(env, "not initialized").ThrowAsJavaScriptException();
        return env.Undefined();
    }
    if (info.Length() < 2 || !info[0].IsString() || !info[1].IsString()) {
        Napi::TypeError::New(env, "loadVlmModel(modelPath, mmprojPath[, id, name]) expects strings")
            .ThrowAsJavaScriptException();
        return env.Undefined();
    }
    std::string model = info[0].As<Napi::String>().Utf8Value();
    std::string mmproj = info[1].As<Napi::String>().Utf8Value();
    std::string id =
        (info.Length() > 2 && info[2].IsString()) ? info[2].As<Napi::String>().Utf8Value() : model;
    std::string name =
        (info.Length() > 3 && info[3].IsString()) ? info[3].As<Napi::String>().Utf8Value() : id;

    auto slot = std::make_shared<int32_t>(0);
    return RunNativeCall(
        env, "vlm load_model",
        [model, mmproj, id, name, slot]() -> rac_result_t {
            rac_handle_t h = nullptr;
            rac_result_t rc = rac_vlm_component_create(&h);
            if (rc != RAC_SUCCESS)
                return rc;
            rc = rac_vlm_component_load_model(h, model.c_str(), mmproj.c_str(), id.c_str(),
                                              name.c_str());
            if (rc != RAC_SUCCESS) {
                rac_vlm_component_destroy(h);
                return rc;
            }
            std::lock_guard<std::mutex> lock(g_handles_mutex);
            *slot = g_next_handle_id++;
            g_vlm_handles[*slot] = h;
            return RAC_SUCCESS;
        },
        [slot](Napi::Env e) { return Napi::Number::New(e, *slot); });
}

// One image, owned by value so it survives on the worker thread. Mirrors the
// three rac_vlm_image_format_t variants: a file path, raw RGB pixels, or base64
// bytes.
struct VlmImage {
    rac_vlm_image_format_t format = RAC_VLM_IMAGE_FORMAT_FILE_PATH;
    std::string file_path;
    std::string base64;
    std::vector<uint8_t> pixels;
    int32_t width = 0;
    int32_t height = 0;
};

// Accepts a plain path string (the historical shape) or
// { path } | { base64 } | { rgb: Uint8Array, width, height }.
bool parse_vlm_image(Napi::Env env, const Napi::Value& v, VlmImage* out) {
    if (v.IsString()) {
        out->format = RAC_VLM_IMAGE_FORMAT_FILE_PATH;
        out->file_path = v.As<Napi::String>().Utf8Value();
        return true;
    }
    if (!v.IsObject()) {
        Napi::TypeError::New(env,
                             "vlm image must be a path, { path }, { base64 }, "
                             "or { rgb, width, height }")
            .ThrowAsJavaScriptException();
        return false;
    }
    Napi::Object obj = v.As<Napi::Object>();
    if (obj.Has("path") && obj.Get("path").IsString()) {
        out->format = RAC_VLM_IMAGE_FORMAT_FILE_PATH;
        out->file_path = obj.Get("path").As<Napi::String>().Utf8Value();
        return true;
    }
    if (obj.Has("base64") && obj.Get("base64").IsString()) {
        out->format = RAC_VLM_IMAGE_FORMAT_BASE64;
        out->base64 = obj.Get("base64").As<Napi::String>().Utf8Value();
        return true;
    }
    if (obj.Has("rgb") && (obj.Get("rgb").IsTypedArray() || obj.Get("rgb").IsBuffer())) {
        Napi::Value raw = obj.Get("rgb");
        const uint8_t* data = nullptr;
        size_t len = 0;
        if (raw.IsBuffer()) {
            Napi::Buffer<uint8_t> buf = raw.As<Napi::Buffer<uint8_t>>();
            data = buf.Data();
            len = buf.Length();
        } else {
            Napi::TypedArray ta = raw.As<Napi::TypedArray>();
            data = static_cast<uint8_t*>(ta.ArrayBuffer().Data()) + ta.ByteOffset();
            len = ta.ByteLength();
        }
        out->format = RAC_VLM_IMAGE_FORMAT_RGB_PIXELS;
        out->pixels.assign(data, data + len);
        out->width = obj.Has("width") ? obj.Get("width").ToNumber().Int32Value() : 0;
        out->height = obj.Has("height") ? obj.Get("height").ToNumber().Int32Value() : 0;
        if (out->width <= 0 || out->height <= 0) {
            Napi::TypeError::New(env, "vlm raw RGB image needs positive width and height")
                .ThrowAsJavaScriptException();
            return false;
        }
        return true;
    }
    Napi::TypeError::New(env, "vlm image must carry path, base64, or rgb+width+height")
        .ThrowAsJavaScriptException();
    return false;
}

// generateVlm(handleId, image, prompt, onToken) OR
// generateVlm(handleId, image, prompt, options, onToken).
Napi::Value GenerateVlm(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    if (info.Length() < 4 || !info[0].IsNumber() || !info[2].IsString()) {
        Napi::TypeError::New(env,
                             "generateVlm(handleId, image, prompt[, options], onToken) bad args")
            .ThrowAsJavaScriptException();
        return env.Undefined();
    }
    VlmImage image;
    if (!parse_vlm_image(env, info[1], &image))
        return env.Undefined();

    GenOpts o;
    Napi::Function on_token;
    if (info[3].IsFunction()) {
        on_token = info[3].As<Napi::Function>();
    } else {
        o = parse_gen_opts(info[3]);
        if (info.Length() < 5 || !info[4].IsFunction()) {
            Napi::TypeError::New(env, "generateVlm: onToken callback required")
                .ThrowAsJavaScriptException();
            return env.Undefined();
        }
        on_token = info[4].As<Napi::Function>();
    }

    int32_t hid = info[0].As<Napi::Number>().Int32Value();
    rac_handle_t h = nullptr;
    std::shared_ptr<std::mutex> gate;
    if (!begin_worker_op(g_vlm_handles, hid, &h, &gate)) {
        Napi::Error::New(env, "invalid vlm handle").ThrowAsJavaScriptException();
        return env.Undefined();
    }
    std::string prompt = info[2].As<Napi::String>().Utf8Value();
    try {
        return start_stream(
            env, on_token,
            [h, image, prompt, o](StreamCtx* c) mutable {
                rac_vlm_image_t img;
                std::memset(&img, 0, sizeof(img));
                img.format = image.format;
                switch (image.format) {
                    case RAC_VLM_IMAGE_FORMAT_FILE_PATH:
                        img.file_path = image.file_path.c_str();
                        break;
                    case RAC_VLM_IMAGE_FORMAT_BASE64:
                        img.base64_data = image.base64.c_str();
                        break;
                    case RAC_VLM_IMAGE_FORMAT_RGB_PIXELS:
                        img.pixel_data = image.pixels.data();
                        img.data_size = image.pixels.size();
                        img.width = image.width;
                        img.height = image.height;
                        break;
                }
                // Pass explicit defaults: NULL options leaves the VLM sampler config
                // (top_k / seed / ...) reading uninitialized memory, which can crash.
                rac_vlm_options_t opts = RAC_VLM_OPTIONS_DEFAULT;
                apply_vlm_opts(opts, o);
                return rac_vlm_component_process_stream(h, &img, prompt.c_str(), &opts,
                                                        stream_token_cb, stream_vlm_complete_cb,
                                                        stream_error_cb, c);
            },
            hid, gate);
    } catch (...) {
        end_op(hid);
        throw;
    }
}

Napi::Value CancelVlm(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    if (info.Length() < 1 || !info[0].IsNumber())
        return env.Undefined();
    rac_handle_t h = handle_for(g_vlm_handles, info[0].As<Napi::Number>().Int32Value());
    if (h)
        rac_vlm_component_cancel(h);
    return env.Undefined();
}

Napi::Value UnloadVlmModel(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    if (info.Length() < 1 || !info[0].IsNumber()) {
        return RunNativeCall(env, "vlm unload", []() { return RAC_SUCCESS; });
    }
    int32_t hid = info[0].As<Napi::Number>().Int32Value();
    return RunNativeCall(env, "vlm unload", [hid]() {
        rac_handle_t h = take_handle_when_idle(g_vlm_handles, hid);
        if (h)
            rac_vlm_component_destroy(h);
        return RAC_SUCCESS;
    });
}

// =============================================================================
// Embeddings: loadEmbeddingModel / embed / unloadEmbeddingModel  (ONNX engine)
// =============================================================================
Napi::Value LoadEmbeddingModel(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    if (!g_initialized.load()) {
        Napi::Error::New(env, "not initialized").ThrowAsJavaScriptException();
        return env.Undefined();
    }
    if (info.Length() < 1 || !info[0].IsString()) {
        Napi::TypeError::New(env, "loadEmbeddingModel(path[, configJson]) expects a string")
            .ThrowAsJavaScriptException();
        return env.Undefined();
    }
    std::string model = info[0].As<Napi::String>().Utf8Value();
    std::string config = (info.Length() > 1 && info[1].IsString())
                             ? info[1].As<Napi::String>().Utf8Value()
                             : std::string();
    auto slot = std::make_shared<int32_t>(0);
    return RunNativeCall(
        env, "embeddings create_service",
        [model, config, slot]() -> rac_result_t {
            rac_handle_t h = nullptr;
            rac_result_t rc = rac::embeddings::create_service(
                model.c_str(), config.empty() ? nullptr : config.c_str(), &h);
            if (rc != RAC_SUCCESS)
                return rc;
            std::lock_guard<std::mutex> lock(g_handles_mutex);
            *slot = g_next_handle_id++;
            g_embed_handles[*slot] = h;
            return RAC_SUCCESS;
        },
        [slot](Napi::Env e) { return Napi::Number::New(e, *slot); });
}

// Owns a rac_embeddings_result_t across the worker/JS-thread boundary: the work
// fills it, the result builder reads it, and the destructor frees it whichever
// side the call ended on.
struct EmbeddingsResultBox {
    rac_embeddings_result_t value;
    bool filled = false;

    EmbeddingsResultBox() { std::memset(&value, 0, sizeof(value)); }
    ~EmbeddingsResultBox() {
        if (filled)
            rac_embeddings_result_free(&value);
    }
    EmbeddingsResultBox(const EmbeddingsResultBox&) = delete;
    EmbeddingsResultBox& operator=(const EmbeddingsResultBox&) = delete;
};

Napi::Float32Array embedding_to_js(Napi::Env env, const rac_embedding_vector_t& embedding) {
    Napi::Float32Array arr = Napi::Float32Array::New(env, embedding.dimension);
    if (embedding.data && embedding.dimension) {
        std::memcpy(arr.Data(), embedding.data, embedding.dimension * sizeof(float));
    }
    return arr;
}

// normalize / pooling arrive as the rac_embeddings_{normalize,pooling}_t ints;
// -1 means "leave the model config's own default in place".
rac_embeddings_options_t parse_embed_opts(const Napi::Value& v) {
    rac_embeddings_options_t opts = RAC_EMBEDDINGS_OPTIONS_DEFAULT;
    if (!v.IsObject())
        return opts;
    Napi::Object obj = v.As<Napi::Object>();
    if (obj.Has("normalize"))
        opts.normalize = obj.Get("normalize").ToNumber().Int32Value();
    if (obj.Has("pooling"))
        opts.pooling = obj.Get("pooling").ToNumber().Int32Value();
    if (obj.Has("nThreads"))
        opts.n_threads = obj.Get("nThreads").ToNumber().Int32Value();
    if (obj.Has("truncate"))
        opts.truncate = obj.Get("truncate").ToNumber().Int32Value();
    if (obj.Has("batchSize"))
        opts.batch_size = obj.Get("batchSize").ToNumber().Int32Value();
    return opts;
}

Napi::Value Embed(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    if (info.Length() < 2 || !info[0].IsNumber() || !info[1].IsString()) {
        Napi::TypeError::New(env, "embed(handleId, text[, options]) bad args")
            .ThrowAsJavaScriptException();
        return env.Undefined();
    }
    int32_t hid = info[0].As<Napi::Number>().Int32Value();
    rac_handle_t h = nullptr;
    std::shared_ptr<std::mutex> gate;
    if (!begin_worker_op(g_embed_handles, hid, &h, &gate)) {
        Napi::Error::New(env, "invalid embedding handle").ThrowAsJavaScriptException();
        return env.Undefined();
    }
    std::string text = info[1].As<Napi::String>().Utf8Value();
    rac_embeddings_options_t opts = parse_embed_opts(info.Length() > 2 ? info[2] : env.Undefined());
    auto box = std::make_shared<EmbeddingsResultBox>();
    return RunNativeCall(
        env, "embed",
        [h, gate, text, opts, box]() {
            std::lock_guard<std::mutex> serialize(*gate);
            rac_embeddings_options_t local = opts;
            const rac_result_t rc = rac_embeddings_embed(h, text.c_str(), &local, &box->value);
            box->filled = rc == RAC_SUCCESS;
            if (rc != RAC_SUCCESS)
                return rc;
            if (box->value.num_embeddings == 0 || box->value.embeddings == nullptr ||
                box->value.embeddings[0].data == nullptr) {
                return RAC_ERROR_INFERENCE_FAILED;
            }
            return RAC_SUCCESS;
        },
        [box](Napi::Env e) { return embedding_to_js(e, box->value.embeddings[0]); },
        [hid]() { end_op(hid); });
}

// embedBatch(handleId, texts[], options?) -> Float32Array[] in input order.
Napi::Value EmbedBatch(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    if (info.Length() < 2 || !info[0].IsNumber() || !info[1].IsArray()) {
        Napi::TypeError::New(env, "embedBatch(handleId, texts[, options]) bad args")
            .ThrowAsJavaScriptException();
        return env.Undefined();
    }
    Napi::Array in = info[1].As<Napi::Array>();
    std::vector<std::string> texts;
    for (uint32_t i = 0; i < in.Length(); ++i)
        texts.push_back(in.Get(i).ToString().Utf8Value());
    if (texts.empty())
        return Napi::Array::New(env, 0);

    int32_t hid = info[0].As<Napi::Number>().Int32Value();
    rac_handle_t h = nullptr;
    std::shared_ptr<std::mutex> gate;
    if (!begin_worker_op(g_embed_handles, hid, &h, &gate)) {
        Napi::Error::New(env, "invalid embedding handle").ThrowAsJavaScriptException();
        return env.Undefined();
    }
    rac_embeddings_options_t opts = parse_embed_opts(info.Length() > 2 ? info[2] : env.Undefined());
    auto box = std::make_shared<EmbeddingsResultBox>();
    return RunNativeCall(
        env, "embed batch",
        [h, gate, texts, opts, box]() {
            std::lock_guard<std::mutex> serialize(*gate);
            std::vector<const char*> ptrs;
            ptrs.reserve(texts.size());
            for (const std::string& t : texts)
                ptrs.push_back(t.c_str());
            rac_embeddings_options_t local = opts;
            const rac_result_t rc =
                rac_embeddings_embed_batch(h, ptrs.data(), ptrs.size(), &local, &box->value);
            box->filled = rc == RAC_SUCCESS;
            return rc;
        },
        [box](Napi::Env e) {
            Napi::Array out = Napi::Array::New(e, box->value.num_embeddings);
            for (size_t i = 0; i < box->value.num_embeddings; ++i) {
                out.Set(static_cast<uint32_t>(i), embedding_to_js(e, box->value.embeddings[i]));
            }
            return out;
        },
        [hid]() { end_op(hid); });
}

Napi::Value UnloadEmbeddingModel(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    if (info.Length() < 1 || !info[0].IsNumber()) {
        return RunNativeCall(env, "embeddings unload", []() { return RAC_SUCCESS; });
    }
    int32_t hid = info[0].As<Napi::Number>().Int32Value();
    return RunNativeCall(env, "embeddings unload", [hid]() {
        rac_handle_t h = take_handle_when_idle(g_embed_handles, hid);
        if (h)
            rac_embeddings_destroy(h);
        return RAC_SUCCESS;
    });
}

// =============================================================================
// STT: loadSttModel / transcribe / unloadSttModel   (sherpa engine)
// =============================================================================
Napi::Value LoadSttModel(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    if (!g_initialized.load()) {
        Napi::Error::New(env, "not initialized").ThrowAsJavaScriptException();
        return env.Undefined();
    }
    if (info.Length() < 1 || !info[0].IsString()) {
        Napi::TypeError::New(env, "loadSttModel(modelDir[, id, name]) expects a string")
            .ThrowAsJavaScriptException();
        return env.Undefined();
    }
    std::string dir = info[0].As<Napi::String>().Utf8Value();
    std::string id =
        (info.Length() > 1 && info[1].IsString()) ? info[1].As<Napi::String>().Utf8Value() : dir;
    std::string name =
        (info.Length() > 2 && info[2].IsString()) ? info[2].As<Napi::String>().Utf8Value() : id;
    auto slot = std::make_shared<int32_t>(0);
    return RunNativeCall(
        env, "stt load_model",
        [dir, id, name, slot]() -> rac_result_t {
            rac_handle_t h = nullptr;
            rac_result_t rc = rac_stt_component_create(&h);
            if (rc != RAC_SUCCESS)
                return rc;
            rc = rac_stt_component_load_model(h, dir.c_str(), id.c_str(), name.c_str());
            if (rc != RAC_SUCCESS) {
                rac_stt_component_destroy(h);
                return rc;
            }
            std::lock_guard<std::mutex> lock(g_handles_mutex);
            *slot = g_next_handle_id++;
            g_stt_handles[*slot] = h;
            return RAC_SUCCESS;
        },
        [slot](Napi::Env e) { return Napi::Number::New(e, *slot); });
}

// Borrow the bytes of a Buffer or any TypedArray without copying.
bool byte_view(const Napi::Value& v, const uint8_t** out_data, size_t* out_len) {
    if (v.IsBuffer()) {
        Napi::Buffer<uint8_t> buf = v.As<Napi::Buffer<uint8_t>>();
        *out_data = buf.Data();
        *out_len = buf.Length();
        return true;
    }
    if (v.IsTypedArray()) {
        Napi::TypedArray ta = v.As<Napi::TypedArray>();
        *out_data = static_cast<uint8_t*>(ta.ArrayBuffer().Data()) + ta.ByteOffset();
        *out_len = ta.ByteLength();
        return true;
    }
    return false;
}

// Held by value so the strings outlive the JS call frame.
struct SttOpts {
    rac_stt_options_t opts = RAC_STT_OPTIONS_DEFAULT;
    std::string language;
};

SttOpts parse_stt_opts(const Napi::Value& v) {
    SttOpts s;
    if (!v.IsObject())
        return s;
    Napi::Object obj = v.As<Napi::Object>();
    if (obj.Has("language") && obj.Get("language").IsString()) {
        s.language = obj.Get("language").As<Napi::String>().Utf8Value();
        s.opts.language = s.language.c_str();
        s.opts.detect_language = RAC_FALSE;
    } else if (obj.Has("detectLanguage")) {
        s.opts.detect_language =
            obj.Get("detectLanguage").ToBoolean().Value() ? RAC_TRUE : RAC_FALSE;
    }
    if (obj.Has("punctuation")) {
        s.opts.enable_punctuation =
            obj.Get("punctuation").ToBoolean().Value() ? RAC_TRUE : RAC_FALSE;
    }
    if (obj.Has("wordTimestamps")) {
        s.opts.enable_timestamps =
            obj.Get("wordTimestamps").ToBoolean().Value() ? RAC_TRUE : RAC_FALSE;
    }
    if (obj.Has("diarization")) {
        s.opts.enable_diarization =
            obj.Get("diarization").ToBoolean().Value() ? RAC_TRUE : RAC_FALSE;
    }
    if (obj.Has("maxSpeakers"))
        s.opts.max_speakers = obj.Get("maxSpeakers").ToNumber().Int32Value();
    if (obj.Has("sampleRate"))
        s.opts.sample_rate = obj.Get("sampleRate").ToNumber().Int32Value();
    return s;
}

Napi::Object stt_result_to_js(Napi::Env env, const rac_stt_result_t& result) {
    Napi::Object out = Napi::Object::New(env);
    out.Set("text", Napi::String::New(env, result.text ? result.text : ""));
    if (result.detected_language && result.detected_language[0]) {
        out.Set("language", Napi::String::New(env, result.detected_language));
    }
    out.Set("confidence", Napi::Number::New(env, result.confidence));
    out.Set("processingTimeMs",
            Napi::Number::New(env, static_cast<double>(result.processing_time_ms)));
    Napi::Array words = Napi::Array::New(env, result.num_words);
    for (size_t i = 0; i < result.num_words; ++i) {
        const rac_stt_word_t& w = result.words[i];
        Napi::Object word = Napi::Object::New(env);
        word.Set("text", Napi::String::New(env, w.text ? w.text : ""));
        word.Set("startMs", Napi::Number::New(env, static_cast<double>(w.start_ms)));
        word.Set("endMs", Napi::Number::New(env, static_cast<double>(w.end_ms)));
        word.Set("confidence", Napi::Number::New(env, w.confidence));
        words.Set(static_cast<uint32_t>(i), word);
    }
    out.Set("words", words);
    return out;
}

struct SttResultBox {
    rac_stt_result_t value;
    bool filled = false;

    SttResultBox() { std::memset(&value, 0, sizeof(value)); }
    ~SttResultBox() {
        if (filled)
            rac_stt_result_free(&value);
    }
    SttResultBox(const SttResultBox&) = delete;
    SttResultBox& operator=(const SttResultBox&) = delete;
};

// transcribe(handleId, pcm16Bytes[, options]) -> { text, language?, confidence,
// words[] }. Audio = mono PCM16 bytes at options.sampleRate (16 kHz default).
// The decode runs on a worker; the audio is copied because the JS-owned bytes
// may be collected or resized before the worker reads them.
Napi::Value Transcribe(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    const uint8_t* pcm_data = nullptr;
    size_t pcm_len = 0;
    // Accept a Node Buffer OR any TypedArray (the public API + MessagePort clones
    // deliver a Uint8Array of PCM16 bytes, not necessarily a Buffer).
    if (info.Length() < 2 || !info[0].IsNumber() || !byte_view(info[1], &pcm_data, &pcm_len)) {
        Napi::TypeError::New(env, "transcribe(handleId, pcm16Bytes[, options]) bad args")
            .ThrowAsJavaScriptException();
        return env.Undefined();
    }
    int32_t hid = info[0].As<Napi::Number>().Int32Value();
    rac_handle_t h = nullptr;
    std::shared_ptr<std::mutex> gate;
    if (!begin_worker_op(g_stt_handles, hid, &h, &gate)) {
        Napi::Error::New(env, "invalid stt handle").ThrowAsJavaScriptException();
        return env.Undefined();
    }
    auto audio = std::make_shared<std::vector<uint8_t>>(pcm_data, pcm_data + pcm_len);
    auto opts =
        std::make_shared<SttOpts>(parse_stt_opts(info.Length() > 2 ? info[2] : env.Undefined()));
    // parse_stt_opts holds `language` by value; re-point after the struct copy.
    if (!opts->language.empty())
        opts->opts.language = opts->language.c_str();
    auto box = std::make_shared<SttResultBox>();
    return RunNativeCall(
        env, "transcribe",
        [h, gate, audio, opts, box]() {
            std::lock_guard<std::mutex> serialize(*gate);
            const rac_result_t rc = rac_stt_component_transcribe(h, audio->data(), audio->size(),
                                                                 &opts->opts, &box->value);
            box->filled = rc == RAC_SUCCESS;
            return rc;
        },
        [box](Napi::Env e) { return stt_result_to_js(e, box->value); }, [hid]() { end_op(hid); });
}

// transcribeStream(handleId, pcm16Bytes, options, onPartial) -> Promise<void>.
// The engine calls back with growing partial text; the terminal call has
// isFinal=true. Runs on a worker thread like generate().
struct SttStreamCtx {
    Napi::ThreadSafeFunction tsfn;
    std::thread worker;
    Napi::Promise::Deferred deferred;
    rac_result_t result = RAC_SUCCESS;
    int32_t lease_id = 0;
    bool leased = false;
    std::shared_ptr<std::mutex> gate;
    rac_handle_t handle = nullptr;
    std::vector<uint8_t> audio;
    SttOpts opts;
    explicit SttStreamCtx(Napi::Env env) : deferred(Napi::Promise::Deferred::New(env)) {}
};

void stt_stream_cb(const char* partial, rac_bool_t is_final, void* ud) {
    auto* ctx = static_cast<SttStreamCtx*>(ud);
    std::string text = partial ? partial : "";
    bool final_flag = is_final == RAC_TRUE;
    ctx->tsfn.BlockingCall([text, final_flag](Napi::Env env, Napi::Function cb) {
        Napi::Object ev = Napi::Object::New(env);
        ev.Set("text", Napi::String::New(env, text));
        ev.Set("isFinal", Napi::Boolean::New(env, final_flag));
        cb.Call({ev});
    });
}

Napi::Value TranscribeStream(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    const uint8_t* pcm_data = nullptr;
    size_t pcm_len = 0;
    if (info.Length() < 4 || !info[0].IsNumber() || !byte_view(info[1], &pcm_data, &pcm_len) ||
        !info[3].IsFunction()) {
        Napi::TypeError::New(env,
                             "transcribeStream(handleId, pcm16Bytes, options, onPartial) bad args")
            .ThrowAsJavaScriptException();
        return env.Undefined();
    }
    int32_t hid = info[0].As<Napi::Number>().Int32Value();
    rac_handle_t h = nullptr;
    std::shared_ptr<std::mutex> gate;
    if (!begin_worker_op(g_stt_handles, hid, &h, &gate)) {
        Napi::Error::New(env, "invalid stt handle").ThrowAsJavaScriptException();
        return env.Undefined();
    }
    auto* ctx = new SttStreamCtx(env);
    ctx->handle = h;
    ctx->lease_id = hid;
    ctx->leased = true;
    ctx->gate = gate;
    ctx->audio.assign(pcm_data, pcm_data + pcm_len);
    ctx->opts = parse_stt_opts(info[2]);
    // parse_stt_opts holds `language` by value; re-point after the struct copy.
    if (!ctx->opts.language.empty())
        ctx->opts.opts.language = ctx->opts.language.c_str();
    try {
        ctx->tsfn = Napi::ThreadSafeFunction::New(
            env, info[3].As<Napi::Function>(), "ra-stt-stream", 256, 1, ctx,
            [](Napi::Env env, void*, SttStreamCtx* c) {
                if (c->worker.joinable())
                    c->worker.join();
                if (c->leased) {
                    end_op(c->lease_id);
                    c->leased = false;
                }
                if (c->result == RAC_SUCCESS) {
                    c->deferred.Resolve(env.Undefined());
                } else {
                    c->deferred.Reject(
                        make_rac_error(env, c->result,
                                       "transcribe stream failed: " + std::to_string(c->result))
                            .Value());
                }
                delete c;
            },
            static_cast<void*>(nullptr));
        ctx->worker = std::thread([ctx]() {
            {
                std::lock_guard<std::mutex> serialize(*ctx->gate);
                ctx->result = rac_stt_component_transcribe_stream(
                    ctx->handle, ctx->audio.data(), ctx->audio.size(), &ctx->opts.opts,
                    stt_stream_cb, ctx);
            }
            if (ctx->leased) {
                end_op(ctx->lease_id);
                ctx->leased = false;
            }
            ctx->tsfn.Release();
        });
    } catch (...) {
        if (ctx->leased)
            end_op(hid);
        delete ctx;
        throw;
    }
    return ctx->deferred.Promise();
}

// sttInfo(handleId) -> { isReady, modelId, supportsStreaming, languages[] }.
Napi::Value SttInfo(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    Napi::Object out = Napi::Object::New(env);
    rac_handle_t h = (info.Length() >= 1 && info[0].IsNumber())
                         ? handle_for(g_stt_handles, info[0].As<Napi::Number>().Int32Value())
                         : nullptr;
    if (!h) {
        out.Set("isReady", Napi::Boolean::New(env, false));
        out.Set("supportsStreaming", Napi::Boolean::New(env, false));
        out.Set("languages", Napi::Array::New(env, 0));
        return out;
    }
    out.Set("isReady", Napi::Boolean::New(env, rac_stt_component_is_loaded(h) == RAC_TRUE));
    const char* model_id = rac_stt_component_get_model_id(h);
    if (model_id && model_id[0])
        out.Set("modelId", Napi::String::New(env, model_id));
    out.Set("supportsStreaming",
            Napi::Boolean::New(env, rac_stt_component_supports_streaming(h) == RAC_TRUE));
    // Commons returns the supported-language list as a JSON array string; hand it
    // through verbatim and let the TS layer parse it (no JSON parser in the
    // addon).
    char* langs = nullptr;
    if (rac_stt_component_get_supported_languages(h, &langs) == RAC_SUCCESS && langs) {
        out.Set("languagesJson", Napi::String::New(env, langs));
        rac_free(langs);
    }
    return out;
}

Napi::Value UnloadSttModel(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    if (info.Length() < 1 || !info[0].IsNumber()) {
        return RunNativeCall(env, "stt unload", []() { return RAC_SUCCESS; });
    }
    int32_t hid = info[0].As<Napi::Number>().Int32Value();
    return RunNativeCall(env, "stt unload", [hid]() {
        rac_handle_t h = take_handle_when_idle(g_stt_handles, hid);
        if (h)
            rac_stt_component_destroy(h);
        return RAC_SUCCESS;
    });
}

// =============================================================================
// TTS: loadTtsVoice / synthesize / unloadTtsVoice   (sherpa engine)
// =============================================================================
Napi::Value LoadTtsVoice(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    if (!g_initialized.load()) {
        Napi::Error::New(env, "not initialized").ThrowAsJavaScriptException();
        return env.Undefined();
    }
    if (info.Length() < 1 || !info[0].IsString()) {
        Napi::TypeError::New(env, "loadTtsVoice(voiceDir[, id, name]) expects a string")
            .ThrowAsJavaScriptException();
        return env.Undefined();
    }
    std::string dir = info[0].As<Napi::String>().Utf8Value();
    std::string id =
        (info.Length() > 1 && info[1].IsString()) ? info[1].As<Napi::String>().Utf8Value() : dir;
    std::string name =
        (info.Length() > 2 && info[2].IsString()) ? info[2].As<Napi::String>().Utf8Value() : id;
    auto slot = std::make_shared<int32_t>(0);
    return RunNativeCall(
        env, "tts load_voice",
        [dir, id, name, slot]() -> rac_result_t {
            rac_handle_t h = nullptr;
            rac_result_t rc = rac_tts_component_create(&h);
            if (rc != RAC_SUCCESS)
                return rc;
            rc = rac_tts_component_load_voice(h, dir.c_str(), id.c_str(), name.c_str());
            if (rc != RAC_SUCCESS) {
                rac_tts_component_destroy(h);
                return rc;
            }
            std::lock_guard<std::mutex> lock(g_handles_mutex);
            *slot = g_next_handle_id++;
            g_tts_handles[*slot] = h;
            return RAC_SUCCESS;
        },
        [slot](Napi::Env e) { return Napi::Number::New(e, *slot); });
}

// Held by value so voice/language outlive the JS call frame.
struct TtsOpts {
    rac_tts_options_t opts = RAC_TTS_OPTIONS_DEFAULT;
    std::string voice;
    std::string language;
};

TtsOpts parse_tts_opts(const Napi::Value& v) {
    TtsOpts t;
    if (!v.IsObject())
        return t;
    Napi::Object obj = v.As<Napi::Object>();
    if (obj.Has("voice") && obj.Get("voice").IsString()) {
        t.voice = obj.Get("voice").As<Napi::String>().Utf8Value();
        t.opts.voice = t.voice.c_str();
    }
    if (obj.Has("language") && obj.Get("language").IsString()) {
        t.language = obj.Get("language").As<Napi::String>().Utf8Value();
        t.opts.language = t.language.c_str();
    }
    // The spec calls it `speed`; rac_tts_options_t calls the same knob `rate`.
    if (obj.Has("speed"))
        t.opts.rate = obj.Get("speed").ToNumber().FloatValue();
    if (obj.Has("pitch"))
        t.opts.pitch = obj.Get("pitch").ToNumber().FloatValue();
    if (obj.Has("volume"))
        t.opts.volume = obj.Get("volume").ToNumber().FloatValue();
    if (obj.Has("audioFormat")) {
        t.opts.audio_format =
            static_cast<rac_audio_format_enum_t>(obj.Get("audioFormat").ToNumber().Int32Value());
    }
    if (obj.Has("sampleRate"))
        t.opts.sample_rate = obj.Get("sampleRate").ToNumber().Int32Value();
    return t;
}

struct TtsResultBox {
    rac_tts_result_t value;
    bool filled = false;

    TtsResultBox() { std::memset(&value, 0, sizeof(value)); }
    ~TtsResultBox() {
        if (filled)
            rac_tts_result_free(&value);
    }
    TtsResultBox(const TtsResultBox&) = delete;
    TtsResultBox& operator=(const TtsResultBox&) = delete;
};

// synthesize(handleId, text[, options]) ->
//   { sampleRate, samples: Float32Array, audioFormat, durationMs }.
Napi::Value Synthesize(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    if (info.Length() < 2 || !info[0].IsNumber() || !info[1].IsString()) {
        Napi::TypeError::New(env, "synthesize(handleId, text[, options]) bad args")
            .ThrowAsJavaScriptException();
        return env.Undefined();
    }
    int32_t hid = info[0].As<Napi::Number>().Int32Value();
    rac_handle_t h = nullptr;
    std::shared_ptr<std::mutex> gate;
    if (!begin_worker_op(g_tts_handles, hid, &h, &gate)) {
        Napi::Error::New(env, "invalid tts handle").ThrowAsJavaScriptException();
        return env.Undefined();
    }
    std::string text = info[1].As<Napi::String>().Utf8Value();
    auto opts =
        std::make_shared<TtsOpts>(parse_tts_opts(info.Length() > 2 ? info[2] : env.Undefined()));
    if (!opts->voice.empty())
        opts->opts.voice = opts->voice.c_str();
    if (!opts->language.empty())
        opts->opts.language = opts->language.c_str();
    auto box = std::make_shared<TtsResultBox>();
    return RunNativeCall(
        env, "synthesize",
        [h, gate, text, opts, box]() {
            std::lock_guard<std::mutex> serialize(*gate);
            const rac_result_t rc =
                rac_tts_component_synthesize(h, text.c_str(), &opts->opts, &box->value);
            box->filled = rc == RAC_SUCCESS;
            return rc;
        },
        [box](Napi::Env e) {
            const rac_tts_result_t& result = box->value;
            const size_t n = result.audio_size / sizeof(float);  // audio_data is float32 PCM
            Napi::Float32Array samples = Napi::Float32Array::New(e, n);
            if (result.audio_data && n) {
                std::memcpy(samples.Data(), result.audio_data, n * sizeof(float));
            }
            Napi::Object out = Napi::Object::New(e);
            out.Set("sampleRate", Napi::Number::New(e, result.sample_rate));
            out.Set("samples", samples);
            out.Set("audioFormat", Napi::Number::New(e, static_cast<int32_t>(result.audio_format)));
            out.Set("durationMs", Napi::Number::New(e, static_cast<double>(result.duration_ms)));
            return out;
        },
        [hid]() { end_op(hid); });
}

// synthesizeStream(handleId, text, options, onChunk) -> Promise<void>. onChunk
// receives { samples: Float32Array } per engine chunk, in order.
struct TtsStreamCtx {
    Napi::ThreadSafeFunction tsfn;
    std::thread worker;
    Napi::Promise::Deferred deferred;
    rac_result_t result = RAC_SUCCESS;
    int32_t lease_id = 0;
    bool leased = false;
    std::shared_ptr<std::mutex> gate;
    rac_handle_t handle = nullptr;
    std::string text;
    TtsOpts opts;
    explicit TtsStreamCtx(Napi::Env env) : deferred(Napi::Promise::Deferred::New(env)) {}
};

void tts_stream_cb(const void* audio, size_t bytes, void* ud) {
    auto* ctx = static_cast<TtsStreamCtx*>(ud);
    // Copy out: the engine's buffer is only valid for this callback.
    std::vector<float> chunk(bytes / sizeof(float));
    if (audio && !chunk.empty())
        std::memcpy(chunk.data(), audio, chunk.size() * sizeof(float));
    ctx->tsfn.BlockingCall([chunk](Napi::Env env, Napi::Function cb) {
        Napi::Float32Array arr = Napi::Float32Array::New(env, chunk.size());
        if (!chunk.empty())
            std::memcpy(arr.Data(), chunk.data(), chunk.size() * sizeof(float));
        Napi::Object ev = Napi::Object::New(env);
        ev.Set("samples", arr);
        cb.Call({ev});
    });
}

Napi::Value SynthesizeStream(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    if (info.Length() < 4 || !info[0].IsNumber() || !info[1].IsString() || !info[3].IsFunction()) {
        Napi::TypeError::New(env, "synthesizeStream(handleId, text, options, onChunk) bad args")
            .ThrowAsJavaScriptException();
        return env.Undefined();
    }
    int32_t hid = info[0].As<Napi::Number>().Int32Value();
    rac_handle_t h = nullptr;
    std::shared_ptr<std::mutex> gate;
    if (!begin_worker_op(g_tts_handles, hid, &h, &gate)) {
        Napi::Error::New(env, "invalid tts handle").ThrowAsJavaScriptException();
        return env.Undefined();
    }
    auto* ctx = new TtsStreamCtx(env);
    ctx->handle = h;
    ctx->lease_id = hid;
    ctx->leased = true;
    ctx->gate = gate;
    ctx->text = info[1].As<Napi::String>().Utf8Value();
    ctx->opts = parse_tts_opts(info[2]);
    if (!ctx->opts.voice.empty())
        ctx->opts.opts.voice = ctx->opts.voice.c_str();
    if (!ctx->opts.language.empty())
        ctx->opts.opts.language = ctx->opts.language.c_str();
    try {
        ctx->tsfn = Napi::ThreadSafeFunction::New(
            env, info[3].As<Napi::Function>(), "ra-tts-stream", 256, 1, ctx,
            [](Napi::Env env, void*, TtsStreamCtx* c) {
                if (c->worker.joinable())
                    c->worker.join();
                if (c->leased) {
                    end_op(c->lease_id);
                    c->leased = false;
                }
                if (c->result == RAC_SUCCESS) {
                    c->deferred.Resolve(env.Undefined());
                } else {
                    c->deferred.Reject(
                        make_rac_error(env, c->result,
                                       "synthesize stream failed: " + std::to_string(c->result))
                            .Value());
                }
                delete c;
            },
            static_cast<void*>(nullptr));
        ctx->worker = std::thread([ctx]() {
            {
                std::lock_guard<std::mutex> serialize(*ctx->gate);
                ctx->result = rac_tts_component_synthesize_stream(
                    ctx->handle, ctx->text.c_str(), &ctx->opts.opts, tts_stream_cb, ctx);
            }
            if (ctx->leased) {
                end_op(ctx->lease_id);
                ctx->leased = false;
            }
            ctx->tsfn.Release();
        });
    } catch (...) {
        if (ctx->leased)
            end_op(hid);
        delete ctx;
        throw;
    }
    return ctx->deferred.Promise();
}

// ttsStop(handleId) — stops playback and any in-flight synthesis.
Napi::Value TtsStop(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    if (info.Length() < 1 || !info[0].IsNumber())
        return env.Undefined();
    rac_handle_t h = handle_for(g_tts_handles, info[0].As<Napi::Number>().Int32Value());
    if (h)
        rac_tts_component_stop(h);
    return env.Undefined();
}

// ttsInfo(handleId) -> { voiceId?, languagesJson? } for tts.voices().
Napi::Value TtsInfo(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    Napi::Object out = Napi::Object::New(env);
    rac_handle_t h = (info.Length() >= 1 && info[0].IsNumber())
                         ? handle_for(g_tts_handles, info[0].As<Napi::Number>().Int32Value())
                         : nullptr;
    if (!h)
        return out;
    const char* voice = rac_tts_component_get_voice_id(h);
    if (voice && voice[0])
        out.Set("voiceId", Napi::String::New(env, voice));
    char* langs = nullptr;
    if (rac_tts_component_get_supported_languages(h, &langs) == RAC_SUCCESS && langs) {
        out.Set("languagesJson", Napi::String::New(env, langs));
        rac_free(langs);
    }
    return out;
}

Napi::Value UnloadTtsVoice(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    if (info.Length() < 1 || !info[0].IsNumber()) {
        return RunNativeCall(env, "tts unload", []() { return RAC_SUCCESS; });
    }
    int32_t hid = info[0].As<Napi::Number>().Int32Value();
    return RunNativeCall(env, "tts unload", [hid]() {
        rac_handle_t h = take_handle_when_idle(g_tts_handles, hid);
        if (h)
            rac_tts_component_destroy(h);
        return RAC_SUCCESS;
    });
}

// =============================================================================
// shutdown()
// =============================================================================
Napi::Value Shutdown(const Napi::CallbackInfo& info) {
    return RunNativeCall(info.Env(), "rac_shutdown", []() -> rac_result_t {
        if (g_initialized.exchange(false)) {
            // Drop the download progress callback and the storage analyzer before
            // anything else: commons must not hold a pointer into this addon once
            // the runtime starts tearing down.
            rac_electron::ShutdownDownloadBridge();
            // Same reason: commons keeps calling the adapter's log slot right
            // through rac_shutdown(), so the JS subscriber has to go first.
            rac_electron::ShutdownLoggingBridge();
            // Destroy every still-loaded component and clear the handle maps so no id
            // outlives the runtime — a later unload/use can't touch freed native
            // state, and a re-init starts from a clean slate.
            {
                // Wait for every in-flight blocking op to drain before freeing its
                // component — otherwise destroy / rac_shutdown() could race a live
                // rac_* call on a worker thread (use-after-free).
                std::unique_lock<std::mutex> lock(g_handles_mutex);
                g_inflight_cv.wait(lock, [] {
                    for (auto& kv : g_inflight) {
                        if (kv.second > 0)
                            return false;
                    }
                    return true;
                });
#ifdef RAC_ELECTRON_HAVE_RAG
                // Without the RAG pipeline no session can ever have been created,
                // so the map is empty and there is nothing to destroy — but the
                // destroy symbol itself would not exist to link against.
                for (auto& kv : g_rag_handles)
                    rac_rag_session_destroy_proto(kv.second);
#endif
                for (auto& kv : g_llm_handles)
                    rac_llm_component_destroy(kv.second);
                for (auto& kv : g_vlm_handles)
                    rac_vlm_component_destroy(kv.second);
                for (auto& kv : g_embed_handles)
                    rac_embeddings_destroy(kv.second);
                for (auto& kv : g_stt_handles)
                    rac_stt_component_destroy(kv.second);
                for (auto& kv : g_tts_handles)
                    rac_tts_component_destroy(kv.second);
                for (auto& kv : g_vad_handles)
                    rac_vad_component_destroy(kv.second);
                for (auto& kv : g_rerank_handles) {
                    rac_rerank_cleanup(kv.second);
                    rac_rerank_destroy(kv.second);
                }
                for (auto& kv : g_diar_handles) {
                    rac_diarization_cleanup(kv.second);
                    rac_diarization_destroy(kv.second);
                }
                for (auto& kv : g_seg_handles) {
                    rac_segmentation_cleanup(kv.second);
                    rac_segmentation_destroy(kv.second);
                }
                g_rerank_handles.clear();
                g_diar_handles.clear();
                g_seg_handles.clear();
                g_lora_applied.clear();
                g_llm_handles.clear();
                g_vlm_handles.clear();
                g_embed_handles.clear();
                g_stt_handles.clear();
                g_tts_handles.clear();
                g_vad_handles.clear();
                g_rag_handles.clear();
                g_inflight.clear();
            }
#ifdef RAC_ELECTRON_HAVE_DESKTOP
            // Join the periodic flusher before the final flush so no batch is
            // in flight when the manager is destroyed below.
            telemetry_flush_thread_stop();
            // Flush queued telemetry while the HTTP transport is still registered
            // (rac_shutdown() tears it down first, which would drop the last batch).
            telemetry_teardown_flush();
#endif
            rac_shutdown();
#ifdef RAC_ELECTRON_HAVE_DESKTOP
            // Detach + destroy the telemetry manager after the runtime is down.
            telemetry_teardown_destroy();
#endif
        }
        return RAC_SUCCESS;
    });
}

// =============================================================================
// Secure key-value store (DPAPI-backed on Windows via the platform adapter).
// Requires initialize() first. Values are encrypted at rest.
// =============================================================================
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
    // Keychain and DPAPI are both syscalls that can block on user interaction or
    // disk, so the store runs off the loop like everything else.
    return RunNativeCall(env, "secure_set", [key, value]() {
        return g_adapter.secure_set(key.c_str(), value.c_str(), g_adapter.user_data);
    });
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
    if (!g_adapter.secure_get)
        return env.Null();
    std::string key = info[0].As<Napi::String>().Utf8Value();
    // A miss is not a failure: resolve null rather than reject, which is what the
    // synchronous version returned and what every caller still expects.
    auto value = std::make_shared<std::string>();
    auto found = std::make_shared<bool>(false);
    return RunNativeCall(
        env, "secure_get",
        [key, value, found]() {
            char* out = nullptr;
            const rac_result_t rc = g_adapter.secure_get(key.c_str(), &out, g_adapter.user_data);
            if (rc == RAC_SUCCESS && out) {
                value->assign(out);
                *found = true;
            }
            if (out)
                rac_free(out);
            return RAC_SUCCESS;
        },
        [value, found](Napi::Env e) -> Napi::Value {
            if (!*found)
                return e.Null();
            return Napi::String::New(e, *value);
        });
}

Napi::Value SecureDelete(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    if (!g_initialized.load()) {
        Napi::Error::New(env, "not initialized").ThrowAsJavaScriptException();
        return env.Undefined();
    }
    if (info.Length() < 1 || !info[0].IsString() || !g_adapter.secure_delete) {
        return RunNativeCall(env, "secure_delete", []() { return RAC_SUCCESS; });
    }
    std::string key = info[0].As<Napi::String>().Utf8Value();
    return RunNativeCall(env, "secure_delete", [key]() {
        g_adapter.secure_delete(key.c_str(), g_adapter.user_data);
        return RAC_SUCCESS;
    });
}

// =============================================================================
// Voice activity detection (built-in energy VAD; no model required).
// =============================================================================
Napi::Value CreateVad(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    if (!g_initialized.load()) {
        Napi::Error::New(env, "not initialized").ThrowAsJavaScriptException();
        return env.Undefined();
    }
    // Accepts a bare threshold number (the historical shape) or a config object
    // { activationThreshold, sampleRate, frameLength, autoCalibration,
    //   calibrationMultiplier, modelPath }.
    rac_vad_config_t cfg = RAC_VAD_CONFIG_DEFAULT;
    std::string model_path;
    if (info.Length() >= 1 && info[0].IsNumber()) {
        cfg.energy_threshold = info[0].As<Napi::Number>().FloatValue();
    } else if (info.Length() >= 1 && info[0].IsObject()) {
        Napi::Object obj = info[0].As<Napi::Object>();
        if (obj.Has("activationThreshold") && obj.Get("activationThreshold").IsNumber()) {
            cfg.energy_threshold = obj.Get("activationThreshold").ToNumber().FloatValue();
        }
        if (obj.Has("sampleRate"))
            cfg.sample_rate = obj.Get("sampleRate").ToNumber().Int32Value();
        if (obj.Has("frameLength"))
            cfg.frame_length = obj.Get("frameLength").ToNumber().FloatValue();
        if (obj.Has("autoCalibration")) {
            cfg.enable_auto_calibration =
                obj.Get("autoCalibration").ToBoolean().Value() ? RAC_TRUE : RAC_FALSE;
        }
        if (obj.Has("calibrationMultiplier")) {
            cfg.calibration_multiplier = obj.Get("calibrationMultiplier").ToNumber().FloatValue();
        }
        if (obj.Has("modelPath") && obj.Get("modelPath").IsString()) {
            model_path = obj.Get("modelPath").As<Napi::String>().Utf8Value();
        }
    }
    auto slot = std::make_shared<int32_t>(0);
    return RunNativeCall(
        env, "vad create",
        [cfg, model_path, slot]() -> rac_result_t {
            rac_handle_t h = nullptr;
            rac_result_t rc = rac_vad_component_create(&h);
            if (rc != RAC_SUCCESS || !h)
                return rc == RAC_SUCCESS ? RAC_ERROR_UNKNOWN : rc;
            if (!model_path.empty()) {
                // A model-backed VAD (e.g. Silero) must be loaded before
                // initialize().
                rc = rac_vad_component_load_model(h, model_path.c_str(), model_path.c_str(),
                                                  model_path.c_str());
                if (rc != RAC_SUCCESS) {
                    rac_vad_component_destroy(h);
                    return rc;
                }
            }
            rac_vad_config_t local = cfg;
            rc = rac_vad_component_configure(h, &local);
            if (rc == RAC_SUCCESS)
                rc = rac_vad_component_initialize(h);
            if (rc != RAC_SUCCESS) {
                rac_vad_component_destroy(h);
                return rc;
            }
            std::lock_guard<std::mutex> lock(g_handles_mutex);
            *slot = g_next_handle_id++;
            g_vad_handles[*slot] = h;
            return RAC_SUCCESS;
        },
        [slot](Napi::Env e) { return Napi::Number::New(e, *slot); });
}

// vadProcess(handleId, Float32Array) -> bool (speech in this frame).
//
// Deliberately still synchronous. A VAD call is one 10-30 ms frame fed to a
// stateful detector, and frames must be seen in order: dispatching them onto
// the libuv pool would let two frames race and answer out of order, which is a
// worse failure than the microseconds of loop time an energy frame costs.
// Everything else in this file that blocks now runs on a worker.
Napi::Value VadProcess(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    if (info.Length() < 2 || !info[0].IsNumber() || !info[1].IsTypedArray()) {
        Napi::TypeError::New(env, "vadProcess(handleId, Float32Array) bad args")
            .ThrowAsJavaScriptException();
        return env.Undefined();
    }
    Napi::TypedArray ta = info[1].As<Napi::TypedArray>();
    if (ta.TypedArrayType() != napi_float32_array) {
        Napi::TypeError::New(env, "vadProcess expects a Float32Array of samples")
            .ThrowAsJavaScriptException();
        return env.Undefined();
    }
    int32_t hid = info[0].As<Napi::Number>().Int32Value();
    rac_handle_t h = begin_op(g_vad_handles, hid);
    if (!h) {
        Napi::Error::New(env, "invalid vad handle").ThrowAsJavaScriptException();
        return env.Undefined();
    }
    OpScope op(hid);
    Napi::Float32Array arr = ta.As<Napi::Float32Array>();
    rac_bool_t is_speech = RAC_FALSE;
    rac_result_t rc = rac_vad_component_process(h, arr.Data(), arr.ElementLength(), &is_speech);
    if (rc != RAC_SUCCESS) {
        throw_rac_error(env, rc, "vad process");
        return env.Undefined();
    }
    return Napi::Boolean::New(env, is_speech == RAC_TRUE);
}

Napi::Value VadIsActive(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    if (info.Length() < 1 || !info[0].IsNumber())
        return Napi::Boolean::New(env, false);
    rac_handle_t h = handle_for(g_vad_handles, info[0].As<Napi::Number>().Int32Value());
    if (!h)
        return Napi::Boolean::New(env, false);
    return Napi::Boolean::New(env, rac_vad_component_is_speech_active(h) == RAC_TRUE);
}

Napi::Value VadSetThreshold(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    if (info.Length() < 2 || !info[0].IsNumber() || !info[1].IsNumber())
        return env.Undefined();
    rac_handle_t h = handle_for(g_vad_handles, info[0].As<Napi::Number>().Int32Value());
    if (h)
        rac_vad_component_set_energy_threshold(h, info[1].As<Napi::Number>().FloatValue());
    return env.Undefined();
}

Napi::Value VadReset(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    if (info.Length() < 1 || !info[0].IsNumber())
        return env.Undefined();
    rac_handle_t h = handle_for(g_vad_handles, info[0].As<Napi::Number>().Int32Value());
    if (h)
        rac_vad_component_reset(h);
    return env.Undefined();
}

// vadStatistics(handleId) -> { threshold, ambientLevel, recentAverage,
// recentMax }.
Napi::Value VadStatistics(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    Napi::Object out = Napi::Object::New(env);
    rac_handle_t h = (info.Length() >= 1 && info[0].IsNumber())
                         ? handle_for(g_vad_handles, info[0].As<Napi::Number>().Int32Value())
                         : nullptr;
    if (!h)
        return out;
    float ambient = 0.0f;
    float recent_avg = 0.0f;
    float recent_max = 0.0f;
    rac_vad_component_get_statistics(h, &ambient, &recent_avg, &recent_max);
    out.Set("threshold", Napi::Number::New(env, rac_vad_component_get_energy_threshold(h)));
    out.Set("ambientLevel", Napi::Number::New(env, ambient));
    out.Set("recentAverage", Napi::Number::New(env, recent_avg));
    out.Set("recentMax", Napi::Number::New(env, recent_max));
    return out;
}

// =============================================================================
// VAD stream proto ABI (rac_vad_stream_*). Commons owns min-speech / silence /
// prefix-padding endpointing and emits SPEECH_ACTIVITY events on the registered
// callback. Mirror Python's vad_set_stream_callback / vad_stream_* surface.
// =============================================================================

struct VadStreamCtx {
    Napi::ThreadSafeFunction emit;
};

std::mutex& VadStreamMutex() {
    static std::mutex mutex;
    return mutex;
}

std::unordered_map<int32_t, VadStreamCtx*>& VadStreamSlots() {
    static std::unordered_map<int32_t, VadStreamCtx*> slots;
    return slots;
}

void ForwardVadStreamEvent(const uint8_t* bytes, size_t size, void* user_data) {
    auto* ctx = static_cast<VadStreamCtx*>(user_data);
    if (ctx == nullptr || bytes == nullptr || size == 0)
        return;
    auto* payload = new std::vector<uint8_t>(bytes, bytes + size);
    const napi_status status = ctx->emit.BlockingCall(
        payload, [](Napi::Env env, Napi::Function callback, std::vector<uint8_t>* held) {
            std::unique_ptr<std::vector<uint8_t>> owned(held);
            callback.Call({Napi::Buffer<uint8_t>::Copy(env, owned->data(), owned->size())});
        });
    if (status != napi_ok)
        delete payload;
}

void ClearVadStreamSlot(int32_t hid, rac_handle_t h) {
    VadStreamCtx* ctx = nullptr;
    {
        std::lock_guard<std::mutex> lock(VadStreamMutex());
        auto it = VadStreamSlots().find(hid);
        if (it != VadStreamSlots().end()) {
            ctx = it->second;
            VadStreamSlots().erase(it);
        }
    }
    if (h != nullptr)
        rac_vad_unset_stream_proto_callback(h);
    rac_vad_proto_quiesce();
    if (ctx != nullptr) {
        ctx->emit.Release();
        delete ctx;
    }
}

Napi::Value VadSetStreamCallback(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    if (info.Length() < 2 || !info[0].IsNumber() || !info[1].IsFunction()) {
        Napi::TypeError::New(env, "vadSetStreamCallback(handleId, onEvent) bad args")
            .ThrowAsJavaScriptException();
        return env.Undefined();
    }
    const int32_t hid = info[0].As<Napi::Number>().Int32Value();
    rac_handle_t h = handle_for(g_vad_handles, hid);
    if (h == nullptr) {
        Napi::Error::New(env, "invalid vad handle").ThrowAsJavaScriptException();
        return env.Undefined();
    }
    ClearVadStreamSlot(hid, h);

    auto* ctx = new VadStreamCtx();
    ctx->emit = Napi::ThreadSafeFunction::New(env, info[1].As<Napi::Function>(),
                                              "runanywhere_vad_stream", 0, 1);
    ctx->emit.Unref(env);
    {
        std::lock_guard<std::mutex> lock(VadStreamMutex());
        VadStreamSlots()[hid] = ctx;
    }
    const rac_result_t rc = rac_vad_set_stream_proto_callback(h, ForwardVadStreamEvent, ctx);
    if (rc != RAC_SUCCESS) {
        ClearVadStreamSlot(hid, h);
        rac_electron::ThrowProtoError(env, rc, "vad_set_stream_callback");
        return env.Undefined();
    }
    return env.Undefined();
}

Napi::Value VadUnsetStreamCallback(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    if (info.Length() < 1 || !info[0].IsNumber()) {
        Napi::TypeError::New(env, "vadUnsetStreamCallback(handleId) bad args")
            .ThrowAsJavaScriptException();
        return env.Undefined();
    }
    const int32_t hid = info[0].As<Napi::Number>().Int32Value();
    return RunNativeCall(env, "vad_unset_stream_callback", [hid]() {
        rac_handle_t h = handle_for(g_vad_handles, hid);
        ClearVadStreamSlot(hid, h);
        return RAC_SUCCESS;
    });
}

Napi::Value VadStreamStart(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    if (info.Length() < 2 || !info[0].IsNumber()) {
        Napi::TypeError::New(env, "vadStreamStart(handleId, optionsBytes) bad args")
            .ThrowAsJavaScriptException();
        return env.Undefined();
    }
    const int32_t hid = info[0].As<Napi::Number>().Int32Value();
    auto options = std::make_shared<std::vector<uint8_t>>(
        rac_electron::RequireProtoBytes(info, 1, "vadStreamStart(handleId, optionsBytes)"));
    auto session = std::make_shared<uint64_t>(0);
    return RunNativeCall(
        env, "vad_stream_start",
        [hid, options, session]() -> rac_result_t {
            rac_handle_t h = handle_for(g_vad_handles, hid);
            if (h == nullptr)
                return RAC_ERROR_INVALID_HANDLE;
            return rac_vad_stream_start_proto(h, options->empty() ? nullptr : options->data(),
                                              options->size(), session.get());
        },
        [session](Napi::Env e) { return Napi::Number::New(e, static_cast<double>(*session)); });
}

Napi::Value VadStreamFeed(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    if (info.Length() < 2 || !info[0].IsNumber()) {
        Napi::TypeError::New(env, "vadStreamFeed(sessionId, audioBytes) bad args")
            .ThrowAsJavaScriptException();
        return env.Undefined();
    }
    const uint64_t session_id = static_cast<uint64_t>(info[0].As<Napi::Number>().Int64Value());
    auto audio = std::make_shared<std::vector<uint8_t>>();
    if (!rac_electron::ReadProtoBytes(info[1], audio.get())) {
        Napi::TypeError::New(env, "vadStreamFeed(sessionId, audioBytes) expects bytes")
            .ThrowAsJavaScriptException();
        return env.Undefined();
    }
    return RunNativeCall(env, "vad_stream_feed", [session_id, audio]() {
        return rac_vad_stream_feed_audio_proto(session_id, audio->empty() ? nullptr : audio->data(),
                                               audio->size());
    });
}

Napi::Value VadStreamStop(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    if (info.Length() < 1 || !info[0].IsNumber()) {
        Napi::TypeError::New(env, "vadStreamStop(sessionId) bad args").ThrowAsJavaScriptException();
        return env.Undefined();
    }
    const uint64_t session_id = static_cast<uint64_t>(info[0].As<Napi::Number>().Int64Value());
    return RunNativeCall(env, "vad_stream_stop",
                         [session_id]() { return rac_vad_stream_stop_proto(session_id); });
}

Napi::Value VadStreamCancel(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    if (info.Length() < 1 || !info[0].IsNumber()) {
        Napi::TypeError::New(env, "vadStreamCancel(sessionId) bad args")
            .ThrowAsJavaScriptException();
        return env.Undefined();
    }
    const uint64_t session_id = static_cast<uint64_t>(info[0].As<Napi::Number>().Int64Value());
    return RunNativeCall(env, "vad_stream_cancel",
                         [session_id]() { return rac_vad_stream_cancel_proto(session_id); });
}

Napi::Value UnloadVad(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    if (info.Length() < 1 || !info[0].IsNumber()) {
        return RunNativeCall(env, "vad unload", []() { return RAC_SUCCESS; });
    }
    int32_t hid = info[0].As<Napi::Number>().Int32Value();
    return RunNativeCall(env, "vad unload", [hid]() {
        rac_handle_t h = take_handle_when_idle(g_vad_handles, hid);
        if (h) {
            ClearVadStreamSlot(hid, h);
            rac_vad_component_destroy(h);
        }
        return RAC_SUCCESS;
    });
}

// =============================================================================
// Rerank (cross-encoder). rac_rerank_* takes a model id at create and the model
// path at initialize, so both are required to load one.
// =============================================================================
Napi::Value LoadRerankModel(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    if (!g_initialized.load()) {
        Napi::Error::New(env, "not initialized").ThrowAsJavaScriptException();
        return env.Undefined();
    }
    if (info.Length() < 1 || !info[0].IsString()) {
        Napi::TypeError::New(env, "loadRerankModel(modelPath[, id]) expects a string")
            .ThrowAsJavaScriptException();
        return env.Undefined();
    }
    std::string path = info[0].As<Napi::String>().Utf8Value();
    std::string id =
        (info.Length() > 1 && info[1].IsString()) ? info[1].As<Napi::String>().Utf8Value() : path;
    auto slot = std::make_shared<int32_t>(0);
    return RunNativeCall(
        env, "rerank initialize",
        [path, id, slot]() -> rac_result_t {
            rac_handle_t h = nullptr;
            rac_result_t rc = rac_rerank_create(id.c_str(), &h);
            if (rc != RAC_SUCCESS)
                return rc;
            rc = rac_rerank_initialize(h, path.c_str());
            if (rc != RAC_SUCCESS) {
                rac_rerank_destroy(h);
                return rc;
            }
            std::lock_guard<std::mutex> lock(g_handles_mutex);
            *slot = g_next_handle_id++;
            g_rerank_handles[*slot] = h;
            return RAC_SUCCESS;
        },
        [slot](Napi::Env e) { return Napi::Number::New(e, *slot); });
}

struct RerankResultBox {
    rac_rerank_result_t value;
    bool filled = false;

    RerankResultBox() { std::memset(&value, 0, sizeof(value)); }
    ~RerankResultBox() {
        if (filled)
            rac_rerank_result_free(&value);
    }
    RerankResultBox(const RerankResultBox&) = delete;
    RerankResultBox& operator=(const RerankResultBox&) = delete;
};

// rerank(handleId, query, documents[], topN?) -> [{ index, score, rank }].
Napi::Value Rerank(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    if (info.Length() < 3 || !info[0].IsNumber() || !info[1].IsString() || !info[2].IsArray()) {
        Napi::TypeError::New(env, "rerank(handleId, query, documents[, topN]) bad args")
            .ThrowAsJavaScriptException();
        return env.Undefined();
    }
    Napi::Array docs = info[2].As<Napi::Array>();
    std::vector<std::string> texts;
    std::vector<std::string> ids;
    for (uint32_t i = 0; i < docs.Length(); ++i) {
        texts.push_back(docs.Get(i).ToString().Utf8Value());
        ids.push_back(std::to_string(i));
    }
    int32_t hid = info[0].As<Napi::Number>().Int32Value();
    rac_handle_t h = nullptr;
    std::shared_ptr<std::mutex> gate;
    if (!begin_worker_op(g_rerank_handles, hid, &h, &gate)) {
        Napi::Error::New(env, "invalid rerank handle").ThrowAsJavaScriptException();
        return env.Undefined();
    }
    std::string query = info[1].As<Napi::String>().Utf8Value();
    rac_rerank_options_t opts = RAC_RERANK_OPTIONS_DEFAULT;
    if (info.Length() > 3 && info[3].IsNumber()) {
        opts.top_n = static_cast<uint32_t>(info[3].As<Napi::Number>().Int32Value());
    }
    auto box = std::make_shared<RerankResultBox>();
    return RunNativeCall(
        env, "rerank",
        [h, gate, query, texts, ids, opts, box]() {
            std::lock_guard<std::mutex> serialize(*gate);
            std::vector<rac_rerank_candidate_t> candidates(texts.size());
            for (size_t i = 0; i < texts.size(); ++i) {
                candidates[i].id = ids[i].c_str();
                candidates[i].text = texts[i].c_str();
            }
            rac_rerank_options_t local = opts;
            const rac_result_t rc = rac_rerank_rerank(h, query.c_str(), candidates.data(),
                                                      candidates.size(), &local, &box->value);
            box->filled = rc == RAC_SUCCESS;
            return rc;
        },
        [box](Napi::Env e) {
            const rac_rerank_result_t& result = box->value;
            Napi::Array out = Napi::Array::New(e, result.item_count);
            for (size_t i = 0; i < result.item_count; ++i) {
                Napi::Object item = Napi::Object::New(e);
                item.Set("index", Napi::Number::New(e, result.items[i].original_index));
                item.Set("score", Napi::Number::New(e, result.items[i].score));
                item.Set("rank", Napi::Number::New(e, result.items[i].rank));
                out.Set(static_cast<uint32_t>(i), item);
            }
            return out;
        },
        [hid]() { end_op(hid); });
}

Napi::Value UnloadRerankModel(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    if (info.Length() < 1 || !info[0].IsNumber()) {
        return RunNativeCall(env, "rerank unload", []() { return RAC_SUCCESS; });
    }
    int32_t hid = info[0].As<Napi::Number>().Int32Value();
    return RunNativeCall(env, "rerank unload", [hid]() {
        rac_handle_t h = take_handle_when_idle(g_rerank_handles, hid);
        if (h) {
            rac_rerank_cleanup(h);
            rac_rerank_destroy(h);
        }
        return RAC_SUCCESS;
    });
}

// =============================================================================
// Speaker diarization. Audio is float32 mono at options.sampleRate.
// =============================================================================
Napi::Value LoadDiarizationModel(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    if (!g_initialized.load()) {
        Napi::Error::New(env, "not initialized").ThrowAsJavaScriptException();
        return env.Undefined();
    }
    if (info.Length() < 1 || !info[0].IsString()) {
        Napi::TypeError::New(env, "loadDiarizationModel(modelPath[, id]) expects a string")
            .ThrowAsJavaScriptException();
        return env.Undefined();
    }
    std::string path = info[0].As<Napi::String>().Utf8Value();
    std::string id =
        (info.Length() > 1 && info[1].IsString()) ? info[1].As<Napi::String>().Utf8Value() : path;
    auto slot = std::make_shared<int32_t>(0);
    return RunNativeCall(
        env, "diarization initialize",
        [path, id, slot]() -> rac_result_t {
            rac_handle_t h = nullptr;
            rac_result_t rc = rac_diarization_create(id.c_str(), &h);
            if (rc != RAC_SUCCESS)
                return rc;
            rc = rac_diarization_initialize(h, path.c_str());
            if (rc != RAC_SUCCESS) {
                rac_diarization_destroy(h);
                return rc;
            }
            std::lock_guard<std::mutex> lock(g_handles_mutex);
            *slot = g_next_handle_id++;
            g_diar_handles[*slot] = h;
            return RAC_SUCCESS;
        },
        [slot](Napi::Env e) { return Napi::Number::New(e, *slot); });
}

struct DiarizationResultBox {
    rac_diarization_result_t value;
    bool filled = false;

    DiarizationResultBox() { std::memset(&value, 0, sizeof(value)); }
    ~DiarizationResultBox() {
        if (filled)
            rac_diarization_result_free(&value);
    }
    DiarizationResultBox(const DiarizationResultBox&) = delete;
    DiarizationResultBox& operator=(const DiarizationResultBox&) = delete;
};

// diarize(handleId, Float32Array, options?) ->
//   { segments: [{ speakerId, speakerIndex, startMs, endMs }], speakerCount,
//   durationMs }.
Napi::Value Diarize(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    if (info.Length() < 2 || !info[0].IsNumber() || !info[1].IsTypedArray()) {
        Napi::TypeError::New(env, "diarize(handleId, Float32Array[, options]) bad args")
            .ThrowAsJavaScriptException();
        return env.Undefined();
    }
    Napi::TypedArray ta = info[1].As<Napi::TypedArray>();
    if (ta.TypedArrayType() != napi_float32_array) {
        Napi::TypeError::New(env, "diarize expects a Float32Array of samples")
            .ThrowAsJavaScriptException();
        return env.Undefined();
    }
    int32_t hid = info[0].As<Napi::Number>().Int32Value();
    rac_handle_t h = nullptr;
    std::shared_ptr<std::mutex> gate;
    if (!begin_worker_op(g_diar_handles, hid, &h, &gate)) {
        Napi::Error::New(env, "invalid diarization handle").ThrowAsJavaScriptException();
        return env.Undefined();
    }
    rac_diarization_options_t opts = RAC_DIARIZATION_OPTIONS_DEFAULT;
    if (info.Length() > 2 && info[2].IsObject()) {
        Napi::Object obj = info[2].As<Napi::Object>();
        if (obj.Has("threshold"))
            opts.threshold = obj.Get("threshold").ToNumber().FloatValue();
        if (obj.Has("minimumDurationMs")) {
            opts.minimum_duration_ms = obj.Get("minimumDurationMs").ToNumber().Int64Value();
        }
        if (obj.Has("mergeGapMs"))
            opts.merge_gap_ms = obj.Get("mergeGapMs").ToNumber().Int64Value();
        if (obj.Has("sampleRate"))
            opts.sample_rate_hz = obj.Get("sampleRate").ToNumber().Int32Value();
        if (obj.Has("channels"))
            opts.channel_count = obj.Get("channels").ToNumber().Int32Value();
    }
    Napi::Float32Array arr = ta.As<Napi::Float32Array>();
    auto samples =
        std::make_shared<std::vector<float>>(arr.Data(), arr.Data() + arr.ElementLength());
    auto box = std::make_shared<DiarizationResultBox>();
    return RunNativeCall(
        env, "diarize",
        [h, gate, samples, opts, box]() {
            std::lock_guard<std::mutex> serialize(*gate);
            rac_diarization_options_t local = opts;
            const rac_result_t rc =
                rac_diarization_diarize(h, samples->data(), samples->size(), &local, &box->value);
            box->filled = rc == RAC_SUCCESS;
            return rc;
        },
        [box](Napi::Env e) {
            const rac_diarization_result_t& result = box->value;
            Napi::Array segments = Napi::Array::New(e, result.segment_count);
            for (size_t i = 0; i < result.segment_count; ++i) {
                Napi::Object seg = Napi::Object::New(e);
                seg.Set(
                    "speakerId",
                    Napi::String::New(e, result.segments[i].speaker_id
                                             ? result.segments[i].speaker_id
                                             : std::to_string(result.segments[i].speaker_index)));
                seg.Set("speakerIndex", Napi::Number::New(e, result.segments[i].speaker_index));
                seg.Set("startMs",
                        Napi::Number::New(e, static_cast<double>(result.segments[i].start_ms)));
                seg.Set("endMs",
                        Napi::Number::New(e, static_cast<double>(result.segments[i].end_ms)));
                segments.Set(static_cast<uint32_t>(i), seg);
            }
            Napi::Object out = Napi::Object::New(e);
            out.Set("segments", segments);
            out.Set("speakerCount", Napi::Number::New(e, result.speaker_count));
            out.Set("durationMs",
                    Napi::Number::New(e, static_cast<double>(result.audio_duration_ms)));
            return out;
        },
        [hid]() { end_op(hid); });
}

Napi::Value UnloadDiarizationModel(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    if (info.Length() < 1 || !info[0].IsNumber()) {
        return RunNativeCall(env, "diarization unload", []() { return RAC_SUCCESS; });
    }
    int32_t hid = info[0].As<Napi::Number>().Int32Value();
    return RunNativeCall(env, "diarization unload", [hid]() {
        rac_handle_t h = take_handle_when_idle(g_diar_handles, hid);
        if (h) {
            rac_diarization_cleanup(h);
            rac_diarization_destroy(h);
        }
        return RAC_SUCCESS;
    });
}

// =============================================================================
// Semantic image segmentation.
// =============================================================================
Napi::Value LoadSegmentationModel(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    if (!g_initialized.load()) {
        Napi::Error::New(env, "not initialized").ThrowAsJavaScriptException();
        return env.Undefined();
    }
    if (info.Length() < 1 || !info[0].IsString()) {
        Napi::TypeError::New(env, "loadSegmentationModel(modelPath[, id]) expects a string")
            .ThrowAsJavaScriptException();
        return env.Undefined();
    }
    std::string path = info[0].As<Napi::String>().Utf8Value();
    std::string id =
        (info.Length() > 1 && info[1].IsString()) ? info[1].As<Napi::String>().Utf8Value() : path;
    auto slot = std::make_shared<int32_t>(0);
    return RunNativeCall(
        env, "segmentation initialize",
        [path, id, slot]() -> rac_result_t {
            rac_handle_t h = nullptr;
            rac_result_t rc = rac_segmentation_create(id.c_str(), &h);
            if (rc != RAC_SUCCESS)
                return rc;
            rc = rac_segmentation_initialize(h, path.c_str());
            if (rc != RAC_SUCCESS) {
                rac_segmentation_destroy(h);
                return rc;
            }
            std::lock_guard<std::mutex> lock(g_handles_mutex);
            *slot = g_next_handle_id++;
            g_seg_handles[*slot] = h;
            return RAC_SUCCESS;
        },
        [slot](Napi::Env e) { return Napi::Number::New(e, *slot); });
}

struct SegmentationResultBox {
    rac_segmentation_result_t value;
    bool filled = false;

    SegmentationResultBox() { std::memset(&value, 0, sizeof(value)); }
    ~SegmentationResultBox() {
        if (filled)
            rac_segmentation_result_free(&value);
    }
    SegmentationResultBox(const SegmentationResultBox&) = delete;
    SegmentationResultBox& operator=(const SegmentationResultBox&) = delete;
};

// segment(handleId, { data, width, height, pixelFormat, strideBytes },
// options?) ->
//   { width, height, classMask: Uint16Array, classes, diagnosticRgba? }.
Napi::Value Segment(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    if (info.Length() < 2 || !info[0].IsNumber() || !info[1].IsObject()) {
        Napi::TypeError::New(env, "segment(handleId, image[, options]) bad args")
            .ThrowAsJavaScriptException();
        return env.Undefined();
    }
    Napi::Object img = info[1].As<Napi::Object>();
    const uint8_t* data = nullptr;
    size_t data_size = 0;
    if (!img.Has("data") || !byte_view(img.Get("data"), &data, &data_size)) {
        Napi::TypeError::New(env, "segment image needs `data` bytes").ThrowAsJavaScriptException();
        return env.Undefined();
    }
    const uint32_t width = static_cast<uint32_t>(img.Get("width").ToNumber().Int32Value());
    const uint32_t height = static_cast<uint32_t>(img.Get("height").ToNumber().Int32Value());
    const rac_segmentation_pixel_format_t pixel_format =
        img.Has("pixelFormat") ? static_cast<rac_segmentation_pixel_format_t>(
                                     img.Get("pixelFormat").ToNumber().Int32Value())
                               : RAC_SEGMENTATION_PIXEL_FORMAT_RGB8;
    const size_t stride_bytes =
        img.Has("strideBytes") ? static_cast<size_t>(img.Get("strideBytes").ToNumber().Int64Value())
                               : 0;

    int32_t hid = info[0].As<Napi::Number>().Int32Value();
    rac_handle_t h = nullptr;
    std::shared_ptr<std::mutex> gate;
    if (!begin_worker_op(g_seg_handles, hid, &h, &gate)) {
        Napi::Error::New(env, "invalid segmentation handle").ThrowAsJavaScriptException();
        return env.Undefined();
    }
    rac_segmentation_options_t opts = RAC_SEGMENTATION_OPTIONS_DEFAULT;
    if (info.Length() > 2 && info[2].IsObject()) {
        Napi::Object o = info[2].As<Napi::Object>();
        if (o.Has("includeDiagnosticImage")) {
            opts.include_diagnostic_rgba =
                o.Get("includeDiagnosticImage").ToBoolean().Value() ? RAC_TRUE : RAC_FALSE;
        }
    }
    auto pixels = std::make_shared<std::vector<uint8_t>>(data, data + data_size);
    auto box = std::make_shared<SegmentationResultBox>();
    return RunNativeCall(
        env, "segment",
        [h, gate, pixels, width, height, pixel_format, stride_bytes, opts, box]() {
            std::lock_guard<std::mutex> serialize(*gate);
            rac_segmentation_image_t image;
            std::memset(&image, 0, sizeof(image));
            image.data = pixels->data();
            image.data_size = pixels->size();
            image.width = width;
            image.height = height;
            image.pixel_format = pixel_format;
            image.stride_bytes = stride_bytes;
            rac_segmentation_options_t local = opts;
            const rac_result_t rc = rac_segmentation_segment(h, &image, &local, &box->value);
            box->filled = rc == RAC_SUCCESS;
            return rc;
        },
        [box](Napi::Env e) {
            const rac_segmentation_result_t& result = box->value;
            Napi::Object out = Napi::Object::New(e);
            out.Set("width", Napi::Number::New(e, result.width));
            out.Set("height", Napi::Number::New(e, result.height));
            Napi::Uint16Array mask = Napi::Uint16Array::New(e, result.class_mask_count);
            if (result.class_mask && result.class_mask_count) {
                std::memcpy(mask.Data(), result.class_mask,
                            result.class_mask_count * sizeof(uint16_t));
            }
            out.Set("classMask", mask);
            Napi::Array classes = Napi::Array::New(e, result.class_summary_count);
            for (size_t i = 0; i < result.class_summary_count; ++i) {
                Napi::Object c = Napi::Object::New(e);
                c.Set("classId", Napi::Number::New(e, result.class_summaries[i].class_id));
                c.Set("pixelCount",
                      Napi::Number::New(
                          e, static_cast<double>(result.class_summaries[i].pixel_count)));
                c.Set("fraction", Napi::Number::New(e, result.class_summaries[i].fraction));
                if (result.class_summaries[i].label) {
                    c.Set("label", Napi::String::New(e, result.class_summaries[i].label));
                }
                classes.Set(static_cast<uint32_t>(i), c);
            }
            out.Set("classes", classes);
            if (result.diagnostic_rgba && result.diagnostic_rgba_size) {
                out.Set("diagnosticRgba", Napi::Buffer<uint8_t>::Copy(e, result.diagnostic_rgba,
                                                                      result.diagnostic_rgba_size));
            }
            return out;
        },
        [hid]() { end_op(hid); });
}

Napi::Value UnloadSegmentationModel(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    if (info.Length() < 1 || !info[0].IsNumber()) {
        return RunNativeCall(env, "segmentation unload", []() { return RAC_SUCCESS; });
    }
    int32_t hid = info[0].As<Napi::Number>().Int32Value();
    return RunNativeCall(env, "segmentation unload", [hid]() {
        rac_handle_t h = take_handle_when_idle(g_seg_handles, hid);
        if (h) {
            rac_segmentation_cleanup(h);
            rac_segmentation_destroy(h);
        }
        return RAC_SUCCESS;
    });
}

// ---- RAG (retrieval-augmented generation) -------------------------------
//
// Proto-byte C ABI: the SDK encodes runanywhere.v1 RAG* messages (ts-proto) and
// hands them across as Buffers; commons returns serialized
// RAGResult/RAGStatistics in an owned rac_proto_buffer_t that we copy into a
// Napi::Buffer and free.

// Copy an owned proto-out buffer to a JS Buffer (throwing on failure), always
// releasing the native buffer.
static Napi::Value rag_out_to_js(Napi::Env env, rac_proto_buffer_t* buf, const char* what) {
    if (buf->status != RAC_SUCCESS || buf->data == nullptr) {
        std::string msg = std::string(what) + " failed: " + std::to_string(buf->status);
        if (buf->error_message) {
            msg += " (";
            msg += buf->error_message;
            msg += ")";
        }
        rac_proto_buffer_free(buf);
        make_rac_error(env, buf->status, msg).ThrowAsJavaScriptException();
        return env.Undefined();
    }
    Napi::Buffer<uint8_t> out = Napi::Buffer<uint8_t>::Copy(env, buf->data, buf->size);
    rac_proto_buffer_free(buf);
    return out;
}

// =============================================================================
// RAG. Optional, exactly like the desktop control plane above: commons only
// defines the `rac_rag_*_proto` C ABI when it is built with RAC_BACKEND_RAG,
// so a build without it (Windows on ARM64 today — the preset turns RAG off
// because its dependency chain cannot configure there) would fail to LINK on
// these symbols rather than merely lose a feature. The JNI host already treats
// this symbol set as optional at RUNTIME (optionalNativeSymbol); a statically
// linked addon expresses the same thing at compile time.
//
// The export names stay present either way, so the RPC allowlist and the TS
// `NativeAddon` surface do not change shape between builds — calling one just
// reports FEATURE_NOT_AVAILABLE instead of vanishing as an undefined method.
// =============================================================================
#ifdef RAC_ELECTRON_HAVE_RAG

// rac_rag_ingest_proto / rac_rag_query_proto run a full embedding / LLM
// generation and can take seconds, so run them on a worker thread and resolve a
// Promise (parity with generate()). A synchronous call would block the entire
// utility-host JS event loop — starving every other RPC — for the whole query.
// The input bytes are copied because the worker outlives the JS call.
using RagProtoOp = rac_result_t (*)(rac_handle_t, const uint8_t*, size_t, rac_proto_buffer_t*);

class RagProtoWorker : public Napi::AsyncWorker {
   public:
    RagProtoWorker(Napi::Env env, rac_handle_t session, int32_t handle_id,
                   std::vector<uint8_t> input, RagProtoOp op, const char* what)
        : Napi::AsyncWorker(env),
          deferred_(Napi::Promise::Deferred::New(env)),
          session_(session),
          handle_id_(handle_id),
          leased_(true),
          input_(std::move(input)),
          op_(op),
          what_(what) {}

    Napi::Promise Promise() { return deferred_.Promise(); }

    void Execute() override {
        // Release the inflight lease when Execute finishes (success or fail).
        struct LeaseGuard {
            int32_t id;
            bool* leased;
            ~LeaseGuard() {
                if (*leased) {
                    end_op(id);
                    *leased = false;
                }
            }
        } guard{handle_id_, &leased_};

        rac_proto_buffer_t out;
        rac_proto_buffer_init(&out);
        rac_result_t rc = op_(session_, input_.data(), input_.size(), &out);
        if (rc != RAC_SUCCESS && out.status == RAC_SUCCESS)
            out.status = rc;
        if (out.status == RAC_SUCCESS && out.data != nullptr) {
            result_.assign(out.data, out.data + out.size);
            ok_ = true;
        } else {
            code_ = out.status;
            err_ = std::string(what_) + " failed: " + std::to_string(out.status);
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
        if (ok_) {
            deferred_.Resolve(Napi::Buffer<uint8_t>::Copy(Env(), result_.data(), result_.size()));
        } else {
            deferred_.Reject(make_rac_error(Env(), code_, err_).Value());
        }
    }

    void OnError(const Napi::Error& e) override {
        if (leased_) {
            end_op(handle_id_);
            leased_ = false;
        }
        Napi::HandleScope scope(Env());
        deferred_.Reject(e.Value());
    }

    ~RagProtoWorker() override {
        if (leased_)
            end_op(handle_id_);
    }

   private:
    Napi::Promise::Deferred deferred_;
    rac_handle_t session_;
    int32_t handle_id_;
    bool leased_;
    std::vector<uint8_t> input_;
    RagProtoOp op_;
    std::string what_;
    std::vector<uint8_t> result_;
    std::string err_;
    bool ok_ = false;
    rac_result_t code_ = RAC_SUCCESS;
};

// Validate (handleId, protoBytes) and dispatch a RagProtoWorker; returns its
// Promise.
static Napi::Value rag_async_op(const Napi::CallbackInfo& info, RagProtoOp op, const char* what) {
    Napi::Env env = info.Env();
    if (info.Length() < 2 || !info[0].IsNumber() || !info[1].IsTypedArray()) {
        Napi::TypeError::New(env, std::string(what) + "(handleId, protoBytes) bad args")
            .ThrowAsJavaScriptException();
        return env.Undefined();
    }
    int32_t hid = info[0].As<Napi::Number>().Int32Value();
    rac_handle_t h = begin_op(g_rag_handles, hid);
    if (!h) {
        Napi::Error::New(env, "invalid rag handle").ThrowAsJavaScriptException();
        return env.Undefined();
    }
    Napi::Uint8Array bytes = info[1].As<Napi::Uint8Array>();
    std::vector<uint8_t> copy(bytes.Data(), bytes.Data() + bytes.ByteLength());
    auto* worker = new RagProtoWorker(env, h, hid, std::move(copy), op, what);
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

#endif  // RAC_ELECTRON_HAVE_RAG

// Register a downloaded model in commons' global registry (id -> local_path) so
// session-create can resolve embedding/LLM model ids to on-disk paths. The
// Electron SDK otherwise loads models by explicit path and never populates the
// registry. rac_register_model deep-copies the struct. Outside the RAG guard
// above: RAG was the first caller, but `models.register` is the general path
// and a build without RAG still needs it.
static char* rag_dup_cstr(const std::string& s) {
    char* p = static_cast<char*>(std::malloc(s.size() + 1));
    if (p)
        std::memcpy(p, s.c_str(), s.size() + 1);
    return p;
}

Napi::Value RegisterModel(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    if (info.Length() < 2 || !info[0].IsString() || !info[1].IsString()) {
        Napi::TypeError::New(env, "registerModel(id, path, category?, framework?) bad args")
            .ThrowAsJavaScriptException();
        return env.Undefined();
    }
    std::string id = info[0].As<Napi::String>().Utf8Value();
    std::string path = info[1].As<Napi::String>().Utf8Value();
    int32_t category = (info.Length() > 2 && info[2].IsNumber())
                           ? info[2].As<Napi::Number>().Int32Value()
                           : static_cast<int32_t>(RAC_MODEL_CATEGORY_UNKNOWN);
    int32_t framework = (info.Length() > 3 && info[3].IsNumber())
                            ? info[3].As<Napi::Number>().Int32Value()
                            : static_cast<int32_t>(RAC_FRAMEWORK_UNKNOWN);
    rac_model_info_t* mi = rac_model_info_alloc();
    if (!mi) {
        Napi::Error::New(env, "rac_model_info_alloc failed").ThrowAsJavaScriptException();
        return env.Undefined();
    }
    mi->id = rag_dup_cstr(id);
    mi->local_path = rag_dup_cstr(path);
    mi->category = static_cast<rac_model_category_t>(category);
    mi->framework = static_cast<rac_inference_framework_t>(framework);
    rac_result_t rc = rac_register_model(mi);
    rac_model_info_free(mi);
    if (rc != RAC_SUCCESS) {
        throw_rac_error(env, rc, "registerModel");
        return env.Undefined();
    }
    return env.Undefined();
}

#ifdef RAC_ELECTRON_HAVE_RAG

// Async (worker-thread) — session create resolves model ids and loads embedding
// (+ optional LLM) services, which can take seconds. A sync call would block
// the utility-host event loop the same way ingest/query used to.
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
        if (rc != RAC_SUCCESS || session_ == nullptr) {
            err_ = "rag session create failed: " + std::to_string(rc);
            session_ = nullptr;
            ok_ = false;
        } else {
            ok_ = true;
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
            // Shutdown may have cleared maps + rac_shutdown() between Execute
            // and OnOK — never register a session into a dead runtime.
            if (!g_initialized.load()) {
                rac_rag_session_destroy_proto(session_);
                session_ = nullptr;
                deferred_.Reject(make_rac_error(Env(), RAC_ERROR_NOT_INITIALIZED,
                                                "rag session create aborted: SDK shut down")
                                     .Value());
                return;
            }
            hid = g_next_handle_id++;
            g_rag_handles[hid] = session_;
            session_ = nullptr;  // ownership transferred to the map
        }
        deferred_.Resolve(Napi::Number::New(Env(), hid));
    }

    void OnError(const Napi::Error& e) override {
        if (session_) {
            rac_rag_session_destroy_proto(session_);
            session_ = nullptr;
        }
        Napi::HandleScope scope(Env());
        deferred_.Reject(e.Value());
    }

    ~RagCreateSessionWorker() override {
        if (session_)
            rac_rag_session_destroy_proto(session_);
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
    // Proto bytes arrive as a Uint8Array (Buffers degrade to Uint8Array crossing
    // the utility-host MessagePort), so accept any typed array, not just Buffer.
    if (info.Length() < 1 || !info[0].IsTypedArray()) {
        Napi::TypeError::New(env, "ragCreateSession(configProtoBytes) bad args")
            .ThrowAsJavaScriptException();
        return env.Undefined();
    }
    Napi::Uint8Array cfg = info[0].As<Napi::Uint8Array>();
    std::vector<uint8_t> copy(cfg.Data(), cfg.Data() + cfg.ByteLength());
    auto* worker = new RagCreateSessionWorker(env, std::move(copy));
    Napi::Promise promise = worker->Promise();
    worker->Queue();
    return promise;
}

// Async (worker-thread) — a document's chunks are embedded, which can be slow.
Napi::Value RagIngest(const Napi::CallbackInfo& info) {
    return rag_async_op(info, rac_rag_ingest_proto, "rag ingest");
}

// Async (worker-thread) — a query runs retrieval + a full LLM generation.
Napi::Value RagQuery(const Napi::CallbackInfo& info) {
    return rag_async_op(info, rac_rag_query_proto, "rag query");
}

// Async (worker-thread) — retrieval-only search (no LLM generation).
Napi::Value RagSearch(const Napi::CallbackInfo& info) {
    return rag_async_op(info, rac_rag_search_proto, "rag search");
}

// ragQueryStream(handleId, queryProtoBytes, onEvent) -> Promise<void>. onEvent
// receives each serialized runanywhere.v1.RAGStreamEvent as a Buffer; the TS
// layer decodes them into retrieved / token / completed events.
struct RagStreamCtx {
    Napi::ThreadSafeFunction tsfn;
    std::thread worker;
    Napi::Promise::Deferred deferred;
    rac_result_t result = RAC_SUCCESS;
    int32_t lease_id = 0;
    bool leased = false;
    rac_handle_t session = nullptr;
    std::vector<uint8_t> query;
    explicit RagStreamCtx(Napi::Env env) : deferred(Napi::Promise::Deferred::New(env)) {}
};

rac_bool_t rag_stream_cb(const uint8_t* bytes, size_t size, void* ud) {
    auto* ctx = static_cast<RagStreamCtx*>(ud);
    std::vector<uint8_t> copy(bytes, bytes + size);
    napi_status st = ctx->tsfn.BlockingCall([copy](Napi::Env env, Napi::Function cb) {
        cb.Call({Napi::Buffer<uint8_t>::Copy(env, copy.data(), copy.size())});
    });
    return (st == napi_ok) ? RAC_TRUE : RAC_FALSE;  // napi_closing -> stop streaming
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
    rac_handle_t h = begin_op(g_rag_handles, hid);
    if (!h) {
        Napi::Error::New(env, "invalid rag handle").ThrowAsJavaScriptException();
        return env.Undefined();
    }
    Napi::Uint8Array bytes = info[1].As<Napi::Uint8Array>();
    auto* ctx = new RagStreamCtx(env);
    ctx->session = h;
    ctx->lease_id = hid;
    ctx->leased = true;
    ctx->query.assign(bytes.Data(), bytes.Data() + bytes.ByteLength());
    try {
        ctx->tsfn = Napi::ThreadSafeFunction::New(
            env, info[2].As<Napi::Function>(), "ra-rag-stream", 256, 1, ctx,
            [](Napi::Env env, void*, RagStreamCtx* c) {
                if (c->worker.joinable())
                    c->worker.join();
                if (c->leased) {
                    end_op(c->lease_id);
                    c->leased = false;
                }
                if (c->result == RAC_SUCCESS || is_cancellation(c->result)) {
                    c->deferred.Resolve(Napi::Boolean::New(env, is_cancellation(c->result)));
                } else {
                    c->deferred.Reject(
                        make_rac_error(env, c->result,
                                       "rag query stream failed: " + std::to_string(c->result))
                            .Value());
                }
                delete c;
            },
            static_cast<void*>(nullptr));
        ctx->worker = std::thread([ctx]() {
            ctx->result = rac_rag_query_stream_proto(ctx->session, ctx->query.data(),
                                                     ctx->query.size(), rag_stream_cb, ctx);
            if (ctx->leased) {
                end_op(ctx->lease_id);
                ctx->leased = false;
            }
            ctx->tsfn.Release();
        });
    } catch (...) {
        if (ctx->leased)
            end_op(hid);
        delete ctx;
        throw;
    }
    return ctx->deferred.Promise();
}

Napi::Value RagCancel(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    if (info.Length() < 1 || !info[0].IsNumber())
        return env.Undefined();
    rac_handle_t h = handle_for(g_rag_handles, info[0].As<Napi::Number>().Int32Value());
    if (h)
        rac_rag_cancel_proto(h);
    return env.Undefined();
}

Napi::Value RagClear(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    if (info.Length() < 1 || !info[0].IsNumber()) {
        Napi::TypeError::New(env, "ragClear(handleId) bad args").ThrowAsJavaScriptException();
        return env.Undefined();
    }
    int32_t hid = info[0].As<Napi::Number>().Int32Value();
    rac_handle_t h = begin_op(g_rag_handles, hid);
    if (!h) {
        Napi::Error::New(env, "invalid rag handle").ThrowAsJavaScriptException();
        return env.Undefined();
    }
    OpScope op(hid);
    rac_proto_buffer_t out;
    rac_proto_buffer_init(&out);
    rac_result_t rc = rac_rag_clear_proto(h, &out);
    if (rc != RAC_SUCCESS && out.status == RAC_SUCCESS)
        out.status = rc;
    return rag_out_to_js(env, &out, "rag clear");
}

Napi::Value RagStats(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    if (info.Length() < 1 || !info[0].IsNumber()) {
        Napi::TypeError::New(env, "ragStats(handleId) bad args").ThrowAsJavaScriptException();
        return env.Undefined();
    }
    int32_t hid = info[0].As<Napi::Number>().Int32Value();
    rac_handle_t h = begin_op(g_rag_handles, hid);
    if (!h) {
        Napi::Error::New(env, "invalid rag handle").ThrowAsJavaScriptException();
        return env.Undefined();
    }
    OpScope op(hid);
    rac_proto_buffer_t out;
    rac_proto_buffer_init(&out);
    rac_result_t rc = rac_rag_stats_proto(h, &out);
    if (rc != RAC_SUCCESS && out.status == RAC_SUCCESS)
        out.status = rc;
    return rag_out_to_js(env, &out, "rag stats");
}

Napi::Value RagDestroySession(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    if (info.Length() < 1 || !info[0].IsNumber())
        return env.Undefined();
    int32_t hid = info[0].As<Napi::Number>().Int32Value();
    rac_handle_t h = take_handle_when_idle(g_rag_handles, hid);
    if (h)
        rac_rag_session_destroy_proto(h);
    return env.Undefined();
}

#else  // !RAC_ELECTRON_HAVE_RAG

// One handler behind every rag* export. Typed, so the TS layer recovers an
// SDKException with a real ErrorCode instead of parsing a string (and instead
// of a bare TypeError from calling an undefined method).
Napi::Value RagUnavailable(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    throw_rac_error(env, RAC_ERROR_FEATURE_NOT_AVAILABLE, "rag (this build has no RAG pipeline)");
    return env.Undefined();
}

#endif  // RAC_ELECTRON_HAVE_RAG

Napi::Object Init(Napi::Env env, Napi::Object exports) {
    rac_electron::RegisterModelBridge(env, exports);
    rac_electron::RegisterLlmBridge(env, exports);
    rac_electron::RegisterToolBridge(env, exports);
    rac_electron::RegisterVlmBridge(env, exports);
    rac_electron::RegisterSpeechBridge(env, exports);
    rac_electron::RegisterVoiceBridge(env, exports);
    rac_electron::RegisterDataBridge(env, exports);
    rac_electron::RegisterDownloadBridge(env, exports);
    rac_electron::RegisterAudioBridge(env, exports);
    rac_electron::RegisterLoraBridge(env, exports);
    rac_electron::RegisterLoggingBridge(env, exports);
    exports.Set("initialize", Napi::Function::New(env, Initialize));
    exports.Set("memoryInfo", Napi::Function::New(env, MemoryInfo));
    // Plugin loader — host / main only. Do NOT add these to ALLOWED_RPC_METHODS
    // or expose them through RaBackend; paths come from RUNANYWHERE_PLUGIN_PATHS.
    exports.Set("loadPlugin", Napi::Function::New(env, LoadPlugin));
    exports.Set("listPlugins", Napi::Function::New(env, ListPlugins));
    exports.Set("listUnavailablePlugins", Napi::Function::New(env, ListUnavailablePlugins));
    exports.Set("pluginApiVersion", Napi::Function::New(env, PluginApiVersion));
#ifdef RAC_ELECTRON_THIN_ADDON
    exports.Set("thinAddon", Napi::Boolean::New(env, true));
#else
    exports.Set("thinAddon", Napi::Boolean::New(env, false));
#endif
#ifdef RAC_ELECTRON_HAVE_DESKTOP
    // Desktop control plane (telemetry + auth). Present only when the desktop
    // libcurl transport is linked into commons (RAC_DESKTOP_ADAPTER=ON).
    exports.Set("hasControlPlane", Napi::Boolean::New(env, true));
    exports.Set("devicePersistentId", Napi::Function::New(env, DevicePersistentId));
    exports.Set("devStagingBaseUrl", Napi::Function::New(env, DevStagingBaseUrl));
    exports.Set("configureControlPlane", Napi::Function::New(env, ConfigureControlPlane));
    exports.Set("retryControlPlane", Napi::Function::New(env, RetryControlPlane));
    exports.Set("telemetryFlush", Napi::Function::New(env, TelemetryFlush));
    exports.Set("authState", Napi::Function::New(env, AuthState));
    exports.Set("clearAuth", Napi::Function::New(env, ClearAuth));
#else
    exports.Set("hasControlPlane", Napi::Boolean::New(env, false));
#endif
    exports.Set("hfTokenSet", Napi::Function::New(env, HfTokenSet));
    exports.Set("hfTokenConfigured", Napi::Function::New(env, HfTokenConfigured));
    exports.Set("secureSet", Napi::Function::New(env, SecureSet));
    exports.Set("secureGet", Napi::Function::New(env, SecureGet));
    exports.Set("secureDelete", Napi::Function::New(env, SecureDelete));
    exports.Set("createVad", Napi::Function::New(env, CreateVad));
    exports.Set("vadProcess", Napi::Function::New(env, VadProcess));
    exports.Set("vadIsActive", Napi::Function::New(env, VadIsActive));
    exports.Set("vadSetThreshold", Napi::Function::New(env, VadSetThreshold));
    exports.Set("vadReset", Napi::Function::New(env, VadReset));
    exports.Set("vadStatistics", Napi::Function::New(env, VadStatistics));
    exports.Set("vadSetStreamCallback", Napi::Function::New(env, VadSetStreamCallback));
    exports.Set("vadUnsetStreamCallback", Napi::Function::New(env, VadUnsetStreamCallback));
    exports.Set("vadStreamStart", Napi::Function::New(env, VadStreamStart));
    exports.Set("vadStreamFeed", Napi::Function::New(env, VadStreamFeed));
    exports.Set("vadStreamStop", Napi::Function::New(env, VadStreamStop));
    exports.Set("vadStreamCancel", Napi::Function::New(env, VadStreamCancel));
    exports.Set("unloadVad", Napi::Function::New(env, UnloadVad));
    exports.Set("loadModel", Napi::Function::New(env, LoadModel));
    exports.Set("generate", Napi::Function::New(env, Generate));
    exports.Set("cancelGenerate", Napi::Function::New(env, CancelGenerate));
    exports.Set("unloadModel", Napi::Function::New(env, UnloadModel));
    exports.Set("loraApply", Napi::Function::New(env, LoraApply));
    exports.Set("loraRemove", Napi::Function::New(env, LoraRemove));
    exports.Set("loraList", Napi::Function::New(env, LoraList));
    exports.Set("loadVlmModel", Napi::Function::New(env, LoadVlmModel));
    exports.Set("generateVlm", Napi::Function::New(env, GenerateVlm));
    exports.Set("cancelVlm", Napi::Function::New(env, CancelVlm));
    exports.Set("unloadVlmModel", Napi::Function::New(env, UnloadVlmModel));
    exports.Set("loadEmbeddingModel", Napi::Function::New(env, LoadEmbeddingModel));
    exports.Set("embed", Napi::Function::New(env, Embed));
    exports.Set("embedBatch", Napi::Function::New(env, EmbedBatch));
    exports.Set("unloadEmbeddingModel", Napi::Function::New(env, UnloadEmbeddingModel));
    exports.Set("loadSttModel", Napi::Function::New(env, LoadSttModel));
    exports.Set("transcribe", Napi::Function::New(env, Transcribe));
    exports.Set("transcribeStream", Napi::Function::New(env, TranscribeStream));
    exports.Set("sttInfo", Napi::Function::New(env, SttInfo));
    exports.Set("unloadSttModel", Napi::Function::New(env, UnloadSttModel));
    exports.Set("loadTtsVoice", Napi::Function::New(env, LoadTtsVoice));
    exports.Set("synthesize", Napi::Function::New(env, Synthesize));
    exports.Set("synthesizeStream", Napi::Function::New(env, SynthesizeStream));
    exports.Set("ttsStop", Napi::Function::New(env, TtsStop));
    exports.Set("ttsInfo", Napi::Function::New(env, TtsInfo));
    exports.Set("unloadTtsVoice", Napi::Function::New(env, UnloadTtsVoice));
    exports.Set("loadRerankModel", Napi::Function::New(env, LoadRerankModel));
    exports.Set("rerank", Napi::Function::New(env, Rerank));
    exports.Set("unloadRerankModel", Napi::Function::New(env, UnloadRerankModel));
    exports.Set("loadDiarizationModel", Napi::Function::New(env, LoadDiarizationModel));
    exports.Set("diarize", Napi::Function::New(env, Diarize));
    exports.Set("unloadDiarizationModel", Napi::Function::New(env, UnloadDiarizationModel));
    exports.Set("loadSegmentationModel", Napi::Function::New(env, LoadSegmentationModel));
    exports.Set("segment", Napi::Function::New(env, Segment));
    exports.Set("unloadSegmentationModel", Napi::Function::New(env, UnloadSegmentationModel));
    exports.Set("registerModel", Napi::Function::New(env, RegisterModel));
#ifdef RAC_ELECTRON_HAVE_RAG
    exports.Set("ragCreateSession", Napi::Function::New(env, RagCreateSession));
    exports.Set("ragIngest", Napi::Function::New(env, RagIngest));
    exports.Set("ragQuery", Napi::Function::New(env, RagQuery));
    exports.Set("ragSearch", Napi::Function::New(env, RagSearch));
    exports.Set("ragQueryStream", Napi::Function::New(env, RagQueryStream));
    exports.Set("ragCancel", Napi::Function::New(env, RagCancel));
    exports.Set("ragClear", Napi::Function::New(env, RagClear));
    exports.Set("ragStats", Napi::Function::New(env, RagStats));
    exports.Set("ragDestroySession", Napi::Function::New(env, RagDestroySession));
#else
    for (const char* name :
         {"ragCreateSession", "ragIngest", "ragQuery", "ragSearch", "ragQueryStream", "ragCancel",
          "ragClear", "ragStats", "ragDestroySession"}) {
        exports.Set(name, Napi::Function::New(env, RagUnavailable));
    }
#endif
    exports.Set("shutdown", Napi::Function::New(env, Shutdown));
    exports.Set("version", Napi::String::New(env, rac_sdk_get_version()));
    return exports;
}

}  // namespace

NODE_API_MODULE(runanywhere_native, Init)
