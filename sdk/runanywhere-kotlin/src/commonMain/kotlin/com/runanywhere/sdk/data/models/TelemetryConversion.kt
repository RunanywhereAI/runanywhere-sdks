package com.runanywhere.sdk.data.models

/**
 * Telemetry data conversion utilities
 * Converts between TelemetryData (flexible properties dict) and TelemetryEventPayload (typed fields)
 * Matches iOS extension TelemetryEventPayload(from: TelemetryData)
 */

/**
 * Convert TelemetryData (with properties dict) to TelemetryEventPayload (typed) for API
 * Matches iOS extension TelemetryEventPayload(from: TelemetryData)
 */
fun TelemetryData.toPayload(): TelemetryEventPayload =
    TelemetryEventPayload(
        id = id,
        eventType = type.name.lowercase(), // Convert to lowercase to match iOS and backend expectations
        timestamp = timestamp,
        createdAt = timestamp, // Use timestamp as created_at
        // Session
        sessionId = properties["session_id"],
        // Model info
        modelId = properties["model_id"],
        modelName = properties["model_name"],
        framework = properties["framework"],
        modality = properties["modality"], // Extract modality from properties
        // Device info
        device = properties["device"],
        osVersion = properties["os_version"],
        platform = platform,
        sdkVersion = sdkVersion,
        // Common metrics
        processingTimeMs =
            properties["processing_time_ms"]?.toDoubleOrNull()
                ?: properties["total_time_ms"]?.toDoubleOrNull(),
        success = success,
        errorMessage = errorMessage,
        errorCode = errorCode,
        // LLM
        inputTokens =
            properties["input_tokens"]?.toIntOrNull()
                ?: properties["prompt_tokens"]?.toIntOrNull(),
        outputTokens = properties["output_tokens"]?.toIntOrNull(),
        totalTokens = properties["total_tokens"]?.toIntOrNull(),
        tokensPerSecond = properties["tokens_per_second"]?.toDoubleOrNull(),
        timeToFirstTokenMs = properties["time_to_first_token_ms"]?.toDoubleOrNull(),
        promptEvalTimeMs = properties["prompt_eval_time_ms"]?.toDoubleOrNull(),
        generationTimeMs = properties["generation_time_ms"]?.toDoubleOrNull(),
        contextLength = properties["context_length"]?.toIntOrNull(),
        temperature = properties["temperature"]?.toDoubleOrNull(),
        maxTokens = properties["max_tokens"]?.toIntOrNull(),
        // STT
        audioDurationMs = properties["audio_duration_ms"]?.toDoubleOrNull(),
        realTimeFactor = properties["real_time_factor"]?.toDoubleOrNull(),
        wordCount = properties["word_count"]?.toIntOrNull(),
        confidence = properties["confidence"]?.toDoubleOrNull(),
        language = properties["language"],
        isStreaming = properties["is_streaming"]?.toBooleanStrictOrNull(),
        segmentIndex = properties["segment_index"]?.toIntOrNull(),
        // TTS
        characterCount = properties["character_count"]?.toIntOrNull(),
        charactersPerSecond = properties["characters_per_second"]?.toDoubleOrNull(),
        audioSizeBytes = properties["audio_size_bytes"]?.toIntOrNull(),
        sampleRate = properties["sample_rate"]?.toIntOrNull(),
        voice = properties["voice"],
        outputDurationMs =
            properties["output_duration_ms"]?.toDoubleOrNull()
                ?: properties["audio_duration_ms"]?.toDoubleOrNull(),
    )
