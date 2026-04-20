// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.

#include "ra_file.h"

#include "file_manager.h"

#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

namespace {

char* dup_cstr(const std::string& s) {
    char* out = static_cast<char*>(std::malloc(s.size() + 1));
    if (!out) return nullptr;
    std::memcpy(out, s.data(), s.size());
    out[s.size()] = '\0';
    return out;
}

ra_status_t emit_array(const std::vector<std::string>& v,
                        char*** out_arr, int32_t* out_count) {
    *out_count = static_cast<int32_t>(v.size());
    if (v.empty()) { *out_arr = nullptr; return RA_OK; }
    *out_arr = static_cast<char**>(std::malloc(v.size() * sizeof(char*)));
    if (!*out_arr) return RA_ERR_OUT_OF_MEMORY;
    for (std::size_t i = 0; i < v.size(); ++i) (*out_arr)[i] = dup_cstr(v[i]);
    return RA_OK;
}

}  // namespace

extern "C" {

ra_status_t ra_file_create_directory(const char* path) {
    if (!path) return RA_ERR_INVALID_ARGUMENT;
    return ra::core::util::create_directory(path) ? RA_OK : RA_ERR_IO;
}

ra_status_t ra_file_remove_path(const char* path) {
    if (!path) return RA_ERR_INVALID_ARGUMENT;
    return ra::core::util::remove_path(path) ? RA_OK : RA_ERR_IO;
}

uint8_t ra_file_path_exists(const char* path) {
    return path && ra::core::util::path_exists(path) ? 1 : 0;
}
uint8_t ra_file_is_directory(const char* path) {
    return path && ra::core::util::is_directory(path) ? 1 : 0;
}
uint8_t ra_file_is_regular_file(const char* path) {
    return path && ra::core::util::is_regular_file(path) ? 1 : 0;
}

ra_status_t ra_file_list_directory(const char* path, char*** out_entries, int32_t* out_count) {
    if (!path || !out_entries || !out_count) return RA_ERR_INVALID_ARGUMENT;
    return emit_array(ra::core::util::list_directory(path), out_entries, out_count);
}

ra_status_t ra_file_list_directory_recursive(const char* path, char*** out_entries, int32_t* out_count) {
    if (!path || !out_entries || !out_count) return RA_ERR_INVALID_ARGUMENT;
    return emit_array(ra::core::util::list_directory_recursive(path), out_entries, out_count);
}

int64_t ra_file_directory_size_bytes(const char* path) {
    if (!path) return 0;
    return static_cast<int64_t>(ra::core::util::directory_size_bytes(path));
}
int64_t ra_file_size_bytes(const char* path) {
    if (!path) return 0;
    return static_cast<int64_t>(ra::core::util::file_size_bytes(path));
}

ra_status_t ra_file_app_support_dir(char** out_path) {
    if (!out_path) return RA_ERR_INVALID_ARGUMENT;
    *out_path = dup_cstr(ra::core::util::app_support_dir().string());
    return *out_path ? RA_OK : RA_ERR_OUT_OF_MEMORY;
}
ra_status_t ra_file_cache_dir(char** out_path) {
    if (!out_path) return RA_ERR_INVALID_ARGUMENT;
    *out_path = dup_cstr(ra::core::util::cache_dir().string());
    return *out_path ? RA_OK : RA_ERR_OUT_OF_MEMORY;
}
ra_status_t ra_file_tmp_dir(char** out_path) {
    if (!out_path) return RA_ERR_INVALID_ARGUMENT;
    *out_path = dup_cstr(ra::core::util::tmp_dir().string());
    return *out_path ? RA_OK : RA_ERR_OUT_OF_MEMORY;
}
ra_status_t ra_file_models_dir(char** out_path) {
    if (!out_path) return RA_ERR_INVALID_ARGUMENT;
    *out_path = dup_cstr(ra::core::util::models_dir().string());
    return *out_path ? RA_OK : RA_ERR_OUT_OF_MEMORY;
}
ra_status_t ra_file_model_path(const char* framework, const char* model_id, char** out_path) {
    if (!framework || !model_id || !out_path) return RA_ERR_INVALID_ARGUMENT;
    *out_path = dup_cstr(ra::core::util::model_path(framework, model_id).string());
    return *out_path ? RA_OK : RA_ERR_OUT_OF_MEMORY;
}

int64_t ra_file_clear_cache(void) {
    return static_cast<int64_t>(ra::core::util::clear_cache());
}
int64_t ra_file_clear_tmp(void) {
    return static_cast<int64_t>(ra::core::util::clear_tmp());
}

void ra_file_string_free(char* s) { if (s) std::free(s); }
void ra_file_string_array_free(char** arr, int32_t count) {
    if (!arr) return;
    for (int32_t i = 0; i < count; ++i) std::free(arr[i]);
    std::free(arr);
}

}  // extern "C"
