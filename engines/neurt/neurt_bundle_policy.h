/**
 * @file neurt_bundle_policy.h
 * @brief NeuRT's bundle-resolution policy — "which file in an ANE bundle is the manifest".
 *
 * The Apple peer of `engines/qhexrt/qhexrt_bundle_policy.h`, and it exists for the same reason:
 * without a registered policy, commons cannot pick a primary file inside an HF folder and a
 * one-line registration fails outright with
 *
 *   cannot choose a primary file under '<dir>' in <org>/<repo> — name the manifest explicitly
 *   in the ref, or register the engine backend for this framework first (it installs the bundle
 *   policy)
 *
 * while naming the manifest explicitly degrades to a SINGLE-FILE download of the manifest JSON
 * (measured: 160 bytes, framework unset) — so neither ref form worked before this policy existed.
 * That is why the Android/HNPU catalog can register an NPU bundle by plain URL and the Apple
 * catalog could not.
 *
 * Header-only, mirroring the QHexRT policy, so it needs no new source file and the commons offline
 * test can include it directly.
 *
 * ── The Apple divergence: NO variant resolver ────────────────────────────────────────────────
 * QHexRT resolves a per-architecture subfolder (v75/v79/v81) because a QNN context binary is
 * arch-pinned. Apple has no compile target at all: ONE `.mlpackage` set runs on every Apple device
 * (rule 61), so `resolve_variant` is deliberately NULL. A precision folder such as `lut8_g32_c6/`
 * is chosen by the CATALOG ENTRY, not probed at runtime — it is a quality/size choice, not a
 * hardware one, and inferring it would silently pick a bundle the caller did not ask for.
 */

#ifndef ENGINES_NEURT_NEURT_BUNDLE_POLICY_H
#define ENGINES_NEURT_NEURT_BUNDLE_POLICY_H

#include <ctype.h>
#include <stdint.h>
#include <string.h>

#include "rac/infrastructure/model_management/rac_bundle_policy.h"

#ifdef __cplusplus
extern "C" {
#endif

/** True when `basename` ends with `suffix` (case-sensitive; our names are generated lowercase). */
static inline int neurt_has_suffix(const char* basename, const char* suffix) {
    const size_t n = strlen(basename);
    const size_t m = strlen(suffix);
    return m <= n && strcmp(basename + (n - m), suffix) == 0;
}

/**
 * JSON files in an ANE bundle that are never the manifest.
 *
 * `*.iodesc.json` is the one that matters and it is UNIQUE TO THIS BACKEND: the bundle ships one
 * I/O-descriptor sidecar PER GRAPH (7 of them for LFM2.5-2.6B), all top-level, all `.json`. A
 * QHexRT-style "any top-level .json that is not tokenizer.json" predicate would match a sidecar
 * and resolve the bundle to the wrong primary file — alphabetically, an `..._chunk0.iodesc.json`
 * sorts BEFORE most manifest names, so it would win.
 *
 * PRECISION.json / GATE_P.json are provenance written by the publish step and are likewise not
 * manifests.
 */
static inline int neurt_is_aux_json(const char* basename) {
    return neurt_has_suffix(basename, ".iodesc.json") || strcmp(basename, "tokenizer.json") == 0 ||
           strcmp(basename, "tokenizer_config.json") == 0 || strcmp(basename, "config.json") == 0 ||
           strcmp(basename, "generation_config.json") == 0 ||
           strcmp(basename, "PRECISION.json") == 0 || strcmp(basename, "GATE_P.json") == 0;
}

/**
 * Bundle-manifest predicate: a TOP-LEVEL (no '/'), case-insensitive `.json` that is not aux.
 *
 * The no-'/' guard is load-bearing here for a second reason beyond QHexRT's: a `.mlpackage` is a
 * DIRECTORY, and every one of them contains `Data/com.apple.CoreML/...` plus its own
 * `Manifest.json`. Without the guard those nested files are candidates.
 */
static inline rac_bool_t neurt_is_bundle_manifest(const char* relative_path) {
    if (relative_path == NULL || strchr(relative_path, '/') != NULL) {
        return RAC_FALSE;
    }
    const size_t len = strlen(relative_path);
    if (len < 6) { /* shortest possible: "x.json" */
        return RAC_FALSE;
    }
    const char* ext = relative_path + len - 5;
    for (int i = 0; i < 5; ++i) {
        if (tolower((unsigned char)ext[i]) != ".json"[i]) {
            return RAC_FALSE;
        }
    }
    return neurt_is_aux_json(relative_path) ? RAC_FALSE : RAC_TRUE;
}

/** The process-lifetime NeuRT bundle policy (function-local static). */
static inline const rac_bundle_policy_t* neurt_bundle_policy(void) {
    static const rac_bundle_policy_t policy = {
        /* .struct_size               = */ (uint32_t)sizeof(rac_bundle_policy_t),
        /* .framework                 = */ RAC_FRAMEWORK_COREML,
        /* .model_format              = */ RAC_MODEL_FORMAT_COREML,
        /* .manifest_extension        = */ ".json",
        /* .manifest_leaf_names_bundle= */ RAC_TRUE,
        /* .is_bundle_manifest        = */ neurt_is_bundle_manifest,
        /* .resolve_variant           = */ {NULL}, /* one portable bundle — see the header note */
        /* .reserved_1                = */ 0,
    };
    return &policy;
}

#ifdef __cplusplus
}
#endif

#endif  // ENGINES_NEURT_NEURT_BUNDLE_POLICY_H
