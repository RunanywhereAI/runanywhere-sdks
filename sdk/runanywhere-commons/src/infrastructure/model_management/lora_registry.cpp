/**
 * @file lora_registry.cpp
 * @brief RunAnywhere Commons - LoRA Adapter Registry Implementation
 *
 * In-memory LoRA adapter metadata store.
 * Follows the same pattern as model_registry.cpp.
 */

#include <cstdlib>
#include <cstring>
#include <map>
#include <mutex>
#include <string>
#include <vector>

#include "rac/core/rac_logger.h"
#include "rac/infrastructure/model_management/rac_lora_registry.h"

struct rac_lora_registry {
    std::map<std::string, rac_lora_entry_t*> entries;
    std::mutex mutex;
};

static void free_lora_entry(rac_lora_entry_t* entry);

static rac_lora_entry_t* deep_copy_lora_entry(const rac_lora_entry_t* src) {
    if (!src) return nullptr;
    rac_lora_entry_t* copy = static_cast<rac_lora_entry_t*>(calloc(1, sizeof(rac_lora_entry_t)));
    if (!copy) return nullptr;
    copy->id = rac_strdup(src->id);
    copy->name = rac_strdup(src->name);
    copy->description = rac_strdup(src->description);
    copy->download_url = rac_strdup(src->download_url);
    copy->filename = rac_strdup(src->filename);

    // Any non-null source string that failed to copy means OOM — entry is unusable
    if ((src->id && !copy->id) ||
        (src->name && !copy->name) ||
        (src->description && !copy->description) ||
        (src->download_url && !copy->download_url) ||
        (src->filename && !copy->filename)) {
        free_lora_entry(copy);
        return nullptr;
    }

    if (src->compatible_model_ids && src->compatible_model_count > 0) {
        // Use calloc so unwritten slots are null-safe for free_lora_entry on partial failure
        copy->compatible_model_ids = static_cast<char**>(calloc(src->compatible_model_count, sizeof(char*)));
        if (!copy->compatible_model_ids) {
            free_lora_entry(copy);
            return nullptr;
        }
        // Set count before filling so free_lora_entry can clean up on partial failure
        copy->compatible_model_count = src->compatible_model_count;
        for (size_t i = 0; i < src->compatible_model_count; ++i) {
            copy->compatible_model_ids[i] = rac_strdup(src->compatible_model_ids[i]);
            if (src->compatible_model_ids[i] && !copy->compatible_model_ids[i]) {
                free_lora_entry(copy);
                return nullptr;
            }
        }
    }
    copy->file_size = src->file_size;
    copy->default_scale = src->default_scale;
    return copy;
}

static void free_lora_entry(rac_lora_entry_t* entry) {
    if (!entry) return;
    if (entry->id) free(entry->id);
    if (entry->name) free(entry->name);
    if (entry->description) free(entry->description);
    if (entry->download_url) free(entry->download_url);
    if (entry->filename) free(entry->filename);
    if (entry->compatible_model_ids) {
        for (size_t i = 0; i < entry->compatible_model_count; ++i) {
            if (entry->compatible_model_ids[i]) free(entry->compatible_model_ids[i]);
        }
        free(entry->compatible_model_ids);
    }
    free(entry);
}

// LIFECYCLE

rac_result_t rac_lora_registry_create(rac_lora_registry_handle_t* out_handle) {
    if (!out_handle) return RAC_ERROR_INVALID_ARGUMENT;
    rac_lora_registry* registry = new rac_lora_registry();
    RAC_LOG_INFO("LoraRegistry", "LoRA registry created");
    *out_handle = registry;
    return RAC_SUCCESS;
}

void rac_lora_registry_destroy(rac_lora_registry_handle_t handle) {
    if (!handle) return;
    for (auto& pair : handle->entries) { free_lora_entry(pair.second); }
    handle->entries.clear();
    delete handle;
    RAC_LOG_DEBUG("LoraRegistry", "LoRA registry destroyed");
}

// REGISTRATION

rac_result_t rac_lora_registry_register(rac_lora_registry_handle_t handle,
                                         const rac_lora_entry_t* entry) {
    if (!handle || !entry || !entry->id) return RAC_ERROR_INVALID_ARGUMENT;
    std::lock_guard<std::mutex> lock(handle->mutex);
    std::string adapter_id = entry->id;
    auto it = handle->entries.find(adapter_id);
    if (it != handle->entries.end()) { free_lora_entry(it->second); }
    rac_lora_entry_t* copy = deep_copy_lora_entry(entry);
    if (!copy) return RAC_ERROR_OUT_OF_MEMORY;
    handle->entries[adapter_id] = copy;
    RAC_LOG_DEBUG("LoraRegistry", "LoRA adapter registered: %s", entry->id);
    return RAC_SUCCESS;
}

rac_result_t rac_lora_registry_remove(rac_lora_registry_handle_t handle, const char* adapter_id) {
    if (!handle || !adapter_id) return RAC_ERROR_INVALID_ARGUMENT;
    std::lock_guard<std::mutex> lock(handle->mutex);
    auto it = handle->entries.find(adapter_id);
    if (it == handle->entries.end()) return RAC_ERROR_NOT_FOUND;
    free_lora_entry(it->second);
    handle->entries.erase(it);
    RAC_LOG_DEBUG("LoraRegistry", "LoRA adapter removed: %s", adapter_id);
    return RAC_SUCCESS;
}

// QUERIES

rac_result_t rac_lora_registry_get_all(rac_lora_registry_handle_t handle,
                                        rac_lora_entry_t*** out_entries, size_t* out_count) {
    if (!handle || !out_entries || !out_count) return RAC_ERROR_INVALID_ARGUMENT;
    std::lock_guard<std::mutex> lock(handle->mutex);
    *out_count = handle->entries.size();
    if (*out_count == 0) { *out_entries = nullptr; return RAC_SUCCESS; }
    *out_entries = static_cast<rac_lora_entry_t**>(malloc(sizeof(rac_lora_entry_t*) * *out_count));
    if (!*out_entries) return RAC_ERROR_OUT_OF_MEMORY;
    size_t i = 0;
    for (const auto& pair : handle->entries) {
        (*out_entries)[i] = deep_copy_lora_entry(pair.second);
        if (!(*out_entries)[i]) {
            for (size_t j = 0; j < i; ++j) free_lora_entry((*out_entries)[j]);
            free(*out_entries); *out_entries = nullptr; *out_count = 0;
            return RAC_ERROR_OUT_OF_MEMORY;
        }
        ++i;
    }
    return RAC_SUCCESS;
}

rac_result_t rac_lora_registry_get_for_model(rac_lora_registry_handle_t handle,
                                              const char* model_id,
                                              rac_lora_entry_t*** out_entries, size_t* out_count) {
    if (!handle || !model_id || !out_entries || !out_count) return RAC_ERROR_INVALID_ARGUMENT;
    std::lock_guard<std::mutex> lock(handle->mutex);
    std::vector<rac_lora_entry_t*> matches;
    for (const auto& pair : handle->entries) {
        const rac_lora_entry_t* entry = pair.second;
        if (!entry->compatible_model_ids) continue;
        for (size_t i = 0; i < entry->compatible_model_count; ++i) {
            if (entry->compatible_model_ids[i] && strcmp(entry->compatible_model_ids[i], model_id) == 0) {
                matches.push_back(pair.second);
                break;
            }
        }
    }
    *out_count = matches.size();
    if (*out_count == 0) { *out_entries = nullptr; return RAC_SUCCESS; }
    *out_entries = static_cast<rac_lora_entry_t**>(malloc(sizeof(rac_lora_entry_t*) * *out_count));
    if (!*out_entries) return RAC_ERROR_OUT_OF_MEMORY;
    for (size_t i = 0; i < matches.size(); ++i) {
        (*out_entries)[i] = deep_copy_lora_entry(matches[i]);
        if (!(*out_entries)[i]) {
            for (size_t j = 0; j < i; ++j) free_lora_entry((*out_entries)[j]);
            free(*out_entries); *out_entries = nullptr; *out_count = 0;
            return RAC_ERROR_OUT_OF_MEMORY;
        }
    }
    return RAC_SUCCESS;
}

rac_result_t rac_lora_registry_get(rac_lora_registry_handle_t handle, const char* adapter_id,
                                    rac_lora_entry_t** out_entry) {
    if (!handle || !adapter_id || !out_entry) return RAC_ERROR_INVALID_ARGUMENT;
    std::lock_guard<std::mutex> lock(handle->mutex);
    auto it = handle->entries.find(adapter_id);
    if (it == handle->entries.end()) return RAC_ERROR_NOT_FOUND;
    *out_entry = deep_copy_lora_entry(it->second);
    if (!*out_entry) return RAC_ERROR_OUT_OF_MEMORY;
    return RAC_SUCCESS;
}

// MEMORY

void rac_lora_entry_free(rac_lora_entry_t* entry) { free_lora_entry(entry); }

void rac_lora_entry_array_free(rac_lora_entry_t** entries, size_t count) {
    if (!entries) return;
    for (size_t i = 0; i < count; ++i) free_lora_entry(entries[i]);
    free(entries);
}

rac_lora_entry_t* rac_lora_entry_copy(const rac_lora_entry_t* entry) {
    return deep_copy_lora_entry(entry);
}
