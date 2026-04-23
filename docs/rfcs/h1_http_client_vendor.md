# RFC H-1 — HTTP client vendor decision for `rac_http_client_*`

**Status.** Accepted.
**Phase.** v2 close-out — Phase H (Kotlin HTTP → commons).
**Owner.** Platform team.
**Scope.** Pick the C/C++ HTTP transport that backs the new
`rac_http_client_*` C ABI in `sdk/runanywhere-commons/src/infrastructure/http/`.

---

## 1. Context

Phase H moves the HTTP transport out of Kotlin
(`CppBridgeDownload.kt`, ~1.3 KLOC of `HttpURLConnection`) and into
commons behind a single C ABI. Every other SDK
(iOS / Flutter / RN / Web) currently re-implements the same primitives
(GET/POST, Range: resume, checksum-verify, chunked streaming, timeouts,
cancellation). The commons ABI becomes the canonical implementation and
each SDK collapses to a thin call-through shim (Kotlin first, iOS /
Flutter / RN follow as v0.21 work).

The ABI requirements are fixed (see `h1_http_client.md` / the parent
Phase H spec):

- Blocking `send` (full buffer) + `stream` (per-chunk callback) +
  `resume` (Range: bytes=N-).
- Redirect follow, custom headers, TLS, configurable timeouts,
  cancellation via callback return value.
- Must build on: macOS / Linux / Android NDK (API 26+) / iOS (17+) /
  Windows (MSVC 19.28+) / Emscripten.
- Stripped binary under ~1 MB; no GPL contamination; no mandatory
  runtime dependencies on platform package managers.

## 2. Alternatives considered

### Option A — **libcurl**  (chosen)

- Battle-tested (since 1998), MIT-style license (curl
  license, GPL-compatible, no attribution-in-binary requirement).
- Tiny stripped footprint — a minimal build (HTTP + HTTPS only,
  no FTP/SCP/LDAP/RTSP/SMB/TELNET/etc) compresses to ~500 KB including
  TLS linkage.
- Native HTTP/1.1 + HTTP/2, redirect (`CURLOPT_FOLLOWLOCATION`),
  resume (`CURLOPT_RESUME_FROM_LARGE`), cancellation (non-zero return
  from `CURLOPT_WRITEFUNCTION`).
- TLS via system providers — OpenSSL on Linux/Android,
  SecureTransport on macOS/iOS, SChannel on Windows. No bundled TLS
  stack means no certificate-store drift with the OS.
- Available off-the-shelf on every target:
  - macOS: Homebrew / system (`/usr/lib/libcurl.dylib`).
  - Linux: apt / yum / pacman (every distro).
  - Android NDK: shipped in the NDK sysroot from r23 onward.
  - iOS: ships with the SDK (private) — we use the same static
    build we FetchContent for Windows, to keep the link deterministic.
  - Windows: not in the base SDK; `vcpkg install curl` or our
    `FetchContent` fallback.
  - Emscripten: Emscripten port (`-sUSE_CURL`) maps to the browser's
    `fetch` under the hood.
- Single handle model (`CURL*`) maps cleanly onto the opaque
  `rac_http_client_t*` handle. `curl_easy_setopt` → set-per-request
  config, `curl_easy_perform` → blocking execute, write callback →
  our `rac_http_body_chunk_fn`.

### Option B — cpr (C++ Requests)

- Header-only C++17 wrapper **on top of libcurl**.
- Adds zero primitives we don't already need — its entire feature
  set is "libcurl with C++ types", at the cost of:
  - ~15 KLOC of C++ template machinery that fails to build cleanly
    on older Android NDK STLs and on Emscripten's `libc++`
    (verified: cpr trunk requires `<filesystem>`, not available in
    Emscripten sysroot by default).
  - Still ships libcurl as a dependency — nothing is saved.
  - `-fvisibility=hidden` (which we enforce in
    `sdk/runanywhere-commons/CMakeLists.txt` Release) requires
    explicit export markup that cpr does not provide.
- **Rejected.** If we want a C++ wrapper around libcurl, we write
  our own (30 lines) that matches our exact ABI. We do that inside
  `rac_http_client_curl.cpp`.

### Option C — platform-native (URLSession / OkHttp / WinHTTP / fetch)

- Each platform's idiomatic HTTP stack. Zero binary cost because
  every target already ships it.
- **Rejected** for commons because it directly contradicts the
  Phase H goal:
  - Commons would need four parallel implementations
    (Foundation/URLSession on Apple, Java/OkHttp called via JNI on
    Android+JVM, WinHTTP on Windows, Emscripten fetch on WASM).
  - Each implementation duplicates retry / resume / checksum /
    cancellation logic — the exact duplication Phase H is
    eliminating.
  - The JNI variant would call *back into Kotlin* for HTTP, which
    is the inverted architecture we're trying to flip.
  - License / distribution is fine but behavioral drift across
    four stacks (redirect semantics, `Range` header handling,
    TLS certificate pinning hooks) has already been a recurring
    bug pattern in v1 — we know empirically this doesn't
    converge.

## 3. Decision

**libcurl**, bundled as a system dep when available (`find_package(CURL
REQUIRED)`) with a `FetchContent` fallback to `curl-7_88_1` for
targets where the system package is absent (Windows MSVC by default,
Emscripten ports when `USE_CURL` is off, CI runners without apt /
brew / choco). TLS always via the platform-native stack — no bundled
OpenSSL.

The C ABI (`rac_http_client.h`) stays impl-agnostic: a different
backend (platform-native, `cpp-httplib`, etc.) can be dropped in as
`rac_http_client_<backend>.cpp` without touching any SDK consumer.

## 4. Consequences

### Added to the commons build graph

- `find_package(CURL REQUIRED)` at the top of
  `sdk/runanywhere-commons/CMakeLists.txt`.
- `CURL::libcurl` propagated `PUBLIC` on `rac_commons` so engine
  plugins and SDK adapters pick it up transitively.
- `FetchContent_Declare(curl_fetched ...)` gated on
  `NOT CURL_FOUND`, pinning
  [`curl/curl@curl-7_88_1`](https://github.com/curl/curl/releases/tag/curl-7_88_1).
- README entry:
  `sdk/runanywhere-commons/README.md` → "Dependencies → libcurl
  (system or FetchContent)."

### Distribution-surface impact

- macOS/iOS xcframeworks: libcurl is linked from `/usr/lib`; no new
  embedded binary.
- Android AAR: libcurl comes from the NDK sysroot; no new binary
  in the AAR.
- JVM: libcurl is loaded from the host system (same story as the
  existing `archive` + `zlib` deps).
- Windows: `rac_commons.lib` statically links the FetchContent
  copy; adds ~500 KB.
- Linux: `librac_commons.so` links against the system `libcurl.so`;
  no new binary.

### Kotlin-side fallout

- `CppBridgeDownload.kt` drops from 1,353 LOC to ~200 LOC
  (constants, listener interface, JNI-facing `@JvmStatic` callbacks
  that forward to commons). `HttpURLConnection` imports and usages
  **DELETED**, not deprecated.
- The `DownloadProvider` SPI remains — a consumer-supplied
  provider still takes precedence over commons when set.

### Follow-up work (NOT in Phase H)

- iOS / Flutter / RN download paths continue to use their
  platform-native HTTP in v0.20.0; they will cut over to
  `rac_http_client_*` in v0.21. Tracked in
  `docs/release/v0_20_0_release_plan.md §"What's NOT in this
  release"`.
