// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// Model management C ABI — helpers matching the main-branch
// `rac_model_*` surface. Wraps `core/model_registry/` and
// `core/util/` format detection.
//
// Covers:
//   - Framework × category support matrix
//   - File-format detection from a URL or local path
//   - Category inference from a model id + metadata
//   - Artifact type inference (singleFile / multiFile / archive)
//   - Canonical model paths (delegating to ra_file_model_path)
//   - Compatibility checks against device budget

#ifndef RA_MODEL_H
#define RA_MODEL_H

#include <stddef.h>
#include <stdint.h>

#include "ra_primitives.h"

#ifdef __cplusplus
extern "C" {
#endif

// ---------------------------------------------------------------------------
// Framework × category support matrix
// ---------------------------------------------------------------------------
//
// Pass framework + category as lowercase C-strings matching the enum
// raw-values in `InferenceFramework` / `ModelCategory`. Examples:
//   ra_framework_supports("llamacpp", "llm")      -> 1
//   ra_framework_supports("llamacpp", "stt")      -> 0
//   ra_framework_supports("whisperkit", "stt")    -> 1
//   ra_framework_supports("onnx", "embedding")    -> 1
//
// The matrix is hand-maintained to mirror the main-branch
// `rac_framework_category_supported` table.
uint8_t ra_framework_supports(const char* framework, const char* category);

// Returns a heap-allocated JSON array listing every (framework, category)
// pair that's supported. Free with `ra_model_string_free`.
ra_status_t ra_framework_support_matrix_json(char** out_json);

// ---------------------------------------------------------------------------
// Format detection
// ---------------------------------------------------------------------------
//
// Infers `ra_model_format_t` from the URL / local-path extension.
// Supports .gguf / .onnx / .mlmodelc / .mlpackage / .safetensors /
// .bin / .pte / .pt / .pth / .tflite / .whisperkit / .mlmodel
// archives (.zip, .tar.gz, etc) resolve to UNKNOWN — callers should
// unpack before detecting.
ra_model_format_t ra_model_detect_format(const char* url_or_path);

// Detects the archive format (returns 0 = none, 1 = zip,
// 2 = tar.gz, 3 = tar.bz2, 4 = tar.xz, 5 = tar). Matches the Swift
// `ArchiveFormat` enum raw values + 1.
int32_t ra_model_detect_archive_format(const char* url_or_path);

// Infers `ra_model_category_t` from a model_id or its metadata hints.
// Scans for well-known substrings (e.g. "whisper" -> STT, "stable"
// -> DIFFUSION, "rerank" -> RERANK). Returns UNKNOWN if no match.
ra_model_category_t ra_model_infer_category(const char* model_id);

// Returns 1 if the URL points at an archive file (.zip, .tar.gz, etc).
uint8_t ra_artifact_is_archive(const char* url_or_path);

// Returns 1 if the URL's filename is a directory-based artifact
// (.mlmodelc, .mlpackage).
uint8_t ra_artifact_is_directory(const char* url_or_path);

// ---------------------------------------------------------------------------
// Canonical paths + compatibility
// ---------------------------------------------------------------------------

typedef struct ra_model_compat_t {
    uint8_t is_compatible;
    uint8_t can_run;
    uint8_t can_fit;
    int64_t required_memory_bytes;
    int64_t available_memory_bytes;
    int64_t required_storage_bytes;
    int64_t available_storage_bytes;
} ra_model_compat_t;

// Checks whether `model_id` fits within the given device budget. The
// model must have been registered via `ra_model_register` (or the
// Swift/Kotlin `RunAnywhere.registerModel`). On error, returns a result
// with `is_compatible = 0` and zeros elsewhere.
ra_status_t ra_model_check_compat(const char* model_id,
                                    int64_t available_memory_bytes,
                                    int64_t available_storage_bytes,
                                    ra_model_compat_t* out_result);

// Free a heap-allocated JSON string returned by helpers above.
void ra_model_string_free(char* str);

#ifdef __cplusplus
}  // extern "C"
#endif

#endif  // RA_MODEL_H
