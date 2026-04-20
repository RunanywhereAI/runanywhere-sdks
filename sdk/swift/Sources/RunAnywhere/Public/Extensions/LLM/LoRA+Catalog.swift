// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// Legacy LoRA catalog helpers. The main struct fields (`downloadURL`,
// `filename`, `fileSize`, `compatibleModelIds`, `defaultScale`) now live
// directly on `LoraAdapterCatalogEntry` itself — see ModelCatalog.swift.

import Foundation

public extension LoraAdapterCatalogEntry {
    /// Descriptive text used by the catalog browser.
    var adapterDescription: String { "\(name) (\(baseModelId))" }
}

public extension LoRAAdapterInfo {
    /// On-disk path resolved from the adapter config.
    var path: String { config.localPath }
}
