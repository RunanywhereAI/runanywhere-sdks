# Flutter Android HTTP Refactor E2E — 2026-05-01

Device: Pixel 6a, API 36 (Android 16), serial `27281JEGR01852`.
App: `examples/flutter/RunAnywhereAI` → `com.runanywhere.runanywhere_ai` (debug APK).
Flutter: build apk --debug.

## Build

- `flutter pub get`: `Got dependencies!` (xml 6.6.1 note, unrelated).
- `flutter build apk --debug`: built in 24.8s → `build/app/outputs/flutter-apk/app-debug.apk` (156 MB).
  - Gradle messages confirm: `Local mode: Using native libraries from src/main/jniLibs/` for commons / llamacpp / onnx; Genie missing on this device (expected — non-Qualcomm NPU).
- Install via `adb install -r`: `Success`.

## Bundled binary state

Path: `sdk/runanywhere-flutter/packages/runanywhere/android/src/main/jniLibs/arm64-v8a/`

```
librac_commons.so      31,932,976 bytes   May  1 00:25
librunanywhere_jni.so   3,961,352 bytes   May  1 00:25
libc++_shared.so        1,794,776 bytes   May  1 00:25
libomp.so               1,229,304 bytes   May  1 00:25
libc++_shared.so.bak    6,769,800 bytes   Apr 25 13:02   (pre-H2 backup)
```

- **H2/H4 symbols present: YES**
  - `librunanywhere_jni.so` strings: `Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racHttpTransportRegisterOkHttp`, `racHttpTransportRegisterOkHttp: OkHttp transport installed`, `Lcom/runanywhere/sdk/foundation/http/OkHttpTransport$HttpResponse;`, etc.
  - `librac_commons.so` strings: `Platform HTTP transport registered`, `Platform HTTP transport unregistered; falling back to libcurl`.
  - Bundled binaries are current (dated 2026-05-01 00:25, matching the H2 rebuild window).

## Launch

- App cold-start: `am start -W … MainActivity` → `Status: ok, TotalTime: 1842 ms`.
- Flutter engine: `Using the Impeller rendering backend (Vulkan)`.
- Native loads observed (Flutter process pid=31194):
  - `libflutter.so`, `libdartjni.so`.
  - `librac_commons.so` — loaded directly by Dart FFI (not via Android SoLoader / no OkHttpTransport JNI glue on the Flutter plugin side).
  - `librac_backend_llamacpp.so`, `libonnxruntime.so`, `libsherpa-onnx-c-api.so`, `librac_backend_onnx.so`, `librac_backend_sherpa.so` — all ok.
  - `librac_backend_genie_jni.so` — not found (expected on Pixel 6a Tensor G1).
- **SDK init: `⚡ SDK initialization completed in 1454ms`** (cold start, including model-registry setup for 9 LlamaCpp models, 1 VLM, 5 STT/TTS, 1 embedding, RAG backend).
- Phase 1 complete timing from Dart log: init to "Phase 1 initialization complete" was ~25 ms of Dart work; total 1454 ms includes backend binding load. The 279 ms figure from earlier warm-start runs is not comparable to this cold-install measurement.
- **Crashes: NONE.** No AndroidRuntime/FATAL entries. Process still alive through the entire observed window.

## HTTP behavior

### OkHttp registration

- **NOT registered on Flutter.**
- The Flutter plugin loads `librac_commons.so` directly from Dart FFI (`packages/runanywhere/lib/…`). It does NOT instantiate Kotlin's `RunAnywhereBridge.racHttpTransportRegisterOkHttp(...)`, so the JNI path that installs the OkHttp platform transport on Kotlin/RN does not fire.
- Consequence: commons falls back to its libcurl transport. The "OkHttp HTTP transport registered" log we see in the Kotlin/native debug app does NOT appear in the Flutter app. Confirmed by comparing `adb logcat --pid=<flutter_pid>` with `--pid=<kotlin_pid>`.

### R4 workaround removed → HTTP now routes through commons: confirmed YES

Positive evidence the R4 removal of the dart:io Android HTTPS bypass (`http_client_adapter.dart:213-219`) is live and HTTPS now flows through FFI → commons → libcurl:

```
[HTTPClientAdapter] POST https://api.runanywhere.ai/api/v1/auth/sdk/authenticate
rac_http_curl: validate_and_setup: url=[https://api.runanywhere.ai/api/v1/auth/sdk/authenticate] method=[POST]
rac_http_curl: curl_easy_setopt(CURLOPT_URL) returned: 0 (OK)
rac_http_curl: libcurl error: code=6 (Couldn't resolve host name)
[DartBridge.Auth] Authentication error
    metadata: {error: HttpClientException(0): rac_http_request_send failed with code -151}
```

Key points:
- `HTTPClientAdapter.rawRequest` now calls `_sendBlocking` via `Isolate.run` (line 218), which goes through `rac_http_request_send` in commons. There is no longer a dart:io `HttpClient` branch for Android HTTPS.
- The DNS error surfaces as an `rac_http_curl` log from native commons with libcurl error code 6, then propagates to Dart as `HttpClientException(0): rac_http_request_send failed with code -151`. Pre-R4, an Android HTTPS request would have come back as `SocketException: Failed host lookup: …` from dart:io's `HttpClient`, without any `rac_http_curl` log line.
- The source comment in `http_client_adapter.dart` (lines 212-217) matches the observed behavior.

### Secondary observations

- `librac_commons.so` CA-bundle hook `racHttpClientSetCaBundle` raised an `UnsatisfiedLinkError` in the sister `com.runanywhere.runanywhereai.debug` native app (pre-H2 Kotlin bridge). Benign for Flutter — the Dart app does not invoke that JNI path.
- Dev-mode config still contains placeholder strings `YOUR_SUPABASE_PROJECT_URL` / `YOUR_BUILD_TOKEN`; telemetry & device registration fail as expected. Not in scope for this HTTP-refactor check.
- One Dart-side `SocketException: Failed host lookup: 'api.runanywhere.ai'` also appeared for the C++-emitted device registration POST. That path (`DartBridge.Device.HTTP.Device registration POST to: …`) uses a separate helper in the Dart layer that was not touched by R4; it's unrelated to the `HTTPClientAdapter` code path we're exercising. The authentication request that immediately follows does go through commons/libcurl as shown above, confirming the refactor.

## Chat test (if cached model)

- **Skipped.** `run-as com.runanywhere.runanywhere_ai find … -type d` shows only `app_flutter/flutter_assets`. No models directory, no cached GGUF. The lazy-discovery log confirms: `[RunAnywhere.Discovery] No downloaded models discovered`.
- Not exercising model download: offline (DNS resolution fails → no network in this test environment), and model download is not the object of this test.

## Overall: PASS

- Build: green, binaries bundled are post-H2, H2/H4 symbols present.
- Init: clean, 1454 ms cold-start, no crashes.
- HTTP: R4 removal is live and effective. HTTPS now routes Dart → FFI → commons → libcurl on Android (confirmed via `rac_http_curl` native log + `HttpClientException(0)` Dart error signature). Pre-R4 dart:io bypass is removed as intended.
- OkHttp registration on Flutter: **not applicable** — the Flutter plugin does not own a Kotlin JNI layer that calls `racHttpTransportRegisterOkHttp`. Commons falls back to libcurl inside its own binary, which is the documented "Desktop / other" path per the source comment. If we later want Flutter/Android to share the OkHttp transport with Kotlin/RN, we'd need to add a tiny Kotlin plugin-side glue that calls `RunAnywhereBridge.racHttpTransportRegisterOkHttp(...)` on plugin init. That's future work, out of scope for this E2E.

Test harness notes: no screenshots captured (per constraints), no commits, no rebuild of the bundled commons .so.
