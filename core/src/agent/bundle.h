// SPDX-License-Identifier: Apache-2.0
//
// Bundle assembly and import. A bundle is a WorkflowDocument list plus every
// NodePack any of them references, transitively through a composite pack's
// own subgraph.

#pragma once

#include "agent_workflow.pb.h"

#include <functional>
#include <string>
#include <vector>

#include "rac/core/rac_error.h"

namespace rac::agent {

using PackLoader =
    std::function<rac_result_t(const std::string& pack_id, runanywhere::v1::NodePack* out_pack)>;

/// Pure assembly: given already-loaded documents and a pack loader, walks
/// every PackNodeConfig transitively and builds the bundle. No filesystem
/// access happens here — @p load_pack is the only source of pack data, which
/// is what makes this testable without a platform adapter.
///
/// A pack that references itself, directly or through intermediate packs,
/// fails with RAC_ERROR_INVALID_CONFIGURATION rather than recursing forever.
/// A pack a node references but @p load_pack cannot supply is silently
/// omitted from the bundle, the same way an unreadable workflow is skipped
/// rather than failing a listing.
rac_result_t assemble_bundle(const std::vector<runanywhere::v1::WorkflowDocument>& documents,
                             const PackLoader& load_pack,
                             runanywhere::v1::WorkflowBundle* out_bundle, std::string* out_error);

/// Loads @p workflow_ids and every pack they transitively reference from
/// storage, and assembles a WorkflowBundle.
rac_result_t bundle_export(const std::vector<std::string>& workflow_ids,
                           runanywhere::v1::WorkflowBundle* out_bundle, std::string* out_error);

/// Saves every workflow and pack @p bundle carries, reporting per-item
/// outcome rather than failing the whole import on one bad entry.
///
/// @return RAC_SUCCESS once the bundle has been processed (even when every
///         item was skipped), or RAC_ERROR_DECODING_ERROR when
///         bundle.format_version() is newer than this build writes — refused
///         before anything is touched.
rac_result_t bundle_import(const runanywhere::v1::WorkflowBundle& bundle,
                           runanywhere::v1::WorkflowBundleImportResult* out_result,
                           std::string* out_error);

}  // namespace rac::agent
