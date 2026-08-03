/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Mapping coverage for the Computer-Use-Agent facade.
 *
 * The parse itself lives in C++ commons and is covered there; what is unique to
 * this SDK — and therefore untestable from commons — is the translation of the
 * decoded `runanywhere.v1.CuaAction` proto into the public [CuaAction] value
 * type. A silent field mix-up here (coordinate_valid, scroll_pixels, parse_ok)
 * would hand callers a well-formed but wrong action, so it is asserted field by
 * field. No JNI required: the mapping is a pure function over the Wire type.
 */

package com.runanywhere.sdk.public.extensions.CUA

import ai.runanywhere.proto.v1.CuaActionType
import org.junit.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue
import ai.runanywhere.proto.v1.CuaAction as CuaActionProto

class CuaActionMappingTest {
    @Test
    fun `left click maps every field`() {
        val action =
            CuaAction.from(
                CuaActionProto(
                    type = CuaActionType.CUA_ACTION_TYPE_LEFT_CLICK,
                    coordinate_valid = true,
                    x = 720,
                    y = 344,
                    reasoning = "I will click the search box.",
                    parse_ok = true,
                ),
            )

        assertEquals(CuaAction.Kind.LEFT_CLICK, action.kind)
        assertEquals(CuaAction.Coordinate(720, 344), action.coordinate)
        assertEquals("I will click the search box.", action.reasoning)
        assertTrue(action.isValid)
    }

    @Test
    fun `coordinate is null when the proto does not mark it valid`() {
        // x/y still carry proto3 defaults; the facade must gate on
        // coordinate_valid rather than on the numbers being present.
        val action =
            CuaAction.from(
                CuaActionProto(
                    type = CuaActionType.CUA_ACTION_TYPE_TYPE,
                    coordinate_valid = false,
                    x = 11,
                    y = 22,
                    text = "hello world",
                    parse_ok = true,
                ),
            )

        assertNull(action.coordinate)
        assertEquals("hello world", action.text)
        assertEquals(CuaAction.Kind.TYPE, action.kind)
    }

    @Test
    fun `an all-default proto is a valid no-action result`() {
        // Commons emits this when no tool_call was found. It must decode to a
        // real object with isValid = false, never be mistaken for an error.
        val action = CuaAction.from(CuaActionProto())

        assertEquals(CuaAction.Kind.UNKNOWN, action.kind)
        assertNull(action.coordinate)
        assertEquals("", action.text)
        assertTrue(!action.isValid)
    }

    @Test
    fun `scroll and wait carry their own fields`() {
        val action =
            CuaAction.from(
                CuaActionProto(
                    type = CuaActionType.CUA_ACTION_TYPE_SCROLL,
                    scroll_pixels = -3,
                    wait_seconds = 2.5,
                    parse_ok = true,
                ),
            )

        assertEquals(-3, action.scrollPixels)
        assertEquals(2.5, action.waitSeconds)
    }

    @Test
    fun `key kind carries the space-joined chord`() {
        val action =
            CuaAction.from(
                CuaActionProto(
                    type = CuaActionType.CUA_ACTION_TYPE_KEY,
                    text = "ctrl l",
                    parse_ok = true,
                ),
            )

        assertEquals(CuaAction.Kind.KEY, action.kind)
        assertEquals("ctrl l", action.text)
    }

    @Test
    fun `kind ordinals line up with the proto enum one for one`() {
        // These ordinals mirror the C enum rac_cua_action_type_t. Any drift
        // silently re-labels every action crossing the bridge.
        val pairs =
            listOf(
                CuaActionType.CUA_ACTION_TYPE_UNSPECIFIED to CuaAction.Kind.UNKNOWN,
                CuaActionType.CUA_ACTION_TYPE_LEFT_CLICK to CuaAction.Kind.LEFT_CLICK,
                CuaActionType.CUA_ACTION_TYPE_KEY to CuaAction.Kind.KEY,
                CuaActionType.CUA_ACTION_TYPE_SCROLL to CuaAction.Kind.SCROLL,
                CuaActionType.CUA_ACTION_TYPE_TERMINATE to CuaAction.Kind.TERMINATE,
            )
        for ((proto, kind) in pairs) {
            assertEquals(kind.rawValue, proto.value, "ordinal drift for $kind")
            assertEquals(kind, CuaAction.Kind.fromRawValue(proto.value))
        }
    }

    @Test
    fun `an out of range ordinal degrades to UNKNOWN`() {
        assertEquals(CuaAction.Kind.UNKNOWN, CuaAction.Kind.fromRawValue(9999))
    }
}
