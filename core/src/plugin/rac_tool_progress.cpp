/**
 * @file rac_tool_progress.cpp
 * @brief Progress sink registration and the per-execute emitter.
 *
 * The sink is process-wide for the same reason the HTTP transport is: it is a
 * host capability, installed once at init, not a per-call argument. Making it
 * a parameter on rac_tool_calling_run_loop_proto would have widened a symbol
 * every binding resolves by name and casts to its own declared signature.
 */

#include "rac/plugin/rac_tool_progress.h"

#include <atomic>
#include <chrono>
#include <condition_variable>
#include <mutex>
#include <utility>

#include "plugin/tool_progress_scope.h"
#include "rac/core/rac_logger.h"

#if defined(RAC_HAVE_PROTOBUF)
#include "tool_calling.pb.h"
#endif

namespace {

constexpr const char* kTag = "ToolProgress";

struct Sink {
    rac_tool_progress_sink_fn fn = nullptr;
    void* user_data = nullptr;
};

std::mutex& sink_mutex() {
    static std::mutex mutex;
    return mutex;
}

Sink& sink() {
    static Sink installed;
    return installed;
}

std::condition_variable& sink_idle() {
    static std::condition_variable idle;
    return idle;
}

/// Emits currently inside the sink callback, which runs outside the lock so a
/// re-entrant callback cannot deadlock.
size_t& sink_in_flight() {
    static size_t count = 0;
    return count;
}

/// True while this thread is inside the sink callback. A callback that
/// registers or clears the sink must not wait for itself to finish.
bool& emitting_on_this_thread() {
    static thread_local bool emitting = false;
    return emitting;
}

/// Copies the sink and marks an emit in flight, so a concurrent register cannot
/// free `user_data` while the callback is still running.
Sink sink_acquire() {
    const std::lock_guard<std::mutex> guard(sink_mutex());
    ++sink_in_flight();
    return sink();
}

void sink_release() {
    {
        const std::lock_guard<std::mutex> guard(sink_mutex());
        --sink_in_flight();
    }
    sink_idle().notify_all();
}

/// Process-wide and monotonic, so every execute() call is distinguishable even
/// when two run under the same run-loop handle at once.
uint64_t next_execution_id() {
    static std::atomic<uint64_t> counter{1};
    return counter.fetch_add(1, std::memory_order_relaxed);
}

int64_t now_ms() {
    using namespace std::chrono;
    return duration_cast<milliseconds>(system_clock::now().time_since_epoch()).count();
}

}  // namespace

extern "C" {

rac_result_t rac_tool_progress_sink_register(rac_tool_progress_sink_fn fn, void* user_data) {
    std::unique_lock<std::mutex> guard(sink_mutex());
    sink() = Sink{fn, user_data};
    // Wait for callbacks already running against the previous sink. They hold a
    // copy of the old `user_data`, and the caller is entitled to free it the
    // moment this returns. Skipped when the caller IS the callback, which would
    // otherwise wait on itself forever.
    if (!emitting_on_this_thread()) {
        sink_idle().wait(guard, [] { return sink_in_flight() == 0; });
    }
    RAC_LOG_DEBUG(kTag, "progress sink %s", fn == nullptr ? "cleared" : "installed");
    return RAC_SUCCESS;
}

rac_bool_t rac_tool_progress_sink_is_registered(void) {
    const std::lock_guard<std::mutex> guard(sink_mutex());
    return sink().fn != nullptr ? RAC_TRUE : RAC_FALSE;
}

}  // extern "C"

namespace rac::plugin {

ToolProgressScope::ToolProgressScope(std::string tool_name, uint64_t run_loop_handle,
                                     std::function<bool()> is_cancelled,
                                     const std::vector<std::string>& history,
                                     std::string user_prompt)
    : tool_name_(std::move(tool_name)),
      run_loop_handle_(run_loop_handle),
      execution_id_(next_execution_id()),
      is_cancelled_(std::move(is_cancelled)),
      history_(history),
      user_prompt_(std::move(user_prompt)) {
    context_.emit = &ToolProgressScope::emit_thunk;
    context_.is_cancelled = &ToolProgressScope::cancelled_thunk;
    context_.state = this;

    history_ptrs_.reserve(history_.size());
    for (const auto& turn : history_) {
        history_ptrs_.push_back(turn.c_str());
    }
    context_.history = history_ptrs_.empty() ? nullptr : history_ptrs_.data();
    context_.n_history = static_cast<int32_t>(history_ptrs_.size());
    context_.user_prompt = user_prompt_.empty() ? nullptr : user_prompt_.c_str();
}

bool ToolProgressScope::cancelled() const {
    return is_cancelled_ && is_cancelled_();
}

bool ToolProgressScope::emit(const char* stage_id, const char* label,
                             rac_tool_progress_status_t status, const char* detail) {
    // Cancellation is checked before the sink so a provider is told to stop
    // even when nobody installed one.
    if (cancelled()) {
        return false;
    }

    const Sink target = sink_acquire();
    struct Release {
        ~Release() { sink_release(); }
    } release_on_exit;
    if (target.fn == nullptr) {
        // Nothing listening is not a reason to abandon the run; the tool's
        // result is still wanted. Only cancellation stops a provider.
        ++sequence_;
        return true;
    }

#if defined(RAC_HAVE_PROTOBUF)
    runanywhere::v1::ToolProgress event;
    event.set_tool_name(tool_name_);
    event.set_stage_id(stage_id != nullptr ? stage_id : "");
    event.set_label(label != nullptr ? label : "");
    // The C enum is stated separately so a provider never links protobuf, which
    // leaves the two free to drift. This cast is the one place they meet, so
    // the agreement is asserted here rather than discovered as a mislabelled
    // stage at runtime.
    static_assert(static_cast<int>(RAC_TOOL_PROGRESS_UNSPECIFIED) ==
                      static_cast<int>(runanywhere::v1::TOOL_PROGRESS_STATUS_UNSPECIFIED),
                  "rac_tool_progress_status_t drifted from ToolProgressStatus");
    static_assert(static_cast<int>(RAC_TOOL_PROGRESS_STARTED) ==
                      static_cast<int>(runanywhere::v1::TOOL_PROGRESS_STATUS_STARTED),
                  "rac_tool_progress_status_t drifted from ToolProgressStatus");
    static_assert(static_cast<int>(RAC_TOOL_PROGRESS_COMPLETED) ==
                      static_cast<int>(runanywhere::v1::TOOL_PROGRESS_STATUS_COMPLETED),
                  "rac_tool_progress_status_t drifted from ToolProgressStatus");
    static_assert(static_cast<int>(RAC_TOOL_PROGRESS_FAILED) ==
                      static_cast<int>(runanywhere::v1::TOOL_PROGRESS_STATUS_FAILED),
                  "rac_tool_progress_status_t drifted from ToolProgressStatus");
    event.set_status(static_cast<runanywhere::v1::ToolProgressStatus>(status));
    if (detail != nullptr) {
        event.set_detail(detail);
    }
    event.set_sequence(sequence_++);
    event.set_run_loop_handle(run_loop_handle_);
    event.set_execution_id(execution_id_);
    event.set_emitted_at_ms(now_ms());

    std::string bytes;
    if (!event.SerializeToString(&bytes)) {
        RAC_LOG_WARNING(kTag, "failed to serialize progress for '%s'", tool_name_.c_str());
        return true;
    }
    emitting_on_this_thread() = true;
    const rac_bool_t keep_going = target.fn(reinterpret_cast<const uint8_t*>(bytes.data()),
                                            bytes.size(), target.user_data);
    emitting_on_this_thread() = false;
    return keep_going != RAC_FALSE;
#else
    (void)stage_id;
    (void)label;
    (void)status;
    (void)detail;
    ++sequence_;
    return true;
#endif
}

rac_bool_t ToolProgressScope::emit_thunk(const rac_tool_context_t* ctx, const char* stage_id,
                                         const char* label, rac_tool_progress_status_t status,
                                         const char* detail) {
    if (ctx == nullptr || ctx->state == nullptr) {
        return RAC_FALSE;
    }
    auto* self = static_cast<ToolProgressScope*>(ctx->state);
    return self->emit(stage_id, label, status, detail) ? RAC_TRUE : RAC_FALSE;
}

rac_bool_t ToolProgressScope::cancelled_thunk(const rac_tool_context_t* ctx) {
    if (ctx == nullptr || ctx->state == nullptr) {
        return RAC_FALSE;
    }
    return static_cast<ToolProgressScope*>(ctx->state)->cancelled() ? RAC_TRUE : RAC_FALSE;
}

}  // namespace rac::plugin
