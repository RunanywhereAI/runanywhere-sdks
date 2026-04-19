// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// Device compatibility check for a model. Ports the capability surface
// from `sdk/runanywhere-commons/include/rac/infrastructure/model_management/
// rac_model_compatibility.h`. Compares the model's memory_required_bytes
// and download_size_bytes against device-available RAM and free storage.

#ifndef RA_CORE_MODEL_COMPATIBILITY_H
#define RA_CORE_MODEL_COMPATIBILITY_H

#include <cstdint>
#include <string_view>

namespace ra::core {

struct ModelCompatibilityResult {
    bool is_compatible = false;  // can_run && can_fit
    bool can_run       = false;
    bool can_fit       = false;
    std::int64_t required_memory_bytes  = 0;
    std::int64_t available_memory_bytes = 0;
    std::int64_t required_storage_bytes = 0;
    std::int64_t available_storage_bytes = 0;
};

// Looks up `model_id` in the process-global ModelRegistry, reads the
// declared memory_required_bytes + download_size_bytes, and reports
// compatibility against the caller-supplied device budgets.
//
// Returns a result with is_compatible=false on any error (model not found,
// zero budgets, etc) rather than throwing — the struct is always populated.
ModelCompatibilityResult check_model_compatibility(
    std::string_view model_id,
    std::int64_t     available_memory_bytes,
    std::int64_t     available_storage_bytes);

}  // namespace ra::core

#endif  // RA_CORE_MODEL_COMPATIBILITY_H
