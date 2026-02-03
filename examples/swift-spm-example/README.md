# Swift SPM Example App

Minimal Swift example app that consumes the **RunAnywhere SDK** via Swift Package Manager using a **versioned** dependency (exact version). Use this to verify SDK consumption from a release tag without tracking a branch.

## Version control

- **Dependency:** `https://github.com/RunanywhereAI/runanywhere-sdks.git`
- **Version:** `exact: "0.17.5"` — SPM resolves this tag and does not auto-upgrade.
- **Products used:** RunAnywhere, RunAnywhereLlamaCPP, RunAnywhereONNX.

To use a different version, change the dependency in `Package.swift` (e.g. `exact: "0.17.6"` or `from: "0.17.0"`).

## Prerequisites

- Xcode 15+ / Swift 5.9+
- macOS 14+ or iOS 17+ (released SDK binaries are iOS-only; use iOS Simulator to run)

## Build and run

### Command line

```bash
cd examples/swift-spm-example
swift package update
swift build
```

**Note:** Released XCFrameworks are iOS-only. On a Mac, `swift build` may resolve and compile but **fail at link** for the host (macOS). To run successfully, build for **iOS Simulator**:

```bash
xcodebuild -scheme SwiftSPMExample -destination 'platform=iOS Simulator,name=iPhone 17' -configuration Debug build
xcrun simctl spawn booted .build/<path-to-SwiftSPMExample>
```

Or open in Xcode and run on a simulator (see below).

### Xcode

1. Open the package in Xcode:
   ```bash
   open examples/swift-spm-example/Package.swift
   ```
2. Wait for package resolution to finish.
3. Set the run destination to an **iOS Simulator** (e.g. iPhone 17).
4. Run (⌘R).

Expected output:

```
RunAnywhere SDK SPM Example: OK
  - RunAnywhere: resolved
  - LlamaCPPRuntime: resolved
  - ONNXRuntime: resolved

SDK consumed via versioned dependency (exact: 0.17.5).
```

## Using a different version or fork

Edit `Package.swift`:

- **Another version from upstream:**  
  `.package(url: "https://github.com/RunanywhereAI/runanywhere-sdks.git", exact: "0.17.6")`
- **Version range:**  
  `.package(url: "https://github.com/RunanywhereAI/runanywhere-sdks.git", from: "0.17.0")`
- **Fork (e.g. for testing):**  
  `.package(url: "https://github.com/YOUR_USERNAME/runanywhere-sdks.git", exact: "0.17.5")`  
  (requires that tag and release assets exist with matching checksums on the fork.)

## Related

- **Full iOS sample app** (path dependency, full UI): `examples/ios/RunAnywhereAI/`
- **Validation consumer** (CI/minimal check): `validation/swift-spm-consumer/`
