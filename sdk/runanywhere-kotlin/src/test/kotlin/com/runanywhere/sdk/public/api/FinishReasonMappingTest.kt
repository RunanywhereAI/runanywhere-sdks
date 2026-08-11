/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Pins commons FinishReason → public FinishReason mapping: no tool-call /
 * is_complete heuristics; UNSPECIFIED stays UNKNOWN; ERROR stays ERROR.
 */

package com.runanywhere.sdk.public.api

import ai.runanywhere.proto.v1.ToolCallingResult
import org.junit.Assert.assertEquals
import org.junit.Test
import ai.runanywhere.proto.v1.FinishReason as ProtoFinishReason

class FinishReasonMappingTest {
    @Test
    fun `finishReasonOf maps each commons value without inventing from local state`() {
        assertEquals(FinishReason.STOP, finishReasonOf(ProtoFinishReason.FINISH_REASON_STOP))
        assertEquals(FinishReason.STOP, finishReasonOf(ProtoFinishReason.FINISH_REASON_STOP_SEQUENCE))
        assertEquals(FinishReason.LENGTH, finishReasonOf(ProtoFinishReason.FINISH_REASON_LENGTH))
        assertEquals(FinishReason.LENGTH, finishReasonOf(ProtoFinishReason.FINISH_REASON_CONTEXT_OVERFLOW))
        assertEquals(FinishReason.TOOL_CALLS, finishReasonOf(ProtoFinishReason.FINISH_REASON_TOOL_CALLS))
        assertEquals(FinishReason.CANCELLED, finishReasonOf(ProtoFinishReason.FINISH_REASON_CANCELLED))
        assertEquals(FinishReason.ERROR, finishReasonOf(ProtoFinishReason.FINISH_REASON_ERROR))
        assertEquals(FinishReason.UNKNOWN, finishReasonOf(ProtoFinishReason.FINISH_REASON_UNSPECIFIED))
    }

    @Test
    fun `tool calling result with tool_calls still respects unspecified finish_reason`() {
        val result =
            ToolCallingResult(
                text = "",
                tool_calls = emptyList(),
                is_complete = false,
                finish_reason = ProtoFinishReason.FINISH_REASON_UNSPECIFIED,
            )
        // Presence of incomplete tool state must not invent STOP or TOOL_CALLS.
        assertEquals(FinishReason.UNKNOWN, finishReasonOf(result.finish_reason))
    }

    @Test
    fun `tool calling LENGTH is not collapsed to STOP when complete`() {
        val result =
            ToolCallingResult(
                text = "truncated",
                is_complete = true,
                finish_reason = ProtoFinishReason.FINISH_REASON_LENGTH,
            )
        assertEquals(FinishReason.LENGTH, finishReasonOf(result.finish_reason))
    }
}
