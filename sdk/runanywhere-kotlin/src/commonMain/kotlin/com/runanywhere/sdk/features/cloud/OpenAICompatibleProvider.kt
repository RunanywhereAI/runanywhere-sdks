/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Built-in cloud provider for OpenAI-compatible APIs.
 * Works with OpenAI, Groq, Together, Ollama, vLLM, etc.
 *
 * Mirrors Swift OpenAICompatibleProvider.swift exactly.
 */

package com.runanywhere.sdk.features.cloud

import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.public.extensions.Cloud.ChatMessage
import com.runanywhere.sdk.public.extensions.Cloud.CloudGenerationOptions
import com.runanywhere.sdk.public.extensions.Cloud.CloudGenerationResult
import com.runanywhere.sdk.public.extensions.Cloud.CloudProvider
import io.ktor.client.HttpClient
import io.ktor.client.call.body
import io.ktor.client.plugins.contentnegotiation.ContentNegotiation
import io.ktor.client.plugins.logging.LogLevel
import io.ktor.client.plugins.logging.Logging
import io.ktor.client.request.get
import io.ktor.client.request.headers
import io.ktor.client.request.post
import io.ktor.client.request.setBody
import io.ktor.client.statement.bodyAsChannel
import io.ktor.http.ContentType
import io.ktor.http.HttpHeaders
import io.ktor.http.contentType
import io.ktor.http.isSuccess
import io.ktor.serialization.kotlinx.json.json
import io.ktor.utils.io.readUTF8Line
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.isActive
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

// MARK: - Cloud Provider Errors

/**
 * Errors from cloud provider operations.
 * Mirrors Swift CloudProviderError exactly.
 */
sealed class CloudProviderError(message: String, cause: Throwable? = null) : Exception(message, cause) {
    class InvalidURL : CloudProviderError("Invalid cloud provider URL")
    class HttpError(val statusCode: Int) : CloudProviderError("Cloud API returned HTTP $statusCode")
    class NoProviderRegistered : CloudProviderError("No cloud provider registered")
    class ProviderNotFound(val id: String) : CloudProviderError("Cloud provider not found: $id")
    class ProviderUnavailable(val id: String) : CloudProviderError("Cloud provider unavailable: $id")
    class DecodingError(val reason: String) : CloudProviderError("Failed to decode cloud response: $reason")
    class BudgetExceeded(val currentUSD: Double, val capUSD: Double) :
        CloudProviderError("Cloud budget exceeded: ${"%.4f".format(currentUSD)} / ${"%.4f".format(capUSD)} cap")
    class LatencyTimeout(val maxMs: Long, val actualMs: Double) :
        CloudProviderError("On-device latency timeout: ${"%.0f".format(actualMs)}ms exceeded ${maxMs}ms limit")
}

// MARK: - OpenAI Compatible Provider

/**
 * Cloud provider for any OpenAI-compatible chat completions API.
 *
 * Supports both streaming (SSE) and non-streaming responses.
 *
 * ```kotlin
 * // OpenAI
 * val openai = OpenAICompatibleProvider(apiKey = "sk-...", model = "gpt-4o-mini")
 *
 * // Groq
 * val groq = OpenAICompatibleProvider(
 *     apiKey = "gsk_...",
 *     model = "llama-3.1-8b-instant",
 *     baseURL = "https://api.groq.com/openai/v1"
 * )
 *
 * // Local Ollama
 * val ollama = OpenAICompatibleProvider(
 *     model = "llama3.2",
 *     baseURL = "http://localhost:11434/v1"
 * )
 * ```
 *
 * Mirrors Swift OpenAICompatibleProvider exactly.
 */
class OpenAICompatibleProvider(
    override val providerId: String,
    override val displayName: String,
    private val apiKey: String? = null,
    private val model: String,
    private val baseURL: String = DEFAULT_BASE_URL,
    private val additionalHeaders: Map<String, String> = emptyMap(),
) : CloudProvider {

    private val logger = SDKLogger("CloudProvider")

    private val json = Json {
        ignoreUnknownKeys = true
        isLenient = true
        encodeDefaults = true
    }

    private val httpClient = HttpClient {
        install(ContentNegotiation) {
            json(this@OpenAICompatibleProvider.json)
        }
        install(Logging) {
            level = LogLevel.NONE
        }
    }

    /**
     * Convenience constructor with auto-generated provider ID and display name.
     */
    constructor(
        apiKey: String? = null,
        model: String,
        baseURL: String = DEFAULT_BASE_URL,
        additionalHeaders: Map<String, String> = emptyMap(),
    ) : this(
        providerId = "openai-compat-${extractHost(baseURL)}",
        displayName = "OpenAI Compatible (${extractHost(baseURL)})",
        apiKey = apiKey,
        model = model,
        baseURL = baseURL,
        additionalHeaders = additionalHeaders,
    )

    // MARK: - CloudProvider Implementation

    override suspend fun generate(
        prompt: String,
        options: CloudGenerationOptions,
    ): CloudGenerationResult {
        val startTime = System.currentTimeMillis()

        val messages = buildMessages(prompt, options)
        val requestBody = buildRequestBody(messages, options, stream = false)

        val response = httpClient.post("$baseURL/chat/completions") {
            contentType(ContentType.Application.Json)
            applyHeaders()
            setBody(requestBody)
        }

        if (!response.status.isSuccess()) {
            throw CloudProviderError.HttpError(response.status.value)
        }

        val responseBody: ChatCompletionResponse = response.body()
        val latencyMs = (System.currentTimeMillis() - startTime).toDouble()
        val text = responseBody.choices.firstOrNull()?.message?.content ?: ""

        return CloudGenerationResult(
            text = text,
            inputTokens = responseBody.usage?.promptTokens ?: 0,
            outputTokens = responseBody.usage?.completionTokens ?: 0,
            latencyMs = latencyMs,
            providerId = providerId,
            model = options.model,
            estimatedCostUSD = null,
        )
    }

    override fun generateStream(
        prompt: String,
        options: CloudGenerationOptions,
    ): Flow<String> = flow {
        val messages = buildMessages(prompt, options)
        val requestBody = buildRequestBody(messages, options, stream = true)

        val response = httpClient.post("$baseURL/chat/completions") {
            contentType(ContentType.Application.Json)
            applyHeaders()
            setBody(requestBody)
        }

        if (!response.status.isSuccess()) {
            throw CloudProviderError.HttpError(response.status.value)
        }

        // Parse SSE stream
        val channel = response.bodyAsChannel()
        while (currentCoroutineContext().isActive && !channel.isClosedForRead) {
            val line = channel.readUTF8Line() ?: break

            if (line.startsWith("data: ")) {
                val data = line.removePrefix("data: ").trim()
                if (data == "[DONE]") break

                try {
                    val chunk = json.decodeFromString<ChatCompletionChunk>(data)
                    val content = chunk.choices.firstOrNull()?.delta?.content
                    if (content != null) {
                        emit(content)
                    }
                } catch (_: Exception) {
                    // Skip malformed chunks
                }
            }
        }
    }

    override suspend fun isAvailable(): Boolean {
        return try {
            val response = httpClient.get("$baseURL/models") {
                applyHeaders()
            }
            response.status.isSuccess()
        } catch (_: Exception) {
            false
        }
    }

    // MARK: - Internal Helpers

    private fun buildMessages(
        prompt: String,
        options: CloudGenerationOptions,
    ): List<ChatMessage> {
        if (options.messages != null) {
            return options.messages
        }

        val msgs = mutableListOf<ChatMessage>()
        if (options.systemPrompt != null) {
            msgs.add(ChatMessage(role = "system", content = options.systemPrompt))
        }
        msgs.add(ChatMessage(role = "user", content = prompt))
        return msgs
    }

    private fun buildRequestBody(
        messages: List<ChatMessage>,
        options: CloudGenerationOptions,
        stream: Boolean,
    ): ChatCompletionRequest {
        return ChatCompletionRequest(
            model = options.model,
            messages = messages.map { RequestMessage(role = it.role, content = it.content) },
            maxTokens = options.maxTokens,
            temperature = options.temperature,
            stream = stream,
        )
    }

    private fun io.ktor.client.request.HttpRequestBuilder.applyHeaders() {
        if (apiKey != null) {
            headers {
                append(HttpHeaders.Authorization, "Bearer $apiKey")
            }
        }
        for ((key, value) in additionalHeaders) {
            headers {
                append(key, value)
            }
        }
    }

    companion object {
        const val DEFAULT_BASE_URL = "https://api.openai.com/v1"

        private fun extractHost(url: String): String {
            return try {
                url.removePrefix("https://").removePrefix("http://").split("/").first()
            } catch (_: Exception) {
                "local"
            }
        }
    }
}

// MARK: - OpenAI API Request/Response Types

@Serializable
internal data class ChatCompletionRequest(
    val model: String,
    val messages: List<RequestMessage>,
    @SerialName("max_tokens") val maxTokens: Int,
    val temperature: Float,
    val stream: Boolean,
)

@Serializable
internal data class RequestMessage(
    val role: String,
    val content: String,
)

@Serializable
internal data class ChatCompletionResponse(
    val choices: List<ResponseChoice>,
    val usage: ResponseUsage? = null,
)

@Serializable
internal data class ResponseChoice(
    val message: ResponseMessage,
)

@Serializable
internal data class ResponseMessage(
    val content: String? = null,
)

@Serializable
internal data class ResponseUsage(
    @SerialName("prompt_tokens") val promptTokens: Int = 0,
    @SerialName("completion_tokens") val completionTokens: Int = 0,
)

@Serializable
internal data class ChatCompletionChunk(
    val choices: List<ChunkChoice>,
)

@Serializable
internal data class ChunkChoice(
    val delta: ChunkDelta,
)

@Serializable
internal data class ChunkDelta(
    val content: String? = null,
)
