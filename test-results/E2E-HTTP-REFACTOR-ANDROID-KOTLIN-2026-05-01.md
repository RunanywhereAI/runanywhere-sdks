# Android Kotlin HTTP Refactor E2E — 2026-05-01

Stage 4 gate for Android Kotlin. Verifies that H4 OkHttp transport (via R3 streaming adapter) works on-device end-to-end against a real HuggingFace model download — the root purpose of the HTTP refactor (Stage 1-3 + H1-H8 wave).

## Device state
- Device: **Pixel 6a**, ADB serial `27281JEGR01852`
- Android version: **Android 16** (`ro.build.version.release=16`)
- Wi-Fi: SSID `RunAnywhere HQ`, 5 GHz 11ax, RSSI -51 dBm, LinkUp 9201 kbps / LinkDn 241–393 Mbps
- `ping -c 2 -W 2 8.8.8.8`: **2/2 received, 0% loss, 7.2/16.8/26.3 ms RTT**
- DNS: `net.dns1` property empty but ping by IP works; HTTPS download resolved domain successfully (see below)

## Build
- NDK cross-compile (`scripts/build-core-android.sh`, ANDROID_NDK_HOME=`~/Library/Android/sdk/ndk/27.0.12077973`): **PASS** — all ABIs (arm64-v8a / armeabi-v7a / x86_64) built; JNI libs copied to Kotlin / RN / Flutter module targets including `src/androidMain/jniLibs/*/libc++_shared.so` + `libomp.so` + `libsherpa-onnx-jni.so` + `libonnxruntime.so`
- `./gradlew :app:assembleDebug --no-daemon`: **BUILD SUCCESSFUL in 16s**, 96 actionable tasks, 10 executed
- APKs produced at `examples/android/RunAnywhereAI/app/build/outputs/apk/debug/`:
  - `app-arm64-v8a-debug.apk` (128.97 MB)
  - `app-x86_64-debug.apk` (59.46 MB)
- `adb install -r app-arm64-v8a-debug.apk`: **Streamed Install Success**

## SDK init

From logcat line at `01:05:23.997` on fresh launch (PID 32005, cleared at init):
```
[INFO] [RunAnywhereBridge] Loading native library 'runanywhere_jni'...
[INFO] [RunAnywhereBridge] ✅ Native library loaded successfully
[INFO] [CppBridge] ✅ Native commons library loaded successfully
[INFO] [CppBridge] AI inference features are AVAILABLE
[INFO] [CppBridge] ✅ OkHttp HTTP transport registered (system trust store + proxy)
[INFO] [CppBridge] ✅ SDK config initialized with version: 0.1.0
[INFO] [CppBridgeTelemetry] [Native] Telemetry manager initialized
```

- `✅ OkHttp HTTP transport registered (system trust store + proxy)`: **YES** — confirmed on every app launch
- `installCaBundle` completed: **NO — and irrelevant**. The legacy `racHttpClientSetCaBundle` JNI call raises `UnsatisfiedLinkError` because that bridge was removed when H4 switched to OkHttp. OkHttp uses the Android system trust store directly so no CA bundle install is required. The caller catches the exception; this is the expected post-refactor behavior. (Follow-up cleanup: remove the now-dead `RunAnywhereApplication.installCaBundle` call at line 114.)

## Model download test

- **Model**: `lfm2-350m-q4_k_m` (LiquidAI LFM2 350M Q4_K_M, advertised 238 MB on picker)
- **Actual size**: 229,309,376 bytes (218.7 MiB, advertised as 238 MB in UI ≈ 238 × 10⁶ rounded)
- **Transport path**: C++ download worker → `ra_http_* / rac_http_dl` ABI → Kotlin OkHttp transport adapter (system trust store)
- **HTTP status**: **200 OK**
- **Bytes transferred**: **229,309,376 bytes (~219 MB)** — full file, 100% complete
- **On-disk path after completion**: `/data/user/0/com.runanywhere.runanywhereai.debug/files/runanywhere/models/llm/lfm2-350m-q4_k_m` (exists: true, size: 229309376) — confirmed via `[Download] Downloaded file: ... (exists: true, size: 229309376)` log
- **Download duration**: tap registered at ~01:10:07, completion logged at `01:10:16.721` → ~9 s for 219 MB ≈ 24 MB/s (consistent with 5 GHz LinkDn ~240+ Mbps)
- **Download flow closed**: `Download flow closed for: lfm2-350m-q4_k_m` → `✅ Download completed for lfm2-350m-q4_k_m`

### Key assertions

| Assertion | Evidence | Result |
|---|---|---|
| NO `rc=77` (CURLE_SSL_CACERT_BADFILE) | `grep -c "rc=77"` → 0 hits in logcat | PASS |
| NO `CURLE_SSL_CACERT_BADFILE` string | `grep -c "CURLE_SSL_CACERT_BADFILE"` → 0 hits | PASS |
| OkHttp transport registered at init | `[INFO] [CppBridge] ✅ OkHttp HTTP transport registered (system trust store + proxy)` at 01:05:23.997 | PASS |
| Real bytes transfer | Progress log ladder 11% → 15% → 35% → ... → 94% → 99% → 100% with `bytes_written=229309376` | PASS |
| HTTPS works (HF redirect chain or direct) | `rac_http_dl: request_stream returned: rc=0 http_status=200 bytes_written=229309376` | PASS |
| Download completion callback fired | `[INFO] [Download] Download completed callback: /data/.../lfm2-350m-q4_k_m (229309376 bytes)` | PASS |
| Telemetry `model.download.completed` fired | `[DEBUG] [CppBridgeTelemetry] [Native] Request body: [{..."event_type":"model.download.completed"...}]` | PASS |

**Definitive single-line proof from the C++ download worker** (kernel log tag `rac_http_dl`, PID 32226, TID 523, timestamp `01:10:16.720`):
```
I rac_http_dl: request_stream returned: rc=0 http_status=200 bytes_written=229309376
```
This is the exact spot where `rc=77` used to fire on this device before H4 landed. `rc=0` is the C API's "success" code; `http_status=200` confirms the server response traversed the full OkHttp → JNI → C++ stream path without a fallback.

### HTTP activity trace counts (from dumped logcat ring buffer, ~22 k lines)

- `rc=77`: **0**
- `CURLE_SSL_CACERT_BADFILE`: **0**
- Any `rc=<nonzero>`: **0** — only `rc=0` observed on `rac_http_dl: request_stream`
- `libcurl` / `CURL*` error strings: **0**
- `x509` / `certificate` / `handshake failed`: **0**
- `rac_http_dl request_stream rc=0`: **1** (the success line above)

A second run-through ran through a larger 4 GB model (`4,368,438,944` bytes) reaching 35% before we re-launched to target the specified 238 MB — also zero SSL errors, also streaming via `OkHttp + rac_http_dl`.

## Overall: **PASS**
- HTTP refactor confirmed on Android Kotlin: **YES**
- Real HTTPS model download on Pixel 6a via OkHttp transport + system trust store: **VERIFIED**
- H4 OkHttp adapter is load-bearing on-device (not a fallback code path) — the `rac_http_dl` return is `rc=0 http_status=200`, proving the OkHttp JNI callback delivered headers + body to the C++ side
- R3 streaming adapter upgrade compiled and ran cleanly through a 229 MB response with no buffering issues

### Residual nits (non-blocking)
1. `RunAnywhereApplication.installCaBundle` at line 114 still invokes the removed `racHttpClientSetCaBundle` JNI and catches `UnsatisfiedLinkError`. Works, but spams two ERROR log lines per launch. Can be deleted when cleaning up Stage 3 detritus.
2. Telemetry HTTP POST to Supabase failed with `status=-1, response=null` — but that's the dev build's `YOUR_SUPABASE_PROJECT_URL` placeholder URL, not a transport issue (download worked fine).
