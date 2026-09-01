# Changelog

All notable changes to the RunAnywhere LlamaCpp Backend will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.20.32] - 2026-08-31

### Changed

- No API change. Rebuilt against plugin ABI v10. llama.cpp's vtable already
  declared its rerank slot explicitly, so the promotion of the following
  reserved slot needed no edit here.

## [0.20.31] - 2026-08-27

### Changed

- No Flutter-facing API change. QHexRT's `HostOpFailed` regression on
  `qwen3.8-27b-1bit-npu` fixed (see the `runanywhere_qhexrt` changelog);
  this bump keeps versions in lockstep.

## [0.20.30] - 2026-08-27

### Changed

- No Flutter-facing API change. Electron and RCLI's QHexRT Windows packaging fixed
  (see the `runanywhere_qhexrt` changelog); this bump keeps versions in lockstep.

## [0.20.29] - 2026-08-26

### Changed

- Re-pinned NeuRT and QHexRT engine archives to neurun v0.20.29. QHexRT win-arm64
  now ships with the Bonsai fully-on-NPU 1-bit decoder (`qwen38_generate`)
  enabled, intended to address `PlanStepFailed` when running
  `qwen3.8-27b-1bit-npu` -- Windows ARM64 device validation of this exact
  pin is in progress.

## [0.20.28] - 2026-08-24

### Changed

- Version-train bump only; no llama.cpp-facing changes in this release.

## [0.20.27] - 2026-08-24

### Changed

- Version-train bump only; no llama.cpp-facing changes in this release.

## [0.20.26] - 2026-08-23

### Changed

- Version-train bump only; no llama.cpp-facing changes in this release.

## [0.20.25] - 2026-08-21

### Changed

- Version-train bump only; no Flutter-facing changes.

## [0.20.24] - 2026-08-16

### Changed

- Reissued the maintained llama.cpp, Maple Preview, and Bonsai/Prism-compatible
  runtime train from the corrected release manifest.

## [0.20.23] - 2026-08-16

### Changed

- Upgraded to the maintained RunAnywhere llama.cpp compatibility tag.
- Added Maple Preview support while preserving Bonsai/Prism compatibility and
  expanded the current GGUF model catalog.

## [0.20.22] - 2026-08-15

### Changed

- Version bump only. This release exists so the Electron packages can be
  republished with their Windows native staging fixed: `0.20.21` shipped the
  ONNX and Sherpa backends without the vendor runtimes they link, so those two
  engines could not load on Windows x64. The Dart/Flutter surface is unchanged
  from 0.20.19 and no 0.20.22 native artifacts are produced for it.

## [0.20.21] - 2026-08-14

### Changed

- Version bump only. This release exists so the Electron packages can be
  republished carrying Windows x64 and Windows ARM64 natives; the Dart/Flutter
  surface is unchanged from 0.20.19 and no 0.20.21 native artifacts are
  published.

## [0.20.20] - 2026-08-14

### Changed

- Version bump only. This release exists so the Electron packages can be
  republished with the staging telemetry URL baked in; the Dart/Flutter surface
  is unchanged from 0.20.19 and no 0.20.20 native artifacts are published.

## [0.20.19] - 2026-08-14

- Suite version bump. No change to this package's Dart, podspec, or Gradle
  surface; it continues to fetch the same checksum-pinned native archives.

## [0.20.18] - 2026-08-12

- Commons: backend registration failures are isolated. An engine that cannot
  register is recorded as unavailable instead of aborting SDK initialization,
  so the remaining backends keep serving.
- Suite version bump. This release also rebuilds the Electron backend plugin
  natives; that part does not affect this package.

## [0.20.17] - 2026-08-11

- Electron QHexRT backend and its commons platform-capability changes.
- Swift package is now consumable by version (`from:`) rather than only by git revision.

## [0.20.15] - 2026-08-11

- Suite version bump.

## [0.20.14] - 2026-08-09

- Suite version bump.

## [0.20.13] - 2026-08-08

- Suite version bump.

## [0.20.12] - 2026-07-28

- Suite version bump; Kotlin/QHexRT Maven release.

## [0.20.11] - 2026-07-16

- Version-aligned release with benchmark aggregation, variance reporting, and updated model catalogs.

## [0.20.10] - 2026-07-13

- CoreML diffusion enablement + macOS backend slice fixes (see SDK release notes).

## [0.20.9] - 2026-07-13

### Changed
- Version-aligned 0.20.9 release across all RunAnywhere SDKs; dev-analytics config baked into the native core at build time.

## [0.20.0] - 2026-07-12

### Changed
- Aligned the backend package and native artifact contract with RunAnywhere 0.20.0.

## [0.19.15] - 2026-07-11

### Changed
- Aligned public package metadata and native artifact staging with RunAnywhere 0.19.15.

## [0.19.13] - 2026-05-13

### Changed
- Kept the Flutter plugin as a thin backend registration adapter by removing unused template MethodChannel methods.
- Aligned the iOS deployment target and platform claims with the Swift iOS 17.0 baseline.
- Removed the backend plugin `uses-material-design` flag.

## [0.16.0] - 2026-02-14

### Changed
- Updated runanywhere dependency to ^0.16.0
- Rebuilt native LlamaCPP backend binaries with latest llama.cpp (b7650)
- Includes parameter piping fix (#340) and network layer improvements from core SDK

## [0.15.9] - 2025-01-11

### Changed
- Updated runanywhere dependency to ^0.15.9 for iOS symbol visibility fix
- See runanywhere 0.15.9 changelog for details on the iOS fix

## [0.15.8] - 2025-01-10

### Added
- Initial public release on pub.dev
- LlamaCpp integration for on-device LLM inference
- GGUF model format support
- Streaming text generation
- Memory-efficient model loading
- Native bindings for iOS and Android

### Features
- High-performance text generation
- Token-by-token streaming output
- Configurable generation parameters (temperature, max tokens, etc.)
- Automatic model management and caching

### Platforms
- iOS 17.0+ support
- Android API 24+ support
