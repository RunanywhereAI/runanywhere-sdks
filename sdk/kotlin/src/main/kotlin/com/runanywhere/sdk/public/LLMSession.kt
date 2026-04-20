// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.

package com.runanywhere.sdk.`public`

import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.consumeAsFlow

/**
 * Direct LLM text-generation session. Wraps ra_llm_* C ABI via JNI.
 * Use `ChatSession` for multi-turn message history over this class.
 *
 *     val session = LLMSession("qwen3-4b", "/path/to/model.gguf")
 *     session.generate("Hello").collect { token -> print(token.text) }
 */
class LLMSession(
    modelId: String,
    modelPath: String,
    format: ModelFormat = ModelFormat.GGUF,
) {
    data class Token(val text: String, val kind: TokenKind, val isFinal: Boolean)

    private val emitter = Emitter()
    private val handle: Long

    init {
        require(NativeLibrary.isLoaded) { "racommons_core not loaded" }
        handle = nativeCreate(emitter, modelId, modelPath, format.raw)
        if (handle == 0L) throw RunAnywhereException(
            RunAnywhereException.BACKEND_UNAVAILABLE,
            "ra_llm_create returned null (no engine registered)")
    }

    fun generate(prompt: String, conversationId: Int = -1): Flow<Token> {
        emitter.channel = Channel(Channel.BUFFERED)
        val rc = nativeGenerate(handle, prompt, conversationId)
        if (rc != 0) {
            emitter.channel!!.trySend(Token("error rc=$rc", TokenKind.ANSWER, true))
            emitter.channel!!.close()
        }
        return emitter.channel!!.consumeAsFlow()
    }

    fun generateFromContext(query: String): Flow<Token> {
        emitter.channel = Channel(Channel.BUFFERED)
        val rc = nativeGenerateFromContext(handle, query)
        if (rc != 0) {
            emitter.channel!!.trySend(Token("error rc=$rc", TokenKind.ANSWER, true))
            emitter.channel!!.close()
        }
        return emitter.channel!!.consumeAsFlow()
    }

    fun cancel(): Int = nativeCancel(handle)
    fun reset(): Int = nativeReset(handle)
    fun injectSystemPrompt(prompt: String): Int =
        nativeInjectSystemPrompt(handle, prompt)
    fun appendContext(text: String): Int = nativeAppendContext(handle, text)
    fun clearContext(): Int = nativeClearContext(handle)

    fun close() { if (handle != 0L) nativeDestroy(handle) }

    @Suppress("unused")  // called from JNI
    internal class Emitter {
        var channel: Channel<Token>? = null

        fun onToken(text: String, kind: Int, isFinal: Boolean) {
            val tk = when (kind) {
                2 -> TokenKind.THOUGHT
                3 -> TokenKind.TOOL_CALL
                else -> TokenKind.ANSWER
            }
            channel?.trySend(Token(text, tk, isFinal))
            if (isFinal) channel?.close()
        }
        fun onError(code: Int, message: String) {
            channel?.trySend(Token("error[$code]: $message",
                                    TokenKind.ANSWER, true))
            channel?.close()
        }
    }

    private external fun nativeCreate(emitter: Emitter, modelId: String,
                                        modelPath: String, format: Int): Long
    private external fun nativeGenerate(handle: Long, prompt: String,
                                          convId: Int): Int
    private external fun nativeCancel(handle: Long): Int
    private external fun nativeReset(handle: Long): Int
    private external fun nativeInjectSystemPrompt(handle: Long, prompt: String): Int
    private external fun nativeAppendContext(handle: Long, text: String): Int
    private external fun nativeGenerateFromContext(handle: Long, query: String): Int
    private external fun nativeClearContext(handle: Long): Int
    private external fun nativeDestroy(handle: Long)
}

enum class ModelFormat(val raw: Int) {
    UNKNOWN(0),
    GGUF(1),
    ONNX(2),
    COREML(3),
    MLX_SAFETENSORS(4),
    EXECUTORCH_PTE(5),
    WHISPERKIT(6),
    OPENVINO_IR(7),
}
