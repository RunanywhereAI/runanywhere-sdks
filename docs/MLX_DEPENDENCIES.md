# MLX Dependency and Security Notes

This note documents the Swift package dependency chain introduced by the MLX
runtime and the controls expected for future updates.

## Runtime Scope

The C++ MLX backend in `engines/mlx/` is a callback-backed plugin shell. It does
not link MLX directly and it does not download model code or weights by itself.
Apple MLX execution is supplied by the Swift `MLXRuntime` target, which registers
callbacks through the C ABI in `rac/backends/rac_mlx.h`.

Model acquisition still flows through the SDK model registry, bundle policy, and
platform download adapters. The MLX runtime receives a resolved local model
folder path after commons lifecycle loading has completed.

## RN and Flutter Apple Hosts

React Native and Flutter continue to use their existing core SDK packages for
model registry, download, lifecycle loading, and C ABI calls. On Apple hosts,
real MLX execution requires the host Xcode project to link the Swift SPM product
`RunAnywhereMLX` in addition to the existing CocoaPods package graph. The RN and
Flutter iOS examples do this with a local SPM package reference to the repository
root so the Swift MLX runtime and exported C entrypoints are present in the app
binary.

Registration is still exposed at the framework layer:

```typescript
import { MLX } from '@runanywhere/mlx';

await MLX.register();
```

```dart
import 'package:runanywhere_mlx/runanywhere_mlx.dart';

await MLX.register();
```

Those calls route through the RN core Nitro bridge or Flutter FFI into the
Swift runtime C symbol `ra_mlx_register_runtime`, which installs the Swift MLX
callback table into the C++ MLX backend. Calling only
`rac_backend_mlx_register()` from JS/Dart is insufficient because the C++ engine
needs the Swift callbacks before it can execute real MLX models.

The example catalog seeders register MLX models only after `MLX.register()`
succeeds. Android, Web, or Apple builds that did not link `RunAnywhereMLX` do
not surface MLX rows, because the C++ MLX plugin without `MLXRuntime` callbacks
would advertise a backend that cannot execute.

The current RN and Flutter packages in this repo ship iOS CocoaPods targets, not
macOS host package targets. macOS MLX support is available through the Swift SDK
and the macOS Swift example/CLI path; adding React Native macOS or Flutter macOS
host packaging should reuse the same `RunAnywhereMLX` SPM product rather than
introducing a second MLX runtime.

## Web Feasibility

Official MLX is an Apple-silicon runtime and the Swift runtime depends on Apple
Metal. There is no official browser, WebAssembly, or WebGPU backend for MLX
today. The tracked MLX WebGPU backend discussion is a feature request, not a
supported runtime path.

For Web, keep using the existing Web SDK acceleration paths:

- `@runanywhere/web-llamacpp` WASM/WebGPU for text and vision models where
  supported.
- `@runanywhere/web-onnx` / Sherpa WASM for speech paths where supported.
- A future MLX-like browser experiment should be a separate WebGPU backend
  (for example `INFERENCE_FRAMEWORK_MLC` / WebLLM style), not an
  `INFERENCE_FRAMEWORK_MLX` backend that implies official MLX compatibility.

References: `https://github.com/ml-explore/mlx-swift`,
`https://ml-explore.github.io/mlx/`,
`https://github.com/ml-explore/mlx/issues/1790`.

## Default Swift Package Chain

The default MLX package graph is enabled by both the root `Package.swift` and the
local Swift SDK manifest at `sdk/runanywhere-swift/Package.swift`.

| Package | Version policy | Resolved version | Purpose |
| --- | --- | --- | --- |
| `ml-explore/mlx-swift` | `.upToNextMinor(from: "0.31.6")` | `0.31.6` | Core MLX arrays, Metal kernels, and low-level runtime APIs. |
| `ml-explore/mlx-swift-lm` | `.upToNextMinor(from: "3.31.4")` | `3.31.4` | LLM, VLM, embedder loaders, tokenizers, and generation helpers used by `MLXRuntime`. |
| `huggingface/swift-transformers` | `.upToNextMinor(from: "1.3.0")` | `1.3.3` | Tokenizer and Hugging Face model utilities pulled by the MLX model stack. |
| `huggingface/swift-huggingface` | transitive | `0.9.0` | Hugging Face Hub metadata utilities. |
| `huggingface/swift-jinja` | transitive | `2.3.6` | Chat-template rendering support. |
| `apple/swift-argument-parser` | transitive | `1.8.2` | CLI parsing dependency used by upstream Swift packages. |
| `apple/swift-collections` | transitive | `1.6.0` | Collection utilities used by upstream Swift packages. |
| `apple/swift-numerics` | transitive | `1.1.1` | Numeric helpers used by upstream Swift packages. |
| `Blaizzy/mlx-audio-swift` | exact revision | `580e952adda0cd6bdc5c04f402822adbb61525c8` | MLX STT/TTS adapters for Apple platforms. |

The resolved revisions are committed in both `Package.resolved` and
`sdk/runanywhere-swift/Package.resolved`; update them together with manifest
changes.

## MLX Audio Package

`Blaizzy/mlx-audio-swift` is in the default `RunAnywhereMLX` dependency graph so
the MLX STT/TTS callback slots are real on both iOS and macOS. Without this
package, the Swift runtime compiles the STT/TTS callbacks but they return
`mlxAudioUnavailable`; LLM, VLM, and embeddings still work through
`mlx-swift-lm`.

The package currently declares `swift-tools-version: 6.2`, so building
`RunAnywhereMLX`, the iOS sample, the macOS sample target, or the Swift MLX CLI
requires a Swift 6.2+ toolchain.

When upstream publishes a compatible tagged release, prefer replacing the
revision pin with a tagged `.upToNextMinor` constraint and refresh all
`Package.resolved` files in the same PR.

## Update Controls

- Use tagged `.upToNextMinor` constraints for default SPM dependencies.
- Keep untagged revision pins documented in this file and gated by MLX-specific
  Apple CI jobs that use a Swift 6.2+ toolchain.
- Review every `Package.swift` and `Package.resolved` diff in the same PR as
  the code that consumes the package.
- Run `swift package resolve` from the repo root and from
  `sdk/runanywhere-swift/` after dependency changes so both manifests stay in
  sync.
- Keep model downloads in the SDK download/model-registry path. Do not let
  runtime packages fetch arbitrary remote model artifacts behind commons.
- Re-run the focused MLX CLI E2E tests and Swift package build after dependency
  updates.
