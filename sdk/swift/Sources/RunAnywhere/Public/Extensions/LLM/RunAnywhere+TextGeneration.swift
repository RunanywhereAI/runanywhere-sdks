// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// `RunAnywhere` text-generation helpers — capability flags + cancellation.

import Foundation

@MainActor
public extension RunAnywhere {

    /// True when the SDK + currently-loaded engine support streaming
    /// token generation. llama.cpp / ONNX / MetalRT / FoundationModels
    /// all support streaming; sample apps gate their UI on this.
    static var supportsLLMStreaming: Bool { true }

    /// Cancel any in-flight LLM generation. Forwards to the current
    /// LLM session's `cancel()` if one is loaded.
    static func cancelGeneration() async {
        SessionRegistry.currentLLM?.cancel()
    }
}
