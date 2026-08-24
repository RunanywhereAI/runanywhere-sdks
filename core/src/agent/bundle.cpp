// SPDX-License-Identifier: Apache-2.0

#include "bundle.h"

#include "pack_store.h"
#include "workflow_store.h"
#include "workflow_validator.h"

#include <chrono>
#include <unordered_set>

namespace rac::agent {
namespace {

using runanywhere::v1::NodePack;
using runanywhere::v1::WorkflowBundle;
using runanywhere::v1::WorkflowBundleImportResult;
using runanywhere::v1::WorkflowDocument;
using runanywhere::v1::WorkflowNode;

int64_t now_ms() {
    return std::chrono::duration_cast<std::chrono::milliseconds>(
               std::chrono::system_clock::now().time_since_epoch())
        .count();
}

rac_result_t collect_pack(const std::string& pack_id, const PackLoader& load_pack,
                          std::unordered_set<std::string>* resolved,
                          std::unordered_set<std::string>* in_progress,
                          std::vector<NodePack>* out_packs, std::string* out_error) {
    if (resolved->count(pack_id) != 0)
        return RAC_SUCCESS;
    if (!in_progress->insert(pack_id).second) {
        *out_error = "pack '" + pack_id + "' has a cyclic dependency";
        return RAC_ERROR_INVALID_CONFIGURATION;
    }

    NodePack pack;
    if (load_pack(pack_id, &pack) != RAC_SUCCESS) {
        // Referenced but not present on this machine. Nothing to bundle for
        // it; the node that named it already carries `missing` for the case
        // where it was flagged at load time.
        in_progress->erase(pack_id);
        return RAC_SUCCESS;
    }

    if (pack.has_composite()) {
        for (const WorkflowNode& node : pack.composite().graph().nodes()) {
            if (node.config_case() != WorkflowNode::kPackNode || node.pack_node().pack_id().empty())
                continue;
            const rac_result_t nested = collect_pack(node.pack_node().pack_id(), load_pack,
                                                     resolved, in_progress, out_packs, out_error);
            if (nested != RAC_SUCCESS) {
                in_progress->erase(pack_id);
                return nested;
            }
        }
    }

    in_progress->erase(pack_id);
    resolved->insert(pack_id);
    out_packs->push_back(std::move(pack));
    return RAC_SUCCESS;
}

}  // namespace

rac_result_t assemble_bundle(const std::vector<WorkflowDocument>& documents,
                             const PackLoader& load_pack, WorkflowBundle* out_bundle,
                             std::string* out_error) {
    out_bundle->Clear();
    out_bundle->set_format_version(kWorkflowBundleFormatVersion);
    out_bundle->set_generator("runanywhere-commons");

    std::unordered_set<std::string> resolved;
    std::unordered_set<std::string> in_progress;
    std::vector<NodePack> packs;

    for (const WorkflowDocument& document : documents) {
        *out_bundle->add_workflows() = document;
        for (const WorkflowNode& node : document.nodes()) {
            if (node.config_case() != WorkflowNode::kPackNode || node.pack_node().missing() ||
                node.pack_node().pack_id().empty())
                continue;
            const rac_result_t status = collect_pack(node.pack_node().pack_id(), load_pack,
                                                     &resolved, &in_progress, &packs, out_error);
            if (status != RAC_SUCCESS)
                return status;
        }
    }

    for (NodePack& pack : packs)
        *out_bundle->add_packs() = std::move(pack);
    return RAC_SUCCESS;
}

rac_result_t bundle_export(const std::vector<std::string>& workflow_ids, WorkflowBundle* out_bundle,
                           std::string* out_error) {
    std::vector<WorkflowDocument> documents;
    documents.reserve(workflow_ids.size());
    for (const std::string& id : workflow_ids) {
        WorkflowDocument document;
        const rac_result_t loaded = store_load_document(id, &document);
        if (loaded != RAC_SUCCESS) {
            *out_error = "could not load workflow '" + id + "'";
            return loaded;
        }
        documents.push_back(std::move(document));
    }

    const rac_result_t assembled =
        assemble_bundle(documents, &store_load_pack, out_bundle, out_error);
    if (assembled != RAC_SUCCESS)
        return assembled;

    out_bundle->set_exported_at_ms(now_ms());
    return RAC_SUCCESS;
}

rac_result_t bundle_import(const WorkflowBundle& bundle, WorkflowBundleImportResult* out_result,
                           std::string* out_error) {
    out_result->Clear();
    if (bundle.format_version() > kWorkflowBundleFormatVersion) {
        *out_error = "bundle format_version " + std::to_string(bundle.format_version()) +
                     " is newer than this build supports (" +
                     std::to_string(kWorkflowBundleFormatVersion) + ")";
        return RAC_ERROR_DECODING_ERROR;
    }

    // Packs first, so a workflow that references one of this bundle's packs
    // finds it already installed by the time it is saved.
    for (const NodePack& pack : bundle.packs()) {
        const rac_result_t saved = store_save_pack(pack);
        if (saved != RAC_SUCCESS) {
            auto* issue = out_result->add_skipped();
            issue->set_kind(runanywhere::v1::BUNDLE_ITEM_KIND_PACK);
            issue->set_id(pack.id());
            issue->set_message(rac_error_message(saved));
            continue;
        }
        out_result->add_imported_pack_ids(pack.id());
    }

    for (const WorkflowDocument& workflow : bundle.workflows()) {
        runanywhere::v1::WorkflowValidationResult validation;
        validate_document(workflow, &validation);
        if (!validation.valid()) {
            auto* issue = out_result->add_skipped();
            issue->set_kind(runanywhere::v1::BUNDLE_ITEM_KIND_WORKFLOW);
            issue->set_id(workflow.id());
            issue->set_message(validation.issues_size() > 0 ? validation.issues(0).message()
                                                            : "workflow is not valid");
            continue;
        }

        const rac_result_t saved = store_save_document(workflow);
        if (saved != RAC_SUCCESS) {
            auto* issue = out_result->add_skipped();
            issue->set_kind(runanywhere::v1::BUNDLE_ITEM_KIND_WORKFLOW);
            issue->set_id(workflow.id());
            issue->set_message(rac_error_message(saved));
            continue;
        }
        out_result->add_imported_workflow_ids(workflow.id());
    }

    return RAC_SUCCESS;
}

}  // namespace rac::agent
