/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 */

package com.runanywhere.sdk.public.api

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

// `ToolCallingOptions.auto_execute` is optional now (idl/tool_calling.proto):
// absent means "let commons decide" rather than a caller-supplied choice, so
// these assertions unwrap with a non-null default matching the orchestrator's
// own true-by-default contract.
private fun Boolean?.orDefaultTrue(): Boolean = this ?: true

/**
 * PR #605 review issue #7 — `llm.generate`/`llm.generateStream` with inline
 * `tools` hardcoded `auto_execute = true` on the proto sent to
 * [com.runanywhere.sdk.public.extensions.LLM.ToolCallingOrchestrator], so
 * there was no way to reach `LlmOptions(autoExecute = false)` -- the field
 * did not even exist on the public options. `makeToolCallingRunLoopRequest`
 * already forwarded whatever `auto_execute` it was given onto
 * `ToolCallingSessionCreateRequest.auto_execute`, which the native run loop
 * (`tool_calling_run_loop.cpp`) honors correctly; the hop that dropped the
 * caller's choice was [LlmOptions.toolCallingProtoForOrchestrator].
 */
class AutoExecuteContractTest {
    @Test
    fun `default LlmOptions requests auto-execution`() {
        val proto = LlmOptions().toolCallingProtoForOrchestrator()
        assertTrue(proto.auto_execute.orDefaultTrue())
    }

    @Test
    fun `explicit autoExecute = false reaches the orchestrator proto`() {
        val proto = LlmOptions(autoExecute = false).toolCallingProtoForOrchestrator()
        assertFalse(proto.auto_execute.orDefaultTrue())
    }

    @Test
    fun `explicit autoExecute = true is preserved`() {
        val proto = LlmOptions(autoExecute = true).toolCallingProtoForOrchestrator()
        assertTrue(proto.auto_execute.orDefaultTrue())
    }

    @Test
    fun `autoExecute is independent of tool choice and tool list`() {
        val proto =
            LlmOptions(
                tools = emptyList(),
                toolChoice = ToolChoice.Required,
                autoExecute = false,
            ).toolCallingProtoForOrchestrator()
        assertFalse(proto.auto_execute.orDefaultTrue())
    }
}
