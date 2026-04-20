// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// Hardcoded diffusion-model catalog. Ports the curated list of CoreML
// Stable-Diffusion weights Apple publishes on HuggingFace — used by the
// iOS sample's "Image Generation" tab to seed a default model list
// without hitting the remote catalog API.
//
// Source: `sdk/runanywhere-commons/src/features/diffusion/rac_diffusion_model_registry.cpp`
// (main branch, lines 46-72).

import Foundation
@_exported import RunAnywhere

public enum DiffusionModelCatalog {

    /// Canonical list of Apple-published CoreML Stable-Diffusion models.
    /// Every entry is a directory-based artifact — the whole .mlmodelc
    /// folder tree must be unpacked from the archive.
    public static let entries: [ModelInfo] = [
        makeEntry(
            id: "sd-1.5-palettized",
            name: "Stable Diffusion 1.5 (palettized)",
            hfPath: "apple/coreml-stable-diffusion-v1-5-palettized",
            filename: "coreml-stable-diffusion-v1-5_original_packages.zip",
            memoryMB: 2200),
        makeEntry(
            id: "sd-2.1-palettized",
            name: "Stable Diffusion 2.1 (palettized)",
            hfPath: "apple/coreml-stable-diffusion-2-1-base-palettized",
            filename: "coreml-stable-diffusion-2-1-base_original_packages.zip",
            memoryMB: 2400),
        makeEntry(
            id: "sdxl-base-palettized",
            name: "Stable Diffusion XL base (palettized)",
            hfPath: "apple/coreml-stable-diffusion-xl-base-palettized",
            filename: "coreml-stable-diffusion-xl-base_original_packages.zip",
            memoryMB: 6800),
        makeEntry(
            id: "sdxl-turbo-palettized",
            name: "Stable Diffusion XL Turbo (palettized)",
            hfPath: "apple/coreml-stable-diffusion-xl-turbo-palettized",
            filename: "coreml-stable-diffusion-xl-turbo_original_packages.zip",
            memoryMB: 6500),
    ]

    /// Register all catalog entries with the global model catalog.
    /// Idempotent — subsequent calls overwrite existing entries.
    @MainActor
    public static func registerAll() {
        for info in entries {
            guard let url = info.url else { continue }
            RunAnywhere.registerModel(
                id: info.id,
                name: info.name,
                url: url,
                framework: info.framework,
                category: info.category,
                artifactType: info.artifactType,
                memoryRequirement: info.memoryRequirement,
                supportsThinking: info.supportsThinking,
                modality: info.modality)
        }
    }

    // MARK: - Helpers

    private static func makeEntry(id: String, name: String,
                                    hfPath: String, filename: String,
                                    memoryMB: Int) -> ModelInfo {
        let url = URL(string: "https://huggingface.co/\(hfPath)/resolve/main/\(filename)")!
        return ModelInfo(
            id: id,
            name: name,
            url: url,
            framework: .coreML,
            category: .diffusion,
            artifactType: .archive(.zip, structure: .directoryBased),
            memoryRequirement: Int64(memoryMB) * 1024 * 1024,
            supportsThinking: false,
            modality: Modality.imageGeneration.rawValue)
    }
}
