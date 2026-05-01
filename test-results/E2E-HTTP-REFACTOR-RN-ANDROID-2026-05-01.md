# RN Android HTTP Refactor E2E — 2026-05-01

Task S4c — Live E2E for React Native Android example app on Pixel 6a (serial `27281JEGR01852`).
Package under test: `com.runanywhereaI` (RN example, Nitro + bundled prebuilt `librunanywherecore.so`).
Metro: running at localhost:8081 (reused existing process; `adb reverse tcp:8081 tcp:8081` configured).

## Build

- `node_modules` already present (no reinstall needed).
- `./gradlew installDebug --no-daemon`: **BUILD SUCCESSFUL in 51s** (34 executed, 419 up-to-date).
- APK installed on Pixel 6a.

## Launch

- Launched via `am start -n com.runanywhereaI/.MainActivity`.
- JS bundle loaded from Metro (Bridgeless/Fabric, Hermes).
- `ReactNativeJS: Running "RunAnywhereAI" with {"rootTag":1,"initialProps":{},"fabric":true}`.
- **SDK init: 112ms** (target ~150–300ms — passed).
  Log: `[App] SDK initialized: v0.2.0, Active, 112ms, env: {"name":"RunAnywhere Core","status":"initialized","version":"0.2.0","api":"rac_*","source":"runanywhere-commons","module":"core","initialized":true}`.
- All Nitro HybridObjects registered: RunAnywhereCore, RunAnywhereDeviceInfo, LLM, VoiceAgent, RunAnywhereGenie, RunAnywhereLlama, RunAnywhereONNX.
- All models registered (SmolLM2, Qwen2.5/3, LFM2 series, Mistral 7B, Llama 2 7B, Llama 3.2 3B, SmolVLM, Qwen2-VL, LFM2-VL, Sherpa Whisper Tiny, Piper TTS, MiniLM embedding).
- VLM LlamaCPP backend registered. Genie loaded but no NPU chip on Pixel 6a (Google Tensor), reported gracefully.
- **RedBox: NO** (one transient RedBox triggered by Metro-unreachable ECONNREFUSED before `adb reverse` was set; after adb reverse + relaunch, no RedBox occurred).

## HTTP state

- **OkHttp transport registered?: NO**
  Log: `RunAnywhereCorePackage: OkHttp HTTP transport registration returned rc=-100`
  This is EXPECTED — the RN example ships a prebuilt `librunanywherecore.so` that predates the H2 transport vtable. The JNI `racHttpClientSetTransport` entrypoint is missing from the bundled binary, so the Kotlin shim logs rc=-100 and returns without crashing. libcurl remains the active HTTP path inside the native SDK.
- **Telemetry HTTP behavior:**
  - `TelemetryBridge: Telemetry using Supabase: YOUR_SUPABASE_PROJECT_URL` (placeholder baseUrl from dev config).
  - `[WARN] [RunAnywhere] Device registration returned false` — expected because `YOUR_SUPABASE_PROJECT_URL` is not a real host; libcurl resolves to a network error.
  - No fatal errors; telemetry failures are logged and swallowed.
- Placeholder Supabase URL errors observed as expected (status=-1 / Network error pattern matches the Kotlin native app's behavior).

## Screens exercised (4/4)

1. **Chat tab (125, 2224)** — Loaded, opened Model Selection sheet ("Choose a Model" with 11 models listed). Dismissed via back.
2. **Vision tab (332, 2224)** — Rendered "Vision AI / Vision Chat / Chat with images using your camera or photos" and "Understand and create visual content with AI".
3. **Voice tab (540, 2224)** — Rendered "Voice Assistant Setup" with Language Model / Speech Recognition / Text to Speech sections and "Start Voice Assistant" button.
4. **Settings tab (956, 2224)** — Rendered Generation Settings (System Prompt, Temperature, Max Tokens), API Key, Base URL, Tool Calling, Save Settings. Also shows tab row with Chat / Vision / Voice / More / Settings labels.

App process `com.runanywhereaI` (pid 32302) remained alive throughout navigation. No fatal exceptions, no ANR, no crash dialogs.

## Notable non-fatal logs

- `OkHttp HTTP transport registration returned rc=-100` (expected; H2 ABI absent in bundled .so — F17 follow-up rebuild needed).
- `Full-path load of cdsprpc failed: library "/vendor/lib64/libcdsprpc.so" not found` (expected on non-Snapdragon Pixel 6a).
- `[WARN] [RunAnywhere] Device registration returned false` (expected — placeholder Supabase URL).
- `ReactNoCrashSoftException: onWindowFocusChange ... context is not ready` (transient RN warning during cold start, non-fatal).
- Telemetry network errors swallowed silently (expected with placeholder URL).

## Overall: PASS

RN Android example launches and operates cleanly with the current prebuilt binaries. SDK init finishes in 112ms, all models register, all four core screens (Chat / Vision / Voice / Settings) render without RedBox or crashes. HTTP behavior matches the predicted stub-mode state: the OkHttp transport registration no-ops (rc=-100) because the bundled `librunanywherecore.so` predates H2; libcurl handles telemetry and produces expected placeholder-URL errors that are logged and swallowed. No regressions from HTTP refactor Stages 1–3. Rebuild of the RN bundled commons binary to activate OkHttp transport is deferred to F17 (out of scope for S4c).
