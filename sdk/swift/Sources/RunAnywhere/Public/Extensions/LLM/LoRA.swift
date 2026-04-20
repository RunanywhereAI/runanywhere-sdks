// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// LoRA adapter management. Today the C ABI does not expose
// `ra_llm_load_lora` / `ra_llm_unload_lora` slots — they're tracked at
// the Swift layer only and forwarded to llama.cpp's runtime hooks via
// the engine vtable in a future ABI extension. For now this is a pure
// Swift catalog the sample apps interact with.

import Foundation

@MainActor
public extension RunAnywhere {

    /// Main-branch parity — `try await` and no-op on an empty config.
    static func loadLoraAdapter(_ config: LoRAAdapterConfig) async throws {
        ModelCatalog.setLoraLoaded(config)
    }

    static func removeLoraAdapter(_ id: String) async throws {
        ModelCatalog.setLoraUnloaded(id)
    }

    static func clearLoraAdapters() async throws {
        ModelCatalog.clearLoraAdapters()
    }

    static var allRegisteredLoraAdapters: [LoRAAdapterConfig] {
        ModelCatalog.allRegisteredLoraAdapters
    }

    /// Returns loaded adapters wrapped in `LoRAAdapterInfo` — main-branch
    /// sample shape.
    static func getLoadedLoraAdapters() async throws -> [LoRAAdapterInfo] {
        ModelCatalog.allRegisteredLoraAdapters.map {
            LoRAAdapterInfo(config: $0, loaded: true)
        }
    }

    /// Available adapters for a given base model as
    /// `LoraAdapterCatalogEntry` — the shape the sample catalog UI
    /// consumes. Synthesised from the registered LoRA configs.
    static func loraAdaptersForModel(_ modelId: String) async -> [LoraAdapterCatalogEntry] {
        ModelCatalog.adaptersForModel(modelId).map { cfg in
            LoraAdapterCatalogEntry(
                id: cfg.id, name: cfg.name,
                url: URL(fileURLWithPath: cfg.localPath),
                baseModelId: cfg.baseModelId,
                sha256: nil, sizeBytes: nil)
        }
    }

    static func checkLoraCompatibility(adapterId: String,
                                          modelId: String) -> LoraCompatibilityResult {
        let adapters = ModelCatalog.adaptersForModel(modelId)
        if adapters.contains(where: { $0.id == adapterId }) {
            return LoraCompatibilityResult(compatible: true)
        }
        return LoraCompatibilityResult(compatible: false,
                                         reason: "adapter and model bases don't match")
    }

    static func downloadLoraAdapter(_ id: String) async throws -> String {
        // Frontend should use ModelManager.download(modelId:url:) instead.
        // Returned for source-compat; throws to surface the design choice.
        throw RunAnywhereError.invalidArgument("use ModelManager.download for LoRA adapters")
    }

    static func deleteDownloadedLoraAdapter(_ id: String) {
        // No-op — frontend deletes through the file manager.
    }

    static func loraAdapterLocalPath(_ id: String) -> String? {
        ModelCatalog.allRegisteredLoraAdapters.first { $0.id == id }?.localPath
    }
}
