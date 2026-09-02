## [0.20.35] - 2026-09-02

### Changed

- No API change. Rebuilt against the 0.20.35 core.

## [0.20.34] - 2026-09-02

### Changed

- No API change. Rebuilt against the 0.20.34 core.

## [0.20.33] - 2026-09-01

### Changed

- No API change. Rebuilt against the 0.20.33 core.
- `rac_framework_supports_tts()` now includes Core ML, because NeuRT actually
  serves the primitive as of this release. It was deliberately left out while the
  slot was null: claiming a capability the engine does not serve routes a model to
  an engine that refuses it.

## [0.20.32] - 2026-08-31

### Changed

- No API change. Rebuilt against plugin ABI v10.
- Core ML models are now routed to the NeuRT engine unconditionally and fail
  closed when it cannot serve the primitive. Previously a Core ML model that MLX
  could not read could still be handed to MLX by plugin priority (110 vs
  NeuRT's 100).

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

- Version-train bump only; no MLX-facing changes in this release.

## [0.20.27] - 2026-08-24

### Changed

- Version-train bump only; no MLX-facing changes in this release.

## [0.20.26] - 2026-08-23

### Changed

- Version-train bump only; no MLX-facing changes in this release.

## [0.20.25] - 2026-08-21

### Changed

- Version-train bump only; no Flutter-facing changes.

## [0.20.24] - 2026-08-16

### Changed

- Reissued the compatible MLX Swift runtime and model support from the
  corrected release manifest.

## [0.20.23] - 2026-08-16

### Changed

- Updated the compatible MLX Swift, MLX Swift LM, and MLX Audio Swift runtime
  line used by the shared Apple backend.
- Added Maple Preview and Nemotron speech support while preserving verified
  Bonsai/Prism model compatibility.

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

- Suite version bump. No change to this package's Dart or podspec surface. The
  four checksum-pinned MLX archives are re-pinned to this release's assets.

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

- Restore the Apple MLX backend as an optional Flutter iOS plugin.
- Register the canonical Swift MLX runtime through its public C entrypoints.
- Support MLX LLM, VLM, embeddings, STT, and TTS routing through core APIs.
