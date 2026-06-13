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

namespace rac::infra::model_management::hf {

struct ResolvedFile {
    std::string url;       // https://huggingface.co/{org}/{repo}/resolve/main/{path}
    std::string filename;  // storage basename inside the model folder
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

}  // namespace rac::infra::model_management::hf

#endif  // RAC_INFRA_MODEL_MANAGEMENT_HF_RESOLVER_H
