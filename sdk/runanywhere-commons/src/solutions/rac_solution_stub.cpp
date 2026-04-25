// SPDX-License-Identifier: Apache-2.0
//
// rac_solution_stub.cpp — always-built fallback for the rac_solution_* C ABI.
//
// The full SolutionRunner implementation lives in rac_solution.cpp, which is
// gated on Protobuf_FOUND in CMakeLists.txt because it depends on the
// generated pipeline.pb / solutions.pb classes. On cross-compilation targets
// (iOS / Android / WASM) Protobuf is typically not discoverable via
// find_package, so the full implementation TUs are dropped and downstream
// link consumers (Swift facade, JNI thunks, RN HybridRunAnywhereCore,
// Flutter FFI, Web exports) lose their referenced symbols.
//
// To keep those bindings linkable, this TU is added to RAC_COMMONS_SOURCES
// unconditionally and provides minimal stubs for all eight functions in
// include/rac/solutions/rac_solution.h. Each stub returns
// RAC_ERROR_FEATURE_NOT_AVAILABLE (which the SDK-side wrappers already
// surface to callers) so a runtime call into RunAnywhere.solutions on a
// build without Protobuf is well-defined rather than a link failure.
//
// When the build does have Protobuf, CMake defines RAC_HAVE_PROTOBUF=1 and
// the entire body of this TU is excluded — the real implementation in
// rac_solution.cpp wins at link time.

#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"
#include "rac/solutions/rac_solution.h"

#ifndef RAC_HAVE_PROTOBUF

extern "C" {

RAC_API rac_result_t rac_solution_create_from_proto(const void*            /*proto_bytes*/,
                                                    size_t                 /*len*/,
                                                    rac_solution_handle_t* out_handle) {
    if (out_handle) *out_handle = nullptr;
    return RAC_ERROR_FEATURE_NOT_AVAILABLE;
}

RAC_API rac_result_t rac_solution_create_from_yaml(const char*            /*yaml_text*/,
                                                   rac_solution_handle_t* out_handle) {
    if (out_handle) *out_handle = nullptr;
    return RAC_ERROR_FEATURE_NOT_AVAILABLE;
}

RAC_API rac_result_t rac_solution_start(rac_solution_handle_t /*handle*/) {
    return RAC_ERROR_FEATURE_NOT_AVAILABLE;
}

RAC_API rac_result_t rac_solution_stop(rac_solution_handle_t /*handle*/) {
    return RAC_ERROR_FEATURE_NOT_AVAILABLE;
}

RAC_API rac_result_t rac_solution_cancel(rac_solution_handle_t /*handle*/) {
    return RAC_ERROR_FEATURE_NOT_AVAILABLE;
}

RAC_API rac_result_t rac_solution_feed(rac_solution_handle_t /*handle*/,
                                       const char*           /*item*/) {
    return RAC_ERROR_FEATURE_NOT_AVAILABLE;
}

RAC_API rac_result_t rac_solution_close_input(rac_solution_handle_t /*handle*/) {
    return RAC_ERROR_FEATURE_NOT_AVAILABLE;
}

RAC_API void rac_solution_destroy(rac_solution_handle_t /*handle*/) {
    // No-op: no SolutionRunner was ever constructed in the stub path.
}

}  // extern "C"

#endif  // !RAC_HAVE_PROTOBUF
