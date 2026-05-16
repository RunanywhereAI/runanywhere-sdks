// =============================================================================
// Centralized version constants for the Swift SDK.
// =============================================================================
//
// Do not hand-edit; run scripts/sync-versions.sh to refresh.
//
// These constants are the single source of truth for:
//   * the SDK version string emitted in telemetry / Sentry events / release
//     XCFramework URLs in Package.swift,
//   * the swift-tools-version pinned in all three Package.swift files (root,
//     sdk/runanywhere-swift, examples/ios/RunAnywhereAI),
//   * the version floors used in the `.upToNextMinor(from:)` constraints for
//     each SPM dependency.
//
// The Package.swift files cannot `import` this module (SwiftPM manifests run
// in a sandbox without access to the package's own sources), so when these
// values change the version literals embedded in Package.swift must be
// updated in lock-step. `scripts/sync-versions.sh` (T4.3 follow-up) reads
// this file with `swift run` or a Mint-pinned `swift-format` and rewrites the
// Package.swift literals so they cannot drift.
// =============================================================================

/// Centralized version constants for the Swift SDK. Do not hand-edit;
/// run scripts/sync-versions.sh to refresh.
public enum RAVersions {
    public static let sdkVersion = "0.19.13"
    public static let swiftToolsVersion = "5.9"
    // Pinned SPM dep version floors (must match Package.swift)
    public static let swiftProtobuf = "1.27.0"
    public static let sentryCocoa = "8.40.0"
    public static let deviceKit = "5.6.0"
    public static let swiftCrypto = "3.0.0"
    public static let files = "4.3.0"
}
