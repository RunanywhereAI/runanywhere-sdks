package com.runanywhere.runanywhereai.data.conversation

import android.content.Context
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.encodeToString
import kotlinx.serialization.decodeFromString
import java.io.File

/**
 * Manager for conversation templates
 */
class ConversationTemplateManager(private val context: Context) {
    companion object {
        private const val TEMPLATES_FILE = "conversation_templates.json"
    }

    private val json = Json {
        ignoreUnknownKeys = true
        isLenient = true
        prettyPrint = true
    }

    private val templatesFile: File by lazy {
        File(context.filesDir, TEMPLATES_FILE)
    }

    /**
     * Get all available conversation templates
     */
    suspend fun getAllTemplates(): List<ConversationTemplate> = withContext(Dispatchers.IO) {
        val builtInTemplates = getBuiltInTemplates()
        val customTemplates = loadCustomTemplates()
        builtInTemplates + customTemplates
    }

    /**
     * Get templates by category
     */
    suspend fun getTemplatesByCategory(category: TemplateCategory): List<ConversationTemplate> {
        return getAllTemplates().filter { it.category == category }
    }

    /**
     * Get template by ID
     */
    suspend fun getTemplate(id: String): ConversationTemplate? {
        return getAllTemplates().find { it.id == id }
    }

    /**
     * Save custom template
     */
    suspend fun saveTemplate(template: ConversationTemplate): Boolean = withContext(Dispatchers.IO) {
        try {
            val customTemplates = loadCustomTemplates().toMutableList()
            val existingIndex = customTemplates.indexOfFirst { it.id == template.id }

            if (existingIndex >= 0) {
                customTemplates[existingIndex] = template
            } else {
                customTemplates.add(template)
            }

            saveCustomTemplates(customTemplates)
            true
        } catch (e: Exception) {
            false
        }
    }

    /**
     * Delete custom template
     */
    suspend fun deleteTemplate(templateId: String): Boolean = withContext(Dispatchers.IO) {
        try {
            val customTemplates = loadCustomTemplates().toMutableList()
            val removed = customTemplates.removeAll { it.id == templateId }

            if (removed) {
                saveCustomTemplates(customTemplates)
            }

            removed
        } catch (e: Exception) {
            false
        }
    }

    /**
     * Apply template to create initial conversation state
     */
    fun applyTemplate(template: ConversationTemplate): ConversationFromTemplate {
        val messages = mutableListOf<TemplateMessage>()

        // Add system message if present
        if (template.systemPrompt.isNotEmpty()) {
            messages.add(TemplateMessage(
                role = MessageRole.SYSTEM,
                content = template.systemPrompt,
                isEditable = template.allowSystemPromptEdit
            ))
        }

        // Add initial messages
        messages.addAll(template.initialMessages)

        return ConversationFromTemplate(
            templateId = template.id,
            templateName = template.name,
            messages = messages,
            suggestedFollowUps = template.suggestedFollowUps,
            variables = template.variables.associateWith { "" }, // Initialize empty
            generationOptions = template.defaultGenerationOptions
        )
    }

    /**
     * Replace variables in template content
     */
    fun replaceVariables(content: String, variables: Map<String, String>): String {
        var result = content
        for ((key, value) in variables) {
            result = result.replace("{{$key}}", value)
        }
        return result
    }

    private fun getBuiltInTemplates(): List<ConversationTemplate> {
        return listOf(
            // Coding Assistant Templates
            ConversationTemplate(
                id = "code-review",
                name = "Code Review Assistant",
                description = "Review code for best practices, bugs, and improvements",
                category = TemplateCategory.CODING,
                systemPrompt = """You are an expert code reviewer. Analyze the provided code and provide constructive feedback on:
1. Code quality and best practices
2. Potential bugs or issues
3. Performance improvements
4. Security considerations
5. Readability and maintainability

Be specific in your suggestions and explain the reasoning behind your recommendations.""",
                initialMessages = listOf(
                    TemplateMessage(
                        role = MessageRole.USER,
                        content = "Please review this code:\n\n```{{language}}\n{{code}}\n```",
                        isEditable = true
                    )
                ),
                variables = listOf("language", "code"),
                suggestedFollowUps = listOf(
                    "Can you suggest specific refactoring improvements?",
                    "Are there any security vulnerabilities I should address?",
                    "How can I improve the performance of this code?",
                    "What testing strategies would you recommend?"
                ),
                tags = listOf("code-review", "best-practices", "debugging"),
                isBuiltIn = true
            ),

            ConversationTemplate(
                id = "debug-helper",
                name = "Debugging Assistant",
                description = "Help debug code issues and errors",
                category = TemplateCategory.CODING,
                systemPrompt = """You are a debugging expert. Help the user identify and fix issues in their code. Approach debugging systematically:
1. Understand the problem and expected behavior
2. Analyze the code for logical errors
3. Suggest debugging techniques and tools
4. Provide step-by-step solutions
5. Explain the root cause of issues

Ask clarifying questions when needed and provide clear, actionable advice.""",
                initialMessages = listOf(
                    TemplateMessage(
                        role = MessageRole.USER,
                        content = "I'm having an issue with my {{language}} code. The error is:\n\n```\n{{error}}\n```\n\nHere's the relevant code:\n\n```{{language}}\n{{code}}\n```",
                        isEditable = true
                    )
                ),
                variables = listOf("language", "error", "code"),
                suggestedFollowUps = listOf(
                    "Can you explain why this error occurred?",
                    "What debugging tools would you recommend?",
                    "How can I prevent similar issues in the future?",
                    "Are there any edge cases I should consider?"
                ),
                tags = listOf("debugging", "error-fixing", "troubleshooting"),
                isBuiltIn = true
            ),

            // Writing Assistant Templates
            ConversationTemplate(
                id = "essay-helper",
                name = "Essay Writing Assistant",
                description = "Help structure and improve essay writing",
                category = TemplateCategory.WRITING,
                systemPrompt = """You are an expert writing tutor. Help users improve their essays by:
1. Analyzing structure and flow
2. Suggesting improvements to clarity and coherence
3. Providing feedback on argumentation
4. Helping with grammar and style
5. Offering constructive criticism

Focus on teaching good writing principles and helping users develop their own voice.""",
                initialMessages = listOf(
                    TemplateMessage(
                        role = MessageRole.USER,
                        content = "I need help with my essay on '{{topic}}'. Here's what I have so far:\n\n{{essay_draft}}",
                        isEditable = true
                    )
                ),
                variables = listOf("topic", "essay_draft"),
                suggestedFollowUps = listOf(
                    "How can I make my introduction more engaging?",
                    "Is my thesis statement clear and strong?",
                    "How can I improve the flow between paragraphs?",
                    "What evidence would strengthen my arguments?"
                ),
                tags = listOf("essay", "writing", "academic"),
                isBuiltIn = true
            ),

            // Learning Templates
            ConversationTemplate(
                id = "concept-explainer",
                name = "Concept Explanation",
                description = "Get clear explanations of complex topics",
                category = TemplateCategory.LEARNING,
                systemPrompt = """You are an expert educator. Explain complex concepts in a clear, accessible way:
1. Start with simple, relatable analogies
2. Build up complexity gradually
3. Use examples and visual descriptions
4. Check for understanding
5. Encourage questions

Adapt your explanation style to the user's knowledge level and learning preferences.""",
                initialMessages = listOf(
                    TemplateMessage(
                        role = MessageRole.USER,
                        content = "Can you explain {{concept}} to me? My current knowledge level is {{level}} (beginner/intermediate/advanced).",
                        isEditable = true
                    )
                ),
                variables = listOf("concept", "level"),
                suggestedFollowUps = listOf(
                    "Can you provide a practical example?",
                    "How does this relate to other concepts I might know?",
                    "What are the key takeaways I should remember?",
                    "Where can I learn more about this topic?"
                ),
                tags = listOf("learning", "explanation", "education"),
                isBuiltIn = true
            ),

            // Business Templates
            ConversationTemplate(
                id = "meeting-planner",
                name = "Meeting Planning Assistant",
                description = "Plan effective meetings with agendas and objectives",
                category = TemplateCategory.BUSINESS,
                systemPrompt = """You are an expert meeting facilitator. Help plan productive meetings by:
1. Creating clear objectives and agendas
2. Identifying key participants
3. Suggesting time allocations
4. Recommending preparation materials
5. Planning follow-up actions

Focus on efficiency and achieving meaningful outcomes.""",
                initialMessages = listOf(
                    TemplateMessage(
                        role = MessageRole.USER,
                        content = "I need to plan a meeting about {{topic}}. The meeting is for {{duration}} with {{participants}}. The main goals are: {{goals}}",
                        isEditable = true
                    )
                ),
                variables = listOf("topic", "duration", "participants", "goals"),
                suggestedFollowUps = listOf(
                    "What materials should participants prepare in advance?",
                    "How should I structure the discussion?",
                    "What decision-making process would work best?",
                    "How can I ensure everyone participates effectively?"
                ),
                tags = listOf("meeting", "planning", "business", "productivity"),
                isBuiltIn = true
            ),

            // Creative Templates
            ConversationTemplate(
                id = "story-brainstorm",
                name = "Story Brainstorming",
                description = "Develop creative story ideas and plots",
                category = TemplateCategory.CREATIVE,
                systemPrompt = """You are a creative writing mentor. Help develop compelling stories by:
1. Brainstorming unique plot ideas
2. Developing interesting characters
3. Creating engaging conflicts
4. Building immersive settings
5. Structuring narrative arcs

Encourage creativity while providing practical storytelling advice.""",
                initialMessages = listOf(
                    TemplateMessage(
                        role = MessageRole.USER,
                        content = "I want to write a {{genre}} story. The basic idea is: {{idea}}. I'm particularly interested in exploring themes of {{themes}}.",
                        isEditable = true
                    )
                ),
                variables = listOf("genre", "idea", "themes"),
                suggestedFollowUps = listOf(
                    "How can I make my main character more compelling?",
                    "What conflicts would create the most tension?",
                    "How should I structure the plot for maximum impact?",
                    "What details would make the setting more vivid?"
                ),
                tags = listOf("creative-writing", "storytelling", "brainstorming"),
                isBuiltIn = true
            ),

            // Problem Solving Templates
            ConversationTemplate(
                id = "decision-maker",
                name = "Decision Making Framework",
                description = "Systematic approach to making difficult decisions",
                category = TemplateCategory.PROBLEM_SOLVING,
                systemPrompt = """You are a decision-making coach. Help users make well-informed decisions using structured frameworks:
1. Clarify the decision to be made
2. Identify all viable options
3. Analyze pros and cons systematically
4. Consider potential risks and outcomes
5. Factor in values and priorities

Guide users through logical analysis while respecting their values and circumstances.""",
                initialMessages = listOf(
                    TemplateMessage(
                        role = MessageRole.USER,
                        content = "I need to make a decision about {{decision}}. The main options I'm considering are: {{options}}. The key factors I need to consider are: {{factors}}.",
                        isEditable = true
                    )
                ),
                variables = listOf("decision", "options", "factors"),
                suggestedFollowUps = listOf(
                    "What are the potential risks of each option?",
                    "How do these options align with my long-term goals?",
                    "What additional information should I gather?",
                    "How can I minimize potential negative outcomes?"
                ),
                tags = listOf("decision-making", "analysis", "problem-solving"),
                isBuiltIn = true
            )
        )
    }

    private fun loadCustomTemplates(): List<ConversationTemplate> {
        return try {
            if (templatesFile.exists()) {
                val jsonData = templatesFile.readText()
                json.decodeFromString<List<ConversationTemplate>>(jsonData)
            } else {
                emptyList()
            }
        } catch (e: Exception) {
            emptyList()
        }
    }

    private fun saveCustomTemplates(templates: List<ConversationTemplate>) {
        try {
            val jsonData = json.encodeToString(templates)
            templatesFile.writeText(jsonData)
        } catch (e: Exception) {
            throw e
        }
    }
}

/**
 * Conversation template data class
 */
@Serializable
data class ConversationTemplate(
    val id: String,
    val name: String,
    val description: String,
    val category: TemplateCategory,
    val systemPrompt: String = "",
    val initialMessages: List<TemplateMessage> = emptyList(),
    val variables: List<String> = emptyList(),
    val suggestedFollowUps: List<String> = emptyList(),
    val tags: List<String> = emptyList(),
    val allowSystemPromptEdit: Boolean = false,
    val defaultGenerationOptions: TemplateGenerationOptions? = null,
    val isBuiltIn: Boolean = false,
    val createdAt: Long = System.currentTimeMillis(),
    val updatedAt: Long = System.currentTimeMillis()
)

/**
 * Template message
 */
@Serializable
data class TemplateMessage(
    val role: MessageRole,
    val content: String,
    val isEditable: Boolean = true
)

/**
 * Message roles
 */
@Serializable
enum class MessageRole {
    SYSTEM, USER, ASSISTANT
}

/**
 * Template categories
 */
@Serializable
enum class TemplateCategory(val displayName: String, val description: String) {
    CODING("Coding", "Programming and development assistance"),
    WRITING("Writing", "Writing and editing assistance"),
    LEARNING("Learning", "Educational content and explanations"),
    BUSINESS("Business", "Business and professional tasks"),
    CREATIVE("Creative", "Creative writing and brainstorming"),
    PROBLEM_SOLVING("Problem Solving", "Analysis and decision making"),
    RESEARCH("Research", "Research and information gathering"),
    PERSONAL("Personal", "Personal productivity and planning"),
    CUSTOM("Custom", "User-created templates")
}

/**
 * Template generation options
 */
@Serializable
data class TemplateGenerationOptions(
    val temperature: Float = 0.7f,
    val maxTokens: Int = 500,
    val topP: Float = 0.9f,
    val presencePenalty: Float? = null,
    val frequencyPenalty: Float? = null
)

/**
 * Result of applying a template
 */
data class ConversationFromTemplate(
    val templateId: String,
    val templateName: String,
    val messages: List<TemplateMessage>,
    val suggestedFollowUps: List<String>,
    val variables: Map<String, String>,
    val generationOptions: TemplateGenerationOptions?
)

/**
 * Template search and filtering
 */
data class TemplateFilter(
    val category: TemplateCategory? = null,
    val tags: List<String> = emptyList(),
    val searchQuery: String = "",
    val showOnlyCustom: Boolean = false,
    val showOnlyBuiltIn: Boolean = false
)

/**
 * Extension functions for template operations
 */
fun List<ConversationTemplate>.filterByCategory(category: TemplateCategory): List<ConversationTemplate> {
    return filter { it.category == category }
}

fun List<ConversationTemplate>.filterByTags(tags: List<String>): List<ConversationTemplate> {
    if (tags.isEmpty()) return this
    return filter { template ->
        tags.any { tag ->
            template.tags.any { templateTag ->
                templateTag.equals(tag, ignoreCase = true)
            }
        }
    }
}

fun List<ConversationTemplate>.search(query: String): List<ConversationTemplate> {
    if (query.isBlank()) return this
    val searchQuery = query.lowercase()
    return filter { template ->
        template.name.lowercase().contains(searchQuery) ||
        template.description.lowercase().contains(searchQuery) ||
        template.tags.any { it.lowercase().contains(searchQuery) }
    }
}

fun List<ConversationTemplate>.sortByRelevance(query: String): List<ConversationTemplate> {
    if (query.isBlank()) return sortedBy { it.name }

    val searchQuery = query.lowercase()
    return sortedWith { a, b ->
        val scoreA = calculateRelevanceScore(a, searchQuery)
        val scoreB = calculateRelevanceScore(b, searchQuery)
        scoreB.compareTo(scoreA) // Higher score first
    }
}

private fun calculateRelevanceScore(template: ConversationTemplate, query: String): Int {
    var score = 0

    // Exact name match gets highest score
    if (template.name.lowercase() == query) score += 100
    else if (template.name.lowercase().contains(query)) score += 50

    // Description match
    if (template.description.lowercase().contains(query)) score += 30

    // Tag matches
    template.tags.forEach { tag ->
        if (tag.lowercase() == query) score += 40
        else if (tag.lowercase().contains(query)) score += 20
    }

    // System prompt match (lower priority)
    if (template.systemPrompt.lowercase().contains(query)) score += 10

    return score
}
