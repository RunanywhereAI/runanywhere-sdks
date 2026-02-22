/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * JVM/Android actual implementations for LoRA adapter management.
 */

package com.runanywhere.sdk.public.extensions

import com.runanywhere.sdk.foundation.SDKLogger
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeLLM
import com.runanywhere.sdk.foundation.errors.SDKError
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.LLM.LoRAAdapterConfig
import com.runanywhere.sdk.public.extensions.LLM.LoRAAdapterInfo
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.float
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

private val loraLogger = SDKLogger("LoRA")

private val loraJson = Json { ignoreUnknownKeys = true }

actual suspend fun RunAnywhere.loadLoraAdapter(config: LoRAAdapterConfig) {
    if (!isInitialized) {
        throw SDKError.notInitialized("SDK not initialized")
    }

    loraLogger.info("Loading LoRA adapter: ${config.path} (scale=${config.scale})")

    val result = CppBridgeLLM.loadLoraAdapter(config.path, config.scale)
    if (result != 0) {
        throw SDKError.llm("Failed to load LoRA adapter: error $result")
    }
}

actual suspend fun RunAnywhere.removeLoraAdapter(path: String) {
    if (!isInitialized) {
        throw SDKError.notInitialized("SDK not initialized")
    }

    val result = CppBridgeLLM.removeLoraAdapter(path)
    if (result != 0) {
        throw SDKError.llm("Failed to remove LoRA adapter: error $result")
    }
}

actual suspend fun RunAnywhere.clearLoraAdapters() {
    if (!isInitialized) {
        throw SDKError.notInitialized("SDK not initialized")
    }

    val result = CppBridgeLLM.clearLoraAdapters()
    if (result != 0) {
        throw SDKError.llm("Failed to clear LoRA adapters: error $result")
    }
}

actual suspend fun RunAnywhere.getLoadedLoraAdapters(): List<LoRAAdapterInfo> {
    if (!isInitialized) {
        throw SDKError.notInitialized("SDK not initialized")
    }

    val jsonStr = CppBridgeLLM.getLoraInfo() ?: return emptyList()

    return try {
        val jsonArray = loraJson.parseToJsonElement(jsonStr) as? JsonArray ?: return emptyList()
        jsonArray.map { element ->
            val obj = element.jsonObject
            LoRAAdapterInfo(
                path = obj["path"]?.jsonPrimitive?.content ?: "",
                scale = obj["scale"]?.jsonPrimitive?.float ?: 1.0f,
                applied = obj["applied"]?.jsonPrimitive?.boolean ?: false,
            )
        }
    } catch (e: Exception) {
        loraLogger.error("Failed to parse LoRA info JSON: ${e.message}")
        emptyList()
    }
}

actual fun RunAnywhere.checkLoraCompatibility(loraPath: String): LoraCompatibilityResult {
    if (!isInitialized) {
        return LoraCompatibilityResult(isCompatible = false, error = "SDK not initialized")
    }

    val error = CppBridgeLLM.checkLoraCompatibility(loraPath)
    return if (error == null) {
        LoraCompatibilityResult(isCompatible = true)
    } else {
        LoraCompatibilityResult(isCompatible = false, error = error)
    }
}
