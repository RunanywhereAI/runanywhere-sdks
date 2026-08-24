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

#include <chrono>
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

Sink sink_snapshot() {
    const std::lock_guard<std::mutex> guard(sink_mutex());
    return sink();
}

int64_t now_ms() {
    using namespace std::chrono;
    return duration_cast<milliseconds>(system_clock::now().time_since_epoch()).count();
}

}  // namespace

extern "C" {

rac_result_t rac_tool_progress_sink_register(rac_tool_progress_sink_fn fn, void* user_data) {
    const std::lock_guard<std::mutex> guard(sink_mutex());
    sink() = Sink{fn, user_data};
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
                                     const std::vector<std::string>& history)
    : tool_name_(std::move(tool_name)),
      run_loop_handle_(run_loop_handle),
      is_cancelled_(std::move(is_cancelled)),
      history_(history) {
    context_.emit = &ToolProgressScope::emit_thunk;
    context_.is_cancelled = &ToolProgressScope::cancelled_thunk;
    context_.state = this;

    history_ptrs_.reserve(history_.size());
    for (const auto& turn : history_) {
        history_ptrs_.push_back(turn.c_str());
    }
    context_.history = history_ptrs_.empty() ? nullptr : history_ptrs_.data();
    context_.n_history = static_cast<int32_t>(history_ptrs_.size());
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

    const Sink target = sink_snapshot();
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
    event.set_status(static_cast<runanywhere::v1::ToolProgressStatus>(status));
    if (detail != nullptr) {
        event.set_detail(detail);
    }
    event.set_sequence(sequence_++);
    event.set_run_loop_handle(run_loop_handle_);
    event.set_emitted_at_ms(now_ms());

    std::string bytes;
    if (!event.SerializeToString(&bytes)) {
        RAC_LOG_WARNING(kTag, "failed to serialize progress for '%s'", tool_name_.c_str());
        return true;
    }
    return target.fn(reinterpret_cast<const uint8_t*>(bytes.data()), bytes.size(),
                     target.user_data) != RAC_FALSE;
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
