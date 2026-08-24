/**
 * @file tool_progress_scope.h
 * @brief Builds the rac_tool_context_t handed to one provider execute() call.
 *
 * Commons stamps tool name, sequence, run-loop handle and timestamp rather
 * than trusting the provider to, so a provider cannot mislabel whose work an
 * event belongs to and does not link protobuf to report anything.
 */
#ifndef RAC_PLUGIN_TOOL_PROGRESS_SCOPE_H
#define RAC_PLUGIN_TOOL_PROGRESS_SCOPE_H

#include <cstdint>
#include <functional>
#include <string>
#include <vector>

#include "rac/plugin/rac_tool_provider.h"

namespace rac::plugin {

class ToolProgressScope {
   public:
    /**
     * @param tool_name        stamped onto every event this scope emits
     * @param run_loop_handle  0 when the tool is running outside a run loop
     * @param is_cancelled     polled by the provider and before each emit; may
     *                         be empty, which reads as never cancelled
     */
    ToolProgressScope(std::string tool_name, uint64_t run_loop_handle,
                      std::function<bool()> is_cancelled,
                      const std::vector<std::string>& history = {});

    ToolProgressScope(const ToolProgressScope&) = delete;
    ToolProgressScope& operator=(const ToolProgressScope&) = delete;

    /** Stable for the lifetime of the scope. Never null. */
    const rac_tool_context_t* context() const { return &context_; }

    /** How many events this scope emitted, for the caller's diagnostics. */
    uint64_t emitted() const { return sequence_; }

   private:
    static rac_bool_t emit_thunk(const rac_tool_context_t* ctx, const char* stage_id,
                                 const char* label, rac_tool_progress_status_t status,
                                 const char* detail);
    static rac_bool_t cancelled_thunk(const rac_tool_context_t* ctx);

    bool emit(const char* stage_id, const char* label, rac_tool_progress_status_t status,
              const char* detail);
    bool cancelled() const;

    rac_tool_context_t context_{};
    std::string tool_name_;
    uint64_t run_loop_handle_;
    std::function<bool()> is_cancelled_;
    uint64_t sequence_ = 0;
    // Owned so the pointer array handed across the ABI outlives the call.
    std::vector<std::string> history_;
    std::vector<const char*> history_ptrs_;
};

}  // namespace rac::plugin

#endif  // RAC_PLUGIN_TOOL_PROGRESS_SCOPE_H
