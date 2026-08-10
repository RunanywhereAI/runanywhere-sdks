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
    /// Pass `nil` to return to the environment lookup: `HF_TOKEN`, then
    /// `$HF_TOKEN_PATH`, then `$HF_HOME/token`, then `~/.cache/huggingface/token`
    /// — the order `huggingface_hub` uses, so `hf auth login` is honoured.
    /// Pass an empty string to clear the in-memory override and disable that
    /// fallback.
    ///
    /// There is no `RAC_HF_TOKEN`; this doc named one for a while, but commons has
    /// only ever read `HF_TOKEN`.
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
    /// `nil` means "never set", which is where the environment fallback applies;
    /// `.some("")` means explicitly cleared, which suppresses it.
    private static let token = OSAllocatedUnfairLock<String?>(initialState: nil)

    static func store(_ value: String?) {
        token.withLock { $0 = value }
    }

    /// The environment and token-file fallbacks commons resolves, mirrored here.
    ///
    /// Without these the background path saw *only* a token handed to
    /// `setHfToken`, while commons additionally resolved the environment — so a
    /// developer authenticated the ordinary way (`hf auth login`, which writes a
    /// token file) got 401s on background-eligible gated downloads and successes
    /// everywhere else. Order matches `rac::http::env_token` and
    /// huggingface_hub: `HF_TOKEN`, then `$HF_TOKEN_PATH`, then `$HF_HOME/token`,
    /// then `~/.cache/huggingface/token`.
    ///
    /// Resolved once, as commons does, so both paths agree for the process
    /// lifetime instead of diverging when a file changes underneath them.
    private static let environmentToken: String? = resolveEnvironmentToken()

    private static func resolveEnvironmentToken() -> String? {
        let environment = ProcessInfo.processInfo.environment
        if let direct = environment["HF_TOKEN"], let value = normalized(direct) {
            return value
        }
        let candidatePaths = [
            environment["HF_TOKEN_PATH"],
            environment["HF_HOME"].map { "\($0)/token" },
            environment["HOME"].map { "\($0)/.cache/huggingface/token" }
        ]
        for case let path? in candidatePaths where !path.isEmpty {
            if let value = readTokenFile(path) {
                return value
            }
        }
        return nil
    }

    private static func readTokenFile(_ path: String) -> String? {
        guard let contents = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        return normalized(contents)
    }

    /// Trimmed, or `nil` when nothing usable is left — commons trims the same way,
    /// and a token file always carries a trailing newline.
    private static func normalized(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    /// The `Authorization` header value for `url`, or `nil` when the token must
    /// not be attached.
    ///
    /// Mirrors `rac::http::hf_bearer_for_url` over `rac::http::current_token`:
    /// an explicitly stored token wins outright — including an empty one, which
    /// is a deliberate opt-out and must not silently re-enable the environment.
    static func bearer(for url: URL) -> String? {
        guard isHuggingFaceHost(url) else { return nil }
        if let explicit = token.withLock({ $0 }) {
            return explicit.isEmpty ? nil : "Bearer \(explicit)"
        }
        guard let fallback = environmentToken else { return nil }
        return "Bearer \(fallback)"
    }

    /// Exact-host match over https, matching commons' `is_hf_host`.
    private static func isHuggingFaceHost(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", let host = url.host?.lowercased() else {
            return false
        }
        return host == "huggingface.co" || host == "hf.co"
    }
}
