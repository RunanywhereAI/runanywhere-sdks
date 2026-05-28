/**
 * @file rac_runtime_helpers.h
 * @brief Shared helpers for L1 runtime adapters.
 *
 * Wave H-3 cleanup (runtime-tensor-dup): consolidates the per-runtime
 * `release_tensor` and `copy_buffer` range-check boilerplate that used to be
 * duplicated across every runtime adapter. Each runtime owns its private
 * buffer struct (CpuRuntimeBuffer, rac_runtime_buffer, …), so the helpers take
 * plain byte-level inputs (raw pointers + sizes) and, for tensor release, a
 * runtime-specific `free_buffer` function pointer for the buffer slot.
 *
 * Scope:
 *   - CPU, ONNXRT, CoreML, and Metal all delegate `release_tensor` here.
 */

#ifndef RAC_RUNTIME_HELPERS_H
#define RAC_RUNTIME_HELPERS_H

#include <cstdlib>
#include <cstring>

#include "rac/core/rac_error.h"
#include "rac/plugin/rac_runtime_vtable.h"

namespace rac {
namespace runtime {

/** Type alias for the runtime-specific `free_buffer` callback used by
 *  `rac_runtime_release_tensor` to release an owned buffer slot. */
using free_buffer_fn = void (*)(rac_runtime_buffer_t*);

/**
 * @brief Release any runtime-owned fields on a v2 tensor and reset it.
 *
 * Semantics mirror the original per-runtime implementations: fields whose
 * ownership is `RAC_RUNTIME_OWNERSHIP_RUNTIME` are freed; the buffer slot is
 * released through the caller-supplied `free_buffer` callback so each runtime
 * keeps its private allocator. All other ownership kinds are left untouched.
 * After the call the tensor is zeroed (same shape as `= rac_runtime_tensor_t{}`).
 *
 * `tensor` MAY be NULL — the call is a no-op in that case.
 * `free_buffer` MAY be NULL — buffer slots with RUNTIME ownership are leaked,
 *  matching the historical behavior when a runtime has no buffer allocator.
 */
inline void rac_runtime_release_tensor(rac_runtime_tensor_t* tensor, free_buffer_fn free_buffer) {
    if (tensor == nullptr)
        return;
    if (tensor->data_ownership == RAC_RUNTIME_OWNERSHIP_RUNTIME && tensor->data != nullptr) {
        std::free(tensor->data);
    }
    if (tensor->shape_ownership == RAC_RUNTIME_OWNERSHIP_RUNTIME && tensor->shape != nullptr) {
        std::free(tensor->shape);
    }
    if (tensor->buffer_ownership == RAC_RUNTIME_OWNERSHIP_RUNTIME && tensor->buffer != nullptr &&
        free_buffer != nullptr) {
        free_buffer(tensor->buffer);
    }
    *tensor = rac_runtime_tensor_t{};
}

/**
 * @brief Perform the v2 `copy_buffer` range check + `memmove`.
 *
 * The caller has already resolved each runtime's private buffer struct down to
 * a base pointer + capacity pair. This helper performs the identical bounds
 * check every runtime used to inline (offset inside capacity, bytes within
 * remaining capacity) and then copies via `memmove`.
 *
 * Returns:
 *   - `RAC_ERROR_NULL_POINTER` if `dst` or `src` is NULL.
 *   - `RAC_ERROR_INVALID_PARAMETER` if any offset/size is out of range.
 *   - `RAC_SUCCESS` otherwise.
 */
inline rac_result_t rac_runtime_copy_buffer(void* dst, size_t dst_capacity, size_t dst_offset,
                                            const void* src, size_t src_capacity, size_t src_offset,
                                            size_t bytes) {
    if (dst == nullptr || src == nullptr) {
        return RAC_ERROR_NULL_POINTER;
    }
    if (dst_offset > dst_capacity || src_offset > src_capacity) {
        return RAC_ERROR_INVALID_PARAMETER;
    }
    if (bytes > dst_capacity - dst_offset || bytes > src_capacity - src_offset) {
        return RAC_ERROR_INVALID_PARAMETER;
    }
    std::memmove(static_cast<unsigned char*>(dst) + dst_offset,
                 static_cast<const unsigned char*>(src) + src_offset, bytes);
    return RAC_SUCCESS;
}

}  // namespace runtime
}  // namespace rac

#endif /* RAC_RUNTIME_HELPERS_H */
