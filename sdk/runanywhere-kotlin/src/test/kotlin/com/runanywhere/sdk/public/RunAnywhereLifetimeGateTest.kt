/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 */

package com.runanywhere.sdk.public

import ai.runanywhere.proto.v1.ErrorCode
import com.runanywhere.sdk.foundation.errors.SDKException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.async
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertSame
import kotlin.test.assertTrue

class RunAnywhereLifetimeGateTest {
    @Test
    fun `reset rejects initialization until its matching completion`() {
        val gate = SDKLifetimeGate()
        gate.requireInitializationAllowed()

        val operation = gate.beginOrJoinReset()
        assertTrue(operation.isOwner)
        val error = assertFailsWith<SDKException> { gate.requireInitializationAllowed() }
        assertSame(ErrorCode.ERROR_CODE_INVALID_STATE, error.code)

        assertFalse(gate.finishReset(CompletableDeferred(), failure = null))
        assertFailsWith<SDKException> { gate.requireInitializationAllowed() }
        assertTrue(gate.finishReset(operation.completion, failure = null))
        gate.requireInitializationAllowed()
    }

    @Test
    fun `concurrent reset joins the same completion`() =
        runTest {
            val gate = SDKLifetimeGate()
            val owner = gate.beginOrJoinReset()
            val joiner = gate.beginOrJoinReset()

            assertTrue(owner.isOwner)
            assertFalse(joiner.isOwner)
            assertSame(owner.completion, joiner.completion)

            val waiting = async { joiner.completion.await() }
            assertFalse(waiting.isCompleted)

            assertTrue(gate.finishReset(owner.completion, failure = null))
            waiting.await()
            assertTrue(waiting.isCompleted)
        }

    @Test
    fun `failed reset stays latched until a later reset succeeds`() =
        runTest {
            val gate = SDKLifetimeGate()
            val failedAttempt = gate.beginOrJoinReset()
            val teardownFailure = IllegalStateException("teardown failed")

            assertTrue(gate.finishReset(failedAttempt.completion, teardownFailure))
            assertFailsWith<IllegalStateException> { failedAttempt.completion.await() }
            val blocked = assertFailsWith<SDKException> { gate.requireInitializationAllowed() }
            assertSame(ErrorCode.ERROR_CODE_INVALID_STATE, blocked.code)

            val retryAttempt = gate.beginOrJoinReset()
            assertTrue(retryAttempt.isOwner)
            assertTrue(gate.finishReset(retryAttempt.completion, failure = null))
            retryAttempt.completion.await()
            gate.requireInitializationAllowed()
        }

    @Test
    fun `failed initialization rollback requires an explicit reset`() =
        runTest {
            val gate = SDKLifetimeGate()
            gate.latchResetRequired(IllegalStateException("rollback failed"))

            assertFailsWith<SDKException> { gate.requireInitializationAllowed() }
            val reset = gate.beginOrJoinReset()
            assertTrue(reset.isOwner)
            assertTrue(gate.finishReset(reset.completion, failure = null))
            reset.completion.await()
            gate.requireInitializationAllowed()
        }

    @Test
    fun `reset owns shared retry work and invalidates stale generation`() =
        runTest {
            val gate = SDKLifetimeGate()
            val generation = gate.currentGeneration()
            val first = CompletableDeferred<Unit>()
            val duplicate = CompletableDeferred<Unit>()

            assertSame(first, gate.installRetryWork(generation, first))
            assertSame(first, gate.currentRetryWork(generation))
            assertSame(first, gate.installRetryWork(generation, duplicate))

            val reset = gate.beginOrJoinReset()
            assertTrue(reset.isOwner)
            assertSame(first, reset.retiringRetryWork)
            assertFalse(gate.isCurrent(generation))
            assertNull(gate.installRetryWork(generation, duplicate))
            assertFailsWith<SDKException> { gate.requireInitializationAllowed() }

            first.cancel()
            assertTrue(gate.finishReset(reset.completion, failure = null))
            gate.requireInitializationAllowed()
        }
}
