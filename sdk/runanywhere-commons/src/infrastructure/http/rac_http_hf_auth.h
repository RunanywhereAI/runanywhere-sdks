/**
 * @file rac_http_hf_auth.h
 * @brief Internal helpers for Hugging Face bearer authentication.
 *
 * The public C ABI (`rac_http_hf_token_set` in `rac_http_client.h`) stores
 * one process-wide Hugging Face token. The dispatch sites
 * (`rac_http_client_default.cpp` for native targets,
 * `rac_http_client_emscripten.cpp` for WASM) consult it when composing the
 * request handed to the platform transport, so EVERY commons HTTP path —
 * model downloads, HEAD size preflight, resumable transfers, and the HF Hub
 * tree API used by the repo resolver — authenticates uniformly. Platform
 * SDKs no longer implement their own HF auth.
 *
 * The token is attached as `Authorization: Bearer <token>` ONLY to requests
 * whose URL host is exactly `huggingface.co` or `hf.co` (no subdomains), and
 * never when the caller already supplied an Authorization header. Redirects
 * to CDN hosts are followed by the platform transports, which drop the
 * Authorization header on cross-host redirects per their default policies.
 *
 * NOT part of the public C ABI. C++-only.
 */

#pragma once

#include <string>

namespace rac::http {

/**
 * @brief Bearer value ("Bearer <token>") to attach for @p url, or "" when
 * no header should be added: token unset, non-HF host, or the caller
 * already supplied an Authorization header (@p has_auth_header).
 *
 * Thread-safe. The token comes from `rac_http_hf_token_set`, falling back
 * to the `HF_TOKEN` environment variable captured on first use.
 */
std::string hf_bearer_for_url(const char* url, bool has_auth_header);

/** @brief True when @p url's host is exactly huggingface.co or hf.co. */
bool is_hf_host(const char* url);

}  // namespace rac::http
