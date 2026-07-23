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
// Modalities: LLM, VLM, embeddings (ONNX), STT + TTS (sherpa), VAD (built-in).

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
#include "rac/infrastructure/model_management/rac_model_paths.h"
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
#ifdef RAC_HAVE_BACKEND_COREML
rac_result_t rac_backend_coreml_register(void);  // Apple Core ML
#endif
#ifdef RAC_HAVE_BACKEND_CLOUD
rac_result_t rac_backend_cloud_register(void);  // Cloud STT provider
#endif
}

namespace {

// The adapter struct is caller-owned and must outlive rac_shutdown().
rac_platform_adapter_t g_adapter;
std::atomic<bool> g_initialized{false};

// Handles are exposed to Python as small integer ids. Each component family
// uses a distinct rac_*_destroy call, so they live in separate maps.
std::mutex g_handles_mutex;
std::unordered_map<int32_t, rac_handle_t> g_llm_handles;
std::unordered_map<int32_t, rac_handle_t> g_vlm_handles;
std::unordered_map<int32_t, rac_handle_t> g_embed_handles;
std::unordered_map<int32_t, rac_handle_t> g_stt_handles;
std::unordered_map<int32_t, rac_handle_t> g_tts_handles;
std::unordered_map<int32_t, rac_handle_t> g_vad_handles;
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
#ifdef RAC_HAVE_BACKEND_COREML
        rac_backend_coreml_register();  // Apple Core ML
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
                  py::function on_token) {
    rac_handle_t h = begin_op(g_vlm_handles, handle);
    if (!h) throw std::runtime_error("invalid vlm handle");
    OpScope op(handle);  // keep the handle alive vs a concurrent unload/shutdown

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
        rc = rac_vlm_component_process_stream(h, &image, prompt.c_str(), &opts, stream_token_cb,
                                              stream_vlm_complete_cb, stream_error_cb, &ctx);
    }
    finish_stream(ctx, rc, "generate_vlm");
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
    rac_handle_t h = handle_for(g_rag_handles, handle);
    if (!h) throw std::runtime_error("invalid rag handle");
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
    rac_handle_t h = handle_for(g_rag_handles, handle);
    if (!h) throw std::runtime_error("invalid rag handle");
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
    rac_handle_t h = handle_for(g_rag_handles, handle);
    if (!h) throw std::runtime_error("invalid rag handle");
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
    rac_handle_t h = handle_for(g_rag_handles, handle);
    if (!h) throw std::runtime_error("invalid rag handle");
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
    rac_handle_t h = handle_for(g_rag_handles, handle);
    if (!h) throw std::runtime_error("invalid rag handle");
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
    rac_handle_t h = take_handle(g_rag_handles, handle);
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

void unload_vad(int32_t handle) {
    rac_handle_t h = take_handle(g_vad_handles, handle);
    if (h) rac_vad_component_destroy(h);
}

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
            // RAG sessions + VAD are intentionally not in g_inflight: rac_rag_session_destroy_proto
            // is documented safe concurrent with active ops, and vad_process holds the GIL.
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
            g_llm_handles.clear();
            g_vlm_handles.clear();
            g_embed_handles.clear();
            g_stt_handles.clear();
            g_tts_handles.clear();
            g_vad_handles.clear();
            g_inflight.clear();
        }
        rac_shutdown();
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
    m.def("unload_model", &unload_model, py::arg("handle"), "Unload an LLM handle.");

    // VLM
    m.def("load_vlm_model", &load_vlm_model, py::arg("model_path"), py::arg("mmproj_path"),
          py::arg("id") = py::none(), py::arg("name") = py::none(),
          "Load a VLM model + mmproj; returns an integer handle.");
    m.def("generate_vlm", &generate_vlm, py::arg("handle"), py::arg("image_path"), py::arg("prompt"),
          py::arg("on_token"),
          "Stream tokens from a VLM handle over an image + prompt; on_token(str) per token.");
    m.def("unload_vlm_model", &unload_vlm_model, py::arg("handle"), "Unload a VLM handle.");

    // Embeddings
    m.def("load_embedding_model", &load_embedding_model, py::arg("path"),
          "Load an embedding model (ONNX); returns an integer handle.");
    m.def("embed", &embed, py::arg("handle"), py::arg("text"),
          "Embed text; returns a float32 numpy array.");
    m.def("unload_embedding_model", &unload_embedding_model, py::arg("handle"),
          "Unload an embedding handle.");

    // Model registry (id -> local_path) so RAG can resolve model ids to paths.
    m.def("register_model", &register_model, py::arg("model_id"), py::arg("local_path"),
          py::arg("framework"), py::arg("category"),
          "Register a model (id -> local_path + framework/category ints) into the "
          "global model registry so the RAG session ABI can resolve it.");

#ifdef RAC_HAVE_BACKEND_RAG
    // RAG — proto-bytes in / proto-bytes out (serialized runanywhere.v1.* msgs).
    m.def("rag_session_create", &rag_session_create, py::arg("config_bytes"),
          "Create a RAG session from RAGConfiguration bytes; returns an integer handle.");
    m.def("rag_ingest", &rag_ingest, py::arg("handle"), py::arg("document_bytes"),
          "Ingest one RAGDocument (bytes); returns RAGStatistics bytes.");
    m.def("rag_query", &rag_query, py::arg("handle"), py::arg("query_bytes"),
          "Query with RAGQueryOptions bytes; returns RAGResult bytes.");
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
    m.def("unload_vad", &unload_vad, py::arg("handle"), "Unload a VAD handle.");

    // Secure store
    m.def("secure_set", &secure_set, py::arg("key"), py::arg("value"),
          "Store an encrypted key/value pair.");
    m.def("secure_get", &secure_get, py::arg("key"),
          "Read a secure value; returns str or None on a miss.");
    m.def("secure_delete", &secure_delete, py::arg("key"), "Delete a secure key.");
}
