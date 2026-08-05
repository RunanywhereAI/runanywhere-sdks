# Swift SDK — Development

Contributor guide for building the Swift SDK from source, running its checks, and validating changes with the iOS example app. For integration instructions, see the [consumer README](../README.md).

## Prerequisites

| Tool | Version |
|------|---------|
| Xcode | 26+ (Swift 6.2) |
| CMake and Ninja | For native XCFramework generation |
| macOS | 14.5+ |

The MLX runtime target needs the Swift 6.2 toolchain, so Xcode 26 is a hard floor for a full build even though `swift-tools-version` is 5.9. Canonical toolchain pins live in `sdk/runanywhere-commons/VERSIONS`.

## Two Package.swift files

| File | Purpose |
|------|---------|
| Repo root `Package.swift` | External SPM consumers. Downloads XCFrameworks from GitHub Releases. |
| `sdk/runanywhere-swift/Package.swift` | SDK development. References the git-ignored local `Binaries/` directory. |

The remote artifacts are the fail-closed default. Local development opts in with `RUNANYWHERE_USE_LOCAL_NATIVES=1`; scripts set it explicitly and never rewrite the manifest.

## First-time setup

```bash
git clone https://github.com/RunanywhereAI/runanywhere-sdks.git
cd runanywhere-sdks

# Build and stage the native XCFrameworks into sdk/runanywhere-swift/Binaries/
./sdk/runanywhere-swift/scripts/build-core-xcframework.sh
```

The script emits every Apple slice the SDK and its backends need:

```
sdk/runanywhere-swift/Binaries/
├── RACommons.xcframework
├── RABackendLLAMACPP.xcframework
├── RABackendONNX.xcframework
├── RABackendSherpa.xcframework
├── RABackendNeuRT.xcframework
├── RABackendMLX.xcframework
├── RunAnywhereMLXRuntime.xcframework
├── RunAnywhereMLXMetal.xcframework
├── onnxruntime.xcframework
└── onnx.xcframework
```

It also syncs the shared frameworks into the React Native and Flutter SDK plugin directories.

## Build and test

```bash
cd sdk/runanywhere-swift

RUNANYWHERE_USE_LOCAL_NATIVES=1 swift build
RUNANYWHERE_USE_LOCAL_NATIVES=1 swift test

# Platform build through Xcode
xcodebuild build -scheme RunAnywhere \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  CODE_SIGNING_REQUIRED=NO

# Packaging validation against the staged XCFrameworks
./scripts/package-sdk.sh --mode local
```

## Code quality

```bash
swiftlint                 # check
swiftlint --fix           # autofix
periphery scan            # unused-code detection
```

SwiftLint treats several rules as errors rather than warnings: no `print()`, `NSLog()`, `os_log()`, `debugPrint()`, or direct `Logger(` use (route everything through `SDKLogger`); no `as!` force casts or `force_try`; and every TODO must carry a GitHub issue number (`// TODO: #123 - description`).

Concurrency conventions worth knowing before you write bridge code: never use `NSLock` (use `OSAllocatedUnfairLock` or a Swift actor), and C callback trampolines are `@convention(c)` free functions with no captures.

## Products

| Product | Target | Capabilities |
|---------|--------|--------------|
| `RunAnywhere` | `RunAnywhere` | Core SDK, model lifecycle, events |
| `RunAnywhereLlamaCPP` | `LlamaCPPRuntime` | GGUF LLM and VLM via llama.cpp |
| `RunAnywhereONNX` | `ONNXRuntime` | STT, TTS, VAD via ONNX and Sherpa |
| `RunAnywhereMLX` | `MLXRuntime` | Apple MLX LLM, VLM, STT, TTS |

Three `.grpc.swift` files under `Sources/RunAnywhere/Generated/` are excluded from compilation. They require iOS 18 / macOS 15, above the SDK's deployment floor; an in-process C callback path replaces them.

## Testing with the iOS example app

```bash
cd examples/ios/RunAnywhereAI
./scripts/build_and_run_ios_sample.sh simulator "iPhone 16 Pro" --build-sdk
```

Swift SDK source changes are picked up on rebuild. After a C++ change in `runanywhere-commons`, re-run `build-core-xcframework.sh` before trusting an app build.

Stream SDK logs in a separate terminal:

```bash
log stream --predicate 'subsystem CONTAINS "com.runanywhere"' --info --debug
```

## After changing generated proto types

Proto-generated `.pb.swift` files under `Sources/RunAnywhere/Generated/` are committed and must never be hand-edited. Change `idl/*.proto`, then:

```bash
./idl/codegen/generate_swift.sh
```

The `idl-drift-check` CI workflow fails if the committed bindings differ from a fresh generation.

## Pull request process

1. Fork and branch.
2. Make the change.
3. Run `swiftlint` and `RUNANYWHERE_USE_LOCAL_NATIVES=1 swift test`.
4. Validate with the iOS example app on a simulator or device.
5. Open a pull request.

When reporting an issue, include the SDK version, Xcode version, deployment target, device or simulator model, reproduction steps, and relevant Console output with credentials redacted.

## Further reading

- [AGENTS.md](../AGENTS.md) — bridge architecture, actor layout, streaming fan-out, error and event systems
- [Consumer README](../README.md) — installation and public API
- [Commons development guide](../../runanywhere-commons/docs/DEVELOPMENT.md) — the C core the SDK binds to
