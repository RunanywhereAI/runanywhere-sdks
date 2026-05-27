/**
 * @file whisperkit_callbacks_internal.h
 * @brief Engine-internal helpers around the Swift callback table.
 *
 * Used to:
 *   - take a value snapshot of the live callbacks under the registration
 *     lock so engine-internal call sites don't dereference the global
 *     struct after another thread may have written it (engines-other-007);
 *   - hand back the destroy fn + user_data that were cached at the first
 *     set_callbacks() so impls created during an earlier registration can
 *     still be torn down even if a zeroed struct was later installed
 *     (engines-other-006).
 *
 * These helpers are private to the engines/whisperkit_coreml/ TU set and
 * intentionally not exported on the commons ABI surface.
 */

#ifndef RAC_ENGINES_WHISPERKIT_COREML_CALLBACKS_INTERNAL_H
#define RAC_ENGINES_WHISPERKIT_COREML_CALLBACKS_INTERNAL_H

#include "rac/backends/rac_stt_whisperkit_coreml.h"

namespace runanywhere::engines::whisperkit_coreml {

bool snapshot_callbacks(rac_whisperkit_coreml_stt_callbacks_t *out);

bool snapshot_cached_destroy(rac_whisperkit_coreml_stt_destroy_fn *out_fn,
                             void **out_user_data);

} // namespace runanywhere::engines::whisperkit_coreml

#endif // RAC_ENGINES_WHISPERKIT_COREML_CALLBACKS_INTERNAL_H
