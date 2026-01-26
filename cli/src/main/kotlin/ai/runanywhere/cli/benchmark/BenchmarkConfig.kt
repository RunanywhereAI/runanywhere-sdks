package ai.runanywhere.cli.benchmark

import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

/**
 * Benchmark configuration passed to mobile apps
 */
@Serializable
data class BenchmarkConfig(
    val warmupIterations: Int = 3,
    val testIterations: Int = 5,
    val maxTokensList: List<Int> = listOf(50, 100),
    val prompts: List<BenchmarkPrompt> = defaultPrompts(),
) {
    
    fun toJsonArg(): String {
        // Escape for shell usage
        return Json.encodeToString(this)
            .replace("\"", "\\\"")
    }
    
    companion object {
        val QUICK = BenchmarkConfig(
            warmupIterations = 1,
            testIterations = 3,
            maxTokensList = listOf(50),
            prompts = listOf(defaultPrompts().first())
        )
        
        val DEFAULT = BenchmarkConfig()
        
        val COMPREHENSIVE = BenchmarkConfig(
            warmupIterations = 3,
            testIterations = 10,
            maxTokensList = listOf(50, 100, 256),
            prompts = defaultPrompts()
        )
    }
}

@Serializable
data class BenchmarkPrompt(
    val id: String,
    val text: String,
    val category: String,
    val expectedMinTokens: Int,
)

fun defaultPrompts() = listOf(
    BenchmarkPrompt(
        id = "short-1",
        text = "What is 2+2?",
        category = "short",
        expectedMinTokens = 5
    ),
    BenchmarkPrompt(
        id = "medium-1",
        text = "Explain quantum computing in simple terms.",
        category = "medium",
        expectedMinTokens = 50
    ),
    BenchmarkPrompt(
        id = "reasoning-1",
        text = "If a train travels at 60 mph for 2.5 hours, how far does it travel? Show your work.",
        category = "reasoning",
        expectedMinTokens = 30
    )
)
