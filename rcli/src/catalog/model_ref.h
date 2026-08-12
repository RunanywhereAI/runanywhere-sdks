/**
 * @file model_ref.h
 * @brief Model reference resolution for pull/run/show/rm arguments.
 *
 * Accepted forms, resolved in order:
 *   1. catalog id            qwen3-0.6b
 *   2. catalog alias         qwen3
 *   3. registered id         (manifest-restored URL/HF pulls, discovered
 * models)
 *   4. hf.co/<org>/<repo>[:quant|/file], hf://..., huggingface.co/...
 *   5. http(s)://...
 *
 * URL and HF forms go through rac_register_model_from_url_proto so the whole
 * grammar (quant selection, mmproj pairing, shards, id/name/format inference)
 * lives in commons — the CLI never guesses.
 */

#ifndef RCLI_CATALOG_MODEL_REF_H
#define RCLI_CATALOG_MODEL_REF_H

#include <string>

#include "model_types.pb.h"
#include "rac/core/rac_types.h"

namespace rcli::model_ref {

struct Resolved {
  std::string model_id; // registry id to operate on
  bool from_catalog = false;
};

struct ResolveOptions {
  bool has_framework = false;
  runanywhere::v1::InferenceFramework framework =
      runanywhere::v1::INFERENCE_FRAMEWORK_UNSPECIFIED;
  bool has_category = false;
  runanywhere::v1::ModelCategory category =
      runanywhere::v1::MODEL_CATEGORY_UNSPECIFIED;
};

/**
 * Resolve `ref` to a registered model id. Catalog entries are assumed already
 * registered (bootstrap runs catalog::register_all()). URL refs register a new
 * entry on the fly. Returns RAC_SUCCESS or an error; `error` (non-null)
 * receives a user-facing message including did-you-mean suggestions.
 */
rac_result_t resolve(const std::string &ref, Resolved *out, std::string *error,
                     const ResolveOptions *options = nullptr);

} // namespace rcli::model_ref

#endif // RCLI_CATALOG_MODEL_REF_H
