//
//  RunAnywhere+HuggingFace.swift
//  RunAnywhere SDK
//

import CRACommons

public extension RunAnywhere {
    /// Set the Hugging Face bearer token used by commons model downloads.
    ///
    /// Pass `nil` to return to `RAC_HF_TOKEN` / `HF_TOKEN` environment lookup.
    /// Pass an empty string to clear the in-memory override and disable env fallback.
    static func setHfToken(_ token: String?) {
        guard let token else {
            rac_http_hf_token_set(nil)
            return
        }
        token.withCString { tokenPtr in
            rac_http_hf_token_set(tokenPtr)
        }
    }
}
