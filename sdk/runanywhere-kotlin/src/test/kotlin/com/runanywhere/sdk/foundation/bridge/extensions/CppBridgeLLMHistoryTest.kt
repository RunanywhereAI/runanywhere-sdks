package com.runanywhere.sdk.foundation.bridge.extensions

import ai.runanywhere.proto.v1.ChatMessage
import ai.runanywhere.proto.v1.LLMGenerateRequest
import ai.runanywhere.proto.v1.MessageRole
import kotlin.test.Test
import kotlin.test.assertEquals

/**
 * Pure-proto/Wire test (no JNI) for the multi-turn chat history plumbing.
 *
 * Proves the [LLMGenerateRequest.history] field (proto field 27) carries an
 * ordered list of [ChatMessage] turns and survives a Wire encode/decode
 * round-trip — the wire contract the Kotlin `generate`/`generateStream`
 * history param now populates.
 */
class CppBridgeLLMHistoryTest {
    private val history =
        listOf(
            ChatMessage(role = MessageRole.MESSAGE_ROLE_USER, content = "hi"),
            ChatMessage(role = MessageRole.MESSAGE_ROLE_ASSISTANT, content = "hello"),
        )

    @Test
    fun testRequestCarriesHistoryInOrder() {
        val request =
            LLMGenerateRequest(
                prompt = "how are you?",
                history = history,
            )

        assertEquals(2, request.history.size)
        assertEquals(history, request.history)
        assertEquals(MessageRole.MESSAGE_ROLE_USER, request.history[0].role)
        assertEquals("hi", request.history[0].content)
        assertEquals(MessageRole.MESSAGE_ROLE_ASSISTANT, request.history[1].role)
        assertEquals("hello", request.history[1].content)
    }

    @Test
    fun testHistoryRoundTripsThroughGeneratedAdapter() {
        val request =
            LLMGenerateRequest(
                prompt = "how are you?",
                history = history,
            )

        val decoded =
            LLMGenerateRequest.ADAPTER.decode(
                LLMGenerateRequest.ADAPTER.encode(request),
            )

        assertEquals("how are you?", decoded.prompt)
        assertEquals(history, decoded.history)
        assertEquals(MessageRole.MESSAGE_ROLE_USER, decoded.history[0].role)
        assertEquals("hi", decoded.history[0].content)
        assertEquals(MessageRole.MESSAGE_ROLE_ASSISTANT, decoded.history[1].role)
        assertEquals("hello", decoded.history[1].content)
    }
}
