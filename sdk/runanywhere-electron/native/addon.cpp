// addon.cpp — RunAnywhere Electron N-API addon.
//
// Binds the rac_* C ABI (reusing the Win32 platform adapter proven by the M0
// harness) for on-device inference in Node/Electron. Node-API only, so one
// prebuilt spans Node/Electron versions. Streaming uses a bounded
// Napi::ThreadSafeFunction on a worker thread (BlockingCall = backpressure) and
// resolves a Promise in the TSFN finalizer.
//
// Modalities: LLM (generate) and VLM (generateVlm, image + prompt) — both served
// by the already-linked llama.cpp engine.

#include <napi.h>

#include <atomic>
#include <cstring>
#include <functional>
#include <mutex>
#include <string>
#include <thread>
#include <unordered_map>

#include "win32_platform_adapter.h"

#include "rac/backends/rac_llm_llamacpp.h"
#include "rac/core/rac_core.h"
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
#include "rac/infrastructure/model_management/rac_model_registry.h"
#include "rac/infrastructure/model_management/rac_model_types.h"
#include "rac/features/rag/rac_rag.h"
#include "rac/foundation/rac_proto_buffer.h"

// Internal (non-proto) embeddings service factory — its header lives under
// commons/src/, not include/, so re-declare the prototype here. The addon
// static-links rac_commons, so the symbol resolves at link time.
namespace rac {
namespace embeddings {
rac_result_t create_service(const char* model_id, const char* config_json, rac_handle_t* out_handle);
}  // namespace embeddings
}  // namespace rac

namespace {

// The adapter struct is caller-owned and must outlive rac_shutdown().
rac_platform_adapter_t g_adapter;
std::atomic<bool> g_initialized{false};

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
int32_t g_next_handle_id = 1;

rac_handle_t handle_for(const std::unordered_map<int32_t, rac_handle_t>& map, int32_t id) {
    std::lock_guard<std::mutex> lock(g_handles_mutex);
    auto it = map.find(id);
    return (it == map.end()) ? nullptr : it->second;
}

// =============================================================================
// initialize(secureDir[, baseDir])
// =============================================================================
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

    rac_electron_fill_win32_adapter(&g_adapter, secure.c_str());

    rac_config_t cfg;
    std::memset(&cfg, 0, sizeof(cfg));
    cfg.platform_adapter = &g_adapter;
    cfg.log_level = RAC_LOG_WARNING;
    cfg.log_tag = "electron";

    rac_model_paths_set_base_dir(base.c_str());

    rac_result_t rc = rac_init(&cfg);
    if (rc != RAC_SUCCESS) {
        Napi::Error::New(env, "rac_init failed: " + std::to_string(rc)).ThrowAsJavaScriptException();
        return env.Undefined();
    }
    // Backend/plugin registration is process-global and persists across
    // rac_shutdown(), so register exactly once — re-registering after a
    // shutdown+re-init would fail (RAC already-registered), which is why
    // initialize() must be safe to call again after shutdown().
    static bool backends_registered = false;
    if (!backends_registered) {
        rc = rac_backend_llamacpp_register();
        if (rc != RAC_SUCCESS) {
            rac_shutdown();
            Napi::Error::New(env, "rac_backend_llamacpp_register failed: " + std::to_string(rc))
                .ThrowAsJavaScriptException();
            return env.Undefined();
        }
        // Embeddings engine (optional): register the ONNX backend. A failure here
        // just means embeddings are unavailable, not a fatal init error.
        rac_backend_onnx_register();
        // Speech engine (optional): register sherpa for STT / TTS.
        rac_backend_sherpa_register();
        backends_registered = true;
    }
    g_initialized.store(true);
    return env.Undefined();
}

// =============================================================================
// Streaming core — shared by LLM generate + VLM process (both stream a char*
// token trio and block their calling thread, so we drive them on a worker
// thread and marshal tokens to JS via a bounded ThreadSafeFunction).
// =============================================================================
struct StreamCtx {
    Napi::ThreadSafeFunction tsfn;
    std::thread worker;
    Napi::Promise::Deferred deferred;
    rac_result_t result = RAC_SUCCESS;
    std::string error_msg;
    std::function<rac_result_t(StreamCtx*)> run;  // performs the rac streaming call
    explicit StreamCtx(Napi::Env env) : deferred(Napi::Promise::Deferred::New(env)) {}
};

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
    ctx->error_msg = msg ? msg : "generation error";
}

void stream_llm_complete_cb(const rac_llm_result_t*, void* ud) {
    static_cast<StreamCtx*>(ud)->result = RAC_SUCCESS;
}

void stream_vlm_complete_cb(const rac_vlm_result_t*, void* ud) {
    static_cast<StreamCtx*>(ud)->result = RAC_SUCCESS;
}

// Create the TSFN + worker thread; resolve/reject the returned Promise in the
// finalizer (JS loop, after the producer thread Release()d).
Napi::Promise start_stream(Napi::Env env, Napi::Function on_token,
                           std::function<rac_result_t(StreamCtx*)> run) {
    auto* ctx = new StreamCtx(env);
    ctx->run = std::move(run);
    ctx->tsfn = Napi::ThreadSafeFunction::New(
        env, on_token, "ra-stream", /*maxQueueSize*/ 256, /*initialThreadCount*/ 1, ctx,
        [](Napi::Env env, void* /*data*/, StreamCtx* c) {
            if (c->worker.joinable()) c->worker.join();
            if (c->result == RAC_SUCCESS) {
                c->deferred.Resolve(env.Undefined());
            } else {
                std::string msg = c->error_msg.empty()
                                      ? ("stream failed: " + std::to_string(c->result))
                                      : c->error_msg;
                c->deferred.Reject(Napi::Error::New(env, msg).Value());
            }
            delete c;
        },
        static_cast<void*>(nullptr));

    ctx->worker = std::thread([ctx]() {
        rac_result_t rc = ctx->run(ctx);
        if (rc != RAC_SUCCESS && ctx->result == RAC_SUCCESS) ctx->result = rc;
        ctx->tsfn.Release();  // last TSFN call from this thread -> finalizer on JS loop
    });
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

    rac_handle_t h = nullptr;
    rac_result_t rc = rac_llm_component_create(&h);
    if (rc != RAC_SUCCESS) {
        Napi::Error::New(env, "llm_component_create failed: " + std::to_string(rc))
            .ThrowAsJavaScriptException();
        return env.Undefined();
    }
    rc = rac_llm_component_load_model(h, path.c_str(), id.c_str(), name.c_str());
    if (rc != RAC_SUCCESS) {
        rac_llm_component_destroy(h);
        Napi::Error::New(env, "load_model failed: " + std::to_string(rc))
            .ThrowAsJavaScriptException();
        return env.Undefined();
    }
    int32_t hid;
    {
        std::lock_guard<std::mutex> lock(g_handles_mutex);
        hid = g_next_handle_id++;
        g_llm_handles[hid] = h;
    }
    return Napi::Number::New(env, hid);
}

// Optional per-request generation options (from a JS object). Strings are held by
// value so their c_str() stays valid for the duration of the streaming call.
struct GenOpts {
    bool has_max = false;
    int32_t max_tokens = 0;
    bool has_temp = false;
    float temperature = 0.0f;
    bool has_top_p = false;
    float top_p = 0.0f;
    bool has_top_k = false;
    int32_t top_k = 0;
    std::string system_prompt;
    std::string grammar;
};

GenOpts parse_gen_opts(const Napi::Value& v) {
    GenOpts o;
    if (!v.IsObject()) return o;
    Napi::Object obj = v.As<Napi::Object>();
    if (obj.Has("maxTokens")) { o.max_tokens = obj.Get("maxTokens").ToNumber().Int32Value(); o.has_max = true; }
    if (obj.Has("temperature")) { o.temperature = obj.Get("temperature").ToNumber().FloatValue(); o.has_temp = true; }
    if (obj.Has("topP")) { o.top_p = obj.Get("topP").ToNumber().FloatValue(); o.has_top_p = true; }
    if (obj.Has("topK")) { o.top_k = obj.Get("topK").ToNumber().Int32Value(); o.has_top_k = true; }
    if (obj.Has("systemPrompt")) o.system_prompt = obj.Get("systemPrompt").ToString().Utf8Value();
    if (obj.Has("grammar")) o.grammar = obj.Get("grammar").ToString().Utf8Value();
    return o;
}

void apply_gen_opts(rac_llm_options_t& opts, const GenOpts& o) {
    if (o.has_max) opts.max_tokens = o.max_tokens;
    if (o.has_temp) opts.temperature = o.temperature;
    if (o.has_top_p) opts.top_p = o.top_p;
    if (o.has_top_k) opts.top_k = o.top_k;
    if (!o.system_prompt.empty()) opts.system_prompt = o.system_prompt.c_str();
    if (!o.grammar.empty()) opts.grammar = o.grammar.c_str();
}

// generate(handle, prompt, onToken) OR generate(handle, prompt, options, onToken).
Napi::Value Generate(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    if (info.Length() < 3 || !info[0].IsNumber() || !info[1].IsString()) {
        Napi::TypeError::New(env, "generate(handleId, prompt[, options], onToken) bad args")
            .ThrowAsJavaScriptException();
        return env.Undefined();
    }
    rac_handle_t h = handle_for(g_llm_handles, info[0].As<Napi::Number>().Int32Value());
    if (!h) {
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
            Napi::TypeError::New(env, "generate: onToken callback required").ThrowAsJavaScriptException();
            return env.Undefined();
        }
        on_token = info[3].As<Napi::Function>();
    }

    return start_stream(env, on_token, [h, prompt, o](StreamCtx* c) {
        rac_llm_options_t opts = RAC_LLM_OPTIONS_DEFAULT;
        apply_gen_opts(opts, o);
        return rac_llm_component_generate_stream(h, prompt.c_str(), &opts, stream_token_cb,
                                                 stream_llm_complete_cb, stream_error_cb, c);
    });
}

Napi::Value UnloadModel(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    if (info.Length() < 1 || !info[0].IsNumber()) return env.Undefined();
    int32_t hid = info[0].As<Napi::Number>().Int32Value();
    rac_handle_t h = nullptr;
    {
        std::lock_guard<std::mutex> lock(g_handles_mutex);
        auto it = g_llm_handles.find(hid);
        if (it != g_llm_handles.end()) {
            h = it->second;
            g_llm_handles.erase(it);
        }
    }
    if (h) rac_llm_component_destroy(h);
    return env.Undefined();
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

    rac_handle_t h = nullptr;
    rac_result_t rc = rac_vlm_component_create(&h);
    if (rc != RAC_SUCCESS) {
        Napi::Error::New(env, "vlm_component_create failed: " + std::to_string(rc))
            .ThrowAsJavaScriptException();
        return env.Undefined();
    }
    rc = rac_vlm_component_load_model(h, model.c_str(), mmproj.c_str(), id.c_str(), name.c_str());
    if (rc != RAC_SUCCESS) {
        rac_vlm_component_destroy(h);
        Napi::Error::New(env, "vlm load_model failed: " + std::to_string(rc))
            .ThrowAsJavaScriptException();
        return env.Undefined();
    }
    int32_t hid;
    {
        std::lock_guard<std::mutex> lock(g_handles_mutex);
        hid = g_next_handle_id++;
        g_vlm_handles[hid] = h;
    }
    return Napi::Number::New(env, hid);
}

Napi::Value GenerateVlm(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    if (info.Length() < 4 || !info[0].IsNumber() || !info[1].IsString() || !info[2].IsString() ||
        !info[3].IsFunction()) {
        Napi::TypeError::New(env, "generateVlm(handleId, imagePath, prompt, onToken) bad args")
            .ThrowAsJavaScriptException();
        return env.Undefined();
    }
    rac_handle_t h = handle_for(g_vlm_handles, info[0].As<Napi::Number>().Int32Value());
    if (!h) {
        Napi::Error::New(env, "invalid vlm handle").ThrowAsJavaScriptException();
        return env.Undefined();
    }
    std::string image_path = info[1].As<Napi::String>().Utf8Value();
    std::string prompt = info[2].As<Napi::String>().Utf8Value();
    return start_stream(env, info[3].As<Napi::Function>(), [h, image_path, prompt](StreamCtx* c) {
        rac_vlm_image_t image;
        std::memset(&image, 0, sizeof(image));
        image.format = RAC_VLM_IMAGE_FORMAT_FILE_PATH;
        image.file_path = image_path.c_str();
        // Pass explicit defaults: NULL options leaves the VLM sampler config
        // (top_k / seed / ...) reading uninitialized memory, which can crash.
        rac_vlm_options_t opts = RAC_VLM_OPTIONS_DEFAULT;
        return rac_vlm_component_process_stream(h, &image, prompt.c_str(), &opts, stream_token_cb,
                                                stream_vlm_complete_cb, stream_error_cb, c);
    });
}

Napi::Value UnloadVlmModel(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    if (info.Length() < 1 || !info[0].IsNumber()) return env.Undefined();
    int32_t hid = info[0].As<Napi::Number>().Int32Value();
    rac_handle_t h = nullptr;
    {
        std::lock_guard<std::mutex> lock(g_handles_mutex);
        auto it = g_vlm_handles.find(hid);
        if (it != g_vlm_handles.end()) {
            h = it->second;
            g_vlm_handles.erase(it);
        }
    }
    if (h) rac_vlm_component_destroy(h);
    return env.Undefined();
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
    rac_handle_t h = nullptr;
    rac_result_t rc = rac::embeddings::create_service(
        model.c_str(), config.empty() ? nullptr : config.c_str(), &h);
    if (rc != RAC_SUCCESS) {
        Napi::Error::New(env, "embeddings create_service failed: " + std::to_string(rc))
            .ThrowAsJavaScriptException();
        return env.Undefined();
    }
    int32_t hid;
    {
        std::lock_guard<std::mutex> lock(g_handles_mutex);
        hid = g_next_handle_id++;
        g_embed_handles[hid] = h;
    }
    return Napi::Number::New(env, hid);
}

Napi::Value Embed(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    if (info.Length() < 2 || !info[0].IsNumber() || !info[1].IsString()) {
        Napi::TypeError::New(env, "embed(handleId, text) bad args").ThrowAsJavaScriptException();
        return env.Undefined();
    }
    rac_handle_t h = handle_for(g_embed_handles, info[0].As<Napi::Number>().Int32Value());
    if (!h) {
        Napi::Error::New(env, "invalid embedding handle").ThrowAsJavaScriptException();
        return env.Undefined();
    }
    std::string text = info[1].As<Napi::String>().Utf8Value();
    rac_embeddings_result_t result;
    std::memset(&result, 0, sizeof(result));
    rac_result_t rc = rac_embeddings_embed(h, text.c_str(), nullptr, &result);
    if (rc != RAC_SUCCESS) {
        Napi::Error::New(env, "embed failed: " + std::to_string(rc)).ThrowAsJavaScriptException();
        return env.Undefined();
    }
    if (result.num_embeddings == 0 || result.embeddings == nullptr ||
        result.embeddings[0].data == nullptr) {
        rac_embeddings_result_free(&result);
        Napi::Error::New(env, "no embedding produced").ThrowAsJavaScriptException();
        return env.Undefined();
    }
    size_t dim = result.embeddings[0].dimension;
    Napi::Float32Array arr = Napi::Float32Array::New(env, dim);
    std::memcpy(arr.Data(), result.embeddings[0].data, dim * sizeof(float));
    rac_embeddings_result_free(&result);
    return arr;
}

Napi::Value UnloadEmbeddingModel(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    if (info.Length() < 1 || !info[0].IsNumber()) return env.Undefined();
    int32_t hid = info[0].As<Napi::Number>().Int32Value();
    rac_handle_t h = nullptr;
    {
        std::lock_guard<std::mutex> lock(g_handles_mutex);
        auto it = g_embed_handles.find(hid);
        if (it != g_embed_handles.end()) {
            h = it->second;
            g_embed_handles.erase(it);
        }
    }
    if (h) rac_embeddings_destroy(h);
    return env.Undefined();
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
    rac_handle_t h = nullptr;
    rac_result_t rc = rac_stt_component_create(&h);
    if (rc != RAC_SUCCESS) {
        Napi::Error::New(env, "stt_component_create failed: " + std::to_string(rc))
            .ThrowAsJavaScriptException();
        return env.Undefined();
    }
    rc = rac_stt_component_load_model(h, dir.c_str(), id.c_str(), name.c_str());
    if (rc != RAC_SUCCESS) {
        rac_stt_component_destroy(h);
        Napi::Error::New(env, "stt load_model failed: " + std::to_string(rc))
            .ThrowAsJavaScriptException();
        return env.Undefined();
    }
    int32_t hid;
    {
        std::lock_guard<std::mutex> lock(g_handles_mutex);
        hid = g_next_handle_id++;
        g_stt_handles[hid] = h;
    }
    return Napi::Number::New(env, hid);
}

// transcribe(handleId, pcm16Buffer) -> text. Audio = 16 kHz mono PCM16 bytes.
// Synchronous (blocks the JS thread for the decode); the utility process keeps it
// off the UI. A dedicated worker-thread variant can come later.
Napi::Value Transcribe(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    // Accept a Node Buffer OR any TypedArray (the public API + MessagePort clones
    // deliver a Uint8Array of PCM16 bytes, not necessarily a Buffer).
    if (info.Length() < 2 || !info[0].IsNumber() ||
        !(info[1].IsBuffer() || info[1].IsTypedArray())) {
        Napi::TypeError::New(env, "transcribe(handleId, pcm16Bytes) bad args")
            .ThrowAsJavaScriptException();
        return env.Undefined();
    }
    rac_handle_t h = handle_for(g_stt_handles, info[0].As<Napi::Number>().Int32Value());
    if (!h) {
        Napi::Error::New(env, "invalid stt handle").ThrowAsJavaScriptException();
        return env.Undefined();
    }
    const uint8_t* pcm_data = nullptr;
    size_t pcm_len = 0;
    if (info[1].IsBuffer()) {
        Napi::Buffer<uint8_t> buf = info[1].As<Napi::Buffer<uint8_t>>();
        pcm_data = buf.Data();
        pcm_len = buf.Length();
    } else {
        Napi::TypedArray ta = info[1].As<Napi::TypedArray>();
        Napi::ArrayBuffer ab = ta.ArrayBuffer();
        pcm_data = static_cast<uint8_t*>(ab.Data()) + ta.ByteOffset();
        pcm_len = ta.ByteLength();
    }
    rac_stt_result_t result;
    std::memset(&result, 0, sizeof(result));
    rac_result_t rc =
        rac_stt_component_transcribe(h, pcm_data, pcm_len, nullptr, &result);
    if (rc != RAC_SUCCESS) {
        Napi::Error::New(env, "transcribe failed: " + std::to_string(rc))
            .ThrowAsJavaScriptException();
        return env.Undefined();
    }
    std::string text = result.text ? result.text : "";
    rac_stt_result_free(&result);
    return Napi::String::New(env, text);
}

Napi::Value UnloadSttModel(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    if (info.Length() < 1 || !info[0].IsNumber()) return env.Undefined();
    int32_t hid = info[0].As<Napi::Number>().Int32Value();
    rac_handle_t h = nullptr;
    {
        std::lock_guard<std::mutex> lock(g_handles_mutex);
        auto it = g_stt_handles.find(hid);
        if (it != g_stt_handles.end()) {
            h = it->second;
            g_stt_handles.erase(it);
        }
    }
    if (h) rac_stt_component_destroy(h);
    return env.Undefined();
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
    rac_handle_t h = nullptr;
    rac_result_t rc = rac_tts_component_create(&h);
    if (rc != RAC_SUCCESS) {
        Napi::Error::New(env, "tts_component_create failed: " + std::to_string(rc))
            .ThrowAsJavaScriptException();
        return env.Undefined();
    }
    rc = rac_tts_component_load_voice(h, dir.c_str(), id.c_str(), name.c_str());
    if (rc != RAC_SUCCESS) {
        rac_tts_component_destroy(h);
        Napi::Error::New(env, "tts load_voice failed: " + std::to_string(rc))
            .ThrowAsJavaScriptException();
        return env.Undefined();
    }
    int32_t hid;
    {
        std::lock_guard<std::mutex> lock(g_handles_mutex);
        hid = g_next_handle_id++;
        g_tts_handles[hid] = h;
    }
    return Napi::Number::New(env, hid);
}

// synthesize(handleId, text) -> { sampleRate, samples: Float32Array }.
Napi::Value Synthesize(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    if (info.Length() < 2 || !info[0].IsNumber() || !info[1].IsString()) {
        Napi::TypeError::New(env, "synthesize(handleId, text) bad args")
            .ThrowAsJavaScriptException();
        return env.Undefined();
    }
    rac_handle_t h = handle_for(g_tts_handles, info[0].As<Napi::Number>().Int32Value());
    if (!h) {
        Napi::Error::New(env, "invalid tts handle").ThrowAsJavaScriptException();
        return env.Undefined();
    }
    std::string text = info[1].As<Napi::String>().Utf8Value();
    rac_tts_result_t result;
    std::memset(&result, 0, sizeof(result));
    rac_result_t rc = rac_tts_component_synthesize(h, text.c_str(), nullptr, &result);
    if (rc != RAC_SUCCESS) {
        Napi::Error::New(env, "synthesize failed: " + std::to_string(rc))
            .ThrowAsJavaScriptException();
        return env.Undefined();
    }
    size_t n = result.audio_size / sizeof(float);  // audio_data is float32 PCM
    Napi::Float32Array samples = Napi::Float32Array::New(env, n);
    if (result.audio_data && n) std::memcpy(samples.Data(), result.audio_data, n * sizeof(float));
    int32_t sr = result.sample_rate;
    rac_tts_result_free(&result);
    Napi::Object out = Napi::Object::New(env);
    out.Set("sampleRate", Napi::Number::New(env, sr));
    out.Set("samples", samples);
    return out;
}

Napi::Value UnloadTtsVoice(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    if (info.Length() < 1 || !info[0].IsNumber()) return env.Undefined();
    int32_t hid = info[0].As<Napi::Number>().Int32Value();
    rac_handle_t h = nullptr;
    {
        std::lock_guard<std::mutex> lock(g_handles_mutex);
        auto it = g_tts_handles.find(hid);
        if (it != g_tts_handles.end()) {
            h = it->second;
            g_tts_handles.erase(it);
        }
    }
    if (h) rac_tts_component_destroy(h);
    return env.Undefined();
}

// =============================================================================
// shutdown()
// =============================================================================
Napi::Value Shutdown(const Napi::CallbackInfo& info) {
    if (g_initialized.exchange(false)) {
        // Destroy every still-loaded component and clear the handle maps so no id
        // outlives the runtime — a later unload/use can't touch freed native
        // state, and a re-init starts from a clean slate.
        {
            std::lock_guard<std::mutex> lock(g_handles_mutex);
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
        }
        rac_shutdown();
    }
    return info.Env().Undefined();
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
        Napi::TypeError::New(env, "secureSet(key, value) expects strings").ThrowAsJavaScriptException();
        return env.Undefined();
    }
    if (!g_adapter.secure_set) {
        Napi::Error::New(env, "secure store unavailable").ThrowAsJavaScriptException();
        return env.Undefined();
    }
    std::string key = info[0].As<Napi::String>().Utf8Value();
    std::string value = info[1].As<Napi::String>().Utf8Value();
    rac_result_t rc = g_adapter.secure_set(key.c_str(), value.c_str(), g_adapter.user_data);
    if (rc != RAC_SUCCESS) {
        Napi::Error::New(env, "secure_set failed: " + std::to_string(rc)).ThrowAsJavaScriptException();
    }
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
        return env.Null();  // clean miss
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

// =============================================================================
// Voice activity detection (built-in energy VAD; no model required).
// =============================================================================
Napi::Value CreateVad(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    if (!g_initialized.load()) {
        Napi::Error::New(env, "not initialized").ThrowAsJavaScriptException();
        return env.Undefined();
    }
    rac_handle_t h = nullptr;
    if (rac_vad_component_create(&h) != RAC_SUCCESS || !h) {
        Napi::Error::New(env, "vad create failed").ThrowAsJavaScriptException();
        return env.Undefined();
    }
    rac_vad_config_t cfg = RAC_VAD_CONFIG_DEFAULT;
    if (info.Length() >= 1 && info[0].IsNumber()) {
        cfg.energy_threshold = info[0].As<Napi::Number>().FloatValue();
    }
    if (rac_vad_component_configure(h, &cfg) != RAC_SUCCESS ||
        rac_vad_component_initialize(h) != RAC_SUCCESS) {
        rac_vad_component_destroy(h);
        Napi::Error::New(env, "vad configure/initialize failed").ThrowAsJavaScriptException();
        return env.Undefined();
    }
    int32_t hid;
    {
        std::lock_guard<std::mutex> lock(g_handles_mutex);
        hid = g_next_handle_id++;
        g_vad_handles[hid] = h;
    }
    return Napi::Number::New(env, hid);
}

// vadProcess(handleId, Float32Array) -> bool (speech in this frame).
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
    rac_handle_t h = handle_for(g_vad_handles, info[0].As<Napi::Number>().Int32Value());
    if (!h) {
        Napi::Error::New(env, "invalid vad handle").ThrowAsJavaScriptException();
        return env.Undefined();
    }
    Napi::Float32Array arr = ta.As<Napi::Float32Array>();
    rac_bool_t is_speech = RAC_FALSE;
    rac_result_t rc = rac_vad_component_process(h, arr.Data(), arr.ElementLength(), &is_speech);
    if (rc != RAC_SUCCESS) {
        Napi::Error::New(env, "vad process failed: " + std::to_string(rc)).ThrowAsJavaScriptException();
        return env.Undefined();
    }
    return Napi::Boolean::New(env, is_speech == RAC_TRUE);
}

Napi::Value VadIsActive(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    if (info.Length() < 1 || !info[0].IsNumber()) return Napi::Boolean::New(env, false);
    rac_handle_t h = handle_for(g_vad_handles, info[0].As<Napi::Number>().Int32Value());
    if (!h) return Napi::Boolean::New(env, false);
    return Napi::Boolean::New(env, rac_vad_component_is_speech_active(h) == RAC_TRUE);
}

Napi::Value VadSetThreshold(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    if (info.Length() < 2 || !info[0].IsNumber() || !info[1].IsNumber()) return env.Undefined();
    rac_handle_t h = handle_for(g_vad_handles, info[0].As<Napi::Number>().Int32Value());
    if (h) rac_vad_component_set_energy_threshold(h, info[1].As<Napi::Number>().FloatValue());
    return env.Undefined();
}

Napi::Value VadReset(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    if (info.Length() < 1 || !info[0].IsNumber()) return env.Undefined();
    rac_handle_t h = handle_for(g_vad_handles, info[0].As<Napi::Number>().Int32Value());
    if (h) rac_vad_component_reset(h);
    return env.Undefined();
}

Napi::Value UnloadVad(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    if (info.Length() < 1 || !info[0].IsNumber()) return env.Undefined();
    int32_t hid = info[0].As<Napi::Number>().Int32Value();
    rac_handle_t h = nullptr;
    {
        std::lock_guard<std::mutex> lock(g_handles_mutex);
        auto it = g_vad_handles.find(hid);
        if (it != g_vad_handles.end()) {
            h = it->second;
            g_vad_handles.erase(it);
        }
    }
    if (h) rac_vad_component_destroy(h);
    return env.Undefined();
}

// ---- RAG (retrieval-augmented generation) -------------------------------
//
// Proto-byte C ABI: the SDK encodes runanywhere.v1 RAG* messages (ts-proto) and
// hands them across as Buffers; commons returns serialized RAGResult/RAGStatistics
// in an owned rac_proto_buffer_t that we copy into a Napi::Buffer and free.

// Copy an owned proto-out buffer to a JS Buffer (throwing on failure), always
// releasing the native buffer.
static Napi::Value rag_out_to_js(Napi::Env env, rac_proto_buffer_t* buf, const char* what) {
    if (buf->status != RAC_SUCCESS || buf->data == nullptr) {
        std::string msg = std::string(what) + " failed: " + std::to_string(buf->status);
        if (buf->error_message) { msg += " ("; msg += buf->error_message; msg += ")"; }
        rac_proto_buffer_free(buf);
        Napi::Error::New(env, msg).ThrowAsJavaScriptException();
        return env.Undefined();
    }
    Napi::Buffer<uint8_t> out = Napi::Buffer<uint8_t>::Copy(env, buf->data, buf->size);
    rac_proto_buffer_free(buf);
    return out;
}

// Register a downloaded model in commons' global registry (id -> local_path) so
// RAG session-create can resolve embedding/LLM model ids to on-disk paths. The
// Electron SDK otherwise loads models by explicit path and never populates the
// registry, so RAG needs this bridge. rac_register_model deep-copies the struct.
static char* rag_dup_cstr(const std::string& s) {
    char* p = static_cast<char*>(std::malloc(s.size() + 1));
    if (p) std::memcpy(p, s.c_str(), s.size() + 1);
    return p;
}

Napi::Value RegisterModel(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    if (info.Length() < 2 || !info[0].IsString() || !info[1].IsString()) {
        Napi::TypeError::New(env, "registerModel(id, path, category?, framework?) bad args").ThrowAsJavaScriptException();
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
        Napi::Error::New(env, "registerModel failed: " + std::to_string(rc)).ThrowAsJavaScriptException();
        return env.Undefined();
    }
    return env.Undefined();
}

Napi::Value RagCreateSession(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    // Proto bytes arrive as a Uint8Array (Buffers degrade to Uint8Array crossing
    // the utility-host MessagePort), so accept any typed array, not just Buffer.
    if (info.Length() < 1 || !info[0].IsTypedArray()) {
        Napi::TypeError::New(env, "ragCreateSession(configProtoBytes) bad args").ThrowAsJavaScriptException();
        return env.Undefined();
    }
    Napi::Uint8Array cfg = info[0].As<Napi::Uint8Array>();
    rac_handle_t h = nullptr;
    rac_result_t rc = rac_rag_session_create_proto(cfg.Data(), cfg.ByteLength(), &h);
    if (rc != RAC_SUCCESS || h == nullptr) {
        Napi::Error::New(env, "rag session create failed: " + std::to_string(rc)).ThrowAsJavaScriptException();
        return env.Undefined();
    }
    int32_t hid;
    {
        std::lock_guard<std::mutex> lock(g_handles_mutex);
        hid = g_next_handle_id++;
        g_rag_handles[hid] = h;
    }
    return Napi::Number::New(env, hid);
}

Napi::Value RagIngest(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    if (info.Length() < 2 || !info[0].IsNumber() || !info[1].IsTypedArray()) {
        Napi::TypeError::New(env, "ragIngest(handleId, documentProtoBytes) bad args").ThrowAsJavaScriptException();
        return env.Undefined();
    }
    rac_handle_t h = handle_for(g_rag_handles, info[0].As<Napi::Number>().Int32Value());
    if (!h) { Napi::Error::New(env, "invalid rag handle").ThrowAsJavaScriptException(); return env.Undefined(); }
    Napi::Uint8Array doc = info[1].As<Napi::Uint8Array>();
    rac_proto_buffer_t out;
    rac_proto_buffer_init(&out);
    rac_result_t rc = rac_rag_ingest_proto(h, doc.Data(), doc.ByteLength(), &out);
    if (rc != RAC_SUCCESS && out.status == RAC_SUCCESS) out.status = rc;
    return rag_out_to_js(env, &out, "rag ingest");
}

Napi::Value RagQuery(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    if (info.Length() < 2 || !info[0].IsNumber() || !info[1].IsTypedArray()) {
        Napi::TypeError::New(env, "ragQuery(handleId, queryProtoBytes) bad args").ThrowAsJavaScriptException();
        return env.Undefined();
    }
    rac_handle_t h = handle_for(g_rag_handles, info[0].As<Napi::Number>().Int32Value());
    if (!h) { Napi::Error::New(env, "invalid rag handle").ThrowAsJavaScriptException(); return env.Undefined(); }
    Napi::Uint8Array q = info[1].As<Napi::Uint8Array>();
    rac_proto_buffer_t out;
    rac_proto_buffer_init(&out);
    rac_result_t rc = rac_rag_query_proto(h, q.Data(), q.ByteLength(), &out);
    if (rc != RAC_SUCCESS && out.status == RAC_SUCCESS) out.status = rc;
    return rag_out_to_js(env, &out, "rag query");
}

Napi::Value RagClear(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    if (info.Length() < 1 || !info[0].IsNumber()) {
        Napi::TypeError::New(env, "ragClear(handleId) bad args").ThrowAsJavaScriptException();
        return env.Undefined();
    }
    rac_handle_t h = handle_for(g_rag_handles, info[0].As<Napi::Number>().Int32Value());
    if (!h) { Napi::Error::New(env, "invalid rag handle").ThrowAsJavaScriptException(); return env.Undefined(); }
    rac_proto_buffer_t out;
    rac_proto_buffer_init(&out);
    rac_result_t rc = rac_rag_clear_proto(h, &out);
    if (rc != RAC_SUCCESS && out.status == RAC_SUCCESS) out.status = rc;
    return rag_out_to_js(env, &out, "rag clear");
}

Napi::Value RagStats(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    if (info.Length() < 1 || !info[0].IsNumber()) {
        Napi::TypeError::New(env, "ragStats(handleId) bad args").ThrowAsJavaScriptException();
        return env.Undefined();
    }
    rac_handle_t h = handle_for(g_rag_handles, info[0].As<Napi::Number>().Int32Value());
    if (!h) { Napi::Error::New(env, "invalid rag handle").ThrowAsJavaScriptException(); return env.Undefined(); }
    rac_proto_buffer_t out;
    rac_proto_buffer_init(&out);
    rac_result_t rc = rac_rag_stats_proto(h, &out);
    if (rc != RAC_SUCCESS && out.status == RAC_SUCCESS) out.status = rc;
    return rag_out_to_js(env, &out, "rag stats");
}

Napi::Value RagDestroySession(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    if (info.Length() < 1 || !info[0].IsNumber()) return env.Undefined();
    int32_t hid = info[0].As<Napi::Number>().Int32Value();
    rac_handle_t h = nullptr;
    {
        std::lock_guard<std::mutex> lock(g_handles_mutex);
        auto it = g_rag_handles.find(hid);
        if (it != g_rag_handles.end()) { h = it->second; g_rag_handles.erase(it); }
    }
    if (h) rac_rag_session_destroy_proto(h);
    return env.Undefined();
}

Napi::Object Init(Napi::Env env, Napi::Object exports) {
    exports.Set("initialize", Napi::Function::New(env, Initialize));
    exports.Set("secureSet", Napi::Function::New(env, SecureSet));
    exports.Set("secureGet", Napi::Function::New(env, SecureGet));
    exports.Set("secureDelete", Napi::Function::New(env, SecureDelete));
    exports.Set("createVad", Napi::Function::New(env, CreateVad));
    exports.Set("vadProcess", Napi::Function::New(env, VadProcess));
    exports.Set("vadIsActive", Napi::Function::New(env, VadIsActive));
    exports.Set("vadSetThreshold", Napi::Function::New(env, VadSetThreshold));
    exports.Set("vadReset", Napi::Function::New(env, VadReset));
    exports.Set("unloadVad", Napi::Function::New(env, UnloadVad));
    exports.Set("loadModel", Napi::Function::New(env, LoadModel));
    exports.Set("generate", Napi::Function::New(env, Generate));
    exports.Set("unloadModel", Napi::Function::New(env, UnloadModel));
    exports.Set("loadVlmModel", Napi::Function::New(env, LoadVlmModel));
    exports.Set("generateVlm", Napi::Function::New(env, GenerateVlm));
    exports.Set("unloadVlmModel", Napi::Function::New(env, UnloadVlmModel));
    exports.Set("loadEmbeddingModel", Napi::Function::New(env, LoadEmbeddingModel));
    exports.Set("embed", Napi::Function::New(env, Embed));
    exports.Set("unloadEmbeddingModel", Napi::Function::New(env, UnloadEmbeddingModel));
    exports.Set("loadSttModel", Napi::Function::New(env, LoadSttModel));
    exports.Set("transcribe", Napi::Function::New(env, Transcribe));
    exports.Set("unloadSttModel", Napi::Function::New(env, UnloadSttModel));
    exports.Set("loadTtsVoice", Napi::Function::New(env, LoadTtsVoice));
    exports.Set("synthesize", Napi::Function::New(env, Synthesize));
    exports.Set("unloadTtsVoice", Napi::Function::New(env, UnloadTtsVoice));
    exports.Set("registerModel", Napi::Function::New(env, RegisterModel));
    exports.Set("ragCreateSession", Napi::Function::New(env, RagCreateSession));
    exports.Set("ragIngest", Napi::Function::New(env, RagIngest));
    exports.Set("ragQuery", Napi::Function::New(env, RagQuery));
    exports.Set("ragClear", Napi::Function::New(env, RagClear));
    exports.Set("ragStats", Napi::Function::New(env, RagStats));
    exports.Set("ragDestroySession", Napi::Function::New(env, RagDestroySession));
    exports.Set("shutdown", Napi::Function::New(env, Shutdown));
    exports.Set("version", Napi::String::New(env, rac_sdk_get_version()));
    return exports;
}

}  // namespace

NODE_API_MODULE(runanywhere_native, Init)
