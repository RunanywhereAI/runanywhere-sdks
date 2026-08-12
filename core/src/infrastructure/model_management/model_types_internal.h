/**
 * @file model_types_internal.h
 * @brief Private model-type ownership helpers shared by commons TUs.
 *
 * NOT part of the public C ABI; only files under
 * `src/infrastructure/model_management/` may include this header.
 *
 * `rac_model_artifact_info_t` owns three heap blocks (the expected-files
 * manifest, the file-descriptor array, and the strategy id). Every place that
 * duplicates a `rac_model_info_t` has to duplicate them too, and the copy has
 * to keep `file_descriptors` and `file_descriptor_count` in lockstep --
 * consumers such as `model_folder_is_complete_struct()` iterate
 * `file_descriptors[i]` bounded only by `file_descriptor_count`, so a non-zero
 * count paired with a NULL pointer is a null dereference. This header is the
 * single declaration of that copy so no TU has to hand-roll it again.
 */

#ifndef RAC_INFRA_MODEL_MANAGEMENT_MODEL_TYPES_INTERNAL_H
#define RAC_INFRA_MODEL_MANAGEMENT_MODEL_TYPES_INTERNAL_H

#include "rac/core/rac_error.h"
#include "rac/infrastructure/model_management/rac_model_types.h"

namespace rac::infra::model_types {

/**
 * @brief Deep-copy an artifact descriptor block into @p dst.
 *
 * @p dst is overwritten wholesale: scalars are assigned and every owned pointer
 * is duplicated, so the result shares no memory with @p src and can be released
 * through the normal `rac_model_info_free()` / `rac_expected_model_files_free()`
 * + `rac_model_file_descriptors_free()` path. @p dst must not already own
 * artifact memory (callers pass a freshly zeroed struct); its previous contents
 * are not freed.
 *
 * Failure contract -- @p dst is left in a consistent, freeable state on every
 * path:
 *   - each owned block is all-or-nothing (a partially duplicated expected-files
 *     manifest or descriptor array is released and the field left NULL rather
 *     than handed back with counted NULL entries), and
 *   - `file_descriptors == NULL` if and only if `file_descriptor_count == 0`.
 *
 * @return RAC_ERROR_NULL_POINTER if either argument is NULL,
 *         RAC_ERROR_OUT_OF_MEMORY if any block could not be duplicated (@p dst
 *         then holds the blocks that did succeed), RAC_SUCCESS otherwise.
 */
rac_result_t artifact_info_copy(const rac_model_artifact_info_t* src,
                                rac_model_artifact_info_t* dst);

}  // namespace rac::infra::model_types

#endif  // RAC_INFRA_MODEL_MANAGEMENT_MODEL_TYPES_INTERNAL_H
