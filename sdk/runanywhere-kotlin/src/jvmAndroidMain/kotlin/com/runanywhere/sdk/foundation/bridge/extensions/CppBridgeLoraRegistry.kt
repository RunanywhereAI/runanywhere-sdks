/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * LoRA Registry bridge wrapper.
 * Thin wrapper around JNI calls to C++ LoRA registry.
 */

package com.runanywhere.sdk.foundation.bridge.extensions

import com.runanywhere.sdk.native.bridge.RunAnywhereBridge
import org.json.JSONArray
import org.json.JSONObject

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

    // JSON Parsing — uses org.json for correctness with special characters

    private fun parseLoraEntryJson(obj: JSONObject): LoraEntry? {
        return try {
            val id = obj.optString("id", "").takeIf { it.isNotEmpty() } ?: return null
            val modelIds = mutableListOf<String>()
            obj.optJSONArray("compatible_model_ids")?.let { arr ->
                for (i in 0 until arr.length()) {
                    arr.optString(i)?.takeIf { it.isNotEmpty() }?.let { modelIds.add(it) }
                }
            }
            LoraEntry(
                id = id,
                name = obj.optString("name", ""),
                description = obj.optString("description", ""),
                downloadUrl = obj.optString("download_url", ""),
                filename = obj.optString("filename", ""),
                compatibleModelIds = modelIds,
                fileSize = obj.optLong("file_size", 0L),
                defaultScale = obj.optDouble("default_scale", 0.0).toFloat(),
            )
        } catch (e: Exception) {
            log(LogLevel.ERROR, "Failed to parse LoRA entry JSON: ${e.message}")
            null
        }
    }

    private fun parseLoraEntryArrayJson(json: String): List<LoraEntry> {
        if (json.isBlank() || json == "[]") return emptyList()
        return try {
            val array = JSONArray(json)
            (0 until array.length()).mapNotNull { i ->
                parseLoraEntryJson(array.getJSONObject(i))
            }
        } catch (e: Exception) {
            log(LogLevel.ERROR, "Failed to parse LoRA entry array JSON: ${e.message}")
            emptyList()
        }
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
