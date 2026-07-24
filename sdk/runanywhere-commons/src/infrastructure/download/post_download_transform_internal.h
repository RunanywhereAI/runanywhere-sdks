/**
 * @file post_download_transform_internal.h
 * @brief Deterministic, restart-safe post-download file transforms.
 */

#ifndef RAC_POST_DOWNLOAD_TRANSFORM_INTERNAL_H
#define RAC_POST_DOWNLOAD_TRANSFORM_INTERNAL_H

#include <string>

namespace runanywhere::v1 {
class PostDownloadTransform;
}

namespace rac::download {

enum class post_download_transform_outcome {
    kApplied,
    kAlreadyFinal,
    kRecoveredPartial,
};

/** Validate the source/final integrity contract and ordered operations. */
bool validate_post_download_transform(const runanywhere::v1::PostDownloadTransform& transform,
                                      std::string* out_error);

/**
 * Verify and apply a transform in place.
 *
 * A source-sized file is verified before any bytes are appended. A final-sized
 * file is accepted only when its final SHA-256 matches. If a previous process
 * stopped part-way through the append, the existing suffix must match an exact
 * prefix of the declared operations before the missing tail is appended.
 */
bool apply_post_download_transform(const std::string& path,
                                   const runanywhere::v1::PostDownloadTransform& transform,
                                   post_download_transform_outcome* out_outcome,
                                   std::string* out_error);

}  // namespace rac::download

#endif  // RAC_POST_DOWNLOAD_TRANSFORM_INTERNAL_H
