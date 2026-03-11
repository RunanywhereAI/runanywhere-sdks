package com.runanywhere.runanywhereai.data.db

import com.runanywhere.runanywhereai.models.ChatMessage
import com.runanywhere.runanywhereai.models.Conversation
import com.runanywhere.runanywhereai.models.MessageAnalytics
import com.runanywhere.runanywhereai.models.MessageModelInfo
import com.runanywhere.runanywhereai.models.MessageRole

/** Map a [ConversationEntity] + its messages back to the domain [Conversation]. */
fun ConversationEntity.toDomain(messages: List<ChatMessage> = emptyList()): Conversation =
    Conversation(
        id = id,
        title = title,
        messages = messages,
        createdAt = createdAt,
        updatedAt = updatedAt,
        modelName = modelName,
    )

/** Map a domain [Conversation] to its Room entity (without messages). */
fun Conversation.toEntity(): ConversationEntity =
    ConversationEntity(
        id = id,
        title = title,
        modelName = modelName,
        createdAt = createdAt,
        updatedAt = updatedAt,
        messageCount = messages.size,
    )

/** Map a [MessageEntity] back to the domain [ChatMessage]. */
fun MessageEntity.toDomain(): ChatMessage =
    ChatMessage(
        id = id,
        role = runCatching { MessageRole.valueOf(role) }.getOrDefault(MessageRole.USER),
        content = content,
        thinkingContent = thinkingContent,
        timestamp = timestamp,
        analytics = if (tokensPerSecond != null || totalGenerationTime != null) {
            MessageAnalytics(
                inputTokens = inputTokens ?: 0,
                outputTokens = outputTokens ?: 0,
                totalGenerationTime = totalGenerationTime ?: 0,
                timeToFirstToken = timeToFirstToken,
                averageTokensPerSecond = tokensPerSecond ?: 0.0,
            )
        } else {
            null
        },
        modelInfo = if (modelId != null && modelName != null) {
            MessageModelInfo(
                modelId = modelId,
                modelName = modelName,
                framework = modelFramework,
            )
        } else {
            null
        },
    )

/** Map a domain [ChatMessage] to its Room entity for a given conversation. */
fun ChatMessage.toEntity(conversationId: String): MessageEntity =
    MessageEntity(
        id = id,
        conversationId = conversationId,
        role = role.name,
        content = content,
        thinkingContent = thinkingContent,
        timestamp = timestamp,
        tokensPerSecond = analytics?.averageTokensPerSecond,
        totalGenerationTime = analytics?.totalGenerationTime,
        timeToFirstToken = analytics?.timeToFirstToken,
        inputTokens = analytics?.inputTokens,
        outputTokens = analytics?.outputTokens,
        modelId = modelInfo?.modelId,
        modelName = modelInfo?.modelName,
        modelFramework = modelInfo?.framework,
        isError = false,
    )
