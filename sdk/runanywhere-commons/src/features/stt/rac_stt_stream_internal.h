/**
 * @file rac_stt_stream_internal.h
 * @brief Component-lifecycle coordination for STT stream sessions.
 */

#ifndef RAC_FEATURES_STT_RAC_STT_STREAM_INTERNAL_H
#define RAC_FEATURES_STT_RAC_STT_STREAM_INTERNAL_H

#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"

namespace rac::stt {

// Component creation/destruction owns registration in the private stream
// registry. Public stream starts are accepted only for registered components.
void register_stream_component(rac_handle_t handle);
void unregister_stream_component(rac_handle_t handle);

// Close the component's start gate, cancel every existing session, and wait
// until its provider calls and callbacks have drained. The caller must not
// hold the component mutex: persistent stream destruction re-enters the
// component to release its lifecycle pin.
rac_result_t begin_stream_component_teardown(rac_handle_t handle);

// Re-open the start gate after a non-destructive lifecycle operation.
void end_stream_component_teardown(rac_handle_t handle);

// Deterministic concurrency probes used only by the native regression suite.
// They expose private admission state without changing the public C ABI.
using StopFlushAdmissionTestHook = void (*)(uint64_t session_id, void* user_data);
using ComponentAdmissionClosedTestHook = void (*)(rac_handle_t handle, void* user_data);
using ComponentLifecycleGateTestHook = void (*)(rac_handle_t handle, void* user_data);
void set_stop_flush_admission_test_hook(StopFlushAdmissionTestHook hook, void* user_data);
void set_component_admission_closed_test_hook(ComponentAdmissionClosedTestHook hook,
                                              void* user_data);
void set_component_lifecycle_gate_test_hook(ComponentLifecycleGateTestHook hook, void* user_data);
bool stream_session_termination_started_for_testing(uint64_t session_id);
bool stream_session_cancel_requested_for_testing(uint64_t session_id);
bool has_stream_callback_for_testing(rac_handle_t handle);

}  // namespace rac::stt

#endif  // RAC_FEATURES_STT_RAC_STT_STREAM_INTERNAL_H
