# v3.1 React Native Deprecation Decisions

_Phase 1.5 of v3.1 Full Architectural Cleanup. Per-item dispositions for the
4 deprecated RN surface items identified by the v3.0.0 audit._

## Decision matrix

| # | Symbol | File:line | Replacement | Decision | Scope |
|---|--------|-----------|-------------|----------|-------|
| 1 | `getTTSVoices()` | `sdk/runanywhere-react-native/packages/core/src/Public/Extensions/RunAnywhere+TTS.ts:402` | `availableTTSVoices()` (same file) | **DELETE** | Phase 4.4 |
| 2 | `getLogLevel()` | `sdk/runanywhere-react-native/packages/core/src/Foundation/Logging/Services/LoggingManager.ts:278` | Direct property access: `config.minLogLevel` | **DELETE** | Phase 4.4 |
| 3 | `SDKErrorCode` enum | `sdk/runanywhere-react-native/packages/core/src/Foundation/ErrorTypes/SDKError.ts:26` | `ErrorCode` (numeric enum in same file) | **DELETE** | Phase 4.4 |
| 4 | `startStreamingSTT()` | `sdk/runanywhere-react-native/packages/core/src/Public/Extensions/RunAnywhere+STT.ts:369` | `transcribeStream()` (same file) | **DELETE** | Phase 4.4 |

## Rationale per item

### 1. `getTTSVoices()` — DELETE

```typescript
// RunAnywhere+TTS.ts:398-404
/**
 * Get available TTS voices (legacy)
 * @deprecated Use availableTTSVoices() instead
 */
export async function getTTSVoices(): Promise<string[]> {
  return availableTTSVoices();
}
```

One-line wrapper calling the canonical API. Zero external consumers in
first-party code. No behavioral difference. Safe delete.

### 2. `getLogLevel()` — DELETE

```typescript
// LoggingManager.ts:274-280
/**
 * Get current log level
 * @deprecated Use configuration.minLogLevel instead
 */
public getLogLevel(): LogLevel {
  return this.config.minLogLevel;
}
```

Trivial getter. The class's `config` is public (or exposed via
configuration getter). Consumers can read `config.minLogLevel` directly.

### 3. `SDKErrorCode` enum — DELETE

```typescript
// SDKError.ts:22-54
/**
 * Legacy SDK error code enum (string-based).
 * @deprecated Prefer using ErrorCode (numeric) for new code.
 */
export enum SDKErrorCode { ... }  // 27 string values
```

String-based error codes were the pre-v2 shape. v2+ uses numeric
`ErrorCode` values that match the proto-generated error codes (keeps
wire format + JSON parseable without string-matching). Both enums
coexist; deleting the string one forces consumers onto the numeric
one. Before delete, grep for external usage:

```sh
rg 'SDKErrorCode\.' sdk/runanywhere-react-native/ examples/react-native/
```

Any sample-app consumers get migrated to `ErrorCode` in Phase 4.4.

### 4. `startStreamingSTT()` — DELETE

```typescript
// RunAnywhere+STT.ts:365-379
/**
 * Start streaming speech-to-text transcription
 * @deprecated Use transcribeStream() for better API parity with Swift SDK
 */
export async function startStreamingSTT(...)
```

The replacement `transcribeStream()` mirrors the Swift/Kotlin/Dart
shape. The deprecated name is the only thing that differs. Safe
delete; grep for external usage in Phase 4.4.

## Execution in Phase 4.4

All 4 deletions happen in a single commit in Phase 4.4 alongside the
RN `VoiceSessionEvent` / `VoiceSessionHandle` deletes. Pre-delete
grep audit required to ensure no external consumers remain.

## Out of scope for v3.1

None. All 4 items are DELETE-READY.
