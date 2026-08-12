/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Focused wire/state coverage for Connect request-id cancellation.
 */

package com.runanywhere.sdk.public.connect

import ai.runanywhere.proto.v1.ConnectClientFrame
import ai.runanywhere.proto.v1.ConnectInvocationCancelRequest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import java.io.DataInputStream
import java.io.DataOutputStream

class ConnectCancelFrameTest {
    @Test
    fun cancelRequestRoundTripsInsideClientFrame() {
        val cancel =
            ConnectInvocationCancelRequest(
                session_id = "session-1",
                request_id = "req-42",
            )
        val encoded =
            ConnectClientFrame.ADAPTER.encode(
                ConnectClientFrame(cancel = cancel),
            )
        val decoded = ConnectClientFrame.ADAPTER.decode(encoded)
        assertTrue(decoded.cancel != null)
        assertEquals("session-1", decoded.cancel!!.session_id)
        assertEquals("req-42", decoded.cancel!!.request_id)
    }

    @Test
    fun lengthPrefixedCancelFrameUsesBigEndianSize() {
        val payload =
            ConnectClientFrame.ADAPTER.encode(
                ConnectClientFrame(
                    cancel =
                        ConnectInvocationCancelRequest(
                            session_id = "s",
                            request_id = "r",
                        ),
                ),
            )
        val stream = ByteArrayOutputStream()
        DataOutputStream(stream).use { out ->
            out.writeInt(payload.size)
            out.write(payload)
        }
        DataInputStream(ByteArrayInputStream(stream.toByteArray())).use { input ->
            val length = input.readInt()
            assertEquals(payload.size, length)
            assertTrue(length in 1..(4 * 1024 * 1024))
            val body = ByteArray(length)
            input.readFully(body)
            val frame = ConnectClientFrame.ADAPTER.decode(body)
            assertEquals("r", frame.cancel!!.request_id)
        }
    }

    @Test
    fun idleConnectStateDefaultsDoNotClaimAnActiveSession() {
        val state = ConnectState()
        assertFalse(state.isConnected)
        assertEquals(ConnectSession.DEFAULT_PROTOCOL_VERSION, state.protocolVersion)
        assertEquals(null, state.activeSessionId)
        assertEquals(ConnectStatus.IDLE, state.status)
    }
}
