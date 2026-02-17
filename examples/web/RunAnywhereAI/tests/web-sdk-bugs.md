# Web SDK Bug Report

## Test Run: Feb 17, 2026 — PR #370 Comment Fixes + Structural Improvements

**Architecture**: Core = pure TypeScript (0 WASM), LlamaCpp = racommons-llamacpp.wasm (3.6 MB), ONNX = sherpa-onnx.wasm (12 MB)

### Test Results

| Phase | Tests | Result |
|---|---|---|
| Phase 1: App Load & Init | A1-A5 | PASS |
| Phase 2: Model Registry | B1-B4 | PASS (via Get Started overlay) |
| Phase 3: Storage Tab | F1-F5 | PASS |
| Phase 4: Settings Tab | M1-M11 | PASS |
| Phase 5: Chat Tab UI | N1-N13 | PASS |
| Phase 6: Vision Tab | O1-O8 | PASS |
| Phase 7: Voice Tab | P1-P8 | PASS |
| Phase 8: Transcribe Tab | Q1-Q10 | PASS |
| Phase 9: Speak Tab | R1-R8 | PASS |
| Phase 10: Cross-Tab Nav | K1-K2 | PASS — all 7 tabs, 3 rapid cycles |
| Phase 11: Acceleration Badge | T1-T3 | PASS — CPU badge visible |
| Phase 12: Console Audit | L1-L2 | PASS — 0 unexpected errors |

### Changes Made in This Run

| # | Change | Type | Files |
|---|--------|------|-------|
| 1 | Replaced globalThis coupling with typed ExtensionPoint service registry | Structural | ExtensionPoint.ts, VoicePipeline.ts, LlamaCppProvider.ts, ONNXProvider.ts, index.ts |
| 2 | Streaming model import via file.stream() for large models | Performance | ModelManager.ts, ModelDownloader.ts, OPFSStorage.ts, LocalFileStorage.ts |
| 3 | Per-key write lock for LocalFileStorage.saveModel() | Concurrency | LocalFileStorage.ts |
| 4 | Focus/visibilitychange fallback for hidden input DOM cleanup | Robustness | RunAnywhere.ts |
| 5 | ModelLoadContext.data JSDoc documenting WASM buffering limitation | Documentation | ModelLoaderTypes.ts |

### Expected Warnings (not bugs)

| Warning | Classification |
|---|---|
| `racommons-llamacpp-webgpu.js` 404 | EXPECTED — WebGPU variant not built, CPU fallback works |
| `n_ctx_seq (8192) < n_ctx_train (128000)` | EXPECTED — Context window limited for browser memory |

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
