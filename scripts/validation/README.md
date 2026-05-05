# Validation Scripts

This folder is the command hub for source and pre-runtime validation.

Use these entry points instead of creating ad hoc `build-cpp*`,
`build-link*`, or `build-proto*` folders at the repo root.

See `docs/BUILD_ORGANIZATION.md` for the build-folder inventory, generated
artifact policy, and cleanup recommendations.

| Script | Purpose | Default build output |
| --- | --- | --- |
| `run_global_source_checks.sh` | Runs repo source checks: short status, whitespace diff check, and IDL drift check. | `build/validation/` |
| `run_commons_proto_checks.sh` | Configures, builds, and runs the commons proto/core CMake tests. | `build/validation/commons-proto/` |
| `run_seven_lane_validation.sh` | Creates the seven-lane runtime evidence folder, optional preflight, and optional v2 evidence self-check. | `build/validation/` |
| `validate_seven_lane_evidence.py` | Validates seven-lane v2 evidence files, required headers, action phases, and lane-relative screenshot/log paths. | N/A |

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
scripts/validation/run_global_source_checks.sh
scripts/validation/run_commons_proto_checks.sh
scripts/validation/run_seven_lane_validation.sh --with-preflight
scripts/validation/run_seven_lane_validation.sh --dry-run
scripts/validation/run_seven_lane_validation.sh --check-only test_workflows/logs/<run-dir>
```
