// =============================================================================
// Centralized version constants for the Swift SDK.
// =============================================================================
//
// Do not hand-edit; run scripts/release/sync-versions.sh to refresh.
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
// updated in lock-step. `scripts/release/sync-versions.sh` (T4.3 follow-up) reads
// this file with `swift run` or a Mint-pinned `swift-format` and rewrites the
// Package.swift literals so they cannot drift.
// =============================================================================

/// Centralized version constants for the Swift SDK. Do not hand-edit;
/// run scripts/release/sync-versions.sh to refresh.
public enum RAVersions {
    public static let sdkVersion = "0.19.13"
    // T5.4: swift-tools-version stays at 5.9 — the 6.0 attempt enabled Swift 6
    // strict concurrency and surfaced pre-existing source-level issues
    // (mutable static globals, closure-captured locals in audio + URLSession
    // callbacks) that are out of scope for the dep-bump PR. Re-attempt once
    // the strict-concurrency migration lands.
    public static let swiftToolsVersion = "5.9"
    // Pinned SPM dep version floors (must match Package.swift) — bumped in T5.4.
    public static let swiftProtobuf = "1.38.0"
    public static let sentryCocoa = "8.58.2"
    public static let deviceKit = "5.8.0"
    public static let swiftCrypto = "3.15.1"
    public static let files = "4.3.0"
}
