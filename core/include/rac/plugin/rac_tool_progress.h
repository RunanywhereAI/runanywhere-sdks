/**
 * @file rac_tool_progress.h
 * @brief Host-facing sink for progress emitted by tools while they run.
 *
 * A provider that does real work — several searches with a generation pass
 * between them — has nothing to say until `execute` returns, and by then the
 * UI has shown a spinner for twenty seconds. Providers report through the
 * emitter on `rac_tool_context_t`; commons stamps, serializes and forwards
 * each event here.
 *
 * Registration mirrors `rac_http_transport_register`: process-wide, NULL to
 * unregister. It is deliberately NOT a parameter on
 * `rac_tool_calling_run_loop_proto`. Every binding resolves that symbol by
 * name and casts it to a signature it declares itself, so widening it would
 * be undefined behaviour in any binding that had not moved yet.
 */
#ifndef RAC_PLUGIN_TOOL_PROGRESS_H
#define RAC_PLUGIN_TOOL_PROGRESS_H

#include <stddef.h>
#include <stdint.h>

#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"

// NOLINTBEGIN(modernize-redundant-void-arg,modernize-use-nullptr)
#ifdef __cplusplus
extern "C" {
#endif

/**
 * @brief Receives one serialized `runanywhere.v1.ToolProgress`.
 *
 * Called synchronously on the thread running the tool, so an implementation
 * must hand off rather than block. Returning false means the consumer has
 * stopped listening; that answer reaches the provider through its emitter and
 * it should abandon the run, the same stop-signal contract the token callback
 * uses.
 */
typedef rac_bool_t (*rac_tool_progress_sink_fn)(const uint8_t* progress_proto_bytes,
                                                size_t progress_proto_size, void* user_data);

/**
 * @brief Install the process-wide progress sink.
 *
 * Pass `sink == NULL` to unregister. Registering replaces any previous sink.
 */
RAC_API rac_result_t rac_tool_progress_sink_register(rac_tool_progress_sink_fn sink,
                                                     void* user_data);

/** @brief Whether a sink is currently installed. */
RAC_API rac_bool_t rac_tool_progress_sink_is_registered(void);

#ifdef __cplusplus
}  // extern "C"
#endif
// NOLINTEND(modernize-redundant-void-arg,modernize-use-nullptr)

#endif  // RAC_PLUGIN_TOOL_PROGRESS_H
