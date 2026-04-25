# V2 Surgical Remediation Summary

Date: 2026-04-24
Branch: `feat/v2-architecture`

## What This Pass Kept In Scope

- L1 runtime truth and first execution path:
  - CPU runtime now delegates sessions through registered providers.
  - llama.cpp blocking generation starts through the CPU runtime provider path.
  - Runtime anti-regression tests were added.
- ONNX / Sherpa ownership cleanup:
  - ONNX owns embeddings + ONNXRT.
  - Sherpa owns STT / TTS / VAD / wakeword plus legacy `rac_*_onnx_*` speech compatibility symbols.
- RN/Web TypeScript generated-code dedup:
  - Shared generated TS protos and stream wrappers moved to `@runanywhere/proto-ts`.
  - Both `src` and `dist` are intentionally tracked because package exports
    point at `dist`; the IDL drift workflow now rebuilds `dist` and fails on
    divergence.
  - RN keeps Nitro-specific generated files locally.
- Web singleton wiring:
  - LlamaCpp backend wires `setRunanywhereModule`, `HTTPAdapter`, and `ModelRegistryAdapter`.
  - Shutdown clears all singleton/default module hooks.
- Sample HTTP scope:
  - Remaining direct sample HTTP calls are annotated as `SAMPLE_HTTP_CARVE_OUT`.
- Review hygiene:
  - Generated file attributes tightened.
  - Legacy RN/Web file blocklist added.
  - Kotlin unused HTTP client dependencies removed.
  - Verification shards were collapsed into this summary plus matrix files to
    keep the PR diff reviewable.

## What Was Reclassified Instead Of Mechanically Split

The original remediation plan asked to split several huge bridge/native files.
Discovery showed those files are native-symbol and shared-state boundaries, so a
raw cut-and-paste split would be unsafe without support-layer and symbol-parity
tests.

Reclassified areas:

- C++ JNI monolith: requires `jni_common.hpp` / shared runtime helpers first.
- Kotlin `RunAnywhereBridge.kt`: JNI owner object must stay stable until symbol parity tests exist.
- Kotlin `CppBridge*`, Flutter `dart_bridge_*`, RN native bridge files, Swift large bridge/type files, and Web `ModelDownloader.ts`: staged split plans, not blind churn.

## Verification Evidence

See:

- `MATRIX.md` for the baseline gate matrix.
- `HARNESS_MATRIX.md` for the Phase 9 cross-SDK harness.
- `v9_HARNESS_MATRIX.md` for the targeted post-remediation verification.

## PR Cleanup Notes

- `@runanywhere/proto-ts` intentionally commits both `src` and `dist` because
  package exports point at `dist`; `idl-drift-check.yml` now regenerates source
  and rebuilds `dist` to catch drift.
- RN SDK and RN sample remain Yarn-based; Web sample remains npm-based and the
  extra branch-added pnpm/yarn locks were removed.
- Broad legacy docs still contain old helper-script names in some places. Those
  are documentation refresh follow-ups and were not expanded in this cleanup to
  avoid growing the review diff.
- The rewritten PR CI narrows the v2 review path around root CMake, IDL drift,
  streaming perf, and blocklists. Any Windows/lint coverage gaps should be
  handled as CI follow-up rather than mixed into this architectural cleanup.

Latest targeted remediation gates:

- C++ ctest: 69/69 passed.
- Swift `RunAnywhere` build: passed.
- Kotlin `compileKotlinJvm --offline`: passed.
- `@runanywhere/proto-ts` typecheck: passed.
- Web core typecheck/build/Vitest: passed.
- RN core `tsc`/Jest: passed.
- Flutter sample analyze: passed.
