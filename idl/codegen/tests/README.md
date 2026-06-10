# idl/codegen/tests — convenience-generator smoke tests

Smoke coverage for the four convenience generators:

- `generate_swift_convenience.py`
- `generate_kotlin_convenience.py`
- `generate_dart_convenience.py`
- `generate_ts_convenience.py`

Filed against pass2-syn-056: the production IDL only exercises `rac_required`
against one string field and `rac_min`/`rac_max` against int32 sample-rate
fields, leaving the int64, float, double, bool, and enum-default code paths
in the per-language emitters dormant. The fixture proto in this directory
deliberately covers every rac_* annotation across every relevant scalar type
so the generator output exercises the full matrix.

## Layout

- `fixtures/test_options.proto` — single-file fixture applying every rac_*
  annotation to every supported scalar type (STRING / INT32 / INT64 / FLOAT
  / DOUBLE / BOOL / ENUM / MESSAGE) plus `rac_display_name`,
  `rac_analytics_key`, and `rac_wire_string` on enum values.
- `test_convenience_generators.py` — runner that sandboxes a minimal repo
  with the fixture + the canonical `rac_options.proto`, invokes each
  generator as a subprocess, and diffs the output against
  `golden/{swift,kotlin,dart,ts}.expected`.
- `golden/` — committed per-language expected outputs. Bootstrap with
  `--update-golden`; CI runs without that flag and asserts byte-identical
  match.

## Running locally

Prerequisites: `protoc` on PATH, Python protobuf runtime (`pip install
protobuf`). These are already installed for any environment that can run
the existing `idl-drift-check` workflow.

```bash
# Bootstrap goldens (after fixture or generator changes).
python3 idl/codegen/tests/test_convenience_generators.py --update-golden

# Verify (CI / pre-commit).
python3 idl/codegen/tests/test_convenience_generators.py
```

Exit codes:

| Code | Meaning                                                |
| ---- | ------------------------------------------------------ |
| 0    | All generators produced output that matches the golden |
| 1    | One or more generators diverged from its golden        |
| 2    | Toolchain (protoc / python protobuf) missing           |

## CI integration

Wired into `.github/workflows/idl-drift-check.yml` as the **Convenience
generator smoke test** step, which runs before the drift check on the same
runner (protoc + Python protobuf are already installed there). It runs without
`--update-golden`, so a generator that produces stably-wrong output — or a
golden that has rotted out of sync with the generators — fails the job. This
complements the drift check, which only catches forgotten regeneration, not
stably-wrong generator output (see the pass2-syn-056 record for the
dormant-bug surface).

## Manual verification (no Python harness)

If the Python runner is unavailable, the equivalent manual procedure is:

1. Copy `fixtures/test_options.proto` into `idl/` (alongside the real
   protos) under a unique name (e.g. `_test_options.proto`).
2. Run each `generate_*_convenience.py` script.
3. Inspect the appended output blocks in each generator's SDK destination
   file. Expected per language:
   - **Swift**: `RAConvenience.swift` contains
     `public extension RARacTestMode { var displayName: String { ... } }`
     and a `static func defaults()` / `func validate()` on
     `RARacTestConfig` whose validate body checks all 6 annotated fields.
   - **Kotlin**: `RAConvenience.kt` contains
     `val RacTestMode.displayName: String get() = ...`,
     `fun RacTestConfig.Companion.defaults(): RacTestConfig = ...`, and a
     `fun RacTestConfig.validate()` that throws
     `SDKException.validationFailed(...)` on each violation.
   - **Dart**: `ra_convenience.dart` contains
     `extension RacTestModeConvenience on RacTestMode { ... }` and a
     defaults+validate pair on `RacTestConfig`.
   - **TypeScript**: `test_options_convenience.ts` contains
     `racTestModeDisplayName(...)`, `racTestConfigDefaults(): RacTestConfig`,
     and `racTestConfigValidate(value: RacTestConfig): void`.
4. Revert: delete the copied proto and rerun `idl/codegen/generate_all.sh`
   to restore the canonical outputs.

The Python harness automates this loop and adds golden-file regression
detection; the manual procedure is documented here as a fallback when the
harness is unavailable.
