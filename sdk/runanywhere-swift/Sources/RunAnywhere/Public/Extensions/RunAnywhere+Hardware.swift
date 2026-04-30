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

/// A snapshot of the device's hardware capabilities relevant to on-device AI.
///
/// Returned by `RunAnywhere.hardware.getProfile()`.
public struct HardwareProfile: Sendable {

    /// Human-readable chip/SoC name (e.g. "A17 Pro", "M4", "Apple Silicon").
    public let chip: String

    /// Whether the device has a dedicated Neural Engine (ANE).
    public let hasNeuralEngine: Bool

    /// Recommended acceleration mode for on-device AI on this device.
    ///
    /// Possible values:
    /// - `"ane"` — Apple Neural Engine is available (arm64 with Neural Engine)
    /// - `"gpu"` — Metal GPU acceleration (arm64 without dedicated ANE)
    /// - `"cpu"` — CPU-only fallback (x86_64 / unknown)
    public let accelerationMode: String

    /// Total physical memory in bytes.
    public let totalMemoryBytes: Int

    /// Number of logical CPU cores.
    public let coreCount: Int

    /// Number of performance CPU cores.
    public let performanceCores: Int

    /// Number of efficiency CPU cores.
    public let efficiencyCores: Int

    /// CPU architecture string (e.g. "arm64", "x86_64").
    public let architecture: String

    /// Platform string (e.g. "ios", "macos").
    public let platform: String
}

/// Canonical alias matching `HardwareProfileResult` from the
/// generated proto type (`Generated/hardware_profile.pb.swift`). Wave 3
/// Step 3.2: lets callers spell the type as `HardwareProfileResult` per
/// CANONICAL_API §14, ahead of the Wave 4 type unification.
public typealias HardwareProfileResult = HardwareProfile

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
        /// - Returns: `HardwareProfile` built from live `DeviceInfo.current` values.
        public func getProfile() -> HardwareProfile {
            let info = DeviceInfo.current
            return HardwareProfile(
                chip: info.chipName,
                hasNeuralEngine: info.hasNeuralEngine,
                accelerationMode: accelerationMode,
                totalMemoryBytes: info.totalMemory,
                coreCount: info.coreCount,
                performanceCores: info.performanceCores,
                efficiencyCores: info.efficiencyCores,
                architecture: info.architecture,
                platform: info.platform
            )
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
