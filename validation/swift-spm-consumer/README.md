# Swift SPM Consumer (Phase 2 validation)

Minimal Swift package used to **test consumption of the RunAnywhere Swift SDK** from a GitHub Release (Phase 2 CI). It lives in `validation/swift-spm-consumer/` and is **separate** from the main SDK and examples to avoid conflicts.

## What it does

- Depends on `runanywhere-sdks` via Swift Package Manager from GitHub.
- Uses products: RunAnywhere, RunAnywhereLlamaCPP, RunAnywhereONNX.
- Imports: `RunAnywhere`, `LlamaCPPRuntime`, `ONNXRuntime` (target/module names).
- Builds a small executable that only prints that the SDK resolved; no runtime SDK calls.

## Prerequisites

- A `swift-v*` tag (e.g. `swift-v0.1.1`) must exist and **Phase 2 must have run** for that tag (GitHub Release with XCFramework ZIPs attached).
- SPM resolves versions from **semver-like tags** (e.g. `0.1.1` or `v0.1.1`). The repo uses `swift-v0.1.1` for releases; SPM does **not** treat `swift-v0.1.1` as version `0.1.1`. So either:
  - Create an additional tag `0.1.1` (or `v0.1.1`) on the same commit as `swift-v0.1.1`, or
  - Point this consumer at a branch/commit that has the release, or
  - Wait until the repo uses a tag SPM can interpret (e.g. `0.1.1`) for the Swift package.

Until then, you can test **inside the main repo** by depending on the local path (see below).

## Run (consuming from GitHub)

This consumer uses **exact: "0.17.5"** from the upstream repo (`RunanywhereAI/runanywhere-sdks`). The tag and release assets must exist with matching checksums.

```bash
cd validation/swift-spm-consumer
swift package update
swift build
./.build/debug/SwiftSPMConsumer
```

**Note:** Release XCFrameworks (v0.17.5) are **iOS-only** (no macOS slice). On a Mac, `swift build` will resolve and compile but **fail at link** with "symbol(s) not found for architecture arm64". To get a full build, open the package in Xcode and build for an **iOS Simulator** destination (e.g. iPhone 16). Resolution and binary fetch validate correctly.

### Running in Xcode

- **Use iOS Simulator.** In Xcode, set the run destination to an **iOS Simulator** (e.g. "iPhone 16"). Then Run (⌘R). No code signing is required and the executable runs correctly.
- **Do not run on a physical device.** This target is a **command-line executable**, not an app bundle (.app). Installing to a real device fails with:
  - *"The executable is not codesigned"* — device installs require code signing.
  - *"The provided item to be installed is not of a type that CoreDevice recognizes"* — iOS expects an .app bundle; a bare executable is not installable.

To validate the SDK on device, use the full iOS example app (`examples/ios/RunAnywhereAI/`) instead, which is a proper app with signing and bundle structure.

### If Xcode shows "Missing package product" (RunAnywhere, RunAnywhereLlamaCPP, RunAnywhereONNX)

Xcode didn’t resolve the package graph, so it doesn’t see those products. Try in order:

1. **Reset and re-resolve in Xcode:**  
   **File → Packages → Reset Package Caches**, then **File → Packages → Resolve Package Versions**. Wait for resolution to finish, then build again.

2. **Re-open the consumer package only:**  
   Close Xcode, then open **only** the consumer:  
   `open validation/swift-spm-consumer/Package.swift`  
   (Don’t open the repo root if it has another `Package.swift`; that can confuse resolution.)

3. **Force a clean resolve:**  
   Close Xcode, then in Terminal from the repo root:
   ```bash
   cd validation/swift-spm-consumer
   rm -rf .build Package.resolved
   open Package.swift
   ```
   In Xcode, let packages resolve, then build for an **iOS Simulator** destination.

If you use a **fork**, change the package URL in `Package.swift` to your fork (e.g. `https://github.com/YOUR_USERNAME/runanywhere-sdks.git`) and use a tag that exists there (e.g. `exact: "0.17.5"`).

## Run (consuming from local repo)

To verify the package structure and imports **without** a GitHub release, depend on the parent repo by path:

1. In `Package.swift`, replace the dependency with:
   ```swift
   .package(path: "../.."),
   ```
2. From repo root, ensure the Swift SDK is built locally:
   ```bash
   cd sdk/runanywhere-swift && ./scripts/build-swift.sh --setup
   ```
3. Then:
   ```bash
   cd validation/swift-spm-consumer
   swift build
   ./.build/debug/SwiftSPMConsumer
   ```

Revert the `Package.swift` dependency back to the URL when testing against the real GitHub release.
