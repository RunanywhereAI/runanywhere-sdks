// RunAnywhere+Hardware.swift
// RunAnywhere SDK
//
// Public API for hardware profile inspection — namespaced under
// `RunAnywhere.hardware.*` per the canonical cross-SDK spec
// (CANONICAL_API §14 — Hardware Profile).
//
// Implementation decodes `RAHardwareProfileResult` from the commons
// serialized-proto ABI. Apple-only device facts used by registration and
// telemetry remain in Swift platform adapters.

import Foundation

public extension RAHardwareProfile {
    var hasNeuralEngine: Bool {
        get { hasNeuralEngine_p }
        set { hasNeuralEngine_p = newValue }
    }
}

// MARK: - Hardware Namespace

public extension RunAnywhere {

    /// Capability accessor for hardware profile inspection.
    ///
    /// Mirrors the `hardware.*` shape used by Kotlin, Flutter, RN, and Web SDKs.
    static var hardware: Hardware { Hardware() }

    /// Stateless namespace exposing generated-proto hardware results from the C++ bridge.
    struct Hardware: Sendable {

        fileprivate init() {}

        // MARK: - Canonical Methods

        /// Get a full hardware profile snapshot as generated proto data.
        public func getProfile() throws -> RAHardwareProfileResult {
            try CppBridge.Hardware.getProfile()
        }

        /// Get available accelerators as generated proto data.
        public func getAccelerators() throws -> [RAAcceleratorInfo] {
            try CppBridge.Hardware.getAccelerators()
        }

        /// Set the preferred accelerator for subsequent routing/inference calls.
        public func setAcceleratorPreference(_ preference: RAAccelerationPreference) throws {
            try CppBridge.Hardware.setAcceleratorPreference(preference)
        }
    }
}
