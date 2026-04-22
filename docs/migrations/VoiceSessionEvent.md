# Migrating off `VoiceSessionEvent` (v2.1-1)

> **Target audience**: consumers of the RunAnywhere SDK's voice-session
> API who use the legacy `VoiceSessionEvent` enum. After v2.1, this
> type is a deprecated derived view over the canonical `VoiceEvent`
> proto (codegen'd from [`idl/voice_events.proto`](../../idl/voice_events.proto)).
>
> **Closes**: [`GAP 09 #6`](../../../v2_gap_specs/GAP_09_STREAMING_CONSISTENCY.md)
> ("zero hand-written `VoiceSessionEvent` types").

## Why the change

Before v2.1, every SDK shipped its own hand-written UX-shaped enum:

| SDK | Hand-written type | Cases |
|-----|-------------------|------:|
| Swift | `enum VoiceSessionEvent` | 10 |
| Kotlin | `sealed class VoiceSessionEvent` | ~9 |
| Dart | `sealed class VoiceSessionEvent` | ~9 |
| React Native | `interface VoiceSessionEvent` | ~9 |
| Web | (shared via `@runanywhere/core`) | — |

5 parallel sources of truth → schema drift was inevitable. GAP 09
introduced a single `voice_events.proto` + codegen across all 5
SDKs, but the hand-written enums stayed in place during v2's
deprecation window.

v2.1-1 completes the migration: **the proto is canonical; the
hand-written enum is a deprecated derived view**.

## The mapping

The proto has 8 payload variants; the legacy enum had 10 UX cases.
Not every proto event maps to a UX case, and one legacy case
(`.turnCompleted`) aggregates multiple proto events.

| Legacy `VoiceSessionEvent` case | Proto `VoiceEvent.payload` | Notes |
|---------------------------------|----------------------------|-------|
| `.started` | `.state { current: IDLE }` | Emitted on session open |
| `.listening(audioLevel:)` | `.state { current: LISTENING }` | Audio level not in proto — populated with 0 |
| `.speechStarted` | `.vad { type: VOICE_START }` | |
| `.processing` | `.vad { type: VOICE_END_OF_UTTERANCE }` | |
| `.transcribed(text:)` | `.userSaid { text, is_final, confidence, audio_start_us, audio_end_us }` | Proto has more fields (confidence, audio timing) |
| `.responded(text:, thinkingContent:)` | `.assistantToken { text, is_final, kind }` | Proto has `TokenKind` enum (ANSWER / THOUGHT / TOOL_CALL); legacy `thinkingContent` is always nil in the mapper |
| `.speaking` | `.audio { pcm, sample_rate_hz, channels, encoding }` OR `.state { current: SPEAKING }` | Ambiguous; mapper picks the `.audio` path |
| `.turnCompleted(transcript:, response:, thinkingContent:, audio:)` | **Cannot be derived** | Aggregates 3+ proto events across a turn; callers must buffer |
| `.stopped` | `.state { current: STOPPED }` | |
| `.error(String)` | `.error { code, message, component, is_recoverable }` | Only `message` used by mapper; code / component / recoverable lost |

**Proto payloads with no legacy counterpart** (new surface, not
reachable via the derived view):

- `.metrics { stt_final_ms, llm_first_token_ms, ... }` — per-primitive latency breakdown; consumers who want SLO dashboards should subscribe to the proto stream directly.
- `.interrupted { reason, detail }` — barge-in signaling; legacy enum only knew pipeline state.
- `.vad { type: BARGE_IN | SILENCE | UNSPECIFIED }` — low-level VAD events; legacy only knew start/end.
- `.state { current: THINKING }` — LLM inference phase; legacy collapsed this into `.processing`.

## Per-SDK status after v2.1-1

| SDK | Status | Details |
|-----|--------|---------|
| **Swift** | Full migration | `VoiceSessionEvent.from(_:)` mapper shipped in [`VoiceAgentTypes.swift`](../../sdk/runanywhere-swift/Sources/RunAnywhere/Public/Extensions/VoiceAgent/VoiceAgentTypes.swift). Deprecation markers in place. |
| **Kotlin** | Scaffold | `@Deprecated` on `sealed class VoiceSessionEvent`; `companion object { fun from(event: VoiceEvent): VoiceSessionEvent? = null }` stub. Full implementation is the Kotlin per-SDK cleanup PR. |
| **Dart** | Scaffold | `@Deprecated` on `sealed class VoiceSessionEvent`; `static fromProto(VoiceEvent event)` stub. Full implementation is the Dart per-SDK cleanup PR. |
| **React Native** | Scaffold | `@deprecated` JSDoc on `interface VoiceSessionEvent`; `voiceSessionEventFromProto(event)` exported stub. Full implementation is the RN per-SDK cleanup PR. |
| **Web** | Shared with RN | Consumed through `@runanywhere/core`; no Web-exclusive duplicate. Status inherits RN. |

Why scaffolds for 4 of 5: the mapper body requires per-SDK idiom
decisions (Kotlin sealed-subclass matching, Dart switch expressions,
TS discriminated unions) + per-SDK proto-runtime imports that each
SDK maintainer should own. Swift is the template; the other 4 follow
the same structure.

## Before / after

**Before (Swift)**:

```swift
// Deprecated path — still compiles, still works in v2.x.
let stream = RunAnywhere.startVoiceSession(config: .default)
for await event in stream {
    switch event {
    case .transcribed(let text): updateUI(text)
    case .error(let msg):        showError(msg)
    default: break
    }
}
```

**After (Swift, preferred)**:

```swift
// Canonical proto path — subscribe directly; get the full event surface.
let adapter = VoiceAgentStreamAdapter(handle: agentHandle)
for await event in adapter.stream() {
    switch event.payload {
    case .userSaid(let e):   updateUI(e.text)
    case .error(let e):      showError(e.message)
    // NEW: metrics, interrupted, etc. available here
    case .metrics(let m):    logLatency(m.endToEndMs)
    default: break
    }
}
```

**After (Swift, backward compat via mapper)**:

```swift
// If you need to keep your old switch statements while the surrounding
// code migrates — VoiceSessionEvent.from(_:) is the bridge.
for await protoEvent in adapter.stream() {
    guard let legacyEvent = VoiceSessionEvent.from(protoEvent) else {
        continue  // proto event with no legacy counterpart
    }
    switch legacyEvent {
    case .transcribed(let text): updateUI(text)
    case .error(let msg):        showError(msg)
    default: break
    }
}
```

## Deferred work (follow-up PRs)

- **Swift rewire PR** (v2.1-1a): make the deprecated `startVoiceSession()` API internally call `VoiceAgentStreamAdapter.stream()` + `VoiceSessionEvent.from(_:)` instead of running its own orchestration. After this, the deprecated API is a thin shell.
- **Kotlin / Dart / RN / Web full implementation PRs** (v2.1-1b..e): port the Swift mapper pattern to each SDK, wire the deprecated APIs internally, run per-SDK behavioral verification.
- **Turn-aggregation helper** (v2.1-1f, optional): a separate utility that buffers proto events into turn-level `TurnCompletedEvent` values for consumers who want the `.turnCompleted` shape without writing their own buffering. Exactly once per SDK, in a non-deprecated module.

After those land, the hand-written `VoiceSessionEvent` can be
`git rm`'d across all 5 SDKs in v3 as part of the
`RAC_PLUGIN_API_VERSION 2u → 3u` cut-over.
