// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// In-memory LoRA adapter registry. Ports the capability surface from
// `sdk/runanywhere-commons/include/rac/infrastructure/model_management/
// rac_lora_registry.h` to C++20 / RAII.
//
// Apps register LoRA adapters at startup with explicit compatible base
// model IDs; SDKs query "which adapters work with this model" without
// reinventing detection logic per platform.

#ifndef RA_CORE_LORA_REGISTRY_H
#define RA_CORE_LORA_REGISTRY_H

#include <cstdint>
#include <string>
#include <unordered_map>
#include <vector>

namespace ra::core {

struct LoRAEntry {
    std::string               id;                     // Unique adapter identifier
    std::string               name;                   // Human-readable display
    std::string               description;
    std::string               download_url;
    std::string               filename;               // On-disk basename
    std::vector<std::string>  compatible_model_ids;   // Explicit compat list
    std::int64_t              file_size_bytes = 0;    // 0 if unknown
    float                     default_scale = 0.3f;   // Recommended scale
};

class LoRARegistry {
public:
    static LoRARegistry& global();

    LoRARegistry() = default;
    LoRARegistry(const LoRARegistry&)            = delete;
    LoRARegistry& operator=(const LoRARegistry&) = delete;

    // Inserts or replaces an entry keyed by `entry.id`.
    void upsert(LoRAEntry entry);

    // Removes an entry by id. Returns true if removed.
    bool remove(std::string_view id);

    // Returns a copy of every registered entry.
    std::vector<LoRAEntry> all() const;

    // Returns entries whose `compatible_model_ids` contains `model_id`.
    std::vector<LoRAEntry> for_model(std::string_view model_id) const;

    // Lookup by adapter id; returns nullptr when missing.
    const LoRAEntry* find(std::string_view id) const;

    void clear();
    std::size_t size() const;

private:
    std::unordered_map<std::string, LoRAEntry> entries_;
};

}  // namespace ra::core

#endif  // RA_CORE_LORA_REGISTRY_H
