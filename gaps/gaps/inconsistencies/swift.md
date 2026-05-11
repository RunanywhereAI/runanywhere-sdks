# Swift / iOS SDK — Open Inconsistencies

Updated: 2026-05-11 (post-Wave-7)
Branch: `feat/v2-architecture`
Latest commit: `b4f99ee19`

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
| Voice Agent (end-to-end pipeline) | UNVERIFIED — `SWIFT-VOICE-AGENT-001` commons fix landed in `4dc98989a`; XCFrameworks rebuilt in `b4f99ee19`; physical-device E2E pending |
| Solutions | UNTESTED — `SWIFT-SOLUTIONS-UNTESTED` |

## Deferred backend Swift bindings (not bugs)

Intentionally present but out of scope:

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

- **Status**: Commons fix committed in `4dc98989a` (T16 / Wave 6E / Path X). XCFrameworks rebuilt in Wave 7B to package the fix. `voice_agent.cpp` proto path consults the global lifecycle via `acquire_lifecycle_{stt,llm,tts,vad}` instead of dereferencing the per-component handles. Mirrors the Phase 6j `rac_vlm_process_proto` precedent.
- **What's left**: Run iPhone 17 Pro Max E2E — confirm VoiceAgent init reports `VAD/STT/TTS: true` after standalone `RunAnywhere.loadModel(...)` calls. Update modality table row to PASS once confirmed.
- **Cross-SDK**: Fix is transparent to Kotlin/Flutter/RN/Web — they consume the same public C ABI. No SDK-side changes needed.

## LOW

### SWIFT-SOLUTIONS-UNTESTED — Solutions facade not yet tested on device

- **Scope**: validation pass.
- **What**: The Solutions YAML runner path (`RunAnywhere.solutions.run(yaml:)`) is real at `Public/Extensions/Solutions/RunAnywhere+Solutions.swift:108-188`, but has not been exercised on physical device.
- **Action**: Include a Solutions smoke test in the next validation pass.

---

# Part 2 — Duplication / dead code (residual)

## LOW

### SWIFT-DEAD-EXECUTION-TARGET-WIRESTRING — Retained: in-file caller

- **Scope**: XS.
- **What**: `RAExecutionTarget.wireString` at `Foundation/Bridge/Extensions/RALLMTypes+CppBridge.swift:114-123` was NOT deleted in T7 because there's a same-file caller at line 83 (`request.executionTarget = executionTarget.wireString`). Not actually dead.
- **Action**: None — entry exists for traceability only. Recategorize once the LLM proto request path stops embedding the string form.

---

## Summary

Wave 6 + Wave 7 (commits `200db1548` → `b4f99ee19`, 11 wave commits) closed 22 items from the previous open list:

- **Wave 6A-F** (commits `200db1548` → `cda52ddbd`): 17 items.
- **Wave 7A-B** (commits `7ba69b1a8`, `b4f99ee19` + XCFramework rebuild): 5 more items —
  - SWIFT-DUP-MODELTYPES-ARCHIVESTRUCTURE (commons + Swift)
  - SWIFT-DEAD-VLM-LOAD-MODEL (commons-side already shipping; Swift adopted)
  - SWIFT-CRACOMMONS-RUNTIME-UNLOAD-EXPORT
  - All XCFrameworks rebuilt; iOS example app builds clean.

Hand-written Swift: 96 files / 17,890 LOC → **~94 files / ~16,927 LOC** (-2 files, ~-963 LOC).

For Wave 6 / Wave 7 details see commit history:

```
b4f99ee19 Wave 7B — Swift adoption of ArchiveStructure + VLM lifecycle cancel (-158 net)
7ba69b1a8 Wave 7A — ArchiveStructure mapper + rac_runtime_unload export
b692aedc9 Wave 6 wrap-up — docs
cda52ddbd Wave 6F — post-T16 cleanup (-100 net)
4dc98989a T16 / SWIFT-VOICE-AGENT-001 — voice agent reads global lifecycle
ce2485b0b T15b — adopt commons enum mappers (-51 net)
8053a831e T15a — commons enum mappers (5 pairs)
dd26d3e16 Wave 6C — Sendable + isLoaded SoT + storage UI cleanup
fe0fb8f88 Wave 6B — tooling sync + codegen regen
200db1548 Wave 6A — dead-code deletes (~-666 LOC)
```

Per repo convention: **DELETE, don't deprecate**. No compat shims, no `@available` gates, no `#if false`. Per `CLAUDE.md`: business logic lives in C++; proto types from `idl/*.proto` are canonical; Swift should be a thin bridge.
