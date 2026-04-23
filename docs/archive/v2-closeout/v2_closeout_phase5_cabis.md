# v2 close-out Phase 5 — new C ABIs landing for Wave D

_What ships in this commit_, and _what's deferred to the per-platform Wave D delete phases (where it's tightly coupled to the corresponding consumer change)._

## Shipped now

### `rac_llm_thinking.h` — Swift `ThinkingContentParser` replacement

Three C entry points covering everything the Swift `ThinkingContentParser` does today, with byte-equivalent semantics:

| C ABI | Swift equivalent |
|-------|------------------|
| `rac_llm_extract_thinking()`        | `ThinkingContentParser.extract(from:)`     |
| `rac_llm_strip_thinking()`          | `ThinkingContentParser.strip(from:)`       |
| `rac_llm_split_thinking_tokens()`   | `ThinkingContentParser.splitTokens(...)`   |

Header: [`sdk/runanywhere-commons/include/rac/features/llm/rac_llm_thinking.h`](../sdk/runanywhere-commons/include/rac/features/llm/rac_llm_thinking.h)
Impl:   [`sdk/runanywhere-commons/src/features/llm/rac_llm_thinking.cpp`](../sdk/runanywhere-commons/src/features/llm/rac_llm_thinking.cpp)
Tests:  [`sdk/runanywhere-commons/tests/test_llm_thinking.cpp`](../sdk/runanywhere-commons/tests/test_llm_thinking.cpp) — 10 scenarios green.

The strings are returned via `thread_local std::string` slots so callers see plain `const char*` outputs without thinking about C++ ownership. Each output channel (`response`, `thinking`, `stripped`) gets its own slot so a single call doesn't clobber a previous output the caller hasn't copied yet.

This is the first C ABI added to commons since GAP 11. It is consumed by **Phase 9** (Swift TextGen sweep) which deletes the `ThinkingContentParser` class in `RunAnywhere+TextGeneration.swift` and replaces every `ThinkingContentParser.extract(...)` site with a thin C bridge call.

## Deferred to the per-platform delete phases

### `rac_auth_*` JNI thunks (Phase 7 / P2-2 — Kotlin auth)

Spec: add a `sdk/runanywhere-commons/src/jni/rac_auth_jni.cpp` wrapping the existing `rac/infrastructure/network/rac_auth_manager.h` declarations.

**Why deferred to Phase 7**: the JNI thunk file only earns its keep when `CppBridgeAuth.kt` is being deleted in the same commit. Adding the thunks now without the consumer means dead JNI code in commons + an unbacked deprecation marker on `CppBridgeAuth.kt`. Phase 7 lands them together so the diff is reviewable as one atomic switch:
- `git rm CppBridgeAuth.kt` (~568 LOC out)
- `+ sdk/runanywhere-commons/src/jni/rac_auth_jni.cpp` (~150 LOC in)
- `+ sdk/runanywhere-kotlin/.../CppBridgePlatformAdapter.kt` JNI extern declarations (~30 LOC in)
- per-call-site repoint inside the Kotlin SDK

### `DownloadServiceStreamAdapter` per-SDK (~150 LOC × 5 SDKs)

Spec: copy the existing `VoiceAgentStreamAdapter` template, swap the proto type from `VoiceEvent` → `DownloadProgress`, route to the Phase-3-generated `download_service` stubs.

**Why deferred to Phases 11 / 12 / 13 / 14**: each per-platform delete phase already touches that SDK's `Adapters/` directory; folding the new download adapter into the same commit makes the diff cohesive. The five adapters land like this:

| Phase | File | Replaces |
|-------|------|----------|
| 11 (Swift Download)      | `sdk/runanywhere-swift/Sources/RunAnywhere/Adapters/DownloadServiceStreamAdapter.swift`   | retry+progress block in `AlamofireDownloadService.swift` |
| 12 (Dart sweep)          | `sdk/runanywhere-flutter/packages/runanywhere/lib/adapters/download_service_stream_adapter.dart` | helpers in `runanywhere.dart` |
| 13 (RN sweep)            | `sdk/runanywhere-react-native/packages/core/src/Adapters/DownloadServiceStreamAdapter.ts`        | (no current direct consumer; future) |
| 14 (Web sweep)           | `sdk/runanywhere-web/packages/core/src/Adapters/DownloadServiceStreamAdapter.ts`                 | (no current direct consumer; future) |
| Phase 7 follow-up (Kotlin)| `sdk/runanywhere-kotlin/src/jvmAndroidMain/kotlin/com/runanywhere/sdk/adapters/DownloadServiceStreamAdapter.kt` | helpers in `CppBridgeDownload.kt` |

The C++ side is **already shipped** in commons (`rac/infrastructure/download/rac_download.h`); the per-language adapter is the only thing missing. Each adapter is the same 100-150 LOC pattern as the Voice equivalent — `subscribe(req) → onMessage(bytes) → decode → emit` with cancellation propagated to the C side.

## Why this split is safe

- **`rac_llm_thinking`** has zero direct consumers in commons today — the impl is dead code on `feat/v2-architecture` until Phase 9 wires Swift to it. Building it now is risk-free.
- **`rac_auth_*` JNI** has the opposite property: adding it standalone without Phase 7's repoint creates a new attack surface that nothing exercises. Wait for the consumer.
- **DownloadServiceStreamAdapter** is per-SDK glue that needs the per-SDK Adapters/ directory to exist. Each platform Wave D phase already touches Adapters/.

The goal is **one atomic delete-with-replacement diff per platform**, not "infrastructure now, deletes later" — which is the same trap Wave D fell into the first time around (markers without deletes).
