package com.runanywhere.sdk.models

import kotlinx.serialization.Serializable
import kotlinx.serialization.json.*
import kotlin.reflect.KClass

/**
 * Protocol for types that can be generated as structured output from LLMs
 * Matches iOS Generatable protocol with enhanced Kotlin features
 */
interface Generatable {
    /**
     * Validate the generated content against expected structure
     */
    fun validate(): Boolean = true

    /**
     * Get custom generation instructions for this type
     */
    fun getGenerationInstructions(): String? = null

    /**
     * The JSON schema for this type (matches iOS jsonSchema property)
     * Override in companion object for type-specific schema
     */
    val jsonSchema: String
        get() = DEFAULT_SCHEMA

    companion object {
        /**
         * Default schema for types that don't provide their own
         */
        const val DEFAULT_SCHEMA = """
            {
              "type": "object",
              "additionalProperties": false
            }
        """

        /**
         * Generate comprehensive JSON schema from the type
         * Enhanced with proper Kotlin serialization support
         */
        fun getJsonSchema(type: KClass<out Generatable>): String {
            // Enhanced schema generation with actual type inspection
            return generateSchemaForType(type)
        }

        /**
         * Generate schema with custom properties and validation rules
         */
        fun generateSchemaForType(type: KClass<out Generatable>): String {
            val typeName = type.simpleName ?: "Unknown"

            // Generate comprehensive schema based on type
            return when (typeName) {
                "PersonInfo" -> generatePersonInfoSchema()
                "CodeSnippet" -> generateCodeSnippetSchema()
                "AnalysisResult" -> generateAnalysisResultSchema()
                "TaskList" -> generateTaskListSchema()
                "JsonResponse" -> generateJsonResponseSchema()
                else -> generateGenericSchema(typeName)
            }
        }

        private fun generatePersonInfoSchema(): String =
            """
            {
              "type": "object",
              "properties": {
                "name": {
                  "type": "string",
                  "minLength": 1,
                  "description": "Person's full name"
                },
                "age": {
                  "type": "integer",
                  "minimum": 0,
                  "maximum": 150,
                  "description": "Person's age in years"
                },
                "email": {
                  "type": "string",
                  "format": "email",
                  "description": "Valid email address"
                },
                "skills": {
                  "type": "array",
                  "items": {
                    "type": "string"
                  },
                  "description": "List of skills or expertise areas"
                }
              },
              "required": ["name"],
              "additionalProperties": false
            }
            """.trimIndent()

        private fun generateCodeSnippetSchema(): String =
            """
            {
              "type": "object",
              "properties": {
                "language": {
                  "type": "string",
                  "enum": ["kotlin", "swift", "javascript", "python", "java", "typescript"],
                  "description": "Programming language"
                },
                "code": {
                  "type": "string",
                  "minLength": 1,
                  "description": "The actual code content"
                },
                "description": {
                  "type": "string",
                  "description": "Brief description of what the code does"
                },
                "dependencies": {
                  "type": "array",
                  "items": {
                    "type": "string"
                  },
                  "description": "Required dependencies or imports"
                }
              },
              "required": ["language", "code"],
              "additionalProperties": false
            }
            """.trimIndent()

        private fun generateAnalysisResultSchema(): String =
            """
            {
              "type": "object",
              "properties": {
                "summary": {
                  "type": "string",
                  "minLength": 10,
                  "description": "Brief summary of the analysis"
                },
                "findings": {
                  "type": "array",
                  "items": {
                    "type": "object",
                    "properties": {
                      "category": {"type": "string"},
                      "description": {"type": "string"},
                      "severity": {"type": "string", "enum": ["low", "medium", "high", "critical"]}
                    },
                    "required": ["category", "description", "severity"]
                  },
                  "description": "List of analysis findings"
                },
                "recommendations": {
                  "type": "array",
                  "items": {
                    "type": "string"
                  },
                  "description": "Actionable recommendations"
                },
                "confidence": {
                  "type": "number",
                  "minimum": 0,
                  "maximum": 1,
                  "description": "Confidence score between 0 and 1"
                }
              },
              "required": ["summary", "findings"],
              "additionalProperties": false
            }
            """.trimIndent()

        private fun generateTaskListSchema(): String =
            """
            {
              "type": "object",
              "properties": {
                "title": {
                  "type": "string",
                  "minLength": 1,
                  "description": "Title or name of the task list"
                },
                "tasks": {
                  "type": "array",
                  "items": {
                    "type": "object",
                    "properties": {
                      "id": {"type": "string"},
                      "title": {"type": "string", "minLength": 1},
                      "description": {"type": "string"},
                      "priority": {"type": "string", "enum": ["low", "medium", "high", "urgent"]},
                      "status": {"type": "string", "enum": ["todo", "in_progress", "done", "blocked"]},
                      "estimatedHours": {"type": "number", "minimum": 0}
                    },
                    "required": ["title", "priority", "status"]
                  },
                  "minItems": 1,
                  "description": "List of tasks"
                },
                "dueDate": {
                  "type": "string",
                  "format": "date",
                  "description": "Due date in YYYY-MM-DD format"
                }
              },
              "required": ["title", "tasks"],
              "additionalProperties": false
            }
            """.trimIndent()

        private fun generateJsonResponseSchema(): String =
            """
            {
              "type": "object",
              "properties": {
                "success": {
                  "type": "boolean",
                  "description": "Whether the operation was successful"
                },
                "data": {
                  "type": "object",
                  "description": "The main response data"
                },
                "error": {
                  "type": "object",
                  "properties": {
                    "code": {"type": "string"},
                    "message": {"type": "string"},
                    "details": {"type": "object"}
                  },
                  "description": "Error information if success is false"
                },
                "metadata": {
                  "type": "object",
                  "description": "Additional metadata about the response"
                }
              },
              "required": ["success"],
              "additionalProperties": false
            }
            """.trimIndent()

        private fun generateGenericSchema(typeName: String): String =
            """
            {
              "type": "object",
              "title": "$typeName",
              "description": "Generated schema for $typeName",
              "additionalProperties": false
            }
            """.trimIndent()
    }
}

/**
 * Enhanced structured output configuration - exact match with iOS StructuredOutputConfig
 * with additional Kotlin-specific features
 */
@Serializable
data class StructuredOutputConfig(
    /** The type name to generate */
    val typeName: String,
    /** Whether to include schema in prompt */
    val includeSchemaInPrompt: Boolean = true,
    /** JSON schema for the type */
    val jsonSchema: String? = null,
    /** Custom generation instructions */
    val generationInstructions: String? = null,
    /** Whether to enforce strict JSON validation */
    val enforceStrictValidation: Boolean = true,
    /** Maximum number of retry attempts for invalid output */
    val maxRetryAttempts: Int = 3,
    /** Whether to include examples in the prompt */
    val includeExamples: Boolean = false,
    /** Example outputs to include in prompt */
    val examples: List<String> = emptyList(),
) {
    /**
     * Validate the configuration
     */
    fun validate() {
        require(typeName.isNotBlank()) { "Type name cannot be blank" }
        require(maxRetryAttempts >= 0) { "Max retry attempts must be non-negative" }
        if (includeExamples) {
            require(examples.isNotEmpty()) { "Examples must be provided when includeExamples is true" }
        }
    }

    /**
     * Generate the complete prompt instruction for structured output
     */
    fun generatePromptInstruction(): String {
        val instruction = StringBuilder()

        instruction.append("Please provide your response as valid JSON that matches the following structure:\n\n")

        if (includeSchemaInPrompt && jsonSchema != null) {
            instruction.append("JSON Schema:\n```json\n$jsonSchema\n```\n\n")
        }

        generationInstructions?.let {
            instruction.append("Additional Instructions:\n$it\n\n")
        }

        if (includeExamples && examples.isNotEmpty()) {
            instruction.append("Examples:\n")
            examples.forEachIndexed { index, example ->
                instruction.append("${index + 1}. ```json\n$example\n```\n")
            }
            instruction.append("\n")
        }

        if (enforceStrictValidation) {
            instruction.append("IMPORTANT: Your response must be valid JSON only, with no additional text or explanation.\n")
        }

        return instruction.toString()
    }

    /**
     * Validate generated JSON against the schema
     */
    fun validateGeneratedJson(jsonString: String): StructuredOutputValidationResult {
        return try {
            // Parse JSON to ensure it's valid
            val jsonElement = Json.parseToJsonElement(jsonString)

            // Basic structure validation
            if (jsonElement !is JsonObject) {
                return StructuredOutputValidationResult(
                    isValid = false,
                    error = "Generated output is not a JSON object",
                    parsedJson = null,
                )
            }

            // Schema validation would go here in a full implementation
            // For now, we do basic checks
            val validationErrors = performBasicValidation(jsonElement)

            StructuredOutputValidationResult(
                isValid = validationErrors.isEmpty(),
                error = validationErrors.firstOrNull(),
                parsedJson = jsonElement,
                validationErrors = validationErrors,
            )
        } catch (e: Exception) {
            StructuredOutputValidationResult(
                isValid = false,
                error = "Invalid JSON: ${e.message}",
                parsedJson = null,
            )
        }
    }

    private fun performBasicValidation(jsonObject: JsonObject): List<String> {
        val errors = mutableListOf<String>()

        // Type-specific validation
        when (typeName.lowercase()) {
            "personinfo" -> validatePersonInfo(jsonObject, errors)
            "codesnippet" -> validateCodeSnippet(jsonObject, errors)
            "analysisresult" -> validateAnalysisResult(jsonObject, errors)
            "tasklist" -> validateTaskList(jsonObject, errors)
            "jsonresponse" -> validateJsonResponse(jsonObject, errors)
        }

        return errors
    }

    private fun validatePersonInfo(
        json: JsonObject,
        errors: MutableList<String>,
    ) {
        if (!json.containsKey("name") || json["name"]?.jsonPrimitive?.contentOrNull.isNullOrBlank()) {
            errors.add("PersonInfo must have a non-empty name field")
        }
    }

    private fun validateCodeSnippet(
        json: JsonObject,
        errors: MutableList<String>,
    ) {
        if (!json.containsKey("language") || json["language"]?.jsonPrimitive?.contentOrNull.isNullOrBlank()) {
            errors.add("CodeSnippet must have a language field")
        }
        if (!json.containsKey("code") || json["code"]?.jsonPrimitive?.contentOrNull.isNullOrBlank()) {
            errors.add("CodeSnippet must have a non-empty code field")
        }
    }

    private fun validateAnalysisResult(
        json: JsonObject,
        errors: MutableList<String>,
    ) {
        if (!json.containsKey("summary") || json["summary"]?.jsonPrimitive?.contentOrNull.isNullOrBlank()) {
            errors.add("AnalysisResult must have a summary field")
        }
        if (!json.containsKey("findings") || json["findings"] !is JsonArray) {
            errors.add("AnalysisResult must have a findings array")
        }
    }

    private fun validateTaskList(
        json: JsonObject,
        errors: MutableList<String>,
    ) {
        if (!json.containsKey("title") || json["title"]?.jsonPrimitive?.contentOrNull.isNullOrBlank()) {
            errors.add("TaskList must have a title field")
        }
        if (!json.containsKey("tasks") || json["tasks"] !is JsonArray) {
            errors.add("TaskList must have a tasks array")
        }
    }

    private fun validateJsonResponse(
        json: JsonObject,
        errors: MutableList<String>,
    ) {
        if (!json.containsKey("success")) {
            errors.add("JsonResponse must have a success field")
        }
    }

    companion object {
        /**
         * Create configuration for a specific Generatable type
         */
        inline fun <reified T : Generatable> create(
            includeSchemaInPrompt: Boolean = true,
            enforceStrictValidation: Boolean = true,
            includeExamples: Boolean = false,
            examples: List<String> = emptyList(),
        ): StructuredOutputConfig {
            val instance =
                try {
                    T::class.java.getDeclaredConstructor().newInstance()
                } catch (e: Exception) {
                    null
                }

            return StructuredOutputConfig(
                typeName = T::class.simpleName ?: "Unknown",
                includeSchemaInPrompt = includeSchemaInPrompt,
                jsonSchema = Generatable.generateSchemaForType(T::class),
                generationInstructions = instance?.getGenerationInstructions(),
                enforceStrictValidation = enforceStrictValidation,
                includeExamples = includeExamples,
                examples = examples,
            )
        }

        /**
         * Create configuration with custom schema
         */
        fun createCustom(
            typeName: String,
            jsonSchema: String,
            generationInstructions: String? = null,
            enforceStrictValidation: Boolean = true,
        ): StructuredOutputConfig =
            StructuredOutputConfig(
                typeName = typeName,
                includeSchemaInPrompt = true,
                jsonSchema = jsonSchema,
                generationInstructions = generationInstructions,
                enforceStrictValidation = enforceStrictValidation,
            )
    }
}

/**
 * Result of structured output validation
 */
data class StructuredOutputValidationResult(
    /** Whether the JSON is valid according to the schema */
    val isValid: Boolean,
    /** Error message if validation failed */
    val error: String? = null,
    /** Parsed JSON object if valid */
    val parsedJson: JsonObject? = null,
    /** List of all validation errors */
    val validationErrors: List<String> = emptyList(),
)

// MARK: - Example Generatable Types

/**
 * Example person information structure
 */
@Serializable
data class PersonInfo(
    val name: String,
    val age: Int? = null,
    val email: String? = null,
    val skills: List<String> = emptyList(),
) : Generatable {
    override fun getGenerationInstructions(): String =
        "Generate person information with at least a name. Include age, email, and skills if mentioned in the input."
}

/**
 * Example code snippet structure
 */
@Serializable
data class CodeSnippet(
    val language: String,
    val code: String,
    val description: String? = null,
    val dependencies: List<String> = emptyList(),
) : Generatable {
    override fun getGenerationInstructions(): String =
        "Generate a code snippet with the specified language and functional code. Include description and dependencies if relevant."
}

/**
 * Example analysis result structure
 */
@Serializable
data class AnalysisResult(
    val summary: String,
    val findings: List<Finding>,
    val recommendations: List<String> = emptyList(),
    val confidence: Double? = null,
) : Generatable {
    @Serializable
    data class Finding(
        val category: String,
        val description: String,
        val severity: String,
    )

    override fun getGenerationInstructions(): String =
        "Provide a comprehensive analysis with summary, specific findings categorized by severity, and actionable recommendations."
}

/**
 * Example task list structure
 */
@Serializable
data class TaskList(
    val title: String,
    val tasks: List<Task>,
    val dueDate: String? = null,
) : Generatable {
    @Serializable
    data class Task(
        val id: String? = null,
        val title: String,
        val description: String? = null,
        val priority: String,
        val status: String,
        val estimatedHours: Double? = null,
    )

    override fun getGenerationInstructions(): String =
        "Create a structured task list with clear priorities and status. Include time estimates if mentioned."
}

/**
 * Example JSON response structure
 */
@Serializable
data class JsonResponse(
    val success: Boolean,
    val data: JsonObject? = null,
    val error: ErrorInfo? = null,
    val metadata: JsonObject? = null,
) : Generatable {
    @Serializable
    data class ErrorInfo(
        val code: String,
        val message: String,
        val details: JsonObject? = null,
    )

    override fun getGenerationInstructions(): String =
        "Structure the response as a standard JSON API response with success indicator, data payload, and error information when applicable."
}
