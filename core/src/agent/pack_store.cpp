// SPDX-License-Identifier: Apache-2.0

#include "pack_store.h"

#include "workflow_store.h"

#include <vector>

#include "rac/core/rac_logger.h"
#include "rac/infrastructure/model_management/rac_model_paths.h"

namespace rac::agent {
namespace {

constexpr const char* kLogCategory = "AgentWorkflow";
constexpr const char* kPackFile = "pack.json";

}  // namespace

std::string packs_directory() {
    char base[1024] = {0};
    if (rac_model_paths_get_base_directory(base, sizeof(base)) != RAC_SUCCESS)
        return {};
    return join(base, "NodePacks");
}

std::string pack_directory(const std::string& pack_id) {
    const std::string root = packs_directory();
    if (root.empty())
        return {};
    return join(root, pack_id);
}

rac_result_t store_save_pack(const runanywhere::v1::NodePack& pack) {
    if (!id_is_safe(pack.id())) {
        rac_error_set_details("pack id must be 1-128 chars of [A-Za-z0-9_-]");
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    const std::string directory = pack_directory(pack.id());
    if (directory.empty()) {
        rac_error_set_details("model paths base directory is not configured");
        return RAC_ERROR_NOT_INITIALIZED;
    }

    return write_message_json(join(directory, kPackFile), pack);
}

rac_result_t store_load_pack(const std::string& pack_id, runanywhere::v1::NodePack* out_pack) {
    if (!id_is_safe(pack_id)) {
        rac_error_set_details("pack id must be 1-128 chars of [A-Za-z0-9_-]");
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    const std::string directory = pack_directory(pack_id);
    if (directory.empty()) {
        rac_error_set_details("model paths base directory is not configured");
        return RAC_ERROR_NOT_INITIALIZED;
    }

    const std::string path = join(directory, kPackFile);
    if (!adapter_file_exists(path))
        return RAC_ERROR_NOT_FOUND;
    return read_message_json(path, out_pack);
}

rac_result_t store_list_packs(runanywhere::v1::NodePackList* out_list) {
    out_list->Clear();

    const std::string root = packs_directory();
    if (root.empty()) {
        rac_error_set_details("model paths base directory is not configured");
        return RAC_ERROR_NOT_INITIALIZED;
    }

    std::vector<std::string> ids;
    const rac_result_t result = adapter_list_directory(root, &ids, /*directories_only=*/true);
    if (result != RAC_SUCCESS)
        return result;

    for (const std::string& id : ids) {
        runanywhere::v1::NodePack pack;
        // One unreadable pack must not make the whole list unopenable, so a
        // failed load drops that entry and the listing continues.
        if (store_load_pack(id, &pack) != RAC_SUCCESS) {
            RAC_LOG_WARNING(kLogCategory, "skipping unreadable pack '%s'", id.c_str());
            continue;
        }
        *out_list->add_packs() = std::move(pack);
    }
    return RAC_SUCCESS;
}

rac_result_t store_delete_pack(const std::string& pack_id) {
    if (!id_is_safe(pack_id)) {
        rac_error_set_details("pack id must be 1-128 chars of [A-Za-z0-9_-]");
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    const std::string directory = pack_directory(pack_id);
    if (directory.empty()) {
        rac_error_set_details("model paths base directory is not configured");
        return RAC_ERROR_NOT_INITIALIZED;
    }

    const std::string path = join(directory, kPackFile);
    if (!adapter_file_exists(path))
        return RAC_SUCCESS;
    return adapter_delete_file(path);
}

}  // namespace rac::agent
