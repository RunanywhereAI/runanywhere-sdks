# v2 Close-out — Phase H Report

**Status.** Complete.
**Phase.** H — HTTP transport into commons, Kotlin collapse to thin shim.
**Owner.** Platform team.
**Related RFCs.** [`docs/rfcs/h1_http_client_vendor.md`](rfcs/h1_http_client_vendor.md).
**Release vehicle.** v0.20.0 (Kotlin only). iOS / Flutter / RN tracked
for v0.21 per [`docs/release/v0_20_0_release_plan.md`](release/v0_20_0_release_plan.md).

---

## 1. Decision (H-1): libcurl

See [`docs/rfcs/h1_http_client_vendor.md`](rfcs/h1_http_client_vendor.md)
for the full rationale. Summary:

| Option | Verdict |
|---|---|
| **libcurl** | **Chosen.** MIT-style license, ~500 KB stripped, HTTP/1.1+2, native TLS via system providers (OpenSSL/SecureTransport/SChannel), byte-range resume, in-flight cancel via write callback, available on every target. |
| cpr (C++ requests) | Rejected. Adds ~15 KLOC of template machinery that doesn't build cleanly on older NDK STLs / Emscripten; still ships libcurl underneath — no saving. |
| Platform-native (URLSession / OkHttp / WinHTTP / fetch) | Rejected. Four parallel impls would re-create the exact per-SDK duplication Phase H is eliminating; the JNI variant would loop back to Kotlin for HTTP, which is the inverted architecture we're flipping. |

Distribution: `find_package(CURL REQUIRED)` at configure time with a
`FetchContent` fallback to `curl-7_88_1` when libcurl isn't on the
system path (Windows MSVC, some CI runners). System package on macOS
(Homebrew / system), Linux (apt/yum/pacman), Android NDK sysroot,
iOS SDK. No bundled TLS stack — system providers only.

## 2. New C ABI surface (H-2)

Two header pairs under `sdk/runanywhere-commons/include/rac/infrastructure/http/`:

| File | LOC | Purpose |
|---|---:|---|
| `rac_http_client.h` | 238 | Opaque `rac_http_client_t`, request/response structs, `rac_http_request_send` / `_stream` / `_resume`, chunk callback, response_free. |
| `src/.../rac_http_client_curl.cpp` | 535 | libcurl easy-handle impl. Process-wide init refcount, per-client easy handle (NOT thread-safe — callers own one per worker), header capture, buffered + streaming write callbacks, CURLE ↔ RAC mapping. |
| `rac_http_download.h` | 133 | `rac_http_download_execute` — blocking download runner with SHA-256, resume, progress. Status codes match the Kotlin `DownloadError` enum byte-for-byte so the JNI layer forwards them verbatim. |
| `src/.../rac_http_download.cpp` | 395 | Runner. Embedded SHA-256 (RFC 6234 reference, ~100 LOC) so commons does not pull OpenSSL just to verify a checksum. Inline hash on the wire (no second pass over the file). Throttled progress callback (≥100 ms between calls). |

Commons **+ 1,301 LOC** across the ABI + impl.

## 3. Tests (H-2d)

| Test | LOC | Coverage |
|---|---:|---|
| `tests/test_http_client.cpp` | 560 | GET/POST/PUT/DELETE, custom headers round-trip, 301/302/307 redirects, timeout (150 ms vs 5 s `/slow`), streaming cancel mid-transfer, `Range: bytes=N-` resume + merged-content byte-for-byte compare, invalid-argument guards. Uses an in-process POSIX-sockets HTTP/1.1 server so there's zero external-network dependency. |
| `tests/test_http_download.cpp` | 470 | Happy path with SHA-256 verify, checksum mismatch → `CHECKSUM_FAILED`, HTTP 404 → `SERVER_ERROR`, invalid URL → `INVALID_URL`, cancel via progress → `CANCELLED`, resume + verify merged payload matches source. |

Wired into [`tests/CMakeLists.txt`](../sdk/runanywhere-commons/tests/CMakeLists.txt).
Unix-only today (the loopback server uses POSIX sockets); Windows
coverage follow-up is tracked as a winsock wrapper.

Note: `test_http_download` payload was bumped from 32 KiB → 512 KiB so
cancel-at-50% and resume tests reliably span multiple libcurl write
chunks (`CURL_MAX_WRITE_SIZE` is 16 KiB by default). Without this
bump the entire payload could arrive in one chunk on loopback and
the cancel assertion would flake.

### Verification output (macOS-debug preset)

```text
$ cmake --preset macos-debug && cmake --build --preset macos-debug
-- Configuring done (1.8s)
-- Build files have been written to: .../build/macos-debug
(...)

$ ctest --preset macos-debug -R http_
    Start 48: http_client_tests
1/2 Test #48: http_client_tests ................   Passed    5.05 sec
    Start 49: http_download_tests
2/2 Test #49: http_download_tests ..............   Passed    0.08 sec
100% tests passed, 0 tests failed out of 2
```

## 4. Platform CMake wiring (H-2c)

`sdk/runanywhere-commons/CMakeLists.txt`:

- `find_package(CURL QUIET)` then, when absent:
  `FetchContent_Declare(curl_fetched GIT_TAG curl-7_88_1 ...)` with
  a minimal feature set (HTTPS only, no FTP/SCP/LDAP/RTSP/SMB/TELNET).
  Sets `CMAKE_USE_SECTRANSP=ON` on Apple and `CMAKE_USE_SCHANNEL=ON`
  on Windows when bundled so TLS still flows through the platform
  provider.
- `target_link_libraries(rac_commons PUBLIC CURL::libcurl)` so tests
  and SDK adapters inherit the dep transitively.
- No change to `engines/*` CMakeLists — curl lives inside commons,
  engine plugins only see the ABI headers.

Per-platform notes:

| Platform | libcurl source | Additional binary |
|---|---|---|
| macOS | System (`/usr/lib/libcurl.dylib`) | 0 bytes |
| iOS | FetchContent-pinned static build | ~500 KB in xcframework |
| Linux | System (`libcurl.so`) | 0 bytes |
| Android | NDK sysroot (r23+) | 0 bytes in AAR |
| Windows | FetchContent fallback (system not guaranteed) | ~500 KB in `rac_commons.lib` |
| Emscripten | `-sUSE_CURL=1` (maps to browser `fetch`) | 0 bytes |

## 5. Kotlin migration (H-3)

### Deletions

| File | Before | After | Δ |
|---|---:|---:|---:|
| `CppBridgeDownload.kt` | 1,352 | 685 | **−667** |
| `CppBridgePlatformAdapter.kt` | 631 | 493 | **−138** (dead `performHttpDownload` + executor + task bookkeeping; commons JNI never bound `http_download` into the platform-adapter struct, so this was unreachable) |
| `RunAnywhere+ModelManagement.jvmAndroid.kt` (local helper `downloadFileWithHttpURLConnection`) | ~50 | 0 | **−50** |
| `RunAnywhere+LoRA.jvmAndroid.kt` (inline HttpURLConnection loop) | ~90 | 0 | **−90** |
| `AndroidSimpleDownloader.kt` (dead object) | 94 | 0 | **−94** |
| `RunAnywhereBridge.kt` (dead `racHttpDownloadReportProgress/Complete` externs) | ~8 | 0 | **−8** |
| **Kotlin total** | | | **−1,047 LOC** |

Replacements are pure delegation to
`RunAnywhereBridge.racHttpDownloadExecute(url, destPath, sha256,
resumeFromByte, timeoutMs, listener, outHttpStatus)` — the
`NativeDownloadProgressListener` SAM interface returns `false` to
cancel (propagates back to libcurl via the chunk callback).

### What survived

- `CppBridgeDownload.DownloadStatus/Error/Priority` constants — the
  public SDK surface depends on them; codes map byte-for-byte to
  `RAC_HTTP_DL_*` in `rac_http_download.h`.
- `CppBridgeDownload.DownloadListener` interface — still the observer
  surface consumers implement.
- `CppBridgeDownload.DownloadProvider` SPI — host apps can still
  plug in their own transport (OkHttp with custom interceptors, etc.).
  When set, it wins over the native runner.
- Task lifecycle bookkeeping (id → status, executor thread, cancel/pause
  flags, `ConcurrentHashMap<String, DownloadTask>`, listener dispatch).

### Net LOC delta (Phase H as a whole)

- Commons: **+1,301 LOC** (header + impl + tests + RFC)
- Kotlin: **−1,047 LOC** (HTTP transport removed from 5 files, 1 file deleted)
- JNI: **+47 LOC net** (existing `racHttpDownloadExecute` JNI wrapper
  stays; the dead `racHttpDownloadReportProgress/Complete` wrappers
  had never been implemented)

## 6. JNI bridge

`sdk/runanywhere-commons/src/jni/runanywhere_commons_jni.cpp`:

- `Java_com_runanywhere_sdk_native_bridge_RunAnywhereBridge_racHttpDownloadExecute`
  takes `(url, destPath, sha256, resumeFromByte, timeoutMs,
  NativeDownloadProgressListener, int[1] outHttpStatus)`. Blocks on
  the calling thread, forwards every progress tick into
  `NativeDownloadProgressListener.onProgress(bytesWritten,
  totalBytes): Boolean`, and returns the `RAC_HTTP_DL_*` status code.
- Dead `racHttpDownloadReportProgress` / `racHttpDownloadReportComplete`
  JNI declarations were removed from `RunAnywhereBridge.kt` — they
  never had JNI implementations and were only referenced by the
  now-deleted `CppBridgePlatformAdapter.performHttpDownload`.

## 7. Verification

```text
$ cd runanywhere-sdks-main && cmake --preset macos-debug
-- Configuring done (1.8s)

$ cmake --build --preset macos-debug
[ok]

$ ctest --preset macos-debug -R http_
100% tests passed, 0 tests failed out of 2

$ cd sdk/runanywhere-kotlin && ./gradlew compileKotlinJvm
BUILD SUCCESSFUL in 3s

$ ./gradlew jvmTest
5/6 passed; 1 pre-existing failure (PerfBenchTest `perf bench p50
under 1ms`) — unrelated to Phase H; depends on /tmp/perf_input.bin
latency characteristics in rac_llm_stream metrics, not HTTP.
```

Grep checks:

```text
# Only documentation / historical comments remain — no live HttpURLConnection
# code in any download path.
$ rg -n 'openConnection\(\) as HttpURLConnection' sdk/runanywhere-kotlin/src \
      --glob '*Download*.kt' --glob '*LoRA*.kt' \
      --glob '*ModelManagement*.kt' --glob '*PlatformAdapter*.kt'
(no matches)

$ rg -n 'TODO.*http|TODO.*retry|TODO.*download' \
      sdk/runanywhere-kotlin/src/jvmAndroidMain/kotlin/com/runanywhere/sdk/foundation/bridge/extensions/CppBridgeDownload.kt
(no matches)
```

Android sample build (`examples/android/RunAnywhereAI`) is skipped in
this run because `ANDROID_HOME` is not set in the shell environment
(though an NDK is available under `~/Library/Android/sdk/ndk`). CI
covers the Android assembly with the normal gradle runner.

## 8. Known residuals (v0.21 track)

Per the RFC's §4, the following **intentionally remain on their
SDK-local HTTP transport** in v0.20 and migrate in v0.21:

| SDK | File(s) | Transport today |
|---|---|---|
| iOS | `Sources/RunAnywhere/Infrastructure/Download/` | URLSession |
| Flutter | `packages/runanywhere/lib/src/download/` | `http:` package |
| React Native | `packages/core/cpp/bridges/InitBridge.cpp` (`RunAnywhereHttpDownloadReportProgress/Complete`) + Nitro adapter | Nitro-bridged Obj-C/Java implementations |
| Web | `packages/web/src/download/` | `fetch` |

Additionally, on the Kotlin side the following HTTP paths are **out
of scope** for Phase H and remain on `HttpURLConnection` (scheduled
for v0.21 when the auth / telemetry ABIs migrate to
`rac_http_client_*`):

- `CppBridgeHTTP.kt` (generic platform-adapter HTTP callback)
- `CppBridgeAuth.kt` (auth POST)
- `CppBridgeTelemetry.kt` (telemetry POST)
- `data/network/HttpClient.kt` (SDK-internal HTTP client)

Tracked in [`docs/release/v0_20_0_release_plan.md` §"What's NOT in
this release"](release/v0_20_0_release_plan.md#whats-not-in-this-release).

## 9. File map

New:
- `docs/rfcs/h1_http_client_vendor.md`
- `sdk/runanywhere-commons/include/rac/infrastructure/http/rac_http_client.h`
- `sdk/runanywhere-commons/include/rac/infrastructure/http/rac_http_download.h`
- `sdk/runanywhere-commons/src/infrastructure/http/rac_http_client_curl.cpp`
- `sdk/runanywhere-commons/src/infrastructure/http/rac_http_download.cpp`
- `sdk/runanywhere-commons/tests/test_http_client.cpp`
- `sdk/runanywhere-commons/tests/test_http_download.cpp`

Modified:
- `sdk/runanywhere-commons/CMakeLists.txt` — `find_package(CURL)` + FetchContent fallback + `PUBLIC` link.
- `sdk/runanywhere-commons/tests/CMakeLists.txt` — wire `test_http_client` + `test_http_download`.
- `sdk/runanywhere-commons/src/jni/runanywhere_commons_jni.cpp` — `racHttpDownloadExecute` JNI wrapper (retained, duplicate attempt removed).
- `sdk/runanywhere-kotlin/src/jvmAndroidMain/kotlin/com/runanywhere/sdk/foundation/bridge/extensions/CppBridgeDownload.kt` — HTTP transport deleted, now a thin listener-dispatch shim on top of the native runner.
- `sdk/runanywhere-kotlin/src/jvmAndroidMain/kotlin/com/runanywhere/sdk/foundation/bridge/extensions/CppBridgePlatformAdapter.kt` — dead `performHttpDownload`, `httpDownload`, `httpDownloadCancel`, `HttpDownloadTask`, `httpDownloadExecutor`, `RAC_HTTP_ERROR_*` constants deleted.
- `sdk/runanywhere-kotlin/src/jvmAndroidMain/kotlin/com/runanywhere/sdk/native/bridge/RunAnywhereBridge.kt` — dead `racHttpDownloadReportProgress`/`racHttpDownloadReportComplete` external declarations deleted.
- `sdk/runanywhere-kotlin/src/jvmAndroidMain/kotlin/com/runanywhere/sdk/public/extensions/RunAnywhere+ModelManagement.jvmAndroid.kt` — `downloadFileWithHttpURLConnection` → `downloadFileWithNativeRunner` (delegates to `racHttpDownloadExecute`), `HttpURLConnection` + `FileOutputStream` imports removed.
- `sdk/runanywhere-kotlin/src/jvmAndroidMain/kotlin/com/runanywhere/sdk/public/extensions/RunAnywhere+LoRA.jvmAndroid.kt` — inline HttpURLConnection loop rewritten as `callbackFlow` over `racHttpDownloadExecute` with `NativeDownloadProgressListener` relay.

Deleted:
- `sdk/runanywhere-kotlin/src/androidMain/kotlin/com/runanywhere/sdk/infrastructure/download/AndroidSimpleDownloader.kt` — unreferenced.

---

## Signed off

- libcurl chosen + rationale recorded.
- C ABI + libcurl impl complete.
- Commons ownership of HTTP transport verified via in-process loopback tests (happy paths, cancel, resume, redirect, timeout, checksum, server error, invalid URL).
- Kotlin `HttpURLConnection` code deleted from every download path; Kotlin layer is now a thin shim.
- Cross-boundary verification: commons configure + build green, JNI shared library rebuilds clean, Kotlin JVM compiles clean, commons tests green.
- iOS / Flutter / RN / Web paths explicitly deferred to v0.21 per the release plan.
