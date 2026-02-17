# Web SDK Bug Report

## Test Run: Feb 17, 2026 — Independent Backend WASM Architecture

**Architecture**: Core = pure TypeScript (0 WASM), LlamaCpp = racommons-llamacpp.wasm (3.6 MB), ONNX = sherpa-onnx.wasm (12 MB)

### Test Results

| Phase | Tests | Result |
|---|---|---|
| Phase 1: App Load & Init | A1-A5 | PASS |
| Phase 2: Model Download + OPFS | C1-C6 | PASS |
| Phase 3: Model Load + TextGen | D1-D5 | PASS — "Hello" at 2.4 tok/s |
| Phase 4: Model Unload | E1-E3 | PASS |
| Phase 5: Storage Tab | F1-F5 | PASS (bug fixed) |
| Phase 6: Delete + Re-download | I1-I6 | PASS |
| Phase 7: Tab Navigation | K1-K2 | PASS — all 7 tabs |
| Phase 8: Settings Tab | M1-M11 | PASS |
| Phase 9: Chat Tab UI | N1-N13 | PASS |
| Phase 10: Console Audit | L1-L2 | PASS — 0 unexpected errors |
| Phase 11: Bug Collection | -- | All bugs fixed |

### Bugs Found and Fixed

| # | Bug | Severity | Fix | Status |
|---|-----|----------|-----|--------|
| 1 | Storage tab model count included `_metadata.json` — showed "2 Models" instead of "1 Model" | Low | Skip files starting with `_` in `getStorageInfo()` | FIXED |

### Expected Warnings (not bugs)

| Warning | Classification |
|---|---|
| `racommons-llamacpp-webgpu.js` 404 | EXPECTED — WebGPU variant not built, CPU fallback works |
| `n_ctx_seq (8192) < n_ctx_train (128000)` | EXPECTED — Context window limited for browser memory |

### Previously Fixed Bugs (from development)

| # | Bug | Fix |
|---|-----|-----|
| 1 | OPFS persistence race condition | Added `await this.storage.initialize()` in `refreshDownloadStatus()` |
| 2 | Sherpa-ONNX JS files lacked ESM exports | Added `export { ... }` statements |
| 3 | Module duplication (Vite singleton issue) | Added `resolve.alias` in `vite.config.ts` |
| 4 | Peer dependency semver prerelease mismatch | Changed to `>=0.1.0-beta.0` |
| 5 | Build script verification paths outdated | Updated to `racommons-llamacpp.wasm` paths |
| 6 | Platform adapter null function signature mismatch | Used full PlatformAdapter class instead of inline minimal version |
