// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// Public `RunAnywhere` storage surface — async-throws convenience
// wrappers over the synchronous `clearCache` / `cleanTempFiles` helpers
// plus a `storedModels()` enumeration.

import Foundation
import CRACommonsCore

@MainActor
public extension RunAnywhere {

    /// List models that exist on disk as `StoredModel` records. Walks
    /// the registered catalog and checks file existence.
    static func storedModels() async -> [StoredModel] {
        availableModels.compactMap { info in
            var path: UnsafeMutablePointer<CChar>?
            defer { if let p = path { ra_file_string_free(p) } }
            let rc = info.framework.rawValue.withCString { fw in
                info.id.withCString { mid in
                    ra_file_model_path(fw, mid, &path)
                }
            }
            guard rc == RA_OK, let raw = path else { return nil }
            let diskPath = String(cString: raw)
            guard FileManager.default.fileExists(atPath: diskPath) else { return nil }
            let size = ra_file_directory_size_bytes(raw)
            return StoredModel(info: info, sizeBytes: size, path: diskPath)
        }
    }

    // `clearCache()` / `cleanTempFiles()` live on the ModelCatalog
    // extension in Public/Extensions/Models/ModelCatalog.swift and are
    // already `async throws`.
}
