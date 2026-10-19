// SPDX-License-Identifier: Apache-2.0

#include <chrono>
#include "workflow_store.h"

#include <cstdlib>
#include <cstring>

#include "rac/core/rac_logger.h"
#include "rac/core/rac_platform_adapter.h"
#include "rac/infrastructure/model_management/rac_model_paths.h"

namespace rac::agent {
namespace {

constexpr const char* kLogCategory = "AgentWorkflow";
constexpr const char* kDocumentFile = "workflow.json";
constexpr const char* kRunsDirectory = "runs";

}  // namespace

bool id_is_safe(const std::string& id) {
    if (id.empty() || id.size() > 128)
        return false;
    if (id == "." || id == "..")
        return false;
    for (char c : id) {
        const bool ok = (c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
                        (c >= '0' && c <= '9') || c == '-' || c == '_';
        if (!ok)
            return false;
    }
    return true;
}

std::string join(const std::string& base, const std::string& leaf) {
    if (base.empty())
        return leaf;
    if (base.back() == '/')
        return base + leaf;
    return base + "/" + leaf;
}

std::string workflows_directory() {
    char base[1024] = {0};
    if (rac_model_paths_get_base_directory(base, sizeof(base)) != RAC_SUCCESS)
        return {};
    return join(base, "Workflows");
}

std::string workflow_directory(const std::string& workflow_id) {
    const std::string root = workflows_directory();
    if (root.empty())
        return {};
    return join(root, workflow_id);
}

rac_result_t adapter_write_file(const std::string& path, const std::string& bytes) {
    const rac_platform_adapter_t* adapter = rac_get_platform_adapter();
    if (adapter == nullptr || adapter->file_write == nullptr) {
        rac_error_set_details("platform adapter does not provide file_write");
        return RAC_ERROR_ADAPTER_NOT_SET;
    }
    return adapter->file_write(path.c_str(), bytes.data(), bytes.size(), adapter->user_data);
}

rac_result_t adapter_read_file(const std::string& path, std::string* out_bytes) {
    const rac_platform_adapter_t* adapter = rac_get_platform_adapter();
    if (adapter == nullptr || adapter->file_read == nullptr) {
        rac_error_set_details("platform adapter does not provide file_read");
        return RAC_ERROR_ADAPTER_NOT_SET;
    }

    void* data = nullptr;
    size_t size = 0;
    const rac_result_t result = adapter->file_read(path.c_str(), &data, &size, adapter->user_data);
    if (result != RAC_SUCCESS)
        return result;

    if (data != nullptr) {
        out_bytes->assign(static_cast<const char*>(data), size);
        // The adapter contract hands ownership of the buffer to the caller.
        std::free(data);
    } else {
        out_bytes->clear();
    }
    return RAC_SUCCESS;
}

bool adapter_file_exists(const std::string& path) {
    const rac_platform_adapter_t* adapter = rac_get_platform_adapter();
    if (adapter == nullptr || adapter->file_exists == nullptr)
        return false;
    return adapter->file_exists(path.c_str(), adapter->user_data) == RAC_TRUE;
}

rac_result_t adapter_delete_file(const std::string& path) {
    const rac_platform_adapter_t* adapter = rac_get_platform_adapter();
    if (adapter == nullptr || adapter->file_delete == nullptr) {
        rac_error_set_details("platform adapter does not provide file_delete");
        return RAC_ERROR_ADAPTER_NOT_SET;
    }
    return adapter->file_delete(path.c_str(), adapter->user_data);
}

rac_result_t adapter_list_directory(const std::string& path, std::vector<std::string>* out_names,
                                    bool directories_only) {
    out_names->clear();

    const rac_platform_adapter_t* adapter = rac_get_platform_adapter();
    if (adapter == nullptr || adapter->file_list_directory == nullptr) {
        rac_error_set_details("platform adapter does not provide file_list_directory");
        return RAC_ERROR_ADAPTER_NOT_SET;
    }

    size_t count = 0;
    rac_result_t result =
        adapter->file_list_directory(path.c_str(), nullptr, &count, adapter->user_data);
    if (result == RAC_ERROR_FILE_NOT_FOUND)
        return RAC_SUCCESS;
    if (result != RAC_SUCCESS)
        return result;
    if (count == 0)
        return RAC_SUCCESS;

    std::vector<rac_directory_entry_t> entries(count);
    result = adapter->file_list_directory(path.c_str(), entries.data(), &count, adapter->user_data);
    if (result != RAC_SUCCESS)
        return result;

    entries.resize(count);
    for (const auto& entry : entries) {
        if (directories_only && entry.is_dir != RAC_TRUE)
            continue;
        out_names->emplace_back(entry.name);
    }
    return RAC_SUCCESS;
}

namespace {

int64_t store_now_ms() {
    return std::chrono::duration_cast<std::chrono::milliseconds>(
               std::chrono::system_clock::now().time_since_epoch())
        .count();
}

}  // namespace

rac_result_t store_save_document(const runanywhere::v1::WorkflowDocument& document) {
    if (!id_is_safe(document.id())) {
        rac_error_set_details("workflow id must be 1-128 chars of [A-Za-z0-9_-]");
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    const std::string directory = workflow_directory(document.id());
    if (directory.empty()) {
        rac_error_set_details("model paths base directory is not configured");
        return RAC_ERROR_NOT_INITIALIZED;
    }

    runanywhere::v1::WorkflowDocument stored = document;
    stored.set_schema_version(kWorkflowSchemaVersion);
    // The header promises a save refreshes this. Copying the caller's value
    // meant a caller that never set it stored 0, and every WorkflowSummary
    // then reported 0 as the last-modified time.
    stored.set_updated_at_ms(store_now_ms());

    return write_message_json(join(directory, kDocumentFile), stored);
}

rac_result_t store_load_document(const std::string& workflow_id,
                                 runanywhere::v1::WorkflowDocument* out_document) {
    if (!id_is_safe(workflow_id)) {
        rac_error_set_details("workflow id must be 1-128 chars of [A-Za-z0-9_-]");
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    const std::string directory = workflow_directory(workflow_id);
    if (directory.empty()) {
        rac_error_set_details("model paths base directory is not configured");
        return RAC_ERROR_NOT_INITIALIZED;
    }

    const std::string path = join(directory, kDocumentFile);
    if (!adapter_file_exists(path))
        return RAC_ERROR_NOT_FOUND;

    const rac_result_t result = read_message_json(path, out_document);
    if (result != RAC_SUCCESS)
        return result;

    if (out_document->schema_version() > kWorkflowSchemaVersion) {
        rac_error_set_details("workflow was written by a newer build");
        return RAC_ERROR_DECODING_ERROR;
    }
    return RAC_SUCCESS;
}

rac_result_t store_list_documents(runanywhere::v1::WorkflowList* out_list) {
    out_list->Clear();

    const std::string root = workflows_directory();
    if (root.empty()) {
        rac_error_set_details("model paths base directory is not configured");
        return RAC_ERROR_NOT_INITIALIZED;
    }

    std::vector<std::string> ids;
    const rac_result_t result = adapter_list_directory(root, &ids, /*directories_only=*/true);
    if (result != RAC_SUCCESS)
        return result;

    for (const std::string& id : ids) {
        runanywhere::v1::WorkflowDocument document;
        // One unreadable document must not make the whole list unopenable, so a
        // failed load drops that entry and the listing continues.
        if (store_load_document(id, &document) != RAC_SUCCESS) {
            RAC_LOG_WARNING(kLogCategory, "skipping unreadable workflow '%s'", id.c_str());
            continue;
        }

        runanywhere::v1::WorkflowSummary* summary = out_list->add_workflows();
        summary->set_id(document.id());
        summary->set_name(document.name());
        summary->set_created_at_ms(document.created_at_ms());
        summary->set_updated_at_ms(document.updated_at_ms());
        summary->set_node_count(static_cast<uint32_t>(document.nodes_size()));
    }
    return RAC_SUCCESS;
}

rac_result_t store_delete_document(const std::string& workflow_id) {
    if (!id_is_safe(workflow_id)) {
        rac_error_set_details("workflow id must be 1-128 chars of [A-Za-z0-9_-]");
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    const std::string directory = workflow_directory(workflow_id);
    if (directory.empty()) {
        rac_error_set_details("model paths base directory is not configured");
        return RAC_ERROR_NOT_INITIALIZED;
    }

    const std::string runs = join(directory, kRunsDirectory);
    std::vector<std::string> run_files;
    if (adapter_list_directory(runs, &run_files, /*directories_only=*/false) == RAC_SUCCESS) {
        for (const std::string& file : run_files) {
            adapter_delete_file(join(runs, file));
        }
    }

    const std::string document = join(directory, kDocumentFile);
    if (!adapter_file_exists(document))
        return RAC_SUCCESS;
    return adapter_delete_file(document);
}

rac_result_t store_save_run(const runanywhere::v1::WorkflowRunRecord& record) {
    if (!id_is_safe(record.workflow_id()) || !id_is_safe(record.run_id())) {
        rac_error_set_details("workflow and run ids must be 1-128 chars of [A-Za-z0-9_-]");
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    const std::string directory = workflow_directory(record.workflow_id());
    if (directory.empty()) {
        rac_error_set_details("model paths base directory is not configured");
        return RAC_ERROR_NOT_INITIALIZED;
    }

    const std::string path = join(join(directory, kRunsDirectory), record.run_id() + ".json");
    return write_message_json(path, record);
}

rac_result_t store_load_run(const std::string& workflow_id, const std::string& run_id,
                            runanywhere::v1::WorkflowRunRecord* out_record) {
    if (!id_is_safe(workflow_id) || !id_is_safe(run_id)) {
        rac_error_set_details("workflow and run ids must be 1-128 chars of [A-Za-z0-9_-]");
        return RAC_ERROR_INVALID_ARGUMENT;
    }

    const std::string directory = workflow_directory(workflow_id);
    if (directory.empty()) {
        rac_error_set_details("model paths base directory is not configured");
        return RAC_ERROR_NOT_INITIALIZED;
    }

    const std::string path = join(join(directory, kRunsDirectory), run_id + ".json");
    if (!adapter_file_exists(path))
        return RAC_ERROR_NOT_FOUND;
    return read_message_json(path, out_record);
}

}  // namespace rac::agent
