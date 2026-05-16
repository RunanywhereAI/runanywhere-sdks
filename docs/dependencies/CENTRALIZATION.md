# Dependency Centralization

Every framework in this repo pins its dependency, toolchain, and SDK versions
to a single source of truth (SoT) so that a bump is a one-line edit instead
of a 30-file grep-and-replace. This document is the contract.

PR scope: T4.0 (per-framework dep centralization). T5 (the actual latest-
stable bump pass) lands later and uses the runbooks below.

## Table of contents

1. [Why centralize](#1-why-centralize)
2. [Cross-framework invariants](#2-cross-framework-invariants)
3. [C++ / native commons](#3-c--native-commons)
4. [Kotlin / Android](#4-kotlin--android)
5. [Swift / iOS](#5-swift--ios)
6. [Flutter / Dart](#6-flutter--dart)
7. [TypeScript (Web + React Native)](#7-typescript-web--react-native)
8. [Bump matrix — at-a-glance](#8-bump-matrix--at-a-glance)
9. [Glossary](#9-glossary)

---

## 1. Why centralize

- **Drift between SDKs** — the same dep was pinned in 5 places (e.g. NDK was
  `25.2.9519653` on Flutter but `27.0.12077973` everywhere else, which broke
  16 KB-page enforcement on Android 16).
- **Build reproducibility** — SwiftPM/Flutter/npm floats produced different
  binaries on CI vs. local machines because no resolved file was committed.
- **One bump, one PR** — `llama.cpp b8201 → b9174` should be a single
  KEY=VALUE edit, not a hunt through CMake + 4 SDK bridges.
- **CI enforcement** — drift fails loud at PR time, not at release time.

## 2. Cross-framework invariants

These apply to every framework below:

- **One SoT per framework.** Build scripts and IDEs read from the SoT; they
  never re-declare a version locally.
- **Lockfile committed where the package manager produces one.** The SoT
  covers direct deps; the lockfile pins transitives.
- **Toolchain (compiler / SDK / runtime) is pinned alongside library deps.**
  An NDK or Flutter SDK bump is treated the same as a library bump.
- **CI fails the PR if a build file declares a literal version that bypasses
  the SoT.** Per-framework "CI validation" sections list the gate.
- **Bumps land in a single commit with a regenerated lockfile and a smoke
  matrix attached to the PR description.**

---

## 3. C++ / native commons

### 3.1 Source of truth

- File: `sdk/runanywhere-commons/VERSIONS`
- Format: `KEY=VALUE` (no spaces around `=`), `#` comments, section banners.
- Owns: every native dep version (ONNX Runtime, Sherpa-ONNX, llama.cpp,
  nlohmann/json, libarchive) **and** the cross-cutting toolchain pins
  (Xcode, NDK, Emscripten, Node, JDK, Gradle wrapper, CMake). Other layers
  re-export these so the whole repo stays in lockstep.

### 3.2 How build files consume it

- **CMake** — `include(LoadVersions)` (cmake module path is
  `sdk/runanywhere-commons/cmake/`). Every `KEY` is exposed as `${KEY}`
  **and** `${RAC_KEY}` (forced into the cache). A missing file → hard
  `FATAL_ERROR`.
- **Shell** — `source sdk/runanywhere-commons/scripts/load-versions.sh`
  exports every key as an env var. Hard rule baked into the script:
  callers **must not** hardcode fallbacks; missing key → fail.

### 3.3 How to add a new dep

1. Append `<LIB>_VERSION=X.Y.Z` (or `<LIB>_VERSION_<PLATFORM>` if it diverges
   per target) to `sdk/runanywhere-commons/VERSIONS` under a section banner.
2. Reference it via `${RAC_<LIB>_VERSION}` inside the relevant
   `FetchContent_Declare(... GIT_TAG ...)` block or via `$<LIB>_VERSION`
   in the platform downloader script.
3. `cmake --preset macos-debug && cmake --build --preset macos-debug` to
   confirm the key resolves.

### 3.4 How to bump a dep

1. Edit the one line in `VERSIONS`. Add a `# History:` comment when the bump
   is non-trivial (`LLAMACPP_VERSION` is the template).
2. Re-run any vendoring scripts the key drives, e.g.
   `./scripts/android/download-sherpa-onnx.sh` for `SHERPA_ONNX_VERSION_ANDROID`.
3. Verify (this is the minimum smoke set):
   ```bash
   cmake --preset macos-debug && cmake --build --preset macos-debug && ctest --preset macos-debug
   cmake --preset linux-debug && cmake --build --preset linux-debug && ctest --preset linux-debug
   ```

### 3.5 CI validation

`pr-build.yml` runs `cmake --preset <p>` for `macos-{debug,release}`,
`linux-{debug,asan}`, `ios-device`, `android-arm64`. A typo in `VERSIONS`
fails at configure (because `LoadVersions.cmake` is included from the root
`CMakeLists.txt`). `idl-drift-check.yml` also `source`s `load-versions.sh`,
so the gate is doubled.

---

## 4. Kotlin / Android

### 4.1 Source of truth

- Library deps + Gradle plugins: `gradle/libs.versions.toml` (Gradle Version
  Catalog, with `[versions] [libraries] [plugins]` sections).
- NDK pin shared with the C++ layer: `gradle.properties::racNdkVersion`
  (mirrors `NDK_VERSION` in `VERSIONS`).
- JDK floor + Gradle wrapper: `JAVA_VERSION` / `GRADLE_VERSION` in `VERSIONS`.

### 4.2 How build files consume it

Module `build.gradle.kts` files **never** declare a literal version. They
reference catalog aliases — `implementation(libs.kotlinx.coroutines.core)`,
`api(libs.wire.runtime)`, `alias(libs.plugins.kotlin.multiplatform)`. NDK
pin is read at task time as `rootProject.findProperty("racNdkVersion")` so
it survives AGP upgrades.

### 4.3 How to add a new dep

1. Add a version under the matching `[versions]` section header in
   `gradle/libs.versions.toml`:
   `coolLib = "1.2.3"`.
2. Add a library entry under `[libraries]`:
   `cool-lib = { group = "com.example", name = "cool-lib", version.ref = "coolLib" }`.
3. Reference it as `implementation(libs.cool.lib)` (TOML hyphens → dots).
4. `./gradlew :runanywhere-kotlin:dependencies --refresh-dependencies` to
   confirm resolution.

### 4.4 How to bump a dep

1. Edit the value in `[versions]`. Never duplicate an alias.
2. Plugin / AGP / Kotlin / Detekt / Ktlint bumps re-flow automatically through
   `alias(libs.plugins.…)`.
3. Verify:
   ```bash
   ./gradlew :runanywhere-kotlin:compileKotlinJvm --no-daemon
   ./gradlew :runanywhere-kotlin:assembleDebug --no-daemon
   ./gradlew :runanywhere-kotlin:detekt :runanywhere-kotlin:ktlintCheck
   ```
4. NDK bumps: edit `gradle.properties::racNdkVersion` **and**
   `VERSIONS::NDK_VERSION` in the same commit, then re-run the C++ smoke.

### 4.5 CI validation

`.github/workflows/pr-build.yml::kotlin-android` runs `assembleDebug`; a
broken catalog alias fails at configure. Gradle enforces the catalog's TOML
schema (unknown `version.ref` → build error). A follow-up
`scripts/validation/check_catalog_only.sh` greps for literal `"X.Y.Z"` in
`*.gradle.kts` with a small allowlist for the few constants the catalog
cannot reach.

---

## 5. Swift / iOS

### 5.1 Source of truth

| Concern | File | Notes |
|---|---|---|
| SDK semver | `sdk/runanywhere-swift/Sources/RunAnywhere/Generated/Versions.swift` (NEW) — `enum Versions { static let sdk = "0.19.13" }` | Replaces the `let sdkVersion = "0.19.13"` literal at `Package.swift:58`. |
| Third-party SPM deps | `Package.swift::dependencies`, with `.upToNextMinor(from:)` | Tightened from `.from(…)` (any future major) to `.upToNextMinor` (same-minor only). |
| Resolved transitives | `Package.resolved` (committed at repo root) | CI re-resolves to verify. |
| Lint / format / static-analysis | `Mintfile` (NEW) pinning `realm/SwiftLint`, `peripheryapp/periphery`, `apple/swift-format` | Replaces ad-hoc `brew install swiftlint` in local docs. |
| Toolchain | `XCODE_VERSION` + `IOS_DEPLOYMENT_TARGET` in `VERSIONS` | CI reads via `load-versions.sh`. |

### 5.2 How build files consume it

- `Package.swift` reads `Versions.sdk` instead of a string literal so the
  `binaryTarget` URLs always match the SDK semver. `Versions.swift` is
  regenerated by `./idl/codegen/generate_version_swift.sh` (idempotent, re-run
  in CI).
- Dep declarations use `.upToNextMinor(from: "X.Y.Z")` — the right balance
  for a binary-distributed SDK: bug-fix patches roll in, silent ABI breaks
  are rejected.
- `Mintfile` pins tooling line-by-line (`realm/SwiftLint@0.55.1`, etc.).
  Local: `mint bootstrap`. CI: `mint run swiftlint --strict`.

### 5.3 How to add a new dep

1. Append the package to `Package.swift::dependencies` with
   `.upToNextMinor(from: "X.Y.Z")`.
2. Add the product to the consuming target's `dependencies`.
3. `swift package resolve && swift build`. Commit the `Package.resolved`
   diff in the same commit.

### 5.4 How to bump a dep

1. Edit the `.upToNextMinor(from:)` floor.
2. `rm Package.resolved && swift package resolve` to force a fresh pin.
3. Verify:
   ```bash
   swift build
   swift test --parallel
   xcodebuild -workspace examples/ios/RunAnywhereAI/RunAnywhereAI.xcworkspace \
              -scheme RunAnywhereAI -destination 'generic/platform=iOS Simulator' build
   ```
4. Commit `Package.swift` **and** `Package.resolved` together.
5. SDK semver bump → edit `VERSION`, run `generate_version_swift.sh`,
   `Package.swift` picks the new value up via `Versions.sdk`.
6. Tooling bump (SwiftLint / Periphery / swift-format) → edit `Mintfile`,
   `mint bootstrap`, re-run `mint run swiftlint --strict`.

### 5.5 CI validation

- `swift-spm` job runs `swift build`, which fails if `Package.resolved` is
  stale. A new `scripts/validation/check_package_resolved.sh` re-runs
  `swift package resolve` and `git diff --exit-code Package.resolved`.
- A lint check confirms no `Package.swift` dep line uses `.from(…)` outside
  a tiny allowlist (transitive workspace packages only).

---

## 6. Flutter / Dart

### 6.1 Source of truth

| Concern | File | Notes |
|---|---|---|
| Workspace + shared deps | `sdk/runanywhere-flutter/pubspec.yaml` (Melos 7 workspace) | Common runtime deps (`ffi`, `protobuf`, `fixnum`, `device_info_plus`, …) hoisted into a workspace `dependencies:` block; sub-packages keep `resolution: workspace`. |
| Per-package deps | `packages/<pkg>/pubspec.yaml` | Sub-packages only declare deps that diverge from the workspace block. |
| Flutter SDK pin | `sdk/runanywhere-flutter/.fvm/fvm_config.json` (NEW) — `{ "flutterSdkVersion": "3.38.0" }` | `fvm` locally, `subosito/flutter-action@v2` in CI both read it. |
| Codegen tool pin | workspace `pubspec.yaml::dev_dependencies::protoc_plugin` (NEW) | Replaces the ad-hoc `dart pub global activate protoc_plugin` in `scripts/setup-toolchain.sh`. |
| Dart SDK floor | `environment.sdk: '>=3.5.0 <4.0.0'` mirrored across all `pubspec.yaml`s | Already in place. |

### 6.2 How build files consume it

- Melos 7 supports a top-level `dependencies:` block on a workspace root.
  Sub-packages with `resolution: workspace` inherit those constraints during
  `flutter pub get`.
- `.fvm/fvm_config.json::flutterSdkVersion` is the SoT for the Flutter
  toolchain — local devs run `fvm flutter …`; CI passes the same value into
  `subosito/flutter-action@v2`'s `flutter-version` field via a tiny
  `actions/github-script` step.
- `idl/codegen/generate_dart.sh` calls `dart pub run protoc_plugin` (not
  `pub global run`) so the workspace pin is the only resolution path.

### 6.3 How to add a new dep

1. Used by ≥ 2 sub-packages → add it to the workspace
   `pubspec.yaml::dependencies`. Used by exactly one → add it to that
   sub-package only.
2. `cd sdk/runanywhere-flutter && melos bootstrap` (calls `flutter pub get`
   in each member).
3. Commit each affected `pubspec.lock`.

### 6.4 How to bump a dep

1. Edit the workspace `pubspec.yaml` (or the sub-package for leaf-only deps).
2. `melos bootstrap` to refresh every `pubspec.lock`.
3. Verify:
   ```bash
   cd sdk/runanywhere-flutter
   melos run analyze
   melos run test
   ```
4. Flutter SDK bump → edit `.fvm/fvm_config.json`, `fvm install && fvm use`,
   then `melos bootstrap`.
5. `protoc_plugin` bump → edit the workspace `dev_dependencies` pin, run
   `./idl/codegen/generate_dart.sh`, commit refreshed `lib/generated/*.pb.dart`.

### 6.5 CI validation

`flutter-pubget` in `pr-build.yml` runs `flutter pub get` + `flutter analyze`;
a drifted workspace constraint fails resolution. `idl-drift-check.yml`
regenerates Dart bindings using the workspace's `protoc_plugin` pin — a
different version produces a diff and fails the gate. The dynamic
`flutter-version` step ties the CI Flutter SDK to `.fvm/fvm_config.json`.

---

## 7. TypeScript (Web + React Native)

### 7.1 Source of truth

| Concern | File | Notes |
|---|---|---|
| Cross-workspace dep pins | `dependencies/versions.json` (NEW) | JSON map: `{ "react": "19.2.0", "react-native": "0.83.1", "typescript": "~5.9.2", "protobufjs": "7.x", … }`. Both Web (npm) and RN (Yarn 3 Berry) resolve against this. |
| Drift enforcement | `.syncpackrc.json` (NEW at repo root) | Syncpack config that fails CI when two workspaces pin the same package to different versions. |
| Web package manager | `sdk/runanywhere-web/package.json` (npm workspaces) | Keep npm 10 on Node 20 LTS. |
| RN package manager | Repo-root `package.json::packageManager: "yarn@3.6.1"` (Berry) | Keep Yarn 3; do not mix npm + yarn at the same workspace root. |
| Node toolchain | `NODE_VERSION=20` in `sdk/runanywhere-commons/VERSIONS` | CI reads via `load-versions.sh`. |

### 7.2 How build files consume it

- A `scripts/sync-ts-versions.mjs` Node script reads
  `dependencies/versions.json` and rewrites every matching entry in every
  `package.json`. Run it via `npm run sync-versions`; CI runs the same script
  with `--check` to fail the PR on drift.
- `.syncpackrc.json` declares one canonical version per package across
  every workspace (Web core / llamacpp / onnx, RN core / llamacpp / onnx,
  `sdk/shared/proto-ts`, and the example apps). `npx syncpack list-mismatches`
  must report `0`.
- Web (npm workspaces): `npm install` at `sdk/runanywhere-web/`.
- RN (Yarn 3 Berry): `yarn install --immutable` at the **repo root** — the
  Yarn workspaces declaration is at the repo-root `package.json`, not inside
  `sdk/runanywhere-react-native/`. (`.github/workflows/pr-build.yml::rn-typecheck`
  documents why; running yarn from the sub-folder fails Yarn's project
  detection.)

### 7.3 How to add a new dep

1. Shared by ≥ 2 workspaces → add `"name": "x.y.z"` to
   `dependencies/versions.json`. Otherwise → just the consuming `package.json`.
2. Add the dep entry to the consuming `package.json::dependencies` (or
   `devDependencies`).
3. `npm install` at the Web root **and** `yarn install --immutable` at the
   repo root for RN.
4. `npx syncpack list-mismatches` → `0`.
5. Commit `dependencies/versions.json`, every affected `package.json`,
   `package-lock.json` (Web), and `yarn.lock` (RN).

### 7.4 How to bump a dep

1. Edit `dependencies/versions.json` — single-line value change.
2. `node scripts/sync-ts-versions.mjs` to propagate to every `package.json`.
3. Re-resolve both package managers:
   ```bash
   cd sdk/runanywhere-web && npm install --no-audit --no-fund
   # RN — repo root, Yarn 3 Berry
   corepack enable && corepack prepare yarn@3.6.1 --activate
   yarn install --immutable
   ```
4. Verify:
   ```bash
   cd sdk/runanywhere-web && npm run typecheck && npm run test
   yarn workspace @runanywhere/core typecheck
   yarn workspace @runanywhere/llamacpp typecheck
   yarn workspace @runanywhere/onnx typecheck
   ```
5. `npx syncpack list-mismatches` must still report `0`.

### 7.5 CI validation

`web-typecheck` + `rn-typecheck` in `pr-build.yml` already run typechecks
across every workspace. Add `npx syncpack list-mismatches` to both jobs to
gate on cross-workspace drift. `--immutable` (yarn) and `npm install` both
fail loud if the lockfile would have to change — that catches the
"developer ran the wrong package manager" footgun. Node version flows from
`VERSIONS::NODE_VERSION` into `actions/setup-node`.

---

## 8. Bump matrix — at-a-glance

| Bumping | Edit | Re-run | CI gate |
|---|---|---|---|
| `llama.cpp` tag | `VERSIONS::LLAMACPP_VERSION` | `cmake --preset macos-debug && cmake --build --preset macos-debug` | `pr-build/macos-{debug,release}` |
| ONNX Runtime (per OS) | `VERSIONS::ONNX_VERSION_<PLATFORM>` | as above + vendor scripts under `sdk/runanywhere-web/wasm/scripts/` | `pr-build/<platform>` |
| Android NDK | `gradle.properties::racNdkVersion` **and** `VERSIONS::NDK_VERSION` (same commit) | `./gradlew :runanywhere-kotlin:assembleDebug` | `pr-build/kotlin-android` |
| Kotlin / AGP / Compose / Ktor / … | `gradle/libs.versions.toml::[versions]` | `./gradlew :runanywhere-kotlin:compileKotlinJvm` | `kotlin-android` |
| SwiftPM dep | `Package.swift` + `Package.resolved` | `swift package resolve && swift build` | `swift-spm` + `check_package_resolved.sh` |
| Swift SDK semver | `VERSION` then `./idl/codegen/generate_version_swift.sh` | `swift build` | `swift-spm` |
| Swift lint tooling | `Mintfile` | `mint bootstrap` | local `mint run swiftlint --strict` mirrored in CI |
| Flutter shared dep | workspace `pubspec.yaml::dependencies` | `melos bootstrap` | `flutter-pubget` |
| Flutter SDK | `.fvm/fvm_config.json::flutterSdkVersion` | `fvm install && fvm use && melos bootstrap` | `flutter-pubget` (dynamic `flutter-version`) |
| `protoc_plugin` (Dart) | workspace `pubspec.yaml::dev_dependencies` | `melos bootstrap && ./idl/codegen/generate_dart.sh` | `idl-drift-check` |
| TS dep shared Web ↔ RN | `dependencies/versions.json` | `npm install` (Web) + `yarn install --immutable` (repo root for RN) | `web-typecheck` + `rn-typecheck` + `syncpack list-mismatches` |
| Node version | `VERSIONS::NODE_VERSION` | re-run `actions/setup-node` | every TS job |

## 9. Glossary

- **SoT** — Single source of truth. The file that owns one canonical value
  per concern; everything else reads from it.
- **Lockfile** — `Package.resolved` (Swift), `pubspec.lock` (Flutter),
  `package-lock.json` / `yarn.lock` (TS). Captures transitive resolution.
  The SoT covers direct deps; the lockfile covers everything they pulled in.
- **Version catalog** — Gradle's TOML-based dep registry
  (`gradle/libs.versions.toml`). Aliases (`libs.kotlinx.coroutines.core`)
  are codegen'd into the Kotlin DSL.
- **`.upToNextMinor`** — SwiftPM range specifier that pins to one minor:
  `1.2.3 ..< 1.3.0`. Stricter than the default `.from("1.2.3")` (any
  future major).
- **Workspace dep (Melos 7 / npm workspaces / Yarn Berry)** — a dep
  declared at a workspace root that all members inherit. Lets us bump in
  one place.
- **Syncpack** — npm tool that fails CI when two workspaces pin the same
  package to different versions. Stand-in for "Gradle Version Catalog, but
  for JS".
