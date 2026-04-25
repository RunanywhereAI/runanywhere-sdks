# W5 Web Module Wiring

Date: 2026-04-24
Branch: `feat/v2-architecture`
HEAD at start of remediation: `737bd781`

## What Changed

- Added `clearRunanywhereModule()` to Web core's `EmscriptenModule.ts`.
- Exported `clearRunanywhereModule` from `@runanywhere/web`.
- LlamaCpp backend init now registers its Emscripten module with:
  - `setRunanywhereModule`
  - `HTTPAdapter.setDefaultModule`
  - `ModelRegistryAdapter.setDefaultModule`
- LlamaCpp shutdown now clears:
  - `HTTPAdapter`
  - `ModelRegistryAdapter`
  - the singleton `runanywhereModule`
- Added `ModelRegistryAdapter.clearDefaultModule()`.
- Added `src/runtime/EmscriptenModule.test.ts`.

## Verification

```bash
cd sdk/runanywhere-web
npm run typecheck -w packages/core
npm run build -w packages/core
npm run typecheck -w packages/llamacpp
npm run test -w packages/core -- --run
```

Results:

- Web core typecheck PASS.
- Web core build PASS.
- Web llamacpp typecheck PASS.
- Web Vitest PASS: 4 files / 9 tests, including:
  - singleton-backed `SolutionAdapter.run`
  - `ModelRegistryAdapter.clearDefaultModule`
  - existing streaming cancel/perf harness
  - existing voice-agent fan-out tests
