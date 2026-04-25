# V2 Reality Reconciliation — Phase 1 Verification Matrix

Date: 2026-04-24
Branch: `feat/v2-architecture`
Baseline commit: `5cd92336` (`v2 reality audit: stabilize tree before verification`)

## Summary

All required clean-baseline gates passed from the current tree.

One command-path caveat: Web packages are an npm workspace under
`sdk/runanywhere-web/`. Running `yarn` from nested web package directories
fails because a root-level `yarn.lock` in `runanywhere-sdks-main/` causes
Yarn 3 to treat the repository root as the project. Web gates therefore use
`npm --prefix sdk/runanywhere-web ...` and `npm --prefix examples/web/RunAnywhereAI ...`.

## Gate Matrix

| ID | Gate | Command/log | Result | Notes |
|---|---|---|---|---|
| T1.1 | C++ macOS configure/build/ctest | `verification/2026-04-24/t1_cpp_macos.log` | PASS | `ctest --preset macos-debug --output-on-failure` succeeded. |
| T1.2 | Android core all ABIs | `verification/2026-04-24/t1_android_core.log` | PASS | `build-core-android.sh` succeeded with NDK `29.0.13113456`. |
| T1.3 | WASM core | `verification/2026-04-24/t1_wasm.log` | PASS | `build-core-wasm.sh` succeeded. |
| T1.4 | Apple xcframeworks | `verification/2026-04-24/t1_xcframework.log` | PASS | `build-core-xcframework.sh` succeeded. |
| T1.5 | Swift package | `verification/2026-04-24/t1_swift_build.log` | PASS | Header sync + `swift build --package-path .` succeeded. |
| T1.6 | iOS native sample | `verification/2026-04-24/t1_ios_sample.log` | PASS | `xcodebuild` simulator build succeeded. |
| T1.7 | Kotlin SDK | `verification/2026-04-24/t1_kotlin.log` | PASS | `compileKotlinJvm jvmTest` succeeded. |
| T1.8 | Android native sample | `verification/2026-04-24/t1_android_sample.log` | PASS | `:app:assembleDebug` succeeded. |
| T1.9 | RN core + Android sample | `verification/2026-04-24/t1_rn_tsc.log`, `verification/2026-04-24/t1_rn_android.log` | PASS | `yarn tsc --noEmit` and `:app:assembleDebug` succeeded. |
| T1.10 | RN iOS sample | `verification/2026-04-24/t1_rn_ios.log` | PASS | `pod install` + `xcodebuild` succeeded. |
| T1.11 | Web packages + sample | `verification/2026-04-24/t1_web_typecheck_npm.log`, `verification/2026-04-24/t1_web_build_npm.log`, `verification/2026-04-24/t1_web_sample_npm.log` | PASS | Used npm workspace commands, not nested Yarn. |
| T1.12 | Flutter packages + sample | `verification/2026-04-24/t1_flutter_*.log`, `verification/2026-04-24/t1_flutter_sample.log` | PASS | Analyze x4 + APK + iOS simulator build succeeded. |
| T1.13 | Cross-SDK harness runners | `verification/2026-04-24/t1_harness_npm.log` | PASS | C++ parity/cancel/perf, Kotlin filters, Dart tests, RN Jest, Web Vitest succeeded. |

## Verdict

Phase 1 clean-baseline verification is green.
