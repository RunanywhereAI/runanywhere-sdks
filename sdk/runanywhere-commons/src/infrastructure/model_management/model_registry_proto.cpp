/**
 * @file model_registry_proto.cpp
 * @brief Model registry — proto-byte + proto_buffer C ABI surface.
 *
 * SRP split of model_registry.cpp (pure code-motion). Owns the proto-byte and
 * proto_buffer registry entry points plus the query/sort/collect helpers they
 * use (see model_registry_internal.h). No behaviour change.
 */

#include "model_registry_internal.h"

#include <algorithm>
#include <cctype>
#include <cstdint>
#include <ranges>
#include <string>
#include <vector>

#include "rac/core/rac_error.h"
#include "rac/core/rac_logger.h"
#include "rac/foundation/rac_proto_buffer.h"
#include "rac/infrastructure/model_management/rac_model_registry.h"
#include "rac/infrastructure/model_management/rac_platform_capabilities.h"

using namespace rac::infra::model_registry::detail;  // NOLINT(build/namespaces)

#ifdef RAC_HAVE_PROTOBUF

// -----------------------------------------------------------------------------
// Query / sort helpers
// -----------------------------------------------------------------------------

namespace {

// Platform capability boundary: models whose inference framework can never
// run on this platform (e.g. Apple-only MLX on Android, Android-only QHexRT
// on iOS/Web) are hidden from every list/query surface. Registration,
// get-by-id, and download paths are intentionally NOT filtered.
bool model_visible_on_platform(const ModelInfo& model) {
    return rac_framework_supported_on_platform(static_cast<int32_t>(model.framework())) == RAC_TRUE;
}

std::string lowercase_copy(const std::string& input) {
    std::string out;
    out.reserve(input.size());
    for (unsigned char ch : input) {
        out.push_back(static_cast<char>(std::tolower(ch)));
    }
    return out;
}

bool contains_text_case_insensitive(const std::string& value, const std::string& needle_lower) {
    return lowercase_copy(value).find(needle_lower) != std::string::npos;
}

bool model_matches_search_text(const ModelInfo& model, const std::string& needle_lower) {
    if (needle_lower.empty()) {
        return true;
    }

    if (contains_text_case_insensitive(model.id(), needle_lower) ||
        contains_text_case_insensitive(model.name(), needle_lower) ||
        contains_text_case_insensitive(model.description(), needle_lower) ||
        contains_text_case_insensitive(model.download_url(), needle_lower) ||
        contains_text_case_insensitive(model.local_path(), needle_lower) ||
        contains_text_case_insensitive(model.checksum_sha256(), needle_lower) ||
        contains_text_case_insensitive(model.status_message(), needle_lower)) {
        return true;
    }

    if (model.has_metadata()) {
        const auto& metadata = model.metadata();
        if (contains_text_case_insensitive(metadata.description(), needle_lower) ||
            contains_text_case_insensitive(metadata.author(), needle_lower) ||
            contains_text_case_insensitive(metadata.license(), needle_lower) ||
            contains_text_case_insensitive(metadata.version(), needle_lower)) {
            return true;
        }
        for (const auto& tag : metadata.tags()) {
            if (contains_text_case_insensitive(tag, needle_lower)) {
                return true;
            }
        }
    }

    if (model.has_expected_files()) {
        const auto& expected = model.expected_files();
        if (contains_text_case_insensitive(expected.root_directory(), needle_lower) ||
            contains_text_case_insensitive(expected.description(), needle_lower)) {
            return true;
        }
        for (const auto& pattern : expected.required_patterns()) {
            if (contains_text_case_insensitive(pattern, needle_lower)) {
                return true;
            }
        }
        for (const auto& pattern : expected.optional_patterns()) {
            if (contains_text_case_insensitive(pattern, needle_lower)) {
                return true;
            }
        }
        for (const auto& file : expected.files()) {
            if (contains_text_case_insensitive(file.url(), needle_lower) ||
                contains_text_case_insensitive(file.filename(), needle_lower) ||
                contains_text_case_insensitive(file.relative_path(), needle_lower) ||
                contains_text_case_insensitive(file.destination_path(), needle_lower) ||
                contains_text_case_insensitive(file.local_path(), needle_lower) ||
                contains_text_case_insensitive(file.checksum_sha256(), needle_lower)) {
                return true;
            }
        }
    }

    return false;
}

int compare_strings(const std::string& lhs, const std::string& rhs) {
    if (lhs < rhs) {
        return -1;
    }
    if (rhs < lhs) {
        return 1;
    }
    return 0;
}

template <typename T>
int compare_values(T lhs, T rhs) {
    if (lhs < rhs) {
        return -1;
    }
    if (rhs < lhs) {
        return 1;
    }
    return 0;
}

int compare_models_by_sort_field(const ModelInfo& lhs, const ModelInfo& rhs,
                                 ModelQuerySortField sort_field) {
    switch (sort_field) {
        case runanywhere::v1::MODEL_QUERY_SORT_FIELD_NAME:
            return compare_strings(lhs.name(), rhs.name());
        case runanywhere::v1::MODEL_QUERY_SORT_FIELD_CREATED_AT_UNIX_MS:
            return compare_values(lhs.created_at_unix_ms(), rhs.created_at_unix_ms());
        case runanywhere::v1::MODEL_QUERY_SORT_FIELD_UPDATED_AT_UNIX_MS:
            return compare_values(lhs.updated_at_unix_ms(), rhs.updated_at_unix_ms());
        case runanywhere::v1::MODEL_QUERY_SORT_FIELD_DOWNLOAD_SIZE_BYTES:
            return compare_values(lhs.download_size_bytes(), rhs.download_size_bytes());
        case runanywhere::v1::MODEL_QUERY_SORT_FIELD_LAST_USED_AT_UNIX_MS:
            return compare_values(lhs.last_used_at_unix_ms(), rhs.last_used_at_unix_ms());
        case runanywhere::v1::MODEL_QUERY_SORT_FIELD_USAGE_COUNT:
            return compare_values(lhs.usage_count(), rhs.usage_count());
        case runanywhere::v1::MODEL_QUERY_SORT_FIELD_UNSPECIFIED:
        default:
            return 0;
    }
}

bool query_has_supported_sort_field(const ModelQuery& query) {
    return query.has_sort_field() &&
           query.sort_field() != runanywhere::v1::MODEL_QUERY_SORT_FIELD_UNSPECIFIED;
}

}  // namespace

namespace rac::infra::model_registry::detail {

bool model_is_downloaded_proto(const ModelInfo& model) {
    return model_is_downloaded_from_fields(model);
}

bool model_is_available_proto(const ModelInfo& model) {
    if (model.has_is_available()) {
        return model.is_available();
    }
    return model_is_downloaded_proto(model);
}

bool model_matches_query(const ModelInfo& model, const ModelQuery& query) {
    if (query.has_framework() && model.framework() != query.framework()) {
        return false;
    }
    if (query.has_category() && model.category() != query.category()) {
        return false;
    }
    if (query.has_format() && model.format() != query.format()) {
        return false;
    }
    if (query.has_source() && model.source() != query.source()) {
        return false;
    }
    if (query.has_registry_status() &&
        effective_registry_status(model) != query.registry_status()) {
        return false;
    }
    if (query.has_downloaded_only() && query.downloaded_only() &&
        !model_is_downloaded_proto(model)) {
        return false;
    }
    if (query.has_available_only() && query.available_only() && !model_is_available_proto(model)) {
        return false;
    }
    if (query.has_max_size_bytes() && query.max_size_bytes() >= 0 &&
        model.download_size_bytes() > query.max_size_bytes()) {
        return false;
    }

    const std::string needle_lower = lowercase_copy(query.search_query());
    return model_matches_search_text(model, needle_lower);
}

void sort_query_results(const ModelQuery& query, std::vector<ModelInfo>* models) {
    if (!models || !query_has_supported_sort_field(query)) {
        return;
    }

    const ModelQuerySortField sort_field = query.sort_field();
    const bool descending =
        query.has_sort_order() &&
        query.sort_order() == runanywhere::v1::MODEL_QUERY_SORT_ORDER_DESCENDING;

    std::ranges::sort(*models,
                      [sort_field, descending](const ModelInfo& lhs, const ModelInfo& rhs) {
                          int result = compare_models_by_sort_field(lhs, rhs, sort_field);
                          if (result == 0) {
                              return lhs.id() < rhs.id();
                          }
                          return descending ? result > 0 : result < 0;
                      });
}

void append_query_results_locked(rac_model_registry_handle_t handle, const ModelQuery& query,
                                 ModelInfoList* out) {
    if (!out) {
        return;
    }

    std::vector<ModelInfo> matches;
    for (const auto& pair : handle->models) {
        ModelInfo snapshot = model_snapshot_locked(handle, pair.first, pair.second);
        normalize_model_registry_state(&snapshot);
        if (model_visible_on_platform(snapshot) && model_matches_query(snapshot, query)) {
            matches.push_back(std::move(snapshot));
        }
    }
    sort_query_results(query, &matches);
    for (ModelInfo& model : matches) {
        out->add_models()->Swap(&model);
    }
}

std::vector<ModelInfo> collect_model_snapshots_locked(rac_model_registry_handle_t handle) {
    std::vector<ModelInfo> models;
    if (!handle) {
        return models;
    }

    models.reserve(handle->models.size());
    for (const auto& pair : handle->models) {
        ModelInfo snapshot = model_snapshot_locked(handle, pair.first, pair.second);
        normalize_model_registry_state(&snapshot);
        if (!model_visible_on_platform(snapshot)) {
            continue;
        }
        models.push_back(std::move(snapshot));
    }
    return models;
}

std::vector<ModelInfo> query_model_snapshots_locked(rac_model_registry_handle_t handle,
                                                    const ModelQuery& query) {
    std::vector<ModelInfo> matches;
    if (!handle) {
        return matches;
    }

    for (ModelInfo& model : collect_model_snapshots_locked(handle)) {
        if (model_matches_query(model, query)) {
            matches.push_back(std::move(model));
        }
    }
    sort_query_results(query, &matches);
    return matches;
}

void move_models_to_list(std::vector<ModelInfo>* models, ModelInfoList* out) {
    if (!models || !out) {
        return;
    }
    for (ModelInfo& model : *models) {
        out->add_models()->Swap(&model);
    }
}

ModelCounts count_models(const std::vector<ModelInfo>& models) {
    ModelCounts counts;
    counts.total = static_cast<int32_t>(models.size());
    for (const ModelInfo& model : models) {
        if (model_is_downloaded_proto(model)) {
            ++counts.downloaded;
        }
        if (model_is_available_proto(model)) {
            ++counts.available;
        }
        if (effective_registry_status(model) == runanywhere::v1::MODEL_REGISTRY_STATUS_ERROR) {
            ++counts.errors;
        }
    }
    return counts;
}

}  // namespace rac::infra::model_registry::detail

#endif  // RAC_HAVE_PROTOBUF

// =============================================================================
// PUBLIC API - PROTO-BYTE MODEL INFO
// =============================================================================

rac_result_t rac_model_registry_register_proto(rac_model_registry_handle_t handle,
                                               const uint8_t* proto_bytes, size_t proto_size) {
#ifndef RAC_HAVE_PROTOBUF
    (void)handle;
    (void)proto_bytes;
    (void)proto_size;
    return RAC_ERROR_FEATURE_NOT_AVAILABLE;
#else
    if (!handle) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    ModelInfo proto_model;
    rac_result_t parse_rc = parse_model_info_bytes(proto_bytes, proto_size, &proto_model);
    if (parse_rc != RAC_SUCCESS) {
        return parse_rc;
    }

    // Registration is allowed regardless of platform capability, but the
    // model will be hidden from list/query results (see
    // rac_platform_capabilities.h).
    if (!model_visible_on_platform(proto_model)) {
        RAC_LOG_DEBUG("ModelRegistry",
                      "Model '%s' uses framework %d which is unsupported on this platform; "
                      "it will be hidden from list results",
                      proto_model.id().c_str(), static_cast<int>(proto_model.framework()));
    }

    // Merge-not-replace: when re-registering an existing model_id (catalog
    // re-seed on app launch), preserve runtime fields the caller doesn't set
    // — local_path, is_downloaded, checksum_sha256, expected_files,
    // multi_file.files[*].local_path, etc. Without this, a registerModel()
    // call that only carries factory defaults clobbers download progress and
    // forces the user to re-download on every launch. Same merge contract as
    // rac_model_registry_update_proto (see preserve_absent_proto_fields).
    {
        std::lock_guard<std::mutex> lock(handle->mutex);
        auto existing_it = handle->models.find(proto_model.id());
        if (existing_it != handle->models.end()) {
            ModelInfo existing =
                model_snapshot_locked(handle, proto_model.id(), existing_it->second);
            // register_proto is an authoritative replace: an explicit empty
            // local_path is a deliberate reset that must win (override
            // escape hatch), so do NOT preserve an empty path.
            preserve_absent_proto_fields(existing, &proto_model,
                                         /*preserve_empty_local_path=*/false);
        }
    }

    normalize_model_registry_state(&proto_model);

    rac_model_info_t* model = model_info_from_proto(proto_model);
    if (!model) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }

    const std::string model_id = proto_model.id();
    // The proto register/update paths carry a caller-authored ModelInfo, so an
    // empty local_path here is an explicit reset that must win. The merge-on-
    // re-seed behaviour lives upstream (rac_register_model_from_url_proto carries
    // the existing runtime fields forward before calling this), so the legacy
    // C-struct "empty means keep the old path" heuristic must NOT fire here.
    rac_result_t save_rc = save_model_info_impl(handle, model,
                                                /*preserve_empty_local_path=*/false);
    rac_model_info_free(model);
    if (save_rc != RAC_SUCCESS) {
        return save_rc;
    }

    std::lock_guard<std::mutex> lock(handle->mutex);
    return store_parsed_proto_snapshot_locked(handle, model_id, proto_model);
#endif
}

rac_result_t rac_model_registry_update_proto(rac_model_registry_handle_t handle,
                                             const uint8_t* proto_bytes, size_t proto_size) {
#ifndef RAC_HAVE_PROTOBUF
    (void)handle;
    (void)proto_bytes;
    (void)proto_size;
    return RAC_ERROR_FEATURE_NOT_AVAILABLE;
#else
    if (!handle) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    ModelInfo proto_model;
    rac_result_t parse_rc = parse_model_info_bytes(proto_bytes, proto_size, &proto_model);
    if (parse_rc != RAC_SUCCESS) {
        return parse_rc;
    }

    {
        std::lock_guard<std::mutex> lock(handle->mutex);
        auto model_it = handle->models.find(proto_model.id());
        if (model_it == handle->models.end()) {
            return RAC_ERROR_NOT_FOUND;
        }
        ModelInfo existing = model_snapshot_locked(handle, proto_model.id(), model_it->second);
        // update_proto is a partial merge: a field the caller left unset (or an
        // empty local_path, which is wire-indistinguishable from unset for this
        // presence-less proto3 string) must preserve the existing value.
        preserve_absent_proto_fields(existing, &proto_model,
                                     /*preserve_empty_local_path=*/true);
    }
    normalize_model_registry_state(&proto_model);

    rac_model_info_t* model = model_info_from_proto(proto_model);
    if (!model) {
        return RAC_ERROR_OUT_OF_MEMORY;
    }

    const std::string model_id = proto_model.id();
    // The proto register/update paths carry a caller-authored ModelInfo, so an
    // empty local_path here is an explicit reset that must win. The merge-on-
    // re-seed behaviour lives upstream (rac_register_model_from_url_proto carries
    // the existing runtime fields forward before calling this), so the legacy
    // C-struct "empty means keep the old path" heuristic must NOT fire here.
    rac_result_t save_rc = save_model_info_impl(handle, model,
                                                /*preserve_empty_local_path=*/false);
    rac_model_info_free(model);
    if (save_rc != RAC_SUCCESS) {
        return save_rc;
    }

    std::lock_guard<std::mutex> lock(handle->mutex);
    return store_parsed_proto_snapshot_locked(handle, model_id, proto_model);
#endif
}

rac_result_t rac_model_registry_get_proto(rac_model_registry_handle_t handle, const char* model_id,
                                          uint8_t** proto_bytes_out, size_t* proto_size_out) {
#ifndef RAC_HAVE_PROTOBUF
    (void)handle;
    (void)model_id;
    if (proto_bytes_out)
        *proto_bytes_out = nullptr;
    if (proto_size_out)
        *proto_size_out = 0;
    return RAC_ERROR_FEATURE_NOT_AVAILABLE;
#else
    if (!handle || !model_id || !proto_bytes_out || !proto_size_out) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    *proto_bytes_out = nullptr;
    *proto_size_out = 0;

    for (int attempt = 0; attempt < 2; ++attempt) {
        {
            std::lock_guard<std::mutex> lock(handle->mutex);
            auto it = handle->models.find(model_id);
            if (it != handle->models.end()) {
                return model_to_proto_bytes_locked(handle, model_id, it->second, proto_bytes_out,
                                                   proto_size_out);
            }
        }
        // Lookup miss: an ad-hoc pull from a previous run may exist on disk
        // with a manifest sidecar but no re-seeded entry. Restore once, retry.
        if (attempt > 0 || !try_restore_model_manifest_by_id(handle, model_id)) {
            break;
        }
    }
    return RAC_ERROR_NOT_FOUND;
#endif
}

rac_result_t rac_model_registry_list_proto(rac_model_registry_handle_t handle,
                                           uint8_t** proto_bytes_out, size_t* proto_size_out) {
#ifndef RAC_HAVE_PROTOBUF
    (void)handle;
    if (proto_bytes_out)
        *proto_bytes_out = nullptr;
    if (proto_size_out)
        *proto_size_out = 0;
    return RAC_ERROR_FEATURE_NOT_AVAILABLE;
#else
    if (!handle || !proto_bytes_out || !proto_size_out) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    *proto_bytes_out = nullptr;
    *proto_size_out = 0;

    ModelInfoList list;
    {
        std::lock_guard<std::mutex> lock(handle->mutex);
        for (const auto& pair : handle->models) {
            ModelInfo snapshot = model_snapshot_locked(handle, pair.first, pair.second);
            if (!model_visible_on_platform(snapshot)) {
                continue;
            }
            list.add_models()->Swap(&snapshot);
        }
    }

    return serialize_proto_to_owned_buffer(list, proto_bytes_out, proto_size_out);
#endif
}

rac_result_t rac_model_registry_query_proto(rac_model_registry_handle_t handle,
                                            const uint8_t* query_proto_bytes,
                                            size_t query_proto_size, uint8_t** proto_bytes_out,
                                            size_t* proto_size_out) {
#ifndef RAC_HAVE_PROTOBUF
    (void)handle;
    (void)query_proto_bytes;
    (void)query_proto_size;
    if (proto_bytes_out)
        *proto_bytes_out = nullptr;
    if (proto_size_out)
        *proto_size_out = 0;
    return RAC_ERROR_FEATURE_NOT_AVAILABLE;
#else
    if (!handle || !proto_bytes_out || !proto_size_out) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    *proto_bytes_out = nullptr;
    *proto_size_out = 0;

    ModelQuery query;
    rac_result_t parse_rc = parse_model_query_bytes(query_proto_bytes, query_proto_size, &query);
    if (parse_rc != RAC_SUCCESS) {
        return parse_rc;
    }

    ModelInfoList list;
    {
        std::lock_guard<std::mutex> lock(handle->mutex);
        append_query_results_locked(handle, query, &list);
    }

    return serialize_proto_to_owned_buffer(list, proto_bytes_out, proto_size_out);
#endif
}

rac_result_t rac_model_registry_list_downloaded_proto(rac_model_registry_handle_t handle,
                                                      uint8_t** proto_bytes_out,
                                                      size_t* proto_size_out) {
#ifndef RAC_HAVE_PROTOBUF
    (void)handle;
    if (proto_bytes_out)
        *proto_bytes_out = nullptr;
    if (proto_size_out)
        *proto_size_out = 0;
    return RAC_ERROR_FEATURE_NOT_AVAILABLE;
#else
    if (!handle || !proto_bytes_out || !proto_size_out) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    *proto_bytes_out = nullptr;
    *proto_size_out = 0;

    ModelQuery query;
    query.set_downloaded_only(true);

    ModelInfoList list;
    {
        std::lock_guard<std::mutex> lock(handle->mutex);
        append_query_results_locked(handle, query, &list);
    }

    return serialize_proto_to_owned_buffer(list, proto_bytes_out, proto_size_out);
#endif
}

rac_result_t rac_model_registry_remove_proto(rac_model_registry_handle_t handle,
                                             const char* model_id) {
    return rac_model_registry_remove(handle, model_id);
}

void rac_model_registry_proto_free(uint8_t* proto_bytes) {
    rac_proto_buffer_free_data(proto_bytes);
}

rac_result_t rac_model_registry_register_proto_buffer(rac_model_registry_handle_t handle,
                                                      const uint8_t* proto_bytes, size_t proto_size,
                                                      rac_proto_buffer_t* out_model) {
    if (!out_model) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
#ifndef RAC_HAVE_PROTOBUF
    (void)handle;
    (void)proto_bytes;
    (void)proto_size;
    return rac_proto_buffer_set_error(out_model, RAC_ERROR_FEATURE_NOT_AVAILABLE,
                                      "protobuf runtime is not available");
#else
    if (!handle) {
        return proto_buffer_error(out_model, RAC_ERROR_INVALID_ARGUMENT,
                                  "registry handle is required");
    }

    ModelInfo parsed;
    rac_result_t parse_rc = parse_model_info_bytes(proto_bytes, proto_size, &parsed);
    if (parse_rc != RAC_SUCCESS) {
        return proto_buffer_error(out_model, parse_rc,
                                  parse_rc == RAC_ERROR_INVALID_FORMAT
                                      ? "failed to parse ModelInfo"
                                      : "ModelInfo.id is required");
    }

    rac_result_t rc = rac_model_registry_register_proto(handle, proto_bytes, proto_size);
    if (rc != RAC_SUCCESS) {
        return proto_buffer_error(out_model, rc, rac_error_message(rc));
    }

    ModelInfo saved;
    if (!get_model_snapshot_by_id(handle, parsed.id(), &saved)) {
        return proto_buffer_error(out_model, RAC_ERROR_NOT_FOUND, "registered model was not found");
    }
    return serialize_proto_to_buffer(saved, out_model);
#endif
}

rac_result_t rac_model_registry_update_proto_buffer(rac_model_registry_handle_t handle,
                                                    const uint8_t* proto_bytes, size_t proto_size,
                                                    rac_proto_buffer_t* out_model) {
    if (!out_model) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
#ifndef RAC_HAVE_PROTOBUF
    (void)handle;
    (void)proto_bytes;
    (void)proto_size;
    return rac_proto_buffer_set_error(out_model, RAC_ERROR_FEATURE_NOT_AVAILABLE,
                                      "protobuf runtime is not available");
#else
    if (!handle) {
        return proto_buffer_error(out_model, RAC_ERROR_INVALID_ARGUMENT,
                                  "registry handle is required");
    }

    ModelInfo parsed;
    rac_result_t parse_rc = parse_model_info_bytes(proto_bytes, proto_size, &parsed);
    if (parse_rc != RAC_SUCCESS) {
        return proto_buffer_error(out_model, parse_rc,
                                  parse_rc == RAC_ERROR_INVALID_FORMAT
                                      ? "failed to parse ModelInfo"
                                      : "ModelInfo.id is required");
    }

    rac_result_t rc = rac_model_registry_update_proto(handle, proto_bytes, proto_size);
    if (rc != RAC_SUCCESS) {
        return proto_buffer_error(out_model, rc, rac_error_message(rc));
    }

    ModelInfo saved;
    if (!get_model_snapshot_by_id(handle, parsed.id(), &saved)) {
        return proto_buffer_error(out_model, RAC_ERROR_NOT_FOUND, "updated model was not found");
    }
    return serialize_proto_to_buffer(saved, out_model);
#endif
}

rac_result_t rac_model_registry_get_proto_buffer(rac_model_registry_handle_t handle,
                                                 const char* model_id,
                                                 rac_proto_buffer_t* out_model) {
    if (!out_model) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
#ifndef RAC_HAVE_PROTOBUF
    (void)handle;
    (void)model_id;
    return rac_proto_buffer_set_error(out_model, RAC_ERROR_FEATURE_NOT_AVAILABLE,
                                      "protobuf runtime is not available");
#else
    if (!handle || !model_id) {
        return proto_buffer_error(out_model, RAC_ERROR_INVALID_ARGUMENT,
                                  "registry handle and model_id are required");
    }

    ModelInfo model;
    if (!get_model_snapshot_by_id(handle, model_id, &model)) {
        return proto_buffer_error(out_model, RAC_ERROR_NOT_FOUND, "model not found");
    }
    return serialize_proto_to_buffer(model, out_model);
#endif
}

rac_result_t rac_model_registry_list_proto_buffer(rac_model_registry_handle_t handle,
                                                  rac_proto_buffer_t* out_models) {
    if (!out_models) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
#ifndef RAC_HAVE_PROTOBUF
    (void)handle;
    return rac_proto_buffer_set_error(out_models, RAC_ERROR_FEATURE_NOT_AVAILABLE,
                                      "protobuf runtime is not available");
#else
    if (!handle) {
        return proto_buffer_error(out_models, RAC_ERROR_INVALID_ARGUMENT,
                                  "registry handle is required");
    }

    ModelInfoList list;
    {
        std::lock_guard<std::mutex> lock(handle->mutex);
        std::vector<ModelInfo> models = collect_model_snapshots_locked(handle);
        move_models_to_list(&models, &list);
    }
    return serialize_proto_to_buffer(list, out_models);
#endif
}

rac_result_t rac_model_registry_query_proto_buffer(rac_model_registry_handle_t handle,
                                                   const uint8_t* query_proto_bytes,
                                                   size_t query_proto_size,
                                                   rac_proto_buffer_t* out_models) {
    if (!out_models) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
#ifndef RAC_HAVE_PROTOBUF
    (void)handle;
    (void)query_proto_bytes;
    (void)query_proto_size;
    return rac_proto_buffer_set_error(out_models, RAC_ERROR_FEATURE_NOT_AVAILABLE,
                                      "protobuf runtime is not available");
#else
    if (!handle) {
        return proto_buffer_error(out_models, RAC_ERROR_INVALID_ARGUMENT,
                                  "registry handle is required");
    }

    ModelQuery query;
    rac_result_t parse_rc = parse_model_query_bytes(query_proto_bytes, query_proto_size, &query);
    if (parse_rc != RAC_SUCCESS) {
        return proto_buffer_error(out_models, parse_rc,
                                  parse_rc == RAC_ERROR_INVALID_FORMAT
                                      ? "failed to parse ModelQuery"
                                      : "invalid ModelQuery bytes");
    }

    ModelInfoList list;
    {
        std::lock_guard<std::mutex> lock(handle->mutex);
        std::vector<ModelInfo> models = query_model_snapshots_locked(handle, query);
        move_models_to_list(&models, &list);
    }
    return serialize_proto_to_buffer(list, out_models);
#endif
}

rac_result_t rac_model_registry_list_downloaded_proto_buffer(rac_model_registry_handle_t handle,
                                                             rac_proto_buffer_t* out_models) {
    if (!out_models) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
#ifndef RAC_HAVE_PROTOBUF
    (void)handle;
    return rac_proto_buffer_set_error(out_models, RAC_ERROR_FEATURE_NOT_AVAILABLE,
                                      "protobuf runtime is not available");
#else
    ModelQuery query;
    query.set_downloaded_only(true);
    std::string bytes;
    if (!query.SerializeToString(&bytes)) {
        return proto_buffer_error(out_models, RAC_ERROR_ENCODING_ERROR,
                                  "failed to serialize downloaded-only query");
    }
    return rac_model_registry_query_proto_buffer(
        handle, reinterpret_cast<const uint8_t*>(bytes.data()), bytes.size(), out_models);
#endif
}

rac_result_t rac_model_registry_remove_proto_buffer(rac_model_registry_handle_t handle,
                                                    const char* model_id,
                                                    rac_proto_buffer_t* out_result) {
    if (!out_result) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
#ifndef RAC_HAVE_PROTOBUF
    (void)handle;
    (void)model_id;
    return rac_proto_buffer_set_error(out_result, RAC_ERROR_FEATURE_NOT_AVAILABLE,
                                      "protobuf runtime is not available");
#else
    if (!handle || !model_id || model_id[0] == '\0') {
        return proto_buffer_error(out_result, RAC_ERROR_INVALID_ARGUMENT,
                                  "registry handle and model_id are required");
    }

    ModelDeleteResult result;
    result.set_model_id(model_id);
    rac_result_t rc = rac_model_registry_remove(handle, model_id);
    if (rc == RAC_SUCCESS) {
        result.set_success(true);
        result.set_registry_updated(true);
        result.set_files_deleted(false);
    } else {
        result.set_success(false);
        result.set_registry_updated(false);
        result.set_files_deleted(false);
        result.set_error_message(rac_error_message(rc));
    }
    return serialize_proto_to_buffer(result, out_result);
#endif
}

rac_result_t rac_model_registry_get_model_proto(rac_model_registry_handle_t handle,
                                                const uint8_t* request_proto_bytes,
                                                size_t request_proto_size,
                                                rac_proto_buffer_t* out_result) {
    if (!out_result) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
#ifndef RAC_HAVE_PROTOBUF
    (void)handle;
    (void)request_proto_bytes;
    (void)request_proto_size;
    return rac_proto_buffer_set_error(out_result, RAC_ERROR_FEATURE_NOT_AVAILABLE,
                                      "protobuf runtime is not available");
#else
    if (!handle) {
        return proto_buffer_error(out_result, RAC_ERROR_INVALID_ARGUMENT,
                                  "registry handle is required");
    }

    ModelGetRequest request;
    rac_result_t parse_rc = parse_proto_message_bytes(request_proto_bytes, request_proto_size,
                                                      &request, "ModelGetRequest", out_result);
    if (parse_rc != RAC_SUCCESS) {
        return parse_rc;
    }
    if (request.model_id().empty()) {
        return proto_buffer_error(out_result, RAC_ERROR_INVALID_ARGUMENT,
                                  "ModelGetRequest.model_id is required");
    }

    ModelGetResult result;
    ModelInfo model;
    if (get_model_snapshot_by_id(handle, request.model_id(), &model)) {
        result.set_found(true);
        result.mutable_model()->CopyFrom(model);
    } else {
        result.set_found(false);
        result.set_error_message("model not found");
    }
    return serialize_proto_to_buffer(result, out_result);
#endif
}

rac_result_t rac_model_registry_list_models_proto(rac_model_registry_handle_t handle,
                                                  const uint8_t* request_proto_bytes,
                                                  size_t request_proto_size,
                                                  rac_proto_buffer_t* out_result) {
    if (!out_result) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
#ifndef RAC_HAVE_PROTOBUF
    (void)handle;
    (void)request_proto_bytes;
    (void)request_proto_size;
    return rac_proto_buffer_set_error(out_result, RAC_ERROR_FEATURE_NOT_AVAILABLE,
                                      "protobuf runtime is not available");
#else
    if (!handle) {
        return proto_buffer_error(out_result, RAC_ERROR_INVALID_ARGUMENT,
                                  "registry handle is required");
    }

    ModelListRequest request;
    rac_result_t parse_rc = parse_proto_message_bytes(request_proto_bytes, request_proto_size,
                                                      &request, "ModelListRequest", out_result);
    if (parse_rc != RAC_SUCCESS) {
        return parse_rc;
    }

    std::vector<ModelInfo> all_models;
    {
        std::lock_guard<std::mutex> lock(handle->mutex);
        all_models = collect_model_snapshots_locked(handle);
    }

    std::vector<ModelInfo> filtered;
    if (request.has_query()) {
        for (const ModelInfo& model : all_models) {
            if (model_matches_query(model, request.query())) {
                filtered.push_back(model);
            }
        }
        sort_query_results(request.query(), &filtered);
    } else {
        filtered = all_models;
    }

    const ModelCounts all_counts = count_models(all_models);
    const ModelCounts filtered_counts = count_models(filtered);

    ModelListResult result;
    result.set_success(true);
    move_models_to_list(&filtered, result.mutable_models());
    if (request.include_counts()) {
        result.set_total_count(all_counts.total);
        result.set_downloaded_count(filtered_counts.downloaded);
        result.set_available_count(filtered_counts.available);
        result.set_filtered_count(filtered_counts.total);
    }
    return serialize_proto_to_buffer(result, out_result);
#endif
}

rac_result_t rac_model_registry_import_proto(rac_model_registry_handle_t handle,
                                             const uint8_t* request_proto_bytes,
                                             size_t request_proto_size,
                                             rac_proto_buffer_t* out_result) {
    if (!out_result) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
#ifndef RAC_HAVE_PROTOBUF
    (void)handle;
    (void)request_proto_bytes;
    (void)request_proto_size;
    return rac_proto_buffer_set_error(out_result, RAC_ERROR_FEATURE_NOT_AVAILABLE,
                                      "protobuf runtime is not available");
#else
    if (!handle) {
        return proto_buffer_error(out_result, RAC_ERROR_INVALID_ARGUMENT,
                                  "registry handle is required");
    }

    ModelImportRequest request;
    rac_result_t parse_rc = parse_proto_message_bytes(request_proto_bytes, request_proto_size,
                                                      &request, "ModelImportRequest", out_result);
    if (parse_rc != RAC_SUCCESS) {
        return parse_rc;
    }

    ModelImportResult result;
    ModelInfo model;
    if (request.has_model()) {
        model.CopyFrom(request.model());
    }

    const std::string source_path = request.source_path();
    if (model.id().empty()) {
        const std::string base = strip_known_model_extension(basename_from_path(source_path));
        if (base.empty()) {
            result.set_success(false);
            result.set_error_message("ModelImportRequest.model.id or source_path is required");
            return serialize_proto_to_buffer(result, out_result);
        }
        model.set_id(base);
    }
    if (model.name().empty()) {
        model.set_name(model.id());
    }
    if (!source_path.empty()) {
        model.set_local_path(source_path);
        if (model.source() == runanywhere::v1::MODEL_SOURCE_UNSPECIFIED) {
            model.set_source(runanywhere::v1::MODEL_SOURCE_LOCAL);
        }
    }
    if (model.format() == runanywhere::v1::MODEL_FORMAT_UNSPECIFIED ||
        model.format() == runanywhere::v1::MODEL_FORMAT_UNKNOWN) {
        model.set_format(infer_format_from_path(source_path));
    }
    if (model.framework() == runanywhere::v1::INFERENCE_FRAMEWORK_UNSPECIFIED ||
        model.framework() == runanywhere::v1::INFERENCE_FRAMEWORK_UNKNOWN) {
        model.set_framework(infer_framework_from_format(model.format()));
    }
    if (request.files_size() > 0 && model.artifact_case() == ModelInfo::ARTIFACT_NOT_SET) {
        for (const ModelFileDescriptor& file : request.files()) {
            model.mutable_multi_file()->add_files()->CopyFrom(file);
        }
        model.set_artifact_type(runanywhere::v1::MODEL_ARTIFACT_TYPE_MULTI_FILE);
    }
    normalize_model_registry_state(&model);
    if (!source_path.empty()) {
        overwrite_download_state_from_local_path(&model);
    }

    ModelInfo existing;
    const bool exists = get_model_snapshot_by_id(handle, model.id(), &existing);
    if (exists && !request.overwrite_existing()) {
        result.set_success(false);
        result.mutable_model()->CopyFrom(existing);
        result.set_local_path(existing.local_path());
        result.set_error_message("model already exists");
        result.set_registered(false);
        return serialize_proto_to_buffer(result, out_result);
    }

    if (request.copy_into_managed_storage()) {
        result.add_warnings(
            "copy_into_managed_storage is platform-owned and was not executed by commons");
    }
    if (request.validate_before_register()) {
        result.add_warnings(
            "validate_before_register requires platform filesystem facts and was not executed");
    }

    std::string model_bytes;
    if (!model.SerializeToString(&model_bytes)) {
        return proto_buffer_error(out_result, RAC_ERROR_ENCODING_ERROR,
                                  "failed to serialize ModelImportRequest.model");
    }

    rac_result_t rc =
        exists
            ? rac_model_registry_update_proto(
                  handle, reinterpret_cast<const uint8_t*>(model_bytes.data()), model_bytes.size())
            : rac_model_registry_register_proto(
                  handle, reinterpret_cast<const uint8_t*>(model_bytes.data()), model_bytes.size());
    if (rc != RAC_SUCCESS) {
        return proto_buffer_error(out_result, rc, rac_error_message(rc));
    }

    ModelInfo saved;
    if (!get_model_snapshot_by_id(handle, model.id(), &saved)) {
        return proto_buffer_error(out_result, RAC_ERROR_NOT_FOUND, "imported model was not found");
    }

    result.set_success(true);
    result.mutable_model()->CopyFrom(saved);
    result.set_local_path(saved.local_path());
    result.set_imported_bytes(imported_size_for_request(request, saved));
    result.set_registered(true);
    result.set_copied_into_managed_storage(false);
    return serialize_proto_to_buffer(result, out_result);
#endif
}
