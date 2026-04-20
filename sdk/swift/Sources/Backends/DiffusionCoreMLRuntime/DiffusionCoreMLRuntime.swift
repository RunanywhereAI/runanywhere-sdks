// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// Diffusion-CoreML runtime entry point. Installs the Swift bridge into
// the `engines/diffusion-coreml` plugin and registers the default
// catalog entries.

@_exported import RunAnywhere

@MainActor
public enum DiffusionCoreMLRuntimeBackend {

    /// Install the bridge + register the default catalog entries.
    /// Idempotent.
    @discardableResult
    public static func ensureRegistered(priority: Int = 100) -> Bool {
        DiffusionCoreMLService.installCallbacks()
        DiffusionModelCatalog.registerAll()
        return true
    }
}
