// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// `RunAnywhere` public STT surface — model-id-only helpers that resolve
// the on-disk path from the model catalog and forward to the canonical
// `loadSTT(_:modelPath:)` entry point.

import Foundation
import CRACommonsCore

@MainActor
public extension RunAnywhere {

    /// Currently-loaded STT model descriptor, or nil when no STT model
    /// is loaded. Resolved from the global catalog via
    /// `SessionRegistry.currentSTTModelId`.
    static var currentSTTModel: ModelInfo? {
        let id = SessionRegistry.currentSTTModelId
        guard !id.isEmpty else { return nil }
        return ModelCatalog.model(id: id)
    }

    /// Load an STT model by id. The catalog is consulted for the
    /// on-disk path; the session is stored on `SessionRegistry.currentSTT`
    /// for subsequent `transcribe(...)` calls.
    static func loadSTTModel(_ modelId: String) async throws {
        guard let info = ModelCatalog.model(id: modelId) else {
            throw RunAnywhereError.invalidArgument(
                "STT model not registered: \(modelId)")
        }
        var path: UnsafeMutablePointer<CChar>?
        defer { if let p = path { ra_file_string_free(p) } }
        let rc = info.framework.rawValue.withCString { fw in
            modelId.withCString { mid in
                ra_file_model_path(fw, mid, &path)
            }
        }
        guard rc == RA_OK, let raw = path else {
            throw RunAnywhereError.invalidArgument(
                "could not resolve STT model path: \(modelId)")
        }
        let resolved = info.localPathString ?? String(cString: raw)
        try loadSTT(modelId, modelPath: resolved, format: info.framework.modelFormat)
        SessionRegistry.currentSTTModelId = modelId
    }

    /// Unload the current STT session. Idempotent.
    static func unloadSTTModel() async {
        SessionRegistry.currentSTT = nil
        SessionRegistry.currentSTTModelId = ""
    }
}
