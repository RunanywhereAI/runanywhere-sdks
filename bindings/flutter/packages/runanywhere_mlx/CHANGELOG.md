## [0.20.18] - 2026-08-12

- Rebuilt the Electron backend plugin natives. 0.20.17 shipped a non-routable
  sherpa carrier that referenced none of its STT/TTS/VAD ops tables, so the
  plugin registry declined it and the backend served nothing.
- Backend registration failures are now isolated: one unavailable engine no
  longer prevents the rest of the SDK from initializing.

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
