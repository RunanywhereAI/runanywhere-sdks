/**
 * @file llamacpp_logging.h
 * @brief Internal: routes ggml/llama.cpp's log sink through commons.
 *
 * ggml_log_set() (declared in the vendored ggml.h, which is a build-time
 * dependency and never shipped in the kit) is a single process-global sink,
 * not one per model/handle. This installs the routing exactly once no matter
 * how many of the four llama.cpp-backed capabilities (LLM, VLM, rerank,
 * embeddings) get used, and in what order.
 *
 * The public surface (rac_llamacpp_set_log_callback(), letting a kit consumer
 * install its own callback) lives in
 * core/include/rac/backends/rac_llm_llamacpp.h.
 */

#ifndef RAC_LLAMACPP_LOGGING_H
#define RAC_LLAMACPP_LOGGING_H

namespace runanywhere::llamacpp_internal {

/**
 * Installs the ggml -> commons log routing via llama_log_set() (which itself
 * calls ggml_log_set() — see llama-impl.cpp) on first call; a no-op on every
 * call after that. Every entry point that calls llama_backend_init() calls
 * this right alongside it, so ggml/Metal init spam is gated behind the SDK
 * logger regardless of which capability initializes the shared llama.cpp
 * backend first.
 */
void ensure_llamacpp_ggml_log_routed();

}  // namespace runanywhere::llamacpp_internal

#endif  // RAC_LLAMACPP_LOGGING_H
