# GAP 11 — Final Gate Report

_Closes [`v2_gap_specs/GAP_11_LEGACY_CLEANUP.md`](../v2_gap_specs/GAP_11_LEGACY_CLEANUP.md) Success Criteria._

| # | Criterion | Status | Evidence |
|---|-----------|--------|----------|
| 1 | `rac_service_*` declarations carry `[[deprecated]]` | **SUPERSEDED** (v3.0.0 C1) | v2 shipped `RAC_DEPRECATED_LEGACY_SVC` markers on the 4 `rac_service_*` entry points. v3.0.0 Phase C1 DELETED those declarations + the macro entirely. There is nothing left to mark deprecated. |
| 2 | One-time runtime warning on first call | **SUPERSEDED** (v3.0.0 C1) | v2 shipped a `rac_legacy_warn_once(...)` helper inside `service_registry.cpp`. v3.0.0 Phase C1 deleted `service_registry.cpp` entirely — first-time-caller warnings are no longer needed because the entry points don't exist. |
| 3 | `engine_plugin_authoring.md` documents migration | OK | New §"Migrating off the legacy service registry (GAP 11 Phase 29)" in [`docs/engine_plugin_authoring.md`](engine_plugin_authoring.md) with the full call-site translation table. |
| 4 | All call sites identified | OK | [`docs/gap11_audit_repoint.md`](gap11_audit_repoint.md) — 88 references across 30 files, broken down by SDK / commons / engines. |
| 5 | `service_registry.cpp` `git rm` + headers gone | **OK** (v3.0.0 C1) | Phase v3-C1 physically deleted `sdk/runanywhere-commons/src/infrastructure/registry/service_registry.cpp` (311 LOC) + the 163-LOC legacy block in `rac/core/rac_core.h` + 118-LOC Swift CRACommons mirror + Dart ffi_types typedef block + 4 exports × 3 export lists. Zero references remain in first-party code. Build verified: cmake --preset macos-release + rac_commons + 3 engine targets link cleanly. |
| 6 | `RAC_PLUGIN_API_VERSION` bumped to `3u` | **OK** (v3.0.0 C3) | Phase v3-C3 bumped `RAC_PLUGIN_API_VERSION` from `2u` to `3u` in `rac/plugin/rac_plugin_entry.h`. Version-history entry documents the `create(...)` op addition to 7 per-primitive ops structs + VAD `initialize` + legacy service-registry removal. Plugins built against v2 are now rejected at register time (the new `create` slot is unreachable otherwise — safe failure mode). Semver 3.0.0 shipped across all 7 package manifests (Package.swift / runanywhere-commons VERSION / runanywhere-swift VERSION / 4 pubspec.yaml / 4 package.json / Kotlin build.gradle.kts fallback). |
| 7 | Post-mortem covering all gaps shipped | OK | [`docs/v2_migration_complete.md`](v2_migration_complete.md) (this commit). |

## History (v2 → v3 progression)

This gap shipped in two waves:

**v2 (original gate)** — deprecation pressure only. Added
`[[deprecated]]` markers on the 4 `rac_service_*` entry points, a
one-time runtime warning helper, a migration doc, and a call-site
audit. No `git rm`; no API-version bump. Rationale at the time: "the
`git rm` would break 30 files that still call `rac_service_*`; each
needs per-platform behavioral verification; a struct-layout-incompatible
change is a major-version event."

**v3.0.0 (this release)** — delete + bump. 15 commits
`c721a9c6` → `b55d41ff` executed the full deletion:

1. **Phase B0** — added `create(model_id, config_json, out_impl)` op to
   all 7 per-primitive ops structs + `initialize(impl, model_path)` on
   VAD (ABI extension prerequisite).
2. **Phase B1-B7** — migrated 6 engines (llamacpp, llamacpp_vlm, onnx,
   whispercpp, whisperkit_coreml, metalrt) + 2 commons-side registers
   (onnx_embeddings, platform) off `rac_service_register_provider`.
3. **Phase B8** — rerouted 7 commons consumers
   (`rac_{llm,stt,tts,vlm,embeddings,diffusion}_create` + `vad_component`)
   off `rac_service_create` to `rac_plugin_route + vt->ops->create`.
4. **Phase B9-B10** — migrated 6 JNI sites + Swift `CppBridge+Services`
   off `rac_service_list_providers`.
5. **Phase C1** — `git rm service_registry.cpp` (311 LOC) + `rac_core.h`
   legacy block (163 LOC) + Swift CRACommons mirror (118 LOC) + Dart
   `ffi_types.dart` typedefs + 12 export entries across 3 lists.
6. **Phase C3** — `RAC_PLUGIN_API_VERSION` 2u → 3u + semver 3.0.0 across
   all 7 SDK packages.

See `docs/v3_phaseB_complete.md` for the per-commit audit trail.

## Nothing remains in this gap

Every criterion is OK. The deferred-deprecation-delete (VoiceSessionEvent
etc.) scope tracked in `docs/v3_phaseC2_scope.md` is **outside** GAP 11
— those are SDK-level deprecated APIs, not the `rac_service_*` legacy
registry surface that GAP 11 covered.
- Physical deletion of the Wave D deprecation-marked orchestration
  bodies (per `docs/gap08_final_gate_report.md` "Files marked for
  deletion" table)
