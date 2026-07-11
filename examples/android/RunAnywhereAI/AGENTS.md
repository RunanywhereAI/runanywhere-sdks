# AGENTS.md — Android RunAnywhereAI Example

This file applies to `examples/android/RunAnywhereAI/`. Run commands from this directory unless noted otherwise.

## Common commands

```bash
./scripts/smoke.sh                         # Fast static SDK-usage check
../../../scripts/build/build-core-android.sh arm64-v8a
./scripts/stage-sdk-aars.sh debug          # Required after SDK/native changes
./scripts/verify.sh                        # Strict debug APK build from staged AARs
./gradlew :app:testDebugUnitTest           # JVM tests
./gradlew :app:lintRelease                 # Release lint
```

The app consumes four local AARs from `libs/`: core SDK, LlamaCPP, ONNX, and QHexRT. After native or Kotlin SDK changes, rebuild/stage those artifacts before trusting an app build.

## Script reference

| Script | Purpose and normal use |
|---|---|
| `smoke.sh` | Grep-based SDK API coverage check. Set `RUN_BUILD_GATES=1` to call `verify.sh` too. |
| `verify.sh` | Debug APK build gate with strict Gradle dependency verification. The four ignored `libs/*.aar` files must already be staged. `REFRESH_NATIVE=1` only refreshes SDK native inputs; restage the AARs afterward before trusting the app build. |
| `stage-sdk-aars.sh` | `stage-sdk-aars.sh [debug\|release]` builds the four Kotlin SDK AARs from already-staged local native libraries and copies deterministic names into `libs/`. |
| `sync-solutions-yamls.sh` | Regenerates `SolutionsYaml.kt` from canonical Commons YAML. Use `--check` in validation; never edit the generated Kotlin file directly. This checks source synchronization, not end-to-end solution execution. |
| `run_npu_e2e.sh` | On-device QHexRT catalog/ad-hoc harness: preflight, optional build/install, one-model-at-a-time inference, evidence collection, cleanup, and aggregation. Run `--help` for device, architecture, HF, and local-bundle options. |
| `preflight_npu_assets.py` | Called by the NPU harness before ADB/build work. Verifies canonical suite/fixture hashes, architecture, safe paths, and rejects legacy `lama_hold_*` assets. |
| `npu_e2e_report.py` | Called after device runs. Applies canonical gates and provenance, performs local Whisper TTS intelligibility checks (the pinned checkpoint may download on first use), and writes `summary.md` plus `summary.json`. |
| `requirements-npu-e2e.txt` | Pins the Whisper evaluator required for production TTS gates: `python3 -m pip install -r scripts/requirements-npu-e2e.txt`. |
| `test_preflight_npu_assets.py` | Hardware-free unit coverage for NPU asset preflight. |
| `test_npu_e2e_report.py` | Hardware-free unit coverage for report validation, thresholds, and provenance. |
| `build-play-aab.sh` | Release-owner workflow that rebuilds/stages native code and AARs, runs tests/lint, builds and validates the signed Play AAB, checks 16 KB alignment, and creates a private evidence archive. It does not upload anything. |
| `verify-aab-signature-coverage.py` | Helper called by `build-play-aab.sh`; checks that every non-signature AAB payload entry has a SHA-256 section in the signing manifest. The release script separately runs `jarsigner` for cryptographic verification. |
| `audit-release-notices.sh` | Generates the release SBOM and archive-level notice evidence. For a release candidate use `--strict --apk PATH`; this is evidence, not legal approval. |
| `generate-release-notice-inventory.py` | Helper called by the notice audit; locates exact SBOM artifacts by SHA-256 and inventories notice/license paths inside AAR/JAR archives. |

## Workflow map

```text
Development: smoke.sh; after SDK/native changes: root native build -> stage debug AARs -> verify.sh
Solutions:   canonical Commons YAML -> sync-solutions-yamls.sh -> generated Kotlin
NPU device:  run_npu_e2e.sh -> preflight_npu_assets.py -> instrumentation -> npu_e2e_report.py
Play:        build-play-aab.sh -> stage-sdk-aars.sh -> Gradle gates -> signature verifier -> archive
Notices:     audit-release-notices.sh -> SBOM -> notice-inventory helper -> optional APK inspection
```

## Guardrails

- `build-play-aab.sh` is release-only. It expects clean SDK and QHexRT worktrees, pinned NDK/QAIRT inputs, release endpoints, keystore credentials, certificate fingerprint, and an explicit non-SNAPSHOT `SDK_VERSION`. `--allow-dirty` produces development evidence, not a Play-ready archive.
- Keep Play release inputs in environment variables or the script's macOS Keychain service. Prefer `HF_TOKEN` over `--token` for NPU runs so it does not enter shell history. Never commit or echo secrets, enable shell tracing, or paste them into reports.
- `run_npu_e2e.sh --build` installs both app and test APKs. Its local-bundle modes use `adb reverse`/temporary device paths and verify cleanup afterward.
- Synced `npu_suites/`, `qhexrt_fixtures/`, and `reports/` are generated and ignored. Never force-add them or replace canonical fixtures with private/restricted assets.
- After editing scripts, run the relevant Python tests, `bash -n scripts/*.sh`, `bash scripts/sync-solutions-yamls.sh --check`, and `git diff --check`.
