# Changelog

All notable changes to the RunAnywhere QHexRT Backend will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
