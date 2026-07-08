//
//  RAModelInfo+LoRAArtifact.swift
//  RunAnywhere SDK
//
//  Shared LoRA artifact classification for model-registry entries.
//

import Foundation

enum LoRAArtifactMetadata {
    static let modelIDPrefix = "lora-adapter:"
    static let adapterTag = "lora-adapter"
    static let legacyAdapterTag = "lora"
    static let baseModelTagPrefix = "base-model:"
}

public extension RAModelInfo {
    /// True when this registry entry represents downloadable adapter bytes,
    /// not a standalone base model that can be loaded for inference.
    var isLoRAAdapterArtifact: Bool {
        let normalizedID = id.lowercased()
        if normalizedID.hasPrefix(LoRAArtifactMetadata.modelIDPrefix) {
            return true
        }

        return metadata.tags.contains { tag in
            let normalizedTag = tag.lowercased()
            return normalizedTag == LoRAArtifactMetadata.adapterTag ||
                normalizedTag == LoRAArtifactMetadata.legacyAdapterTag
        }
    }
}
