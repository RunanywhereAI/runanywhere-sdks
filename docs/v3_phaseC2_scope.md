# v3 Phase C2 — Deprecated SDK-Surface Deletion Scope

_Date: 2026-04-19_

## Decision: C2 scope-narrowed to a v3 addendum PR

The originally-planned C2 — delete `VoiceSessionEvent` / `VoiceSessionHandle` /
`startVoiceSession` / sibling deprecated API surface across all 5 SDKs — is
**NOT included in the v3.0.0 release** (this commit set). It moves to a
**v3.1** follow-up PR for the reasons below.

## Why deferred

The items originally listed in C2 fall into two categories:

### Category 1 — Clean delete, but shallow SDK-only

| Item | Status |
|------|--------|
| `voiceSessionEventFromProto` / `voiceSessionEventKindFromProto` (RN) | Safe to delete — helpers never called from sample apps. |
| `VoiceAgentEventData` export (Web) | Stays — it's the Web SDK's idiomatic event type (no parallel `VoiceSessionEvent` ever existed); deletion would be an unrelated UX breakage. |
| `postTelemetryEvent` (Web HTTPService) | Stays — not a deprecated API; it's actively used by the telemetry layer. |
| `getTTSVoices`, `getLogLevel`, `SDKErrorCode` (RN) | Need per-item audit (some are deprecated placeholders with real replacements; others are mislabeled). |
| `buildRegistrationJSON` (Swift CppBridge+Device) | Safe to delete — internal helper, no public consumers. |

### Category 2 — Deep cross-SDK + sample-app coupling

| Item | Surface |
|------|---------|
| `VoiceSessionEvent` (Swift, Kotlin, Dart, RN) | Deprecated enum/interface kept as a derived view over the canonical proto `VoiceEvent`. Sample apps (iOS VoiceAgentViewModel, Android VoiceAssistantViewModel, Flutter voice_assistant_view, RN VoiceAssistantScreen) all switch on this type. Deletion requires replacing each sample's voice-agent UI with the `VoiceAgentStreamAdapter` + proto-direct pattern. |
| `VoiceSessionHandle` (Swift, Kotlin, Dart) | Deprecated actor/class that drives the end-to-end voice session loop (STT → LLM → TTS orchestration). Still used by all 4 platform sample apps. Deletion means all sample apps migrate to the adapter-stream model — a separate UX-tested PR. |
| `startVoiceSession` / `streamVoiceSession` / `processVoice` (Swift, Kotlin, Dart, RN) | Entry points to the deprecated handle. Same sample-app coupling as above. |
| `startStreamingTranscription` (Swift) | Called by Swift's `LiveTranscriptionSession`. Removal means `LiveTranscriptionSession` needs its own migration. |

## What ships in v3.0.0 regardless

Everything from B0 through B11 + C1 + C3 ships:

- Plugin-registry ABI extension (v3 `create` op across 7 primitives)
- All 5 engines migrated from `rac_service_register_provider` to the unified
  `rac_engine_vtable_t` path
- All 7 commons consumers migrated to `rac_plugin_route` + `vt->ops->create`
- JNI + Swift bridging surface migrated to `rac_plugin_list`
- Legacy `service_registry.cpp` + 163 LOC of `rac_core.h` + CRACommons mirror
  + 4 export-list entries × 3 files DELETED (C1)
- `RAC_PLUGIN_API_VERSION` bumped 2u → 3u + semver 3.0.0 on all 7 packages (C3)

The deprecated SDK-surface shims are marked `@deprecated` / `@Deprecated` and
continue to work — they just trigger deprecation warnings that the v3.1 PR
will resolve via sample-app migration.

## v3.1 follow-up plan

A single follow-up PR titled **"v3.1: delete deprecated SDK surface + migrate
sample apps to VoiceAgentStreamAdapter"** covers:

1. Migrate each sample app's VoiceAssistant view/screen to
   `VoiceAgentStreamAdapter` + proto events (4 sample apps: iOS, Android,
   Flutter, RN).
2. Delete `VoiceSessionEvent` + `VoiceSessionHandle` + `startVoiceSession` /
   `streamVoiceSession` / `processVoice` + `startStreamingTranscription` from
   the 4 SDKs.
3. Delete internal helpers that only those APIs called
   (`buildRegistrationJSON`, Swift `LiveTranscriptionSession` if not used
   elsewhere, etc.).
4. Audit and delete remaining RN deprecations (`getTTSVoices`, `getLogLevel`,
   `SDKErrorCode`).

This ring-fences the scope so the v3.0.0 release ships clean without
sample-app breakage, and the deprecated-surface cleanup gets its own
focused, reviewable PR with sample-app validation.
