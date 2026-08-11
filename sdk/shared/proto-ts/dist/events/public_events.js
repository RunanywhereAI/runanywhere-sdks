"use strict";
/**
 * Canonical public stream-event grammars shared by Web / React Native / Electron.
 *
 * HAND-AUTHORED companion to the generated proto bindings. Discriminated unions
 * keyed by `type` — the v4 public API grammar (`started` → deltas → terminal
 * `completed` / `failed` / `cancelled`).
 *
 * Design rules:
 *   - `failed.error` is always the structured proto {@link SDKError} (Electron's
 *     IPC-safe choice). SDKs that historically used `Error` must adapt at the
 *     re-export boundary, not widen the shared type back to `Error`.
 *   - Result / match / transcription shapes differ across SDKs; those payload
 *     slots are type parameters so each SDK can bind its local public types
 *     without forking the discriminant arms.
 *   - Deprecated RN-only arms (`token`, `toolCall`) live in the
 *     `*WithDeprecated` aliases — keep them out of the canonical unions so new
 *     SDKs do not inherit dead surface area.
 */
Object.defineProperty(exports, "__esModule", { value: true });
exports.AgentState = exports.TokenKind = void 0;
/** Whether a streamed delta is answer text or a thought. */
exports.TokenKind = {
    TEXT: 'text',
    THOUGHT: 'thought',
};
/** What a voice session is doing right now. */
exports.AgentState = {
    LISTENING: 'listening',
    THINKING: 'thinking',
    SPEAKING: 'speaking',
};
