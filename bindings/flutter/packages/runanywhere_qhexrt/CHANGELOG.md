# Changelog

All notable changes to the RunAnywhere QHexRT Backend will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
