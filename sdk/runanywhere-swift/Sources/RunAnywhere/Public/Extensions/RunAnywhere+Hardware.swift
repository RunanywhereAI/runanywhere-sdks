// RunAnywhere+Hardware.swift
// RunAnywhere SDK
//
// Public API for hardware profile inspection — namespaced under
// `RunAnywhere.hardware.*` per the canonical cross-SDK spec
// (CANONICAL_API §14 — Hardware Profile).
//
// Implementation is client-side using `DeviceInfo.current` (no C ABI needed;
// CPP-blocked: G-C6). The public NAME and SHAPE matches the canonical spec so
// that apps can write `RunAnywhere.hardware.getProfile()` on every platform.

import Foundation

// MARK: - Hardware Profile Types

public typealias HardwareProfile = RAHardwareProfile
public typealias HardwareProfileResult = RAHardwareProfileResult
public typealias AcceleratorInfo = RAAcceleratorInfo
public typealias AcceleratorPreference = RAAcceleratorPreference

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

    /// Stateless namespace exposing the canonical 4-method hardware surface.
    /// Backed by client-side `DeviceInfo` inspection (no C ABI required).
    struct Hardware: Sendable {

        fileprivate init() {}

        // MARK: - Canonical Methods

        /// Get a full hardware profile snapshot.
        ///
        /// - Returns: generated proto-backed `HardwareProfileResult`.
        public func getProfile() -> HardwareProfileResult {
            let info = DeviceInfo.current
            var profile = HardwareProfile()
            profile.chip = info.chipName
            profile.hasNeuralEngine = info.hasNeuralEngine
            profile.accelerationMode = accelerationMode
            profile.totalMemoryBytes = UInt64(max(info.totalMemory, 0))
            profile.coreCount = UInt32(max(info.coreCount, 0))
            profile.performanceCores = UInt32(max(info.performanceCores, 0))
            profile.efficiencyCores = UInt32(max(info.efficiencyCores, 0))
            profile.architecture = info.architecture
            profile.platform = info.platform

            var result = HardwareProfileResult()
            result.profile = profile
            var accelerator = AcceleratorInfo()
            accelerator.name = accelerationMode
            accelerator.type = info.hasNeuralEngine ? .ane : .cpu
            accelerator.available = true
            result.accelerators = [accelerator]
            return result
        }

        /// Get the chip/SoC name for the current device.
        ///
        /// - Returns: Human-readable chip name (e.g. "A17 Pro", "M4").
        public func getChip() -> String {
            DeviceInfo.current.chipName
        }

        /// Whether the current device has a dedicated Neural Engine.
        public var hasNeuralEngine: Bool {
            DeviceInfo.current.hasNeuralEngine
        }

        /// Recommended acceleration mode string for on-device AI inference.
        ///
        /// - `"ane"` — Apple Neural Engine available
        /// - `"gpu"` — Metal GPU acceleration
        /// - `"cpu"` — CPU-only fallback
        public var accelerationMode: String {
            let info = DeviceInfo.current
            if info.hasNeuralEngine {
                return "ane"
            } else if info.architecture == "arm64" {
                return "gpu"
            } else {
                return "cpu"
            }
        }
    }
}
