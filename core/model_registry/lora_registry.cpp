// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.

#include "lora_registry.h"

#include <algorithm>

namespace ra::core {

LoRARegistry& LoRARegistry::global() {
    static LoRARegistry instance;
    return instance;
}

void LoRARegistry::upsert(LoRAEntry entry) {
    auto id = entry.id;
    entries_[std::move(id)] = std::move(entry);
}

bool LoRARegistry::remove(std::string_view id) {
    const auto it = entries_.find(std::string{id});
    if (it == entries_.end()) return false;
    entries_.erase(it);
    return true;
}

std::vector<LoRAEntry> LoRARegistry::all() const {
    std::vector<LoRAEntry> out;
    out.reserve(entries_.size());
    for (const auto& [_, e] : entries_) out.push_back(e);
    return out;
}

std::vector<LoRAEntry> LoRARegistry::for_model(std::string_view model_id) const {
    std::vector<LoRAEntry> out;
    const std::string mid{model_id};
    for (const auto& [_, e] : entries_) {
        if (std::find(e.compatible_model_ids.begin(),
                      e.compatible_model_ids.end(), mid)
            != e.compatible_model_ids.end()) {
            out.push_back(e);
        }
    }
    return out;
}

const LoRAEntry* LoRARegistry::find(std::string_view id) const {
    const auto it = entries_.find(std::string{id});
    return it == entries_.end() ? nullptr : &it->second;
}

void LoRARegistry::clear() { entries_.clear(); }

std::size_t LoRARegistry::size() const { return entries_.size(); }

}  // namespace ra::core
