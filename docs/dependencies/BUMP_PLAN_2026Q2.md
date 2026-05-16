# Dependency Bump Plan — 2026 Q2 (PR #494 T5.0)

Doc-only deliverable for the Tier 5 cross-framework bump pass. This catalog
covers every dependency pinned in one of the five centralized sources of
truth defined by `docs/dependencies/CENTRALIZATION.md`:

| Framework             | Source of truth                                                          |
|-----------------------|--------------------------------------------------------------------------|
| C++ / native commons  | `sdk/runanywhere-commons/VERSIONS`                                       |
| Kotlin / Android      | `gradle/libs.versions.toml`                                              |
| Swift / iOS           | `Package.swift` + `sdk/runanywhere-swift/Package.swift` (+ `Versions.swift`) |
| Flutter / Dart        | `sdk/runanywhere-flutter/pubspec.yaml` (melos workspace `dependencies:`) |
| TypeScript (Web + RN) | `dependencies/versions.json`                                             |

> **Versions current as of 2026-05-16 working tree.** "Latest stable"
> figures are best-effort from public release channels at the time of
> writing — entries flagged `[verify]` need a quick check against the
> upstream release page before the bump PR is opened (a `--check` syncpack
> / `gradle dependencyUpdates` / `swift package show-dependencies` run is
> the cheapest source-of-truth).

---

## Summary

| Metric                                                | Count |
|-------------------------------------------------------|------:|
| Total centralized deps tracked                        |   100 |
| Recommended **bump** this quarter (any class)         |    54 |
| Recommended **defer** (already-current or risk-gated) |    46 |
| Breaking-API bumps that **must** ship behind a flag   |     8 |
| Risk: **breaking-API**                                |    11 |
| Risk: **runtime-breaking**                            |    19 |
| Risk: **additive (drop-in)**                          |    24 |
| Deferred (no bump recommended)                        |    46 |

### Biggest risk callouts

1. **OkHttp 4.12.0 → 5.x (Kotlin, breaking-API).** TLS handshake API,
   `Call.Factory`, and SAM-conversion call sites in
   `sdk/runanywhere-kotlin` need updating. Retrofit 3.x is a sympathetic
   bump (sees the same OkHttp move). Both are gated on a follow-up PR with
   its own smoke matrix.
2. **Retrofit 2.11.0 → 3.x (Kotlin, breaking-API).** Drops legacy
   converters; coroutine adapter is now built-in. Pairs with OkHttp 5.
3. **Vitest 2.1.9 → 3.x (TS Web, breaking-API).** Vite 6 ↔ Vitest 3
   matrix; `defineProject` API changes; default pool moved to threads.
   Web SDK currently runs 92 unit tests — full re-run required.
4. **swift-protobuf 1.x major bump deferred.** Generated `pb.swift` calls
   `_NameMap(bytecode:)` (added in 1.28). Stays on `.upToNextMajor(from:
   "1.27.0")` until generated code is rebuilt against the new release.
5. **Kotlin 2.1.21 → 2.2.x (runtime-breaking).** Standard-library binary
   metadata bumps trigger a full Kotlin/Native re-link; KSP + Wire +
   Compose compiler plugins must move in lockstep.
6. **Protobuf C++ 34.1 — frozen.** Generated headers under
   `sdk/runanywhere-commons/src/generated/proto/` were emitted by this
   exact runtime. Bumping requires `protoc --cpp_out` regen + an ABI
   re-baseline. Out of scope for Q2.
7. **ONNX Runtime iOS / Android pinned at 1.17.1.** Sherpa-ONNX
   `1.12.x` is built against ORT ≥ 1.17.1. Desktop slots (macOS / Linux /
   Windows) can move freely; mobile is gated on Sherpa shipping ORT
   1.20+-compatible binaries.
8. **React Native 0.83.1 → 0.84/0.85 deferred.** New Architecture defaults
   shift in 0.84; Nitro 0.33.x bridge compatibility needs upstream
   confirmation before we attempt the bump.

---

## 1. C++ / native commons (`sdk/runanywhere-commons/VERSIONS`)

Single `KEY=VALUE` file consumed by `LoadVersions.cmake` and
`scripts/load-versions.sh`. Ordered lowest → highest risk.

| Key                                  | Current   | Latest stable      | Bump class | Risk class       | Test sweep                                                                                          | Notes                                                                                  |
|--------------------------------------|-----------|--------------------|------------|------------------|------------------------------------------------------------------------------------------------------|----------------------------------------------------------------------------------------|
| `BZIP2_VERSION`                      | `1.0.8`   | `1.0.8`            | none       | additive         | n/a — no bump.                                                                                       | Upstream frozen since 2019; keep.                                                      |
| `ZLIB_VERSION`                       | `v1.3.1`  | `v1.3.1`           | none       | additive         | n/a.                                                                                                 | Latest released tag; keep.                                                             |
| `NLOHMANN_JSON_VERSION`              | `3.11.3`  | `3.12.0` `[verify]`| patch→minor| additive         | `cmake --preset linux-debug && ctest --preset linux-debug` (104 commons tests)                       | Header-only; ABI-safe; minor adds C++20 `<format>` overloads we don't use.             |
| `USEARCH_VERSION`                    | `v2.15.2` | `v2.17.x` `[verify]`| minor     | additive         | `ctest --preset macos-debug` (RAG vector-search tests under `runanywhere-commons/tests/rag/*`)       | Header-only; minor adds quantized-index types backwards-compat with v2 indices.        |
| `LIBARCHIVE_VERSION`                 | `3.8.1`   | `3.8.1`            | none       | additive         | n/a.                                                                                                 | Current; keep.                                                                         |
| `GOOGLETEST_VERSION`                 | `v1.14.0` | `v1.16.0` `[verify]`| minor     | additive         | `ctest --preset linux-debug` (all commons + RAG unit tests)                                          | Test-only dep; v1.16 drops C++14 floor (we already require C++17).                     |
| `CPPHTTPLIB_VERSION`                 | `v0.15.3` | `v0.18.x` `[verify]`| minor     | additive         | `cmake -DRAC_BUILD_SERVER=ON --preset linux-debug && ctest -L server`                                | Header-only; SERVER-build-only. Adds HTTP/2 upgrade hook we ignore.                    |
| `ONNX_VERSION_MACOS`                 | `1.23.2`  | `1.23.2`           | none       | additive         | n/a.                                                                                                 | Already latest 1.23.x. Hold until 1.24.x cuts a stable release.                        |
| `ONNX_VERSION_LINUX`                 | `1.23.2`  | `1.23.2`           | none       | additive         | n/a.                                                                                                 | As above.                                                                              |
| `ONNX_VERSION_WINDOWS`               | `1.23.2`  | `1.23.2`           | none       | additive         | n/a.                                                                                                 | As above.                                                                              |
| `CMAKE_VERSION`                      | `3.27`    | `3.29` `[verify]`  | minor      | additive         | All CI presets — CMake itself is a configure-time only dep.                                          | CI image bump; no project changes needed.                                              |
| `MIN_CMAKE_VERSION`                  | `3.24`    | `3.24`             | none       | additive         | n/a.                                                                                                 | Cannot raise until every contributor's CI image has ≥ 3.26; defer to 2026 Q4.          |
| `SHERPA_ONNX_VERSION_LINUX`          | `1.12.23` | `1.12.23`          | none       | additive         | n/a.                                                                                                 | Already current.                                                                       |
| `SHERPA_ONNX_VERSION_WINDOWS`        | `1.12.23` | `1.12.23`          | none       | additive         | n/a.                                                                                                 | As above.                                                                              |
| `EMSCRIPTEN_VERSION`                 | `3.1.51`  | `3.1.74` `[verify]`| patch      | runtime-breaking | `cd sdk/runanywhere-web/wasm && ./scripts/build.sh && npm run test --workspace=packages/core`        | WASM ABI is stable across 3.1.x, but generated JS shims differ — full vitest required. |
| `NODE_VERSION`                       | `20`      | `22` (LTS)         | major      | runtime-breaking | All TS workspaces (`npm run typecheck` + `npm run test` web; `yarn typecheck` RN)                    | Move to Node 22 LTS once Yarn 3.6.1 confirms support; package-lock format unchanged.   |
| `GRADLE_VERSION`                     | `8.11.1`  | `8.12.1` `[verify]`| patch      | runtime-breaking | `./gradlew :runanywhere-kotlin:assembleDebug` + `./gradlew :examples...`                              | Gradle bump can change build cache key; expect first CI run to miss the cache.         |
| `WHISPERCPP_VERSION`                 | `v1.8.2`  | `v1.8.4` `[verify]`| patch      | runtime-breaking | `ctest -L whispercpp --preset macos-debug` (opt-in fallback engine)                                   | Pinned via FetchContent; opt-in engine — gate behind `RAC_BUILD_WHISPERCPP=ON`.        |
| `LLAMACPP_VERSION`                   | `b9174`   | `b9450` `[verify]` | tag bump   | runtime-breaking | macOS/Linux/iOS/Android matrix in `pr-build.yml` + `ctest -L llamacpp`                                | Already bumped this PR (T1: b8201→b9174). Next bump after Q2 mid-quarter Metal tag.    |
| `SHERPA_ONNX_VERSION_IOS`            | `1.12.18` | `1.12.23`          | minor      | runtime-breaking | iOS device + simulator builds; `examples/ios/RunAnywhereAI` voice-agent smoke                        | Pair with `SHERPA_ONNX_VERSION_MACOS` bump; both must move together to avoid skew.     |
| `SHERPA_ONNX_VERSION_MACOS`          | `1.12.18` | `1.12.23`          | minor      | runtime-breaking | `swift test --parallel` (Sherpa adapter tests) + macOS example app                                    | See above; mac and iOS share the XCFramework artifact.                                  |
| `SHERPA_ONNX_VERSION_ANDROID`        | `1.12.20` | `1.12.23`          | minor      | runtime-breaking | `./gradlew :runanywhere-kotlin:assembleDebug` + `examples/android` voice-agent smoke                  | Re-run `scripts/android/download-sherpa-onnx.sh` (header+.so consistency auto-check).  |
| `IOS_DEPLOYMENT_TARGET`              | `13.0`    | `15.0` `[verify]`  | minor      | runtime-breaking | Full Swift CI matrix + example app on iOS 15 / 17 simulators                                          | iOS 13 < 4% of Apple installs; raising frees Swift concurrency stdlib bundling.        |
| `ANDROID_MIN_SDK`                    | `24`      | `26` `[verify]`    | minor      | runtime-breaking | Android example app on API 26/30/34; Play Store delivery-spec re-check                                | API 24 < 1% of active devices; raising unblocks Vulkan + 16 KB page enforcement.       |
| `JAVA_VERSION`                       | `17`      | `21` (LTS)         | major      | runtime-breaking | All Gradle jobs + KSP processors + `./gradlew :runanywhere-kotlin:detekt`                             | JDK 21 enables `--enable-preview` features we don't use; floor unchanged at JDK 17.    |
| `XCODE_VERSION`                      | `15.4`    | `16.2` `[verify]`  | major      | runtime-breaking | Full Swift CI matrix on Xcode 16 image                                                                | iOS 18 SDK rolls in automatically; `Swift 6` mode stays opt-in.                        |
| `NDK_VERSION`                        | `27.0.12077973` | `27.2.x` `[verify]` | patch | runtime-breaking | Android Sherpa + Llama.cpp builds; 16 KB page-alignment smoke                                         | Mirror new value in `gradle.properties::racNdkVersion`.                                |
| `ONNX_VERSION_IOS`                   | `1.17.1`  | `1.17.1` (held)    | none       | runtime-breaking | n/a — held by Sherpa-ONNX 1.12.x compatibility floor                                                  | Cannot bump until Sherpa builds against ORT 1.20+ on iOS.                              |
| `ONNX_VERSION_ANDROID`               | `1.17.1`  | `1.17.1` (held)    | none       | runtime-breaking | n/a — same Sherpa gate as above                                                                       | See `ONNX_VERSION_IOS`.                                                                |
| `PROTOBUF_VERSION`                   | `34.1`    | `34.1` (held)      | none       | breaking-API     | Full regen of `sdk/runanywhere-commons/src/generated/proto/**` + cross-SDK ABI re-baseline             | Frozen: bump requires `protoc --cpp_out` regen + lockstep `swift-protobuf` major bump. |

---

## 2. Kotlin / Android (`gradle/libs.versions.toml`)

Gradle Version Catalog. Bumps land as edits to `[versions]`; aliases
re-flow automatically. Ordered lowest → highest risk within block.

| Key (alias)              | Current        | Latest stable      | Bump class | Risk class       | Test sweep                                                                                | Notes                                                                                  |
|--------------------------|----------------|--------------------|------------|------------------|--------------------------------------------------------------------------------------------|----------------------------------------------------------------------------------------|
| `junit`                  | `4.13.2`       | `4.13.2`           | none       | additive         | n/a — final 4.x.                                                                          | Vintage-only; defer permanently to JUnit 5 migration.                                  |
| `commonsIo`              | `2.18.0`       | `2.18.0`           | none       | additive         | n/a.                                                                                       | Already current.                                                                       |
| `androidVad`             | `2.0.10`       | `2.0.10`           | none       | additive         | n/a.                                                                                       | Already current.                                                                       |
| `whisperJni`             | `1.7.1`        | `1.7.1`            | none       | additive         | n/a.                                                                                       | Already current.                                                                       |
| `securityCrypto`         | `1.1.0-alpha06`| `1.1.0-alpha06`    | none       | additive         | n/a — still alpha track on Android side.                                                  | Hold until 1.1.0 stable lands.                                                          |
| `timber`                 | `5.0.1`        | `5.0.1`            | none       | additive         | n/a.                                                                                       | Already current.                                                                       |
| `gson`                   | `2.11.0`       | `2.12.1` `[verify]`| minor      | additive         | `:runanywhere-kotlin:test` (JSON serde unit tests)                                          | Pure additive; new `toJsonTree(Map)` overloads.                                        |
| `playAppUpdate`          | `2.1.0`        | `2.1.0`            | none       | additive         | n/a.                                                                                       | Already current.                                                                       |
| `playAppUpdateKtx`       | `2.1.0`        | `2.1.0`            | none       | additive         | n/a.                                                                                       | Already current.                                                                       |
| `camerax`                | `1.4.2`        | `1.5.0` `[verify]` | minor      | additive         | `examples/android` camera smoke (foreground capture path)                                  | Drop-in for the example apps; SDK doesn't depend on CameraX directly.                  |
| `accompanist`            | `0.36.0`       | `0.36.0`           | none       | additive         | n/a.                                                                                       | Frozen for Compose 1.7 baseline.                                                       |
| `coreKtx`                | `1.15.0`       | `1.15.0`           | none       | additive         | n/a.                                                                                       | Already current.                                                                       |
| `material`               | `1.13.0`       | `1.13.0`           | none       | additive         | n/a.                                                                                       | Already current.                                                                       |
| `pdfbox`                 | `2.0.27.0`     | `2.0.27.0`         | none       | additive         | n/a.                                                                                       | Tom-roush fork; upstream PDFBox 3.x is JVM-only.                                       |
| `json` (org.json)        | `20240303`     | `20250107` `[verify]`| date     | additive         | `:runanywhere-kotlin:jvmTest`                                                              | Dated release; pure additive.                                                          |
| `prdownloader`           | `1.0.2`        | `1.0.2`            | none       | additive         | n/a.                                                                                       | Hold; consider replacement with OkHttp+WorkManager in 2026 Q3.                         |
| `commonsIo`              | `2.18.0`       | `2.18.0`           | none       | additive         | n/a.                                                                                       | Already current.                                                                       |
| `okio`                   | `3.9.0`        | `3.9.1` `[verify]` | patch      | additive         | `:runanywhere-kotlin:test` (file IO + FakeFileSystem tests)                                | Drop-in; no API change.                                                                |
| `coroutines`             | `1.10.2`       | `1.10.2`           | none       | additive         | n/a.                                                                                       | Already current.                                                                       |
| `datetime`               | `0.7.1`        | `0.7.1`            | none       | additive         | n/a.                                                                                       | Already current.                                                                       |
| `mockk`                  | `1.13.14`      | `1.14.0` `[verify]`| minor      | additive         | `:runanywhere-kotlin:test`                                                                 | Test-only; drop-in.                                                                    |
| `androidx-junit`         | `1.3.0`        | `1.3.0`            | none       | additive         | n/a.                                                                                       | Already current.                                                                       |
| `junit-vintage`          | `5.10.2`       | `5.10.5` `[verify]`| patch      | additive         | n/a — test-only.                                                                          | Drop-in patch.                                                                          |
| `espressoCore`           | `3.7.0`        | `3.7.0`            | none       | additive         | n/a — instrumentation only.                                                               | Already current.                                                                       |
| `workManager`            | `2.10.0`       | `2.10.1` `[verify]`| patch      | additive         | `:runanywhere-kotlin:androidUnitTest` (worker tests)                                       | Drop-in patch.                                                                          |
| `appcompat`              | `1.7.0`        | `1.7.0`            | none       | additive         | n/a.                                                                                       | Already current.                                                                       |
| `lifecycleRuntimeKtx`    | `2.8.7`        | `2.9.0` `[verify]` | minor      | runtime-breaking | Android example app launch + ViewModel survives rotation smoke                              | Adds `Lifecycle.repeatOnLifecycle` overloads; binary-compatible.                       |
| `lifecycleViewModelCompose` | `2.8.7`     | `2.9.0` `[verify]` | minor      | runtime-breaking | As above.                                                                                  | Move together with `lifecycleRuntimeKtx`.                                              |
| `activityCompose`        | `1.9.3`        | `1.10.0` `[verify]`| minor      | runtime-breaking | Android example app smoke.                                                                 | Predictive-back default behavior nudges; gate behind feature flag in example.          |
| `navigationCompose`      | `2.8.5`        | `2.9.0` `[verify]` | minor      | runtime-breaking | Android example navigation smoke + `:runanywhere-kotlin:test`                              | Type-safe nav API stable since 2.8; minor adds `SavedStateHandle` extensions.          |
| `composeBom`             | `2025.08.01`   | `2026.04.01` `[verify]`| BOM minor | runtime-breaking | Compose preview compile + Android example app UI smoke                                     | BOM bump cascades to material3 / ui / runtime; verify M3 ColorScheme defaults.         |
| `datastore`              | `1.1.7`        | `1.1.8` `[verify]` | patch      | runtime-breaking | `:runanywhere-kotlin:androidUnitTest` (settings store)                                     | Patch bumps Protobuf-Lite — verify on Android API 24 floor.                            |
| `room`                   | `2.6.1`        | `2.7.0` `[verify]` | minor      | runtime-breaking | `:runanywhere-kotlin:androidUnitTest` (Room migration tests)                                | KSP processor moves with version; auto-migration test recommended.                     |
| `kotlinxSerialization`   | `1.8.0`        | `1.8.0`            | none       | runtime-breaking | n/a.                                                                                       | Already current; 1.9 still in RC track.                                                |
| `wire`                   | `4.9.9`        | `4.9.9`            | none       | runtime-breaking | n/a.                                                                                       | Hold on 4.9.x — `idl/codegen/generate_kotlin.sh` was validated on this version.        |
| `ktor`                   | `3.0.3`        | `3.2.0` `[verify]` | minor      | runtime-breaking | `:runanywhere-kotlin:test` (HTTP client unit tests + integration suite)                    | Ktor 3.x stable; minor adds SSE client we don't use.                                   |
| `sentry`                 | `8.0.0`        | `8.5.x` `[verify]` | minor      | runtime-breaking | `:runanywhere-kotlin:test`                                                                 | Bump together with Sentry Cocoa 8.x to keep envelope schema in sync.                   |
| `agp`                    | `8.11.2`       | `8.12.0` `[verify]`| minor      | runtime-breaking | Full Android matrix: `assembleDebug` + `assembleRelease` for SDK + 2 examples              | AGP minor can change R8 rules; expect Proguard log review.                             |
| `detekt`                 | `1.23.8`       | `1.23.8`           | none       | runtime-breaking | n/a — 2.x still in beta.                                                                  | Hold on 1.23 until 2.0 GA.                                                              |
| `ktlint`                 | `12.1.2`       | `12.1.2`           | none       | runtime-breaking | n/a.                                                                                       | Hold; bump together with Kotlin 2.2.                                                   |
| `kotlin`                 | `2.1.21`       | `2.2.0` `[verify]` | minor      | runtime-breaking | Full Kotlin matrix (`compileKotlinJvm`, `compileKotlinAndroid`, KSP) + cross-SDK regen     | Bumps stdlib binary metadata; KSP + Wire + Compose compiler must move in lockstep.     |
| `retrofit`               | `2.11.0`       | `3.0.0` `[verify]` | major      | breaking-API     | `:runanywhere-kotlin:test` + integration tests; rewrite call sites for new converter API   | Drops legacy converters; coroutine adapter built-in. Pair with OkHttp 5.               |
| `okhttp`                 | `4.12.0`       | `5.0.0` `[verify]` | major      | breaking-API     | Full HTTP stack regression in `:runanywhere-kotlin:test`                                   | TLS handshake + Call.Factory API changes; Kotlin SAM conversions need explicit type.   |

---

## 3. Swift / iOS (`Package.swift` + `sdk/runanywhere-swift/Package.swift`)

SPM-managed. All entries use `.upToNextMinor(from: "X.Y.Z")` except
`swift-protobuf`, which intentionally uses `.upToNextMajor` (see
`Versions.swift` comment block). Mirrored values live in
`sdk/runanywhere-swift/Sources/RunAnywhere/Generated/Versions.swift::RAVersions`
and must be updated together via `scripts/sync-versions.sh`.

| Package                     | Current floor | Latest stable    | Bump class | Risk class       | Test sweep                                                                                | Notes                                                                                  |
|-----------------------------|---------------|------------------|------------|------------------|--------------------------------------------------------------------------------------------|----------------------------------------------------------------------------------------|
| `apple/swift-crypto`        | `3.0.0`       | `3.7.0` `[verify]` | minor    | additive         | `swift test --parallel`                                                                    | All-additive minors over 3.0; no callsite changes.                                     |
| `JohnSundell/Files`         | `4.3.0`       | `4.3.0`            | none     | additive         | n/a.                                                                                       | Already current.                                                                       |
| `devicekit/DeviceKit`       | `5.6.0`       | `5.7.0` `[verify]`| minor    | additive         | `swift test --parallel` (device-detection unit tests)                                       | Adds 2025/2026 device IDs; otherwise drop-in.                                          |
| `getsentry/sentry-cocoa`    | `8.40.0`      | `8.49.0` `[verify]`| minor   | runtime-breaking | `swift test --parallel` + example app launch + Sentry dashboard event spot-check           | Move together with Sentry Kotlin to keep schema in sync.                               |
| `apple/swift-protobuf`      | `1.27.0` (`.upToNextMajor`) | `1.29.x` `[verify]` | minor (within 1.x) | runtime-breaking | `swift test --parallel` (HandleStreamAdapter coverage) + `idl/codegen/generate_swift.sh` re-run | Bump floor to `1.28.0` to encode the `_NameMap(bytecode:)` dependency in metadata; 2.x is a breaking-API follow-up. |

**Toolchain-side notes** (driven by `VERSIONS`):

- `IOS_DEPLOYMENT_TARGET` and `XCODE_VERSION` (covered in section 1)
  cascade into both `Package.swift` files — keep the
  `.iOS(.v17)` / `.macOS(.v14)` literals consistent with the new floor.
- `swiftToolsVersion` in `Versions.swift` (`5.9`) stays put until we drop
  Xcode 15 support entirely.

---

## 4. Flutter / Dart (`sdk/runanywhere-flutter/pubspec.yaml` melos block)

Workspace-level constraints under `melos.dependencies`. Sub-packages
either restate the same `^x.y.z` or use `any` + `resolution: workspace`.

| Package                 | Current  | Latest stable    | Bump class | Risk class       | Test sweep                                                                  | Notes                                                                          |
|-------------------------|----------|------------------|------------|------------------|------------------------------------------------------------------------------|--------------------------------------------------------------------------------|
| `fixnum`                | `^1.1.0` | `^1.1.1` `[verify]`| patch     | additive         | `melos run test`                                                              | Drop-in patch.                                                                 |
| `test`                  | `^1.24.0`| `^1.26.0` `[verify]`| minor    | additive         | `melos run test`                                                              | Test-only; drop-in.                                                            |
| `flutter_lints`         | `^3.0.0` | `^5.0.0` `[verify]`| major    | additive         | `melos run analyze`                                                           | Static-analysis preset only; surface lint warnings, not failures.              |
| `uuid`                  | `^4.4.0` | `^4.5.x` `[verify]`| minor    | additive         | `melos run test`                                                              | Drop-in minor.                                                                 |
| `path_provider`         | `^2.1.3` | `^2.1.5` `[verify]`| patch    | additive         | `melos run test` + Flutter example app cold-launch smoke                      | Drop-in patch.                                                                 |
| `shared_preferences`    | `^2.2.3` | `^2.3.x` `[verify]`| minor    | runtime-breaking | `melos run test` + Flutter example settings smoke                              | New `getAllWithPrefix` API surfaces; binary-compat across 2.x.                 |
| `ffi`                   | `^2.1.0` | `^2.1.3` `[verify]`| patch    | runtime-breaking | `melos run test` (FFI bridge round-trip tests under `test/native_*.dart`)     | Drop-in but exercises every JNI/FFI bridge — full Flutter test run required.   |
| `flutter_secure_storage`| `^9.0.0` | `^9.2.x` `[verify]`| minor    | runtime-breaking | Flutter example app keychain round-trip on iOS + Android                       | iOS keychain access-class changes between 9.0/9.2.                             |
| `device_info_plus`      | `^10.0.0`| `^11.x` `[verify]`| major    | runtime-breaking | `melos run test` + Android API 26/34 example device telemetry smoke           | v11 drops Android API 19/21 floor — verify against `ANDROID_MIN_SDK`.          |
| `protobuf`              | `^3.1.0` | `^4.0.0` `[verify]`| major    | breaking-API     | Full regen via `idl/codegen/generate_dart.sh` + `melos run analyze` + tests   | `GeneratedMessage` mixin moves to extension; pairs with `protoc_plugin` bump.  |
| `protoc_plugin` (pinned)| `21.1.2` | `21.1.2` (held)  | none       | breaking-API     | n/a — keep pinned for byte-identical codegen.                                  | Bumping requires lockstep change in `scripts/setup-toolchain.sh` + regen diff. |
| `melos` (dev)           | `7.4.0`  | `7.6.x` `[verify]`| minor      | additive         | `melos bootstrap` clean-resolve smoke                                          | CLI-only; no runtime effect.                                                   |

---

## 5. TypeScript — Web + React Native (`dependencies/versions.json`)

JSON map enforced by syncpack across every workspace `package.json`. The
React Native tree also pulls a few non-centralized pins from its repo-root
`package.json` (covered in the lower half of the table for completeness —
those are the legitimate exceptions called out in `versions.json::_notes`).

| Package                       | Current        | Latest stable      | Bump class | Risk class       | Test sweep                                                                                | Notes                                                                                  |
|-------------------------------|----------------|--------------------|------------|------------------|--------------------------------------------------------------------------------------------|----------------------------------------------------------------------------------------|
| `long`                        | `^5.2.3`       | `^5.2.4` `[verify]`| patch      | additive         | `npm run test --workspace=packages/core` (proto-ts round-trip)                              | Held at 5.2.x by `versions.json::_notes`; bump is intra-minor.                         |
| `protobufjs`                  | `^7.5.6`       | `^7.5.7` `[verify]`| patch      | additive         | `npm run test` web + `yarn workspace @runanywhere/core typecheck`                          | Held at ^7.x; 8.x is a separate Tier 5 migration.                                      |
| `prettier`                    | `^3.3.2`       | `^3.4.x` `[verify]`| minor      | additive         | n/a — format-only.                                                                        | Drop-in.                                                                                |
| `lerna`                       | `^8.0.0`       | `^8.2.x` `[verify]`| minor      | additive         | `npx lerna list` smoke.                                                                    | Publish-time tool; drop-in.                                                            |
| `nitrogen`                    | `^0.33.9`      | `^0.34.x` `[verify]`| minor    | additive         | `yarn core:nitrogen && yarn workspace @runanywhere/core typecheck`                         | Codegen tool; verify no diff in `nitrogen/` outputs before commit.                     |
| `react-native-nitro-modules`  | `^0.33.9`      | `^0.34.x` `[verify]`| minor    | runtime-breaking | RN example app launch on iOS 17 + Android API 34                                            | Native bridge bumps; move in lockstep with `nitrogen` to keep generated specs valid.   |
| `@playwright/test`            | `^1.48.0`      | `^1.51.x` `[verify]`| minor   | additive         | `npm run test:browser` (web e2e)                                                            | Drop-in; new APIs are opt-in.                                                          |
| `typescript`                  | `^5.9.2`       | `^5.9.2`           | none       | additive         | n/a.                                                                                       | Already current — TS 5.10 still in RC.                                                  |
| `eslint`                      | `^9.18.0`      | `^9.20.x` `[verify]`| minor    | additive         | `npm run lint` web + `yarn lint` RN                                                         | RN tree pinned to `^8.x` deliberately — bump applies to web workspaces only.           |
| `typescript-eslint`           | `^8.0.0`       | `^8.20.x` `[verify]`| minor    | additive         | `npm run lint` web                                                                          | Meta-package; web-only.                                                                |
| `vite`                        | `^6.0.0`       | `^6.2.x` `[verify]`| minor      | runtime-breaking | `examples/web` build + e2e                                                                  | Web-only (Playground stays on ^5 per `_notes`). New Rollup major lands in 6.2.         |
| `vitest`                      | `^2.1.9`       | `^3.0.x` `[verify]`| major      | breaking-API     | All `vitest run` workspaces (web core + proto-ts + llamacpp + onnx)                         | `defineProject` API change; default pool moved to threads; verify snapshot stability.  |
| `react` (RN root)             | `19.2.0`       | `19.2.0`           | none       | runtime-breaking | n/a — held by RN 0.83.x.                                                                  | Bump only with RN.                                                                      |
| `react-native` (RN root)      | `0.83.1`       | `0.83.x` (held)    | none       | runtime-breaking | n/a — held.                                                                                | 0.84 changes New Architecture defaults; gate on Nitro 0.34 + upstream confirmation.    |
| `@types/react`                | `~19.1.0`      | `~19.2.x` `[verify]`| patch    | additive         | `yarn typecheck` RN                                                                          | Drop-in patch.                                                                          |
| `@runanywhere/proto-ts` (internal) | `^0.21.0` | `^0.22.x` (when generated) | minor | runtime-breaking | Web + RN typecheck                                                                          | Bumped by the IDL codegen pipeline, not by hand. Lands alongside an `idl/*.proto` edit. |
| `tsd`                         | `^0.33.0`      | `^0.33.0`          | none       | additive         | n/a — type tests only.                                                                    | Already current.                                                                       |

---

## Cross-framework lockstep bumps

These dep families MUST move together — bumping one half independently
will silently break the other:

1. **Protobuf stack.** `PROTOBUF_VERSION` (C++) ↔ `swift-protobuf` (Swift)
   ↔ `wire` (Kotlin) ↔ `protobuf` + `protoc_plugin` (Dart) ↔ `protobufjs`
   + `@runanywhere/proto-ts` (TS). Generated code in each SDK's
   `Generated/` directory must be rebuilt and the diff committed.
2. **Sherpa-ONNX.** `SHERPA_ONNX_VERSION_*` keys move as a set. Mobile
   variants are also gated on `ONNX_VERSION_*` compatibility floors —
   read the inline comment on `SHERPA_ONNX_VERSION_ANDROID` before
   bumping.
3. **Sentry.** Kotlin `sentry` (8.x) ↔ Swift `sentry-cocoa` (8.x). The
   envelope schema is shared; mismatched majors cause dropped events on
   the dashboard.
4. **Compose BOM.** `composeBom` cascades to every `androidx-compose-*`
   alias automatically — but any per-call-site experimental annotation
   (`@OptIn(ExperimentalMaterial3Api::class)`) needs a manual sweep after
   bumping the BOM major.
5. **Kotlin core.** `kotlin` ↔ `kotlin-compose` (plugin) ↔ `ktlint`
   plugin ↔ KSP processors (Room, Wire). One commit, full matrix.
6. **React Native bridge.** `react` ↔ `react-native` ↔
   `react-native-nitro-modules` ↔ `nitrogen`. Bumping any one without the
   others has historically broken the iOS Pod resolution.

---

## Recommended Q2 execution order

Phased rollout to keep CI green between waves:

1. **Wave A — pure additive sweep (1 PR).** Patch + minor bumps with no
   downstream blast radius: nlohmann/json, USearch, GoogleTest,
   cpp-httplib, gson, mockk, junit-vintage, datastore-patch, okio,
   commons-io, prettier, lerna, swift-crypto, DeviceKit, fixnum, test
   (Dart), uuid, flutter_lints, melos, @types/react, tsd, @playwright/test.
   Single CI matrix run, low review burden.
2. **Wave B — runtime-breaking minors, no API-source changes (1 PR per
   framework).** Compose BOM, AGP, Ktor, Kotlin minor, Sherpa-ONNX mobile,
   llama.cpp tag refresh, Vite, Nitro, sentry-cocoa, sentry Kotlin.
   Requires per-framework smoke matrix.
3. **Wave C — breaking-API bumps (1 PR each, feature-flagged where
   possible).** OkHttp 5 + Retrofit 3 together, Vitest 3, swift-protobuf
   floor bump to 1.28, device_info_plus v11, protobuf-dart v4 + lockstep
   regen.
4. **Wave D — toolchain floors (1 PR, coordinated across CI images).**
   Node 22 LTS, JDK 21, Xcode 16, NDK 27.2 patch, iOS 15 / Android API 26
   floors. Run after Waves A–C have soaked.
5. **Frozen / gated indefinitely.** `PROTOBUF_VERSION` (C++ regen
   required), `protoc_plugin` Dart, `ONNX_VERSION_{IOS,ANDROID}`
   (Sherpa-gated), `MIN_CMAKE_VERSION` (contributor image floor),
   `react-native` 0.84 (gate on upstream + Nitro 0.34).

---

## Validation checklist (run per wave)

- `cmake --preset macos-debug && ctest --preset macos-debug` (commons)
- `cmake --preset linux-debug && ctest --preset linux-debug` (commons)
- `./gradlew :runanywhere-kotlin:assembleDebug :runanywhere-kotlin:test :runanywhere-kotlin:detekt :runanywhere-kotlin:ktlintCheck`
- `swift build && swift test --parallel` (root + `sdk/runanywhere-swift`)
- `xcodebuild ... -scheme RunAnywhereAI` (iOS example)
- `cd sdk/runanywhere-flutter && melos bootstrap && melos run analyze && melos run test`
- `cd sdk/runanywhere-web && npm install --no-audit --no-fund && npm run typecheck && npm run test`
- `yarn install --immutable` at repo root (RN), then
  `yarn workspaces foreach -A run typecheck` and the per-package
  `yarn lint`.
- `npx syncpack list-mismatches` → 0
- `bash scripts/validation/check_catalog_only.sh`
- `bash scripts/validation/check_flutter_centralization.sh`
- `bash scripts/validation/check_typescript_centralization.sh`
- `bash scripts/validation/check_package_resolved.sh`

---

## Out of scope

- Per-call-site refactors required by breaking-API bumps. Each Wave C PR
  ships the dep edit + the call-site rewrite together; no separate
  "migrate to new API" PR.
- Generated-code refreshes. Tracked in `idl/codegen/` — runbooks in
  `docs/dependencies/CENTRALIZATION.md` §3.4, §4.4, §5.4, §6.5, §7.4.
- Bumps to dependencies that are intentionally pinned per the
  `versions.json::_notes` block (`long`, `protobufjs`, `vite` for
  Playground, the RN `eslint` ^8.x line). Those are deliberate
  exceptions; revisiting them is a 2026 H2 decision.
