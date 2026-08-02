/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Public v3 surface: `RunAnywhere.llm`.
 */

package com.runanywhere.sdk.public.api

import ai.runanywhere.proto.v1.LLMGenerateRequest
import ai.runanywhere.proto.v1.LLMStreamEvent
import ai.runanywhere.proto.v1.StructuredOutputParseRequest
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeLLM
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeStructuredOutput
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.LLM.ToolCallingOrchestrator
import com.runanywhere.sdk.public.extensions.NativeUnaryRequestCoordinator
import com.runanywhere.sdk.public.extensions.losslessLLMStreamFlow
import com.runanywhere.sdk.public.extensions.runCancellableNativeUnaryRequest
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import java.util.UUID
import ai.runanywhere.proto.v1.TokenKind as ProtoTokenKind

/** Registry of tools the model may call during generation. */
public class ToolsNamespace internal constructor() {
    /**
     * Make [tool] callable, running [executor] whenever the model asks for it.
     *
     * @throws SDKException when a tool with the same name is already registered.
     */
    public suspend fun register(
        tool: ToolDefinition,
        executor: suspend (Map<String, ToolValue>) -> Map<String, ToolValue>,
    ) {
        ToolCallingOrchestrator.registerTool(tool, executor)
    }

    /** Stop offering the tool called [name]. */
    public suspend fun unregister(name: String) {
        ToolCallingOrchestrator.unregisterTool(name)
    }

    /** Every currently registered tool. */
    public suspend fun list(): List<ToolDefinition> = ToolCallingOrchestrator.getRegisteredTools()
}

/**
 * Text generation.
 *
 * ```kotlin
 * val reply = RunAnywhere.llm.generate("Summarise this release", LlmOptions(model = "qwen3-0.6b"))
 * println(reply.text)
 * ```
 */
public class LlmNamespace internal constructor() {
    /** Tools this namespace may call while generating. */
    public val tools: ToolsNamespace = ToolsNamespace()

    /**
     * The blocking one-shot JNI call keeps decoding after its coroutine is
     * cancelled, so route it through the request coordinator: cancellation
     * dispatches the native cancel before the worker is joined.
     */
    private val unaryRequests = NativeUnaryRequestCoordinator()

    /**
     * Generate a completion for [prompt].
     *
     * @throws SDKException when no language model can be loaded.
     */
    public suspend fun generate(prompt: String, options: LlmOptions? = null): GenerationResult {
        val opts = options.orDefault()
        val model = prepareGeneration(opts, ModelCategory.MODEL_CATEGORY_LANGUAGE)
        if (opts.usesTools() && opts.activeTools().isNotEmpty()) {
            return generateWithTools(prompt, opts, emptyList(), model)
        }
        return generateUnary(opts.toRequest(prompt, newRequestId(), emptyList()))
    }

    /**
     * Generate the next assistant turn for [messages].
     *
     * @throws SDKException when no language model can be loaded.
     */
    public suspend fun generate(
        messages: List<ChatMessage>,
        options: LlmOptions? = null,
    ): GenerationResult {
        val opts = options.orDefault()
        val model = prepareGeneration(opts, ModelCategory.MODEL_CATEGORY_LANGUAGE)
        val prompt = messages.lastPrompt()
        val history = messages.dropLast(1)
        if (opts.usesTools() && opts.activeTools().isNotEmpty()) {
            return generateWithTools(prompt, opts, history, model)
        }
        return generateUnary(opts.toRequest(prompt, newRequestId(), history))
    }

    /**
     * Stream a completion for [prompt].
     *
     * @throws SDKException when no language model can be loaded.
     */
    public fun generateStream(prompt: String, options: LlmOptions? = null): Flow<GenerationEvent> =
        streamEvents(prompt, emptyList(), options.orDefault())

    /**
     * Stream the next assistant turn for [messages].
     *
     * @throws SDKException when no language model can be loaded.
     */
    public fun generateStream(
        messages: List<ChatMessage>,
        options: LlmOptions? = null,
    ): Flow<GenerationEvent> =
        streamEvents(messages.lastPrompt(), messages.dropLast(1), options.orDefault())

    /**
     * Generate a completion constrained to [schema] and parse it.
     *
     * @throws SDKException when no language model can be loaded.
     */
    public suspend fun generateStructured(
        prompt: String,
        schema: JsonSchema,
        options: LlmOptions? = null,
    ): StructuredResult {
        val opts =
            options.orDefault().copy(
                structuredOutput = options?.structuredOutput ?: StructuredOutput(schema = schema),
            )
        val generation = generate(prompt, opts)
        val parsed =
            withContext(Dispatchers.IO) {
                CppBridgeStructuredOutput.parse(
                    StructuredOutputParseRequest(
                        request_id = generation.requestId,
                        text = generation.text,
                        options = StructuredOutput(schema = schema, strict = opts.strictStructuredOutput()).toProto(),
                    ),
                )
            }
        return StructuredResult(
            value = parsed.parsed_json.utf8(),
            raw = parsed.raw_text ?: generation.text,
            valid = parsed.validation?.is_valid == true,
            inputTokens = generation.inputTokens,
            outputTokens = generation.outputTokens,
            timeToFirstTokenMs = generation.timeToFirstTokenMs,
            tokensPerSecond = generation.tokensPerSecond,
            requestId = generation.requestId,
            model = generation.model,
        )
    }

    /**
     * Cancellation of the calling coroutine dispatches the native LLM cancel
     * before the blocking JNI worker is joined, so a stopped stream stops
     * decoding instead of finishing in the background.
     */
    private suspend fun generateUnary(request: LLMGenerateRequest): GenerationResult =
        runCancellableNativeUnaryRequest(
            coordinator = unaryRequests,
            request = { runBlocking { CppBridgeLLM.generate(request) } },
            cancel = { runBlocking { CppBridgeLLM.cancelProto() } },
        ).toGenerationResult(request.request_id)

    private fun streamEvents(
        prompt: String,
        history: List<ChatMessage>,
        opts: LlmOptions,
    ): Flow<GenerationEvent> =
        flow {
            val model = prepareGeneration(opts, ModelCategory.MODEL_CATEGORY_LANGUAGE)
            val requestId = newRequestId()
            val request = opts.toRequest(prompt, requestId, history)
            val answer = StringBuilder()
            val thinking = StringBuilder()
            var startedEmitted = false

            losslessLLMStreamFlow(
                prepare = { RunAnywhere.ensureServicesReady() },
                generate = { onEvent -> CppBridgeLLM.generateStream(request, onEvent) },
                cancel = { CppBridgeLLM.cancelProto() },
            ).collect { raw ->
                if (!startedEmitted) {
                    startedEmitted = true
                    emit(GenerationEvent.Started(requestId))
                }
                raw.failureOrNull()?.let { throw it }
                raw.tokenEventOrNull(answer, thinking)?.let { emit(it) }
                raw.tool_call?.let { emit(GenerationEvent.ToolCallRequested(it)) }
                if (raw.is_final) {
                    emit(
                        GenerationEvent.Completed(
                            raw.result?.toGenerationResult(
                                requestId = requestId,
                                model = model,
                                fallbackText = answer.toString(),
                                fallbackThinking = thinking.toString().takeIf { it.isNotEmpty() },
                            ) ?: GenerationResult(
                                text = answer.toString(),
                                thinkingText = thinking.toString().takeIf { it.isNotEmpty() },
                                finishReason = finishReasonOf(raw.finish_reason),
                                requestId = requestId,
                                model = model,
                            ),
                        ),
                    )
                }
            }
        }

    private suspend fun generateWithTools(
        prompt: String,
        opts: LlmOptions,
        history: List<ChatMessage>,
        model: String,
    ): GenerationResult {
        val result =
            ToolCallingOrchestrator.generateWithTools(
                prompt = prompt,
                options = opts.toolCallingProtoForOrchestrator(),
                llmOptions = opts.toProto(),
                validateCalls = null,
                history = history.toAlternatingTurns(),
            )
        result.error_message?.let { throw SDKException.operation(it) }
        return GenerationResult(
            text = result.text,
            thinkingText = result.thinking_content?.takeIf { it.isNotEmpty() },
            toolCalls = result.tool_calls,
            toolResults = result.tool_results,
            finishReason =
                if (result.tool_calls.isNotEmpty() && !result.is_complete) {
                    FinishReason.TOOL_CALLS
                } else {
                    FinishReason.STOP
                },
            requestId = result.conversation_id.orEmpty(),
            model = model,
        )
    }
}

private fun newRequestId(): String = UUID.randomUUID().toString()

private fun LlmOptions.usesTools(): Boolean = toolChoice != ToolChoice.None

/**
 * Tools the run loop will offer, using the same rule the orchestrator applies:
 * the explicit list when the caller gave one, otherwise the registry. Reading
 * only the registry here would skip the loop for inline tools.
 */
private suspend fun LlmOptions.activeTools(): List<ToolDefinition> =
    tools.ifEmpty { ToolCallingOrchestrator.getRegisteredTools() }

private fun LlmOptions.strictStructuredOutput(): Boolean = structuredOutput?.strict ?: true

private fun LlmOptions.toRequest(
    prompt: String,
    requestId: String,
    history: List<ChatMessage>,
): LLMGenerateRequest =
    LLMGenerateRequest(
        prompt = prompt,
        request_id = requestId,
        model_id = model.orEmpty(),
        options = toProto(),
        history = history.map { it.toProto() },
    )

private fun LlmOptions.toolCallingProtoForOrchestrator(): ai.runanywhere.proto.v1.ToolCallingOptions =
    ai.runanywhere.proto.v1.ToolCallingOptions(
        tools = tools,
        max_tool_calls = maxToolCalls,
        tool_choice = toolChoice.toProto(),
        forced_tool_name = (toolChoice as? ToolChoice.Forced)?.name,
        auto_execute = true,
    )

private fun List<ChatMessage>.lastPrompt(): String =
    lastOrNull()?.content ?: throw SDKException.invalidArgument("messages must not be empty")

/**
 * Flatten a transcript into the commons tool-calling history contract: a flat
 * alternating `[user0, assistant0, user1, ...]` list of completed turns.
 *
 * The tool-calling proto carries history as plain strings, so roles are implied
 * by position. Blank turns, a leading assistant turn, and a dangling trailing
 * user turn are dropped, and consecutive same-role turns are merged, so a
 * skipped reply cannot shift every later turn onto the wrong role.
 */
private fun List<ChatMessage>.toAlternatingTurns(): List<String> {
    val turns = mutableListOf<String>()
    var lastRole: ChatRole? = null
    for (message in this) {
        if (message.role != ChatRole.USER && message.role != ChatRole.ASSISTANT) continue
        if (message.content.isEmpty()) continue
        if (turns.isEmpty() && message.role != ChatRole.USER) continue
        if (message.role == lastRole) {
            turns[turns.lastIndex] = turns[turns.lastIndex] + "\n\n" + message.content
        } else {
            turns.add(message.content)
            lastRole = message.role
        }
    }
    if (lastRole == ChatRole.USER && turns.isNotEmpty()) {
        turns.removeAt(turns.lastIndex)
    }
    return turns
}

private fun LLMStreamEvent.failureOrNull(): SDKException? {
    val err = error ?: return null
    return SDKException(err)
}

private fun LLMStreamEvent.tokenEventOrNull(
    answer: StringBuilder,
    thinking: StringBuilder,
): GenerationEvent? {
    if (token.isEmpty()) return null
    return when (kind) {
        ProtoTokenKind.TOKEN_KIND_THOUGHT -> {
            thinking.append(token)
            GenerationEvent.Token(token, TokenKind.THOUGHT)
        }
        ProtoTokenKind.TOKEN_KIND_TOOL_CALL -> null
        else -> {
            answer.append(token)
            GenerationEvent.Token(token, TokenKind.TEXT)
        }
    }
}
