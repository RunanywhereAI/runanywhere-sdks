# v0.20.0 Release Plan

_Plan only. No version bump or release execution happens until the v2
close-out (Phases A through J in the plan) lands and this doc is
explicitly approved._

## Why v0.20.0 (not v1.0.0 or v3.0.0)

Three numbering options were considered:

| Option | Signal | Rationale |
|---|---|---|
| **v0.20.0** (recommended) | Additive minor in the existing 0.x line | The C ABI added the unified `rac_engine_vtable_t` (`RAC_PLUGIN_API_VERSION = 3u`); the legacy `rac_service_*` registry was deleted; voice agent rewritten across all 5 SDKs. These ARE breaking, but we're still in 0.x semver where minors can break — and the consumer base is small enough that the explicit migration matrix below is sufficient. |
| v1.0.0 | "We commit to API stability now" | Premature. Phase H (Kotlin HTTP into commons) and the Web `VoiceAgent` story are still in flight. Locking 1.0 forces another major bump within months. |
| v3.0.0 | Match `RAC_PLUGIN_API_VERSION = 3u` | Conflates the C-ABI version with the SDK version. Internal v3.x markers were already used (see deleted `release(v3.1.x)` commits) and caused enough confusion that the user reverted them. |

## Files that get version-bumped (atomic — all in one commit)

When approved, the bump touches **14 files**:

| # | File | Current | After |
|---|---|---|---|
| 1 | `sdk/runanywhere-commons/VERSION` | 0.19.13 | 0.20.0 |
| 2 | `sdk/runanywhere-commons/VERSIONS` | 0.19.13 | 0.20.0 |
| 3 | `Package.swift` (`let sdkVersion`) | "0.19.13" | "0.20.0" |
| 4 | `sdk/runanywhere-flutter/packages/runanywhere/pubspec.yaml` | 0.19.13 | 0.20.0 |
| 5 | `sdk/runanywhere-flutter/packages/runanywhere_llamacpp/pubspec.yaml` | 0.19.13 | 0.20.0 |
| 6 | `sdk/runanywhere-flutter/packages/runanywhere_onnx/pubspec.yaml` | 0.19.13 | 0.20.0 |
| 7 | `sdk/runanywhere-flutter/packages/runanywhere_genie/pubspec.yaml` | 0.19.13 | 0.20.0 |
| 8 | `sdk/runanywhere-web/package.json` (root + 3 packages) | 0.19.13 | 0.20.0 |
| 9 | `sdk/runanywhere-web/packages/core/package.json` | 0.19.13 | 0.20.0 |
| 10 | `sdk/runanywhere-web/packages/onnx/package.json` | 0.19.13 | 0.20.0 |
| 11 | `sdk/runanywhere-web/packages/llamacpp/package.json` | 0.19.13 | 0.20.0 |
| 12 | `sdk/runanywhere-react-native/package.json` (root + core) | 0.19.13 | 0.20.0 |
| 13 | `sdk/runanywhere-react-native/packages/core/package.json` | 0.19.13 | 0.20.0 |
| 14 | `sdk/runanywhere-kotlin/gradle.properties` (`VERSION_NAME`) | 0.19.13 | 0.20.0 |

Auth-shaped files that mention `0.19.13` as a string literal in HTTP
headers (e.g. `CppBridge+Auth.swift`, `AuthModels.kt`, the various
`bridges/AuthBridge.cpp` files, `BuildConfig.kt` constants) are
auto-updated by the same scripted bump.

## Migration matrix — breaking changes

### 1. C ABI: `RAC_PLUGIN_API_VERSION = 3u` (was 2u)

- Legacy `rac_service_*` registry: GONE. All engine registration goes
  through `rac_plugin_register(rac_plugin_entry_<name>())`.
- Every per-primitive ops struct (`rac_llm_service_ops_t`, etc.) gained
  a mandatory `create` op. Plugins built against `2u` reject at load
  with `RAC_ERROR_ABI_VERSION_MISMATCH`.
- New: `rac_engine_vtable_t` unified vtable. New: `EngineRouter` +
  `HardwareProfile` for capability-based routing.
- New: `rac_plugin_loader.h` — `dlopen` path + `RAC_STATIC_PLUGIN_REGISTER`
  static companion (GAP 03).

**Consumer action**: third-party plugins must rebuild against the v3u
vtable shape. See [`docs/engine_plugin_authoring.md`](../engine_plugin_authoring.md).

### 2. Voice Session API: DELETED

`VoiceSessionEvent`, `VoiceSessionHandle`, `startVoiceSession`,
`processVoice`, `streamVoiceSession` — removed across Swift, Kotlin,
Dart, RN, Web. Replacement: `VoiceAgentStreamAdapter` proto-stream
pattern (uniform across the 5 SDKs).

**Migration**: see `docs/migrations/VoiceSessionEvent.md`.

### 3. Flutter SDK: god-class deletion (Phase C)

Once Phase C lands, the static `RunAnywhere` class in
[`packages/runanywhere/lib/public/runanywhere.dart`](../../sdk/runanywhere-flutter/packages/runanywhere/lib/public/runanywhere.dart)
is DELETED entirely (no `@Deprecated` shim). All consumers move to
`RunAnywhereSDK.instance.<capability>.<method>()`.

**Migration**: see [`docs/migrations/v3_to_v4_flutter.md`](../migrations/v3_to_v4_flutter.md).
The mapping table covers every public symbol; sed-friendly 1:1 swaps.

### 4. Web SDK: `VoiceAgent` stub class DELETED (Phase D)

The throw-`componentNotReady` stub class
[`Public/Extensions/RunAnywhere+VoiceAgent.ts`](../../sdk/runanywhere-web/packages/core/src/Public/Extensions/RunAnywhere+VoiceAgent.ts)
is removed. Replacement: `VoiceAgentStreamAdapter` (WASM proto-stream,
parity with mobile) OR `VoicePipeline` (TS-side composition, ExtensionPoint).

**Migration**: see [`docs/sdks/web-sdk.md`](../sdks/web-sdk.md) (Phase D-4 deliverable).

### 5. Kotlin SDK: download internals refactored (Phase H)

User-facing API of `RunAnywhere.downloadModel(...)` is unchanged. The
internal HTTP transport moves from
[`CppBridgeDownload.kt`](../../sdk/runanywhere-kotlin/src/jvmAndroidMain/kotlin/com/runanywhere/sdk/foundation/bridge/extensions/CppBridgeDownload.kt)
(1,485 LOC of `HttpURLConnection`) to commons via the new
`rac_http_client_t` C ABI (Phase H-2). Consumers see no API change but
gain a single canonical retry/resume implementation shared across iOS,
Android, Flutter, RN.

### 6. RN SDK: tool-calling backed by commons (Phase G-1)

`HybridRunAnywhereCore.cpp` tool-call methods (`parseToolCallFromOutput`,
`formatToolsForPrompt`, etc.) move from TS-stub to real `rac_tool_call_*`
calls. Consumers see no API change but stop getting `"{}"` / empty-string
results when commons isn't present.

### 7. Kotlin SDK: `gRPC*Client.kt` generated stubs deleted

The `Wire 4.x` gRPC client classes
(`GrpcDownloadClient`, `GrpcLLMClient`, `GrpcVoiceAgentClient`,
`DownloadClient`, `LLMClient`, `VoiceAgentClient`) were never linked to
a runtime. Deleted from `commonMain/kotlin/.../generated/` and stripped
from `idl/codegen/generate_kotlin.sh`. Real streaming uses
`VoiceAgentStreamAdapter` + `set_proto_callback`.

## Release sequence

After Phases A-J have all landed and `feat/v2-architecture` is
merge-ready:

```bash
# 0. Pre-flight
git checkout feat/v2-architecture
git pull --ff-only
./idl/codegen/generate_all.sh && git diff --exit-code  # no IDL drift

# 1. Bump versions across the 14 files
./scripts/bump-version.sh 0.20.0   # script lives in the close-out PR

# 2. Verify all the build-matrix presets stay green
cmake --preset macos-debug && cmake --build --preset macos-debug
cmake --preset linux-debug && cmake --build --preset linux-debug
cmake --preset android-arm64
cmake --preset ios-device
cmake --preset wasm
cd sdk/runanywhere-react-native/packages/core && yarn tsc --noEmit
cd ../../../runanywhere-web/packages/core && yarn tsc --noEmit
cd ../../runanywhere-flutter/packages/runanywhere && flutter analyze && flutter test
cd ../../../runanywhere-kotlin && ./gradlew compileKotlinJvm assembleAndroid

# 3. Squash-merge to main
gh pr create --base main --title "v0.20.0: v2 architecture close-out" \
             --body-file docs/release/v0_20_0_release_plan.md
gh pr merge --squash --delete-branch=false  # keep the branch for tag

# 4. Tag + Github Release with changelog from this doc
git tag -a v0.20.0 -m "v0.20.0: v2 architecture close-out"
git push origin v0.20.0
gh release create v0.20.0 \
  --title "v0.20.0 \u2014 v2 architecture close-out" \
  --notes-file docs/release/v0_20_0_release_plan.md

# 5. Build and upload xcframeworks (operator step on macOS box)
#
# Prereqs on the operator's release machine (see also Phase J-1 report:
# docs/v2_closeout_phase_j1_report.md):
#   - Xcode 15+ with iOS SDK
#   - ./sdk/runanywhere-commons/scripts/ios/download-onnx.sh has been run,
#     populating sdk/runanywhere-commons/third_party/onnxruntime-ios/
#   - `gh auth status` green for github.com/RunanywhereAI/runanywhere-sdks
#   - The v0.20.0 GitHub release was created in step 4 above
#
# Optional preflight (validates the pipeline without invoking cmake):
#   DRY_RUN=1 ./scripts/release-swift-binaries.sh 0.20.0
#
# Real build:
./scripts/release-swift-binaries.sh 0.20.0
#
# This produces three zips in release-artifacts/native-ios-macos/:
#   RACommons-ios-v0.20.0.zip
#   RABackendLLAMACPP-ios-v0.20.0.zip
#   RABackendONNX-ios-v0.20.0.zip
# and patches the corresponding `checksum:` lines in Package.swift.
#
# Upload them to the existing v0.20.0 release (single call, glob expansion):
gh release upload v0.20.0 release-artifacts/native-ios-macos/*.zip

# Commit + push the Package.swift checksum bump alongside the version bump
# from step 1 (same branch, separate commit for bisect-friendliness):
git add Package.swift && \
    git commit -m "release: bump xcframework checksums for v0.20.0" && \
    git push origin HEAD

# Smoke-test from a fresh clone (operator should run this before
# declaring v0.20.0 done):
cd /tmp && rm -rf v020-smoke && \
    git clone https://github.com/RunanywhereAI/runanywhere-sdks v020-smoke && \
    cd v020-smoke && swift package resolve && swift build -c release
# Expected: all three binary targets downloaded from the v0.20.0 release
# and verified against the checksums we just committed.

# 6. Publish to package registries
cd sdk/runanywhere-flutter/packages/runanywhere      && dart pub publish
cd ../runanywhere_llamacpp                           && dart pub publish
cd ../runanywhere_onnx                               && dart pub publish
cd ../runanywhere_genie                              && dart pub publish

cd ../../../runanywhere-react-native/packages/core   && npm publish --access=public
cd ../../runanywhere-web/packages/core               && npm publish --access=public
cd ../onnx                                           && npm publish --access=public
cd ../llamacpp                                       && npm publish --access=public

cd ../../../runanywhere-kotlin && ./gradlew publish  # Maven Central via signed staging
```

## Post-merge tasks

| When | Task | Owner |
|---|---|---|
| Within 1 week | Update each SDK's `README.md` with v0.20.0 install snippets | SDK owner per platform |
| Within 1 week | Sample apps validated against published artifacts (not local) | QA |
| Within 2 weeks | Migration support: monitor `gh issue` for migration friction | Engineering on rotation |
| Within 1 month | Evaluate whether to accelerate v0.21 (HTTP-into-commons rollout to iOS/Flutter/RN) or stay on the v0.20 line | Engineering |

## Rollback contingency

If a P0 surfaces post-tag:
- Yank from package registries (`npm unpublish`, `pub retract`,
  `gh release delete`) within 24h
- Hot-fix on a `release/0.20.x` branch; tag `v0.20.1`
- Keep `feat/v2-architecture` open as the long-running integration
  branch until v0.21 stabilises

## What's NOT in this release

- Real wakeword detector (Phase F-3 — Sherpa KWS integration; deferred to v0.21+)
- iOS / Flutter / RN download paths migrated to commons HTTP (Phase H
  starts with Kotlin; iOS/Flutter/RN follow once the C ABI proves out)
- LLM streaming via proto-encoded `LLMStreamEvent` (Phase G-2 — voice
  is on proto streams; LLM still per-SDK hand-rolled, scheduled for v0.21)
- Web `LLMStreamAdapter` parity with mobile (depends on G-2)
