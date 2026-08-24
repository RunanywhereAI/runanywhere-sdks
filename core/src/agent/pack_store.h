// SPDX-License-Identifier: Apache-2.0
//
// Node pack persistence. Mirrors workflow_store.{h,cpp} exactly: JSON through
// the platform adapter, same id safety rule, unreadable entries skipped when
// listing.

#pragma once

#include "agent_workflow.pb.h"

#include <string>

#include "rac/core/rac_error.h"

namespace rac::agent {

/// `{base}/RunAnywhere/NodePacks`
std::string packs_directory();

/// `{base}/RunAnywhere/NodePacks/{pack_id}`
std::string pack_directory(const std::string& pack_id);

rac_result_t store_save_pack(const runanywhere::v1::NodePack& pack);
rac_result_t store_load_pack(const std::string& pack_id, runanywhere::v1::NodePack* out_pack);
rac_result_t store_list_packs(runanywhere::v1::NodePackList* out_list);
rac_result_t store_delete_pack(const std::string& pack_id);

}  // namespace rac::agent
