// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.

#include "model_compatibility.h"

#include "model_registry.h"

namespace ra::core {

ModelCompatibilityResult check_model_compatibility(
    std::string_view model_id,
    std::int64_t     available_memory_bytes,
    std::int64_t     available_storage_bytes) {
    ModelCompatibilityResult r;
    r.available_memory_bytes  = available_memory_bytes;
    r.available_storage_bytes = available_storage_bytes;

    const auto entry = ModelRegistry::global().find(model_id);
    if (!entry) return r;

    r.required_memory_bytes  = static_cast<std::int64_t>(entry->memory_required_bytes);
    r.required_storage_bytes = static_cast<std::int64_t>(entry->size_bytes);

    // can_run: if required_memory is unknown (0), assume yes — the registry
    // metadata simply hasn't been populated yet.
    r.can_run = r.required_memory_bytes == 0
                || available_memory_bytes >= r.required_memory_bytes;
    r.can_fit = r.required_storage_bytes == 0
                || available_storage_bytes >= r.required_storage_bytes;
    r.is_compatible = r.can_run && r.can_fit;
    return r;
}

}  // namespace ra::core
