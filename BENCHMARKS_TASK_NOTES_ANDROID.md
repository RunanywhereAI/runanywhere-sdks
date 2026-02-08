# Android Benchmark Notes

## Prompt Status: Ready for implementation (refined — iteration 7)
The `BENCHMARKS_IMPLEMENTATION_PROMPT.md` contains verified KMP SDK APIs, exact file paths, full implementation sketches for all 3 providers (LLM, STT, TTS), complete UI composables, Android-specific export/share patterns, and a step-by-step implementation checklist (3.19). An implementor can follow sections 3.1–3.19 directly.

## What was refined in latest iteration (7)
- **Added section 1.7 "Timestamp Serialization — Cross-Platform Consistency"**: Documents the iOS `Date`→ISO8601 vs Android `Long` epoch millis difference. Clarifies that internal persistence can use raw `Long`, but JSON **export** must convert to ISO8601 strings for cross-platform compatibility.
- **Fixed JSON export (`writeJSON`)**: Replaced naive `json.encodeToString(run)` (which would emit `Long` timestamps) with explicit `buildJsonObject` construction that formats timestamps as ISO8601 strings via `dateFormat`. Added required `kotlinx.serialization.json.*` imports.
- **Fixed `dateFormat` timezone**: Added `.apply { timeZone = TimeZone.getTimeZone("UTC") }` to `SimpleDateFormat` in `BenchmarkReportFormatter` — the literal `'Z'` suffix alone doesn't set UTC.
- **Fixed `BenchmarkRun` data class**: Changed `var completedAt`, `var results`, `var status` → all `val`. The ViewModel already uses `.copy()` — `var` was unnecessary and non-idiomatic for Kotlin data classes.
- **Fixed `lifecycle-runtime-compose` dependency**: Now documents BOTH the `gradle/libs.versions.toml` entry AND the `app/build.gradle.kts` import (was missing the TOML step). Reuses existing `lifecycleRuntimeKtx = "2.8.7"` version ref.
- **Updated file counts**: Now 12 new files + 1 XML + **5** modified files (was 4; added `gradle/libs.versions.toml`).
- **Added future VLM image generation stubs**: `SyntheticInputGenerator.kt` now contains commented-out `solidColorBitmap()` and `gradientBitmap()` methods matching iOS's `SyntheticInputGenerator.swift`, ready to uncomment when VLM benchmarks are added.
- **Updated section 1.6**: Changed "Use `Codable` for serialization" to "Use `Codable` (iOS) / `kotlinx.serialization` with `@Serializable` (Android)" for clarity.
- **Added version catalog to Appendix B3**: `gradle/libs.versions.toml` now listed in key file references.
- **Added BenchmarkReportFormatter.kt imports to section 3.18**: JSON builder imports (`buildJsonObject`, `encodeToJsonElement`, `put`, `putJsonArray`, `addJsonObject`) now documented.

## Key Gotchas to Watch For
- **LLM load/unload**: `loadLLMModel(modelId)` / `unloadLLMModel()` (NOT `loadModel`/`unloadModel` like iOS)
- **TTS load**: `loadTTSVoice(voiceId)` — same name as iOS
- **TTS unload**: `unloadTTSVoice()` — same name as iOS
- **Use `synthesize()` not `speak()`**: `speak()` plays audio through speakers, adding overhead. `synthesize()` returns raw audio data.
- **Memory measurement**: Use `Debug.getNativeHeapAllocatedSize()`. Delta = after - before (opposite of iOS).
- **Streaming with metrics**: Use `generateStreamWithMetrics()` not `generateStream()` — the former returns `LLMStreamingResult` with both `Flow<String>` and `Deferred<LLMGenerationResult>`.
- **FileProvider NOT configured**: Must add `file_paths.xml` and manifest provider entry (section 3.13). No `file_paths.xml` exists in `res/xml/` currently.
- **`lifecycle-runtime-compose` NOT present**: Must add to BOTH `gradle/libs.versions.toml` AND `app/build.gradle.kts` (section 3.10 note).
- **SettingsScreen modification**: Add `onNavigateToBenchmarks` callback param + insert "Performance" section at line 196. Note: `SettingsSection` is private.
- **AppNavigation.kt**: Add `NavigationRoute.BENCHMARKS` and `BENCHMARK_DETAIL` routes (lines 172-178), add 2 `composable()` blocks, update SettingsScreen wiring (lines 66-68).
- **Timing**: Use `System.nanoTime()` (not `System.currentTimeMillis()`) for precision; divide by `1_000_000.0` for ms.
- **Save to Downloads**: MediaStore API 29+ path; legacy fallback for API 24-28.
- **`BenchmarkStore`**: NOT thread-safe. Only call from ViewModel (main/viewModelScope), not from BenchmarkRunner coroutine.
- **`getPackageInfo()` API 33+**: Use `PackageInfoFlags.of(0)` overload on API 33+; `@Suppress("DEPRECATION")` fallback for older.
- **`RunAnywhere.version`**: Delegates to `SDKConstants.VERSION` = `"0.1.0"`.
- **JSON export timestamps**: `writeJSON` uses `buildJsonObject` with manual ISO8601 formatting (NOT raw `encodeToString(run)` which would emit `Long` values). `dateFormat` must set `timeZone = UTC`.
- **`BenchmarkRun` fields**: All `val` (immutable). Use `.copy()` to create updated instances.
