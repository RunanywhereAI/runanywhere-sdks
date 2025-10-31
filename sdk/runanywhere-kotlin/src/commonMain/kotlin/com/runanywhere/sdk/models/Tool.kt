package com.runanywhere.sdk.models

import kotlinx.serialization.Serializable

/**
 * Tool parameter type
 */
@Serializable
enum class ToolParameterType {
    STRING,
    NUMBER,
    INTEGER,
    BOOLEAN,
    OBJECT,
    ARRAY;

    fun toJsonSchemaType(): String = when (this) {
        STRING -> "string"
        NUMBER -> "number"
        INTEGER -> "integer"
        BOOLEAN -> "boolean"
        OBJECT -> "object"
        ARRAY -> "array"
    }
}

/**
 * Tool parameter definition
 *
 * @param type Parameter type
 * @param description Human-readable description
 * @param required Whether this parameter is required
 * @param enum Optional list of allowed values
 */
@Serializable
data class ToolParameter(
    val type: ToolParameterType,
    val description: String,
    val required: Boolean = false,
    val enum: List<String>? = null
)

/**
 * Tool parameters schema (JSON Schema compatible)
 *
 * @param type Always "object" for function parameters
 * @param properties Map of parameter name to parameter definition
 * @param required List of required parameter names
 */
@Serializable
data class ToolParametersSchema(
    val type: String = "object",
    val properties: Map<String, ToolParameter>,
    val required: List<String>
)

/**
 * Example of how to use a tool (for few-shot learning)
 *
 * @param userQuery Example user query that would trigger this tool
 * @param arguments Example arguments for the tool call
 */
@Serializable
data class ToolExample(
    val userQuery: String,
    val arguments: Map<String, String>
)

/**
 * Tool definition
 *
 * Represents a function/tool that can be called by the LLM.
 *
 * @param name Unique name for the tool
 * @param description What the tool does
 * @param parameters Schema for tool parameters
 * @param examples Few-shot examples for prompt-based tool calling (optional)
 */
@Serializable
data class Tool(
    val name: String,
    val description: String,
    val parameters: ToolParametersSchema,
    val examples: List<ToolExample> = emptyList()
) {
    /**
     * Convert to JSON schema format for grammar generation
     */
    fun toJsonSchema(): Map<String, Any> {
        return mapOf(
            "type" to "object",
            "properties" to mapOf(
                "name" to mapOf(
                    "const" to name  // Force exact name match
                ),
                "arguments" to mapOf(
                    "type" to "object",
                    "properties" to parameters.properties.mapValues { (_, param) ->
                        val schema = mutableMapOf<String, Any>(
                            "type" to param.type.toJsonSchemaType(),
                            "description" to param.description
                        )
                        param.enum?.let { schema["enum"] = it }
                        schema
                    },
                    "required" to parameters.required
                )
            ),
            "required" to listOf("name", "arguments")
        )
    }

    companion object {
        /**
         * Generate JSON schema for a list of tools
         *
         * Creates a schema for an object with "tool_calls" array containing tool call objects
         */
        fun generateSchema(tools: List<Tool>): Map<String, Any> {
            return mapOf(
                "type" to "object",
                "properties" to mapOf(
                    "tool_calls" to mapOf(
                        "type" to "array",
                        "items" to mapOf(
                            "type" to "object",
                            "properties" to mapOf(
                                "id" to mapOf(
                                    "type" to "string",
                                    "description" to "Unique identifier for this tool call"
                                ),
                                "name" to mapOf(
                                    "type" to "string",
                                    "enum" to tools.map { it.name },  // Only allow defined tool names
                                    "description" to "Name of the tool to call"
                                ),
                                "arguments" to mapOf(
                                    "type" to "object",
                                    "description" to "Arguments for the tool call"
                                )
                            ),
                            "required" to listOf("id", "name", "arguments")
                        )
                    )
                ),
                "required" to listOf("tool_calls")
            )
        }
    }
}

/**
 * Tool call result from LLM
 *
 * @param id Unique identifier for this tool call
 * @param name Tool name to execute
 * @param arguments Map of argument name to value
 */
@Serializable
data class ToolCall(
    val id: String,
    val name: String,
    val arguments: Map<String, String>
)

/**
 * Result of tool calling generation
 *
 * @param success Whether generation succeeded
 * @param text Optional text response before tool calls
 * @param toolCalls List of detected tool calls
 * @param mode Which mode was used (grammar vs prompt)
 * @param metrics Generation performance metrics
 */
data class ToolCallResult(
    val success: Boolean,
    val text: String? = null,
    val toolCalls: List<ToolCall> = emptyList(),
    val mode: ToolCallingMode
)

/**
 * Tool calling mode
 */
enum class ToolCallingMode {
    /** Use grammar-based constrained generation (recommended) */
    GRAMMAR_BASED,

    /** Use prompt engineering (fallback) */
    PROMPT_BASED,

    /** Try grammar, fallback to prompt on error */
    AUTO
}

/**
 * Builder function for creating tools
 */
fun createTool(
    name: String,
    description: String,
    parameters: Map<String, ToolParameter>
): Tool {
    val required = parameters
        .filter { it.value.required }
        .map { it.key }

    return Tool(
        name = name,
        description = description,
        parameters = ToolParametersSchema(
            properties = parameters,
            required = required
        )
    )
}

/**
 * DSL for building tools
 */
class ToolBuilder(private val name: String, private val description: String) {
    private val parameters = mutableMapOf<String, ToolParameter>()

    fun parameter(
        name: String,
        type: ToolParameterType,
        description: String,
        required: Boolean = false,
        enum: List<String>? = null
    ) {
        parameters[name] = ToolParameter(type, description, required, enum)
    }

    fun stringParameter(
        name: String,
        description: String,
        required: Boolean = false,
        enum: List<String>? = null
    ) = parameter(name, ToolParameterType.STRING, description, required, enum)

    fun numberParameter(
        name: String,
        description: String,
        required: Boolean = false
    ) = parameter(name, ToolParameterType.NUMBER, description, required)

    fun intParameter(
        name: String,
        description: String,
        required: Boolean = false
    ) = parameter(name, ToolParameterType.INTEGER, description, required)

    fun boolParameter(
        name: String,
        description: String,
        required: Boolean = false
    ) = parameter(name, ToolParameterType.BOOLEAN, description, required)

    fun build(): Tool = createTool(name, description, parameters)
}

fun tool(name: String, description: String, builder: ToolBuilder.() -> Unit): Tool {
    return ToolBuilder(name, description).apply(builder).build()
}
