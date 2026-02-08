# Shared Task Notes — Benchmarks Implementation Prompt

## Current State
- `BENCHMARKS_IMPLEMENTATION_PROMPT.md` is fully complete for iOS. All implementation sketches, verified APIs, export UX, acceptance criteria (AC-1 through AC-32), and manual test plan (T1–T22) are specified. Ready for implementation.
- Android section is intentionally a placeholder — will be expanded in a separate iteration loop.
- All SDK APIs re-verified on 2026-02-07 — all match current source.

## Next Steps
1. **Implement iOS**: Follow `BENCHMARKS_IMPLEMENTATION_PROMPT.md` end-to-end to create all 13 files + 1 modification to `CombinedSettingsView.swift`.
2. **Android pass**: After iOS is implemented and validated, start a separate iteration loop to expand the Android section with the same level of detail.

## Key Risks
- VLM model loading via `RunAnywhere.loadVLMModel(model)` requires complete download (`.gguf` + `mmproj` files). Incomplete downloads will throw.
- Diffusion benchmarks may take several minutes per scenario on device. Cancel mechanism is critical.
- VLM `unloadVLMModel()` is `async` only (no `throws`), unlike other component unloads.
- `BenchmarkStore` is `Sendable` but should only be called from `@MainActor` context (the ViewModel).
