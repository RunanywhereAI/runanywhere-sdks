package com.runanywhere.sdk.generation

import com.runanywhere.sdk.models.Generatable
import com.runanywhere.sdk.models.StructuredOutputConfig
import com.runanywhere.sdk.data.models.SDKError
import kotlinx.serialization.json.*
import kotlin.reflect.KClass

/**
 * Handler for structured output generation that matches iOS StructuredOutputHandler
 * Simple pattern: enhance options → call generate() → parse result
 */
class StructuredOutputHandler {
    
    /**
     * Get system prompt for a Generatable type - matches iOS getSystemPrompt()
     */
    fun <T : Generatable> getSystemPrompt(type: KClass<T>): String {
        val schema = Generatable.getJsonSchema(type)
        val typeName = type.simpleName ?: "Response"
        
        return """
You are a JSON generation assistant. Your task is to generate valid JSON that exactly matches the provided schema.

SCHEMA for $typeName:
$schema

INSTRUCTIONS:
1. Generate ONLY valid JSON that conforms to the schema
2. Do not include any explanation, commentary, or additional text
3. Ensure all required fields are present
4. Use appropriate data types as specified in the schema
5. Do not add fields not defined in the schema

Your response must be valid JSON only.
        """.trimIndent()
    }
    
    /**
     * Build user prompt for structured output - matches iOS buildUserPrompt()
     */
    fun <T : Generatable> buildUserPrompt(type: KClass<T>, content: String): String {
        val typeName = type.simpleName ?: "Response"
        
        return """
$content

Generate a $typeName object as JSON based on the above content.
        """.trimIndent()
    }
    
    /**
     * Parse structured output from generated text - matches iOS parseStructuredOutput()
     */
    fun <T : Generatable> parseStructuredOutput(
        generatedText: String,
        type: KClass<T>
    ): T {
        // Extract JSON from the response
        val jsonText = extractJsonFromResponse(generatedText)
        
        // Validate JSON structure
        val jsonElement = try {
            Json.parseToJsonElement(jsonText)
        } catch (e: Exception) {
            throw SDKError.StructuredOutputGenerationFailed("Invalid JSON in response: ${e.message}")
        }
        
        if (jsonElement !is JsonObject) {
            throw SDKError.StructuredOutputGenerationFailed("Response is not a JSON object")
        }
        
        // Basic validation against expected structure
        validateJsonStructure(jsonElement, type)
        
        // Parse to target type
        return parseJsonToType(jsonElement, type)
    }
    
    /**
     * Extract JSON from potentially mixed response text
     */
    private fun extractJsonFromResponse(text: String): String {
        val trimmed = text.trim()
        
        // If it's already clean JSON, return it
        if (trimmed.startsWith("{") && trimmed.endsWith("}")) {
            return trimmed
        }
        
        // Find JSON block within text
        val jsonStart = trimmed.indexOf("{")
        val jsonEnd = trimmed.lastIndexOf("}") + 1
        
        if (jsonStart == -1 || jsonEnd <= jsonStart) {
            throw SDKError.StructuredOutputGenerationFailed("No JSON object found in response")
        }
        
        return trimmed.substring(jsonStart, jsonEnd)
    }
    
    /**
     * Validate JSON structure matches expected type
     */
    private fun <T : Generatable> validateJsonStructure(json: JsonObject, type: KClass<T>) {
        val typeName = type.simpleName?.lowercase() ?: "unknown"
        
        when (typeName) {
            "personinfo" -> {
                if (!json.containsKey("name")) {
                    throw SDKError.StructuredOutputGenerationFailed("PersonInfo must have 'name' field")
                }
            }
            "codesnippet" -> {
                if (!json.containsKey("language") || !json.containsKey("code")) {
                    throw SDKError.StructuredOutputGenerationFailed("CodeSnippet must have 'language' and 'code' fields")
                }
            }
            "analysisresult" -> {
                if (!json.containsKey("summary") || !json.containsKey("findings")) {
                    throw SDKError.StructuredOutputGenerationFailed("AnalysisResult must have 'summary' and 'findings' fields")
                }
            }
            "tasklist" -> {
                if (!json.containsKey("title") || !json.containsKey("tasks")) {
                    throw SDKError.StructuredOutputGenerationFailed("TaskList must have 'title' and 'tasks' fields")
                }
            }
            "jsonresponse" -> {
                if (!json.containsKey("success")) {
                    throw SDKError.StructuredOutputGenerationFailed("JsonResponse must have 'success' field")
                }
            }
        }
    }
    
    /**
     * Parse JSON to target type - simplified implementation
     */
    private fun <T : Generatable> parseJsonToType(json: JsonObject, type: KClass<T>): T {
        val typeName = type.simpleName ?: "Unknown"
        
        // Create instances based on type name
        // In a full implementation, this would use proper serialization
        @Suppress("UNCHECKED_CAST")
        return when (typeName) {
            "PersonInfo" -> {
                val name = json["name"]?.jsonPrimitive?.content ?: ""
                val age = json["age"]?.jsonPrimitive?.intOrNull
                val email = json["email"]?.jsonPrimitive?.contentOrNull
                val skills = json["skills"]?.jsonArray?.mapNotNull { it.jsonPrimitive?.content } ?: emptyList()
                
                com.runanywhere.sdk.models.PersonInfo(
                    name = name,
                    age = age,
                    email = email,
                    skills = skills
                ) as T
            }
            "CodeSnippet" -> {
                val language = json["language"]?.jsonPrimitive?.content ?: ""
                val code = json["code"]?.jsonPrimitive?.content ?: ""
                val description = json["description"]?.jsonPrimitive?.contentOrNull
                val dependencies = json["dependencies"]?.jsonArray?.mapNotNull { it.jsonPrimitive?.content } ?: emptyList()
                
                com.runanywhere.sdk.models.CodeSnippet(
                    language = language,
                    code = code,
                    description = description,
                    dependencies = dependencies
                ) as T
            }
            "AnalysisResult" -> {
                val summary = json["summary"]?.jsonPrimitive?.content ?: ""
                val findingsArray = json["findings"]?.jsonArray ?: JsonArray(emptyList())
                val findings = findingsArray.map { findingElement ->
                    val finding = findingElement.jsonObject
                    com.runanywhere.sdk.models.AnalysisResult.Finding(
                        category = finding["category"]?.jsonPrimitive?.content ?: "",
                        description = finding["description"]?.jsonPrimitive?.content ?: "",
                        severity = finding["severity"]?.jsonPrimitive?.content ?: "low"
                    )
                }
                val recommendations = json["recommendations"]?.jsonArray?.mapNotNull { it.jsonPrimitive?.content } ?: emptyList()
                val confidence = json["confidence"]?.jsonPrimitive?.doubleOrNull
                
                com.runanywhere.sdk.models.AnalysisResult(
                    summary = summary,
                    findings = findings,
                    recommendations = recommendations,
                    confidence = confidence
                ) as T
            }
            "TaskList" -> {
                val title = json["title"]?.jsonPrimitive?.content ?: ""
                val tasksArray = json["tasks"]?.jsonArray ?: JsonArray(emptyList())
                val tasks = tasksArray.map { taskElement ->
                    val task = taskElement.jsonObject
                    com.runanywhere.sdk.models.TaskList.Task(
                        id = task["id"]?.jsonPrimitive?.contentOrNull,
                        title = task["title"]?.jsonPrimitive?.content ?: "",
                        description = task["description"]?.jsonPrimitive?.contentOrNull,
                        priority = task["priority"]?.jsonPrimitive?.content ?: "medium",
                        status = task["status"]?.jsonPrimitive?.content ?: "todo",
                        estimatedHours = task["estimatedHours"]?.jsonPrimitive?.doubleOrNull
                    )
                }
                val dueDate = json["dueDate"]?.jsonPrimitive?.contentOrNull
                
                com.runanywhere.sdk.models.TaskList(
                    title = title,
                    tasks = tasks,
                    dueDate = dueDate
                ) as T
            }
            "JsonResponse" -> {
                val success = json["success"]?.jsonPrimitive?.boolean ?: false
                val data = json["data"]?.jsonObject
                val errorObj = json["error"]?.jsonObject
                val error = errorObj?.let { 
                    com.runanywhere.sdk.models.JsonResponse.ErrorInfo(
                        code = it["code"]?.jsonPrimitive?.content ?: "",
                        message = it["message"]?.jsonPrimitive?.content ?: "",
                        details = it["details"]?.jsonObject
                    )
                }
                val metadata = json["metadata"]?.jsonObject
                
                com.runanywhere.sdk.models.JsonResponse(
                    success = success,
                    data = data,
                    error = error,
                    metadata = metadata
                ) as T
            }
            else -> {
                throw SDKError.StructuredOutputGenerationFailed("Unsupported type: $typeName")
            }
        }
    }
}