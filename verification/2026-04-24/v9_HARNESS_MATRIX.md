# V9 Remediation Harness Matrix

Date: 2026-04-24
Branch: `feat/v2-architecture`

## Summary

Targeted post-remediation gates passed for the surfaces changed in this plan.

| Gate | Command / log | Result | Notes |
|---|---|---|---|
| C++ full ctest | `verification/2026-04-24/v9_cpp_ctest_full.log` | PASS | 69/69 tests passed, including new `runtime_cpu_session_tests` and `engine_uses_runtime_tests`. |
| Swift build | `verification/2026-04-24/v9_swift_build.log` | PASS | `swift build --target RunAnywhere` passed after header sync. |
| Kotlin compile | `verification/2026-04-24/v9_kotlin_compile.log` | PASS | `compileKotlinJvm --offline` succeeded after unused dependency removal. |
| Shared TS proto | `verification/2026-04-24/v9_proto_ts_typecheck.log` | PASS | `@runanywhere/proto-ts` typecheck passed. |
| Web build | `verification/2026-04-24/v9_web_core_build.log` | PASS | Web core `tsc` build passed. |
| Web tests | `verification/2026-04-24/v9_web_core_test.log` | PASS | 4 Vitest files / 9 tests passed, including singleton module lifecycle tests and streaming harness. |
| RN typecheck + tests | `verification/2026-04-24/v9_rn_core_tsc_test.log` | PASS | RN `tsc` + 2 Jest suites / 3 tests passed. |
| Flutter sample analyze | `verification/2026-04-24/v9_flutter_sample_analyze.log` | PASS | `flutter analyze --no-fatal-infos` found no issues. |

## Not Re-run In This Pass

Full Android core all-ABI, WASM, Apple xcframework, and iOS/RN/Flutter/Web sample
builds were not re-run in this final pass. Their prior green evidence remains in
`MATRIX.md`; this remediation focused on changed runtime, generated TS, Web,
RN, Kotlin, Swift-header, and sample source surfaces.
