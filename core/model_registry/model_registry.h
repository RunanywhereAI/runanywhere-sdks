// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// Model registry — the single source of truth for model metadata and
// resolved filesystem paths. Ported from KMP ModelManager.kt + Swift
// ModelDownloader.swift into C++ so every frontend sees the same state.

#ifndef RA_CORE_MODEL_REGISTRY_H
#define RA_CORE_MODEL_REGISTRY_H

#include <chrono>
#include <cstddef>
#include <mutex>
#include <optional>
#include <string>
#include <string_view>
#include <unordered_map>
#include <vector>

#include "../abi/ra_primitives.h"

namespace ra::core {

struct ModelEntry {
    std::string       id;                 // e.g. "qwen3-4b-q4_k_m"
    std::string       display_name;
    ra_model_format_t format = RA_FORMAT_UNKNOWN;
    std::string       local_path;         // Absolute path once downloaded
    std::string       remote_url;         // HTTPS mirror
    std::string       sha256;             // Expected hex digest
    std::size_t       size_bytes = 0;               // Download size on disk
    std::size_t       memory_required_bytes = 0;    // Peak RAM to run; 0 = unknown
    std::vector<ra_primitive_t> capabilities;
    bool              is_downloaded = false;
    std::chrono::system_clock::time_point last_used;
};

class ModelRegistry {
public:
    static ModelRegistry& global();

    ModelRegistry(const ModelRegistry&)            = delete;
    ModelRegistry& operator=(const ModelRegistry&) = delete;

    // Register a model definition. Idempotent — later calls update the
    // metadata (useful for a downloader marking downloaded=true).
    void upsert(ModelEntry entry);

    std::optional<ModelEntry> find(std::string_view id) const;

    // Enumerate by capability — used by the L3 router to list candidates.
    std::vector<ModelEntry> by_capability(ra_primitive_t primitive) const;

    // Clear all registered models. Used by tests only.
    void clear();

    std::size_t size() const;

private:
    ModelRegistry() = default;

    mutable std::mutex                              mu_;
    std::unordered_map<std::string, ModelEntry>    by_id_;
};

}  // namespace ra::core

#endif  // RA_CORE_MODEL_REGISTRY_H
