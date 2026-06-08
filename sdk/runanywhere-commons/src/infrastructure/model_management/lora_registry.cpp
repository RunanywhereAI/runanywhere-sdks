/**
 * @file lora_registry.cpp
 * @brief RunAnywhere Commons - LoRA Adapter Registry Implementation
 *
 * In-memory LoRA adapter metadata store.
 * Follows the same pattern as model_registry.cpp.
 */

#include <algorithm>
#include <cctype>
#include <chrono>
#include <cstdlib>
#include <cstring>
#include <map>
#include <mutex>
#include <new>
#include <ranges>
#include <string>
#include <vector>

#include "rac/core/rac_logger.h"
#include "rac/foundation/rac_proto_buffer.h"
#include "rac/infrastructure/model_management/rac_lora_registry.h"

#ifdef RAC_HAVE_PROTOBUF
#include "lora_options.pb.h"

#include "foundation/rac_proto_marshal_internal.h"
#include "rac/foundation/rac_proto_adapters.h"
#endif

struct rac_lora_registry {
    std::map<std::string, rac_lora_entry_t*> entries;
#ifdef RAC_HAVE_PROTOBUF
    std::map<std::string, std::string> entry_proto_bytes;
#endif
    std::mutex mutex;
};

// Forward declaration — needed by deep_copy_lora_entry for OOM cleanup
static void free_lora_entry(rac_lora_entry_t* entry);

static rac_lora_entry_t* deep_copy_lora_entry(const rac_lora_entry_t* src) {
    if (!src)
        return nullptr;
    rac_lora_entry_t* copy = static_cast<rac_lora_entry_t*>(calloc(1, sizeof(rac_lora_entry_t)));
    if (!copy)
        return nullptr;
    copy->id = rac_strdup(src->id);
    copy->name = rac_strdup(src->name);
    copy->description = rac_strdup(src->description);
    copy->download_url = rac_strdup(src->download_url);
    copy->filename = rac_strdup(src->filename);

    // Any non-null source string that failed to copy means OOM — entry is unusable
    if ((src->id && !copy->id) || (src->name && !copy->name) ||
        (src->description && !copy->description) || (src->download_url && !copy->download_url) ||
        (src->filename && !copy->filename)) {
        free_lora_entry(copy);
        return nullptr;
    }

    if (src->compatible_model_ids && src->compatible_model_count > 0) {
        // Use calloc so unwritten slots are null-safe for free_lora_entry on partial failure
        copy->compatible_model_ids =
            static_cast<char**>(calloc(src->compatible_model_count, sizeof(char*)));
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
    if (!entry)
        return;
    if (entry->id)
        free(entry->id);
    if (entry->name)
        free(entry->name);
    if (entry->description)
        free(entry->description);
    if (entry->download_url)
        free(entry->download_url);
    if (entry->filename)
        free(entry->filename);
    if (entry->compatible_model_ids) {
        for (size_t i = 0; i < entry->compatible_model_count; ++i) {
            if (entry->compatible_model_ids[i])
                free(entry->compatible_model_ids[i]);
        }
        free(static_cast<void*>(entry->compatible_model_ids));
    }
    free(entry);
}

#ifdef RAC_HAVE_PROTOBUF
namespace {

int64_t current_time_ms() {
    using namespace std::chrono;
    return std::chrono::duration_cast<std::chrono::milliseconds>(
               std::chrono::system_clock::now().time_since_epoch())
        .count();
}

const void* parse_data(const uint8_t* bytes, size_t size) {
    return rac_proto_bytes_data_or_empty(bytes, size);
}

template <typename Message>
rac_result_t parse_proto_message(const uint8_t* bytes, size_t size, const char* message_name,
                                 Message* out, rac_proto_buffer_t* error_out) {
    rac_result_t validation = rac_proto_bytes_validate(bytes, size);
    if (validation != RAC_SUCCESS) {
        std::string message = std::string(message_name) + " bytes are invalid";
        return rac_proto_buffer_set_error(error_out, RAC_ERROR_DECODING_ERROR, message.c_str());
    }
    if (!out->ParseFromArray(parse_data(bytes, size), static_cast<int>(size))) {
        std::string message = std::string("failed to parse ") + message_name;
        return rac_proto_buffer_set_error(error_out, RAC_ERROR_DECODING_ERROR, message.c_str());
    }
    return RAC_SUCCESS;
}

rac_result_t copy_proto(const google::protobuf::MessageLite& message, rac_proto_buffer_t* out) {
    return rac::proto::copy_message(message, out, "failed to serialize proto result");
}

std::string lowercase_ascii(const std::string& value) {
    std::string lowered = value;
    std::ranges::transform(lowered, lowered.begin(),
                           [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
    return lowered;
}

bool contains_case_insensitive(const std::string& haystack, const std::string& needle_lower) {
    return lowercase_ascii(haystack).find(needle_lower) != std::string::npos;
}

bool catalog_entry_is_downloaded(const runanywhere::v1::LoraAdapterCatalogEntry& entry) {
    return (entry.has_is_downloaded() && entry.is_downloaded()) || !entry.local_path().empty();
}

void clear_completion_state(runanywhere::v1::LoraAdapterCatalogEntry* entry) {
    entry->clear_local_path();
    entry->clear_is_downloaded();
    entry->clear_downloaded_at_unix_ms();
    entry->clear_is_imported();
    entry->clear_status_message();
}

void preserve_completion_state(const runanywhere::v1::LoraAdapterCatalogEntry& from,
                               runanywhere::v1::LoraAdapterCatalogEntry* to) {
    if (from.has_local_path())
        to->set_local_path(from.local_path());
    if (from.has_is_downloaded())
        to->set_is_downloaded(from.is_downloaded());
    if (from.has_downloaded_at_unix_ms()) {
        to->set_downloaded_at_unix_ms(from.downloaded_at_unix_ms());
    }
    if (from.has_is_imported())
        to->set_is_imported(from.is_imported());
    if (from.has_status_message())
        to->set_status_message(from.status_message());
}

bool parse_snapshot(const std::string& bytes, runanywhere::v1::LoraAdapterCatalogEntry* out) {
    return out != nullptr && out->ParseFromArray(bytes.data(), static_cast<int>(bytes.size()));
}

rac_result_t store_catalog_snapshot_locked(rac_lora_registry_handle_t handle,
                                           const runanywhere::v1::LoraAdapterCatalogEntry& entry) {
    std::string bytes;
    if (!entry.SerializeToString(&bytes)) {
        return RAC_ERROR_ENCODING_ERROR;
    }
    handle->entry_proto_bytes[entry.id()] = bytes;
    return RAC_SUCCESS;
}

runanywhere::v1::LoraAdapterCatalogEntry
snapshot_from_struct_locked(rac_lora_registry_handle_t handle, const std::string& adapter_id,
                            const rac_lora_entry_t* entry) {
    runanywhere::v1::LoraAdapterCatalogEntry snapshot;
    auto proto_it = handle->entry_proto_bytes.find(adapter_id);
    if (proto_it != handle->entry_proto_bytes.end() &&
        parse_snapshot(proto_it->second, &snapshot)) {
        return snapshot;
    }

    (void)rac::foundation::rac_lora_entry_to_proto(entry, &snapshot);
    if (snapshot.id().empty()) {
        snapshot.set_id(adapter_id);
    }
    return snapshot;
}

rac_result_t store_struct_snapshot_locked(rac_lora_registry_handle_t handle,
                                          const std::string& adapter_id,
                                          const rac_lora_entry_t* entry) {
    runanywhere::v1::LoraAdapterCatalogEntry snapshot;
    auto proto_it = handle->entry_proto_bytes.find(adapter_id);
    if (proto_it != handle->entry_proto_bytes.end()) {
        (void)parse_snapshot(proto_it->second, &snapshot);
    }
    runanywhere::v1::LoraAdapterCatalogEntry from_struct;
    if (!rac::foundation::rac_lora_entry_to_proto(entry, &from_struct)) {
        return RAC_ERROR_DECODING_ERROR;
    }
    preserve_completion_state(snapshot, &from_struct);
    return store_catalog_snapshot_locked(handle, from_struct);
}

std::vector<runanywhere::v1::LoraAdapterCatalogEntry>
collect_snapshots_locked(rac_lora_registry_handle_t handle) {
    std::vector<runanywhere::v1::LoraAdapterCatalogEntry> entries;
    entries.reserve(handle->entries.size());
    for (const auto& pair : handle->entries) {
        entries.push_back(snapshot_from_struct_locked(handle, pair.first, pair.second));
    }
    return entries;
}

bool contains_model_id(const runanywhere::v1::LoraAdapterCatalogEntry& entry,
                       const std::string& model_id) {
    if (model_id.empty())
        return true;
    for (const auto& compatible_model : entry.compatible_models()) {
        if (compatible_model == model_id)
            return true;
    }
    return false;
}

bool contains_all_tags(const runanywhere::v1::LoraAdapterCatalogEntry& entry,
                       const runanywhere::v1::LoraAdapterCatalogQuery& query) {
    for (const auto& required_tag : query.tags()) {
        bool found = false;
        for (const auto& tag : entry.tags()) {
            if (tag == required_tag) {
                found = true;
                break;
            }
        }
        if (!found)
            return false;
    }
    return true;
}

bool matches_search_query(const runanywhere::v1::LoraAdapterCatalogEntry& entry,
                          const std::string& query) {
    if (query.empty())
        return true;
    const std::string needle = lowercase_ascii(query);
    if (contains_case_insensitive(entry.id(), needle) ||
        contains_case_insensitive(entry.name(), needle) ||
        contains_case_insensitive(entry.description(), needle)) {
        return true;
    }
    if (entry.has_author() && contains_case_insensitive(entry.author(), needle)) {
        return true;
    }
    for (const auto& tag : entry.tags()) {
        if (contains_case_insensitive(tag, needle))
            return true;
    }
    return false;
}

bool matches_catalog_query(const runanywhere::v1::LoraAdapterCatalogEntry& entry,
                           const runanywhere::v1::LoraAdapterCatalogQuery& query) {
    if (query.has_adapter_id() && !query.adapter_id().empty() && entry.id() != query.adapter_id()) {
        return false;
    }
    if (query.has_model_id() && !contains_model_id(entry, query.model_id())) {
        return false;
    }
    if (query.has_downloaded_only() && query.downloaded_only() &&
        !catalog_entry_is_downloaded(entry)) {
        return false;
    }
    if (query.has_search_query() && !matches_search_query(entry, query.search_query())) {
        return false;
    }
    return contains_all_tags(entry, query);
}

int32_t downloaded_count(const std::vector<runanywhere::v1::LoraAdapterCatalogEntry>& entries) {
    int32_t count = 0;
    for (const auto& entry : entries) {
        if (catalog_entry_is_downloaded(entry))
            ++count;
    }
    return count;
}

rac_result_t list_catalog_with_query(rac_lora_registry_handle_t handle,
                                     const runanywhere::v1::LoraAdapterCatalogQuery* query,
                                     rac_proto_buffer_t* out_result) {
    std::vector<runanywhere::v1::LoraAdapterCatalogEntry> all_entries;
    {
        std::lock_guard<std::mutex> lock(handle->mutex);
        all_entries = collect_snapshots_locked(handle);
    }

    std::vector<runanywhere::v1::LoraAdapterCatalogEntry> filtered;
    filtered.reserve(all_entries.size());
    for (const auto& entry : all_entries) {
        if (!query || matches_catalog_query(entry, *query)) {
            filtered.push_back(entry);
        }
    }

    runanywhere::v1::LoraAdapterCatalogListResult result;
    result.set_success(true);
    result.set_total_count(static_cast<int32_t>(all_entries.size()));
    result.set_filtered_count(static_cast<int32_t>(filtered.size()));
    result.set_downloaded_count(downloaded_count(filtered));
    for (const auto& entry : filtered) {
        *result.add_entries() = entry;
    }
    return copy_proto(result, out_result);
}

}  // namespace
#endif

// LIFECYCLE

rac_result_t rac_lora_registry_create(rac_lora_registry_handle_t* out_handle) {
    if (!out_handle)
        return RAC_ERROR_INVALID_ARGUMENT;
    rac_lora_registry* registry = new (std::nothrow) rac_lora_registry();
    if (!registry)
        return RAC_ERROR_OUT_OF_MEMORY;
    RAC_LOG_INFO("LoraRegistry", "LoRA registry created");
    *out_handle = registry;
    return RAC_SUCCESS;
}

void rac_lora_registry_destroy(rac_lora_registry_handle_t handle) {
    if (!handle)
        return;
    {
        std::lock_guard<std::mutex> lock(handle->mutex);
        for (auto& pair : handle->entries) {
            free_lora_entry(pair.second);
        }
        handle->entries.clear();
    }
    delete handle;
    RAC_LOG_DEBUG("LoraRegistry", "LoRA registry destroyed");
}

// REGISTRATION

rac_result_t rac_lora_registry_register(rac_lora_registry_handle_t handle,
                                        const rac_lora_entry_t* entry) {
    if (!handle || !entry || !entry->id)
        return RAC_ERROR_INVALID_ARGUMENT;
    std::lock_guard<std::mutex> lock(handle->mutex);
    std::string adapter_id = entry->id;
    rac_lora_entry_t* copy = deep_copy_lora_entry(entry);
    if (!copy)
        return RAC_ERROR_OUT_OF_MEMORY;
    // Free old entry AFTER successful deep_copy to avoid dangling pointer on OOM
    auto it = handle->entries.find(adapter_id);
    if (it != handle->entries.end()) {
        free_lora_entry(it->second);
    }
    handle->entries[adapter_id] = copy;
#ifdef RAC_HAVE_PROTOBUF
    rac_result_t snapshot_rc = store_struct_snapshot_locked(handle, adapter_id, copy);
    if (snapshot_rc != RAC_SUCCESS) {
        return snapshot_rc;
    }
#endif
    RAC_LOG_DEBUG("LoraRegistry", "LoRA adapter registered: %s", entry->id);
    return RAC_SUCCESS;
}

rac_result_t rac_lora_registry_remove(rac_lora_registry_handle_t handle, const char* adapter_id) {
    if (!handle || !adapter_id)
        return RAC_ERROR_INVALID_ARGUMENT;
    std::lock_guard<std::mutex> lock(handle->mutex);
    auto it = handle->entries.find(adapter_id);
    if (it == handle->entries.end())
        return RAC_ERROR_NOT_FOUND;
    free_lora_entry(it->second);
    handle->entries.erase(it);
#ifdef RAC_HAVE_PROTOBUF
    handle->entry_proto_bytes.erase(adapter_id);
#endif
    RAC_LOG_DEBUG("LoraRegistry", "LoRA adapter removed: %s", adapter_id);
    return RAC_SUCCESS;
}

// QUERIES

rac_result_t rac_lora_registry_get_all(rac_lora_registry_handle_t handle,
                                       rac_lora_entry_t*** out_entries, size_t* out_count) {
    if (!handle || !out_entries || !out_count)
        return RAC_ERROR_INVALID_ARGUMENT;
    std::lock_guard<std::mutex> lock(handle->mutex);
    *out_count = handle->entries.size();
    if (*out_count == 0) {
        *out_entries = nullptr;
        return RAC_SUCCESS;
    }
    *out_entries = static_cast<rac_lora_entry_t**>(malloc(sizeof(rac_lora_entry_t*) * *out_count));
    if (!*out_entries)
        return RAC_ERROR_OUT_OF_MEMORY;
    size_t i = 0;
    for (const auto& pair : handle->entries) {
        (*out_entries)[i] = deep_copy_lora_entry(pair.second);
        if (!(*out_entries)[i]) {
            for (size_t j = 0; j < i; ++j)
                free_lora_entry((*out_entries)[j]);
            free(static_cast<void*>(*out_entries));
            *out_entries = nullptr;
            *out_count = 0;
            return RAC_ERROR_OUT_OF_MEMORY;
        }
        ++i;
    }
    return RAC_SUCCESS;
}

rac_result_t rac_lora_registry_get_for_model(rac_lora_registry_handle_t handle,
                                             const char* model_id, rac_lora_entry_t*** out_entries,
                                             size_t* out_count) {
    if (!handle || !model_id || !out_entries || !out_count)
        return RAC_ERROR_INVALID_ARGUMENT;
    std::lock_guard<std::mutex> lock(handle->mutex);
    std::vector<rac_lora_entry_t*> matches;
    for (const auto& pair : handle->entries) {
        const rac_lora_entry_t* entry = pair.second;
        if (!entry->compatible_model_ids)
            continue;
        for (size_t i = 0; i < entry->compatible_model_count; ++i) {
            if (entry->compatible_model_ids[i] &&
                strcmp(entry->compatible_model_ids[i], model_id) == 0) {
                matches.push_back(pair.second);
                break;
            }
        }
    }
    *out_count = matches.size();
    if (*out_count == 0) {
        *out_entries = nullptr;
        return RAC_SUCCESS;
    }
    *out_entries = static_cast<rac_lora_entry_t**>(malloc(sizeof(rac_lora_entry_t*) * *out_count));
    if (!*out_entries)
        return RAC_ERROR_OUT_OF_MEMORY;
    for (size_t i = 0; i < matches.size(); ++i) {
        (*out_entries)[i] = deep_copy_lora_entry(matches[i]);
        if (!(*out_entries)[i]) {
            for (size_t j = 0; j < i; ++j)
                free_lora_entry((*out_entries)[j]);
            free(static_cast<void*>(*out_entries));
            *out_entries = nullptr;
            *out_count = 0;
            return RAC_ERROR_OUT_OF_MEMORY;
        }
    }
    return RAC_SUCCESS;
}

rac_result_t rac_lora_registry_get(rac_lora_registry_handle_t handle, const char* adapter_id,
                                   rac_lora_entry_t** out_entry) {
    if (!handle || !adapter_id || !out_entry)
        return RAC_ERROR_INVALID_ARGUMENT;
    std::lock_guard<std::mutex> lock(handle->mutex);
    auto it = handle->entries.find(adapter_id);
    if (it == handle->entries.end())
        return RAC_ERROR_NOT_FOUND;
    *out_entry = deep_copy_lora_entry(it->second);
    if (!*out_entry)
        return RAC_ERROR_OUT_OF_MEMORY;
    return RAC_SUCCESS;
}

// MEMORY

void rac_lora_entry_free(rac_lora_entry_t* entry) {
    free_lora_entry(entry);
}

void rac_lora_entry_array_free(rac_lora_entry_t** entries, size_t count) {
    if (!entries)
        return;
    for (size_t i = 0; i < count; ++i)
        free_lora_entry(entries[i]);
    free(static_cast<void*>(entries));
}

rac_lora_entry_t* rac_lora_entry_copy(const rac_lora_entry_t* entry) {
    return deep_copy_lora_entry(entry);
}

extern "C" rac_result_t rac_lora_registry_register_catalog_entry_proto(
    rac_lora_registry_handle_t registry, const uint8_t* entry_proto_bytes, size_t entry_proto_size,
    rac_proto_buffer_t* out_entry) {
    if (!out_entry)
        return RAC_ERROR_NULL_POINTER;
#ifndef RAC_HAVE_PROTOBUF
    (void)registry;
    (void)entry_proto_bytes;
    (void)entry_proto_size;
    return rac_proto_buffer_set_error(out_entry, RAC_ERROR_FEATURE_NOT_AVAILABLE,
                                      "protobuf support is not available");
#else
    if (!registry) {
        return rac_proto_buffer_set_error(out_entry, RAC_ERROR_NULL_POINTER,
                                          "LoRA registry handle is required");
    }

    runanywhere::v1::LoraAdapterCatalogEntry proto;
    rac_result_t rc = parse_proto_message(entry_proto_bytes, entry_proto_size,
                                          "LoraAdapterCatalogEntry", &proto, out_entry);
    if (rc != RAC_SUCCESS)
        return rc;
    if (proto.id().empty()) {
        return rac_proto_buffer_set_error(out_entry, RAC_ERROR_INVALID_ARGUMENT,
                                          "LoraAdapterCatalogEntry.id is required");
    }

    clear_completion_state(&proto);
    {
        std::lock_guard<std::mutex> lock(registry->mutex);
        auto existing_it = registry->entry_proto_bytes.find(proto.id());
        if (existing_it != registry->entry_proto_bytes.end()) {
            runanywhere::v1::LoraAdapterCatalogEntry existing;
            if (parse_snapshot(existing_it->second, &existing)) {
                preserve_completion_state(existing, &proto);
            }
        }
    }

    auto* entry = static_cast<rac_lora_entry_t*>(std::calloc(1, sizeof(rac_lora_entry_t)));
    if (!entry) {
        return rac_proto_buffer_set_error(out_entry, RAC_ERROR_OUT_OF_MEMORY,
                                          "failed to allocate LoRA entry");
    }
    if (!rac::foundation::rac_lora_entry_from_proto(proto, entry)) {
        rac_lora_entry_free(entry);
        return rac_proto_buffer_set_error(out_entry, RAC_ERROR_DECODING_ERROR,
                                          "failed to convert LoraAdapterCatalogEntry");
    }

    rc = rac_lora_registry_register(registry, entry);
    rac_lora_entry_free(entry);
    if (rc != RAC_SUCCESS) {
        return rac_proto_buffer_set_error(out_entry, rc, rac_error_message(rc));
    }

    {
        std::lock_guard<std::mutex> lock(registry->mutex);
        rc = store_catalog_snapshot_locked(registry, proto);
    }
    if (rc != RAC_SUCCESS) {
        return rac_proto_buffer_set_error(out_entry, rc, rac_error_message(rc));
    }
    return copy_proto(proto, out_entry);
#endif
}

extern "C" RAC_API rac_result_t rac_lora_catalog_list_proto(rac_lora_registry_handle_t registry,
                                                            const uint8_t* request_proto_bytes,
                                                            size_t request_proto_size,
                                                            rac_proto_buffer_t* out_result) {
    if (!out_result)
        return RAC_ERROR_NULL_POINTER;
#ifndef RAC_HAVE_PROTOBUF
    (void)registry;
    (void)request_proto_bytes;
    (void)request_proto_size;
    return rac_proto_buffer_set_error(out_result, RAC_ERROR_FEATURE_NOT_AVAILABLE,
                                      "protobuf support is not available");
#else
    if (!registry) {
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_NULL_POINTER,
                                          "LoRA registry handle is required");
    }

    runanywhere::v1::LoraAdapterCatalogListRequest request;
    rac_result_t rc = parse_proto_message(request_proto_bytes, request_proto_size,
                                          "LoraAdapterCatalogListRequest", &request, out_result);
    if (rc != RAC_SUCCESS)
        return rc;
    const runanywhere::v1::LoraAdapterCatalogQuery* query =
        request.has_query() ? &request.query() : nullptr;
    return list_catalog_with_query(registry, query, out_result);
#endif
}

extern "C" RAC_API rac_result_t rac_lora_catalog_query_proto(rac_lora_registry_handle_t registry,
                                                             const uint8_t* query_proto_bytes,
                                                             size_t query_proto_size,
                                                             rac_proto_buffer_t* out_result) {
    if (!out_result)
        return RAC_ERROR_NULL_POINTER;
#ifndef RAC_HAVE_PROTOBUF
    (void)registry;
    (void)query_proto_bytes;
    (void)query_proto_size;
    return rac_proto_buffer_set_error(out_result, RAC_ERROR_FEATURE_NOT_AVAILABLE,
                                      "protobuf support is not available");
#else
    if (!registry) {
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_NULL_POINTER,
                                          "LoRA registry handle is required");
    }

    runanywhere::v1::LoraAdapterCatalogQuery query;
    rac_result_t rc = parse_proto_message(query_proto_bytes, query_proto_size,
                                          "LoraAdapterCatalogQuery", &query, out_result);
    if (rc != RAC_SUCCESS)
        return rc;
    return list_catalog_with_query(registry, &query, out_result);
#endif
}

extern "C" RAC_API rac_result_t rac_lora_catalog_get_proto(rac_lora_registry_handle_t registry,
                                                           const uint8_t* request_proto_bytes,
                                                           size_t request_proto_size,
                                                           rac_proto_buffer_t* out_result) {
    if (!out_result)
        return RAC_ERROR_NULL_POINTER;
#ifndef RAC_HAVE_PROTOBUF
    (void)registry;
    (void)request_proto_bytes;
    (void)request_proto_size;
    return rac_proto_buffer_set_error(out_result, RAC_ERROR_FEATURE_NOT_AVAILABLE,
                                      "protobuf support is not available");
#else
    if (!registry) {
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_NULL_POINTER,
                                          "LoRA registry handle is required");
    }

    runanywhere::v1::LoraAdapterCatalogGetRequest request;
    rac_result_t rc = parse_proto_message(request_proto_bytes, request_proto_size,
                                          "LoraAdapterCatalogGetRequest", &request, out_result);
    if (rc != RAC_SUCCESS)
        return rc;
    if (request.adapter_id().empty()) {
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_INVALID_ARGUMENT,
                                          "LoraAdapterCatalogGetRequest.adapter_id is required");
    }

    runanywhere::v1::LoraAdapterCatalogGetResult result;
    {
        std::lock_guard<std::mutex> lock(registry->mutex);
        auto it = registry->entries.find(request.adapter_id());
        if (it == registry->entries.end()) {
            result.set_found(false);
            result.set_error_message("LoRA catalog entry not found");
        } else {
            result.set_found(true);
            *result.mutable_entry() =
                snapshot_from_struct_locked(registry, request.adapter_id(), it->second);
        }
    }
    return copy_proto(result, out_result);
#endif
}

extern "C" RAC_API rac_result_t rac_lora_catalog_mark_download_completed_proto(
    rac_lora_registry_handle_t registry, const uint8_t* request_proto_bytes,
    size_t request_proto_size, rac_proto_buffer_t* out_result) {
    if (!out_result)
        return RAC_ERROR_NULL_POINTER;
#ifndef RAC_HAVE_PROTOBUF
    (void)registry;
    (void)request_proto_bytes;
    (void)request_proto_size;
    return rac_proto_buffer_set_error(out_result, RAC_ERROR_FEATURE_NOT_AVAILABLE,
                                      "protobuf support is not available");
#else
    if (!registry) {
        return rac_proto_buffer_set_error(out_result, RAC_ERROR_NULL_POINTER,
                                          "LoRA registry handle is required");
    }

    runanywhere::v1::LoraAdapterDownloadCompletedRequest request;
    rac_result_t rc =
        parse_proto_message(request_proto_bytes, request_proto_size,
                            "LoraAdapterDownloadCompletedRequest", &request, out_result);
    if (rc != RAC_SUCCESS)
        return rc;
    if (request.adapter_id().empty()) {
        return rac_proto_buffer_set_error(
            out_result, RAC_ERROR_INVALID_ARGUMENT,
            "LoraAdapterDownloadCompletedRequest.adapter_id is required");
    }
    if (request.local_path().empty()) {
        return rac_proto_buffer_set_error(
            out_result, RAC_ERROR_INVALID_ARGUMENT,
            "LoraAdapterDownloadCompletedRequest.local_path is required");
    }

    runanywhere::v1::LoraAdapterDownloadCompletedResult result;
    {
        std::lock_guard<std::mutex> lock(registry->mutex);
        auto it = registry->entries.find(request.adapter_id());
        if (it == registry->entries.end()) {
            result.set_success(false);
            result.set_persisted(false);
            result.set_error_message("LoRA catalog entry not found");
            return copy_proto(result, out_result);
        }

        runanywhere::v1::LoraAdapterCatalogEntry entry =
            snapshot_from_struct_locked(registry, request.adapter_id(), it->second);
        entry.set_local_path(request.local_path());
        entry.set_is_downloaded(true);
        entry.set_downloaded_at_unix_ms(request.has_completed_at_unix_ms()
                                            ? request.completed_at_unix_ms()
                                            : current_time_ms());
        entry.set_is_imported(request.imported());
        entry.set_status_message(
            request.status_message().empty()
                ? (request.imported() ? "import completed" : "download completed")
                : request.status_message());
        if (request.has_size_bytes() && request.size_bytes() > 0) {
            entry.set_size_bytes(request.size_bytes());
            it->second->file_size = request.size_bytes();
        }
        if (request.has_checksum_sha256()) {
            entry.set_checksum_sha256(request.checksum_sha256());
        }

        rc = store_catalog_snapshot_locked(registry, entry);
        if (rc != RAC_SUCCESS) {
            return rac_proto_buffer_set_error(out_result, rc, rac_error_message(rc));
        }
        result.set_success(true);
        result.set_persisted(true);
        *result.mutable_entry() = entry;
    }
    return copy_proto(result, out_result);
#endif
}
