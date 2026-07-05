/**
 * @file rac_bundle_policy.h
 * @brief Per-framework model-bundle resolution policy registry.
 *
 * Some engines load "folder bundles" — a directory of files whose entry point
 * is a framework-specific manifest (e.g. a JSON plan) rather than a single
 * model file. Commons can resolve such bundles generically (list a remote
 * folder, download every file, register a multi-file model), but WHICH file
 * is the manifest, and what model format the bundle carries, is engine
 * knowledge that must not be hardcoded in commons.
 *
 * This header defines the seam: an engine registers a small, static
 * `rac_bundle_policy_t` for its framework (typically inside its
 * `rac_backend_<engine>_register()`, before any model registration), and the
 * generic resolution paths (`rac_register_model_from_url_proto`'s Hugging
 * Face folder branch) consult the registry by framework. Commons itself
 * contains only this mechanism — zero framework-specific policy.
 *
 * Lifetime: the registry stores the pointer; the policy (and its predicate)
 * must live for the process lifetime — a function-local static or plugin
 * .rodata/.text, the same contract as plugin vtables. All entry points are
 * thread-safe.
 */

#ifndef RAC_INFRASTRUCTURE_MODEL_MANAGEMENT_RAC_BUNDLE_POLICY_H
#define RAC_INFRASTRUCTURE_MODEL_MANAGEMENT_RAC_BUNDLE_POLICY_H

#include <stdint.h>

#include "rac/core/rac_types.h"
#include "rac/infrastructure/model_management/rac_model_types.h"

#ifdef __cplusplus
extern "C" {
#endif

/**
 * Predicate over a bundle-relative path ("whisper-small.json",
 * "host_weights/w1.bin"): RAC_TRUE when the file is the bundle's manifest /
 * primary entry point. Must be thread-safe and non-blocking (called during
 * remote resolution; filename-only — no file contents are available).
 */
typedef rac_bool_t (*rac_bundle_manifest_predicate_fn)(const char* relative_path);

typedef struct rac_bundle_policy {
    /** = sizeof(rac_bundle_policy_t); registration rejects a mismatch. */
    uint32_t struct_size;

    /** Registry key (the C enum, e.g. RAC_FRAMEWORK_QHEXRT — NOT the proto value). */
    rac_inference_framework_t framework;

    /**
     * Model format stamped on folder-bundle registrations for this framework;
     * RAC_MODEL_FORMAT_UNSPECIFIED leaves the format unset.
     */
    rac_model_format_t model_format;

    /** Manifest filename extension incl. dot (e.g. ".json"); NULL = none. */
    const char* manifest_extension;

    /**
     * RAC_TRUE when a folder ref may name the manifest as its leaf
     * (`.../<dir>/<manifest><ext>` = "the bundle at <dir>/, pinned to
     * <manifest>"). RAC_FALSE keeps extension-leaf refs meaning a plain
     * single-file download.
     */
    rac_bool_t manifest_leaf_names_bundle;

    /** Manifest predicate; NULL falls back to matching manifest_extension only. */
    rac_bundle_manifest_predicate_fn is_bundle_manifest;

    uint64_t reserved_0; /**< Must be 0. */
    uint64_t reserved_1; /**< Must be 0. */
} rac_bundle_policy_t;

/**
 * Registers (or replaces) the bundle policy for `policy->framework`.
 * @return RAC_SUCCESS; RAC_ERROR_INVALID_ARGUMENT on NULL/UNKNOWN framework;
 *         RAC_ERROR_ABI_VERSION_MISMATCH when struct_size differs.
 */
RAC_API rac_result_t rac_bundle_policy_register(const rac_bundle_policy_t* policy);

/** Removes the policy for @p framework (no-op when absent). */
RAC_API rac_result_t rac_bundle_policy_unregister(rac_inference_framework_t framework);

/** @return the registered policy for @p framework, or NULL. */
RAC_API const rac_bundle_policy_t* rac_bundle_policy_find(rac_inference_framework_t framework);

#ifdef __cplusplus
}
#endif

#endif  // RAC_INFRASTRUCTURE_MODEL_MANAGEMENT_RAC_BUNDLE_POLICY_H
