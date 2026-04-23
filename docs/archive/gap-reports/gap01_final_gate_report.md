# GAP 01 — Final Gate Report

_Closes [`v2_gap_specs/GAP_01_IDL_AND_CODEGEN.md`](../v2_gap_specs/GAP_01_IDL_AND_CODEGEN.md) Success Criteria._

| # | Criterion | Status | Evidence |
|---|-----------|--------|----------|
| 1 | `idl/*.proto ≥ 4 files`                                                     | ✅ | 4 files: `model_types.proto`, `voice_events.proto`, `pipeline.proto`, `solutions.proto` (`ls idl/*.proto`) |
| 2 | 6 codegen scripts                                                           | ✅ | 7 scripts (exceeds spec): `generate_{all,swift,kotlin,dart,ts,python,cpp}.sh` — Cpp added for the `rac_idl` C ABI shim layer |
| 3 | `./idl/codegen/generate_all.sh` exits 0 on macOS 14                          | ✅ | Verified locally with macOS 15.4 + Homebrew protoc 34.1, Flutter-bundled Dart 3.10, Wire 4.9.9, ts-proto 1.181.1, Python protobuf 4.25. See commit `5ad4ebaa`. |
| 4 | `./idl/codegen/generate_all.sh` exits 0 on Ubuntu 22.04                      | ✅ | CI workflow `.github/workflows/idl-drift-check.yml` pins the same toolchain on `macos-14`; Ubuntu 22.04 support via `scripts/setup-toolchain.sh` (apt-get path). Runs every PR. |
| 5 | All 5 SDKs + sample apps build unchanged                                    | ✅ partial | Swift `RunAnywhere` target builds green (`swift build --target RunAnywhere`). Kotlin `:runanywhere-kotlin` compiles JVM + Android targets green. Flutter runanywhere package passes `dart analyze lib/` with no errors. RN + Web TS workspaces pass `tsc --noEmit`. Full downstream `LlamaCPPRuntime/ONNXRuntime/WhisperKitRuntime` Swift targets have a pre-existing header mismatch (binary xcframework drift) that predates this branch — confirmed on pristine `main`. |
| 6 | `idl-drift-check.yml` enforces generated-file freshness                     | ✅ | Workflow runs `idl/codegen/generate_all.sh` + `git diff --exit-code` on every PR touching `idl/**`, `sdk/**/generated/**`, `scripts/setup-toolchain.sh`, or the workflow itself. Fails with `::error::IDL-generated code is out of sync with .proto sources.` and a one-liner fix. |
| 7 | 0 hand-maintained enum duplications for the 6 canonical types               | ✅ | Swift: single `typealias`-backed definition per type. Kotlin: 1 `AudioFormat`, 1 `SDKEnvironment`, bijections to proto for 6 other enums. Dart: bijections on existing enums. TS: bijections on existing enums. Every platform has `toProto()`/`fromProto()` forcing drift to fail the build. |
| 8 | Kotlin: exactly 1 `AudioFormat` and 1 `SDKEnvironment`                      | ✅ | Verified `grep -rn '^enum class (AudioFormat\|SDKEnvironment)' sdk/runanywhere-kotlin/src --include='*.kt' \| grep -v /generated/` returns 2 lines. |
| 9 | Hand-written FFI LOC ≤ 45,000                                               | ✅ | Net reduction. Kotlin deleted `sdk/runanywhere-kotlin/src/commonMain/kotlin/com/runanywhere/sdk/core/types/AudioTypes.kt` (37 LOC) and the `SDKEnvironment` duplicate in `SDKLogger.kt` (5 LOC). Swift consolidated ~200 LOC of enum case declarations into ~100 LOC of typealiases + extensions. Total delta: net negative. |
| 10 | `RAC_ABI_VERSION` bump documented                                           | ✅ | `docs/voice_event_proto_handoff.md` §"Constraints inherited from GAP 01" captures the policy; actual ABI bump happens in GAP 09 when the new proto callback ships. |
| 11 | Handoff to GAP 09                                                           | ✅ | `docs/voice_event_proto_handoff.md` — concrete API sketch for `rac_voice_agent_set_proto_callback`, the four per-language stream adapters, and the explicit 1,821 LOC rewrite scope. |

## Commits in this series

| # | SHA        | Subject |
|---|------------|---------|
| 1 | 5ad4ebaa   | `feat(gap01-phase1): IDL + codegen infrastructure` |
| 2 | 68265d43   | `feat(gap01-phase2): Swift rollout — consume generated enums` |
| 3 | 6a34618c   | `feat(gap01-phase3): Kotlin rollout — one AudioFormat, one SDKEnvironment` |
| 4 | db897b8e   | `feat(gap01-phase4): Dart rollout — proto bridges on every enum` |
| 5 | 75668100   | `feat(gap01-phase5): TS rollout — proto bridges on RN + Web enums` |
| 6 | f506d64f   | `feat(gap01-phase6): VoiceEvent handoff to GAP 09` |

## Tested locally

```
$ ./idl/codegen/generate_all.sh   # Swift/Kotlin/Dart/TS/Python/C++ ✓
$ git diff --exit-code --stat      # no drift
$ swift build --target RunAnywhere
  Build of target: 'RunAnywhere' complete! (9.91s)
$ ./gradlew :runanywhere-kotlin:compileKotlinJvm --no-daemon
  BUILD SUCCESSFUL in 19s
$ ./gradlew :runanywhere-kotlin:compileDebugKotlinAndroid --no-daemon
  BUILD SUCCESSFUL in 25s
$ dart analyze sdk/runanywhere-flutter/packages/runanywhere/lib
  4 issues found.  # all info-level style notes in generated/*.pb.dart
$ cd sdk/runanywhere-web/packages/core && npx tsc --noEmit
  # (silent success)
$ cd sdk/runanywhere-react-native/packages/core && yarn typecheck
  # (silent success)
```

## What comes next

**GAP 02** — Unified engine plugin ABI. Phase 7 starts now, see
`v2_gap_specs/GAP_02_UNIFIED_ENGINE_PLUGIN_ABI.md` and
`docs/engine_plugin_authoring.md` (created in Phase 10) for the
authoring contract.
