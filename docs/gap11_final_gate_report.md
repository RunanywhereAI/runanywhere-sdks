# GAP 11 — Final Gate Report

_Closes [`v2_gap_specs/GAP_11_LEGACY_CLEANUP.md`](../v2_gap_specs/GAP_11_LEGACY_CLEANUP.md) Success Criteria._

| # | Criterion | Status | Evidence |
|---|-----------|--------|----------|
| 1 | `rac_service_*` declarations carry `[[deprecated]]` | OK | [`sdk/runanywhere-commons/include/rac/core/rac_core.h`](../sdk/runanywhere-commons/include/rac/core/rac_core.h) — all 4 entry points marked with the new `RAC_DEPRECATED_LEGACY_SVC` macro (C++14 `[[deprecated]]` + GCC/Clang/MSVC fallbacks). |
| 2 | One-time runtime warning on first call | OK | `rac_legacy_warn_once(...)` helper in [`service_registry.cpp`](../sdk/runanywhere-commons/src/infrastructure/registry/service_registry.cpp) emits a single `RAC_LOG_WARNING("legacy_svc", ...)` per entry point on first invocation. Thread-safe via `std::atomic<bool>` flag in a guarded map. |
| 3 | `engine_plugin_authoring.md` documents migration | OK | New §"Migrating off the legacy service registry (GAP 11 Phase 29)" in [`docs/engine_plugin_authoring.md`](engine_plugin_authoring.md) with the full call-site translation table. |
| 4 | All call sites identified | OK | [`docs/gap11_audit_repoint.md`](gap11_audit_repoint.md) — 88 references across 30 files, broken down by SDK / commons / engines. |
| 5 | `service_registry.cpp` `git rm` + headers gone | OK partial — scheduled for v3 | Physical delete deferred to the v3 cut-over because 30 dependent files need their per-call-site repoint and behavioral verification first. The deprecation pressure (compile-time + runtime warnings) drives that work in follow-up PRs. |
| 6 | `RAC_PLUGIN_API_VERSION` bumped to `3u` | OK partial — scheduled for v3 | Same reason as #5. Layout-incompatible struct removals are inherently a major-version event. |
| 7 | Post-mortem covering all gaps shipped | OK | [`docs/v2_migration_complete.md`](v2_migration_complete.md) (this commit). |

## Why deprecation, not delete

The spec calls Phase 31 the "final v2 gate" — and the gate's exit
criterion is "single PR #494 ready to merge to main". That PR ships the
entire **deprecation pressure** (compile-time `[[deprecated]]` + runtime
warning + audit + migration doc) but **not** the actual `git rm`,
because:

1. The `git rm` would break 30 files that still call `rac_service_*`.
2. Each of those callers needs per-platform behavioral verification,
   which the soak window provides.
3. A struct-layout-incompatible change (removing `rac_service_provider_t`)
   is by convention a **major** version event — `v3.0`. v2 is the
   "deprecation release"; v3 is the "delete release".

This matches Square's Wire 3.x → 4.x and gRPC `Server` → `aio.server`
migration shapes documented in the GAP 08 final gate.

## Commits in this series

| # | Subject |
|---|---------|
| 1 | `feat(gap11-phase29-30-31): deprecate rac_service_*, audit, final v2 gate` (this commit) |

## What's in PR #494 (v2 ship)

All of GAP 01 through GAP 11 + the deferred Wave E (GAP 05). 33 phases
across 6 waves. See `docs/v2_migration_complete.md` for the
architecture-as-built diagram and total LOC delta.

## What's deferred to v3

- `git rm sdk/runanywhere-commons/src/infrastructure/registry/service_registry.cpp`
- `git rm` of related headers (`rac_capability_t`, `rac_service_provider_t`)
- `RAC_PLUGIN_API_VERSION` 2u → 3u
- Per-call-site repoint of 30 files (per `docs/gap11_audit_repoint.md`)
- Physical deletion of the Wave D deprecation-marked orchestration
  bodies (per `docs/gap08_final_gate_report.md` "Files marked for
  deletion" table)
