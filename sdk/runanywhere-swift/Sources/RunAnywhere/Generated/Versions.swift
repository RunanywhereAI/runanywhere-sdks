// =============================================================================
// Centralized version constants for the Swift SDK.
// =============================================================================
//
// Do not hand-edit; run scripts/release/sync-versions.sh to refresh.
//
// These constants are the single source of truth for:
//   * the SDK version string emitted in telemetry events / release
//     XCFramework URLs in Package.swift,
//   * the swift-tools-version pinned in all three Package.swift files (root,
//     sdk/runanywhere-swift, examples/ios/RunAnywhereAI),
//   * the version floors used in the `.upToNextMinor(from:)` constraints for
//     each SPM dependency,
//   * native dependency versions exposed by Swift runtime modules.
//
// The Package.swift files cannot `import` this module (SwiftPM manifests run
// in a sandbox without access to the package's own sources), so when these
// values change the version literals embedded in Package.swift must be
// updated in lock-step. `scripts/release/sync-versions.sh` (T4.3 follow-up) reads
// this file with `swift run` or a Mint-pinned `swift-format` and rewrites the
// Package.swift literals so they cannot drift.
// =============================================================================

/// Centralized version constants for the Swift SDK. Do not hand-edit;
/// run scripts/release/sync-versions.sh to refresh.
public enum RAVersions {
    public static let sdkVersion = "0.19.15"
    public static let swiftToolsVersion = "6.2"
    // Pinned SPM dep version floors (must match Package.swift) — bumped in T5.4.
    public static let swiftProtobuf = "1.38.0"
    public static let deviceKit = "5.8.0"
    public static let swiftCrypto = "3.15.1"
    public static let files = "4.3.0"
    // Mirrors sdk/runanywhere-commons/VERSIONS::ONNX_VERSION_IOS.
    public static let onnxRuntimeIOS = "1.24.3"
}
