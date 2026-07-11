/**
 * @file hf_resolver.h
 * @brief Internal Hugging Face reference resolver (NOT part of the public ABI).
 *
 * Resolves Ollama/llama.cpp-style Hugging Face references into concrete
 * downloadable file sets:
 *
 *   hf.co/{org}/{repo}              -> default quant (Q4_K_M -> Q8_0 -> first)
 *   hf.co/{org}/{repo}:{quant}      -> quant tag matched against GGUF basenames
 *   hf.co/{org}/{repo}:{file.gguf}  -> exact filename match
 *   hf.co/{org}/{repo}/{path/file}  -> explicit file (normalized to /resolve/)
 *   hf.co/{org}/{repo}/{manifest}   -> with a device arch, a logical folder
 *                                      bundle ref under {arch}/{manifest}
 *   hf.co/{org}/{repo}/{subdir}     -> folder bundle: EVERY file under the
 *                                      subfolder (see resolve_repo_folder)
 *   hf://..., huggingface.co/...    -> same grammar, alternate prefixes
 *
 * Repo resolution lists files through the HF Hub tree API
 * (`api/models/{org}/{repo}/tree/main?recursive=true`) over the registered
 * platform HTTP transport, records per-file size + SHA-256 (`lfs.oid`), pairs
 * the mmproj sibling for VLM repos, and expands sharded
 * `-NNNNN-of-NNNNN.gguf` sets. Consumed by rac_register_model_from_url_proto
 * so every SDK + the CLI inherit HF ingestion through the existing ABI.
 */

#ifndef RAC_INFRA_MODEL_MANAGEMENT_HF_RESOLVER_H
#define RAC_INFRA_MODEL_MANAGEMENT_HF_RESOLVER_H

#include <cstdint>
#include <string>
#include <vector>

#include "rac/core/rac_error.h"
#include "rac/infrastructure/model_management/rac_bundle_policy.h"

namespace rac::infra::model_management::hf {

struct ResolvedFile {
    std::string url;       // https://huggingface.co/{org}/{repo}/resolve/main/{path}
    std::string filename;  // storage path inside the model folder; basename for
                           // GGUF resolution, subfolder-relative (may contain
                           // '/') for folder-bundle resolution
    int64_t size_bytes = 0;
    std::string sha256;  // lowercase hex from lfs.oid; empty when not LFS-backed
    bool is_vision_projector = false;
};

struct ResolvedModel {
    std::string model_id;             // filesystem-safe id, e.g. "qwen3-0.6b-gguf-q4_k_m"
    std::string display_name;         // e.g. "unsloth/Qwen3-0.6B-GGUF (Q4_K_M)"
    std::vector<ResolvedFile> files;  // primary (or shard set) first, mmproj last
    bool has_vision_projector = false;
    int64_t total_size_bytes = 0;
};

/** True when @p ref uses one of the recognized Hugging Face prefixes. */
bool is_hf_ref(const std::string& ref);

/**
 * True when @p ref points INSIDE a repo at a folder rather than a file: the
 * in-repo path's last segment has no extension (`hf.co/org/repo/v81`, which
 * as a file ref would just 404). When @p manifest_leaf_ext is non-NULL (the
 * registered bundle policy's manifest extension, e.g. ".json"), a leaf with
 * that extension also counts — the ref then names the bundle's manifest and
 * the PARENT folder is the bundle root
 * (`hf.co/org/repo/v79/lfm2-5-350m-2048.json`). Full /resolve/ or /blob/
 * URLs are never folder refs.
 */
bool is_folder_ref(const std::string& ref, const char* manifest_leaf_ext);

/**
 * Normalize an explicit-file HF ref (org/repo/path/file or an hf-hosted
 * /resolve/ URL) to a direct https download URL. Returns "" when @p ref is a
 * repo-level reference that needs full resolution instead.
 */
std::string normalize_explicit_file_ref(const std::string& ref);

/**
 * Resolve a repo-level ref (org/repo[:tag]) by listing the repo and selecting
 * GGUF files. Requires a registered HTTP transport. On failure returns an
 * error code and a human-actionable message in @p error_message.
 */
rac_result_t resolve_repo(const std::string& ref, ResolvedModel* out, std::string* error_message);

/**
 * Resolve a folder ref (see is_folder_ref) into the COMPLETE file set under
 * that subfolder: every tree entry below it (dotfiles and *.md excluded),
 * `filename` carrying the path RELATIVE to the subfolder (nested paths like
 * `host_weights/x.bin` preserved), plus the repo-root `config.json` appended
 * as a trailing companion when present (the Hub's download-counter query
 * file). The primary file — ordered first — is the manifest named by the ref
 * when given, else the alphabetically-first top-level file matching
 * @p is_manifest (the registered bundle policy's predicate — commons carries
 * no per-framework manifest heuristics). @p manifest_leaf_ext splits a
 * manifest-leaf ref into subdir + pinned primary. Requires a registered HTTP
 * transport.
 */
rac_result_t resolve_repo_folder(const std::string& ref, const char* manifest_leaf_ext,
                                 rac_bundle_manifest_predicate_fn is_manifest, ResolvedModel* out,
                                 std::string* error_message);

/**
 * Pure resolution core behind resolve_repo_folder, exposed for offline tests:
 * resolves @p tree_json_body (an HF tree-API response) for
 * `org/repo/<subdir>` with optional @p primary_rel (manifest path relative to
 * @p subdir) and optional @p is_manifest predicate. No network access.
 */
rac_result_t resolve_folder_from_tree_json(const std::string& tree_json_body,
                                           const std::string& org, const std::string& repo,
                                           const std::string& subdir,
                                           const std::string& primary_rel,
                                           rac_bundle_manifest_predicate_fn is_manifest,
                                           ResolvedModel* out, std::string* error_message);

}  // namespace rac::infra::model_management::hf

#endif  // RAC_INFRA_MODEL_MANAGEMENT_HF_RESOLVER_H
