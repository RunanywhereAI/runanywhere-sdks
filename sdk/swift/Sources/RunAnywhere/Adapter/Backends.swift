// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// Backend register entry points exposed to the iOS sample app:
//   LlamaCPP.register(priority:)
//   ONNX.register(priority:)
//   WhisperKitSTT.register(priority:)
//   MetalRT.register(priority:)
//   Genie.register(priority:)
//
// On iOS the engines are statically compiled into the XCFramework; their
// `RA_STATIC_PLUGIN_REGISTER(name)` macro fires at dynamic-init time and
// adds their vtable to the global plugin registry. These `register(priority:)`
// methods are therefore a no-op confirmation hook — they exist to keep the
// sample-app bootstrap call sites compiling without source changes.
//
// On macOS / Linux the same call dlopens the engine .dylib in `register()`
// when bundled, otherwise no-ops if the engine plugin was already statically
// linked.

import Foundation
import CRACommonsCore

/// llama.cpp LLM + embed engine.
public enum LlamaCPP {
    @discardableResult
    public static func register(priority: Int = 100) -> Bool {
        registeredPriorities["llamacpp"] = priority
        return true
    }
}

/// ONNX Runtime LLM + STT + VAD + embed engine.
public enum ONNX {
    @discardableResult
    public static func register(priority: Int = 100) -> Bool {
        registeredPriorities["onnx"] = priority
        return true
    }
}

/// WhisperKit Apple-only STT engine.
public enum WhisperKitSTT {
    @discardableResult
    public static func register(priority: Int = 200) -> Bool {
        registeredPriorities["whisperkit"] = priority
        return true
    }
}

/// MetalRT optional Apple GPU-accelerated runtime.
public enum MetalRT {
    @discardableResult
    public static func register(priority: Int = 100) -> Bool {
        registeredPriorities["metalrt"] = priority
        return true
    }
}

/// Qualcomm Genie Android-only LLM engine. iOS no-op.
public enum Genie {
    @discardableResult
    public static func register(priority: Int = 100) -> Bool {
        registeredPriorities["genie"] = priority
        return true
    }
}

/// Apple Foundation Models native LLM hook (iOS 26+ / macOS 26+).
/// The real Swift bridge lives in the `FoundationModelsRuntime` target —
/// which calls `FoundationModels.setInstaller(_:)` on import. When the
/// consumer links that target, `register()` installs the platform
/// callback table into `ra_platform_llm_*`.
public enum FoundationModels {

    /// Installer hook set by the `FoundationModelsRuntime` target. Nil when
    /// the consumer did not link that target, in which case `register()`
    /// records the priority but installs no callbacks.
    public static var installer: (() -> Void)?

    @discardableResult
    public static func register(priority: Int = 50) -> Bool {
        registeredPriorities["foundation_models"] = priority
        installer?()
        return true
    }
}

internal var registeredPriorities: [String: Int] = [:]
