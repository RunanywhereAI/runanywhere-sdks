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
#include "rac/infrastructure/model_management/rac_model_paths.h"

namespace {

// The adapter struct is caller-owned and must outlive rac_shutdown().
rac_platform_adapter_t g_adapter;
std::atomic<bool> g_initialized{false};

// Handles are exposed to JS as small integer ids. LLM and VLM components use
// distinct rac_*_component_destroy calls, so they live in separate maps.
std::mutex g_handles_mutex;
std::unordered_map<int32_t, rac_handle_t> g_llm_handles;
std::unordered_map<int32_t, rac_handle_t> g_vlm_handles;
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
        return rac_vlm_component_process_stream(h, &image, prompt.c_str(), nullptr, stream_token_cb,
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
    exports.Set("shutdown", Napi::Function::New(env, Shutdown));
    exports.Set("version", Napi::String::New(env, rac_sdk_get_version()));
    return exports;
}

}  // namespace

NODE_API_MODULE(runanywhere_native, Init)
