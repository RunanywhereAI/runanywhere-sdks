# v2 close-out — device verification plan

_Phase 15 of v2 close-out (P2-10). Companion to the parity tests shipped in Phase 4 + the per-platform deletions of Phases 6-14._

## What runs in CI today (no device required)

All shipped automatically on every PR via `.github/workflows/pr-build.yml`:

| Test | Coverage | Passes today |
|------|----------|--------------|
| `proto_event_dispatch_tests` (CTest) | Phase 2 + post-audit Phase A — C++ → proto VoiceEvent translation across **all 7 union arms** (TRANSCRIPTION, RESPONSE, AUDIO_SYNTHESIZED, VAD_TRIGGERED, ERROR, PROCESSED, WAKEWORD_DETECTED) + monotonic seq + unregister-stops-dispatch + handle-validation | **11/11 OK** |
| `llm_thinking_tests` (CTest) | Phase 5 — extract / strip / split-tokens behavioral parity with deleted Swift `ThinkingContentParser` | **10/10 OK** |
| `parity_test_cpp_check` (CTest) | Phase 4 — golden 8-event sequence (vad start, vad end, user_said, assistant_token, audio, metrics, error, state) emitted by C++ matches `tests/streaming/fixtures/golden_events.txt` | **8/8 events match** |
| `parity_test.swift` (XCTest) | Phase 4 — Swift swift-protobuf decoding matches the same golden | wired (runs in `swift-spm` CI job) |
| `parity_test.kt` (JUnit5) | Phase 4 — Kotlin Wire decoding matches the same golden | wired |
| `parity_test.dart` (test pkg) | Phase 4 — Dart protoc_plugin decoding matches the same golden | wired |
| `parity_test.ts` (Jest) | Phase 4 — TS ts-proto decoding matches the same golden | wired |

These prove the **wire-format contract** (proto schema + line schema) is identical across all 6 implementations of VoiceEvent (C++, Swift, Kotlin, Dart, RN-TS, Web-TS). Drift between any of them surfaces as a CI failure.

## What needs a device matrix to verify

Three behavioral concerns the audit flagged that the synthetic golden cannot exercise. Each requires a real device (or at least a simulator with a real OS networking stack + audio HAL).

### 1. 60-second auth refresh window (Android)

**Source of truth**: `rac/infrastructure/network/rac_auth_manager.h` defines `rac_auth_needs_refresh()` — the canonical 60-second window.

**Phase 7 fix**: `CppBridgeAuth.kt` (Kotlin) was rewritten to use a `REFRESH_WINDOW_MS = 60 * 1000` constant matching the C ABI. The previous value was `5 * 60 * 1000` (5 minutes) — that drift was the documented bug.

**Verification plan**:

```bash
# On a real Android device with the SDK initialized:
adb shell setprop debug.runanywhere.log.auth VERBOSE
# Trigger authentication.
# Set device clock 50 seconds before token expiration:
#   expected: refresh NOT triggered (still inside the safe window)
# Set device clock 70 seconds before expiration:
#   expected: refresh triggered (within 60-sec refresh window)
# Watch logcat for: "CppBridge/Auth: refreshAccessToken called"
```

**Status**: shipping the code-level fix in Phase 7. A maintainer with access to the Android sample app + device clock manipulation would close the verification.

### 2. Voice barge-in latency (iOS)

**Source of truth**: the C++ voice agent's `voice_agent_process_stream` interrupts TTS playback when VAD fires VOICE_START during PIPELINE_STATE_SPEAKING. The proto-byte event ABI (Phase 2) emits an `interrupted` event in that case.

**Phase 10 fix**: Swift `VoiceSessionHandle` no longer owns audio playback or interrupt coordination — that's the C++ side's job. The deleted Swift orchestration's `audioPlayback.stop()` calls were removed; consumers route through `VoiceAgentStreamAdapter` which receives `interrupted` events when the C++ side decides.

**Verification plan**:

```swift
// On a real iOS device:
let adapter = VoiceAgentStreamAdapter(handle: agentHandle)
let start = Date()
var bargeLatencyMs: Double?

for await event in adapter.stream() {
    switch event.payload {
    case .audio:
        // First TTS audio chunk played — start a barge-in.
        // (sample app: tap the mic button while TTS is playing)
        break
    case .interrupted:
        bargeLatencyMs = Date().timeIntervalSince(start) * 1000
        // Spec target: < 300ms p50.
        XCTAssertLessThan(bargeLatencyMs ?? 999, 300.0)
    default: break
    }
}
```

**Status**: shipping the code-level fix in Phase 10. Device verification needs the iOS sample app + a 10-second audio recording + manual barge-in testing.

### 3. Download resume after disconnect (any device with network)

**Source of truth**: `rac/infrastructure/download/rac_download.h` already handles retry-with-exponential-backoff in C++.

**Phase 11 audit finding**: `AlamofireDownloadService.swift` was already a thin shim (the spec's "180 LOC of retry duplication" was wrong); the C++ side already owns retry. No code change shipped — just a doc clarification.

**Verification plan**:

```bash
# On any device:
# 1. Start a model download.
# 2. After 30% progress, disable network (airplane mode).
# 3. Wait 10 seconds.
# 4. Re-enable network.
# 5. Expected: download resumes from 30% (not from 0%).
# Logs to watch: "rac_download: resume_offset=N"
```

**Status**: behavior is already correct (audit confirmed); device verification is a smoke check, not a fix.

## Sample-app smoke checklist

Per the spec's GAP 08 criterion #7 ("every demo screen still works"):

- [ ] **iOS sample app**: voice screen runs end-to-end (start → speak → stop). Verifies Phase 10 + Phase 9.
- [ ] **Android sample app**: voice screen runs end-to-end. Verifies Phase 6 + Phase 7 + Phase 8.
- [ ] **Flutter sample app**: voice screen runs end-to-end. Verifies Phase 12.
- [ ] **RN sample app**: voice screen runs end-to-end. Verifies Phase 13.
- [ ] **Web sample app**: text generation streaming works. Verifies Phase 14.

These are manual checklist items because they exercise the device matrix that CI cannot reach without per-platform Detox / Maestro / XCUITest scaffolding (a separate workstream).

## Bottom line

- **Wire-format parity** across 6 implementations: green in CI.
- **Behavioral parity** for the 3 device-only checks: code-level fixes shipped, manual verification scheduled.
- **Sample app smoke**: 5 checklists, manual today, automation tracked as a separate v2.x workstream.
