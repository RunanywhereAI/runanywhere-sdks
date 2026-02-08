# Shared Task Notes — Benchmarks Implementation Prompt

## Current State
- `BENCHMARKS_IMPLEMENTATION_PROMPT.md` is fully complete for BOTH iOS AND Android. All sections detailed, ready for implementation.
- iOS: 13 new files, 1 modification (`CombinedSettingsView.swift`). LLM/STT/TTS/VLM/Diffusion providers.
- Android: 12 new files + 1 XML resource, 5 modifications (`gradle/libs.versions.toml`, `app/build.gradle.kts`, `AndroidManifest.xml`, `AppNavigation.kt`, `SettingsScreen.kt`). LLM/STT/TTS providers (VLM/Diffusion are future extensibility).
- All SDK APIs verified against current source (both Swift and KMP).
- All Android file line number references verified (SettingsScreen.kt, AppNavigation.kt).
- Acceptance criteria split: AC-1 through AC-26 (cross-platform), AC-27 through AC-36 (Android), AC-37 through AC-42 (iOS), AC-43 through AC-46 (non-functional both).
- Test plan split: T1–T20 cross-platform, T21–T23 iOS-specific, T24–T31 Android-specific.

## Latest Android Refinements (iteration 7)
- Added section 1.7 "Timestamp Serialization — Cross-Platform Consistency"
- Fixed JSON export to produce ISO8601 timestamps (was raw Long) via `buildJsonObject`
- Fixed `dateFormat` UTC timezone (was using literal 'Z' without setting timezone)
- Fixed `BenchmarkRun` to use all `val` fields (was `var`; ViewModel uses `.copy()`)
- Fixed `lifecycle-runtime-compose` to document BOTH `gradle/libs.versions.toml` AND `app/build.gradle.kts` steps
- Updated file counts (12 new + 1 XML + 5 modified)
- Added future VLM image generation stubs in `SyntheticInputGenerator`
- Added version catalog to Appendix B3 key file references
- Added BenchmarkReportFormatter JSON builder imports to section 3.18

## Next Steps
1. **Implement iOS**: Follow sections 2.1–2.14 end-to-end.
2. **Implement Android**: Follow sections 3.1–3.19 end-to-end (use checklist at 3.19 for ordering).
3. Either platform can be implemented independently — they share the data model (section 1) but have independent code.

## Key Risks
- VLM model loading via `RunAnywhere.loadVLMModel(model)` requires complete download (iOS only).
- Diffusion benchmarks may take several minutes per scenario on device (iOS only).
- Android `FileProvider` must be configured in AndroidManifest.xml (section 3.13) — not yet present.
- Android `lifecycle-runtime-compose` dependency must be added to BOTH `gradle/libs.versions.toml` AND `app/build.gradle.kts`.
- Android `MediaStore.Downloads` requires API 29+ (fallback provided for API 24-28).
- Memory measurement: iOS uses `os_proc_available_memory()` (available → delta = before - after), Android uses `Debug.getNativeHeapAllocatedSize()` (allocated → delta = after - before).
- Android `SettingsSection` is private — new benchmark code inserted in same file body can use it, but extracting requires visibility change.
- Android JSON export timestamps must use ISO8601 formatting (section 1.7) — `writeJSON` already handles this via `buildJsonObject`.
