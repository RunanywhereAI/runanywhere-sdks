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
import kotlinx.coroutines.flow.emitAll
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
     * [mode] picks how the schema is enforced:
     * - [StructuredOutputMode.VALIDATION_ONLY] (default): generate freely, then validate.
     * - [StructuredOutputMode.REPAIR]: validate, then retry once with a repair instruction if invalid.
     * - [StructuredOutputMode.CONSTRAINED]: engine-constrained decoding — fails preflight
     *   until a constrained-decoding engine is wired in.
     *
     * @throws SDKException when no language model can be loaded, [mode] cannot
     *   be honored, or generation fails.
     */
    public suspend fun generateStructured(
        prompt: String,
        schema: JsonSchema,
        mode: StructuredOutputMode = StructuredOutputMode.VALIDATION_ONLY,
        options: LlmOptions? = null,
    ): StructuredResult {
        if (mode == StructuredOutputMode.CONSTRAINED) {
            throw SDKException.unsupportedCapability(
                "llm.generateStructured(mode = CONSTRAINED)",
                "needs engine-level constrained decoding, which is not wired in yet; use VALIDATION_ONLY or REPAIR",
            )
        }
        val opts = options.orDefault()
        val structuredOutput = StructuredOutput(schema = schema)
        var generation = generateStructuredUnary(prompt, opts, structuredOutput)
        var parsed = parseStructuredOutput(generation, schema, structuredOutput)

        if (mode == StructuredOutputMode.REPAIR && parsed.validation?.is_valid != true) {
            val repairPrompt = structuredRepairPrompt(prompt, generation.text, schema)
            generation = generateStructuredUnary(repairPrompt, opts, structuredOutput)
            parsed = parseStructuredOutput(generation, schema, structuredOutput)
        }

        return StructuredResult(
            value = parsed.parsed_json.utf8(),
            raw = parsed.raw_text ?: generation.text,
            valid = parsed.validation?.is_valid == true,
            mode = mode,
            inputTokens = generation.inputTokens,
            outputTokens = generation.outputTokens,
            timeToFirstTokenMs = generation.timeToFirstTokenMs,
            tokensPerSecond = generation.tokensPerSecond,
            requestId = generation.requestId,
            model = generation.model,
        )
    }

    /** Plain generation for `generateStructured` — bypasses the tool-calling loop entirely. */
    private suspend fun generateStructuredUnary(
        prompt: String,
        opts: LlmOptions,
        structuredOutput: StructuredOutput,
    ): GenerationResult {
        prepareGeneration(opts, ModelCategory.MODEL_CATEGORY_LANGUAGE)
        return generateUnary(opts.toRequest(prompt, newRequestId(), emptyList(), structuredOutput))
    }

    private suspend fun parseStructuredOutput(
        generation: GenerationResult,
        schema: JsonSchema,
        structuredOutput: StructuredOutput,
    ) = withContext(Dispatchers.IO) {
        CppBridgeStructuredOutput.parse(
            StructuredOutputParseRequest(
                request_id = generation.requestId,
                text = generation.text,
                options = structuredOutput.toProto(),
            ),
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
            val rawEvents =
                losslessLLMStreamFlow(
                    prepare = { RunAnywhere.ensureServicesReady() },
                    generate = { onEvent -> CppBridgeLLM.generateStream(request, onEvent) },
                    cancel = { CppBridgeLLM.cancelProto() },
                )
            emitAll(mapLLMStreamEvents(requestId, model, rawEvents))
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
            inputTokens = result.usage?.input_tokens ?: 0,
            outputTokens = result.usage?.output_tokens ?: 0,
            tokensPerSecond = result.usage?.tokens_per_second?.toFloat() ?: 0f,
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

/** The one retry prompt `generateStructured(mode = REPAIR)` sends when the first pass did not validate. */
private fun structuredRepairPrompt(original: String, invalidOutput: String, schema: JsonSchema): String =
    """
    $original

    Your previous answer did not match the required JSON schema. Reply again with ONLY JSON that satisfies this schema.

    Schema: ${schema.raw_json.orEmpty()}
    Previous invalid answer: $invalidOutput
    """.trimIndent()

private fun LlmOptions.usesTools(): Boolean = toolChoice != ToolChoice.None

/**
 * Tools the run loop will offer, using the same rule the orchestrator applies:
 * the explicit list when the caller gave one, otherwise the registry. Reading
 * only the registry here would skip the loop for inline tools.
 */
private suspend fun LlmOptions.activeTools(): List<ToolDefinition> =
    tools.ifEmpty { ToolCallingOrchestrator.getRegisteredTools() }

private fun LlmOptions.toRequest(
    prompt: String,
    requestId: String,
    history: List<ChatMessage>,
    structuredOutput: StructuredOutput? = null,
): LLMGenerateRequest =
    LLMGenerateRequest(
        prompt = prompt,
        request_id = requestId,
        model_id = model.orEmpty(),
        options = toProto(structuredOutput),
        history = history.map { it.toProto() },
    )

/** Not `private` so tests can pin the `autoExecute` forwarding contract. */
internal fun LlmOptions.toolCallingProtoForOrchestrator(): ai.runanywhere.proto.v1.ToolCallingOptions =
    ai.runanywhere.proto.v1.ToolCallingOptions(
        tools = tools,
        max_tool_calls = maxToolCalls,
        tool_choice = toolChoice.toProto(),
        forced_tool_name = (toolChoice as? ToolChoice.Forced)?.name,
        // Forwarded verbatim -- makeToolCallingRunLoopRequest reads this
        // straight onto ToolCallingSessionCreateRequest.auto_execute, so an
        // explicit caller `autoExecute = false` must survive this hop
        // instead of being hardcoded away.
        auto_execute = autoExecute,
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

/** Breaks the raw-event collect loop once a terminal event has been emitted. */
private class StreamTerminalReached : RuntimeException()

/**
 * Fold raw native LLM stream events onto the v4 `started` / `textDelta` /
 * `reasoningDelta` / `toolCallAdded` / `completed` grammar.
 *
 * Internal and injectable — [rawEvents] is any `Flow<LLMStreamEvent>`, not
 * tied to [CppBridgeLLM], so unit tests can characterize the native-boundary
 * contract without a JNI bridge.
 *
 * Never fabricates a successful `completed`: a stream that ends after
 * producing at least one event but without a terminal `is_final` emits
 * `failed` instead (mirrors Swift's `RunAnywhere.mapGenerationStream`). A
 * stream that produced zero events throws, since there is no partial
 * `requestId` to report a terminal event against.
 */
internal fun mapLLMStreamEvents(
    requestId: String,
    model: String,
    rawEvents: Flow<LLMStreamEvent>,
): Flow<GenerationEvent> =
    flow {
        val answer = StringBuilder()
        val thinking = StringBuilder()
        var startedEmitted = false
        var sawTerminal = false
        var sawAnyEvent = false
        var sequence = 0L
        var toolCallIndex = 0
        val textItemId = UUID.randomUUID().toString()
        val reasoningItemId = UUID.randomUUID().toString()

        fun partialOrNull(): String? = answer.toString().takeIf { it.isNotEmpty() }

        try {
            rawEvents.collect { raw ->
                sawAnyEvent = true
                if (!startedEmitted) {
                    startedEmitted = true
                    emit(GenerationEvent.Started(requestId))
                }
                raw.error?.let {
                    sawTerminal = true
                    emit(GenerationEvent.Failed(requestId, partialOrNull(), SDKException(it)))
                    throw StreamTerminalReached()
                }
                raw.tokenEventOrNull(requestId, answer, thinking, textItemId, reasoningItemId, sequence)?.let {
                    sequence += 1
                    emit(it)
                }
                raw.tool_call?.let { call ->
                    val itemId = call.id.takeIf { it.isNotEmpty() } ?: "tool-$toolCallIndex"
                    emit(GenerationEvent.ToolCallAdded(requestId, sequence++, itemId, toolCallIndex, call))
                    emit(GenerationEvent.ToolArgumentsDone(requestId, sequence++, itemId, call.arguments_json))
                    toolCallIndex += 1
                }
                if (raw.is_final) {
                    sawTerminal = true
                    emit(
                        GenerationEvent.Completed(
                            requestId,
                            raw.result?.toGenerationResult(
                                requestId = requestId,
                                model = model,
                                fallbackText = answer.toString(),
                                fallbackThinking = thinking.toString().takeIf { it.isNotEmpty() },
                            ) ?: GenerationResult(
                                text = answer.toString(),
                                thinkingText = thinking.toString().takeIf { it.isNotEmpty() },
                                finishReason = finishReasonOf(raw.finish_reason),
                                rawFinishReason = raw.finish_reason.takeIf { it.isNotEmpty() },
                                requestId = requestId,
                                model = model,
                            ),
                        ),
                    )
                    throw StreamTerminalReached()
                }
            }
        } catch (_: StreamTerminalReached) {
            // Terminal event already emitted above; stop consuming raw events.
        }

        if (!sawTerminal) {
            if (!sawAnyEvent) {
                throw SDKException.operation("Generation ended before producing any output")
            }
            emit(
                GenerationEvent.Failed(
                    requestId,
                    partialOrNull(),
                    SDKException.operation("Generation stream ended before a terminal event"),
                ),
            )
        }
    }

private fun LLMStreamEvent.tokenEventOrNull(
    requestId: String,
    answer: StringBuilder,
    thinking: StringBuilder,
    textItemId: String,
    reasoningItemId: String,
    sequence: Long,
): GenerationEvent? {
    if (token.isEmpty()) return null
    return when (kind) {
        ProtoTokenKind.TOKEN_KIND_THOUGHT -> {
            thinking.append(token)
            GenerationEvent.ReasoningDelta(requestId, sequence, reasoningItemId, 0, token)
        }
        ProtoTokenKind.TOKEN_KIND_TOOL_CALL -> null
        else -> {
            answer.append(token)
            GenerationEvent.TextDelta(requestId, sequence, textItemId, 0, token)
        }
    }
}
