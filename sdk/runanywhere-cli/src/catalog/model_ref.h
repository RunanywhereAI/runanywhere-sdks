/**
 * @file model_ref.h
 * @brief Model reference resolution for pull/run/show/rm arguments.
 *
 * Accepted forms, resolved in order:
 *   1. catalog id            qwen3-0.6b
 *   2. catalog alias         qwen3
 *   3. hf.co/<org>/<repo>/<file>           (rewritten to a resolve/main URL)
 *   4. http(s)://...                       (registered via commons URL factory)
 *
 * URL forms go through rac_register_model_from_url_proto so id/name/format/
 * framework inference all happen in commons — the CLI never guesses.
 */

#ifndef RCLI_CATALOG_MODEL_REF_H
#define RCLI_CATALOG_MODEL_REF_H

#include <string>

#include "rac/core/rac_types.h"

namespace rcli::model_ref {

struct Resolved {
    std::string model_id;     // registry id to operate on
    bool from_catalog = false;
};

/**
 * Resolve `ref` to a registered model id. Catalog entries are assumed already
 * registered (bootstrap runs catalog::register_all()). URL refs register a new
 * entry on the fly. Returns RAC_SUCCESS or an error; `error` (non-null)
 * receives a user-facing message including did-you-mean suggestions.
 */
rac_result_t resolve(const std::string& ref, Resolved* out, std::string* error);

/**
 * Normalize an hf.co/huggingface.co shorthand to a direct resolve URL.
 * Returns empty string when `ref` is not an hf shorthand. Exposed for tests.
 */
std::string normalize_hf_ref(const std::string& ref);

}  // namespace rcli::model_ref

#endif  // RCLI_CATALOG_MODEL_REF_H
