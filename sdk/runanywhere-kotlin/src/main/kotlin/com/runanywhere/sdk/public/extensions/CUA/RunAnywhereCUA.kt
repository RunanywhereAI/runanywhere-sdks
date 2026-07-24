/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Public API for the Computer-Use Agent (CUA) scaffold.
 *
 * Turns a VLM into a drivable computer-use agent using a model *profile* (data
 * describing prompt / output format / coordinate convention). Fara1.5 ships
 * built in; adding another CUA model is a new profile in C++ commons, not new
 * API. This layer is stateless — pair it with `processImage`/`processImageStream`
 * for inference; the app owns screenshot capture, executing the action, and the
 * agent loop.
 *
 * Mirrors Swift RunAnywhere+CUA.swift exactly (iOS is the source of truth). The
 * facade calls `rac_cua_system_prompt` for the prompt and `rac_cua_parse_action_proto`
 * for parsing through the JNI bridge, decoding the returned
 * `runanywhere.v1.CuaAction` proto (Wire) into the structured [CuaAction] value
 * type — the same proto-byte bridging every other modality uses. Reached as
 * `RunAnywhere.CUA.*`.
 */

package com.runanywhere.sdk.public.extensions.CUA

import ai.runanywhere.proto.v1.CuaAction as CuaActionProto
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge

/**
 * A computer-use-agent action parsed from a model's output, with coordinates
 * already scaled to the caller's viewport. Model-agnostic (see [CUA]). Mirrors
 * the Swift `CuaAction` struct.
 */
data class CuaAction(
    /** The action the model wants to perform. */
    val kind: Kind,
    /** Viewport-scaled pixel coordinate (for click / move / drag), else null. */
    val coordinate: Coordinate?,
    /**
     * Primary string argument, interpreted by [kind]: TYPE→text, VISIT_URL→url,
     * WEB_SEARCH→query, TERMINATE→answer, ASK_USER/READ_PAGE_ANSWER→question,
     * PAUSE_MEMORIZE→fact, KEY→space-joined keys.
     */
    val text: String,
    /** Chain-of-thought the model emitted before the tool call, if any. */
    val reasoning: String,
    /** Scroll amount for scroll/hscroll (+up / -down). */
    val scrollPixels: Int,
    /** Seconds to wait for [Kind.WAIT]. */
    val waitSeconds: Double,
    /** Whether a valid tool call was found. */
    val isValid: Boolean,
) {
    /**
     * A viewport-scaled pixel coordinate. Structured value type so the public
     * API never leaks raw pairs / arrays.
     */
    data class Coordinate(val x: Int, val y: Int)

    /**
     * The action the model wants to perform. Ordinals match the C
     * `rac_cua_action_type_t` enum in `rac_cua.h` — do not reorder.
     */
    enum class Kind(val rawValue: Int) {
        UNKNOWN(0),
        LEFT_CLICK(1),
        RIGHT_CLICK(2),
        DOUBLE_CLICK(3),
        TRIPLE_CLICK(4),
        MOUSE_MOVE(5),
        LEFT_CLICK_DRAG(6),
        TYPE(7),
        KEY(8),
        SCROLL(9),
        HSCROLL(10),
        VISIT_URL(11),
        HISTORY_BACK(12),
        WEB_SEARCH(13),
        READ_PAGE_ANSWER(14),
        PAUSE_MEMORIZE(15),
        ASK_USER(16),
        WAIT(17),
        TERMINATE(18),
        ;

        companion object {
            /** Map a C `rac_cua_action_type_t` ordinal to a [Kind], defaulting to [UNKNOWN]. */
            fun fromRawValue(rawValue: Int): Kind =
                entries.firstOrNull { it.rawValue == rawValue } ?: UNKNOWN
        }
    }

    companion object {
        /** Build a [CuaAction] from the decoded `runanywhere.v1.CuaAction` proto. */
        internal fun from(proto: CuaActionProto): CuaAction =
            CuaAction(
                kind = Kind.fromRawValue(proto.type.value),
                coordinate = if (proto.coordinate_valid) Coordinate(proto.x, proto.y) else null,
                text = proto.text,
                reasoning = proto.reasoning,
                scrollPixels = proto.scroll_pixels,
                waitSeconds = proto.wait_seconds,
                isValid = proto.parse_ok,
            )
    }
}

/**
 * A declared coordinate space for a CUA profile's system prompt / a viewport to
 * rescale parsed coordinates into. Structured so the public API never passes a
 * bare width/height pair.
 */
data class CuaDisplay(val width: Int, val height: Int)

/**
 * Computer-use-agent scaffold namespace. Reached as `RunAnywhere.CUA`.
 *
 * Stateless and model-agnostic — `fara` is just the built-in profile id. Pair
 * these with the VLM inference APIs; the app owns screenshot capture, executing
 * the returned action, and the agent loop.
 */
object CUA {
    /** Built-in profile for Microsoft Fara1.5 / Qwen3.5-VL `computer_use`. */
    const val FARA_PROFILE: String = "fara"

    /** Fara's native coordinate space (1000x1000). */
    private val defaultDisplay = CuaDisplay(1000, 1000)

    /**
     * The system prompt (identity + `computer_use` tool schema) for a profile,
     * rendered at a declared coordinate space (pass the profile's native space,
     * e.g. 1000x1000 for Fara). Returns null for an unknown profile (or if the
     * native library is unavailable).
     */
    fun systemPrompt(
        profile: String = FARA_PROFILE,
        display: CuaDisplay = defaultDisplay,
    ): String? {
        if (!RunAnywhereBridge.ensureNativeLibraryLoaded()) return null
        return RunAnywhereBridge.racCuaSystemPrompt(profile, display.width, display.height)
    }

    /**
     * Parse a model's raw output into a [CuaAction], rescaling coordinates from
     * the profile's model space to [viewport]. Returns null for an unknown
     * profile (or if the native library is unavailable); [CuaAction.isValid] is
     * false when no tool call was found.
     */
    fun parseAction(
        modelOutput: String,
        profile: String = FARA_PROFILE,
        viewport: CuaDisplay,
    ): CuaAction? {
        if (!RunAnywhereBridge.ensureNativeLibraryLoaded()) return null
        val bytes =
            RunAnywhereBridge.racCuaParseAction(
                profile,
                modelOutput,
                viewport.width,
                viewport.height,
            ) ?: return null
        return CuaAction.from(CuaActionProto.ADAPTER.decode(bytes))
    }
}
