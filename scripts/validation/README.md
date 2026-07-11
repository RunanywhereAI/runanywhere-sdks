# Validation Scripts

This folder is the command hub for source and pre-runtime validation, organized
into three subfolders by concern:

- **`gates/`** — CI rule-gates wired into `.github/workflows/pr-build.yml` (TS /
  Flutter / Gradle centralization + the deprecated-surface regression guard).
- **`commons/`** — C++ commons checks: RAC_API export drift, PII-logging guard,
  the commons proto/core CMake test runner, and the export-list sync tool.
- **`e2e/`** — the seven-lane runtime-validation harness (invoked by the local
  e2e skills, not CI).

`_validation_lib.sh` (shared logging/step helpers) stays at this folder's root
and is sourced by the `e2e/` and `commons/` run-scripts via `../_validation_lib.sh`.
Use these entry points instead of ad hoc `build-cpp*` / `build-link*` /
`build-proto*` folders. See `docs/BUILD_ORGANIZATION.md` for the build-folder
inventory and cleanup policy.

| Script | Purpose | Default build output |
| --- | --- | --- |
| `gates/check_typescript_centralization.sh` | syncpack: TS/RN/Web `package.json` pins vs `dependencies/versions.json`. | N/A |
| `gates/check_release_version_coherence.sh` | Release-train manifests, native download pins, public fallbacks, and workspace lockfiles vs `sdk/runanywhere-commons/VERSION`. | N/A |
| `gates/check_wasm_provenance_contract.sh` | Component-specific ORT/Sherpa WASM recipe-schema wiring. | N/A |
| `gates/check_flutter_centralization.sh` | Flutter `pubspec.yaml` pins vs the central registry. | N/A |
| `gates/check_gradle_centralization.sh` | Fails on hardcoded Maven coords outside `gradle/libs.versions.toml`. | N/A |
| `gates/check_deprecated_surfaces.sh` | Regression guard against hand-written DTOs / string enums (allowlist beside it). | N/A |
| `commons/check_rac_api_exports.sh` | RAC_API decls vs `sdk/runanywhere-commons/exports/*.exports` (pairs with `sync_rac_api_exports.sh`). | N/A |
| `commons/check_no_pii_logging.sh` | Blocks signed-URL / per-user paths in commons INFO logs. | N/A |
| `commons/run_commons_proto_checks.sh` | Configures, builds, and runs the commons proto/core CMake tests. | `build/validation/commons-proto/` |
| `e2e/run_global_source_checks.sh` | Repo source checks: short status, whitespace diff, and IDL drift. | `build/validation/` |
| `e2e/run_seven_lane_validation.sh` | Creates the seven-lane evidence folder, optional preflight, and v2 self-check. | `build/validation/` |
| `e2e/validate_seven_lane_evidence.py` | Validates seven-lane v2 evidence schema, headers, action phases, and lane-relative paths. | N/A |

Useful environment variables:

| Variable | Purpose |
| --- | --- |
| `VALIDATION_BUILD_ROOT` | Override the build root. Defaults to `build/validation`. |
| `VALIDATION_RUN_DIR` | Override the log/evidence output folder. |
| `VALIDATION_JOBS` | Override the CMake build parallelism. |
| `VALIDATION_FAIL_FAST=1` | Stop after the first failing command. |
| `VALIDATION_RUN_IDL_DRIFT=0` | Skip IDL drift in `run_global_source_checks.sh`. |
| `VALIDATION_IDL_DRIFT_BASELINE` | Select IDL drift baseline: `auto` (default), `current-worktree`, or `committed`. `auto` uses `committed` in CI and `current-worktree` locally. |

The global source check uses a validation wrapper for IDL drift. In local
test-workflow runs, the wrapper seeds a temporary isolated Git index from the
current worktree before running codegen, then fails only if codegen changes
files relative to that dirty baseline. CI stays strict by using the committed
Git index.

**GLOBAL-04 status**: The dirty-worktree IDL drift gate is satisfied by
`run_idl_drift_check.sh`. In `current-worktree` mode (the local default) it
creates an isolated `GIT_INDEX_FILE` in a temp directory, snapshots all tracked
and untracked files, runs `generate_all.sh`, then diffs the worktree against
that baseline. Temp files are cleaned up via `trap cleanup EXIT` even on
failure. The real Git index is never modified. Tested on a branch with 1194
staged files and confirmed correct behavior.

Examples:

```bash
scripts/validation/e2e/run_global_source_checks.sh
scripts/validation/commons/run_commons_proto_checks.sh
scripts/validation/e2e/run_seven_lane_validation.sh --with-preflight
scripts/validation/e2e/run_seven_lane_validation.sh --dry-run
scripts/validation/e2e/run_seven_lane_validation.sh --check-only test_workflows/logs/<run-dir>
```
