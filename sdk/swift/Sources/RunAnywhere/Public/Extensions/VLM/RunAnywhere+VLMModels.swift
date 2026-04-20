// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// ModelInfo-centric VLM entry points + a sample-app-shaped
// `processImageStream(image:prompt:maxTokens:)` wrapper.

import Foundation
import CRACommonsCore

@MainActor
public extension RunAnywhere {

    /// Load a VLM by resolved `ModelInfo`. Convenience on top of the
    /// explicit `loadVLMModel(_:modelPath:format:)` form.
    static func loadVLMModel(_ info: ModelInfo) async throws {
        var path: UnsafeMutablePointer<CChar>?
        defer { if let p = path { ra_file_string_free(p) } }
        let rc = info.framework.rawValue.withCString { fw in
            info.id.withCString { mid in
                ra_file_model_path(fw, mid, &path)
            }
        }
        let resolved: String
        if rc == RA_OK, let raw = path {
            resolved = info.localPathString ?? String(cString: raw)
        } else if let local = info.localPathString {
            resolved = local
        } else {
            throw RunAnywhereError.invalidArgument(
                "could not resolve VLM model path: \(info.id)")
        }
        try loadVLMModel(info.id, modelPath: resolved,
                         format: info.framework.modelFormat)
    }

    /// Streaming convenience that mirrors main's sample shape:
    ///     for try await tok in RunAnywhere.processImageStream(
    ///         image: img, prompt: "Describe", maxTokens: 256) { … }
    static func processImageStream(image: VLMImage, prompt: String,
                                    maxTokens: Int = 256)
        -> AsyncThrowingStream<VLMSession.Token, Error>
    {
        processImageStream(image, prompt: prompt,
                            options: VLMGenerationOptions(maxTokens: maxTokens))
    }
}
