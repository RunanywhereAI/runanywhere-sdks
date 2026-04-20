// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// LlamaCPPRuntime — re-export shim over the core RunAnywhere module so
// the iOS sample app's `import LlamaCPPRuntime` keeps working without
// changes. The real engine plugin is statically linked into
// RACommonsCore.xcframework and self-registers at dynamic-init time
// via RA_STATIC_PLUGIN_REGISTER(llamacpp).

@_exported import RunAnywhere

/// Convenience helper — sample apps often do `LlamaCPP.register(priority:)`
/// at launch. The plugin is already registered statically; this call only
/// records the priority hint for the EngineRouter.
public enum LlamaCPPRuntime {
    public static func ensureRegistered(priority: Int = 100) -> Bool {
        LlamaCPP.register(priority: priority)
    }
}
