// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// FoundationModelsRuntime module. Importing this target arms
// `FoundationModels.installer`; the first subsequent
// `FoundationModels.register(priority:)` call actually installs the
// platform-LLM callback table into `ra_platform_llm_*`.

@_exported import RunAnywhere

/// Re-exports + auto-installer wiring for the Apple Foundation Models
/// backend. Sample apps call `FoundationModels.register(priority:)` at
/// startup as usual.
@MainActor
public enum FoundationModelsRuntimeBackend {

    /// Eagerly wire the installer. Called automatically at module-load
    /// time via the `_ = armInstaller` side effect below. Exposed as
    /// a manual entry point for hosts that want explicit control.
    @discardableResult
    public static func arm() -> Bool {
        FoundationModels.installer = {
            SystemFoundationModelsService.installPlatformCallbacks()
        }
        return true
    }

    /// Manual register helper: forwards to `FoundationModels.register`.
    @discardableResult
    public static func ensureRegistered(priority: Int = 50) -> Bool {
        arm()
        return FoundationModels.register(priority: priority)
    }

    // Fire arm() at first access of any member of this enum — Swift
    // lazy static — so merely referencing the module or calling its
    // FoundationModels.register() path installs the hook.
    @usableFromInline internal static let _armed: Bool = arm()
}
