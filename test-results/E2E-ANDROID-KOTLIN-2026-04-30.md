# Android Kotlin E2E — 2026-04-30

**Device:** Pixel 6a (27281JEGR01852), Android 16
**App:** com.runanywhere.runanywhereai.debug (installed, not rebuilt — prior agent install retained)
**Build commit:** 10acf0c3
**Tester notes:** Device had WiFi connectivity but libcurl SSL CA cert lookup failed (code 77) and DNS resolve failed (code 6) during model download, so no LLM model could be downloaded on-device. This prevented actual LLM generation testing. All screens were exercised for render/navigation/crash-safety; B07 spinner behavior and B04 structured-output JNI could not be triggered without a loaded model.

## Results
| # | Screen | Result | Notes |
|---|---|---|---|
| 1 | Chat welcome | PASS | "Welcome!" + orange "Get Started" CTA render cleanly; history icon in top-right. |
| 2 | Select LLM Model (bottom sheet, B06) | PASS | Sheet opens as modal; "Cancel / Select LLM Model" header is below status bar; device status card (Model/Chip/Memory/Neural Engine) and 15 models render. No overlap with clock/battery. |
| 3 | Model download (LFM2-350M-Q4) | PARTIAL | Tap on download pill enqueues download (`rac_http_dl_jni: Starting download`). Failed on device: libcurl code 6 "Couldn't resolve host name" and code 77 "Problem with the SSL CA cert". App logs `ModelSelectionViewModel ❌ Download stream error: ... Network error` and recovers gracefully — no crash, UI stays on sheet. |
| 4 | Settings | PASS | Renders: API Configuration (API Key: Not Set, Base URL: Using Default), Generation Settings (Temperature 0.7, Max Tokens 1000, System Prompt), Tool Calling, Storage Overview (Total 118 GB, Available 94.79 GB, Models Storage 0 B, Downloaded Models 0), Downloaded Models (No models…), Storage Management (Clear Cache, Clean Temporary Files), Logging Configuration, About. **No "Hardware" sub-screen exists in this app.** |
| 5 | More hub | PASS | Sections: Audio AI (STT, TTS), Document AI (Document Q&A), Model Customization (LoRA Adapters), Performance (Benchmarks), Solutions (Solutions). |
| 6 | Speech to Text | PASS | "Voice to Text" hero with green "Get Started" CTA; renders without crash. |
| 7 | Text to Speech | PASS | "Read Aloud" hero with purple "Get Started" CTA; renders without crash. |
| 8 | Document Q&A (RAG) | PASS | Embedding Model / LLM Model selectors ("Not selected"), Select Document CTA, question input bar at bottom. No crash. |
| 9 | Solutions | PASS-render / FAIL-functional | Screen opens. Tapping "Voice Agent" prints "Voice Agent: creating solution from YAML…" then "Voice Agent: rac_solution_create_from_yaml returned a null handle" — no crash but solution pipeline fails. |
| 10 | Benchmarks | PASS | Device card (Model google Pixel 6a / Architecture arm64 / RAM 5.86 GB / Available 508 MB), info card, category chips (LLM STT TTS VLM), descriptions, "Run All Benchmarks" button. |
| 11 | Vision tab | PASS | "Vision AI" → "Vision Chat" card entry renders. |
| 12 | Voice tab (Voice Assistant Setup) | PASS | Large mic icon, "Voice Assistant Setup" copy, 3 setup rows (Speech Recognition / Language Model / Text to Speech), "Start Voice Assistant" disabled until all 3 models chosen. No crash. |

## Recent fix verification
- **B06 ModalBottomSheet insets:** PASS — "Select LLM Model" sheet (the main ModalBottomSheet exercised) renders with its header below the status bar; content does not intrude under the clock/battery row. No overlap artifacts observed on the opened sheet.
- **B07 "Thinking…" spinner clears after LLM response:** UNABLE TO VERIFY — could not download a model (network error on device), so no generation was triggered. `isGenerating` state cannot be observed end-to-end.
- **B08 HW profile shows real chip name (Tensor G2):** NOT REPRODUCED — the Android example app does not have a dedicated "Settings → Hardware" screen. The two places the app surfaces CPU info are:
  - Chat → Select LLM Model sheet → Device Status card: **"Chip: arm64"**
  - More → Benchmarks → Device card: **"Architecture: arm64"**

  Both populate from `DeviceInfo.current.architecture` (Android `Build.SUPPORTED_ABIS` mapping → `"arm64"`), not from the native C++ proto's `chipName`. A grep of `examples/android/RunAnywhereAI` finds `chipName` only assigned from `architecture` (BenchmarkViewModel.kt line 238) or `Build.HARDWARE` fallback (line 246). No Kotlin caller consumes the C++ proto `chipName` field, so the B08 fix is not surfaced in the example app's UI. Verdict: **FAIL (not wired)**. Logcat grep for "tensor|chipname|socname" over 5000 lines returned nothing from the RunAnywhere SDK; only pixel-thermal kernel strings.
- **B04 extractStructuredOutput JNI:** N/A — structured output flow requires a loaded LLM model; network-offline prevented model download. No `UnsatisfiedLinkError` for `extractStructuredOutput` observed in logcat, which is the expected "happy path" for code that is never invoked.

## Overall: 10/11 render-level PASS, 1 functional finding (Solutions → Voice Agent YAML → null handle)

## Logcat anomalies
No `FATAL`, `AndroidRuntime`, `UnsatisfiedLinkError`, or uncaught `NullPointerException` across the session. Specific notable log lines:

- `rac_http_curl: libcurl error: code=6 (Couldn't resolve host name)` — repeated, on telemetry POST and model download.
- `rac_http_curl: libcurl error: code=77 (Problem with the SSL CA cert (path? access rights?))` — on HTTPS GET to huggingface.co. Native curl cannot find CA bundle on this device configuration.
- `[ERROR] [CppBridgeDownload] [Native] Download failed: … Network error.` — graceful propagation into Kotlin.
- `✗ Voice Agent: rac_solution_create_from_yaml returned a null handle` — Solutions pipeline bootstrap returns null; user-visible error but non-crashing.
- `[ERROR] [CppBridgeTelemetry] [Native] Telemetry HTTP failed: status=-1, response=null` — telemetry never reaches server, same root cause as CA bundle.

## Suggested follow-ups
1. **Bundle CA cert with the native HTTP layer** (or use Android system trust store) — `rac_http_curl` error 77 breaks every HTTPS egress on this device.
2. **Wire `chipName` from the native C++ hardware profile proto into Kotlin `DeviceInfo`** so the B08 fix actually surfaces in the Benchmarks and model-selection UI, instead of displaying the ABI string `"arm64"`.
3. **Investigate `rac_solution_create_from_yaml` null-return** — the Solutions screen's Voice Agent path is broken at the native layer.
