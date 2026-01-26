package ai.runanywhere.cli.commands

import com.github.ajalt.clikt.core.CliktCommand
import com.github.ajalt.clikt.core.subcommands
import com.github.ajalt.clikt.parameters.arguments.argument
import com.github.ajalt.clikt.parameters.arguments.optional
import com.github.ajalt.clikt.parameters.options.flag
import com.github.ajalt.clikt.parameters.options.option
import com.github.ajalt.mordant.rendering.TextColors.*
import com.github.ajalt.mordant.terminal.Terminal
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json

/**
 * Models command - manage AI models
 * 
 * Usage:
 *   runanywhere models list
 *   runanywhere models info <model-id>
 *   runanywhere models download <model-id>
 */
class ModelsCommand : CliktCommand(
    name = "models",
    help = "Manage AI models"
) {
    override fun run() {
        // Default action: list models
    }
    
    init {
        subcommands(
            ModelsListCommand(),
            ModelsInfoCommand(),
            ModelsDownloadCommand(),
        )
    }
}

class ModelsListCommand : CliktCommand(
    name = "list",
    help = "List available models"
) {
    private val category by option("--category", "-c", help = "Filter by category (llm, stt, tts)")
    private val downloadedOnly by option("--downloaded", "-d", help = "Show only downloaded models").flag()
    
    override fun run() {
        val terminal = Terminal()
        terminal.println()
        terminal.println(cyan("Available Models"))
        terminal.println(gray("─".repeat(60)))
        
        // Sample model data - in production, this would come from the SDK
        val models = getSampleModels()
            .filter { model ->
                (category == null || model.category.lowercase() == category?.lowercase()) &&
                (!downloadedOnly || model.isDownloaded)
            }
        
        if (models.isEmpty()) {
            terminal.println(yellow("No models found matching criteria"))
            return
        }
        
        // Group by category
        models.groupBy { it.category }.forEach { (cat, categoryModels) ->
            terminal.println()
            terminal.println(white(cat.uppercase()))
            
            categoryModels.forEach { model ->
                val status = if (model.isDownloaded) {
                    green("✓ downloaded")
                } else {
                    gray("○ available")
                }
                
                terminal.println(
                    "  ${cyan(model.id.padEnd(25))} " +
                    "${gray(model.size.padEnd(10))} " +
                    status
                )
            }
        }
        
        terminal.println()
        terminal.println(gray("Use 'runanywhere models info <model-id>' for details"))
    }
}

class ModelsInfoCommand : CliktCommand(
    name = "info",
    help = "Show model details"
) {
    private val modelId by argument("model-id", help = "Model identifier")
    
    override fun run() {
        val terminal = Terminal()
        
        val model = getSampleModels().find { it.id == modelId }
        if (model == null) {
            terminal.println(red("✗ Model not found: $modelId"))
            return
        }
        
        terminal.println()
        terminal.println(cyan("Model: ${model.id}"))
        terminal.println(gray("─".repeat(40)))
        terminal.println("  Name:       ${model.name}")
        terminal.println("  Category:   ${model.category}")
        terminal.println("  Framework:  ${model.framework}")
        terminal.println("  Size:       ${model.size}")
        terminal.println("  Downloaded: ${if (model.isDownloaded) green("Yes") else yellow("No")}")
        terminal.println()
        terminal.println("  ${gray(model.description)}")
        terminal.println()
    }
}

class ModelsDownloadCommand : CliktCommand(
    name = "download",
    help = "Download a model"
) {
    private val modelId by argument("model-id", help = "Model identifier")
    
    override fun run() {
        val terminal = Terminal()
        
        val model = getSampleModels().find { it.id == modelId }
        if (model == null) {
            terminal.println(red("✗ Model not found: $modelId"))
            return
        }
        
        if (model.isDownloaded) {
            terminal.println(yellow("⚠ Model already downloaded: $modelId"))
            return
        }
        
        terminal.println(cyan("Downloading ${model.name}..."))
        terminal.println(gray("  This is a CLI placeholder - actual download happens in mobile apps"))
        terminal.println()
        terminal.println(yellow("To download models on device:"))
        terminal.println("  iOS:     Open RunAnywhereAI app → Settings → Models")
        terminal.println("  Android: Open RunAnywhereAI app → Settings → Models")
    }
}

// Sample model data
@Serializable
data class ModelEntry(
    val id: String,
    val name: String,
    val category: String,
    val framework: String,
    val size: String,
    val description: String,
    val isDownloaded: Boolean = false,
)

private fun getSampleModels() = listOf(
    ModelEntry(
        id = "smollm2-135m",
        name = "SmolLM2 135M",
        category = "LLM",
        framework = "LlamaCPP",
        size = "270 MB",
        description = "Tiny language model for fast inference on mobile devices",
        isDownloaded = true
    ),
    ModelEntry(
        id = "smollm2-360m",
        name = "SmolLM2 360M",
        category = "LLM",
        framework = "LlamaCPP",
        size = "726 MB",
        description = "Small language model with good balance of speed and quality"
    ),
    ModelEntry(
        id = "qwen-0.5b",
        name = "Qwen 0.5B",
        category = "LLM",
        framework = "LlamaCPP",
        size = "1.0 GB",
        description = "Qwen model optimized for mobile with excellent multilingual support"
    ),
    ModelEntry(
        id = "whisper-tiny",
        name = "Whisper Tiny",
        category = "STT",
        framework = "ONNX",
        size = "39 MB",
        description = "Fast speech recognition for real-time transcription",
        isDownloaded = true
    ),
    ModelEntry(
        id = "whisper-base",
        name = "Whisper Base",
        category = "STT",
        framework = "ONNX",
        size = "74 MB",
        description = "Balanced speech recognition model"
    ),
    ModelEntry(
        id = "coqui-tts",
        name = "Coqui TTS",
        category = "TTS",
        framework = "ONNX",
        size = "85 MB",
        description = "Text-to-speech with natural sounding voices"
    ),
)
