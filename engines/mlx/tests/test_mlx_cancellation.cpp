/**
 * @file test_mlx_cancellation.cpp
 * @brief Deterministic cancellation coverage for the MLX callback bridge.
 */

#include "rac_mlx_callbacks_internal.h"

#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstdlib>
#include <cstring>
#include <future>
#include <iostream>
#include <mutex>
#include <string>

#include "rac/plugin/rac_plugin_entry_mlx.h"

namespace {

using namespace std::chrono_literals;

constexpr auto kQuickTimeout = 500ms;
constexpr auto kSafetyTimeout = 2s;

struct FakeSession {
    std::atomic<bool> cancelled{false};
};

struct BlockingState {
    std::mutex mutex;
    std::condition_variable changed;
    bool block_llm = false;
    bool block_tts = false;
    bool block_interrupt = false;
    bool llm_entered = false;
    bool tts_entered = false;
    bool interrupt_entered = false;
    bool allow_llm_return = false;
    bool allow_interrupt_return = false;
    bool llm_callback_returning = false;
    int cancel_calls = 0;
    int stop_calls = 0;
    int clear_calls = 0;

    void reset() {
        std::lock_guard<std::mutex> lock(mutex);
        block_llm = false;
        block_tts = false;
        block_interrupt = false;
        llm_entered = false;
        tts_entered = false;
        interrupt_entered = false;
        allow_llm_return = false;
        allow_interrupt_return = false;
        llm_callback_returning = false;
        cancel_calls = 0;
        stop_calls = 0;
        clear_calls = 0;
    }
};

BlockingState g_state;
int g_failures = 0;

void check(bool condition, const char* message) {
    if (condition) {
        std::cout << "  ok:   " << message << '\n';
        return;
    }
    std::cerr << "  FAIL: " << message << '\n';
    g_failures += 1;
}

template <typename Predicate>
bool wait_for_state(Predicate predicate) {
    std::unique_lock<std::mutex> lock(g_state.mutex);
    return g_state.changed.wait_for(lock, kSafetyTimeout, predicate);
}

rac_result_t fake_create(rac_mlx_session_kind_t, const char*, rac_handle_t* out_handle, void*) {
    if (!out_handle) {
        return RAC_ERROR_NULL_POINTER;
    }
    *out_handle = new FakeSession();
    return RAC_SUCCESS;
}

rac_result_t fake_initialize(rac_handle_t, const char*, void*) {
    return RAC_SUCCESS;
}

rac_result_t fake_llm_generate(rac_handle_t handle, const char*, const rac_llm_options_t*,
                               rac_llm_result_t* out_result, void*) {
    auto* session = static_cast<FakeSession*>(handle);
    if (!session || !out_result) {
        return RAC_ERROR_NULL_POINTER;
    }

    std::unique_lock<std::mutex> lock(g_state.mutex);
    if (g_state.block_llm) {
        g_state.llm_entered = true;
        g_state.changed.notify_all();
        const bool released = g_state.changed.wait_for(lock, kSafetyTimeout, [&] {
            return session->cancelled.load(std::memory_order_acquire) || g_state.allow_llm_return;
        });
        if (!released) {
            return RAC_ERROR_TIMEOUT;
        }
        g_state.llm_callback_returning = true;
        g_state.changed.notify_all();
    }
    if (session->cancelled.load(std::memory_order_acquire)) {
        return RAC_ERROR_CANCELLED;
    }

    std::memset(out_result, 0, sizeof(*out_result));
    out_result->text = strdup("mlx-test");
    return out_result->text ? RAC_SUCCESS : RAC_ERROR_OUT_OF_MEMORY;
}

rac_result_t fake_llm_generate_stream(rac_handle_t, const char*, const rac_llm_options_t*,
                                      rac_llm_stream_callback_fn, void*, void*) {
    return RAC_ERROR_NOT_SUPPORTED;
}

rac_result_t fake_vlm_process(rac_handle_t, const rac_vlm_image_t*, const char*,
                              const rac_vlm_options_t*, rac_vlm_result_t*, void*) {
    return RAC_ERROR_NOT_SUPPORTED;
}

rac_result_t fake_vlm_process_stream(rac_handle_t, const rac_vlm_image_t*, const char*,
                                     const rac_vlm_options_t*, rac_vlm_stream_callback_fn, void*,
                                     void*) {
    return RAC_ERROR_NOT_SUPPORTED;
}

rac_result_t fake_embed_batch(rac_handle_t, const char* const*, size_t,
                              const rac_embeddings_options_t*, rac_embeddings_result_t*, void*) {
    return RAC_ERROR_NOT_SUPPORTED;
}

rac_result_t fake_stt_transcribe(rac_handle_t, const void*, size_t, const rac_stt_options_t*,
                                 rac_stt_result_t*, void*) {
    return RAC_ERROR_NOT_SUPPORTED;
}

rac_result_t fake_tts_synthesize(rac_handle_t handle, const char*, const rac_tts_options_t*,
                                 rac_tts_result_t* out_result, void*) {
    auto* session = static_cast<FakeSession*>(handle);
    if (!session || !out_result) {
        return RAC_ERROR_NULL_POINTER;
    }

    std::unique_lock<std::mutex> lock(g_state.mutex);
    if (g_state.block_tts) {
        g_state.tts_entered = true;
        g_state.changed.notify_all();
        const bool released = g_state.changed.wait_for(lock, kSafetyTimeout, [&] {
            return session->cancelled.load(std::memory_order_acquire);
        });
        if (!released) {
            return RAC_ERROR_TIMEOUT;
        }
    }
    if (session->cancelled.load(std::memory_order_acquire)) {
        return RAC_ERROR_CANCELLED;
    }

    std::memset(out_result, 0, sizeof(*out_result));
    return RAC_SUCCESS;
}

rac_result_t fake_cancel(rac_handle_t handle, void*) {
    auto* session = static_cast<FakeSession*>(handle);
    {
        std::unique_lock<std::mutex> lock(g_state.mutex);
        g_state.cancel_calls += 1;
        g_state.interrupt_entered = true;
        g_state.changed.notify_all();
        if (g_state.block_interrupt) {
            const bool released = g_state.changed.wait_for(
                lock, kSafetyTimeout, [] { return g_state.allow_interrupt_return; });
            if (!released) {
                return RAC_ERROR_TIMEOUT;
            }
        }
    }
    session->cancelled.store(true, std::memory_order_release);
    g_state.changed.notify_all();
    return RAC_SUCCESS;
}

rac_result_t fake_tts_stop(rac_handle_t handle, void*) {
    {
        std::lock_guard<std::mutex> lock(g_state.mutex);
        g_state.stop_calls += 1;
    }
    auto* session = static_cast<FakeSession*>(handle);
    session->cancelled.store(true, std::memory_order_release);
    g_state.changed.notify_all();
    return RAC_SUCCESS;
}

rac_result_t fake_cleanup(rac_handle_t, void*) {
    return RAC_SUCCESS;
}

void fake_destroy(rac_handle_t handle, void*) {
    delete static_cast<FakeSession*>(handle);
}

void fake_clear_cancel(rac_handle_t handle, void*) {
    static_cast<FakeSession*>(handle)->cancelled.store(false, std::memory_order_release);
    std::lock_guard<std::mutex> lock(g_state.mutex);
    g_state.clear_calls += 1;
}

bool install_callbacks() {
    rac_mlx_callbacks_t callbacks = {};
    callbacks.struct_size = sizeof(callbacks);
    callbacks.create = fake_create;
    callbacks.initialize = fake_initialize;
    callbacks.llm_generate = fake_llm_generate;
    callbacks.llm_generate_stream = fake_llm_generate_stream;
    callbacks.vlm_process = fake_vlm_process;
    callbacks.vlm_process_stream = fake_vlm_process_stream;
    callbacks.embed_batch = fake_embed_batch;
    callbacks.stt_transcribe = fake_stt_transcribe;
    callbacks.tts_synthesize = fake_tts_synthesize;
    callbacks.tts_stop = fake_tts_stop;
    callbacks.cancel = fake_cancel;
    callbacks.cleanup = fake_cleanup;
    callbacks.destroy = fake_destroy;
    return ra_mlx_set_clear_cancel_callback(fake_clear_cancel, nullptr) == RAC_SUCCESS &&
           rac_mlx_set_callbacks(&callbacks) == RAC_SUCCESS;
}

const rac_engine_vtable_t* mlx_vtable() {
    return rac_plugin_entry_mlx();
}

void test_llm_cancel_during_blocked_inference() {
    std::cout << "test_llm_cancel_during_blocked_inference\n";
    g_state.reset();
    {
        std::lock_guard<std::mutex> lock(g_state.mutex);
        g_state.block_llm = true;
    }

    const auto* ops = mlx_vtable()->llm_ops;
    void* impl = nullptr;
    check(ops->create("mlx-test-llm", nullptr, &impl) == RAC_SUCCESS, "LLM session creates");
    check(ops->initialize(impl, "/tmp/mlx-test-llm") == RAC_SUCCESS, "LLM session initializes");

    rac_llm_result_t result = {};
    auto generation = std::async(std::launch::async,
                                 [&] { return ops->generate(impl, "hello", nullptr, &result); });
    check(wait_for_state([] { return g_state.llm_entered; }),
          "LLM callback reaches blocked inference");

    auto cancellation = std::async(std::launch::async, [&] { return ops->cancel(impl); });
    check(cancellation.wait_for(kQuickTimeout) == std::future_status::ready,
          "LLM cancel does not wait for the inference serialization lock");
    check(cancellation.get() == RAC_SUCCESS, "LLM cancel callback succeeds");
    check(generation.wait_for(kQuickTimeout) == std::future_status::ready,
          "blocked LLM inference exits after cancellation");
    check(generation.get() == RAC_ERROR_CANCELLED, "blocked LLM reports cancellation");

    int cancel_calls = 0;
    {
        std::lock_guard<std::mutex> lock(g_state.mutex);
        cancel_calls = g_state.cancel_calls;
    }
    check(ops->cancel(impl) == RAC_SUCCESS, "late LLM cancel is accepted as a no-op");
    {
        std::lock_guard<std::mutex> lock(g_state.mutex);
        check(g_state.cancel_calls == cancel_calls,
              "late LLM cancel does not reach the completed Swift operation");
    }

    ops->destroy(impl);
}

void test_late_interrupt_does_not_poison_successor() {
    std::cout << "test_late_interrupt_does_not_poison_successor\n";
    g_state.reset();
    {
        std::lock_guard<std::mutex> lock(g_state.mutex);
        g_state.block_llm = true;
        g_state.block_interrupt = true;
    }

    const auto* ops = mlx_vtable()->llm_ops;
    void* impl = nullptr;
    check(ops->create("mlx-test-late", nullptr, &impl) == RAC_SUCCESS,
          "late-interrupt LLM session creates");
    check(ops->initialize(impl, "/tmp/mlx-test-late") == RAC_SUCCESS,
          "late-interrupt LLM session initializes");

    rac_llm_result_t first_result = {};
    auto generation = std::async(
        std::launch::async, [&] { return ops->generate(impl, "first", nullptr, &first_result); });
    check(wait_for_state([] { return g_state.llm_entered; }),
          "first LLM callback reaches blocked inference");

    auto cancellation = std::async(std::launch::async, [&] { return ops->cancel(impl); });
    check(wait_for_state([] { return g_state.interrupt_entered; }),
          "interrupt is admitted while the first operation is active");
    {
        std::lock_guard<std::mutex> lock(g_state.mutex);
        g_state.allow_llm_return = true;
    }
    g_state.changed.notify_all();
    check(wait_for_state([] { return g_state.llm_callback_returning; }),
          "Swift callback returns while its admitted interrupt is still pending");
    check(generation.wait_for(100ms) != std::future_status::ready,
          "operation lifetime remains pinned until the admitted interrupt drains");

    {
        std::lock_guard<std::mutex> lock(g_state.mutex);
        g_state.allow_interrupt_return = true;
    }
    g_state.changed.notify_all();
    check(cancellation.wait_for(kQuickTimeout) == std::future_status::ready,
          "late admitted interrupt completes");
    check(cancellation.get() == RAC_SUCCESS, "late admitted interrupt succeeds");
    check(generation.wait_for(kQuickTimeout) == std::future_status::ready,
          "first operation completes after interrupt drain");
    check(generation.get() == RAC_SUCCESS, "first operation preserves its callback result");
    rac_llm_result_free(&first_result);

    {
        std::lock_guard<std::mutex> lock(g_state.mutex);
        g_state.block_llm = false;
        g_state.block_interrupt = false;
    }
    rac_llm_result_t next_result = {};
    check(ops->generate(impl, "next", nullptr, &next_result) == RAC_SUCCESS,
          "late cancellation state is cleared before the successor starts");
    rac_llm_result_free(&next_result);

    ops->destroy(impl);
}

void test_tts_stop_during_blocked_unary_synthesis() {
    std::cout << "test_tts_stop_during_blocked_unary_synthesis\n";
    g_state.reset();
    {
        std::lock_guard<std::mutex> lock(g_state.mutex);
        g_state.block_tts = true;
    }

    const auto* ops = mlx_vtable()->tts_ops;
    void* impl = nullptr;
    check(ops->create("/tmp/mlx-test-tts", nullptr, &impl) == RAC_SUCCESS, "TTS session creates");
    check(ops->initialize(impl) == RAC_SUCCESS, "TTS session initializes");

    rac_tts_result_t result = {};
    auto synthesis = std::async(std::launch::async,
                                [&] { return ops->synthesize(impl, "hello", nullptr, &result); });
    check(wait_for_state([] { return g_state.tts_entered; }),
          "unary TTS callback reaches blocked synthesis");

    auto stop = std::async(std::launch::async, [&] { return ops->stop(impl); });
    check(stop.wait_for(kQuickTimeout) == std::future_status::ready,
          "TTS stop does not wait for the synthesis serialization lock");
    check(stop.get() == RAC_SUCCESS, "TTS stop callback succeeds");
    check(synthesis.wait_for(kQuickTimeout) == std::future_status::ready,
          "blocked unary TTS exits after stop");
    check(synthesis.get() == RAC_ERROR_CANCELLED, "blocked unary TTS reports cancellation");

    int stop_calls = 0;
    {
        std::lock_guard<std::mutex> lock(g_state.mutex);
        stop_calls = g_state.stop_calls;
    }
    check(ops->stop(impl) == RAC_SUCCESS, "late TTS stop is accepted as a no-op");
    {
        std::lock_guard<std::mutex> lock(g_state.mutex);
        check(g_state.stop_calls == stop_calls,
              "late TTS stop does not reach the completed Swift operation");
    }

    ops->destroy(impl);
}

}  // namespace

int main() {
    std::cout << "test_mlx_cancellation\n";
    check(install_callbacks(), "MLX test callbacks install");
    const auto* vtable = mlx_vtable();
    check(vtable && vtable->llm_ops && vtable->tts_ops, "MLX LLM/TTS vtables are available");
    if (!vtable || !vtable->llm_ops || !vtable->tts_ops) {
        return EXIT_FAILURE;
    }

    test_llm_cancel_during_blocked_inference();
    test_late_interrupt_does_not_poison_successor();
    test_tts_stop_during_blocked_unary_synthesis();

    std::cout << "  "
              << (g_failures == 0 ? "all checks passed" : "failures: " + std::to_string(g_failures))
              << '\n';
    return g_failures == 0 ? EXIT_SUCCESS : EXIT_FAILURE;
}
