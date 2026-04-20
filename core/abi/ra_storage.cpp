// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.

#include "ra_storage.h"

#include "../util/storage_analyzer.h"

#include <cstdlib>
#include <cstring>
#include <string>

namespace {
char* dup_cstr(const std::string& s) {
    char* out = static_cast<char*>(std::malloc(s.size() + 1));
    if (!out) return nullptr;
    std::memcpy(out, s.data(), s.size());
    out[s.size()] = '\0';
    return out;
}
}  // namespace

extern "C" {

ra_status_t ra_storage_disk_space_for(const char* path, ra_storage_disk_space_t* out_info) {
    if (!path || !out_info) return RA_ERR_INVALID_ARGUMENT;
    auto info = ra::core::util::disk_space_for(path);
    out_info->capacity_bytes  = static_cast<int64_t>(info.capacity_bytes);
    out_info->free_bytes      = static_cast<int64_t>(info.free_bytes);
    out_info->available_bytes = static_cast<int64_t>(info.available_bytes);
    return RA_OK;
}

uint8_t ra_storage_can_fit(const char* path, int64_t required_bytes) {
    if (!path || required_bytes < 0) return 0;
    auto info = ra::core::util::disk_space_for(path);
    return (static_cast<int64_t>(info.available_bytes) >= required_bytes) ? 1 : 0;
}

ra_status_t ra_storage_list_models(ra_storage_model_info_t** out_models, int32_t* out_count) {
    if (!out_models || !out_count) return RA_ERR_INVALID_ARGUMENT;
    auto v = ra::core::util::list_models_with_size();
    *out_count = static_cast<int32_t>(v.size());
    if (v.empty()) { *out_models = nullptr; return RA_OK; }
    *out_models = static_cast<ra_storage_model_info_t*>(
        std::calloc(v.size(), sizeof(ra_storage_model_info_t)));
    if (!*out_models) return RA_ERR_OUT_OF_MEMORY;
    for (std::size_t i = 0; i < v.size(); ++i) {
        (*out_models)[i].model_id   = dup_cstr(v[i].model_id);
        (*out_models)[i].framework  = dup_cstr(v[i].framework);
        (*out_models)[i].path       = dup_cstr(v[i].path);
        (*out_models)[i].size_bytes = static_cast<int64_t>(v[i].size_bytes);
    }
    return RA_OK;
}

void ra_storage_model_info_free(ra_storage_model_info_t* m) {
    if (!m) return;
    if (m->model_id)  std::free(m->model_id);
    if (m->framework) std::free(m->framework);
    if (m->path)      std::free(m->path);
    *m = ra_storage_model_info_t{};
}

void ra_storage_model_info_array_free(ra_storage_model_info_t* arr, int32_t count) {
    if (!arr) return;
    for (int32_t i = 0; i < count; ++i) ra_storage_model_info_free(&arr[i]);
    std::free(arr);
}

}  // extern "C"
