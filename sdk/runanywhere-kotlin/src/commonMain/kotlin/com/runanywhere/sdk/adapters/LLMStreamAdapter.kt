/*
 * LLMStreamAdapter.kt
 *
 * Kotlin port of Swift's `Sources/RunAnywhere/Adapters/LLMStreamAdapter.swift`.
 *
 * This file used to (in the Swift world) carry ~221 LOC of fan-out
 * machinery — per-handle registry, lock-guarded continuations, retained
 * trampoline — that was bit-for-bit identical to `VoiceAgentStreamAdapter`
 * except for the native handle / proto event types and the
 * register/unregister C symbols. Phase 1 P1-T6 extracted that machinery
 * into the generic `HandleStreamAdapter<Handle, Event>`; this file is
 * now a thin specialization that wires the LLM-specific proto event
 * type and the LLM `is_final` terminal-event predicate.
 *
 * **W3-7 status — not currently wired to the public API.**
 *
 * The public LLM streaming entry point
 * [com.runanywhere.sdk.public.RunAnywhere.generateStream] still
 * routes through the single-call ABI
 * `rac_llm_generate_stream_proto(request_bytes, listener)` via
 * `CppBridgeLLM.generateStream(...)`, NOT through this adapter. The
 * Swift SDK is in exactly the same state: its
 * `LLMStreamAdapter` typealias exists alongside the
 * `rac_llm_set_stream_proto_callback` /
 * `rac_llm_unset_stream_proto_callback` C symbols, but
 * `RunAnywhere.generateStream` calls the single-call generated
 * `ProtoStreamContext` path instead.
 *
 * Migrating Kotlin's public surface to this adapter is gated on adding
 * the `racLlmSetStreamProtoCallback` / `racLlmUnsetStreamProtoCallback`
 * thunks to [com.runanywhere.sdk.native.bridge.RunAnywhereBridge] (the
 * underlying C symbols already ship in
 * `sdk/runanywhere-commons/include/rac/features/llm/rac_llm_stream.h`).
 * Once those thunks land, callers should switch to:
 *
 *     val adapter = llmStreamAdapter(
 *         handle = CppBridgeLLM.getHandle(),
 *         register = { h, cb -> RunAnywhereBridge.racLlmSetStreamProtoCallback(h, cb) },
 *         unregister = { h, id -> RunAnywhereBridge.racLlmUnsetStreamProtoCallback(h, id) },
 *     )
 *     adapter.stream().collect { event ->
 *         if (event.is_final) return@collect
 *         print(event.token)
 *     }
 *
 * to gain multi-collector fan-out (one C registration, N `Flow`
 * collectors) for free.
 *
 * Cancellation (once wired): ordinary `Flow` cancellation (collector
 * cancelled, the terminal `is_final` event fires, etc.) tears down the
 * C registration via the generic's `awaitClose` path.
 *
 * Why a typealias + top-level factory (and not a subclass)?
 *
 *   Swift specializes `HandleStreamAdapter` via a `typealias` plus an
 *   `extension` carrying a `convenience init`. Kotlin has neither
 *   extension constructors nor convenience initializers, so the
 *   equivalent shape is a `typealias` plus a free function that fills
 *   in the LLM-specific arguments. Subclassing `HandleStreamAdapter`
 *   would force the generic to be `open`, add a vtable for `stream()`,
 *   and obscure that this file contributes zero behavior beyond
 *   parameter binding — exactly the regression the Swift Phase 1
 *   refactor was meant to avoid.
 */

package com.runanywhere.sdk.adapters

import com.runanywhere.sdk.public.types.RALLMStreamEvent

/**
 * Specialization of [HandleStreamAdapter] for the LLM token stream.
 *
 * The native handle is the raw `rac_handle_t` (a `Long` on the JNI side),
 * and events are decoded as the Wire-generated [RALLMStreamEvent]
 * (alias of `ai.runanywhere.proto.v1.LLMStreamEvent`). All fan-out,
 * lifecycle, and cancellation semantics live in the generic — this
 * typealias only fixes the type parameters so the public
 * `LLMStreamAdapter` / `.stream()` shape matches Swift's.
 */
public typealias LLMStreamAdapter = HandleStreamAdapter<Long, RALLMStreamEvent>

/**
 * Build a [LLMStreamAdapter] wired to the LLM-specific C registration
 * symbols.
 *
 * Mirrors Swift's `convenience init(handle:)` on the LLM specialization:
 * fills in the [streamKey] (`"llm"`), the [RALLMStreamEvent] decoder,
 * and the LLM terminal-event predicate (`event.is_final`). The
 * register/unregister closures are injected by the caller because the
 * actual JNI thunks for `rac_llm_set_stream_proto_callback` /
 * `rac_llm_unset_stream_proto_callback` live in `jvmAndroidMain` and
 * are not visible from `commonMain`.
 *
 * @param handle Native LLM component handle (`rac_handle_t` as `Long`).
 * @param streamKey Identifier used by [HandleStreamAdapter]'s global
 *   fan-out registry. Defaults to `"llm"`; only override if you need a
 *   second LLM adapter family that must not share fan-out state with
 *   the default one.
 * @param register Closure that installs a proto-byte callback on the
 *   underlying handle. Must return a non-zero callback id on success or
 *   [HandleStreamAdapter.INVALID_CALLBACK_ID] on failure. Typically
 *   wraps `RunAnywhereBridge.racLlmSetStreamProtoCallback` (when
 *   exposed via JNI).
 * @param unregister Closure that tears down the C-side registration
 *   identified by the callback id returned from [register]. Typically
 *   wraps `RunAnywhereBridge.racLlmUnsetStreamProtoCallback`.
 */
public fun llmStreamAdapter(
    handle: Long,
    streamKey: String = "llm",
    register: (Long, (ByteArray) -> Unit) -> Long,
    unregister: (Long, Long) -> Unit,
): LLMStreamAdapter = HandleStreamAdapter(
    handle = handle,
    streamKey = streamKey,
    register = register,
    unregister = unregister,
    decodeEvent = { bytes -> RALLMStreamEvent.ADAPTER.decode(bytes) },
    isTerminalEvent = { event -> event.is_final },
)
