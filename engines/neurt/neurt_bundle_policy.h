/**
 * @file neurt_bundle_policy.h
 * @brief CoreML/ANE folder-bundle resolution for `runanywhere/*_ANE` repos.
 *
 * ANE LLM bundles are directories of `.mlpackage` graphs plus a root plan JSON
 * (e.g. `qwen3-0-6b.json`) and host embed weights. Without this policy,
 * `registerModel(..., framework: .coreml, url: hf.co/..._ANE)` falls into the
 * GGUF single-file path and cannot download the private NeuRT trees.
 */

#ifndef ENGINES_NEURT_NEURT_BUNDLE_POLICY_H
#define ENGINES_NEURT_NEURT_BUNDLE_POLICY_H

#include <stdint.h>
#include <string.h>

#include "rac/infrastructure/model_management/rac_bundle_policy.h"

#ifdef __cplusplus
extern "C" {
#endif

static inline rac_bool_t neurt_is_bundle_manifest(const char* relative_path) {
    if (relative_path == NULL) {
        return RAC_FALSE;
    }
    // Prefer the root plan JSON (`qwen3-0-6b.json`), not tokenizer / nested.
    if (strchr(relative_path, '/') != NULL) {
        return RAC_FALSE;
    }
    const size_t len = strlen(relative_path);
    if (len < 6 || strcmp(relative_path + (len - 5), ".json") != 0) {
        return RAC_FALSE;
    }
    if (strcmp(relative_path, "tokenizer.json") == 0 ||
        strcmp(relative_path, "vocab.json") == 0 ||
        strcmp(relative_path, "special_tokens_map.json") == 0 ||
        strcmp(relative_path, "iodesc.json") == 0) {
        return RAC_FALSE;
    }
    // Skip sidecar iodecs named `*_iodesc.json` / `*.iodesc.json`.
    if (strstr(relative_path, "iodesc") != NULL) {
        return RAC_FALSE;
    }
    return RAC_TRUE;
}

static inline const rac_bundle_policy_t* neurt_bundle_policy(void) {
    static const rac_bundle_policy_t policy = {
        /* .struct_size                = */ (uint32_t)sizeof(rac_bundle_policy_t),
        /* .framework                  = */ RAC_FRAMEWORK_COREML,
        /* .model_format               = */ RAC_MODEL_FORMAT_MLPACKAGE,
        /* .manifest_extension         = */ ".json",
        /* .manifest_leaf_names_bundle = */ RAC_FALSE,
        /* .is_bundle_manifest         = */ neurt_is_bundle_manifest,
        /* .resolve_variant            = */ {NULL},
        /* .reserved_1                 = */ 0,
    };
    return &policy;
}

#ifdef __cplusplus
}
#endif

#endif  // ENGINES_NEURT_NEURT_BUNDLE_POLICY_H
