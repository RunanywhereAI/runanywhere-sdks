/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * LoRA Registry bridge wrapper.
 * Thin wrapper around JNI calls to C++ LoRA registry.
 */

package com.runanywhere.sdk.foundation.bridge.extensions

import com.runanywhere.sdk.native.bridge.RunAnywhereBridge

object CppBridgeLoraRegistry {
    private const val TAG = "CppBridge/CppBridgeLoraRegistry"

    data class LoraEntry(
        val id: String,
        val name: String,
        val description: String,
        val downloadUrl: String,
        val filename: String,
        val compatibleModelIds: List<String>,
        val fileSize: Long,
        val defaultScale: Float,
    )

    fun register(entry: LoraEntry) {
        log(LogLevel.DEBUG, "Registering LoRA adapter: ${entry.id}")
        val result = RunAnywhereBridge.racLoraRegistryRegister(
            id = entry.id, name = entry.name, description = entry.description,
            downloadUrl = entry.downloadUrl, filename = entry.filename,
            compatibleModelIds = entry.compatibleModelIds.toTypedArray(),
            fileSize = entry.fileSize, defaultScale = entry.defaultScale,
        )
        if (result != RunAnywhereBridge.RAC_SUCCESS) {
            log(LogLevel.ERROR, "Failed to register LoRA adapter: ${entry.id}, error=$result")
            throw RuntimeException("Failed to register LoRA adapter: $result")
        }
        log(LogLevel.INFO, "LoRA adapter registered: ${entry.id}")
    }

    fun getForModel(modelId: String): List<LoraEntry> {
        val json = RunAnywhereBridge.racLoraRegistryGetForModel(modelId)
        return parseLoraEntryArrayJson(json)
    }

    fun getAll(): List<LoraEntry> {
        val json = RunAnywhereBridge.racLoraRegistryGetAll()
        return parseLoraEntryArrayJson(json)
    }

    // JSON Parsing

    private fun parseLoraEntryJson(json: String): LoraEntry? {
        if (json == "null" || json.isBlank()) return null
        return try {
            LoraEntry(
                id = extractString(json, "id") ?: return null,
                name = extractString(json, "name") ?: "",
                description = extractString(json, "description") ?: "",
                downloadUrl = extractString(json, "download_url") ?: "",
                filename = extractString(json, "filename") ?: "",
                compatibleModelIds = extractStringArray(json, "compatible_model_ids"),
                fileSize = extractLong(json, "file_size"),
                defaultScale = extractFloat(json, "default_scale"),
            )
        } catch (e: Exception) {
            log(LogLevel.ERROR, "Failed to parse LoRA entry JSON: ${e.message}")
            null
        }
    }

    private fun parseLoraEntryArrayJson(json: String): List<LoraEntry> {
        if (json == "[]" || json.isBlank()) return emptyList()
        val entries = mutableListOf<LoraEntry>()
        var depth = 0; var objectStart = -1
        for (i in json.indices) {
            when (json[i]) {
                '{' -> { if (depth == 0) objectStart = i; depth++ }
                '}' -> {
                    depth--
                    if (depth == 0 && objectStart >= 0) {
                        parseLoraEntryJson(json.substring(objectStart, i + 1))?.let { entries.add(it) }
                        objectStart = -1
                    }
                }
            }
        }
        return entries
    }

    private fun extractString(json: String, key: String): String? {
        val regex = Regex(""""$key"\s*:\s*"((?:[^"\\]|\\.)*)"""")
        return regex.find(json)?.groupValues?.get(1)?.takeIf { it.isNotEmpty() }
    }

    private fun extractLong(json: String, key: String): Long {
        val regex = Regex(""""$key"\s*:\s*(-?\d+)""")
        return regex.find(json)?.groupValues?.get(1)?.toLongOrNull() ?: 0L
    }

    private fun extractFloat(json: String, key: String): Float {
        val regex = Regex(""""$key"\s*:\s*(-?[\d.]+)""")
        return regex.find(json)?.groupValues?.get(1)?.toFloatOrNull() ?: 0f
    }

    private fun extractStringArray(json: String, key: String): List<String> {
        val keyMatch = Regex(""""$key"\s*:\s*\[""").find(json) ?: return emptyList()
        val arrayStart = keyMatch.range.last + 1
        var depth = 1; var pos = arrayStart
        while (pos < json.length && depth > 0) {
            when (json[pos]) { '[' -> depth++; ']' -> depth-- }; pos++
        }
        if (depth != 0) return emptyList()
        val arrayContent = json.substring(arrayStart, pos - 1).trim()
        if (arrayContent.isEmpty()) return emptyList()
        return Regex(""""((?:[^"\\]|\\.)*)"""").findAll(arrayContent).map { it.groupValues[1] }.toList()
    }

    private enum class LogLevel { DEBUG, INFO, WARN, ERROR }
    private fun log(level: LogLevel, message: String) {
        val adapterLevel = when (level) {
            LogLevel.DEBUG -> CppBridgePlatformAdapter.LogLevel.DEBUG
            LogLevel.INFO -> CppBridgePlatformAdapter.LogLevel.INFO
            LogLevel.WARN -> CppBridgePlatformAdapter.LogLevel.WARN
            LogLevel.ERROR -> CppBridgePlatformAdapter.LogLevel.ERROR
        }
        CppBridgePlatformAdapter.logCallback(adapterLevel, TAG, message)
    }
}
