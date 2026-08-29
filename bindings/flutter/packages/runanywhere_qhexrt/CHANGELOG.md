# Changelog

All notable changes to the RunAnywhere QHexRT Backend will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.20.31] - 2026-08-27

### Fixed

- `HostOpFailed` still reproduced on `qwen3.8-27b-1bit-npu` after v0.20.30's
  `ADSP_LIBRARY_PATH` fix, even with the environment variable confirmed
  correctly set. Root cause: `qhx_runtime_device()` (used to pick the
  `v75`/`v79`/`v81` manifest directory, before the manifest is even parsed)
  shared its device query with the code path that creates a live QNN HTP
  device -- so every model, including the Bonsai/Maple ternary decoder's
  `host_only` manifest, opened a real QNN device before the manifest was
  read. That device then contended with the decoder's own direct FastRPC
  session for the same Hexagon cDSP: traced live on a Snapdragon X2 Elite,
  the FastRPC `SET_PATH`/`GET_PATH` session controls both returned a
  non-zero rc once the QNN device was up, and the skel open that followed
  failed `0x80000406`. Neither `ADSP_LIBRARY_PATH` nor a QAIRT-version
  mismatch (also investigated) was the actual cause. Fixed in neurun
  v0.20.31 (`qnn::Backend::profile()` now queries device info without
  creating a live device) and re-pinned here.

## [0.20.30] - 2026-08-27

### Fixed

- The Electron packaging never set `ADSP_LIBRARY_PATH`, so the Bonsai/Maple
  ternary decoder (`qwen3.8-27b-1bit-npu`) failed every generation in the
  packaged Windows app with `HostOpFailed` -- confirmed on a real Snapdragon
  X2 Elite device. Every other QHexRT model was unaffected, which is why this
  slipped through. Fixed by extending `ADSP_LIBRARY_PATH` the same way `PATH`
  was already extended for the standard QNN HTP path.
- The private QHexRT overlay used to build RCLI silently dropped every skel
  file (`.so`/`.cat`), so a fresh RCLI build could not run any QHexRT model,
  standard or ternary, without hand-copying files in. Fixed.

## [0.20.29] - 2026-08-26

### Changed

- Re-pinned NeuRT and QHexRT engine archives to neurun v0.20.29. QHexRT win-arm64
  now ships with the Bonsai fully-on-NPU 1-bit decoder (`qwen38_generate`)
  enabled, intended to address `PlanStepFailed` when running
  `qwen3.8-27b-1bit-npu` -- Windows ARM64 device validation of this exact
  pin is in progress.

## [0.20.28] - 2026-08-24

### Changed

- Version-train bump only; no Hexagon-facing API change. The Windows ARM64
  QHexRT payload continues to ship as a private overlay, not a public kit.

## [0.20.27] - 2026-08-24

### Changed

- The Hexagon NPU payload is now fetched from a pinned prebuilt release instead
  of being staged by hand, with atomic selection on every platform.
- The QAIRT/QNN runtime the engine depends on at execution time is now a
  separate, pinned, checksum-verified private artifact — fetched with the same
  credential as the engine payload, so a build that can reach one reaches both.
  A build without that credential correctly falls back to the non-routable
  shell rather than shipping a half-configured engine.

## [0.20.26] - 2026-08-23

### Changed

- The Hexagon NPU payload is now fetched from a pinned prebuilt release instead of
  being staged by hand. Both the archive checksum and the payload's own build-receipt
  hash are pinned, so the pin describes the bytes rather than trusting the archive's
  claim about itself.
- Fixes a case where a hand-staged payload could keep an old build selected while
  reporting success. Selection is now atomic on every platform.

## [0.20.25] - 2026-08-21

### Changed

- Version-train bump only; no Flutter-facing changes.

## [0.20.24] - 2026-08-16

### Changed

- Kept the private QHexRT wrapper aligned with the corrected shared SDK release
  manifest. This package remains excluded from public publication.

## [0.20.23] - 2026-08-16

### Changed

- Kept the private QHexRT wrapper version aligned with the shared SDK ABI and
  release train. This package is not part of the public pub.dev publication.

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

- QHexRT catalog: added the `lfm2_5_1_2b_thinking` policy row. The app catalogs
  already shipped that model, but the engine had no row for it, so device-aware
  registration failed with `-259` ("unknown QHexRT native catalog model id") on
  a real v81 device. The bundle is public and v81 only.
- QHexRT catalog: `lfm2_5_vl_3b` no longer requires an HF token. Its repo
  (`runanywhere/lfm2_5_vl_3b_HNPU`) is public, so the stale auth gate was
  hiding a public model from the picker.
- Note: this package still ships no natives from pub.dev by design. The
  Qualcomm QNN libraries are private and must be staged separately; without
  them the SDK reports QHexRT unavailable and continues.

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
- Aligned the private backend package and native artifact contract with RunAnywhere 0.20.0.

## [0.19.13] - 2026-05-13

### Added
- Initial Flutter package for the private Android-only QHexRT backend.
- Registers Qualcomm Hexagon NPU support through the standard RunAnywhere SDK APIs.
- Includes NPU capability probing and staged native library packaging for Android.
