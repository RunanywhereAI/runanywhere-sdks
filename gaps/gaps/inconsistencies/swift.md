# Swift / iOS SDK — Open Inconsistencies

Updated: 2026-05-11 (post-Wave-6)
Branch: `feat/v2-architecture`
Latest commit: `cda52ddbd`

This document lists ONLY what is still open. Closed items have been removed — see git log for history.

---

## Current modality state (physical iPhone 17 Pro Max)

| Modality | Status |
|---|---|
| LLM Chat | PASS |
| VLM (LFM2-VL 450M) | PASS |
| STT (Sherpa Whisper Tiny, single-shot) | PASS |
| TTS (Platform + Sherpa Piper) | PASS |
| Tool Calling | PASS |
| RAG ingest + query | PASS |
| Document storage + retrieval | PASS |
| Archive extraction → canonical path | PASS |
| Model persistence across relaunch | PASS |
| Settings / Hardware / Permissions | PASS |
| VAD | PASS |
| Voice Agent (end-to-end pipeline) | UNVERIFIED — `SWIFT-VOICE-AGENT-001` commons fix landed in `4dc98989a`; physical-device E2E pending |
| Solutions | UNTESTED — `SWIFT-SOLUTIONS-UNTESTED` |

## Deferred backend Swift bindings (not bugs)

Intentionally present but out of scope. Exclude/stub OK:

- `Sources/WhisperKitRuntime/`, `Sources/MetalRTRuntime/`
- `Sources/RunAnywhere/Foundation/Bridge/Extensions/CppBridge+Diffusion.swift` + `Public/Extensions/Diffusion/` + `Features/Diffusion/`
- `CRACommons/include/rac_stt_whisperkit_coreml.h`
- `Package.swift`: `MetalRTBackend`, `MetalRTRuntime`, `RABackendMetalRTBinary`, `WhisperKitRuntime`, `RunAnywhereMetalRT`, `RunAnywhereWhisperKit`
- `examples/ios/RunAnywhereAI/.../Features/Diffusion/`

No Genie or WhisperCPP Swift bindings exist.

---

# Part 1 — Runtime correctness

## HIGH

### SWIFT-VOICE-AGENT-001 — Physical-device E2E verification pending

- **Status**: Commons fix landed in `4dc98989a` (T16 / Wave 6E / Path X). `voice_agent.cpp` proto path now consults the global lifecycle via `acquire_lifecycle_{stt,llm,tts,vad}` instead of dereferencing the per-component handles. Mirrors the Phase 6j `rac_vlm_process_proto` precedent.
- **What's left**: Physical-device E2E on iPhone 17 Pro Max — verify VoiceAgent init now reports `VAD/STT/TTS: true` after standalone `RunAnywhere.loadModel(...)` calls. Update modality table row to PASS once confirmed.
- **Cross-SDK**: Fix is transparent to Kotlin/Flutter/RN/Web; they all consume the same public C ABI. No SDK-side changes needed.

## LOW

### SWIFT-SOLUTIONS-UNTESTED — Solutions facade not yet tested on device

- **Scope**: validation pass.
- **What**: The Solutions YAML runner path (`RunAnywhere.solutions.run(yaml:)`) is real at `Public/Extensions/Solutions/RunAnywhere+Solutions.swift:108-188`, but has not been exercised on physical device.
- **Action**: Include a Solutions smoke test in the next validation pass.

---

# Part 2 — Duplication / dead code (residual)

## LOW

### SWIFT-DUP-MODELTYPES-ARCHIVESTRUCTURE — Remaining hand-written switch

- **Scope**: XS.
- **What**: `Foundation/Bridge/Extensions/CppBridge+Strategy.swift` still contains hand-written `ArchiveStructure.toC()` / `init(from cStructure:)` switches. T15a deliberately scoped the 5 most-trafficked enum mappers in commons (InferenceFramework, ModelCategory, ModelFormat, ModelSource, ArchiveType) and excluded ArchiveStructure.
- **Action**: Add `rac_archive_structure_from_proto` / `_to_proto` mapper pair in commons (sibling to the existing 5 pairs in `model_types_mappers.cpp`) + parity tests, then adopt in Swift. Estimate ~15 LOC commons + ~10 LOC Swift deletion.

### SWIFT-DEAD-VLM-LOAD-MODEL — VLM lifecycle adapter retained for cancel() path

- **Scope**: S.
- **What**: `CppBridge+VLM.swift` still has `loadModel(from result:)` and `RunAnywhere+ModelLifecycle.swift` still calls `synchronizeVLMComponentLoad`. T17 kept these because `RunAnywhere.cancelVLMGeneration()` → `CppBridge.VLM.shared.cancel()` consults the actor-owned level-3 handle (vlm_component.cpp:746-764 derefs `component->lifecycle`).
- **Action**: Add a lifecycle-route cancellation ABI in commons (`rac_vlm_cancel_lifecycle_proto` mirroring the existing `rac_*_lifecycle_proto` pattern). Once commons exposes a cancel that consults the global lifecycle, the Swift VLM `loadModel(from:)` and `synchronizeVLMComponentLoad` can be deleted. Estimate ~30 LOC commons + ~30 LOC Swift deletion.

### SWIFT-DEAD-EXECUTION-TARGET-WIRESTRING — Retained: in-file caller

- **Scope**: XS.
- **What**: `RAExecutionTarget.wireString` at `Foundation/Bridge/Extensions/RALLMTypes+CppBridge.swift:114-123` was NOT deleted in T7 because there's a same-file caller at line 83 (`request.executionTarget = executionTarget.wireString`). Not actually dead.
- **Action**: None — entry exists for traceability only. Recategorize this item's tracker once the LLM proto request path stops embedding the string form.

### SWIFT-CRACOMMONS-RUNTIME-UNLOAD-EXPORT — Symbol still not in RACommons.exports

- **Scope**: XS.
- **What**: T10 added `rac_runtime_unload` to the Swift mirror header `CRACommons/include/rac_runtime_registry.h` with a `/* Note: not currently exported via dlsym; add to RACommons.exports if Swift consumes this. */` comment. Swift does not call this symbol today. If a future caller needs it, add to `sdk/runanywhere-commons/exports/RACommons.exports`.

---

## Summary

Wave 6 (commits `200db1548` → `cda52ddbd`) closed 17 items from the previous open list. Hand-written Swift dropped from 96 files / 17,890 LOC → **95 files / 17,085 LOC** (-1 file, -805 LOC).

For Wave 6 details, see commit history:

- `200db1548` Wave 6A — 8 dead-code deletes (~-666 LOC)
- `fe0fb8f88` Wave 6B — SwiftLint + mirror sync + codegen regen
- `dd26d3e16` Wave 6C — Sendable wrap + isLoaded consolidation + Storage UI cleanup
- `8053a831e` + `ce2485b0b` Wave 6D — commons enum mappers + Swift adoption
- `4dc98989a` Wave 6E — SWIFT-VOICE-AGENT-001 commons fix
- `cda52ddbd` Wave 6F — post-T16 cleanup

Per repo convention: **DELETE, don't deprecate**. No compat shims, no `@available` gates, no `#if false`. Per `CLAUDE.md`: business logic lives in C++; proto types from `idl/*.proto` are canonical; Swift should be a thin bridge.
