# Build Organization

Audit date: 2026-05-03.

This repo should use one validation command hub and one predictable local build
root. Future agents should not create new root-level `build-cpp*`,
`build-link*`, or `build-proto*` folders.

## Command Hub

Use:

```text
scripts/validation/
```

Recommended pre-runtime commands:

```bash
scripts/validation/run_global_source_checks.sh
scripts/validation/run_commons_proto_checks.sh
scripts/validation/run_seven_lane_validation.sh
```

`run_seven_lane_validation.sh` scaffolds the seven target evidence lanes. Add
`--with-preflight` to run the global source and commons proto checks before
manual/MCP runtime validation.

## Standard Output Locations

Generated validation builds:

```text
build/validation/<check-name>/
```

Commons proto/core CMake validation:

```text
build/validation/commons-proto/
```

Runtime logs, screenshots, videos, and reports:

```text
test_workflows/logs/<timestamp>-<run-name>/
```

`build/` and `build-*/` are ignored generated outputs. Source-controlled scripts
and durable docs live outside ignored evidence folders.

## Inventory

None of the inspected build folders are tracked by git.

| Location | Status | What it is |
| --- | --- | --- |
| `.build/` | ignored, about 6.5G | SwiftPM/local tool output. Generated. |
| `build/` | ignored, about 15G | Mixed local platform builds and the standard validation build root. Generated. |
| `build-cpp02-commons/`, `build-cpp02c-registry-verify/`, `build-cpp04-download/`, `build-cpp05-extraction/`, `build-cpp06-storage/`, `build-cpp07-events/`, `build-cpp09a-llm/`, `build-cpp09a-llm-nopb/`, `build-cpp10a-speech/`, `build-link01-proto/`, `build-link01-proto-rag/`, `build-proto-verify/` | untracked CMake scratch folders; now ignored by `build-*/` | Worker-created CMake build dirs. Each `CMakeCache.txt` points at `sdk/runanywhere-commons`. Most are backends-off test builds; `build-link01-proto-rag/` was configured with backends on. |
| `sdk/runanywhere-commons/build/` | ignored by commons `.gitignore`, about 220M | Local commons CMake build. Generated. |
| `sdk/runanywhere-commons/build-advanced-modality/`, `build-cpp01/`, `build-jni-verify/`, `build-proto-verify/` | ignored by commons `.gitignore`, about 293M-478M each | Worker-created commons CMake build dirs. Generated. |
| `test_workflows/logs/` | ignored, about 21G | Local command logs, screenshots, videos, and copied build evidence. Some old runs contain DerivedData or CMake dependency artifacts. |

Root and commons top-level `.log` files were not found during this audit; logs
were under `test_workflows/logs/`.

## Generated Vs Source-Controlled

Generated and safe to recreate:

- `build/`, `build-*/`, `.build/`
- `sdk/runanywhere-commons/build/`, `sdk/runanywhere-commons/build-*/`
- `test_workflows/logs/<run>/`
- CMake `_deps/`, `CMakeFiles/`, `Testing/`, binaries, and compiler databases
  inside those build folders

Source-controlled build organization assets:

- `scripts/validation/`
- `scripts/README.md`
- `docs/BUILD_ORGANIZATION.md`

`test_workflows/` is local evidence space in this checkout because it is ignored
by the root `.gitignore`; tracked durable guidance should be mirrored in
`docs/BUILD_ORGANIZATION.md` or `scripts/validation/README.md`.

## Cleanup Policy

Do not delete build folders during an audit unless the owner explicitly asks for
cleanup and the target is clearly generated. Prefer documenting the cleanup
command first.

Review disk use before removal:

```bash
du -sh .build build build-* sdk/runanywhere-commons/build sdk/runanywhere-commons/build-* test_workflows/logs/* 2>/dev/null
```

When cleanup is approved, these generated folders are the intended old worker
targets:

```bash
rm -rf build-cpp* build-link* build-proto-verify
rm -rf sdk/runanywhere-commons/build-advanced-modality sdk/runanywhere-commons/build-cpp01 sdk/runanywhere-commons/build-jni-verify sdk/runanywhere-commons/build-proto-verify
```

Use a retention window for old evidence logs after reviewing whether any run is
still needed:

```bash
find test_workflows/logs -mindepth 1 -maxdepth 1 -mtime +14 -exec rm -rf {} +
```

Avoid deleting `build/` wholesale if another local platform build is in use. For
validation-only cleanup, remove `build/validation/`.
