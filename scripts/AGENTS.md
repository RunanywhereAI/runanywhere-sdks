# AGENTS.md — scripts/

Cross-cutting automation for the whole monorepo: env setup, native builds, release
packaging, and CI/local validation. For SDK build/test/lint commands, see the root
[`AGENTS.md`](../AGENTS.md) and each `bindings/<name>/AGENTS.md` — **this file only covers
working *in* `scripts/` itself.** The full per-script inventory (including scripts that
live outside this folder, in `core/scripts/`, `bindings/*/scripts/`, etc., and why each one
lives where it does) is [`scripts/README.md`](README.md); don't duplicate its tables here.

## Layout

| dir | contents | full inventory |
|---|---|---|
| `build/` | `build-core-android.sh` (native `.so` build + stage into every SDK's `jniLibs/`) + its guard tests, `validate-qhexrt-prebuilt.py` (+ test) | `README.md` |
| `release/` | version bump, artifact validation, npm/consumer-app publish helpers (see below) | `README.md` |
| `setup/` | `doctor.sh`, `setup.sh`, `setup-toolchain.sh`, `detect-mode.sh`, `sync-skills.sh` | `README.md` |
| `validation/` | CI gates (`gates/`), C++ commons checks (`commons/`), the seven-lane e2e harness (`e2e/`), plus root-level `verify_default_pool.sh` (cross-language default-value parity check) | [`validation/README.md`](validation/README.md) |
| `ci/` | `verify_cpp_desktop_kit.py` — kit tarball contract (proto headers, SCHEMA_LOCK, Windows zlibstatic/bz2). `oss_keyless_telemetry_blast.sh` is retired (CLI lives in RunanywhereAI/RCLI). | — |
| `models/` | empty on this branch — a BigVGAN ONNX exporter and a Parakeet CTC prep script have existed here on other commits/branches; a stale `__pycache__` from one of those checkouts may linger locally and is safe to delete | — |

## Path resolution: every script derives repo root from its own location, never cwd

The standard one-liner, at the top of nearly every script here:

```bash
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"   # scripts/<x>/*.sh
```

Adjust the `../..` count for depth (`scripts/validation/e2e/*.sh` needs `../../..`). This
matters in practice, not just in theory: `build-core-android.sh` explicitly `cd`s to
`$REPO_ROOT` before invoking `cmake --preset`, because Gradle's `buildLocalJniLibs` task
runs it with `workingDir = bindings/kotlin/`, and `CMakePresets.json` only resolves from
the repo root.

`setup/sync-skills.sh` uses a different pattern on purpose: it walks up looking for a
marker (`CMakeLists.txt` + `package.json`) instead of counting `..` hops, so it keeps
working if the script itself is ever moved to a different depth. Prefer the hop-counting
form for a new script at a fixed depth (simpler, and it's what every other script does);
reach for the walk-up form only when the script's own location is expected to move.

## Running the Python checks directly

These are plain `unittest`/argparse scripts, invoked directly with `python3 <path>`, not
through pytest (that's a separate, unrelated test suite under `bindings/python/`) — exactly
like this from `pr-build.yml`:

```bash
python3 scripts/build/test_build_core_android_guards.py
python3 scripts/build/test_validate_qhexrt_prebuilt.py
python3 scripts/validation/gates/test_release_version_coherence.py
```

`validate-qhexrt-prebuilt.py` exits **3** (not 1) when no prebuilt is selected — that's the
intentional public/stub-build path, not a failure. Do not treat every nonzero exit as
failure here: exit 3 is the intentional no-prebuilt path, while exit 1 indicates a partial
or identity-mismatched selection.

## Skills: `.claude/skills/` is canonical, `.agents/skills/` is a generated mirror

Both trees are gitignored (skill content isn't public yet), but non-Claude tooling (e.g.
Codex, which has no native skills mechanism) reads `.agents/skills/` as plain markdown.
Edit only `.claude/skills/`, then run `scripts/setup/sync-skills.sh` to regenerate the
mirror (`--check` verifies it's in sync without writing, for CI/pre-commit use). Never
hand-edit `.agents/skills/` — it's a plain `cp -R`, not a symlink, because a checkout
without `core.symlinks=true` (common on Windows) would materialize a git symlink as a text
file and silently break Codex's reads.

## Release scripts: why they're this paranoid

Each exists because a specific broken artifact or PR once shipped anyway. Keep using them
rather than a manual `npm publish` / manifest edit — read each script's own header comment
before changing its checks, the full story is there:

- **`release/prepublish_check.py --version <v> ARTIFACT...`** — the last gate before a
  registry push (npm `.tgz`, Android `.aar`, pub.dev `.tar.gz`). Exists because
  `@runanywhere/electron-sherpa` 0.20.17 once shipped a same-size, same-symbol-count
  carrier whose vtable slots were all NULL; `@runanywhere/qhexrt` nearly shipped with an
  unresolvable `"workspace:*"` dependency; and `@runanywhere/core` 0.20.18 shipped missing
  a generated header that five other shipped headers `#include`. None of those are visible
  to `npm pack`, artifact size, or `nm -gU` — only to this script.
- **`release/bump-consumer-apps.sh <version> [apps-root]`** — bumps and opens a PR against
  each of the six extracted consumer/starter apps once `<version>` is already *published*.
  Refreshes the manifest **and** the ecosystem's real enforcement layer, because editing
  only the manifest fails differently per ecosystem: npm lockfile drift, Gradle dependency
  locking *and* verification-metadata (two independent layers, order matters — lockfile
  first), a stale `Package.resolved`, and pubspec solving. Best-effort per app: a repo
  without a checkout at `apps-root` (default: sibling `starters/` next to this repo, or
  `$RUNANYWHERE_APPS_ROOT`) is skipped, not fatal.
- **`release/validate-artifact.sh FILE...`** — type-aware sanity check (`.zip`/xcframework
  Info.plist + slice count, `.so` ELF magic + arch, `.aar` classes.jar + `jni/*.so`,
  `.wasm` magic bytes, `.tgz` package.json, `.jar` manifest); called from every
  `package-sdk.sh`.
- **`release/rewrite_npm_package.py`** — rewrites an already-packed `.tgz`'s manifest in
  place (drops `workspace:*` specs, optionally vendors dependency archives) so the archive
  is publishable independent of the machine that built it.

## Env vars this layer reads

| Var | Read by | Effect |
|---|---|---|
| `RAC_BUILD_MODE` | anything that sources `setup/detect-mode.sh` | `local` (tolerant, cached, hints) vs `ci` (strict, fail-fast); auto-detected from `$CI`/`$GITHUB_ACTIONS`, set explicitly to override |
| `RAC_SETUP_CODEGEN_LANGS` | `setup/setup.sh` | pins which `idl/codegen/generate_all.sh --only` languages to require, instead of auto-skipping ones whose toolchain (protoc-gen-swift, java, dart, npm) is missing on this host |
| `RUNANYWHERE_APPS_ROOT` | `release/bump-consumer-apps.sh` | where the six consumer-app checkouts live |
| `STAGING_BASE_URL` / `RA_OSS_BASE_URL` | `ci/oss_keyless_telemetry_blast.sh` | retired with that script (exit 2); OSS keyless blast now lives in RunanywhereAI/RCLI |
| `PYTHON_BIN` | `validation/verify_default_pool.sh` | override the `python3` interpreter |

`validation/`'s own env vars (`VALIDATION_BUILD_ROOT`, `VALIDATION_RUN_DIR`,
`VALIDATION_JOBS`, `VALIDATION_FAIL_FAST`, `VALIDATION_RUN_IDL_DRIFT`,
`VALIDATION_IDL_DRIFT_BASELINE`) are documented in
[`validation/README.md`](validation/README.md), not repeated here.

## Adding a new script

Cross-cutting (multi-SDK or whole-repo) → here, grouped by function (`build/`, `release/`,
`setup/`, `validation/`, `ci/`). Scoped to one SDK's build/release/test flow →
`bindings/<lang>/scripts/`. Depends on `core/`'s CMake → `core/scripts/`. Full rationale
and the complete per-SDK script inventory: [`README.md`](README.md).
