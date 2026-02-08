# iOS Benchmark Notes

## Prompt Status: Ready for implementation
The `BENCHMARKS_IMPLEMENTATION_PROMPT.md` contains verified SDK APIs, exact file paths, and full implementation sketches for all 5 providers. An implementor can follow it directly.

## What was added in latest iteration
- Category filter chip implementation sketch added to BenchmarkDashboardView (section 2.9.1)
- "Save CSV to Files" option added alongside JSON in toolbar export menu (section 2.10.1)
- Test cases T21 (Save to Files) and T22 (Haptic feedback) added to manual test plan
- AC-14 added for "Save to Files" action; AC numbering fixed (was duplicate AC-15, now AC-14 through AC-32)
- `downloadedModels` filter simplified: includes built-in models too (removed `!$0.isBuiltIn`)
- All SDK APIs re-verified against current source — all still match

## Key Gotchas to Watch For
- **TTS unload**: The method is `unloadTTSVoice()` (not `unloadTTSModel()`)
- **VLM load**: Pass `ModelInfo` object, not `model.id` string
- **Diffusion load**: Must use `model.localPath!.path` (filesystem string), not model ID
- **Settings section placement**: New "Performance" section goes between "Logging Configuration" and "About" in `IOSSettingsContent`
- **`@Observable` vs `@ObservableObject`**: Use `@Observable` for new ViewModel (AC-26). Existing app VMs use `ObservableObject` but new code should use the modern pattern.
- **`synthesize` vs `speak`**: Use `synthesize()` for benchmarks to avoid audio playback overhead
- **VLM unload is non-throwing**: `RunAnywhere.unloadVLMModel()` is `async` only (no `throws`), unlike other components
- **`BenchmarkStore`**: Only call from `@MainActor` (ViewModel). Do NOT call from `BenchmarkRunner` actor.
