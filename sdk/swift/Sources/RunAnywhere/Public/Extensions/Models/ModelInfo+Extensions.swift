// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// Convenience accessors on public model types used by the iOS sample's
// model-listing / download UI.

import Foundation

public extension ModelInfo {
    /// Whether the model artifact exists on disk. Resolves from the
    /// model's `localPath` when present, otherwise returns false.
    var isDownloaded: Bool {
        guard let url = localPath else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    /// Whether this is a built-in (SDK-shipped) model. v2 has no
    /// bundled weights; always false.
    var isBuiltIn: Bool { false }

    /// Approximate total download size in bytes — sum of artifact file
    /// sizes from the catalog entry. `nil` when the catalog entry has no
    /// size metadata (so sample UIs can fall back to "Get").
    var downloadSize: Int64? {
        let files = files ?? []
        guard !files.isEmpty else { return memoryRequirement }
        let sum = files.reduce(Int64(0)) { $0 + ($1.sizeBytes ?? 0) }
        return sum > 0 ? sum : memoryRequirement
    }
}

public extension ModelArtifactType {
    /// Sample parity — main exposed an `.Other` bucket for artifacts
    /// that don't fit the standard categories. v2's nearest match is
    /// `.multiFile`, which covers everything that isn't a single file
    /// or a known archive format.
    static var Other: ModelArtifactType { .multiFile }

    /// Whether this artifact requires a network download before load.
    /// All artifact kinds except in-bundle placeholders do; kept as a
    /// convenience for sample UIs that gate on this.
    var requiresDownload: Bool { true }
}
