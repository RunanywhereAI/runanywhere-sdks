// addon.cpp — RunAnywhere Electron N-API addon.
//
// M1a: proves the .node loads in Node/Electron (MSVC ABI) and drives the rac_*
// C ABI + llama.cpp: initialize (Win32 platform adapter) -> loadModel -> generate
// (streaming tokens to a JS callback via Napi::ThreadSafeFunction on a worker
// thread, returning a Promise) -> unloadModel / shutdown. Reuses the exact Win32
// adapter proven by the M0 harness. Node-API only (node_api.h via node-addon-api),
// so one prebuilt spans Node/Electron versions.

#include <napi.h>

#include <atomic>
#include <cstring>
#include <mutex>
#include <string>
#include <thread>
#include <unordered_map>

#include "win32_platform_adapter.h"

#include "rac/backends/rac_llm_llamacpp.h"
#include "rac/core/rac_core.h"
#include "rac/core/rac_types.h"
#include "rac/features/llm/rac_llm_component.h"
#include "rac/infrastructure/model_management/rac_model_paths.h"

namespace {

// The adapter struct is caller-owned and must outlive rac_shutdown(); keep it in
// static storage. Set once during initialize() before rac_init().
rac_platform_adapter_t g_adapter;
std::atomic<bool> g_initialized{false};

// LLM handles are exposed to JS as small integer ids.
std::mutex g_handles_mutex;
std::unordered_map<int32_t, rac_handle_t> g_handles;
int32_t g_next_handle_id = 1;

rac_handle_t handle_for(int32_t id) {
    std::lock_guard<std::mutex> lock(g_handles_mutex);
    auto it = g_handles.find(id);
    return (it == g_handles.end()) ? nullptr : it->second;
}

// -------------------------------------------------------------------------
// initialize(secureDir[, baseDir])
// -------------------------------------------------------------------------
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

// -------------------------------------------------------------------------
// loadModel(path[, id[, name]]) -> handleId (number)
// -------------------------------------------------------------------------
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
        g_handles[hid] = h;
    }
    return Napi::Number::New(env, hid);
}

// -------------------------------------------------------------------------
// generate(handleId, prompt, onToken) -> Promise<void>
//
// The rac generate_stream call blocks its calling thread and invokes the token
// callback inline, so we run it on a std::thread and marshal each token to JS via
// a bounded ThreadSafeFunction (BlockingCall = automatic backpressure). The
// Promise resolves/rejects in the TSFN finalizer, which runs on the JS loop once
// the producer thread has Release()d.
// -------------------------------------------------------------------------
struct GenCtx {
    rac_handle_t handle{};
    std::string prompt;
    Napi::ThreadSafeFunction tsfn;
    std::thread worker;
    Napi::Promise::Deferred deferred;
    rac_result_t result = RAC_SUCCESS;
    std::string error_msg;
    explicit GenCtx(Napi::Env env) : deferred(Napi::Promise::Deferred::New(env)) {}
};

rac_bool_t gen_token_cb(const char* token, void* ud) {
    auto* ctx = static_cast<GenCtx*>(ud);
    std::string tok = token ? token : "";  // copy out — the buffer is transient
    napi_status st = ctx->tsfn.BlockingCall([tok](Napi::Env env, Napi::Function jsCb) {
        jsCb.Call({Napi::String::New(env, tok)});  // JS values built on the JS thread
    });
    return (st == napi_ok) ? RAC_TRUE : RAC_FALSE;  // napi_closing -> stop generation
}

void gen_complete_cb(const rac_llm_result_t*, void* ud) {
    static_cast<GenCtx*>(ud)->result = RAC_SUCCESS;
}

void gen_error_cb(rac_result_t code, const char* msg, void* ud) {
    auto* ctx = static_cast<GenCtx*>(ud);
    ctx->result = code;
    ctx->error_msg = msg ? msg : "generation error";
}

Napi::Value Generate(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    if (info.Length() < 3 || !info[0].IsNumber() || !info[1].IsString() || !info[2].IsFunction()) {
        Napi::TypeError::New(env, "generate(handleId, prompt, onToken) bad args")
            .ThrowAsJavaScriptException();
        return env.Undefined();
    }
    int32_t hid = info[0].As<Napi::Number>().Int32Value();
    rac_handle_t h = handle_for(hid);
    if (!h) {
        Napi::Error::New(env, "invalid handle").ThrowAsJavaScriptException();
        return env.Undefined();
    }

    auto* ctx = new GenCtx(env);
    ctx->handle = h;
    ctx->prompt = info[1].As<Napi::String>().Utf8Value();

    ctx->tsfn = Napi::ThreadSafeFunction::New(
        env, info[2].As<Napi::Function>(), "ra-generate", /*maxQueueSize*/ 256,
        /*initialThreadCount*/ 1, ctx,
        [](Napi::Env env, void* /*data*/, GenCtx* c) {
            if (c->worker.joinable()) c->worker.join();
            if (c->result == RAC_SUCCESS) {
                c->deferred.Resolve(env.Undefined());
            } else {
                std::string msg = c->error_msg.empty()
                                      ? ("generate failed: " + std::to_string(c->result))
                                      : c->error_msg;
                c->deferred.Reject(Napi::Error::New(env, msg).Value());
            }
            delete c;
        },
        static_cast<void*>(nullptr));

    ctx->worker = std::thread([ctx]() {
        rac_result_t rc = rac_llm_component_generate_stream(
            ctx->handle, ctx->prompt.c_str(), nullptr, gen_token_cb, gen_complete_cb, gen_error_cb,
            ctx);
        if (rc != RAC_SUCCESS && ctx->result == RAC_SUCCESS) ctx->result = rc;
        ctx->tsfn.Release();  // last TSFN call from this thread -> finalizer on JS loop
    });

    return ctx->deferred.Promise();
}

// -------------------------------------------------------------------------
// unloadModel(handleId) / shutdown()
// -------------------------------------------------------------------------
Napi::Value UnloadModel(const Napi::CallbackInfo& info) {
    Napi::Env env = info.Env();
    if (info.Length() < 1 || !info[0].IsNumber()) return env.Undefined();
    int32_t hid = info[0].As<Napi::Number>().Int32Value();
    rac_handle_t h = nullptr;
    {
        std::lock_guard<std::mutex> lock(g_handles_mutex);
        auto it = g_handles.find(hid);
        if (it != g_handles.end()) {
            h = it->second;
            g_handles.erase(it);
        }
    }
    if (h) rac_llm_component_destroy(h);
    return env.Undefined();
}

Napi::Value Shutdown(const Napi::CallbackInfo& info) {
    if (g_initialized.exchange(false)) rac_shutdown();
    return info.Env().Undefined();
}

Napi::Object Init(Napi::Env env, Napi::Object exports) {
    exports.Set("initialize", Napi::Function::New(env, Initialize));
    exports.Set("loadModel", Napi::Function::New(env, LoadModel));
    exports.Set("generate", Napi::Function::New(env, Generate));
    exports.Set("unloadModel", Napi::Function::New(env, UnloadModel));
    exports.Set("shutdown", Napi::Function::New(env, Shutdown));
    exports.Set("version", Napi::String::New(env, rac_sdk_get_version()));
    return exports;
}

}  // namespace

NODE_API_MODULE(runanywhere_native, Init)
