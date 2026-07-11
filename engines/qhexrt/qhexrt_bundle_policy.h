/**
 * @file qhexrt_bundle_policy.h
 * @brief QHexRT's bundle-resolution policy — the single source of truth for
 *        "which file in an HNPU bundle is the manifest".
 *
 * Header-only so it compiles in routable AND stub builds with no new sources,
 * and so the commons offline test can include it directly. Consumed by:
 *  - rac_backend_qhexrt_register.cpp — registers the policy with commons'
 *    generic bundle-policy registry, enabling one-line HF folder
 *    registrations (`registerModel(url="hf.co/org/<m>_HNPU/v81",
 *    framework=QHEXRT, ...)`) with zero QHexRT knowledge in commons.
 *  - qhexrt_session.cpp — reuses qhexrt_is_aux_json for its on-disk manifest
 *    selection, so remote resolution and device-side loading agree.
 *
 * A QHexRT bundle folder holds one (or more) top-level `.json` manifests
 * (carrying `schema_version`/`plan`/`dsp_arch`) next to aux JSON sidecars
 * (tokenizer/config/...). Remote resolution is filename-only — content
 * sniffing is impossible before download — so multi-manifest folders resolve
 * to the alphabetically-first manifest unless the catalog ref pins one
 * explicitly (`hf.co/org/repo/v79/<manifest>.json`).
 */

#ifndef ENGINES_QHEXRT_QHEXRT_BUNDLE_POLICY_H
#define ENGINES_QHEXRT_QHEXRT_BUNDLE_POLICY_H

#include <ctype.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

#include "rac/infrastructure/model_management/rac_bundle_policy.h"
#include "rac/qhexrt/rac_qhexrt.h"

#ifdef __cplusplus
extern "C" {
#endif

/** JSON sidecars that are never a QHexRT manifest. */
static inline int qhexrt_is_aux_json(const char* basename) {
    return strcmp(basename, "tokenizer.json") == 0 ||
           strcmp(basename, "tokenizer_config.json") == 0 ||
           strcmp(basename, "config.json") == 0 ||
           strcmp(basename, "generation_config.json") == 0 ||
           strcmp(basename, "preprocessor_config.json") == 0;
}

/**
 * Bundle-manifest predicate: a TOP-LEVEL (no '/'), case-insensitive `.json`
 * file that is not an aux sidecar.
 */
static inline rac_bool_t qhexrt_is_bundle_manifest(const char* relative_path) {
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
    /* Aux names are lowercase by convention; compare the path as-is. */
    return qhexrt_is_aux_json(relative_path) ? RAC_FALSE : RAC_TRUE;
}

/** Select the current device's architecture folder for generic registration. */
static inline rac_result_t qhexrt_resolve_bundle_variant(char* out_variant, size_t out_variant_size,
                                                         char* out_error_message,
                                                         size_t out_error_message_size) {
    if (out_variant == NULL || out_variant_size == 0) {
        return RAC_ERROR_INVALID_ARGUMENT;
    }
    out_variant[0] = '\0';
    if (out_error_message != NULL && out_error_message_size > 0) {
        out_error_message[0] = '\0';
    }

    rac_qhexrt_device_info_t device;
    const rac_result_t probe_rc = rac_qhexrt_probe(&device);
    if (probe_rc != RAC_SUCCESS) {
        if (out_error_message != NULL && out_error_message_size > 0) {
            (void)snprintf(out_error_message, out_error_message_size,
                           "QHexRT NPU probe failed (%d)", probe_rc);
        }
        return probe_rc;
    }
    if (device.supported != RAC_TRUE) {
        if (out_error_message != NULL && out_error_message_size > 0) {
            (void)snprintf(out_error_message, out_error_message_size,
                           "QHexRT is unavailable on Hexagon %s",
                           rac_qhexrt_arch_name(device.hexagon_arch));
        }
        return RAC_ERROR_BACKEND_UNAVAILABLE;
    }

    const char* arch_name = rac_qhexrt_arch_name(device.hexagon_arch);
    const int written = snprintf(out_variant, out_variant_size, "%s", arch_name);
    if (written < 0 || (size_t)written >= out_variant_size) {
        out_variant[0] = '\0';
        return RAC_ERROR_BUFFER_TOO_SMALL;
    }
    return RAC_SUCCESS;
}

/** The process-lifetime QHexRT bundle policy (function-local static). */
static inline const rac_bundle_policy_t* qhexrt_bundle_policy(void) {
    static const rac_bundle_policy_t policy = {
        /* .struct_size               = */ (uint32_t)sizeof(rac_bundle_policy_t),
        /* .framework                 = */ RAC_FRAMEWORK_QHEXRT,
        /* .model_format              = */ RAC_MODEL_FORMAT_QNN_CONTEXT,
        /* .manifest_extension        = */ ".json",
        /* .manifest_leaf_names_bundle= */ RAC_TRUE,
        /* .is_bundle_manifest        = */ qhexrt_is_bundle_manifest,
        /* .resolve_variant           = */ {qhexrt_resolve_bundle_variant},
        /* .reserved_1                = */ 0,
    };
    return &policy;
}

#ifdef __cplusplus
}
#endif

#endif  // ENGINES_QHEXRT_QHEXRT_BUNDLE_POLICY_H
