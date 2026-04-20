// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.

package com.runanywhere.sdk.`public`

import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.channelFlow

/**
 * Chat-style wrapper over LLMSession. Manages message history and exposes
 * `generate(messages)` → `Flow<String>` (token text).
 *
 *     val chat = ChatSession("qwen3-4b", "/path", systemPrompt = "Be helpful.")
 *     chat.generate(listOf(ChatMessage.user("Hi"))).collect(::print)
 */
class ChatSession(
    modelId: String,
    modelPath: String,
    systemPrompt: String = "",
    format: ModelFormat = ModelFormat.GGUF,
) {
    private val llm = LLMSession(modelId, modelPath, format)
    private var systemPromptInjected: Boolean = false

    init {
        if (systemPrompt.isNotEmpty()) {
            val rc = llm.injectSystemPrompt(systemPrompt)
            systemPromptInjected = (rc == 0)
        }
    }

    fun generate(messages: List<ChatMessage>): Flow<String> = channelFlow {
        val rendered = renderMessages(messages, skipSystem = systemPromptInjected)
        val source = if (systemPromptInjected)
            llm.generateFromContext(rendered)
        else
            llm.generate(rendered)

        source.collect { token ->
            if (token.kind == TokenKind.ANSWER) {
                send(token.text)
            }
        }
    }

    suspend fun generateText(messages: List<ChatMessage>): String {
        val buf = StringBuilder()
        generate(messages).collect { buf.append(it) }
        return buf.toString()
    }

    fun cancel(): Int = llm.cancel()
    fun resetHistory(): Int = llm.clearContext().also { systemPromptInjected = false }
    fun close() { llm.close() }

    companion object {
        internal fun renderMessages(messages: List<ChatMessage>,
                                      skipSystem: Boolean): String {
            val sb = StringBuilder()
            for (m in messages) {
                if (skipSystem && m.role == ChatRole.SYSTEM) continue
                sb.append("<|im_start|>${m.role.raw}\n${m.content}<|im_end|>\n")
            }
            sb.append("<|im_start|>assistant\n")
            return sb.toString()
        }
    }
}

data class ChatMessage(val role: ChatRole, val content: String) {
    companion object {
        fun system(content: String)    = ChatMessage(ChatRole.SYSTEM, content)
        fun user(content: String)      = ChatMessage(ChatRole.USER, content)
        fun assistant(content: String) = ChatMessage(ChatRole.ASSISTANT, content)
        fun tool(content: String)      = ChatMessage(ChatRole.TOOL, content)
    }
}

enum class ChatRole(val raw: String) {
    SYSTEM("system"), USER("user"),
    ASSISTANT("assistant"), TOOL("tool");
}
