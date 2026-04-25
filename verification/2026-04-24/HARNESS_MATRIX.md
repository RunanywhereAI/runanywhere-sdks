# Phase 9 Cross-SDK Harness Matrix

Date: 2026-04-24
Repo: `runanywhere-sdks-main`

## Summary

All 6 requested cross-SDK harness runners passed from the local tree.

Swift macOS reality: `RACommons.xcframework` now includes a `macos-arm64`
slice, which is the binary target linked by the macOS Swift parity/cancel/perf
test target. Full macOS backend xcframework slices were intentionally not
expanded in this phase: a full `macos-release` build hits llama.cpp
`ggml-metal` Objective-C++ compile failures on this Xcode/SDK, and ONNX macOS
packaging is dylib-based rather than the iOS static archive layout. The harness
does not link those backend products.

## Runner Matrix

| ID | Runner | Command | Log | Result | Notes |
|---|---|---|---|---|---|
| T9.1 | Swift macOS parity/cancel/perf | `swift test --filter "parity\|cancel\|perf"` | `verification/2026-04-24/t9_swift_test.log` | PASS | 4 selected XCTest cases ran: parity, cancel, and 2 perf assertions. |
| T9.2 | Kotlin parity | `cd sdk/runanywhere-kotlin && ./gradlew jvmTest --tests '*StreamingParity*'` | `verification/2026-04-24/t9_kotlin_streaming_parity.log` | PASS | Gradle `BUILD SUCCESSFUL`; root `jvmTest` executed. |
| T9.3 | Dart parity + perf | `cd sdk/runanywhere-flutter/packages/runanywhere && flutter test test/parity_test.dart test/perf_bench_test.dart` | `verification/2026-04-24/t9_dart_parity_perf.log` | PASS | 4 Flutter tests passed. |
| T9.4a | React Native core harness | `cd sdk/runanywhere-react-native/packages/core && yarn test --passWithNoTests` | `verification/2026-04-24/t9_rn_core_test.log` | PASS | 2 Jest suites / 3 tests passed. |
| T9.4b | Web core harness | `cd sdk/runanywhere-web && npm run test -w packages/core -- --run` | `verification/2026-04-24/t9_web_core_test.log` | PASS | 2 Vitest files / 3 tests passed. |
| T9.5 | C++ ctest harness | `ctest --preset macos-debug -R "parity\|cancel\|perf" --output-on-failure` | `verification/2026-04-24/t9_cpp_ctest_harness.log` | PASS | 6/6 filtered CTest cases passed. |

## Additional Verification

| Gate | Command | Log | Result | Notes |
|---|---|---|---|---|
| xcframework rebuild | `./scripts/build-core-xcframework.sh` | `verification/2026-04-24/t9_xcframework.log` | PASS | Rebuilt Apple xcframeworks; `RACommons` has `ios-arm64`, `ios-arm64-simulator`, and `macos-arm64`. |
| Swift package build | `swift build --package-path .` | `verification/2026-04-24/t9_swift_build.log` | PASS | Build completed with existing Swift warnings. |
| C++ full ctest | `ctest --preset macos-debug --output-on-failure` | `verification/2026-04-24/t9_cpp_ctest_full.log` | PASS | 67/67 tests passed. |

## Verdict

Phase 9 harness reality is green: 6/6 requested runners passed, with the Swift
macOS harness backed by a local `RACommons.xcframework` `macos-arm64` slice.
