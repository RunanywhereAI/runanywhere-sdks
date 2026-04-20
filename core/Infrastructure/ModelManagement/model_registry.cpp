// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.

#include "model_registry.h"

namespace ra::core {

ModelRegistry& ModelRegistry::global() {
    static ModelRegistry instance;
    return instance;
}

void ModelRegistry::upsert(ModelEntry entry) {
    std::lock_guard<std::mutex> lk(mu_);
    by_id_[entry.id] = std::move(entry);
}

std::optional<ModelEntry> ModelRegistry::find(std::string_view id) const {
    std::lock_guard<std::mutex> lk(mu_);
    auto it = by_id_.find(std::string(id));
    if (it == by_id_.end()) return std::nullopt;
    return it->second;
}

std::vector<ModelEntry> ModelRegistry::by_capability(ra_primitive_t p) const {
    std::lock_guard<std::mutex> lk(mu_);
    std::vector<ModelEntry> out;
    out.reserve(by_id_.size());
    for (const auto& [id, entry] : by_id_) {
        for (auto cap : entry.capabilities) {
            if (cap == p) { out.push_back(entry); break; }
        }
    }
    return out;
}

void ModelRegistry::clear() {
    std::lock_guard<std::mutex> lk(mu_);
    by_id_.clear();
}

std::size_t ModelRegistry::size() const {
    std::lock_guard<std::mutex> lk(mu_);
    return by_id_.size();
}

}  // namespace ra::core
