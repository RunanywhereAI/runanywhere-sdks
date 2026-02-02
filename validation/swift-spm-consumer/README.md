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

```bash
cd validation/swift-spm-consumer
swift build
./.build/debug/SwiftSPMConsumer
```

If you use a **fork**, change the package URL in `Package.swift` to your fork (e.g. `https://github.com/josuediazflores/runanywhere-sdks`) and use a version that exists there.

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
