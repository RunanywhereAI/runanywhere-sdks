// SPDX-License-Identifier: Apache-2.0
//
// Workflow persistence. Documents and run records are stored as JSON so a user
// can read, diff, and hand-edit them, but they round-trip through the generated
// proto types rather than a hand-written serializer.
//
// Every filesystem touch goes through rac_platform_adapter_t. Commons never
// calls fopen, which is what lets the same code persist to OPFS on Web and to a
// sandboxed container on Apple platforms.

#pragma once

#include "agent_workflow.pb.h"

#include <google/protobuf/util/json_util.h>
#include <string>
#include <vector>

#include "rac/core/rac_error.h"

namespace rac::agent {

/// `{base}/RunAnywhere/Workflows`
std::string workflows_directory();

/// `{base}/RunAnywhere/Workflows/{workflow_id}`
std::string workflow_directory(const std::string& workflow_id);

rac_result_t adapter_write_file(const std::string& path, const std::string& bytes);
rac_result_t adapter_read_file(const std::string& path, std::string* out_bytes);
bool adapter_file_exists(const std::string& path);
rac_result_t adapter_delete_file(const std::string& path);

/// Entry names only, no path component. Returns RAC_SUCCESS with an empty
/// vector when the directory does not exist, because an empty workflow list and
/// a missing workflows directory are the same thing to a caller.
rac_result_t adapter_list_directory(const std::string& path, std::vector<std::string>* out_names,
                                    bool directories_only);

/// A workflow or pack id becomes a directory name, so anything that could
/// escape the parent directory or collide across platforms is refused
/// outright rather than sanitized into a different id than the caller asked
/// for.
bool id_is_safe(const std::string& id);

std::string join(const std::string& base, const std::string& leaf);

/// Shared with pack_store.cpp so a pack round-trips through JSON the same way
/// a workflow document does.
template <typename Message>
rac_result_t write_message_json(const std::string& path, const Message& message) {
    google::protobuf::util::JsonPrintOptions options;
    options.add_whitespace = true;
    // A user reading the file should see every field, including the ones left
    // at their default, rather than having to know what protobuf omitted.
    options.always_print_fields_with_no_presence = true;

    std::string json;
    const auto status = google::protobuf::util::MessageToJsonString(message, &json, options);
    if (!status.ok()) {
        rac_error_set_details("failed to encode workflow JSON");
        return RAC_ERROR_ENCODING_ERROR;
    }
    return adapter_write_file(path, json);
}

template <typename Message>
rac_result_t read_message_json(const std::string& path, Message* out_message) {
    std::string json;
    const rac_result_t read_result = adapter_read_file(path, &json);
    if (read_result != RAC_SUCCESS)
        return read_result;

    google::protobuf::util::JsonParseOptions options;
    // Tolerate a document written by a build that knew fields this one does
    // not. The schema_version check at the call site is the real gate.
    options.ignore_unknown_fields = true;

    const auto status = google::protobuf::util::JsonStringToMessage(json, out_message, options);
    if (!status.ok()) {
        rac_error_set_details("stored workflow JSON is not readable");
        return RAC_ERROR_DECODING_ERROR;
    }
    return RAC_SUCCESS;
}

rac_result_t store_save_document(const runanywhere::v1::WorkflowDocument& document);
rac_result_t store_load_document(const std::string& workflow_id,
                                 runanywhere::v1::WorkflowDocument* out_document);
rac_result_t store_list_documents(runanywhere::v1::WorkflowList* out_list);
rac_result_t store_delete_document(const std::string& workflow_id);

rac_result_t store_save_run(const runanywhere::v1::WorkflowRunRecord& record);
rac_result_t store_load_run(const std::string& workflow_id, const std::string& run_id,
                            runanywhere::v1::WorkflowRunRecord* out_record);

/// Schema shape this build writes and the newest it can read. A document
/// carrying a higher value is rejected rather than parsed with fields missing.
inline constexpr uint32_t kWorkflowSchemaVersion = 1u;

/// Shape of WorkflowBundle this build writes and the newest it can import. A
/// bundle carrying a higher value is refused outright, before any of its
/// items are touched.
inline constexpr uint32_t kWorkflowBundleFormatVersion = 1u;

}  // namespace rac::agent
