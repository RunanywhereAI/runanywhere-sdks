// SPDX-License-Identifier: Apache-2.0

#include "rac/agent/rac_agent_workflow.h"

#include "agent_workflow.pb.h"
#include "bundle.h"
#include "host_callbacks.h"
#include "pack_store.h"
#include "workflow_runner.h"
#include "workflow_store.h"
#include "workflow_validator.h"

#include <atomic>
#include <cstdio>
#include <memory>
#include <mutex>
#include <string>
#include <unordered_map>
#include <vector>

namespace {

using rac::agent::WorkflowRunner;

struct RunTable {
    std::mutex mutex;
    std::unordered_map<uint64_t, std::shared_ptr<WorkflowRunner>> runs;
    uint64_t next_handle = 1;
};

RunTable& run_table() {
    static RunTable table;
    return table;
}

std::shared_ptr<WorkflowRunner> lookup(rac_handle_t handle) {
    RunTable& table = run_table();
    std::lock_guard<std::mutex> lock(table.mutex);
    auto it = table.runs.find(reinterpret_cast<uint64_t>(handle));
    return it == table.runs.end() ? nullptr : it->second;
}

/// Monotonic within a process, prefixed so it satisfies the store's id rules.
std::string generate_run_id() {
    static std::atomic<uint64_t> counter{0};
    char buffer[64];
    std::snprintf(buffer, sizeof(buffer), "run-%llu",
                  static_cast<unsigned long long>(counter.fetch_add(1) + 1));
    return buffer;
}

rac_result_t write_message(const google::protobuf::MessageLite& message,
                           rac_proto_buffer_t* out_buffer) {
    const std::string encoded = message.SerializeAsString();
    return rac_proto_buffer_copy(reinterpret_cast<const uint8_t*>(encoded.data()), encoded.size(),
                                 out_buffer);
}

bool parse_request(const uint8_t* bytes, size_t size, google::protobuf::MessageLite* out) {
    if (bytes == nullptr || size == 0)
        return false;
    return out->ParseFromArray(bytes, static_cast<int>(size));
}

}  // namespace

rac_result_t rac_agent_set_host_callbacks(const rac_agent_host_callbacks_t* callbacks) {
    return rac::agent::set_host_callbacks(callbacks);
}

rac_result_t rac_agent_workflow_save_proto(const uint8_t* document_proto_bytes,
                                           size_t document_proto_size) {
    runanywhere::v1::WorkflowDocument document;
    if (!parse_request(document_proto_bytes, document_proto_size, &document)) {
        rac_error_set_details("failed to parse WorkflowDocument");
        return RAC_ERROR_DECODING_ERROR;
    }

    runanywhere::v1::WorkflowValidationResult validation;
    rac::agent::validate_document(document, &validation);
    if (!validation.valid()) {
        rac_error_set_details(validation.issues_size() > 0 ? validation.issues(0).message().c_str()
                                                           : "workflow is not valid");
        return RAC_ERROR_INVALID_CONFIGURATION;
    }

    return rac::agent::store_save_document(document);
}

rac_result_t rac_agent_workflow_load_proto(const char* workflow_id,
                                           rac_proto_buffer_t* out_document) {
    if (workflow_id == nullptr || out_document == nullptr)
        return RAC_ERROR_INVALID_ARGUMENT;
    rac_proto_buffer_init(out_document);

    runanywhere::v1::WorkflowDocument document;
    const rac_result_t result = rac::agent::store_load_document(workflow_id, &document);
    if (result != RAC_SUCCESS)
        return result;
    return write_message(document, out_document);
}

rac_result_t rac_agent_workflow_list_proto(rac_proto_buffer_t* out_list) {
    if (out_list == nullptr)
        return RAC_ERROR_INVALID_ARGUMENT;
    rac_proto_buffer_init(out_list);

    runanywhere::v1::WorkflowList list;
    const rac_result_t result = rac::agent::store_list_documents(&list);
    if (result != RAC_SUCCESS)
        return result;
    return write_message(list, out_list);
}

rac_result_t rac_agent_workflow_delete(const char* workflow_id) {
    if (workflow_id == nullptr)
        return RAC_ERROR_INVALID_ARGUMENT;
    return rac::agent::store_delete_document(workflow_id);
}

rac_result_t rac_agent_workflow_validate_proto(const uint8_t* document_proto_bytes,
                                               size_t document_proto_size,
                                               rac_proto_buffer_t* out_result) {
    if (out_result == nullptr)
        return RAC_ERROR_INVALID_ARGUMENT;
    rac_proto_buffer_init(out_result);

    runanywhere::v1::WorkflowDocument document;
    if (!parse_request(document_proto_bytes, document_proto_size, &document)) {
        rac_error_set_details("failed to parse WorkflowDocument");
        return RAC_ERROR_DECODING_ERROR;
    }

    runanywhere::v1::WorkflowValidationResult validation;
    rac::agent::validate_document(document, &validation);
    return write_message(validation, out_result);
}

rac_result_t rac_agent_run_create_proto(const uint8_t* request_proto_bytes,
                                        size_t request_proto_size,
                                        rac_agent_run_event_callback_fn event_callback,
                                        void* user_data, rac_handle_t* out_run) {
    if (out_run == nullptr)
        return RAC_ERROR_INVALID_ARGUMENT;
    *out_run = nullptr;

    runanywhere::v1::WorkflowRunRequest request;
    if (!parse_request(request_proto_bytes, request_proto_size, &request)) {
        rac_error_set_details("failed to parse WorkflowRunRequest");
        return RAC_ERROR_DECODING_ERROR;
    }

    runanywhere::v1::WorkflowDocument document;
    const rac_result_t loaded = rac::agent::store_load_document(request.workflow_id(), &document);
    if (loaded != RAC_SUCCESS)
        return loaded;

    runanywhere::v1::WorkflowValidationResult validation;
    rac::agent::validate_document(document, &validation);
    if (!validation.valid()) {
        rac_error_set_details(validation.issues_size() > 0 ? validation.issues(0).message().c_str()
                                                           : "workflow is not valid");
        return RAC_ERROR_INVALID_CONFIGURATION;
    }

    std::vector<runanywhere::v1::WorkflowItem> initial_items(request.initial_items().begin(),
                                                             request.initial_items().end());

    auto runner =
        std::make_shared<WorkflowRunner>(std::move(document), generate_run_id(),
                                         std::move(initial_items), event_callback, user_data);

    RunTable& table = run_table();
    std::lock_guard<std::mutex> lock(table.mutex);
    const uint64_t handle = table.next_handle++;
    table.runs[handle] = std::move(runner);
    *out_run = reinterpret_cast<rac_handle_t>(handle);
    return RAC_SUCCESS;
}

rac_result_t rac_agent_run_start(rac_handle_t run) {
    auto runner = lookup(run);
    if (runner == nullptr)
        return RAC_ERROR_INVALID_HANDLE;
    return runner->start();
}

rac_result_t rac_agent_run_cancel(rac_handle_t run) {
    auto runner = lookup(run);
    if (runner == nullptr)
        return RAC_ERROR_INVALID_HANDLE;
    runner->cancel();
    return RAC_SUCCESS;
}

rac_result_t rac_agent_run_record_proto(rac_handle_t run, rac_proto_buffer_t* out_record) {
    if (out_record == nullptr)
        return RAC_ERROR_INVALID_ARGUMENT;
    rac_proto_buffer_init(out_record);

    auto runner = lookup(run);
    if (runner == nullptr)
        return RAC_ERROR_INVALID_HANDLE;
    return write_message(runner->record(), out_record);
}

void rac_agent_run_destroy(rac_handle_t run) {
    if (run == nullptr)
        return;

    std::shared_ptr<WorkflowRunner> runner;
    {
        RunTable& table = run_table();
        std::lock_guard<std::mutex> lock(table.mutex);
        auto it = table.runs.find(reinterpret_cast<uint64_t>(run));
        if (it == table.runs.end())
            return;
        runner = std::move(it->second);
        table.runs.erase(it);
    }

    // Cancel and join happen in the destructor; dropping the last reference
    // here keeps that ordering in one place.
    runner->cancel();
    runner->join();
}

rac_result_t rac_agent_run_record_load_proto(const char* workflow_id, const char* run_id,
                                             rac_proto_buffer_t* out_record) {
    if (workflow_id == nullptr || run_id == nullptr || out_record == nullptr)
        return RAC_ERROR_INVALID_ARGUMENT;
    rac_proto_buffer_init(out_record);

    runanywhere::v1::WorkflowRunRecord record;
    const rac_result_t result = rac::agent::store_load_run(workflow_id, run_id, &record);
    if (result != RAC_SUCCESS)
        return result;
    return write_message(record, out_record);
}

rac_result_t rac_agent_pack_save_proto(const uint8_t* pack_proto_bytes, size_t pack_proto_size) {
    runanywhere::v1::NodePack pack;
    if (!parse_request(pack_proto_bytes, pack_proto_size, &pack)) {
        rac_error_set_details("failed to parse NodePack");
        return RAC_ERROR_DECODING_ERROR;
    }
    return rac::agent::store_save_pack(pack);
}

rac_result_t rac_agent_pack_load_proto(const char* pack_id, rac_proto_buffer_t* out_pack) {
    if (pack_id == nullptr || out_pack == nullptr)
        return RAC_ERROR_INVALID_ARGUMENT;
    rac_proto_buffer_init(out_pack);

    runanywhere::v1::NodePack pack;
    const rac_result_t result = rac::agent::store_load_pack(pack_id, &pack);
    if (result != RAC_SUCCESS)
        return result;
    return write_message(pack, out_pack);
}

rac_result_t rac_agent_pack_list_proto(rac_proto_buffer_t* out_list) {
    if (out_list == nullptr)
        return RAC_ERROR_INVALID_ARGUMENT;
    rac_proto_buffer_init(out_list);

    runanywhere::v1::NodePackList list;
    const rac_result_t result = rac::agent::store_list_packs(&list);
    if (result != RAC_SUCCESS)
        return result;
    return write_message(list, out_list);
}

rac_result_t rac_agent_pack_delete(const char* pack_id) {
    if (pack_id == nullptr)
        return RAC_ERROR_INVALID_ARGUMENT;
    return rac::agent::store_delete_pack(pack_id);
}

rac_result_t rac_agent_bundle_export_proto(const uint8_t* request_proto_bytes,
                                           size_t request_proto_size,
                                           rac_proto_buffer_t* out_bundle) {
    if (out_bundle == nullptr)
        return RAC_ERROR_INVALID_ARGUMENT;
    rac_proto_buffer_init(out_bundle);

    runanywhere::v1::WorkflowBundleExportRequest request;
    if (!parse_request(request_proto_bytes, request_proto_size, &request)) {
        rac_error_set_details("failed to parse WorkflowBundleExportRequest");
        return RAC_ERROR_DECODING_ERROR;
    }

    const std::vector<std::string> workflow_ids(request.workflow_ids().begin(),
                                                request.workflow_ids().end());

    runanywhere::v1::WorkflowBundle bundle;
    std::string error;
    const rac_result_t result = rac::agent::bundle_export(workflow_ids, &bundle, &error);
    if (result != RAC_SUCCESS) {
        rac_error_set_details(error.empty() ? "bundle export failed" : error.c_str());
        return result;
    }
    return write_message(bundle, out_bundle);
}

rac_result_t rac_agent_bundle_import_proto(const uint8_t* bundle_proto_bytes,
                                           size_t bundle_proto_size,
                                           rac_proto_buffer_t* out_result) {
    if (out_result == nullptr)
        return RAC_ERROR_INVALID_ARGUMENT;
    rac_proto_buffer_init(out_result);

    runanywhere::v1::WorkflowBundle bundle;
    if (!parse_request(bundle_proto_bytes, bundle_proto_size, &bundle)) {
        rac_error_set_details("failed to parse WorkflowBundle");
        return RAC_ERROR_DECODING_ERROR;
    }

    runanywhere::v1::WorkflowBundleImportResult result;
    std::string error;
    const rac_result_t status = rac::agent::bundle_import(bundle, &result, &error);
    if (status != RAC_SUCCESS) {
        rac_error_set_details(error.empty() ? "bundle import failed" : error.c_str());
        return status;
    }
    return write_message(result, out_result);
}
