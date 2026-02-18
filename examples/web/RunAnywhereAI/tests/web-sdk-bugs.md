# Web SDK Bug Report

## Run 5: Feb 17, 2026 — Post-Refactoring Validation (WASM moved to backend packages)

**Architecture**: Core = pure TypeScript (0 WASM), LlamaCpp = racommons-llamacpp.wasm (3.7 MB), ONNX = sherpa-onnx.wasm (12 MB)

**Published versions**: `@runanywhere/web@0.1.0-beta.7`, `@runanywhere/web-llamacpp@0.1.0-beta.7`, `@runanywhere/web-onnx@0.1.0-beta.7`

### Test Results — All 48 Tests PASS

| Phase | Tests | Result |
|---|---|---|
| Phase 1: App Load & Init | A1-A5 | PASS |
| Phase 2: Model Registry | B6-B9 | PASS |
| Phase 3: Storage Tab | F24-F28 | PASS |
| Phase 4: Settings Tab | M48-M58 | PASS |
| Phase 5: Chat Tab UI | N59-N71 | PASS |
| Phase 6: Vision Tab | O72-O78 | PASS |
| Phase 7: Voice Tab | P80-P83 | PASS |
| Phase 8: Transcribe Tab | Q88-Q97 | PASS |
| Phase 9: Speak Tab | R98-R105 | PASS |
| Phase 10: Cross-Tab Nav | K44-K45 | PASS — 35 rapid tab switches |
| Phase 11: Acceleration Badge | T110-T112 | PASS — CPU badge visible |
| Phase 12: Persistence | localStorage + OPFS | PASS — survives page refresh |

### Persistence Test Details

| Test | Before Refresh | After Refresh | Result |
|---|---|---|---|
| Temperature | 0.3 | 0.3 | PASS |
| Max Tokens | 1024 | 1024 | PASS |
| API Key | test-key-123 | test-key-123 | PASS |
| Base URL | custom.api.example.com | custom.api.example.com | PASS |
| Analytics toggle | false | false | PASS |
| OPFS models directory | exists | exists | PASS |

### Expected Warnings (not bugs)

| Warning | Classification |
|---|---|
| `racommons-llamacpp-webgpu.js` 404 | EXPECTED — WebGPU variant not built, CPU fallback works |

### Previously Fixed Bugs (from earlier development)

| # | Bug | Fix |
|---|-----|-----|
| 1 | OPFS persistence race condition | Added `await this.storage.initialize()` in `refreshDownloadStatus()` |
| 2 | Sherpa-ONNX JS files lacked ESM exports | Added `export { ... }` statements |
| 3 | Module duplication (Vite singleton issue) | Added `resolve.alias` in `vite.config.ts` |
| 4 | Peer dependency semver prerelease mismatch | Changed to `>=0.1.0-beta.0` |
| 5 | Build script verification paths outdated | Updated to `racommons-llamacpp.wasm` paths |
| 6 | Platform adapter null function signature mismatch | Used full PlatformAdapter class instead of inline minimal version |
| 7 | Storage tab model count included `_metadata.json` | Skip files starting with `_` in `getStorageInfo()` |

## Run 6: Feb 17, 2026 — Sherpa-ONNX Glue Patch Validation

**Fix**: Added `wasm/scripts/patch-sherpa-glue.js` to apply 5 browser-compatibility patches to Emscripten Node.js glue output.

### Test Results — All UI Tests PASS (no ONNX regression)

| Section | Tests | Result |
|---|---|---|
| A. App Load & SDK Init | A1-A5 | PASS — Both LlamaCpp + ONNX backends register |
| K. Cross-Tab Navigation | K1-K2 | PASS — 20 rapid switches, no crash |
| M. Settings Tab | M1-M10 | PASS |
| M11. Settings Persistence | localStorage | PASS — Max Tokens 2548 survives reload |
| N. Chat Tab UI | N1,N5,N7,N12,N13 | PASS |
| O. Vision Tab | O1-O7 | PASS |
| P. Voice Tab | P1-P5 | PASS — STT/TTS model sheets show ONNX models |
| Q. Transcribe Tab | Q1-Q5 | PASS |
| R. Speak Tab | R1-R7 | PASS |
| T. Acceleration Badge | T1-T3 | PASS — CPU badge persists across tabs |
| L/O. Console Audit | Error count | PASS — 1 expected error (WebGPU 404), 0 unexpected |

### ONNX Backend Integration Verified

- `[RunAnywhere:ONNXProvider] ONNX backend registered successfully` in console
- ONNX capabilities: `[stt, tts, vad]`
- Voice tab: STT model "Whisper Tiny English (ONNX)" listed with ONNX badge
- Voice tab: TTS models "Piper TTS US English" + "Piper TTS British English" listed
- No `createModule is not a function` error (BUG-1 from starter app fixed)
- No `require is not defined` error (node:path patched)
- No `NODERAWFS not supported` error (NODERAWFS removed)

---

### Changes Since Run 4

| # | Change | Type |
|---|--------|------|
| 1 | WASM moved from core to backend packages (llamacpp, onnx) | Architecture |
| 2 | Core package is now pure TypeScript (no WASM) | Architecture |
| 3 | New LlamaCppBridge.ts and LlamaCppOffsets.ts in llamacpp package | New files |
| 4 | DOM refactored: tab panels use `.tab-panel#tab-{name}` pattern | UI |
| 5 | ExtensionPoint service registry replaces globalThis coupling | Structural |
| 6 | Streaming model import via file.stream() for large models | Performance |
