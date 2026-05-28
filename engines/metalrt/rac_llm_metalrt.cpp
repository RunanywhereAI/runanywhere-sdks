/**
 * @file rac_llm_metalrt.cpp
 * @brief MetalRT LLM backend — wraps metalrt_c_api.h for LLM inference
 */

#include "rac_llm_metalrt.h"

#include "metalrt_c_api.h"
#include "rac_runtime_metal.h"

#include <atomic>
#include <condition_variable>
#include <cstdlib>
#include <cstring>
#include <mutex>

#include "rac/core/rac_logger.h"

static const char* LOG_CAT = "LLM.MetalRT";

// =============================================================================
// INTERNAL HANDLE
// =============================================================================

// engines-003 (CLUSTER-211): MetalRT's underlying engine is a closed-source
// vendor library with no documented thread-safety guarantee, and the public
// `destroy` entrypoint races any in-flight `generate` / `generate_stream`.
// The previous design guarded only `handle` / `loaded` with `mutex_` + an
// atomic but ran inference lock-free, which left `impl->handle` and the
// `impl` allocation itself unprotected once destroy fell through the lock
// and called `delete impl;` — a textbook UAF. We adopt the lifecycle
// layer's acquire/release pin pattern (see
// `sdk/runanywhere-commons/src/core/capabilities/lifecycle_manager.cpp`
// `rac_lifecycle_acquire_service` / `rac_lifecycle_release_service`):
// every public op pins the impl for the duration of the metalrt call, and
// destroy parks on a condvar until the refcount drains. Concurrent token-
// by-token streaming therefore stays lock-free during a single call but
// teardown is fenced.
struct rac_llm_metalrt_impl {
    void* handle = nullptr;  // metalrt_create() handle
    std::atomic<bool> loaded{false};
    mutable std::mutex mutex_;
    std::condition_variable cv_;
    int refcount_ = 0;  // guarded by mutex_
};

namespace {

// RAII pin: bumps refcount under the impl mutex if `loaded`, captures the
// engine handle, and releases (with notify) on destruction. The captured
// handle stays valid for the pin's lifetime — destroy waits on cv_ for
// refcount to drain before tearing the engine handle down and deleting
// the impl.
class MetalRTLLMPin {
   public:
    explicit MetalRTLLMPin(rac_llm_metalrt_impl* impl) : impl_(impl) {
        if (impl_ == nullptr)
            return;
        std::lock_guard<std::mutex> lock(impl_->mutex_);
        if (!impl_->loaded.load(std::memory_order_acquire) || impl_->handle == nullptr)
            return;
        handle_ = impl_->handle;
        impl_->refcount_++;
        pinned_ = true;
    }
    MetalRTLLMPin(const MetalRTLLMPin&) = delete;
    MetalRTLLMPin& operator=(const MetalRTLLMPin&) = delete;
    ~MetalRTLLMPin() {
        if (!pinned_)
            return;
        bool notify = false;
        {
            std::lock_guard<std::mutex> lock(impl_->mutex_);
            impl_->refcount_--;
            notify = (impl_->refcount_ == 0);
        }
        if (notify)
            impl_->cv_.notify_all();
    }
    bool pinned() const { return pinned_; }
    void* handle() const { return handle_; }

   private:
    rac_llm_metalrt_impl* impl_ = nullptr;
    void* handle_ = nullptr;
    bool pinned_ = false;
};

}  // namespace

// =============================================================================
// API IMPLEMENTATION
// =============================================================================

extern "C" {

rac_result_t rac_llm_metalrt_create(const char* model_path, rac_handle_t* out_handle) {
    if (out_handle == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }
    rac_result_t runtime_rc = rac_metal_runtime_require_available();
    if (runtime_rc != RAC_SUCCESS)
        return runtime_rc;

    auto* impl = new (std::nothrow) rac_llm_metalrt_impl();
    if (!impl) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }

    impl->handle = metalrt_create();
    if (!impl->handle) {
        delete impl;
        rac_error_set_details("metalrt_create() returned null");
        return RAC_ERROR_BACKEND_INIT_FAILED;
    }

    if (model_path && model_path[0] != '\0') {
        if (!metalrt_load(impl->handle, model_path)) {
            metalrt_destroy(impl->handle);
            delete impl;
            rac_error_set_details("metalrt_load() failed");
            return RAC_ERROR_MODEL_LOAD_FAILED;
        }
        impl->loaded.store(true, std::memory_order_release);
        RAC_LOG_INFO(LOG_CAT, "Model loaded: %s", model_path);
    }

    *out_handle = static_cast<rac_handle_t>(impl);
    return RAC_SUCCESS;
}

void rac_llm_metalrt_destroy(rac_handle_t handle) {
    if (!handle)
        return;
    auto* impl = static_cast<rac_llm_metalrt_impl*>(handle);
    {
        std::unique_lock<std::mutex> lock(impl->mutex_);
        // Flip loaded first so any new entrant fails fast (see pin ctor).
        impl->loaded.store(false, std::memory_order_release);
        // Wait until every in-flight pin releases before touching the
        // engine handle or freeing the impl.
        impl->cv_.wait(lock, [impl] { return impl->refcount_ == 0; });
        if (impl->handle) {
            metalrt_destroy(impl->handle);
            impl->handle = nullptr;
        }
    }
    delete impl;
}

rac_bool_t rac_llm_metalrt_is_loaded(rac_handle_t handle) {
    if (!handle)
        return RAC_FALSE;
    auto* impl = static_cast<rac_llm_metalrt_impl*>(handle);
    return impl->loaded.load(std::memory_order_acquire) ? RAC_TRUE : RAC_FALSE;
}

rac_result_t rac_llm_metalrt_generate(rac_handle_t handle, const char* prompt,
                                      const rac_llm_options_t* options,
                                      rac_llm_result_t* out_result) {
    if (!handle || !prompt || !out_result)
        return RAC_ERROR_NULL_POINTER;
    auto* impl = static_cast<rac_llm_metalrt_impl*>(handle);
    MetalRTLLMPin pin(impl);
    if (!pin.pinned())
        return RAC_ERROR_BACKEND_NOT_READY;

    struct MetalRTOptions opts = {};
    opts.max_tokens = options ? options->max_tokens : 100;
    opts.temperature = options ? options->temperature : 0.8f;
    opts.top_k = 40;
    opts.think = false;
    opts.reset_cache = true;
    opts.ignore_eos = false;

    struct MetalRTResult result = metalrt_generate(pin.handle(), prompt, &opts);

    out_result->text = result.text ? strdup(result.text) : nullptr;
    out_result->prompt_tokens = result.prompt_tokens;
    out_result->completion_tokens = result.generated_tokens;
    out_result->total_tokens = result.prompt_tokens + result.generated_tokens;
    out_result->time_to_first_token_ms = static_cast<int64_t>(result.prefill_ms);
    out_result->total_time_ms = static_cast<int64_t>(result.prefill_ms + result.decode_ms);
    out_result->tokens_per_second = static_cast<float>(result.tps);

    metalrt_free_result(result);
    return RAC_SUCCESS;
}

// Adapter to bridge MetalRT's callback to RAC's callback,
// with client-side max_tokens enforcement since the engine may overshoot.
struct MetalRTStreamCtx {
    rac_llm_metalrt_stream_cb callback;
    void* user_data;
    int32_t max_tokens;
    int32_t emitted_tokens;
    bool client_cancelled;
};

static bool metalrt_stream_bridge(const char* piece, void* ctx) {
    auto* adapter = static_cast<MetalRTStreamCtx*>(ctx);
    if (!adapter || !adapter->callback)
        return false;
    if (adapter->max_tokens > 0 && adapter->emitted_tokens >= adapter->max_tokens) {
        return false;
    }
    adapter->emitted_tokens++;
    if (adapter->callback(piece, RAC_FALSE, adapter->user_data) != RAC_TRUE) {
        adapter->client_cancelled = true;
        return false;
    }
    return true;
}

rac_result_t rac_llm_metalrt_generate_stream(rac_handle_t handle, const char* prompt,
                                             const rac_llm_options_t* options,
                                             rac_llm_metalrt_stream_cb callback, void* user_data) {
    if (!handle || !prompt || !callback)
        return RAC_ERROR_NULL_POINTER;
    auto* impl = static_cast<rac_llm_metalrt_impl*>(handle);
    MetalRTLLMPin pin(impl);
    if (!pin.pinned())
        return RAC_ERROR_BACKEND_NOT_READY;

    int32_t max_tok = options ? options->max_tokens : 100;

    struct MetalRTOptions opts = {};
    opts.max_tokens = max_tok;
    opts.temperature = options ? options->temperature : 0.8f;
    opts.top_k = 40;
    opts.think = false;
    opts.reset_cache = true;
    opts.ignore_eos = false;

    MetalRTStreamCtx ctx = {callback, user_data, max_tok, 0, false};
    struct MetalRTResult result =
        metalrt_generate_stream(pin.handle(), prompt, metalrt_stream_bridge, &ctx, &opts);

    // Send final token only if client did not cancel.
    if (!ctx.client_cancelled) {
        callback("", RAC_TRUE, user_data);
    }

    metalrt_free_result(result);
    return ctx.client_cancelled ? RAC_ERROR_STREAM_CANCELLED : RAC_SUCCESS;
}

rac_result_t rac_llm_metalrt_inject_system_prompt(rac_handle_t handle, const char* prompt) {
    if (!handle || !prompt)
        return RAC_ERROR_NULL_POINTER;
    auto* impl = static_cast<rac_llm_metalrt_impl*>(handle);
    MetalRTLLMPin pin(impl);
    if (!pin.pinned())
        return RAC_ERROR_BACKEND_NOT_READY;
    metalrt_set_system_prompt(pin.handle(), prompt);
    return RAC_SUCCESS;
}

rac_result_t rac_llm_metalrt_append_context(rac_handle_t handle, const char* text) {
    if (!handle || !text)
        return RAC_ERROR_NULL_POINTER;
    auto* impl = static_cast<rac_llm_metalrt_impl*>(handle);
    MetalRTLLMPin pin(impl);
    if (!pin.pinned())
        return RAC_ERROR_BACKEND_NOT_READY;
    metalrt_cache_prompt(pin.handle(), text);
    return RAC_SUCCESS;
}

rac_result_t rac_llm_metalrt_generate_from_context(rac_handle_t handle, const char* query,
                                                   const rac_llm_options_t* options,
                                                   rac_llm_result_t* out_result) {
    if (!handle || !query || !out_result)
        return RAC_ERROR_NULL_POINTER;
    auto* impl = static_cast<rac_llm_metalrt_impl*>(handle);
    MetalRTLLMPin pin(impl);
    if (!pin.pinned())
        return RAC_ERROR_BACKEND_NOT_READY;

    struct MetalRTOptions opts = {};
    opts.max_tokens = options ? options->max_tokens : 100;
    opts.temperature = options ? options->temperature : 0.8f;
    opts.top_k = 40;
    opts.think = false;
    opts.reset_cache = false;
    opts.ignore_eos = false;

    struct MetalRTResult result = metalrt_generate_raw_continue(pin.handle(), query, &opts);

    out_result->text = result.text ? strdup(result.text) : nullptr;
    out_result->prompt_tokens = result.prompt_tokens;
    out_result->completion_tokens = result.generated_tokens;
    out_result->total_tokens = result.prompt_tokens + result.generated_tokens;
    out_result->time_to_first_token_ms = static_cast<int64_t>(result.prefill_ms);
    out_result->total_time_ms = static_cast<int64_t>(result.prefill_ms + result.decode_ms);
    out_result->tokens_per_second = static_cast<float>(result.tps);

    metalrt_free_result(result);
    return RAC_SUCCESS;
}

rac_result_t rac_llm_metalrt_clear_context(rac_handle_t handle) {
    if (!handle)
        return RAC_ERROR_NULL_POINTER;
    auto* impl = static_cast<rac_llm_metalrt_impl*>(handle);
    MetalRTLLMPin pin(impl);
    if (!pin.pinned())
        return RAC_ERROR_BACKEND_NOT_READY;
    metalrt_clear_kv(pin.handle());
    return RAC_SUCCESS;
}

void rac_llm_metalrt_reset(rac_handle_t handle) {
    if (!handle)
        return;
    auto* impl = static_cast<rac_llm_metalrt_impl*>(handle);
    MetalRTLLMPin pin(impl);
    if (!pin.pinned())
        return;
    metalrt_reset(pin.handle());
}

int rac_llm_metalrt_context_size(rac_handle_t handle) {
    if (!handle)
        return 0;
    auto* impl = static_cast<rac_llm_metalrt_impl*>(handle);
    MetalRTLLMPin pin(impl);
    if (!pin.pinned())
        return 0;
    return metalrt_context_size(pin.handle());
}

const char* rac_llm_metalrt_model_name(rac_handle_t handle) {
    if (!handle)
        return nullptr;
    auto* impl = static_cast<rac_llm_metalrt_impl*>(handle);
    MetalRTLLMPin pin(impl);
    if (!pin.pinned())
        return nullptr;
    return metalrt_model_name(pin.handle());
}

}  // extern "C"
