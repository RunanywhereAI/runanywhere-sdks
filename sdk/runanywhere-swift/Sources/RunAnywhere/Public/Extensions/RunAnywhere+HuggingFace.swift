//
//  RunAnywhere+HuggingFace.swift
//  RunAnywhere SDK
//

import CRACommons
import Foundation
import os

public extension RunAnywhere {
    /// Set the Hugging Face bearer token used by model downloads.
    ///
    /// Pass `nil` to return to `RAC_HF_TOKEN` / `HF_TOKEN` environment lookup.
    /// Pass an empty string to clear the in-memory override and disable env fallback.
    static func setHfToken(_ token: String?) {
        HuggingFaceAuth.store(token)
        guard let token else {
            rac_http_hf_token_set(nil)
            return
        }
        token.withCString { tokenPtr in
            rac_http_hf_token_set(tokenPtr)
        }
    }
}

/// Swift-side mirror of the token commons holds, for the one transfer path that
/// does not go through the commons HTTP dispatcher.
///
/// ## Why a mirror is necessary
///
/// Commons owns the canonical token and deliberately never hands it back: the C
/// ABI exposes `rac_http_hf_token_set` and `rac_http_hf_token_is_configured`,
/// and nothing to read the value, so the token cannot leak through the boundary
/// or into a log. Every request that goes through `rac_http_request_*` therefore
/// gets its `Authorization` header attached inside
/// `rac_http_client_default.cpp` (`prepare_request` → `hf_bearer_for_url`), and
/// the caller never sees or needs the token.
///
/// `BackgroundDownloadCoordinator` is the exception. It runs
/// `URLSession.downloadTask` directly — that is the entire point, because only a
/// background-configured URLSession survives app suspension — so it never
/// reaches the commons dispatcher and no header is attached for it. A gated
/// Hugging Face model therefore returned 401 on the *default* download path
/// while the same model downloaded fine on the archive/unknown-size path, which
/// is a difference no caller can see or explain.
///
/// So the token is retained here as well, and the eligibility rules are
/// reproduced exactly rather than approximated:
/// - **https only**, and the host must be **exactly** `huggingface.co` or
///   `hf.co`. Subdomains are excluded on purpose: a CDN/LFS redirect target must
///   never receive the bearer token.
/// - A caller-supplied `Authorization` header is never overridden.
///
/// Mirrored in the SDK rather than in the app for the obvious reason: an
/// example app must not know how model downloads authenticate.
enum HuggingFaceAuth {
    /// `nil` means "never set" (env fallback applies inside commons, which the
    /// Swift side cannot read); `.some("")` means explicitly cleared.
    private static let token = OSAllocatedUnfairLock<String?>(initialState: nil)

    static func store(_ value: String?) {
        token.withLock { $0 = value }
    }

    /// The `Authorization` header value for `url`, or `nil` when the token must
    /// not be attached.
    ///
    /// Mirrors `rac::http::hf_bearer_for_url`.
    static func bearer(for url: URL) -> String? {
        guard isHuggingFaceHost(url) else { return nil }
        guard let value = token.withLock({ $0 }), !value.isEmpty else { return nil }
        return "Bearer \(value)"
    }

    /// Exact-host match over https, matching commons' `is_hf_host`.
    private static func isHuggingFaceHost(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased() else {
            return false
        }
        return host == "huggingface.co" || host == "hf.co"
    }
}
