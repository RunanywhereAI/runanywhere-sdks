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
#include "rac/infrastructure/model_management/rac_model_paths.h"

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

Napi::Value Generate(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    if (info.Length() < 3 || !info[0].IsNumber() || !info[1].IsString() || !info[2].IsFunction()) {
        Napi::TypeError::New(env, "generate(handleId, prompt, onToken) bad args")
            .ThrowAsJavaScriptException();
        return env.Undefined();
    }
    rac_handle_t h = handle_for(g_llm_handles, info[0].As<Napi::Number>().Int32Value());
    if (!h) {
        Napi::Error::New(env, "invalid handle").ThrowAsJavaScriptException();
        return env.Undefined();
    }
    std::string prompt = info[1].As<Napi::String>().Utf8Value();
    return start_stream(env, info[2].As<Napi::Function>(), [h, prompt](StreamCtx* c) {
        return rac_llm_component_generate_stream(h, prompt.c_str(), nullptr, stream_token_cb,
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
    if (info.Length() < 2 || !info[0].IsNumber() || !info[1].IsBuffer()) {
        Napi::TypeError::New(env, "transcribe(handleId, pcm16Buffer) bad args")
            .ThrowAsJavaScriptException();
        return env.Undefined();
    }
    rac_handle_t h = handle_for(g_stt_handles, info[0].As<Napi::Number>().Int32Value());
    if (!h) {
        Napi::Error::New(env, "invalid stt handle").ThrowAsJavaScriptException();
        return env.Undefined();
    }
    Napi::Buffer<uint8_t> buf = info[1].As<Napi::Buffer<uint8_t>>();
    rac_stt_result_t result;
    std::memset(&result, 0, sizeof(result));
    rac_result_t rc =
        rac_stt_component_transcribe(h, buf.Data(), buf.Length(), nullptr, &result);
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
    if (g_initialized.exchange(false)) rac_shutdown();
    return info.Env().Undefined();
}

Napi::Object Init(Napi::Env env, Napi::Object exports) {
    exports.Set("initialize", Napi::Function::New(env, Initialize));
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
    exports.Set("shutdown", Napi::Function::New(env, Shutdown));
    exports.Set("version", Napi::String::New(env, rac_sdk_get_version()));
    return exports;
}

}  // namespace

NODE_API_MODULE(runanywhere_native, Init)
